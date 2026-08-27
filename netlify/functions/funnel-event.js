const {
  json,
  parseJsonBody,
  requireMethod,
  supabaseFetch,
} = require("./_membership");

const EVENT_TABLE = "digital_wellness_feature_payloads";
const ALLOWED_EVENTS = new Set([
  "onboarding_started",
  "onboarding_step_viewed",
  "onboarding_personalization_submitted",
  "onboarding_personalization_failed",
  "trial_cta_tapped",
  "trial_started",
  "trial_failed",
  "free_plan_selected",
  "screen_time_permission_result",
  "notifications_permission_result",
  "apps_selection_updated",
  "first_block_started",
  "block_started",
  "block_ended",
  "relapse_attempt",
  "health_permission_requested",
  "health_permission_result",
  "ai_insight_requested",
  "ai_insight_received",
]);

function cleanText(value, maxLength = 160) {
  return String(value || "").trim().slice(0, maxLength);
}

function cleanBoolean(value) {
  return value === true ? true : value === false ? false : null;
}

function cleanNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function cleanProperties(value) {
  const source = value && typeof value === "object" && !Array.isArray(value) ? value : {};
  const cleaned = {};

  for (const [key, rawValue] of Object.entries(source).slice(0, 30)) {
    const cleanKey = cleanText(key, 64);
    if (!cleanKey) continue;

    if (typeof rawValue === "boolean") {
      cleaned[cleanKey] = rawValue;
    } else if (typeof rawValue === "number") {
      cleaned[cleanKey] = cleanNumber(rawValue);
    } else {
      cleaned[cleanKey] = cleanText(rawValue, 240);
    }
  }

  return cleaned;
}

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;

  try {
    const body = parseJsonBody(event);
    const anonymousUserId = cleanText(body.anonymous_user_id, 80);
    const eventName = cleanText(body.event, 80);

    if (!anonymousUserId || body.data_consent !== true) {
      return json(400, { error: "missing_consent_or_user_id" });
    }

    if (!ALLOWED_EVENTS.has(eventName)) {
      return json(400, { error: "unsupported_event" });
    }

    const payload = {
      event: eventName,
      step: cleanText(body.step, 80) || null,
      properties: cleanProperties(body.properties),
    };

    await supabaseFetch(EVENT_TABLE, {
      method: "POST",
      headers: { prefer: "return=minimal" },
      body: JSON.stringify({
        anonymous_user_id: anonymousUserId,
        schema_version: 1,
        payload,
        insight: { event: eventName },
        platform: cleanText(body.platform, 40) || "ios",
        locale: cleanText(body.locale, 40),
        app_version: cleanText(body.app_version, 40),
        build_number: cleanText(body.build_number, 40),
        data_consent: true,
        consent_text: cleanText(body.consent_text, 240) || "Product analytics",
        privacy_raw_health_samples_sent: false,
        privacy_raw_sleep_stage_timestamps_sent: false,
        privacy_exact_app_selection_sent: false,
        privacy_exact_location_sent: false,
        submitted_at: new Date().toISOString(),
      }),
    });

    return json(200, { ok: true });
  } catch (error) {
    return json(500, { error: "funnel_event_failed", detail: error.message });
  }
};
