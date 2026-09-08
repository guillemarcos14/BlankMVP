const {
  json,
  supabaseFetch,
} = require("./_membership");
const { syncConnection } = require("./wearable-sync");

const SYNCABLE_STATUSES = "connected,partial,no_data,stale,error";
const DIRECT_PROVIDERS = "oura,whoop,fitbit_google_health,withings";

function cleanText(value, maxLength = 160) {
  return String(value || "").trim().slice(0, maxLength);
}

function authorized(event) {
  const secret = process.env.WEARABLE_SYNC_ADMIN_SECRET || process.env.MEMBERSHIP_ADMIN_SECRET;
  if (!secret) return true;
  const header = event.headers?.authorization || event.headers?.Authorization || "";
  const query = event.queryStringParameters?.token || "";
  return header === `Bearer ${secret}` || query === secret;
}

exports.handler = async (event) => {
  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 204, headers: { "cache-control": "no-store" }, body: "" };
  }
  if (event.httpMethod && !["GET", "POST"].includes(event.httpMethod)) {
    return json(405, { error: "method_not_allowed" });
  }
  if (!authorized(event)) return json(401, { error: "unauthorized" });

  const limit = Math.min(100, Math.max(1, Number(event.queryStringParameters?.limit || 50)));
  const staleBefore = new Date(Date.now() - 20 * 60 * 60 * 1000).toISOString();
  try {
    const rows = await supabaseFetch(
      `wearable_connections?status=in.(${SYNCABLE_STATUSES})&provider=in.(${DIRECT_PROVIDERS})&or=(last_sync_at.is.null,last_sync_at.lt.${encodeURIComponent(staleBefore)})&select=*&order=last_sync_at.asc.nullsfirst&limit=${limit}`,
      { method: "GET" }
    );
    const results = [];
    for (const connection of rows || []) {
      results.push(await syncConnection(cleanText(connection.anonymous_user_id, 80), connection, "incremental").catch((error) => ({
        ok: false,
        provider: connection.provider,
        anonymous_user_id: cleanText(connection.anonymous_user_id, 80),
        error: cleanText(error.message, 180),
      })));
    }
    return json(200, {
      ok: results.every((result) => result.ok),
      scanned: rows?.length || 0,
      synced: results.filter((result) => result.ok).length,
      failed: results.filter((result) => !result.ok).length,
      results,
    });
  } catch (error) {
    return json(500, { error: "wearable_scheduled_sync_failed", detail: error.message });
  }
};

exports.config = {
  schedule: "17 5 * * *",
};
