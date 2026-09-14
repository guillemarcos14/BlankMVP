const crypto = require("crypto");
const {
  json,
  parseJsonBody,
  requireMethod,
  supabaseFetch,
} = require("./_membership");
const {
  decide: decidePlanIntelligence,
  bestMacro: bestMacroEvidence,
  bestMicro: bestMicroEvidence,
  candidateValue,
  patternKey: intelligencePatternKey,
  recommendationKind,
  segmentKey,
} = require("./bai-intelligence");
const {
  resolveWearableSources,
  wearableDecisionContext,
} = require("./_wearable_intelligence");

function cleanText(value, maxLength = 240) {
  return String(value || "").trim().slice(0, maxLength);
}

function cleanNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function cleanBoolean(value) {
  return value === true ? true : value === false ? false : null;
}

function recommendationId(anonymousUserId, payload, insight) {
  const { pattern, kind } = recommendationKeys(payload, insight);
  const source = [anonymousUserId, payload.period_start, payload.period_end, pattern, kind].join("|");
  return `dw_${crypto.createHash("sha256").update(source).digest("hex").slice(0, 24)}`;
}

function recommendationKeys(payload, insight) {
  const candidate = planUpdateCandidate(insight?.plan_update || {});
  return {
    pattern: intelligencePatternKey({ key: candidate.kind }, `${insight?.plan_update?.title || ""} ${insight?.plan_update?.evidence || ""}`),
    kind: recommendationKind(candidate),
  };
}

async function persistGeneratedOutcome(anonymousUserId, payload, insight, id) {
  try {
    const { pattern, kind } = recommendationKeys(payload, insight);
    await supabaseFetch("bai_user_plan_outcomes", {
      method: "POST",
      headers: { prefer: "resolution=ignore-duplicates,return=minimal" },
      body: JSON.stringify({
        anonymous_user_id: anonymousUserId,
        segment_key: segmentKey(payload.profile || {}),
        pattern_key: pattern,
        recommendation_kind: kind,
        recommendation_id: id,
        proposed_value: candidateValue(insight?.plan_update || {}),
        outcome: "generated",
        outcome_score: 0,
        metadata: {
          generated_key: id,
          source: "digital_wellness_features",
          risk_score: insight?.behavior_forecast?.risk_score || null,
          forecast_window: insight?.behavior_forecast?.window || null,
          experiment: insight?.experiment?.name || null,
        },
      }),
    });
  } catch (error) {
    console.warn("bai_generated_outcome_skipped", error.message);
  }
}

function requireSafePrivacy(payload) {
  const privacy = payload?.privacy || {};
  const blocked = [
    privacy.raw_health_samples_sent,
    privacy.raw_sleep_stage_timestamps_sent,
    privacy.exact_app_selection_sent,
    privacy.exact_location_sent,
  ].some((value) => value === true);

  if (blocked) {
    throw new Error("raw_or_sensitive_payload_rejected");
  }
}

function compactPayload(payload) {
  return {
    schema_version: cleanNumber(payload.schema_version),
    generated_at: payload.generated_at,
    period_start: payload.period_start,
    period_end: payload.period_end,
    common_features: cleanFeatureMap(payload.common_features),
    provider_features: cleanProviderFeatures(payload.provider_features),
    source_confidence: cleanFeatureMap(payload.source_confidence),
    freshness: cleanFeatureMap(payload.freshness),
    profile: payload.profile || {},
    daily: Array.isArray(payload.daily) ? payload.daily.slice(-14) : [],
    weekly: payload.weekly || {},
    correlations: payload.correlations || {},
    privacy: payload.privacy || {},
  };
}

function cleanFeatureMap(value) {
  const source = value && typeof value === "object" && !Array.isArray(value) ? value : {};
  return Object.fromEntries(
    Object.entries(source)
      .slice(0, 30)
      .map(([key, rawValue]) => [cleanText(key, 64), cleanText(rawValue, 160)])
      .filter(([key, rawValue]) => key && rawValue)
  );
}

function cleanProviderFeatures(value) {
  const source = value && typeof value === "object" && !Array.isArray(value) ? value : {};
  return Object.fromEntries(
    Object.entries(source)
      .slice(0, 10)
      .map(([provider, features]) => [cleanText(provider, 64), cleanFeatureMap(features)])
      .filter(([provider, features]) => provider && Object.keys(features).length)
  );
}

function hourWindow(hour) {
  if (!Number.isFinite(Number(hour))) return null;
  const start = Number(hour);
  const end = (start + 2) % 24;
  return `${clockTimeText(start)} to ${clockTimeText(end)}`;
}

