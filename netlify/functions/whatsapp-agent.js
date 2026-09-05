const crypto = require("crypto");
const { json, parseJsonBody, supabaseFetch } = require("./_membership");
const { handler: blankedAgentHandler } = require("./blanked-agent");

function cleanText(value, maxLength = 600) {
  return String(value || "").trim().replace(/\s+/g, " ").slice(0, maxLength);
}

function header(event, name) {
  const target = name.toLowerCase();
  const entries = Object.entries(event.headers || {});
  const match = entries.find(([key]) => key.toLowerCase() === target);
  return match ? match[1] : "";
}

function timingSafeEqual(left, right) {
  const leftBuffer = Buffer.from(left || "");
  const rightBuffer = Buffer.from(right || "");
  if (leftBuffer.length !== rightBuffer.length) return false;
  return crypto.timingSafeEqual(leftBuffer, rightBuffer);
}

function rawBody(event) {
  if (!event.body) return "";
  return event.isBase64Encoded ? Buffer.from(event.body, "base64").toString("utf8") : event.body;
}

function verifySignature(event) {
  const secret = process.env.WHATSAPP_APP_SECRET;
  if (!secret) return true;
  const signature = header(event, "x-hub-signature-256");
  if (!signature.startsWith("sha256=")) return false;
  const expected = `sha256=${crypto.createHmac("sha256", secret).update(rawBody(event), "utf8").digest("hex")}`;
  return timingSafeEqual(signature, expected);
}

function verifyChallenge(event) {
  const params = event.queryStringParameters || {};
  const token = process.env.WHATSAPP_VERIFY_TOKEN;
  if (params["hub.mode"] !== "subscribe" || !params["hub.challenge"]) {
    return json(400, { error: "invalid_whatsapp_challenge" });
  }
  if (!token || params["hub.verify_token"] !== token) {
    return json(403, { error: "invalid_whatsapp_verify_token" });
  }
  return {
    statusCode: 200,
    headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" },
    body: params["hub.challenge"],
  };
}

function incomingMessages(body) {
  const messages = [];
  for (const entry of body.entry || []) {
    for (const change of entry.changes || []) {
      const value = change.value || {};
      for (const message of value.messages || []) {
        const text = cleanText(message.text && message.text.body);
        if (!text) continue;
        messages.push({
          from: cleanText(message.from, 40),
          id: cleanText(message.id, 120),
          text,
        });
      }
    }
  }
  return messages;
}

function requestedAppNames(text) {
  const source = ` ${cleanText(text, 600).toLowerCase()} `;
  const candidates = [
    { keys: ["tiktok", "tik tok"], label: "TikTok" },
    { keys: ["instagram", "insta", " ig "], label: "Instagram" },
    { keys: [" x ", "twitter"], label: "X" },
    { keys: ["youtube", "yt", "youtube shorts"], label: "YouTube" },
    { keys: ["reddit"], label: "Reddit" },
    { keys: ["facebook"], label: "Facebook" },
    { keys: ["snapchat"], label: "Snapchat" },
  ];
  return candidates
    .map((candidate) => ({
      label: candidate.label,
      index: Math.min(...candidate.keys.map((key) => source.indexOf(key)).filter((index) => index >= 0)),
    }))
    .filter((candidate) => Number.isFinite(candidate.index))
    .sort((left, right) => left.index - right.index)
    .map((candidate) => candidate.label);
}

function appsQuery(appNames) {
  const names = Array.isArray(appNames) ? appNames.filter(Boolean).slice(0, 8) : [];
  return names.length ? `&apps=${encodeURIComponent(names.join(","))}` : "";
}

function appLink(action, appNames = []) {
  const scheme = process.env.BLANKED_APP_DEEP_LINK_SCHEME || "blank";
  const type = action && action.type;
  if (type === "start_protection") {
    const minutes = Number.isFinite(action.minutes) ? action.minutes : 30;
    const hard = action.hard_mode ? "&hard=1" : "";
    return `${scheme}://start-focus?minutes=${minutes}${hard}`;
  }
  if (type === "apply_schedule") {
    const start = Number.isFinite(action.start_minute) ? action.start_minute : null;
    const end = Number.isFinite(action.end_minute) ? action.end_minute : null;
    if (start == null || end == null) return "";
    const days = Number.isFinite(action.duration_days) ? action.duration_days : 7;
    if (appNames.length) return `${scheme}://setup-plan?start_minute=${start}&end_minute=${end}&days=${days}${appsQuery(appNames)}`;
    return `${scheme}://apply-plan?start_minute=${start}&end_minute=${end}&days=${days}`;
  }
  if (type === "enable_allow_only") return `${scheme}://allow-only`;
  if (type === "enable_adult_filter") return `${scheme}://adult-filter`;
  if (type === "set_daily_limit") return `${scheme}://daily-limit?minutes=${Number.isFinite(action.minutes) ? action.minutes : 25}`;
  if (type === "pause_rules") return `${scheme}://pause-rules?hours=${Number.isFinite(action.hours) ? action.hours : 168}`;
  if (type === "disable_pause") return `${scheme}://resume-rules`;
  if (type === "switch_mode" && action.name) return `${scheme}://mode?name=${encodeURIComponent(action.name)}`;
  if (type === "open_app_picker" || type === "request_screen_time_permission" || type === "apply_ai_plan") return `${scheme}://open-picker?source=assistant${appsQuery(appNames)}`;
  return "";
}

