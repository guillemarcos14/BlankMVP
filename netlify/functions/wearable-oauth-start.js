const crypto = require("crypto");
const { json, parseJsonBody, requireMethod } = require("./_membership");
const { providerConfig, redirectUri, signState } = require("./_wearable_oauth");

function cleanText(value, maxLength = 160) {
  return String(value || "").trim().slice(0, maxLength);
}

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;

  try {
    const body = parseJsonBody(event);
    const anonymousUserId = cleanText(body.anonymous_user_id, 80);
    const provider = cleanText(body.provider, 64);
    if (!anonymousUserId || body.data_consent !== true) {
      return json(400, { error: "missing_consent_or_user_id" });
    }
    if (provider === "garmin") {
      return json(409, { error: "provider_requires_partner_access" });
    }

    const config = providerConfig(provider);
    if (!config) return json(400, { error: "unsupported_provider" });
    const clientId = process.env[config.clientIdEnv];
    if (!clientId) return json(409, { error: "provider_oauth_not_configured" });

    const state = signState({
      anonymous_user_id: anonymousUserId,
      provider,
      iat: Date.now(),
      nonce: cryptoRandom(),
    });
    const url = new URL(config.authUrl);
    url.searchParams.set("response_type", "code");
    url.searchParams.set("client_id", clientId);
    url.searchParams.set("redirect_uri", redirectUri(provider));
    url.searchParams.set("scope", config.scopes.join(" "));
    url.searchParams.set("state", state);
    if (provider === "fitbit_google_health") {
      url.searchParams.set("access_type", "offline");
      url.searchParams.set("prompt", "consent");
    }
    if (provider === "strava") {
      url.searchParams.set("approval_prompt", "auto");
    }

    return json(200, { ok: true, provider, authorization_url: url.toString() });
  } catch (error) {
    return json(500, { error: "wearable_oauth_start_failed", detail: error.message });
  }
};

function cryptoRandom() {
  return crypto.randomBytes(12).toString("base64url");
}