function clockTimeText(hour, minute = 0) {
  const safeHour = ((Number(hour) % 24) + 24) % 24;
  const safeMinute = Math.min(59, Math.max(0, Number(minute) || 0));
  const displayHour = safeHour % 12 === 0 ? 12 : safeHour % 12;
  const meridiem = safeHour < 12 ? "AM" : "PM";
  return `${displayHour}:${String(safeMinute).padStart(2, "0")} ${meridiem}`;
}

function buildInsight(payload, memory = {}) {
  const weekly = payload.weekly || {};
  const correlations = payload.correlations || {};
  const profile = payload.profile || {};
  const common = payload.common_features || {};
  const resolvedWearable = payload.resolved_wearable || {};
  const resolvedCommon = resolvedWearable.common_features || common;
  const wearableDecision = payload.wearable_decision_context || {};
  const freshness = payload.freshness || {};
  const sourceConfidence = payload.source_confidence || {};
  const wellnessSignals = payload.wellness_signals || {};
  const unlockPressure = cleanNumber(weekly.unlock_pressure_score) || cleanNumber(weekly.pickup_pressure_score) || 0;
  const appSequence = cleanText(weekly.dominant_app_sequence || weekly.behavior_chain || "", 120);
  const sequenceRisk = cleanText(weekly.app_sequence_risk || weekly.sequence_risk || "", 40);
  const recentCheckIn = wellnessSignals.latest_check_in || {};
  const recommendations = [];
  const patterns = [];

  if (weekly.blocked_minutes > 0) {
    patterns.push(`${weekly.blocked_minutes} protected minutes across ${weekly.blocks_completed || 0} completed blocks.`);
  } else {
    patterns.push("Not enough completed blocks yet; start with one protected window this week.");
  }

  if (weekly.avg_sleep_minutes) {
    patterns.push(`Average sleep signal is ${Math.round(weekly.avg_sleep_minutes / 60 * 10) / 10}h.`);
  }

  if (weekly.avg_steps) {
    patterns.push(`Average activity signal is ${weekly.avg_steps} steps.`);
  }

  if (weekly.avg_recovery_score) {
    patterns.push(`Recovery context is ${weekly.avg_recovery_score}/100 across ${weekly.health_days_count || 0} Health days.`);
  } else if (weekly.avg_hrv || weekly.avg_resting_hr) {
    patterns.push(`Wearable recovery signals include HRV ${weekly.avg_hrv || "learning"} and resting HR ${weekly.avg_resting_hr || "learning"}.`);
  }

  if ((weekly.health_signal_coverage_percent || 0) > 0 && weekly.health_signal_coverage_percent < 45) {
    recommendations.push("Sync your wearable daily so Blanked can separate recovery dips from normal screen urges.");
  }

  if (resolvedWearable.data_quality?.status) {
    patterns.push(`Best wearable context is ${resolvedWearable.data_quality.status} with ${resolvedWearable.data_quality.confidence || 0}/100 confidence.`);
  } else if (common.confidence || sourceConfidence.apple_health || sourceConfidence.health_connect) {
    patterns.push(`Wearable confidence is ${common.confidence || sourceConfidence.apple_health || sourceConfidence.health_connect}/100 with ${freshness.status || "unknown"} freshness.`);
  }

  if (unlockPressure >= 65) {
    patterns.push(`Pickup pressure is elevated at ${unlockPressure}/100, so short checks are becoming a risk signal.`);
    recommendations.push("Intervene before the second quick check, not after the full scroll session starts.");
  }

  if (appSequence) {
    patterns.push(`Dominant behavior chain is ${appSequence}${sequenceRisk ? ` with ${sequenceRisk} risk` : ""}.`);
    if (/high|medium/i.test(sequenceRisk)) {
      recommendations.push("Protect the second step of the chain so harmless checks do not become scroll sessions.");
    }
  }

  const weakWindow = weekly.worst_focus_window || hourWindow(weekly.weakest_hour);
  if (weakWindow) {
    recommendations.push(`Protect ${weakWindow} before opening high-friction apps.`);
  }

  if ((weekly.plan_adherence_percent || 0) < 60) {
    recommendations.push("Lower the next block length and repeat the same window for cleaner learning.");
  } else {
    recommendations.push("Keep the current plan stable for one more week.");
  }

  if (
    correlations.relapses_after_short_sleep > 0 ||
    correlations.screen_risk_after_bad_sleep === "high" ||
    (weekly.avg_recovery_score && weekly.avg_recovery_score < 45) ||
    wearableDecision.flags?.includes("low_recovery") ||
    wearableDecision.flags?.includes("short_sleep")
  ) {
    recommendations.push("Use a lighter block after short sleep instead of relying on willpower.");
  }

  if (wearableDecision.flags?.includes("high_strain")) {
    recommendations.push("Avoid adding friction everywhere today; protect only the highest-risk window.");
  }

  if (wearableDecision.flags?.includes("stale_signals")) {
    recommendations.push("Sync your wearable before changing the plan intensity.");
  }

  if (wellnessSignals.latest_weather?.value_text) {
    patterns.push(`Weather context is ${wellnessSignals.latest_weather.value_text}.`);
  }

  if (wellnessSignals.latest_check_in?.signal_type) {
    patterns.push(`Latest check-in is ${wellnessSignals.latest_check_in.signal_type} ${wellnessSignals.latest_check_in.value_number || ""}.`.replace(/\s+\./, "."));
  }

  if (["stress", "energy", "mood"].includes(recentCheckIn.signal_type) && Number(recentCheckIn.value_number) <= 4) {
    recommendations.push("Use a lighter block today because the latest check-in points to lower control capacity.");
  }

  if (memory.acceptedActions?.includes("sleep_boundary")) {
    recommendations.push("Keep the sleep boundary stable; this is already a pattern you accepted.");
  }

  if (memory.ignoredActions?.includes("recovery_mode")) {
    recommendations.push("Try a smaller preventive block instead of repeating recovery mode.");
  }

  if (weekly.selection_count < 3) {
    recommendations.push("Add at least three distracting apps or categories to improve protection.");
  }

  const nextStep = recommendations[0] || "Complete one focus block so Blanked can learn your baseline.";
  const wearableConfidence = cleanNumber(resolvedCommon.confidence || common.confidence || sourceConfidence.apple_health || sourceConfidence.health_connect) || 0;
  const confidence = Math.min(100, Math.max(20, (weekly.days_count || 0) * 5 + (weekly.active_days_7d || 0) * 7 + Math.round((weekly.health_signal_coverage_percent || 0) / 4) + Math.round(wearableConfidence / 8)));
  const motivation = profile.motivation_cluster || "general_control";

  return {
    schema_version: 1,
    generated_at: new Date().toISOString(),
    confidence,
    motivation_cluster: motivation,
    summary: `Your current plan difficulty is ${weekly.recommended_plan_difficulty || "baseline"} with ${weekly.plan_adherence_percent || 0}% adherence.`,
    patterns: patterns.slice(0, 3),
    recommendations: recommendations.slice(0, 3),
    next_step: nextStep,
    risk_window: weakWindow || null,
    behavior_forecast: buildBehaviorForecast(payload, weakWindow, confidence),
    experiment: buildExperiment(payload),
    plan_update: buildPlanUpdate(payload, weakWindow),
  };
}

