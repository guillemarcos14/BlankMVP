const assert = require("assert");

process.env.SUPABASE_URL = "https://blank-test.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role";
process.env.WEARABLE_TOKEN_ENCRYPTION_KEY = "test-wearable-token-key";
process.env.GOOGLE_HEALTH_CLIENT_ID = "test-google-client";
process.env.GOOGLE_HEALTH_CLIENT_SECRET = "test-google-secret";

const { encryptToken, decryptToken } = require("../netlify/functions/_wearable_oauth");
const { handler: syncHandler } = require("../netlify/functions/wearable-sync");
const { handler: connectionsHandler } = require("../netlify/functions/wearable-connections");
const { handler: scheduledSyncHandler } = require("../netlify/functions/wearable-scheduled-sync");

function response(status, data) {
  return {
    ok: status >= 200 && status < 300,
    status,
    statusText: status >= 200 && status < 300 ? "OK" : "Error",
    text: async () => JSON.stringify(data || {}),
  };
}

function postEvent(body) {
  return {
    httpMethod: "POST",
    body: JSON.stringify(body),
  };
}

async function refreshesExpiredTokenBeforeSync() {
  const requests = [];
  const expiredAt = new Date(Date.now() - 60_000).toISOString();
  const connection = {
    id: "conn-google",
    anonymous_user_id: "anon-wearable",
    provider: "fitbit_google_health",
    status: "connected",
    encrypted_access_token: encryptToken("expired-access-token"),
    encrypted_refresh_token: encryptToken("refresh-token"),
    token_expires_at: expiredAt,
  };

  global.fetch = async (url, options = {}) => {
    requests.push({ url: String(url), options });
    if (String(url).startsWith("https://blank-test.supabase.co/rest/v1/wearable_connections") && options.method === "GET") {
      return response(200, [connection]);
    }
    if (String(url) === "https://oauth2.googleapis.com/token") {
      assert.match(String(options.body), /grant_type=refresh_token/);
      assert.match(String(options.body), /refresh-token/);
      return response(200, { access_token: "fresh-access-token", refresh_token: "fresh-refresh-token", expires_in: 3600 });
    }
    if (String(url) === "https://health.googleapis.com/v4/users/me/profile") {
      assert.strictEqual(options.headers.authorization, "Bearer fresh-access-token");
      return response(200, { resourceName: "users/me" });
    }
    if (String(url).includes("dataPoints:dailyRollUp")) {
      assert.strictEqual(options.headers.authorization, "Bearer fresh-access-token");
      if (String(url).includes("/steps/")) return response(200, { rollupDataPoints: [{ steps: { countSum: 4200 } }] });
      if (String(url).includes("/sleep/")) return response(200, { rollupDataPoints: [{ sleep: { durationMillisSum: 25_200_000 } }] });
      return response(200, { rollupDataPoints: [] });
    }
    if (String(url).startsWith("https://blank-test.supabase.co/rest/v1/wearable_feature_snapshots")) {
      const payload = JSON.parse(options.body);
      assert.strictEqual(payload.provider, "fitbit_google_health");
      assert.strictEqual(payload.raw_samples_sent, false);
      assert.ok(payload.common_features.coverage > 0);
      return response(201, null);
    }
    if (String(url).startsWith("https://blank-test.supabase.co/rest/v1/wearable_connections") && options.method === "PATCH") {
      const payload = JSON.parse(options.body);
      assert.strictEqual(payload.status, "connected");
      assert.strictEqual(decryptToken(payload.encrypted_access_token), "fresh-access-token");
      assert.strictEqual(decryptToken(payload.encrypted_refresh_token), "fresh-refresh-token");
      return response(204, null);
    }
    if (String(url).startsWith("https://blank-test.supabase.co/rest/v1/digital_wellness_feature_payloads")) {
      return response(201, null);
    }
    throw new Error(`Unexpected request: ${url}`);
  };

  const result = await syncHandler(postEvent({
    anonymous_user_id: "anon-wearable",
    data_consent: true,
    provider: "fitbit_google_health",
    sync_kind: "incremental",
  }));
  const body = JSON.parse(result.body);

  assert.strictEqual(result.statusCode, 200, result.body);
  assert.strictEqual(body.ok, true);
  assert.strictEqual(body.token_refreshed, true);
  assert.ok(requests.some((request) => request.url === "https://oauth2.googleapis.com/token"));
}

