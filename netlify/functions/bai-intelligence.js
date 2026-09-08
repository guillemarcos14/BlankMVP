const crypto = require("crypto");
const { json, parseJsonBody, requireMethod, supabaseFetch } = require("./_membership");

const TAXONOMY = {
  patterns: new Set(["sleep_night_scroll", "lunch_scroll", "work_focus", "study_focus", "social_scroll", "general"]),
  recommendationKinds: new Set(["sleep_boundary", "preventive_block", "daily_limit", "allow_only", "recovery_mode", "source_connect", "other"]),
};

const OUTCOME_WEIGHTS = {
  generated: 0,
  accepted: 12,
  completed: 24,
  held: 30,
  ignored: -8,
  dismissed: -10,
  failed: -18,
  broke: -30,
};

function cleanText(value, maxLength = 240) {
  return String(value || "").trim().replace(/\s+/g, " ").slice(0, maxLength);
}

function cleanNumber(value, fallback = null, min = Number.NEGATIVE_INFINITY, max = Number.POSITIVE_INFINITY) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(max, Math.max(min, Math.round(number)));
}

function ageBand(age) {
  const value = cleanNumber(age, null, 13, 100);
  if (value == null) return "age_unknown";
  if (value < 18) return "age_u18";
  if (value < 25) return "age_18_24";
  if (value < 35) return "age_25_34";
  if (value < 45) return "age_35_44";
  if (value < 55) return "age_45_54";
  return "age_55_plus";
}

function normalizeGender(value) {
  const text = cleanText(value, 40).toLowerCase();
  if (["female", "woman", "women", "f", "mujer"].includes(text)) return "female";
  if (["male", "man", "men", "m", "hombre"].includes(text)) return "male";
  if (text) return "other";
  return "gender_unknown";
}

function segmentKey(profile = {}) {
  const goal = cleanText(profile.goal || profile.motivation_cluster || "goal_unknown", 40).toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "") || "goal_unknown";
  return [ageBand(profile.age), `gender_${normalizeGender(profile.gender)}`, `goal_${goal}`].join("|");
}

function patternKey(pattern = {}, prompt = "") {
  const raw = cleanText(pattern.key || pattern.pattern_key || pattern.type || prompt, 80).toLowerCase();
  if (/(sleep|bed|night|dormir|noche)/.test(raw)) return "sleep_night_scroll";
  if (/(lunch|comida|comer|almuerzo)/.test(raw)) return "lunch_scroll";
  if (/(work|trabaj|focus|foco)/.test(raw)) return "work_focus";
  if (/(study|estudi|exam|opos)/.test(raw)) return "study_focus";
  if (/(social|scroll|tiktok|instagram|youtube|reddit|reels|shorts)/.test(raw)) return "social_scroll";
  const normalized = raw.replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "").slice(0, 60) || "general";
  return TAXONOMY.patterns.has(normalized) ? normalized : "general";
}

function recommendationKind(candidate = {}, pattern = {}) {
  const kind = cleanText(candidate.kind || candidate.recommendation_kind || pattern.recommendation_kind || "preventive_block", 80);
  return TAXONOMY.recommendationKinds.has(kind) ? kind : "other";
}

function candidateValue(candidate = {}) {
  return {
    ...((candidate.value && typeof candidate.value === "object") ? candidate.value : {}),
    ...((candidate.start_minute ?? candidate.proposed_start_minute) != null ? { start_minute: cleanNumber(candidate.start_minute ?? candidate.proposed_start_minute, null, 0, 1439) } : {}),
    ...((candidate.end_minute ?? candidate.proposed_end_minute) != null ? { end_minute: cleanNumber(candidate.end_minute ?? candidate.proposed_end_minute, null, 0, 1439) } : {}),
    ...(candidate.minutes_before_target != null ? { minutes_before_target: cleanNumber(candidate.minutes_before_target, null, 0, 240) } : {}),
    ...(candidate.duration_days != null ? { duration_days: cleanNumber(candidate.duration_days, null, 1, 30) } : {}),
  };
}

function bestMacro(rows = []) {
  const ranked = rows
    .filter((row) => cleanNumber(row.sample_size, 0, 0) > 0)
    .sort((left, right) => {
      const leftRate = Number(left.positive_rate || 0);
      const rightRate = Number(right.positive_rate || 0);
      if (rightRate !== leftRate) return rightRate - leftRate;
      return Number(right.sample_size || 0) - Number(left.sample_size || 0);
    });
  const row = ranked[0];
  if (!row) return null;
  return {
    value: row.proposed_value || {},
    positive_rate: Number(row.positive_rate || 0),
    sample_size: Number(row.sample_size || 0),
    positive_count: Number(row.positive_count || 0),
    negative_count: Number(row.negative_count || 0),
    evidence_score: macroEvidenceScore(row),
    confidence: macroConfidence(row),
  };
}

