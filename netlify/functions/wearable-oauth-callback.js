const {
  json,
  requireMethod,
  supabaseFetch,
} = require("./_membership");
const crypto = require("crypto");
const {
  encryptToken,
  exchangeCode,
  verifyState,
} = require("./_wearable_oauth");

function html(statusCode, body) {
  return {
    statusCode,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
    },
    body,
  };
}

function cleanText(value, maxLength = 160) {
  return String(value || "").trim().slice(0, maxLength);
}

exports.handler = async (event) => {
  const methodError = requireMethod(event, "GET");
  if (methodError) return methodError;

  try {
    const code = cleanText(event.queryStringParameters?.code, 600);
    const state = cleanText(event.queryStringParameters?.state, 2000);
    const oauthError = cleanText(event.queryStringParameters?.error, 180);
    if (oauthError) return html(400, closePage("Connection cancelled", oauthError));
    if (!code || !state) return json(400, { error: "missing_oauth_callback_params" });

    const statePayload = verifyState(state);
    const provider = cleanText(event.queryStringParameters?.provider || statePayload.provider, 64);
    if (!provider || statePayload.provider !== provider) throw new Error("provider_state_mismatch");

    const token = await exchangeCode(provider, code);
    const expiresIn = Number(token.expires_in || 0);
    const tokenExpiresAt = expiresIn > 0 ? new Date(Date.now() + expiresIn * 1000).toISOString() : null;

    const externalId = token.user_id || token.userid || token.owner_id || null;

    await supabaseFetch("wearable_connections?on_conflict=anonymous_user_id,provider", {
      method: "POST",
      headers: { prefer: "resolution=merge-duplicates,return=minimal" },
      body: JSON.stringify({
        anonymous_user_id: statePayload.anonymous_user_id,
        provider,
        status: "connected",
        scopes: cleanText(token.scope || "").split(/[,\s]+/).filter(Boolean).slice(0, 30),
        external_account_hash: externalId ? crypto.createHash("sha256").update(`${provider}:${externalId}`).digest("hex") : null,
        encrypted_access_token: encryptToken(token.access_token),
        encrypted_refresh_token: encryptToken(token.refresh_token),
        token_expires_at: tokenExpiresAt,
        last_error: null,
        disconnected_at: null,
        updated_at: new Date().toISOString(),
      }),
    });

    return html(200, closePage("Wearable connected", "You can return to Blanked."));
  } catch (error) {
    return html(500, closePage("Wearable connection failed", error.message));
  }
};

function closePage(title, body) {
  return `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHtml(title)}</title></head><body style="font-family:-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif;padding:28px;line-height:1.4"><h1>${escapeHtml(title)}</h1><p>${escapeHtml(body)}</p></body></html>`;
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (char) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  }[char]));
}