async function disconnectRevokesGoogleTokenBestEffort() {
  const revokedTokens = [];
  const connection = {
    id: "conn-google",
    encrypted_access_token: encryptToken("access-token"),
    encrypted_refresh_token: encryptToken("refresh-token"),
  };

  global.fetch = async (url, options = {}) => {
    if (String(url).startsWith("https://blank-test.supabase.co/rest/v1/wearable_connections") && options.method === "GET") {
      return response(200, [connection]);
    }
    if (String(url) === "https://oauth2.googleapis.com/revoke") {
      revokedTokens.push(new URLSearchParams(String(options.body)).get("token"));
      return response(200, {});
    }
    if (String(url).startsWith("https://blank-test.supabase.co/rest/v1/wearable_connections") && options.method === "PATCH") {
      const payload = JSON.parse(options.body);
      assert.strictEqual(payload.status, "disconnected");
      assert.strictEqual(payload.encrypted_access_token, null);
      assert.strictEqual(payload.encrypted_refresh_token, null);
      return response(204, null);
    }
    throw new Error(`Unexpected request: ${url}`);
  };

  const result = await connectionsHandler(postEvent({
    anonymous_user_id: "anon-wearable",
    data_consent: true,
    action: "disconnect",
    provider: "fitbit_google_health",
  }));
  const body = JSON.parse(result.body);

  assert.strictEqual(result.statusCode, 200, result.body);
  assert.deepStrictEqual(revokedTokens, ["refresh-token"]);
  assert.strictEqual(body.revoke.attempted, true);
}

async function scheduledSyncProcessesDueConnections() {
  const connection = {
    id: "conn-due",
    anonymous_user_id: "anon-scheduled",
    provider: "fitbit_google_health",
    status: "no_data",
    encrypted_access_token: encryptToken("valid-access-token"),
    encrypted_refresh_token: encryptToken("refresh-token"),
    token_expires_at: new Date(Date.now() + 3_600_000).toISOString(),
    last_sync_at: null,
  };
  let snapshotInserted = false;

  global.fetch = async (url, options = {}) => {
    const target = String(url);
    if (target.startsWith("https://blank-test.supabase.co/rest/v1/wearable_connections") && options.method === "GET") {
      assert.match(target, /status=in\.\(connected,partial,no_data,stale,error\)/);
      return response(200, [connection]);
    }
    if (target === "https://health.googleapis.com/v4/users/me/profile") {
      return response(200, { resourceName: "users/me" });
    }
    if (target.includes("dataPoints:dailyRollUp")) {
      if (target.includes("/steps/")) return response(200, { rollupDataPoints: [{ steps: { countSum: 3000 } }] });
      return response(200, { rollupDataPoints: [] });
    }
    if (target.startsWith("https://blank-test.supabase.co/rest/v1/wearable_feature_snapshots")) {
      snapshotInserted = true;
      return response(201, null);
    }
    if (target.startsWith("https://blank-test.supabase.co/rest/v1/wearable_connections") && options.method === "PATCH") {
      return response(204, null);
    }
    if (target.startsWith("https://blank-test.supabase.co/rest/v1/digital_wellness_feature_payloads")) {
      return response(201, null);
    }
    throw new Error(`Unexpected request: ${url}`);
  };

  const result = await scheduledSyncHandler({ httpMethod: "POST", headers: {}, queryStringParameters: { limit: "10" } });
  const body = JSON.parse(result.body);
  assert.strictEqual(result.statusCode, 200, result.body);
  assert.strictEqual(body.synced, 1);
  assert.strictEqual(snapshotInserted, true);
}

(async () => {
  await refreshesExpiredTokenBeforeSync();
  await disconnectRevokesGoogleTokenBestEffort();
  await scheduledSyncProcessesDueConnections();
  console.log("wearable_platform_smoke_test: ok");
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
