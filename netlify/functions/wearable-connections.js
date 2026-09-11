const {
  json,
  parseJsonBody,
  requireMethod,
  supabaseFetch,
} = require("./_membership");
const {
  decryptToken,
  revokeToken,
} = require("./_wearable_oauth");

const PROVIDERS = new Set(["apple_health", "health_connect", "oura", "whoop", "garmin", "fitbit_google_health", "withings", "strava"]);
const STATUSES = new Set(["connected", "partial", "no_data", "stale", "error", "disconnected"]);

function cleanText(value, maxLength = 160) {
  return String(value || "").trim().slice(0, maxLength);
}

function cleanProvider(value) {
  const provider = cleanText(value, 64);
  if (!PROVIDERS.has(provider)) throw new Error("unsupported_provider");
  return provider;
}

function cleanStatus(value) {
  const status = cleanText(value, 40) || "connected";
  if (!STATUSES.has(status)) throw new Error("unsupported_status");
  return status;
}

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;

  try {
    const body = parseJsonBody(event);
    const anonymousUserId = cleanText(body.anonymous_user_id, 80);
    const action = cleanText(body.action, 40) || "list";
    if (!anonymousUserId || body.data_consent !== true) {
      return json(400, { error: "missing_consent_or_user_id" });
    }

    if (action === "list") {
      const connections = await supabaseFetch(
        `wearable_connections?anonymous_user_id=eq.${encodeURIComponent(anonymousUserId)}&select=id,provider,status,scopes,last_sync_at,last_error,updated_at&order=created_at.asc`,
        { method: "GET" }
      );
      return json(200, { ok: true, connections });
    }

    if (action === "disconnect") {
      const provider = cleanProvider(body.provider);
      const rows = await supabaseFetch(
        `wearable_connections?anonymous_user_id=eq.${encodeURIComponent(anonymousUserId)}&provider=eq.${encodeURIComponent(provider)}&select=id,encrypted_access_token,encrypted_refresh_token&limit=1`,
        { method: "GET" }
      );
      const connection = rows?.[0];
      let revoke = { attempted: false, supported: false };
      if (body.revoke !== false && connection) {
        revoke = await revokeConnectionTokens(provider, connection).catch((error) => ({
          attempted: true,
          supported: true,
          error: cleanText(error.message, 180),
        }));
      }
      await supabaseFetch(
        `wearable_connections?anonymous_user_id=eq.${encodeURIComponent(anonymousUserId)}&provider=eq.${encodeURIComponent(provider)}`,
        {
          method: "PATCH",
          headers: { prefer: "return=minimal" },
          body: JSON.stringify({
            status: "disconnected",
            encrypted_access_token: null,
            encrypted_refresh_token: null,
            token_expires_at: null,
            disconnected_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
          }),
        }
      );
      return json(200, { ok: true, revoke });
    }

    if (action === "upsert_aggregator") {
      const provider = cleanProvider(body.provider);
      if (provider !== "apple_health" && provider !== "health_connect") {
        return json(400, { error: "aggregator_provider_required" });
      }
      const status = cleanStatus(body.status);
      await supabaseFetch("wearable_connections?on_conflict=anonymous_user_id,provider", {
        method: "POST",
        headers: { prefer: "resolution=merge-duplicates,return=minimal" },
        body: JSON.stringify({
          anonymous_user_id: anonymousUserId,
          provider,
          status,
          scopes: Array.isArray(body.scopes) ? body.scopes.map((scope) => cleanText(scope, 80)).filter(Boolean).slice(0, 30) : [],
          last_sync_at: body.last_sync_at || null,
          last_error: cleanText(body.last_error, 240) || null,
          updated_at: new Date().toISOString(),
        }),
      });
      return json(200, { ok: true });
    }

    return json(400, { error: "unsupported_action" });
  } catch (error) {
    const status = ["unsupported_provider", "unsupported_status"].includes(error.message) ? 400 : 500;
    return json(status, { error: "wearable_connections_failed", detail: error.message });
  }
};

async function revokeConnectionTokens(provider, connection) {
  const encrypted = connection.encrypted_refresh_token || connection.encrypted_access_token;
  if (!encrypted) return { attempted: false, supported: false };
  const token = decryptToken(encrypted);
  return revokeToken(provider, token);
}
