const { json, parseJsonBody, requireMethod, supabaseFetch } = require("./_membership");

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
  return raw.replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "").slice(0, 60) || "general";
}

function recommendationKind(candidate = {}, pattern = {}) {
  return cleanText(candidate.kind || candidate.recommendation_kind || pattern.recommendation_kind || "preventive_block", 80);
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
  };
}

function bestMicro(rows = []) {
  const row = rows.find((item) => ["accepted", "completed", "held"].includes(item.outcome));
  if (!row) return null;
  return {
    value: row.proposed_value || {},
    outcome: row.outcome,
    outcome_score: row.outcome_score,
    last_seen_at: row.created_at,
  };
}

function decide({ macro, micro, fallback }) {
  if (micro) {
    return {
      decision_source: "micro",
      final_recommendation: micro.value,
      reason: "This user's own history contradicts or refines the segment pattern, so personal evidence wins.",
      confidence: cleanNumber(micro.outcome_score, 72, 0, 100) || 72,
    };
  }
  if (macro) {
    const confidence = Math.min(85, Math.max(35, Math.round(macro.positive_rate * 0.7 + Math.min(macro.sample_size, 50) * 0.3)));
    return {
      decision_source: "macro",
      final_recommendation: macro.value,
      reason: "No stronger personal pattern exists yet, so Blanked starts from the best matching segment pattern.",
      confidence,
    };
  }
  return {
    decision_source: "fallback",
    final_recommendation: fallback,
    reason: "There is not enough global or personal evidence yet.",
    confidence: 20,
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

    const [macroRows, microRows] = await Promise.all([
      supabaseFetch(`bai_global_plan_patterns?segment_key=eq.${encodeURIComponent(segment)}&pattern_key=eq.${encodeURIComponent(pattern)}&recommendation_kind=eq.${encodeURIComponent(kind)}&select=*&order=positive_rate.desc,sample_size.desc&limit=5`, { method: "GET" }),
      supabaseFetch(`bai_user_plan_preferences?anonymous_user_id=eq.${encodeURIComponent(anonymousUserId)}&pattern_key=eq.${encodeURIComponent(pattern)}&recommendation_kind=eq.${encodeURIComponent(kind)}&select=*&limit=5`, { method: "GET" }),
    ]);

    const macro = bestMacro(macroRows);
    const micro = bestMicro(microRows);
    const decision = decide({ macro, micro, fallback });
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
    });
  } catch (error) {
    return json(500, { error: "bai_intelligence_failed", detail: error.message });
  }
};

module.exports = {
  ageBand,
  candidateValue,
  decide,
  patternKey,
  recommendationKind,
  segmentKey,
  handler: exports.handler,
};
