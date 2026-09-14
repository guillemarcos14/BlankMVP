import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

function cleanText(value: unknown, maxLength = 240) {
  return String(value || "").trim().slice(0, maxLength);
}

function cleanNumber(value: unknown) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function cleanBoolean(value: unknown) {
  if (value === true) return true;
  if (value === false) return false;
  return null;
}

function ageBand(age: unknown) {
  const value = cleanNumber(age);
  if (value == null || value < 13) return "age_unknown";
  if (value < 18) return "age_u18";
  if (value < 25) return "age_18_24";
  if (value < 35) return "age_25_34";
  if (value < 45) return "age_35_44";
  if (value < 55) return "age_45_54";
  return "age_55_plus";
}

function normalizeGender(value: unknown) {
  const text = cleanText(value, 40).toLowerCase();
  if (["female", "woman", "women", "f", "mujer"].includes(text)) return "female";
  if (["male", "man", "men", "m", "hombre"].includes(text)) return "male";
  return text ? "other" : "gender_unknown";
}

function segmentKey(profile: Record<string, any> = {}) {
  const goal = cleanText(profile.goal || profile.motivation_cluster || "goal_unknown", 40)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_|_$/g, "") || "goal_unknown";
  return [ageBand(profile.age), `gender_${normalizeGender(profile.gender)}`, `goal_${goal}`].join("|");
}

function patternKey(planUpdate: Record<string, any> = {}) {
  const raw = cleanText(`${planUpdate.title || ""} ${planUpdate.evidence || ""}`, 160).toLowerCase();
  if (/(sleep|bed|night|dormir|noche|recovery)/.test(raw)) return "sleep_night_scroll";
  if (/(lunch|comida|comer|almuerzo)/.test(raw)) return "lunch_scroll";
  if (/(work|trabaj|focus|foco)/.test(raw)) return "work_focus";
  if (/(study|estudi|exam|opos)/.test(raw)) return "study_focus";
  if (/(social|scroll|tiktok|instagram|youtube|reddit|reels|shorts)/.test(raw)) return "social_scroll";
  return "general";
}

function recommendationKind(planUpdate: Record<string, any> = {}) {
  const raw = cleanText(`${planUpdate.title || ""} ${planUpdate.evidence || ""}`, 160).toLowerCase();
  return /(sleep|bed|night|dormir|noche|recovery)/.test(raw) ? "sleep_boundary" : "preventive_block";
}

function proposedValue(planUpdate: Record<string, any> = {}) {
  const value: Record<string, number> = {};
  const start = cleanNumber(planUpdate.proposed_start_minute);
  const end = cleanNumber(planUpdate.proposed_end_minute);
  const duration = cleanNumber(planUpdate.duration_days);
  if (start != null) value.start_minute = Math.min(1439, Math.max(0, Math.round(start)));
  if (end != null) value.end_minute = Math.min(1439, Math.max(0, Math.round(end)));
  if (duration != null) value.duration_days = Math.min(30, Math.max(1, Math.round(duration)));
  return value;
}

async function recommendationId(anonymousUserId: string, payload: Record<string, any>, insight: Record<string, any>) {
  const pattern = patternKey(insight.plan_update || {});
  const kind = recommendationKind(insight.plan_update || {});
  const source = [anonymousUserId, payload.period_start, payload.period_end, pattern, kind].join("|");
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(source));
  const hex = Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
  return `dw_${hex.slice(0, 24)}`;
}

async function persistGeneratedOutcome(
  supabase: ReturnType<typeof createClient>,
  anonymousUserId: string,
  payload: Record<string, any>,
  insight: Record<string, any>,
  id: string,
) {
  const planUpdate = insight.plan_update || {};
  const { error } = await supabase.from("bai_user_plan_outcomes").insert({
    anonymous_user_id: anonymousUserId,
    segment_key: segmentKey(payload.profile || {}),
    pattern_key: patternKey(planUpdate),
    recommendation_kind: recommendationKind(planUpdate),
    recommendation_id: id,
    proposed_value: proposedValue(planUpdate),
    outcome: "generated",
    outcome_score: 0,
    metadata: {
      generated_key: id,
      source: "digital_wellness_features_edge",
      risk_score: insight.behavior_forecast?.risk_score || null,
      forecast_window: insight.behavior_forecast?.window || null,
      experiment: insight.experiment?.name || null,
    },
  });
  if (error && error.code !== "23505") {
    console.warn("bai_generated_outcome_skipped", error.message);
  }
}

