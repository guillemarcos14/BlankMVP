const {
  json,
  parseJsonBody,
  requireMethod,
  supabaseFetch,
} = require("./_membership");

const PROVIDERS = new Set(["apple_health", "health_connect", "oura", "whoop", "garmin", "fitbit_google_health", "withings"]);
const ACTIONS = new Set(["recovery_mode", "sleep_boundary", "preventive_block", "morning_report", "source_connect", "other"]);
const OUTCOMES = new Set(["generated", "accepted", "ignored", "dismissed", "completed", "failed"]);

function cleanText(value, maxLength = 160) {
  return String(value || "").trim().slice(0, maxLength);
}

function cleanNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function cleanMetadata(value) {
  const source = value && typeof value === "object" && !Array.isArray(value) ? value : {};
  const cleaned = {};
  for (const [key, rawValue] of Object.entries(source).slice(0, 25)) {
    const cleanKey = cleanText(key, 64);
    if (!cleanKey) continue;
    cleaned[cleanKey] = typeof rawValue === "number" || typeof rawValue === "boolean"
      ? rawValue
      : cleanText(rawValue, 180);
  }
  return cleaned;
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

    const provider = cleanText(body.provider, 64) || null;
    if (provider && !PROVIDERS.has(provider)) return json(400, { error: "unsupported_provider" });
    const actionKind = cleanText(body.action_kind, 64) || "other";
    if (!ACTIONS.has(actionKind)) return json(400, { error: "unsupported_action_kind" });
    const outcome = cleanText(body.outcome, 64);
    if (!OUTCOMES.has(outcome)) return json(400, { error: "unsupported_outcome" });

    await supabaseFetch("wearable_recommendation_outcomes", {
      method: "POST",
      headers: { prefer: "return=minimal" },
      body: JSON.stringify({
        anonymous_user_id: anonymousUserId,
        provider,
        signal_type: cleanText(body.signal_type, 80) || null,
        recommendation_id: cleanText(body.recommendation_id, 120) || null,
        action_kind: actionKind,
        outcome,
        confidence: cleanNumber(body.confidence),
        metadata: cleanMetadata(body.metadata),
      }),
    });

    return json(200, { ok: true });
  } catch (error) {
    return json(500, { error: "wearable_outcome_failed", detail: error.message });
  }
};