function buildBehaviorForecast(payload, weakWindow, confidence) {
  const weekly = payload.weekly || {};
  const correlations = payload.correlations || {};
  const wearableDecision = payload.wearable_decision_context || {};
  const wellnessSignals = payload.wellness_signals || {};
  const reasons = [];
  const unlockPressure = cleanNumber(weekly.unlock_pressure_score) || cleanNumber(weekly.pickup_pressure_score) || 0;
  const relapseRate = cleanNumber(weekly.relapse_rate) || 0;
  const recovery = cleanNumber(weekly.avg_recovery_score);
  const riskScore = Math.min(96, Math.max(18,
    28 +
    Math.round(relapseRate * 32) +
    Math.round(unlockPressure / 3) +
    ((weekly.plan_adherence_percent || 0) < 60 ? 12 : 0) +
    (recovery && recovery < 45 ? 14 : 0) +
    (correlations.screen_risk_after_bad_sleep === "high" ? 10 : 0) +
    (wearableDecision.flags?.includes("low_recovery") ? 8 : 0)
  ));

  if (unlockPressure >= 50) reasons.push("pickup pressure is above baseline");
  if (weekly.dominant_app_sequence || weekly.behavior_chain) reasons.push("a repeated app-category chain is visible");
  if ((weekly.plan_adherence_percent || 0) < 60) reasons.push("recent plans are not holding cleanly");
  if (recovery && recovery < 45) reasons.push("recovery is low");
  if (wellnessSignals.latest_check_in?.signal_type) reasons.push(`latest check-in: ${wellnessSignals.latest_check_in.signal_type}`);
  if (!reasons.length) reasons.push("baseline, timing and block history are still being learned");

  return {
    window: weakWindow || hourWindow(weekly.weakest_hour) || "Learning",
    risk_score: riskScore,
    confidence,
    reasons: reasons.slice(0, 4),
    action_label: riskScore >= 70 ? "Protect before the risk window" : "Test a light preventive block",
  };
}

