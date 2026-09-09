const crypto = require("crypto");

const PROVIDERS = {
  oura: {
    authUrl: "https://cloud.ouraring.com/oauth/authorize",
    tokenUrl: "https://api.ouraring.com/oauth/token",
    revokeUrlEnv: "OURA_REVOKE_URL",
    scopes: ["email", "personal", "daily", "heartrate", "workout", "session", "spo2"],
    clientIdEnv: "OURA_CLIENT_ID",
    clientSecretEnv: "OURA_CLIENT_SECRET",
  },
  whoop: {
    authUrl: "https://api.prod.whoop.com/oauth/oauth2/auth",
    tokenUrl: "https://api.prod.whoop.com/oauth/oauth2/token",
    revokeUrlEnv: "WHOOP_REVOKE_URL",
    scopes: ["offline", "read:profile", "read:recovery", "read:cycles", "read:sleep", "read:workout", "read:body_measurement"],
    clientIdEnv: "WHOOP_CLIENT_ID",
    clientSecretEnv: "WHOOP_CLIENT_SECRET",
  },
  fitbit_google_health: {
    authUrl: "https://accounts.google.com/o/oauth2/v2/auth",
    tokenUrl: "https://oauth2.googleapis.com/token",
    revokeUrl: "https://oauth2.googleapis.com/revoke",
    scopes: [
      "https://www.googleapis.com/auth/googlehealth.profile.readonly",
      "https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly",
      "https://www.googleapis.com/auth/googlehealth.sleep.readonly",
      "https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly",
    ],
    clientIdEnv: "GOOGLE_HEALTH_CLIENT_ID",
    clientSecretEnv: "GOOGLE_HEALTH_CLIENT_SECRET",
  },
  withings: {
    authUrl: "https://account.withings.com/oauth2_user/authorize2",
    tokenUrl: "https://wbsapi.withings.net/v2/oauth2",
    revokeUrlEnv: "WITHINGS_REVOKE_URL",
    scopes: ["user.info,user.metrics,user.activity"],
    clientIdEnv: "WITHINGS_CLIENT_ID",
    clientSecretEnv: "WITHINGS_CLIENT_SECRET",
  },
  strava: {
    authUrl: "https://www.strava.com/oauth/authorize",
    tokenUrl: "https://www.strava.com/oauth/token",
    revokeUrl: "https://www.strava.com/oauth/deauthorize",
    scopes: ["read", "activity:read_all"],
    clientIdEnv: "STRAVA_CLIENT_ID",
    clientSecretEnv: "STRAVA_CLIENT_SECRET",
  },
};

function providerConfig(provider) {
  return PROVIDERS[provider] || null;
}

function redirectUri() {
  const base = process.env.WEARABLE_OAUTH_REDIRECT_BASE || process.env.URL;
  if (!base) throw new Error("WEARABLE_OAUTH_REDIRECT_BASE is not configured");
  return `${base.replace(/\/$/, "")}/.netlify/functions/wearable-oauth-callback`;
}

function signState(payload) {
  const secret = process.env.WEARABLE_OAUTH_STATE_SECRET || process.env.MEMBERSHIP_ADMIN_SECRET;
  if (!secret) throw new Error("WEARABLE_OAUTH_STATE_SECRET is not configured");
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const sig = crypto.createHmac("sha256", secret).update(body).digest("base64url");
  return `${body}.${sig}`;
}

function verifyState(state) {
  const secret = process.env.WEARABLE_OAUTH_STATE_SECRET || process.env.MEMBERSHIP_ADMIN_SECRET;
  if (!secret) throw new Error("WEARABLE_OAUTH_STATE_SECRET is not configured");
  const [body, sig] = String(state || "").split(".");
  if (!body || !sig) throw new Error("invalid_oauth_state");
  const expected = crypto.createHmac("sha256", secret).update(body).digest("base64url");
  if (!crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected))) {
    throw new Error("invalid_oauth_state");
  }
  const payload = JSON.parse(Buffer.from(body, "base64url").toString("utf8"));
  if (!payload.iat || Date.now() - payload.iat > 15 * 60 * 1000) {
    throw new Error("expired_oauth_state");
  }
  return payload;
}

