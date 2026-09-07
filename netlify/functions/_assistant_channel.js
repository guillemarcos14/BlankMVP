const { supabaseFetch } = require("./_membership");

const EVENT_TABLE = "digital_wellness_feature_payloads";

function cleanText(value, maxLength = 240) {
  return String(value || "").trim().replace(/\s+/g, " ").slice(0, maxLength);
}

function cleanChannel(value) {
  const channel = cleanText(value, 20).toLowerCase();
  return channel === "whatsapp" || channel === "sms" ? channel : "";
}

function connectCodeFromText(text) {
  const match = cleanText(text, 80).match(/^connect\s+([a-z0-9-]{4,24})$/i);
  return match ? match[1].toUpperCase() : "";
}

function normalizeConnectCode(value) {
  return cleanText(value, 32).toUpperCase().replace(/[^A-Z0-9-]/g, "");
}

function assistantUserId(connectCode) {
  return `connect:${normalizeConnectCode(connectCode)}`;
}

async function recordAssistantChannel({ event, channel, connectCode, channelUser = "", userPhone = "", preferredChannel = "" }) {
  const normalizedCode = normalizeConnectCode(connectCode);
  if (!normalizedCode) return;
  const now = new Date().toISOString();
  await supabaseFetch(EVENT_TABLE, {
    method: "POST",
    headers: { prefer: "return=minimal" },
    body: JSON.stringify({
      anonymous_user_id: assistantUserId(normalizedCode),
      schema_version: 1,
      payload: {
        event,
        properties: {
          channel: cleanChannel(channel),
          preferred_channel: cleanChannel(preferredChannel) || cleanChannel(channel),
          connect_code: normalizedCode,
          channel_user: cleanText(channelUser, 120),
          user_phone: cleanText(userPhone, 80),
        },
      },
      insight: { event },
      platform: cleanChannel(channel) || cleanChannel(preferredChannel) || "assistant",
      locale: "",
      app_version: "",
      build_number: "",
      data_consent: true,
      consent_text: "Assistant channel connection",
      privacy_raw_health_samples_sent: false,
      privacy_raw_sleep_stage_timestamps_sent: false,
      privacy_exact_app_selection_sent: false,
      privacy_exact_location_sent: false,
      submitted_at: now,
    }),
  });
}

async function findAssistantConnection(connectCode, preferredChannel = "") {
  const normalizedCode = normalizeConnectCode(connectCode);
  if (!normalizedCode) return null;
  const rows = await supabaseFetch(
    `${EVENT_TABLE}?anonymous_user_id=eq.${encodeURIComponent(assistantUserId(normalizedCode))}&select=*&order=submitted_at.desc&limit=20`,
    { method: "GET" }
  );
  const preferred = cleanChannel(preferredChannel);
  const candidates = rows
    .map((row) => row.payload?.properties || {})
    .filter((props) => props.connect_code === normalizedCode);
  const connected = candidates.filter((props) => props.channel_user);
  const match = connected.find((props) => cleanChannel(props.channel) === preferred)
    || connected[0]
    || candidates.find((props) => cleanChannel(props.preferred_channel) === preferred)
    || candidates[0];
  if (!match) return null;
  const channel = cleanChannel(match.channel) || cleanChannel(match.preferred_channel) || preferred;
  const channelUser = cleanText(match.channel_user, 120);
  return channel && channelUser ? { channel, channelUser, connectCode: normalizedCode } : null;
}

async function sendSmsMessage(to, body) {
  const sid = process.env.TWILIO_ACCOUNT_SID;
  const token = process.env.TWILIO_AUTH_TOKEN;
  const from = process.env.TWILIO_FROM_NUMBER;
  const messagingServiceSid = process.env.TWILIO_MESSAGING_SERVICE_SID;
  if (!sid || !token || (!from && !messagingServiceSid)) {
    return { skipped: true, reason: "missing_sms_credentials" };
  }

  const params = new URLSearchParams();
  params.set("To", to);
  params.set("Body", body);
  if (messagingServiceSid) {
    params.set("MessagingServiceSid", messagingServiceSid);
  } else {
    params.set("From", from);
  }

  const response = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${encodeURIComponent(sid)}/Messages.json`, {
    method: "POST",
    headers: {
      authorization: `Basic ${Buffer.from(`${sid}:${token}`).toString("base64")}`,
      "content-type": "application/x-www-form-urlencoded",
    },
    body: params.toString(),
  });
  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`sms_send_failed_${response.status}:${detail.slice(0, 240)}`);
  }
  return response.json();
}

async function sendWhatsAppMessage(to, body) {
  const token = process.env.WHATSAPP_ACCESS_TOKEN;
  const phoneNumberId = process.env.WHATSAPP_PHONE_NUMBER_ID;
  if (!token || !phoneNumberId) {
    return { skipped: true, reason: "missing_whatsapp_credentials" };
  }

  const graphVersion = process.env.WHATSAPP_GRAPH_API_VERSION || "v26.0";
  const response = await fetch(`https://graph.facebook.com/${graphVersion}/${phoneNumberId}/messages`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      messaging_product: "whatsapp",
      to,
      type: "text",
      text: { preview_url: false, body },
    }),
  });
  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`whatsapp_send_failed_${response.status}:${detail.slice(0, 240)}`);
  }
  return response.json();
}

async function sendAssistantMessage(connection, body) {
  if (!connection) return { skipped: true, reason: "missing_connection" };
  if (connection.channel === "sms") return sendSmsMessage(connection.channelUser, body);
  if (connection.channel === "whatsapp") return sendWhatsAppMessage(connection.channelUser, body);
  return { skipped: true, reason: "unsupported_channel" };
}

module.exports = {
  cleanChannel,
  cleanText,
  connectCodeFromText,
  findAssistantConnection,
  normalizeConnectCode,
  recordAssistantChannel,
  sendAssistantMessage,
  sendSmsMessage,
  sendWhatsAppMessage,
};