function buildExperiment(payload) {
  const weekly = payload.weekly || {};
  const correlations = payload.correlations || {};
  const unlockPressure = cleanNumber(weekly.unlock_pressure_score) || cleanNumber(weekly.pickup_pressure_score) || 0;
  const lowAdherence = (weekly.plan_adherence_percent || 0) < 60;
  const chainRisk = /high|medium/i.test(String(weekly.app_sequence_risk || weekly.sequence_risk || ""));

  if (unlockPressure >= 65 || chainRisk) {
    return {
      name: "Chain Intercept",
      hypothesis: "Stopping the second quick check prevents the longer scroll loop.",
      variant: "warning_then_short_block",
      success_metric: "Fewer blocked attempts and fewer emergency exits in the same window.",
    };
  }

  if (lowAdherence || correlations.screen_risk_after_bad_sleep === "high") {
    return {
      name: "Lighter Earlier Block",
      hypothesis: "A shorter block before the weak window will hold better than a strict late block.",
      variant: "25_min_before_window",
      success_metric: "Completed block without manual or emergency exit.",
    };
  }

  return {
    name: "Stable Repeat",
    hypothesis: "Repeating the same window creates a cleaner baseline before increasing difficulty.",
    variant: "same_window_same_apps",
    success_metric: "Three completed sessions with no relapse.",
  };
}

function buildPlanUpdate(payload, weakWindow) {
  const weekly = payload.weekly || {};
  const correlations = payload.correlations || {};
  const wearableDecision = payload.wearable_decision_context || {};
  const startHour = Number.isFinite(Number(weekly.weakest_hour)) ? Number(weekly.weakest_hour) : 22;
  const startMinute = Math.max(0, Math.min(1439, startHour * 60 - 30));
  const gentle = wearableDecision.recommended_intensity === "gentle";
  const endMinute = (startMinute + (gentle ? 90 : 9 * 60)) % (24 * 60);
  const lowRecovery = (weekly.avg_recovery_score && weekly.avg_recovery_score < 45) || wearableDecision.flags?.includes("low_recovery");
  const sleepPattern = correlations.night_scroll_after_late_bedtime || correlations.screen_risk_after_bad_sleep === "high" || lowRecovery;
  const evidence = sleepPattern
    ? lowRecovery
      ? "Recovery context is low, so the next protection window should be earlier and lighter."
      : "Night scroll signals are overlapping with weaker sleep and recovery."
    : `Your riskiest window is ${weakWindow || hourWindow(startHour) || "later in the day"}.`;

  return {
    title: sleepPattern ? "Protect nights before the scroll starts." : "Protect your next risk window.",
    evidence,
    proposed_start_minute: startMinute,
    proposed_end_minute: endMinute,
    duration_days: gentle ? 3 : 5,
    action_label: "Apply preventive block",
  };
}

const insightSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "confidence",
    "motivation_cluster",
    "summary",
    "patterns",
    "recommendations",
    "next_step",
    "risk_window",
    "behavior_forecast",
    "experiment",
    "plan_update",
  ],
  properties: {
    confidence: { type: "integer", minimum: 20, maximum: 100 },
    motivation_cluster: { type: "string", maxLength: 80 },
    summary: { type: "string", maxLength: 180 },
    patterns: {
      type: "array",
      minItems: 1,
      maxItems: 3,
      items: { type: "string", maxLength: 140 },
    },
    recommendations: {
      type: "array",
      minItems: 1,
      maxItems: 3,
      items: { type: "string", maxLength: 140 },
    },
    next_step: { type: "string", maxLength: 140 },
    risk_window: { type: ["string", "null"], maxLength: 40 },
    behavior_forecast: {
      type: "object",
      additionalProperties: false,
      required: ["window", "risk_score", "confidence", "reasons", "action_label"],
      properties: {
        window: { type: "string", maxLength: 40 },
        risk_score: { type: "integer", minimum: 18, maximum: 96 },
        confidence: { type: "integer", minimum: 20, maximum: 100 },
        reasons: {
          type: "array",
          minItems: 1,
          maxItems: 4,
          items: { type: "string", maxLength: 100 },
        },
        action_label: { type: "string", maxLength: 60 },
      },
    },
    experiment: {
      type: "object",
      additionalProperties: false,
      required: ["name", "hypothesis", "variant", "success_metric"],
      properties: {
        name: { type: "string", maxLength: 60 },
        hypothesis: { type: "string", maxLength: 140 },
        variant: { type: "string", maxLength: 60 },
        success_metric: { type: "string", maxLength: 140 },
      },
    },
    plan_update: {
      type: "object",
      additionalProperties: false,
      required: ["title", "evidence", "proposed_start_minute", "proposed_end_minute", "duration_days", "action_label"],
      properties: {
        title: { type: "string", maxLength: 120 },
        evidence: { type: "string", maxLength: 180 },
        proposed_start_minute: { type: "integer", minimum: 0, maximum: 1439 },
        proposed_end_minute: { type: "integer", minimum: 0, maximum: 1439 },
        duration_days: { type: "integer", minimum: 1, maximum: 14 },
        action_label: { type: "string", maxLength: 60 },
      },
    },
  },
};

