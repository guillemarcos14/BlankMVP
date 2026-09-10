const { json, parseJsonBody, requireMethod, supabaseFetch } = require("./_membership");
const {
  candidateValue,
  patternKey,
  recommendationKind,
  segmentKey,
} = require("./bai-intelligence");

const OUTCOMES = new Set([
  "generated",
  "accepted",
  "activated",
  "edited",
  "cancelled",
  "ignored",
  "dismissed",
  "completed",
  "failed",
  "broke",
  "held",
  "relapse_after",
  "improved_after",
]);

function cleanText(value, maxLength = 240) {
  return String(value || "").trim().replace(/\s+/g, " ").slice(0, maxLength);
}

function cleanNumber(value, fallback = null, min = Number.NEGATIVE_INFINITY, max = Number.POSITIVE_INFINITY) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(max, Math.max(min, Math.round(number)));
}

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;
  try {
    const body = parseJsonBody(event);
    const anonymousUserId = cleanText(body.anonymous_user_id, 120);
    if (!anonymousUserId) return json(400, { error: "missing_anonymous_user_id" });
    if (body.data_consent !== true) return json(403, { error: "data_consent_required" });

    const outcome = cleanText(body.outcome, 40);
    if (!OUTCOMES.has(outcome)) return json(400, { error: "unsupported_outcome" });

    const record = {
      anonymous_user_id: anonymousUserId,
      segment_key: cleanText(body.segment_key, 180) || segmentKey(body.profile || {}),
      pattern_key: cleanText(body.pattern_key, 80) || patternKey(body.pattern || {}, body.prompt || ""),
      recommendation_kind: recommendationKind(body.recommendation || body.candidate_recommendation || {}, body.pattern || {}),
      recommendation_id: cleanText(body.recommendation_id, 120) || null,
      proposed_value: candidateValue(body.recommendation || body.candidate_recommendation || body.proposed_value || {}),
      outcome,
      outcome_score: cleanNumber(body.outcome_score, null, -100, 100),
      metadata: body.metadata && typeof body.metadata === "object" && !Array.isArray(body.metadata) ? body.metadata : {},
    };

    await supabaseFetch("bai_user_plan_outcomes", {
      method: "POST",
      headers: { prefer: "return=minimal" },
      body: JSON.stringify(record),
    });

    return json(200, { ok: true });
  } catch (error) {
    return json(500, { error: "bai_outcome_failed", detail: error.message });
  }
};
