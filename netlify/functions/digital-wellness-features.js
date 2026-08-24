const {
  json,
  parseJsonBody,
  requireMethod,
  supabaseFetch,
} = require("./_membership");

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
    profile: payload.profile || {},
    daily: Array.isArray(payload.daily) ? payload.daily.slice(-14) : [],
    weekly: payload.weekly || {},
    correlations: payload.correlations || {},
    privacy: payload.privacy || {},
  };
}

function hourWindow(hour) {
  if (!Number.isFinite(Number(hour))) return null;
  const start = Number(hour);
  const end = (start + 2) % 24;
  return `${String(start).padStart(2, "0")}:00-${String(end).padStart(2, "0")}:00`;
}

function buildInsight(payload) {
  const weekly = payload.weekly || {};
  const correlations = payload.correlations || {};
  const profile = payload.profile || {};
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

  if (weekly.selection_count < 3) {
    recommendations.push("Add at least three distracting apps or categories to improve protection.");
  }

  const nextStep = recommendations[0] || "Complete one focus block so Blanked can learn your baseline.";
  const confidence = Math.min(100, Math.max(20, (weekly.days_count || 0) * 6 + (weekly.active_days_7d || 0) * 8));
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
  };
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
    const insight = buildInsight(payload);

    const rows = await supabaseFetch("digital_wellness_feature_payloads?select=*", {
      method: "POST",
      headers: { prefer: "return=representation" },
      body: JSON.stringify({
        anonymous_user_id: anonymousUserId,
        schema_version: payload.schema_version || 1,
        period_start: payload.period_start,
        period_end: payload.period_end,
        payload,
        insight,
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
      }),
    });

    return json(200, { ok: true, id: rows?.[0]?.id || null, insight });
  } catch (error) {
    const status = error.message === "raw_or_sensitive_payload_rejected" ? 400 : 500;
    return json(status, { error: "digital_wellness_features_failed", detail: error.message });
  }
};