function normalizeInsight(candidate, fallback) {
  const source = candidate && typeof candidate === "object" ? candidate : {};
  const patterns = Array.isArray(source.patterns) ? source.patterns.map((item) => cleanInsightText(item, 140)).filter(Boolean) : [];
  const recommendations = Array.isArray(source.recommendations)
    ? source.recommendations.map((item) => cleanInsightText(item, 140)).filter(Boolean)
    : [];

  return {
    schema_version: 1,
    generated_at: new Date().toISOString(),
    confidence: Math.min(100, Math.max(20, Math.round(cleanNumber(source.confidence) || fallback.confidence || 20))),
    motivation_cluster: cleanText(source.motivation_cluster, 80) || fallback.motivation_cluster,
    summary: cleanInsightText(source.summary, 180) || fallback.summary,
    patterns: (patterns.length ? patterns : fallback.patterns).slice(0, 3),
    recommendations: (recommendations.length ? recommendations : fallback.recommendations).slice(0, 3),
    next_step: cleanInsightText(source.next_step, 140) || fallback.next_step,
    risk_window: source.risk_window === null ? null : normalizeClockText(cleanText(source.risk_window, 40)) || fallback.risk_window || null,
    behavior_forecast: normalizeBehaviorForecast(source.behavior_forecast, fallback.behavior_forecast),
    experiment: normalizeExperiment(source.experiment, fallback.experiment),
    plan_update: normalizePlanUpdate(source.plan_update, fallback.plan_update),
  };
}

function normalizeBehaviorForecast(candidate, fallback = {}) {
  const source = candidate && typeof candidate === "object" ? candidate : {};
  const reasons = Array.isArray(source.reasons) ? source.reasons.map((item) => cleanInsightText(item, 100)).filter(Boolean) : [];
  return {
    window: normalizeClockText(cleanText(source.window, 40)) || fallback.window || "Learning",
    risk_score: Math.min(96, Math.max(18, Math.round(cleanNumber(source.risk_score) || fallback.risk_score || 40))),
    confidence: Math.min(100, Math.max(20, Math.round(cleanNumber(source.confidence) || fallback.confidence || 20))),
    reasons: (reasons.length ? reasons : fallback.reasons || ["Blanked is learning your baseline."]).slice(0, 4),
    action_label: cleanText(source.action_label, 60) || fallback.action_label || "Test preventive protection",
  };
}

function normalizeExperiment(candidate, fallback = {}) {
  const source = candidate && typeof candidate === "object" ? candidate : {};
  return {
    name: cleanText(source.name, 60) || fallback.name || "Stable Repeat",
    hypothesis: cleanInsightText(source.hypothesis, 140) || fallback.hypothesis || "Repeating the same window creates a cleaner baseline.",
    variant: cleanText(source.variant, 60) || fallback.variant || "same_window_same_apps",
    success_metric: cleanInsightText(source.success_metric, 140) || fallback.success_metric || "Completed sessions without manual or emergency exits.",
  };
}

function normalizePlanUpdate(candidate, fallback) {
  const source = candidate && typeof candidate === "object" ? candidate : {};
  return {
    title: cleanInsightText(source.title, 120) || fallback.title,
    evidence: cleanInsightText(source.evidence, 180) || fallback.evidence,
    proposed_start_minute: Math.min(1439, Math.max(0, Math.round(cleanNumber(source.proposed_start_minute) ?? fallback.proposed_start_minute))),
    proposed_end_minute: Math.min(1439, Math.max(0, Math.round(cleanNumber(source.proposed_end_minute) ?? fallback.proposed_end_minute))),
    duration_days: Math.min(14, Math.max(1, Math.round(cleanNumber(source.duration_days) ?? fallback.duration_days))),
    action_label: cleanText(source.action_label, 60) || fallback.action_label,
  };
}

