const { json, parseJsonBody, requireMethod, supabaseFetch, timingSafeEqual } = require("./_membership");

function cleanText(value, maxLength = 240) {
  return String(value || "").trim().replace(/\s+/g, " ").slice(0, maxLength);
}

function cleanNumber(value, fallback = 25, min = 1, max = 200) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(max, Math.max(min, Math.round(number)));
}

function requireOwner(event) {
  const token = process.env.BAI_OWNER_TOKEN;
  if (!token) return null;
  const header = event.headers.authorization || event.headers.Authorization || "";
  const provided = header.replace(/^Bearer\s+/i, "");
  if (timingSafeEqual(token, provided)) return null;
  return json(401, { error: "unauthorized" });
}

async function safeFetch(path, fallback = []) {
  try {
    return await supabaseFetch(path, { method: "GET" });
  } catch (error) {
    return { unavailable: error.message, rows: fallback };
  }
}

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;
  const ownerError = requireOwner(event);
  if (ownerError) return ownerError;

  try {
    const body = parseJsonBody(event);
    const limit = cleanNumber(body.limit, 25, 1, 200);
    const anonymousUserId = cleanText(body.anonymous_user_id, 120);
    const userFilter = anonymousUserId ? `anonymous_user_id=eq.${encodeURIComponent(anonymousUserId)}&` : "";

    const [
      recommendations,
      feedback,
      memorySignals,
      learningChanges,
      outcomes,
    ] = await Promise.all([
      safeFetch(`bai_learning_dashboard?select=*&order=sample_size.desc&limit=${limit}`),
      safeFetch(`bai_recommendation_feedback?${userFilter}select=*&order=created_at.desc&limit=${limit}`),
      safeFetch(`bai_user_memory_signals?${userFilter}select=*&order=updated_at.desc,created_at.desc&limit=${limit}`),
      safeFetch(`bai_learning_changes?select=*&order=created_at.desc&limit=${Math.min(limit, 50)}`),
      safeFetch(`bai_user_plan_outcomes?${userFilter}select=*&order=created_at.desc&limit=${limit}`),
    ]);

    return json(200, {
      ok: true,
      recommendations,
      feedback,
      memory_signals: memorySignals,
      learning_changes: learningChanges,
      recent_outcomes: outcomes,
    });
  } catch (error) {
    return json(500, { error: "bai_learning_dashboard_failed", detail: error.message });
  }
};
