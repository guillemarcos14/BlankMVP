const { json, parseJsonBody, requireMethod, supabaseFetch, timingSafeEqual } = require("./_membership");

function cleanText(value, maxLength = 240) {
  return String(value || "").trim().replace(/\s+/g, " ").slice(0, maxLength);
}

function cleanNumber(value, fallback = 20, min = 1, max = 100) {
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

async function listNotifications(body) {
  const status = cleanText(body.status || "pending", 40);
  const allowedStatus = new Set(["pending", "reviewed", "reverted", "dismissed"]);
  const safeStatus = allowedStatus.has(status) ? status : "pending";
  const limit = cleanNumber(body.limit, 20, 1, 100);
  try {
    return await supabaseFetch(`bai_learning_changes?status=eq.${encodeURIComponent(safeStatus)}&select=*&order=created_at.desc&limit=${limit}`, { method: "GET" });
  } catch (_) {
    const decisions = await supabaseFetch(`bai_recommendation_decisions?select=id,anonymous_user_id,segment_key,pattern_key,recommendation_kind,evidence,created_at&order=created_at.desc&limit=${limit * 4}`, { method: "GET" });
    return decisions
      .map((decision) => ({
        id: decision.id,
        created_at: decision.created_at,
        anonymous_user_id: decision.anonymous_user_id,
        segment_key: decision.segment_key,
        pattern_key: decision.pattern_key,
        recommendation_kind: decision.recommendation_kind,
        ...(decision.evidence?.learning_change || {}),
        storage: "decision_evidence",
      }))
      .filter((change) => change.change_key && (change.status || "pending") === safeStatus)
      .slice(0, limit);
  }
}

async function updateNotification(body) {
  const id = cleanText(body.id, 80);
  const changeKey = cleanText(body.change_key, 80);
  const status = cleanText(body.status || "reviewed", 40);
  const allowedStatus = new Set(["reviewed", "reverted", "dismissed"]);
  if (!allowedStatus.has(status)) return { error: "unsupported_status" };
  if (!id && !changeKey) return { error: "missing_id_or_change_key" };
  const filter = id ? `id=eq.${encodeURIComponent(id)}` : `change_key=eq.${encodeURIComponent(changeKey)}`;
  try {
    await supabaseFetch(`bai_learning_changes?${filter}`, {
      method: "PATCH",
      headers: { prefer: "return=minimal" },
      body: JSON.stringify({
        status,
        reviewed_at: new Date().toISOString(),
      }),
    });
  } catch (_) {
    const lookup = id
      ? `id=eq.${encodeURIComponent(id)}`
      : `evidence->learning_change->>change_key=eq.${encodeURIComponent(changeKey)}`;
    const rows = await supabaseFetch(`bai_recommendation_decisions?${lookup}&select=id,evidence&order=created_at.desc&limit=1`, { method: "GET" });
    const row = rows[0];
    if (!row?.id || !row.evidence?.learning_change) return { error: "notification_not_found" };
    await supabaseFetch(`bai_recommendation_decisions?id=eq.${encodeURIComponent(row.id)}`, {
      method: "PATCH",
      headers: { prefer: "return=minimal" },
      body: JSON.stringify({
        evidence: {
          ...row.evidence,
          learning_change: {
            ...row.evidence.learning_change,
            status,
            reviewed_at: new Date().toISOString(),
          },
        },
      }),
    });
  }
  return { ok: true };
}

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;
  const ownerError = requireOwner(event);
  if (ownerError) return ownerError;

  try {
    const body = parseJsonBody(event);
    const action = cleanText(body.action || "list", 40);
    if (action === "list") {
      const notifications = await listNotifications(body);
      return json(200, { ok: true, notifications });
    }
    if (action === "review" || action === "dismiss" || action === "revert") {
      const status = action === "dismiss" ? "dismissed" : action === "revert" ? "reverted" : "reviewed";
      const result = await updateNotification({ ...body, status });
      if (result.error) return json(400, result);
      return json(200, result);
    }
    return json(400, { error: "unsupported_action" });
  } catch (error) {
    return json(500, { error: "bai_learning_notifications_failed", detail: error.message });
  }
};