function planUpdateCandidate(planUpdate = {}) {
  return {
    kind: /sleep|night|recovery/i.test(`${planUpdate.title || ""} ${planUpdate.evidence || ""}`) ? "sleep_boundary" : "preventive_block",
    start_minute: cleanNumber(planUpdate.proposed_start_minute),
    end_minute: cleanNumber(planUpdate.proposed_end_minute),
    duration_days: cleanNumber(planUpdate.duration_days),
  };
}

async function applyPlanIntelligence(anonymousUserId, payload, insight) {
  const planUpdate = insight.plan_update;
  if (!planUpdate) return insight;
  try {
    const candidate = planUpdateCandidate(planUpdate);
    const segment = segmentKey(payload.profile || {});
    const pattern = intelligencePatternKey({ key: candidate.kind }, `${planUpdate.title || ""} ${planUpdate.evidence || ""}`);
    const kind = recommendationKind(candidate);
    const [macroRows, microRows] = await Promise.all([
      supabaseFetch(`bai_global_plan_patterns?segment_key=eq.${encodeURIComponent(segment)}&pattern_key=eq.${encodeURIComponent(pattern)}&recommendation_kind=eq.${encodeURIComponent(kind)}&select=*&order=positive_rate.desc,sample_size.desc&limit=5`, { method: "GET" }),
      supabaseFetch(`bai_user_plan_outcomes?anonymous_user_id=eq.${encodeURIComponent(anonymousUserId)}&pattern_key=eq.${encodeURIComponent(pattern)}&recommendation_kind=eq.${encodeURIComponent(kind)}&select=*&order=created_at.desc&limit=30`, { method: "GET" }),
    ]);
    const macro = bestMacroEvidence(macroRows);
    const micro = bestMicroEvidence(microRows);
    const decision = decidePlanIntelligence({ macro, micro, fallback: candidate, seed: `${anonymousUserId}|${segment}|${pattern}|${kind}` });
    const value = decision.final_recommendation || {};
    return {
      ...insight,
      plan_update: {
        ...planUpdate,
        proposed_start_minute: cleanNumber(value.start_minute) ?? planUpdate.proposed_start_minute,
        proposed_end_minute: cleanNumber(value.end_minute) ?? planUpdate.proposed_end_minute,
        duration_days: cleanNumber(value.duration_days) ?? planUpdate.duration_days,
      },
      plan_intelligence: {
        segment_key: segment,
        pattern_key: pattern,
        recommendation_kind: kind,
        decision_source: decision.decision_source,
        reason: decision.reason,
        confidence: decision.confidence,
      },
    };
  } catch (error) {
    return {
      ...insight,
      plan_intelligence: {
        unavailable: true,
        reason: error.message,
      },
    };
  }
}

function cleanInsightText(value, maxLength) {
  const text = normalizeClockText(cleanText(value, maxLength + 80)).replace(/\s+/g, " ");
  if (text.length <= maxLength) return closeInsightText(text);

  const sentence = text.slice(0, maxLength).match(/^(.+[.!?])\s/);
  if (sentence?.[1] && sentence[1].length >= 40) {
    return sentence[1].trim();
  }

  const wordSafe = text.slice(0, maxLength - 1).replace(/\s+\S*$/, "").trim();
  return closeInsightText(wordSafe);
}

function normalizeClockText(text) {
  return cleanText(text, 400).replace(/\b([01]?\d|2[0-3]):([0-5]\d)(?!\s*(?:AM|PM)\b)(?:\s*[-–]\s*([01]?\d|2[0-3]):([0-5]\d)(?!\s*(?:AM|PM)\b))?/gi, (match, hour, minute, endHour, endMinute) => {
    const start = clockTimeText(Number(hour), Number(minute));
    if (endHour === undefined) return start;
    return `${start} to ${clockTimeText(Number(endHour), Number(endMinute))}`;
  });
}

