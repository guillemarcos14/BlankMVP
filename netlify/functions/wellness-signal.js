const {
  json,
  parseJsonBody,
  requireMethod,
  supabaseFetch,
} = require("./_membership");

const ALLOWED_SIGNALS = new Set([
  "mood",
  "energy",
  "stress",
  "caffeine",
  "alcohol",
  "sick",
  "meditation",
  "weather_context",
]);

function cleanText(value, maxLength = 160) {
  return String(value || "").trim().slice(0, maxLength);
}

function cleanNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;

  try {
    const body = parseJsonBody(event);
    const anonymousUserId = cleanText(body.anonymous_user_id, 80);
    const signalType = cleanText(body.signal_type, 40);
    if (!anonymousUserId || body.data_consent !== true) {
      return json(400, { error: "missing_consent_or_user_id" });
    }
    if (!ALLOWED_SIGNALS.has(signalType)) {
      return json(400, { error: "unsupported_signal_type" });
    }

    const row = {
      anonymous_user_id: anonymousUserId,
      signal_type: signalType,
      value_number: cleanNumber(body.value_number),
      value_text: cleanText(body.value_text, 120) || null,
      source: cleanText(body.source, 40) || "app",
      metadata: body.metadata && typeof body.metadata === "object" && !Array.isArray(body.metadata)
        ? body.metadata
        : {},
      measured_at: cleanText(body.measured_at, 40) || new Date().toISOString(),
    };

    await supabaseFetch("wellness_signal_events", {
      method: "POST",
      headers: { prefer: "return=minimal" },
      body: JSON.stringify(row),
    });

    return json(200, { ok: true, signal_type: signalType });
  } catch (error) {
    return json(500, { error: "wellness_signal_failed", detail: error.message });
  }
};