function actionableLink(plan, prompt = "") {
  const actions = Array.isArray(plan.actions) ? plan.actions : [];
  const appNames = requestedAppNames(prompt);
  for (const action of actions) {
    const link = appLink(action, appNames);
    if (link) return link;
  }
  return "";
}

function whatsappReplyText(plan, prompt = "") {
  const text = cleanText(plan.response_text, 280) || "I can help with that in Blanked.";
  const link = actionableLink(plan, prompt);
  if (!link) return text;
  return `${text}\n\nOpen Blanked to apply it:\n${link}`;
}

function agentContext() {
  return {
    channel: "whatsapp",
    is_blank_active: false,
    has_selected_apps: true,
    selection_count: 1,
    screen_time_authorized: true,
    emergency_unlocks_remaining: 3,
    vacation_mode_active: false,
    risk_window: "the usual risk window",
    recommended_duration_minutes: 30,
    memory: {},
  };
}

async function callBlankedAgent(prompt) {
  const response = await blankedAgentHandler({
    httpMethod: "POST",
    body: JSON.stringify({ prompt, context: agentContext() }),
  });
  const body = JSON.parse(response.body || "{}");
  if (response.statusCode < 200 || response.statusCode >= 300 || !body.ok) {
    throw new Error(body.error || "blanked_agent_failed");
  }
  return body.plan;
}

async function sendWhatsAppMessage(to, text) {
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
      text: { preview_url: false, body: text },
    }),
  });
  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`whatsapp_send_failed_${response.status}:${detail.slice(0, 240)}`);
  }
  return response.json();
}

function connectCodeFromText(text) {
  const match = cleanText(text, 80).match(/^connect\s+([a-z0-9-]{4,24})$/i);
  return match ? match[1].toUpperCase() : "";
}

async function recordAssistantConnection({ channel, connectCode, from }) {
  try {
    await supabaseFetch("digital_wellness_feature_payloads", {
      method: "POST",
      headers: { prefer: "return=minimal" },
      body: JSON.stringify({
        anonymous_user_id: `connect:${connectCode}`,
        schema_version: 1,
        payload: {
          event: "assistant_channel_connected",
          properties: {
            channel,
            connect_code: connectCode,
            channel_user: from,
          },
        },
        insight: { event: "assistant_channel_connected" },
        platform: channel,
        locale: "",
        app_version: "",
        build_number: "",
        data_consent: true,
        consent_text: "Assistant channel connection",
        privacy_raw_health_samples_sent: false,
        privacy_raw_sleep_stage_timestamps_sent: false,
        privacy_exact_app_selection_sent: false,
        privacy_exact_location_sent: false,
        submitted_at: new Date().toISOString(),
      }),
    });
  } catch (_) {
    return;
  }
}

async function processMessage(message) {
  const connectCode = connectCodeFromText(message.text);
  if (connectCode) {
    await recordAssistantConnection({ channel: "whatsapp", connectCode, from: message.from });
    return sendWhatsAppMessage(
      message.from,
      "Connected. Blanked will use this WhatsApp thread for your digital wellness assistant. Open the app to see blocks, Health, reports and settings."
    );
  }

  const command = message.text.toLowerCase();
  if (command === "stop" || command === "disconnect") {
    return sendWhatsAppMessage(message.from, "WhatsApp updates paused. Reconnect from Blanked when you want to use this channel again.");
  }
  const plan = await callBlankedAgent(message.text);
  return sendWhatsAppMessage(message.from, whatsappReplyText(plan, message.text));
}

exports.handler = async (event) => {
  if (event.httpMethod === "GET") return verifyChallenge(event);
  if (event.httpMethod === "OPTIONS") return { statusCode: 204, headers: json(200, {}).headers, body: "" };
  if (event.httpMethod !== "POST") return json(405, { error: "method_not_allowed" });
  if (!verifySignature(event)) return json(403, { error: "invalid_whatsapp_signature" });

  try {
    const body = parseJsonBody(event);
    const messages = incomingMessages(body);
    const results = [];
    for (const message of messages.slice(0, 5)) {
      results.push(await processMessage(message));
    }
    return json(200, { ok: true, received: messages.length, results });
  } catch (error) {
    return json(500, { error: "whatsapp_agent_failed", detail: error.message });
  }
};