function closeInsightText(text) {
  const normalized = text
    .replace(/\s+(and|or|with|to|for|of|in|on|at|by|from|while|because)$/i, "")
    .replace(/[,;:]+$/, "")
    .trim();

  if (!/[.!?]$/.test(normalized)) {
    const completeSentence = normalized.match(/^(.+[.!?])\s+/);
    if (completeSentence?.[1] && completeSentence[1].length >= 40) {
      return completeSentence[1].trim();
    }
  }

  const cleaned = normalized.replace(/\s+\S{1,2}$/, "").trim();
  if (!cleaned) return "";
  return /[.!?]$/.test(cleaned) ? cleaned : `${cleaned}.`;
}

function extractResponseText(responseBody) {
  if (typeof responseBody.output_text === "string") {
    return responseBody.output_text;
  }

  const output = Array.isArray(responseBody.output) ? responseBody.output : [];
  for (const item of output) {
    const content = Array.isArray(item.content) ? item.content : [];
    for (const part of content) {
      if (typeof part.text === "string") return part.text;
      if (typeof part.output_text === "string") return part.output_text;
    }
  }
  return "";
}

async function buildModelInsight(payload, fallback, memory = {}) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    return { insight: fallback, source: "deterministic_fallback" };
  }

  const model = process.env.OPENAI_MODEL || "gpt-5.6-luna";
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      authorization: `Bearer ${apiKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model,
      input: [
        {
          role: "system",
          content:
            "You generate concise digital wellness insights for Blanked. Use only the aggregated features provided, including pickup pressure, app-category chains, check-ins, outcomes, Health/wearable signals, and baseline timing when present. Do not claim medical diagnosis, therapy, health treatment, exact app surveillance, exact location, or certainty. Do not use the word coach. Every summary, pattern, recommendation, next_step, behavior_forecast reason, experiment hypothesis, and success_metric must be a complete sentence ending with punctuation. behavior_forecast must explain the next likely risk window with reasons and an action label. experiment must pick one small intervention test with a measurable outcome. plan_update must propose one preventive daily blocking window that can reduce screen time based on the signals. Return practical, specific, non-alarming English.",
        },
        {
          role: "user",
          content: JSON.stringify({
            task: "Create one weekly digital wellness insight for the app.",
            output_contract: insightSchema,
            aggregated_features: payload,
            wearable_memory: memory,
          }),
        },
      ],
      text: {
        format: {
          type: "json_schema",
          name: "digital_wellness_insight",
          strict: true,
          schema: insightSchema,
        },
      },
      max_output_tokens: 700,
    }),
  });

  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`openai_failed_${response.status}:${detail.slice(0, 240)}`);
  }

  const body = await response.json();
  const text = extractResponseText(body);
  const parsed = JSON.parse(text);
  return { insight: normalizeInsight(parsed, fallback), source: `openai:${model}` };
}

async function loadWearableMemory(anonymousUserId) {
  try {
    const rows = await supabaseFetch(
      `wearable_recommendation_outcomes?anonymous_user_id=eq.${encodeURIComponent(anonymousUserId)}&select=provider,signal_type,action_kind,outcome,confidence,created_at&order=created_at.desc&limit=30`,
      { method: "GET" }
    );
    const acceptedActions = rows.filter((row) => row.outcome === "accepted" || row.outcome === "completed").map((row) => row.action_kind);
    const ignoredActions = rows.filter((row) => row.outcome === "ignored" || row.outcome === "dismissed").map((row) => row.action_kind);
    return {
      acceptedActions: [...new Set(acceptedActions)].slice(0, 8),
      ignoredActions: [...new Set(ignoredActions)].slice(0, 8),
      recentOutcomes: rows.slice(0, 8),
    };
  } catch (error) {
    return { acceptedActions: [], ignoredActions: [], recentOutcomes: [], unavailable: error.message };
  }
}

async function loadRecentWearableSnapshots(anonymousUserId) {
  try {
    return await supabaseFetch(
      `wearable_feature_snapshots?anonymous_user_id=eq.${encodeURIComponent(anonymousUserId)}&select=provider,common_features,provider_features,source_confidence,freshness,created_at&period_end=not.is.null&order=created_at.desc&limit=24`,
      { method: "GET" }
    );
  } catch (error) {
    return [];
  }
}

async function loadRecentWellnessSignals(anonymousUserId) {
  try {
    const rows = await supabaseFetch(
      `wellness_signal_events?anonymous_user_id=eq.${encodeURIComponent(anonymousUserId)}&select=signal_type,value_number,value_text,source,metadata,measured_at&order=measured_at.desc&limit=30`,
      { method: "GET" }
    );
    const latestWeather = rows.find((row) => row.signal_type === "weather_context") || null;
    const latestCheckIn = rows.find((row) => ["mood", "energy", "stress"].includes(row.signal_type)) || null;
    const recentLogs = rows
      .filter((row) => ["caffeine", "alcohol", "sick", "meditation"].includes(row.signal_type))
      .slice(0, 8);
    return {
      latest_weather: latestWeather,
      latest_check_in: latestCheckIn,
      recent_logs: recentLogs,
    };
  } catch (error) {
    return { unavailable: error.message };
  }
}

async function persistWearableSnapshot(anonymousUserId, payload) {
  const providers = Object.keys(payload.provider_features || {});
  const provider = providers.includes("apple_health")
    ? "apple_health"
    : providers.includes("health_connect")
      ? "health_connect"
      : null;
  if (!provider || !Object.keys(payload.common_features || {}).length) return;

  try {
    await supabaseFetch("wearable_feature_snapshots", {
      method: "POST",
      headers: { prefer: "return=minimal" },
      body: JSON.stringify({
        anonymous_user_id: anonymousUserId,
        provider,
        period_start: payload.period_start,
        period_end: payload.period_end,
        common_features: payload.common_features,
        provider_features: payload.provider_features[provider] || {},
        source_confidence: payload.source_confidence || {},
        freshness: payload.freshness || {},
        raw_samples_sent: false,
        sync_kind: "incremental",
      }),
    });
  } catch (error) {
    console.warn("wearable_snapshot_skipped", error.message);
  }
}

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;

  try {
    const body = parseJsonBody(event);
    const anonymousUserId = cleanText(body.anonymous_user_id, 80);

    if (!anonymousUserId || body.data_consent !== true) {
      return json(400, { error: "missing_consent_or_user_id" });
    }

    const payload = compactPayload(body.payload || {});
    requireSafePrivacy(payload);
    await persistWearableSnapshot(anonymousUserId, payload);
    const recentSnapshots = await loadRecentWearableSnapshots(anonymousUserId);
    const resolvedWearable = resolveWearableSources({ currentPayload: payload, snapshots: recentSnapshots });
    payload.resolved_wearable = resolvedWearable;
    payload.wearable_decision_context = wearableDecisionContext(resolvedWearable);
    payload.wellness_signals = await loadRecentWellnessSignals(anonymousUserId);
    const wearableMemory = await loadWearableMemory(anonymousUserId);
    const fallbackInsight = buildInsight(payload, wearableMemory);
    let modelResult;
    try {
      modelResult = await buildModelInsight(payload, fallbackInsight, wearableMemory);
    } catch (error) {
      modelResult = { insight: fallbackInsight, source: "deterministic_fallback_after_model_error", error: error.message };
    }
    let insight = await applyPlanIntelligence(anonymousUserId, payload, {
      ...modelResult.insight,
      source: modelResult.source,
    });
    const generatedRecommendationId = recommendationId(anonymousUserId, payload, insight);
    insight = { ...insight, recommendation_id: generatedRecommendationId };
    await persistGeneratedOutcome(anonymousUserId, payload, insight, generatedRecommendationId);

    const rows = await supabaseFetch("digital_wellness_feature_payloads?select=*", {
      method: "POST",
      headers: { prefer: "return=representation" },
      body: JSON.stringify({
        anonymous_user_id: anonymousUserId,
        schema_version: payload.schema_version || 1,
        period_start: payload.period_start,
        period_end: payload.period_end,
        payload,
        insight: { ...insight, wearable_memory: wearableMemory, model_error: modelResult.error || null },
        platform: cleanText(body.platform, 40) || "ios",
        locale: cleanText(body.locale, 40),
        app_version: cleanText(body.app_version, 40),
        build_number: cleanText(body.build_number, 40),
        data_consent: true,
        consent_text: cleanText(body.consent_text, 240),
        privacy_raw_health_samples_sent: cleanBoolean(payload.privacy.raw_health_samples_sent),
        privacy_raw_sleep_stage_timestamps_sent: cleanBoolean(payload.privacy.raw_sleep_stage_timestamps_sent),
        privacy_exact_app_selection_sent: cleanBoolean(payload.privacy.exact_app_selection_sent),
        privacy_exact_location_sent: cleanBoolean(payload.privacy.exact_location_sent),
        submitted_at: new Date().toISOString(),
      }),
    });

    return json(200, { ok: true, id: rows?.[0]?.id || null, insight, source: modelResult.source });
  } catch (error) {
    const status = error.message === "raw_or_sensitive_payload_rejected" ? 400 : 500;
    return json(status, { error: "digital_wellness_features_failed", detail: error.message });
  }
};