function encryptToken(value) {
  if (!value) return null;
  const rawKey = process.env.WEARABLE_TOKEN_ENCRYPTION_KEY;
  if (!rawKey) throw new Error("WEARABLE_TOKEN_ENCRYPTION_KEY is not configured");
  const key = crypto.createHash("sha256").update(rawKey).digest();
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", key, iv);
  const encrypted = Buffer.concat([cipher.update(String(value), "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  return `${iv.toString("base64url")}.${tag.toString("base64url")}.${encrypted.toString("base64url")}`;
}

function decryptToken(value) {
  if (!value) return null;
  const rawKey = process.env.WEARABLE_TOKEN_ENCRYPTION_KEY;
  if (!rawKey) throw new Error("WEARABLE_TOKEN_ENCRYPTION_KEY is not configured");
  const [ivValue, tagValue, encryptedValue] = String(value).split(".");
  if (!ivValue || !tagValue || !encryptedValue) throw new Error("invalid_encrypted_token");
  const key = crypto.createHash("sha256").update(rawKey).digest();
  const decipher = crypto.createDecipheriv("aes-256-gcm", key, Buffer.from(ivValue, "base64url"));
  decipher.setAuthTag(Buffer.from(tagValue, "base64url"));
  const decrypted = Buffer.concat([
    decipher.update(Buffer.from(encryptedValue, "base64url")),
    decipher.final(),
  ]);
  return decrypted.toString("utf8");
}

async function exchangeCode(provider, code) {
  const config = providerConfig(provider);
  if (!config) throw new Error("unsupported_provider");
  const clientId = process.env[config.clientIdEnv];
  const clientSecret = process.env[config.clientSecretEnv];
  if (!clientId || !clientSecret) throw new Error("provider_oauth_not_configured");

  const body = new URLSearchParams({
    grant_type: "authorization_code",
    code,
    redirect_uri: redirectUri(provider),
    client_id: clientId,
    client_secret: clientSecret,
  });
  if (provider === "withings") body.set("action", "requesttoken");

  const response = await fetch(config.tokenUrl, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body,
  });
  const text = await response.text();
  const data = text ? JSON.parse(text) : {};
  if (!response.ok) throw new Error(`token_exchange_failed_${response.status}:${text.slice(0, 180)}`);
  return data.body && provider === "withings" ? data.body : data;
}

async function refreshAccessToken(provider, refreshToken) {
  const config = providerConfig(provider);
  if (!config) throw new Error("unsupported_provider");
  if (!refreshToken) throw new Error("missing_refresh_token");
  const clientId = process.env[config.clientIdEnv];
  const clientSecret = process.env[config.clientSecretEnv];
  if (!clientId || !clientSecret) throw new Error("provider_oauth_not_configured");

  const body = new URLSearchParams({
    grant_type: "refresh_token",
    refresh_token: refreshToken,
    client_id: clientId,
    client_secret: clientSecret,
  });
  if (provider === "withings") body.set("action", "requesttoken");

  const response = await fetch(config.tokenUrl, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body,
  });
  const text = await response.text();
  const data = text ? JSON.parse(text) : {};
  if (!response.ok) throw new Error(`token_refresh_failed_${response.status}:${text.slice(0, 180)}`);
  return data.body && provider === "withings" ? data.body : data;
}

async function revokeToken(provider, token) {
  const config = providerConfig(provider);
  if (!config || !token) return { attempted: false, supported: false };
  const revokeUrl = config.revokeUrl || process.env[config.revokeUrlEnv];
  if (!revokeUrl) return { attempted: false, supported: false };

  const response = await fetch(revokeUrl, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ token }),
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`token_revoke_failed_${response.status}:${text.slice(0, 180)}`);
  return { attempted: true, supported: true };
}

module.exports = {
  providerConfig,
  redirectUri,
  signState,
  verifyState,
  encryptToken,
  decryptToken,
  exchangeCode,
  refreshAccessToken,
  revokeToken,
};
