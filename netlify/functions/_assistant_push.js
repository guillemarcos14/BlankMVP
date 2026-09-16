const crypto = require("crypto");
const http2 = require("http2");

let cachedProviderToken = null;
let cachedProviderTokenAt = 0;

function base64url(value) {
  return Buffer.from(value).toString("base64url");
}

function normalizedPrivateKey() {
  return String(process.env.APNS_AUTH_KEY || "").replace(/\\n/g, "\n").trim();
}

function providerToken() {
  const now = Math.floor(Date.now() / 1000);
  if (cachedProviderToken && now - cachedProviderTokenAt < 45 * 60) return cachedProviderToken;
  const keyId = String(process.env.APNS_KEY_ID || "").trim();
  const teamId = String(process.env.APNS_TEAM_ID || "").trim();
  const privateKey = normalizedPrivateKey();
  if (!keyId || !teamId || !privateKey) return "";
  const header = base64url(JSON.stringify({ alg: "ES256", kid: keyId }));
  const claims = base64url(JSON.stringify({ iss: teamId, iat: now }));
  const unsigned = `${header}.${claims}`;
  const signature = crypto.sign("sha256", Buffer.from(unsigned), {
    key: privateKey,
    dsaEncoding: "ieee-p1363",
  }).toString("base64url");
  cachedProviderToken = `${unsigned}.${signature}`;
  cachedProviderTokenAt = now;
  return cachedProviderToken;
}

function normalizeDevicePush(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const token = String(value.token || "").replace(/[^a-fA-F0-9]/g, "").toLowerCase();
  if (token.length < 32 || token.length > 200) return null;
  return {
    token,
    environment: String(value.environment || "production").toLowerCase() === "sandbox" ? "sandbox" : "production",
    app_install_id: String(value.app_install_id || "").slice(0, 160),
    updated_at: String(value.updated_at || "").slice(0, 40),
  };
}

function pushPayload(action) {
  const needsForeground = ["open_app_picker", "request_screen_time_permission"].includes(action?.type);
  return {
    aps: {
      "content-available": 1,
      ...(needsForeground ? { alert: { title: "Blankmind", body: "Tap to finish selecting the apps for this block." } } : {}),
    },
    bm_action_id: String(action?.id || "").slice(0, 80),
    bm_action_type: String(action?.type || "").slice(0, 60),
  };
}

async function sendAssistantActionPush(devicePush, action) {
  const device = normalizeDevicePush(devicePush);
  const auth = providerToken();
  const topic = String(process.env.APNS_TOPIC || "com.blanknfc.app.ios").trim();
  if (!device) return { sent: false, reason: "missing_device_token" };
  if (!auth || !topic) return { sent: false, reason: "apns_not_configured" };
  const host = device.environment === "sandbox" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
  const body = JSON.stringify(pushPayload(action));
  const needsForeground = ["open_app_picker", "request_screen_time_permission"].includes(action?.type);

  return new Promise((resolve) => {
    const client = http2.connect(host);
    let settled = false;
    let timeout;
    const finish = (result) => {
      if (settled) return;
      settled = true;
      if (timeout) clearTimeout(timeout);
      client.close();
      resolve(result);
    };
    timeout = setTimeout(() => finish({ sent: false, reason: "apns_timeout" }), 5000);
    client.on("error", (error) => finish({ sent: false, reason: `apns_connection:${error.message}` }));
    const request = client.request({
      ":method": "POST",
      ":path": `/3/device/${device.token}`,
      authorization: `bearer ${auth}`,
      "apns-topic": topic,
      "apns-push-type": needsForeground ? "alert" : "background",
      "apns-priority": needsForeground ? "10" : "5",
      "apns-expiration": String(Math.floor(Date.now() / 1000) + 2 * 60 * 60),
      "content-type": "application/json",
    });
    let responseBody = "";
    let status = 0;
    request.setEncoding("utf8");
    request.on("response", (headers) => { status = Number(headers[":status"] || 0); });
    request.on("data", (chunk) => { responseBody += chunk; });
    request.on("end", () => finish(status === 200
      ? { sent: true, reason: "" }
      : { sent: false, reason: `apns_${status}:${responseBody.slice(0, 160)}` }));
    request.on("error", (error) => finish({ sent: false, reason: `apns_request:${error.message}` }));
    request.end(body);
  });
}

module.exports = { normalizeDevicePush, pushPayload, sendAssistantActionPush };