function bestMicro(rows = []) {
  const ranked = microCandidates(rows);
  const row = ranked[0];
  if (!row || row.evidence_score <= 0) return null;
  return {
    value: row.proposed_value || {},
    outcome: row.latest_outcome,
    outcome_score: row.outcome_score,
    evidence_score: row.evidence_score,
    confidence: row.confidence,
    sample_size: row.sample_size,
    last_seen_at: row.last_seen_at,
  };
}

function valueSignature(value = {}) {
  return JSON.stringify(Object.keys(value || {}).sort().reduce((result, key) => {
    result[key] = value[key];
    return result;
  }, {}));
}

function valuesDiffer(left = {}, right = {}) {
  return valueSignature(left) !== valueSignature(right);
}

function macroEvidenceScore(row = {}) {
  const sample = cleanNumber(row.sample_size, 0, 0, 100000);
  const rate = Number(row.positive_rate || 0) / 100;
  const negative = cleanNumber(row.negative_count, 0, 0, 100000);
  const sampleConfidence = 1 - Math.exp(-sample / 30);
  const penalty = Math.min(0.35, negative / Math.max(sample, 1) * 0.4);
  return Math.round(100 * Math.max(0, rate - penalty) * sampleConfidence);
}

function macroConfidence(row = {}) {
  const score = macroEvidenceScore(row);
  const sample = cleanNumber(row.sample_size, 0, 0, 100000);
  return Math.min(88, Math.max(25, Math.round(score * 0.75 + Math.min(sample, 80) * 0.25)));
}

function microCandidates(rows = []) {
  const groups = new Map();
  rows.forEach((row, index) => {
    const proposed = row.proposed_value || {};
    const signature = valueSignature(proposed);
    const current = groups.get(signature) || {
      proposed_value: proposed,
      evidence_score: 0,
      sample_size: 0,
      latest_outcome: "",
      last_seen_at: "",
    };
    const decay = Math.pow(0.86, index);
    const explicitScore = row.outcome_score == null ? null : cleanNumber(row.outcome_score, null, -100, 100);
    const baseWeight = OUTCOME_WEIGHTS[row.outcome] ?? 0;
    const score = explicitScore == null ? baseWeight : baseWeight + explicitScore / 8;
    current.evidence_score += score * decay;
    current.sample_size += 1;
    if (!current.last_seen_at || String(row.created_at || "") > current.last_seen_at) {
      current.latest_outcome = row.outcome;
      current.last_seen_at = row.created_at;
      current.outcome_score = row.outcome_score;
    }
    groups.set(signature, current);
  });
  return Array.from(groups.values())
    .map((item) => ({
      ...item,
      evidence_score: Math.round(item.evidence_score),
      confidence: Math.min(94, Math.max(20, Math.round(35 + Math.abs(item.evidence_score) * 1.7 + item.sample_size * 7))),
    }))
    .sort((left, right) => {
      if (right.evidence_score !== left.evidence_score) return right.evidence_score - left.evidence_score;
      return String(right.last_seen_at || "").localeCompare(String(left.last_seen_at || ""));
    });
}

function stableBucket(seed) {
  const digest = crypto.createHash("sha256").update(seed).digest("hex").slice(0, 8);
  return parseInt(digest, 16) / 0xffffffff;
}

function explorationVariant(fallback = {}, seed = "") {
  const value = { ...(fallback || {}) };
  const minutes = cleanNumber(value.minutes_before_target, null, 0, 240);
  if (minutes != null) {
    const alternatives = minutes >= 40 ? [30, 20] : [45, 20];
    const chosen = alternatives[Math.floor(stableBucket(`${seed}:minutes`) * alternatives.length)];
    const delta = chosen - minutes;
    return {
      ...value,
      minutes_before_target: chosen,
      ...(value.start_minute != null ? { start_minute: (((value.start_minute - delta) % 1440) + 1440) % 1440 } : {}),
    };
  }
  if (value.duration_days != null) {
    return { ...value, duration_days: value.duration_days >= 7 ? 3 : 7 };
  }
  return value;
}

function shouldExplore({ macro, micro, explorationRate = 0, seed = "" }) {
  if (micro && micro.confidence >= 65) return false;
  if (macro && macro.confidence >= 75) return false;
  const rate = Math.min(0.25, Math.max(0, Number(explorationRate) || 0));
  return rate > 0 && stableBucket(seed) < rate;
}

