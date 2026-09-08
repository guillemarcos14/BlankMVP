const { cleanText } = require("./_assistant_channel");

function parseFormBody(event) {
  const raw = event.isBase64Encoded ? Buffer.from(event.body || "", "base64").toString("utf8") : event.body || "";
  return Object.fromEntries(new URLSearchParams(raw).entries());
}

function xml(statusCode, body) {
  return {
    statusCode,
    headers: { "content-type": "application/xml; charset=utf-8" },
    body,
  };
}

function json(statusCode, body) {
  return {
    statusCode,
    headers: { "content-type": "application/json; charset=utf-8" },
    body: JSON.stringify(body),
  };
}

function twilioConfig() {
  return {
    sid: process.env.TWILIO_ACCOUNT_SID,
    token: process.env.TWILIO_AUTH_TOKEN,
    from: process.env.TWILIO_VOICE_FROM_NUMBER || process.env.TWILIO_FROM_NUMBER,
  };
}

function elevenLabsConfig() {
  return {
    apiKey: process.env.ELEVENLABS_CONVAI_API_KEY,
    agentId: process.env.ELEVENLABS_AGENT_ID,
  };
}

function publicBaseUrl(event) {
  const configured = cleanText(process.env.BLANKED_PUBLIC_APP_LINK_BASE, 240).replace(/\/$/, "");
  if (configured) return configured;
  const host = event?.headers?.host || event?.headers?.Host || "getblank.netlify.app";
  const proto = event?.headers?.["x-forwarded-proto"] || event?.headers?.["X-Forwarded-Proto"] || "https";
  return `${proto}://${host}`;
}

function basicAuth(sid, token) {
  return `Basic ${Buffer.from(`${sid}:${token}`).toString("base64")}`;
}

function requireCallAdmin(event) {
  const configured = process.env.BAI_CALL_ADMIN_SECRET;
  if (!configured) return { ok: false, response: json(503, { error: "call_admin_not_configured" }) };
  const provided =
    event.headers?.["x-bai-call-secret"] ||
    event.headers?.["X-BAI-Call-Secret"] ||
    event.queryStringParameters?.secret ||
    "";
  if (provided !== configured) return { ok: false, response: json(401, { error: "unauthorized" }) };
  return { ok: true };
}

function twilioVoiceUrl(event, direction = "inbound") {
  const params = new URLSearchParams({ direction });
  return `${publicBaseUrl(event)}/.netlify/functions/bai-call-twiml?${params.toString()}`;
}

async function registerElevenLabsCall({ fromNumber, toNumber, direction }) {
  const config = elevenLabsConfig();
  if (!config.apiKey || !config.agentId) {
    throw new Error("elevenlabs_call_not_configured");
  }

  const response = await fetch("https://api.elevenlabs.io/v1/convai/twilio/register-call", {
    method: "POST",
    headers: {
      "xi-api-key": config.apiKey,
      "content-type": "application/json",
      accept: "application/xml",
    },
    body: JSON.stringify({
      agent_id: config.agentId,
      from_number: cleanText(fromNumber, 80),
      to_number: cleanText(toNumber, 80),
      direction: direction === "outbound" ? "outbound" : "inbound",
      conversation_initiation_client_data: {
        dynamic_variables: {
          caller_number: cleanText(fromNumber, 80),
          called_number: cleanText(toNumber, 80),
          assistant_channel: "voice_call",
        },
      },
    }),
  });

  const body = await response.text();
  if (!response.ok) {
    throw new Error(`elevenlabs_register_call_failed_${response.status}:${cleanText(body, 240)}`);
  }
  return body;
}

async function twilioRequest(path, params) {
  const config = twilioConfig();
  if (!config.sid || !config.token) {
    throw new Error("twilio_voice_not_configured");
  }
  const response = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${encodeURIComponent(config.sid)}${path}`, {
    method: "POST",
    headers: {
      authorization: basicAuth(config.sid, config.token),
      "content-type": "application/x-www-form-urlencoded",
    },
    body: params.toString(),
  });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`twilio_voice_failed_${response.status}:${cleanText(text, 300)}`);
  }
  try {
    return JSON.parse(text);
  } catch {
    return { raw: text };
  }
}

module.exports = {
  json,
  parseFormBody,
  publicBaseUrl,
  registerElevenLabsCall,
  requireCallAdmin,
  twilioConfig,
  twilioRequest,
  twilioVoiceUrl,
  xml,
};