function requireSafePrivacy(payload: Record<string, any>) {
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

function compactPayload(payload: Record<string, any>) {
  return {
    schema_version: cleanNumber(payload.schema_version),
    generated_at: payload.generated_at,
    period_start: payload.period_start,
    period_end: payload.period_end,
    profile: payload.profile || {},
    daily: Array.isArray(payload.daily) ? payload.daily.slice(-14) : [],
    weekly: payload.weekly || {},
    correlations: payload.correlations || {},
    privacy: payload.privacy || {},
  };
}

function hourWindow(hour: unknown) {
  const start = Number(hour);
  if (!Number.isFinite(start)) return null;
  const end = (start + 2) % 24;
  return `${clockTimeText(start)} to ${clockTimeText(end)}`;
}

function clockTimeText(hour: number, minute = 0) {
  const safeHour = ((Number(hour) % 24) + 24) % 24;
  const safeMinute = Math.min(59, Math.max(0, Number(minute) || 0));
  const displayHour = safeHour % 12 === 0 ? 12 : safeHour % 12;
  const meridiem = safeHour < 12 ? "AM" : "PM";
  return `${displayHour}:${String(safeMinute).padStart(2, "0")} ${meridiem}`;
}

function buildInsight(payload: Record<string, any>) {
  const weekly = payload.weekly || {};
  const correlations = payload.correlations || {};
  const profile = payload.profile || {};
  const patterns: string[] = [];
  const recommendations: string[] = [];

  if ((weekly.blocked_minutes || 0) > 0) {
    patterns.push(`${weekly.blocked_minutes} protected minutes across ${weekly.blocks_completed || 0} completed blocks.`);
  } else {
    patterns.push("Not enough completed blocks yet; start with one protected window this week.");
  }

  if (weekly.avg_sleep_minutes) {
    patterns.push(`Average sleep signal is ${Math.round((weekly.avg_sleep_minutes / 60) * 10) / 10}h.`);
  }

  if (weekly.avg_steps) {
    patterns.push(`Average activity signal is ${weekly.avg_steps} steps.`);
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

  if (correlations.relapses_after_short_sleep > 0 || correlations.screen_risk_after_bad_sleep === "high") {
    recommendations.push("Use a lighter block after short sleep instead of relying on willpower.");
  }

  if ((weekly.selection_count || 0) < 3) {
    recommendations.push("Add at least three distracting apps or categories to improve protection.");
  }

  const nextStep = recommendations[0] || "Complete one focus block so Blanked can learn your baseline.";
  const confidence = Math.min(100, Math.max(20, (weekly.days_count || 0) * 6 + (weekly.active_days_7d || 0) * 8));
  const behaviorForecast = buildBehaviorForecast(payload, weakWindow, confidence);

  return {
    schema_version: 1,
    generated_at: new Date().toISOString(),
    confidence,
    motivation_cluster: profile.motivation_cluster || "general_control",
    summary: `Your current plan difficulty is ${weekly.recommended_plan_difficulty || "baseline"} with ${weekly.plan_adherence_percent || 0}% adherence.`,
    patterns: patterns.slice(0, 3),
    recommendations: recommendations.slice(0, 3),
    next_step: nextStep,
    risk_window: weakWindow || null,
    behavior_forecast: behaviorForecast,
    experiment: buildExperiment(payload),
    plan_update: buildPlanUpdate(payload, weakWindow),
  };
}

function buildBehaviorForecast(payload: Record<string, any>, weakWindow: string | null, confidence: number) {
  const weekly = payload.weekly || {};
  const correlations = payload.correlations || {};
  const unlockPressure = Number(weekly.unlock_pressure_score || weekly.pickup_pressure_score || 0);
  const relapseRate = Number(weekly.relapse_rate || 0);
  const lowRecovery = Number(weekly.avg_recovery_score || 100) < 45;
  const riskScore = Math.min(96, Math.max(18,
    28 + Math.round(relapseRate * 32) + Math.round(unlockPressure / 3)
      + (Number(weekly.plan_adherence_percent || 0) < 60 ? 12 : 0)
      + (lowRecovery ? 14 : 0)
      + (correlations.screen_risk_after_bad_sleep === "high" ? 10 : 0),
  ));
  const reasons: string[] = [];
  if (unlockPressure >= 50) reasons.push("Pickup pressure is above baseline.");
  if (weekly.dominant_app_sequence || weekly.behavior_chain) reasons.push("A repeated app-category chain is visible.");
  if (Number(weekly.plan_adherence_percent || 0) < 60) reasons.push("Recent plans are not holding cleanly.");
  if (lowRecovery) reasons.push("Recovery context is low.");
  if (!reasons.length) reasons.push("Blanked is still learning baseline timing and outcomes.");
  return {
    window: weakWindow || hourWindow(weekly.weakest_hour) || "Learning",
    risk_score: riskScore,
    confidence,
    reasons: reasons.slice(0, 4),
    action_label: riskScore >= 70 ? "Protect before the risk window" : "Test a light preventive block",
  };
}

function buildExperiment(payload: Record<string, any>) {
  const weekly = payload.weekly || {};
  const correlations = payload.correlations || {};
  const unlockPressure = Number(weekly.unlock_pressure_score || weekly.pickup_pressure_score || 0);
  if (unlockPressure >= 65 || /high|medium/i.test(String(weekly.app_sequence_risk || weekly.sequence_risk || ""))) {
    return {
      name: "Chain Intercept",
      hypothesis: "Stopping the second quick check prevents the longer scroll loop.",
      variant: "warning_then_short_block",
      success_metric: "Fewer blocked attempts and fewer emergency exits in the same window.",
    };
  }
  if (Number(weekly.plan_adherence_percent || 0) < 60 || correlations.screen_risk_after_bad_sleep === "high") {
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

function buildPlanUpdate(payload: Record<string, any>, weakWindow: string | null) {
  const weekly = payload.weekly || {};
  const correlations = payload.correlations || {};
  const startHour = Number.isFinite(Number(weekly.weakest_hour)) ? Number(weekly.weakest_hour) : 22;
  const startMinute = Math.max(0, Math.min(1439, startHour * 60 - 30));
  const endMinute = (startMinute + 9 * 60) % (24 * 60);
  const sleepPattern = correlations.night_scroll_after_late_bedtime || correlations.screen_risk_after_bad_sleep === "high";
  const evidence = sleepPattern
    ? "Night scroll signals are overlapping with weaker sleep and recovery."
    : `Your riskiest window is ${weakWindow || hourWindow(startHour) || "later in the day"}.`;

  return {
    title: sleepPattern ? "Protect nights before the scroll starts." : "Protect your next risk window.",
    evidence,
    proposed_start_minute: startMinute,
    proposed_end_minute: endMinute,
    duration_days: 5,
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
        reasons: { type: "array", minItems: 1, maxItems: 4, items: { type: "string", maxLength: 100 } },
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

function normalizeInsight(candidate: Record<string, any>, fallback: Record<string, any>) {
  const source = candidate && typeof candidate === "object" ? candidate : {};
  const patterns = Array.isArray(source.patterns)
    ? source.patterns.map((item) => cleanInsightText(item, 140)).filter(Boolean)
    : [];
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
    behavior_forecast: source.behavior_forecast && typeof source.behavior_forecast === "object"
      ? source.behavior_forecast
      : fallback.behavior_forecast,
    experiment: source.experiment && typeof source.experiment === "object"
      ? source.experiment
      : fallback.experiment,
    plan_update: normalizePlanUpdate(source.plan_update, fallback.plan_update),
  };
}

function normalizePlanUpdate(candidate: Record<string, any>, fallback: Record<string, any>) {
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

function cleanInsightText(value: unknown, maxLength: number) {
  const text = normalizeClockText(cleanText(value, maxLength + 80)).replace(/\s+/g, " ");
  if (text.length <= maxLength) return closeInsightText(text);

  const sentence = text.slice(0, maxLength).match(/^(.+[.!?])\s/);
  if (sentence?.[1] && sentence[1].length >= 40) {
    return sentence[1].trim();
  }

  const wordSafe = text.slice(0, maxLength - 1).replace(/\s+\S*$/, "").trim();
  return closeInsightText(wordSafe);
}

function normalizeClockText(text: unknown) {
  return cleanText(text, 400).replace(/\b([01]?\d|2[0-3]):([0-5]\d)(?:\s*[-–]\s*([01]?\d|2[0-3]):([0-5]\d))?/g, (_match, hour, minute, endHour, endMinute) => {
    const start = clockTimeText(Number(hour), Number(minute));
    if (endHour === undefined) return start;
    return `${start} to ${clockTimeText(Number(endHour), Number(endMinute))}`;
  });
}

function closeInsightText(text: string) {
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

function extractResponseText(responseBody: Record<string, any>) {
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

async function buildModelInsight(payload: Record<string, any>, fallback: Record<string, any>) {
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) {
    return { insight: fallback, source: "deterministic_fallback" };
  }

  const model = Deno.env.get("OPENAI_MODEL") || "gpt-5.6-luna";
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
            "You generate concise digital wellness insights for Blanked. Use only the aggregated features provided, including pickup pressure, app-category chains, check-ins, outcomes, Health/wearable signals, and baseline timing. Do not claim medical diagnosis, therapy, health treatment, exact app surveillance, exact location, or certainty. Do not use the word coach. Every summary, pattern, recommendation, next_step, behavior_forecast reason, experiment hypothesis, and success_metric must be a complete sentence ending with punctuation. behavior_forecast must explain the next likely digital risk window. experiment must pick one small intervention test with a measurable outcome. plan_update must propose one preventive daily blocking window. Return practical, specific, non-alarming English.",
        },
        {
          role: "user",
          content: JSON.stringify({
            task: "Create one weekly digital wellness insight for the app.",
            output_contract: insightSchema,
            aggregated_features: payload,
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

serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return json(405, { error: "method_not_allowed" });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error("supabase_env_not_configured");
    }

    const body = await request.json();
    const anonymousUserId = cleanText(body.anonymous_user_id, 80);
    if (!anonymousUserId || body.data_consent !== true) {
      return json(400, { error: "missing_consent_or_user_id" });
    }

    const payload = compactPayload(body.payload || {});
    requireSafePrivacy(payload);
    const fallbackInsight = buildInsight(payload);
    let modelResult;
    try {
      modelResult = await buildModelInsight(payload, fallbackInsight);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      modelResult = { insight: fallbackInsight, source: "deterministic_fallback_after_model_error", error: message };
    }
    const insightWithoutId = {
      ...modelResult.insight,
      source: modelResult.source,
    };
    const generatedRecommendationId = await recommendationId(anonymousUserId, payload, insightWithoutId);
    const insight = { ...insightWithoutId, recommendation_id: generatedRecommendationId };
    const supabase = createClient(supabaseUrl, serviceRoleKey);
    await persistGeneratedOutcome(supabase, anonymousUserId, payload, insight, generatedRecommendationId);

    const { data, error } = await supabase
      .from("digital_wellness_feature_payloads")
      .insert({
        anonymous_user_id: anonymousUserId,
        schema_version: payload.schema_version || 1,
        period_start: payload.period_start,
        period_end: payload.period_end,
        payload,
        insight: { ...insight, model_error: modelResult.error || null },
        platform: "ios",
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
      })
      .select("id")
      .single();

    if (error) {
      throw error;
    }

    return json(200, { ok: true, id: data?.id || null, insight, source: modelResult.source });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const status = message === "raw_or_sensitive_payload_rejected" ? 400 : 500;
    return json(status, { error: "digital_wellness_features_failed", detail: message });
  }
});
