const crypto = require("crypto");
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

function assistantChannelUserId(channel, channelUser) {
  const key = `${cleanChannel(channel)}:${cleanText(channelUser, 160)}`;
  const hash = crypto.createHash("sha256").update(key).digest("hex").slice(0, 32);
  return `assistant:${hash}`;
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

async function recordAssistantMemory({ channel, channelUser, memory = {}, source = "" }) {
  const normalizedChannel = cleanChannel(channel);
  const normalizedUser = cleanText(channelUser, 160);
  if (!normalizedChannel || !normalizedUser || !memory || !Object.keys(memory).length) return;
  const now = new Date().toISOString();
  await supabaseFetch(EVENT_TABLE, {
    method: "POST",
    headers: { prefer: "return=minimal" },
    body: JSON.stringify({
      anonymous_user_id: assistantChannelUserId(normalizedChannel, normalizedUser),
      schema_version: 1,
      payload: {
        event: "assistant_memory_updated",
        properties: {
          channel: normalizedChannel,
          memory,
          source: cleanText(source, 240),
        },
      },
      insight: { event: "assistant_memory_updated" },
      platform: normalizedChannel,
      locale: "",
      app_version: "",
      build_number: "",
      data_consent: true,
      consent_text: "Assistant personal memory from user-provided chat data",
      privacy_raw_health_samples_sent: false,
      privacy_raw_sleep_stage_timestamps_sent: false,
      privacy_exact_app_selection_sent: false,
      privacy_exact_location_sent: false,
      submitted_at: now,
    }),
  });
}

async function getAssistantMemory(channel, channelUser) {
  const normalizedChannel = cleanChannel(channel);
  const normalizedUser = cleanText(channelUser, 160);
  if (!normalizedChannel || !normalizedUser) return {};
  const rows = await supabaseFetch(
    `${EVENT_TABLE}?anonymous_user_id=eq.${encodeURIComponent(assistantChannelUserId(normalizedChannel, normalizedUser))}&select=payload,submitted_at&order=submitted_at.desc&limit=20`,
    { method: "GET" }
  );
  return rows.reverse().reduce((memory, row) => {
    const next = row.payload?.properties?.memory;
    if (!next || typeof next !== "object") return memory;
    return {
      ...memory,
      ...next,
      main_apps: Array.isArray(next.main_apps) ? next.main_apps : memory.main_apps,
      weak_hours: Array.isArray(next.weak_hours) ? next.weak_hours : memory.weak_hours,
    };
  }, {});
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
  const twilioSid = process.env.TWILIO_ACCOUNT_SID;
  const twilioToken = process.env.TWILIO_AUTH_TOKEN;
  const twilioFrom = process.env.TWILIO_WHATSAPP_FROM_NUMBER;
  if (twilioSid && twilioToken && twilioFrom) {
    const params = new URLSearchParams();
    const normalizedTo = String(to || "").startsWith("whatsapp:") ? to : `whatsapp:+${String(to || "").replace(/^\+/, "")}`;
    const normalizedFrom = String(twilioFrom).startsWith("whatsapp:") ? twilioFrom : `whatsapp:${twilioFrom}`;
    params.set("To", normalizedTo);
    params.set("From", normalizedFrom);
    params.set("Body", body);

    const response = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${encodeURIComponent(twilioSid)}/Messages.json`, {
      method: "POST",
      headers: {
        authorization: `Basic ${Buffer.from(`${twilioSid}:${twilioToken}`).toString("base64")}`,
        "content-type": "application/x-www-form-urlencoded",
      },
      body: params.toString(),
    });
    if (!response.ok) {
      const detail = await response.text();
      throw new Error(`twilio_whatsapp_send_failed_${response.status}:${detail.slice(0, 240)}`);
    }
    return response.json();
  }

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
  getAssistantMemory,
  normalizeConnectCode,
  recordAssistantChannel,
  recordAssistantMemory,
  sendAssistantMessage,
  sendSmsMessage,
  sendWhatsAppMessage,
};
