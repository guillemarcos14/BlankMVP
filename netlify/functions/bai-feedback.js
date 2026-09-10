const { json, parseJsonBody, requireMethod, supabaseFetch } = require("./_membership");
const {
  candidateValue,
  patternKey,
  recommendationKind,
  segmentKey,
} = require("./bai-intelligence");

const FEEDBACK_TYPES = new Set([
  "helpful",
  "not_helpful",
  "too_strict",
  "too_soft",
  "wrong_context",
  "good_recommendation",
]);

const FEEDBACK_OUTCOME = {
  helpful: { outcome: "accepted", score: 18 },
  not_helpful: { outcome: "dismissed", score: -18 },
  too_strict: { outcome: "edited", score: -8 },
  too_soft: { outcome: "edited", score: -4 },
  wrong_context: { outcome: "failed", score: -28 },
  good_recommendation: { outcome: "accepted", score: 24 },
};

function cleanText(value, maxLength = 240) {
  return String(value || "").trim().replace(/\s+/g, " ").slice(0, maxLength);
}

function cleanObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function inferMemorySignals({ prompt, feedbackType, metadata }) {
  const text = cleanText(`${prompt} ${metadata?.user_note || ""}`, 900).toLowerCase();
  const signals = [];
  const add = (signalType, value, confidence = 35) => {
    if (!value) return;
    signals.push({
      signal_type: signalType,
      signal_value: value,
      confidence,
      source: feedbackType,
    });
  };

  if (/too strict|demasiado estricto|too_strict/.test(feedbackType)) add("blocking_tolerance", "softer", 70);
  if (/too soft|demasiado suave|too_soft/.test(feedbackType)) add("blocking_tolerance", "stricter", 70);
  if (feedbackType === "wrong_context") add("context_reliability", "needs_clarification", 80);
  if (/instagram/.test(text)) add("problem_app", "Instagram", 45);
  if (/tiktok|tik tok/.test(text)) add("problem_app", "TikTok", 45);
  if (/youtube|shorts/.test(text)) add("problem_app", "YouTube", 45);
  if (/reddit/.test(text)) add("problem_app", "Reddit", 45);
  if (/night|bed|sleep|noche|dormir|cama/.test(text)) add("weak_moment", "night", 45);
  if (/lunch|after lunch|comida|almuerzo/.test(text)) add("weak_moment", "after_lunch", 45);
  if (/work|deep work|trabaj|focus|foco|study|estudi/.test(text)) add("goal", "focus", 40);

  return signals.slice(0, 8);
}

async function writeOutcome(record, feedbackType) {
  const mapped = FEEDBACK_OUTCOME[feedbackType];
  if (!mapped) return;
  await supabaseFetch("bai_user_plan_outcomes", {
    method: "POST",
    headers: { prefer: "return=minimal" },
    body: JSON.stringify({
      ...record,
      outcome: mapped.outcome,
      outcome_score: mapped.score,
    }),
  });
}

async function writeMemorySignals(anonymousUserId, signals, baseRecord) {
  if (!signals.length) return;
  await supabaseFetch("bai_user_memory_signals", {
    method: "POST",
    headers: { prefer: "return=minimal" },
    body: JSON.stringify(signals.map((signal) => ({
      anonymous_user_id: anonymousUserId,
      signal_type: signal.signal_type,
      signal_value: signal.signal_value,
      confidence: signal.confidence,
      source: signal.source,
      recommendation_id: baseRecord.recommendation_id,
      metadata: baseRecord.metadata,
    }))),
  });
}

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;
  try {
    const body = parseJsonBody(event);
    const anonymousUserId = cleanText(body.anonymous_user_id, 120);
    if (!anonymousUserId) return json(400, { error: "missing_anonymous_user_id" });
    if (body.data_consent !== true) return json(403, { error: "data_consent_required" });

    const feedbackType = cleanText(body.feedback_type, 40);
    if (!FEEDBACK_TYPES.has(feedbackType)) return json(400, { error: "unsupported_feedback_type" });

    const metadata = cleanObject(body.metadata);
    const recommendation = body.recommendation || body.candidate_recommendation || {};
    const baseRecord = {
      anonymous_user_id: anonymousUserId,
      segment_key: cleanText(body.segment_key, 180) || segmentKey(body.profile || {}),
      pattern_key: cleanText(body.pattern_key, 80) || patternKey(body.pattern || {}, body.prompt || ""),
      recommendation_kind: recommendationKind(recommendation, body.pattern || {}),
      recommendation_id: cleanText(body.recommendation_id, 120) || null,
      proposed_value: candidateValue(recommendation || body.proposed_value || {}),
      metadata: {
        ...metadata,
        prompt: cleanText(body.prompt, 600),
        response_text: cleanText(body.response_text, 700),
        feedback_type: feedbackType,
      },
    };

    await supabaseFetch("bai_recommendation_feedback", {
      method: "POST",
      headers: { prefer: "return=minimal" },
      body: JSON.stringify({
        ...baseRecord,
        feedback_type: feedbackType,
        user_note: cleanText(body.user_note, 500) || null,
      }),
    });

    await writeOutcome(baseRecord, feedbackType);
    await writeMemorySignals(
      anonymousUserId,
      inferMemorySignals({ prompt: body.prompt, feedbackType, metadata }),
      baseRecord,
    );

    return json(200, { ok: true });
  } catch (error) {
    return json(500, { error: "bai_feedback_failed", detail: error.message });
  }
};