function decide({ macro, micro, fallback, explorationRate = 0, seed = "" }) {
  const contradiction = Boolean(macro && micro && valuesDiffer(macro.value, micro.value));
  if (micro && (micro.confidence >= 55 || contradiction)) {
    return {
      decision_source: "micro",
      final_recommendation: micro.value,
      reason: "This user's own history contradicts or refines the segment pattern, so personal evidence wins.",
      confidence: micro.confidence,
      evidence: { macro, micro, contradiction, exploration: false },
    };
  }
  if (shouldExplore({ macro, micro, explorationRate, seed })) {
    return {
      decision_source: "experiment",
      final_recommendation: explorationVariant(fallback, seed),
      reason: "Evidence is not strong enough yet, so Blanked tests a bounded variation to learn faster.",
      confidence: Math.max(20, Math.min(55, macro?.confidence || 35)),
      evidence: { macro, micro, contradiction, exploration: true },
    };
  }
  if (macro) {
    return {
      decision_source: "macro",
      final_recommendation: macro.value,
      reason: "No stronger personal pattern exists yet, so Blanked starts from the best matching segment pattern.",
      confidence: macro.confidence,
      evidence: { macro, micro, contradiction, exploration: false },
    };
  }
  return {
    decision_source: "fallback",
    final_recommendation: fallback,
    reason: "There is not enough global or personal evidence yet.",
    confidence: 20,
    evidence: { macro, micro, contradiction: false, exploration: false },
  };
}

async function insertDecision(record) {
  try {
    await supabaseFetch("bai_recommendation_decisions", {
      method: "POST",
      headers: { prefer: "return=minimal" },
      body: JSON.stringify(record),
    });
  } catch (_) {
    // Intelligence should still answer if analytics persistence is not deployed yet.
  }
}

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;
  try {
    const body = parseJsonBody(event);
    const anonymousUserId = cleanText(body.anonymous_user_id, 120);
    if (!anonymousUserId) return json(400, { error: "missing_anonymous_user_id" });
    if (body.data_consent !== true) return json(403, { error: "data_consent_required" });

    const segment = segmentKey(body.profile || {});
    const pattern = patternKey(body.pattern || {}, body.prompt || "");
    const kind = recommendationKind(body.candidate_recommendation || {}, body.pattern || {});
    const fallback = candidateValue(body.candidate_recommendation || {});
    const explorationRate = body.exploration_enabled === true ? cleanNumber(body.exploration_rate, 0.08, 0, 0.25) : 0;
    const seed = `${anonymousUserId}|${segment}|${pattern}|${kind}`;

    const [macroRows, microRows] = await Promise.all([
      supabaseFetch(`bai_global_plan_patterns?segment_key=eq.${encodeURIComponent(segment)}&pattern_key=eq.${encodeURIComponent(pattern)}&recommendation_kind=eq.${encodeURIComponent(kind)}&select=*&order=positive_rate.desc,sample_size.desc&limit=5`, { method: "GET" }),
      supabaseFetch(`bai_user_plan_outcomes?anonymous_user_id=eq.${encodeURIComponent(anonymousUserId)}&pattern_key=eq.${encodeURIComponent(pattern)}&recommendation_kind=eq.${encodeURIComponent(kind)}&select=*&order=created_at.desc&limit=30`, { method: "GET" }),
    ]);

    const macro = bestMacro(macroRows);
    const micro = bestMicro(microRows);
    const decision = decide({ macro, micro, fallback, explorationRate, seed });
    const record = {
      anonymous_user_id: anonymousUserId,
      segment_key: segment,
      pattern_key: pattern,
      recommendation_kind: kind,
      macro_recommendation: macro || {},
      micro_recommendation: micro || {},
      final_recommendation: decision.final_recommendation,
      decision_source: decision.decision_source,
      reason: decision.reason,
      confidence: decision.confidence,
      evidence: decision.evidence,
    };
    await insertDecision(record);

    return json(200, {
      ok: true,
      segment_key: segment,
      pattern_key: pattern,
      recommendation_kind: kind,
      macro_recommendation: macro,
      micro_recommendation: micro,
      final_recommendation: decision.final_recommendation,
      decision_source: decision.decision_source,
      reason: decision.reason,
      confidence: decision.confidence,
      evidence: decision.evidence,
    });
  } catch (error) {
    return json(500, { error: "bai_intelligence_failed", detail: error.message });
  }
};

module.exports = {
  ageBand,
  bestMacro,
  bestMicro,
  candidateValue,
  decide,
  explorationVariant,
  macroConfidence,
  macroEvidenceScore,
  microCandidates,
  patternKey,
  recommendationKind,
  segmentKey,
  handler: exports.handler,
};
