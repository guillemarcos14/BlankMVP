const crypto = require("crypto");
const { json, parseJsonBody } = require("./_membership");
const {
  connectCodeFromText,
  getAssistantMemory,
  recordAssistantChannel,
  recordAssistantMemory,
  sendWhatsAppMessage,
} = require("./_assistant_channel");
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

function publicOpenLink(deepLink) {
  return `https://getblank.netlify.app/open.html?to=${encodeURIComponent(deepLink)}`;
}

function appLink(action, appNames = []) {
  const scheme = process.env.BLANKED_APP_DEEP_LINK_SCHEME || "blank";
  const type = action && action.type;
  let deepLink = "";
  if (type === "start_protection") {
    const minutes = Number.isFinite(action.minutes) ? action.minutes : 30;
    const hard = action.hard_mode ? "&hard=1" : "";
    deepLink = `${scheme}://start-focus?minutes=${minutes}${hard}`;
  }
  else if (type === "apply_schedule") {
    const start = Number.isFinite(action.start_minute) ? action.start_minute : null;
    const end = Number.isFinite(action.end_minute) ? action.end_minute : null;
    if (start == null || end == null) return "";
    const days = Number.isFinite(action.duration_days) ? action.duration_days : 7;
    deepLink = appNames.length
      ? `${scheme}://setup-plan?start_minute=${start}&end_minute=${end}&days=${days}${appsQuery(appNames)}`
      : `${scheme}://apply-plan?start=${start}&end=${end}&days=${days}`;
  }
  else if (type === "enable_allow_only") deepLink = `${scheme}://allow-only`;
  else if (type === "enable_adult_filter") deepLink = `${scheme}://adult-filter`;
  else if (type === "set_daily_limit") deepLink = `${scheme}://daily-limit?minutes=${Number.isFinite(action.minutes) ? action.minutes : 25}`;
  else if (type === "pause_rules") deepLink = `${scheme}://pause-rules?hours=${Number.isFinite(action.hours) ? action.hours : 168}`;
  else if (type === "disable_pause") deepLink = `${scheme}://resume-rules`;
  else if (type === "switch_mode" && action.name) deepLink = `${scheme}://mode?name=${encodeURIComponent(action.name)}`;
  else if (type === "open_app_picker" || type === "request_screen_time_permission" || type === "apply_ai_plan") deepLink = `${scheme}://open-picker?source=assistant${appsQuery(appNames)}`;
  return deepLink ? publicOpenLink(deepLink) : "";
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
  const text = cleanText(plan.message_text || plan.response_text, 320) || "I can help with that in Blanked.";
  const link = actionableLink(plan, prompt);
  if (!link) return text;
  return `${text}\n\nOpen Blanked to apply it:\n${link}`;
}

function minuteOfDay(hour, minute, meridiem) {
  if (!Number.isFinite(hour) || hour < 1 || hour > 12 || !Number.isFinite(minute) || minute < 0 || minute > 59) return null;
  const normalized = meridiem === "pm" && hour !== 12 ? hour + 12 : meridiem === "am" && hour === 12 ? 0 : hour;
  return normalized * 60 + minute;
}

function lunchEndMinute(text) {
  const value = cleanText(text, 800).toLowerCase();
  if (!/(lunch|comida|comer|almuerzo)/i.test(value)) return null;
  const matches = [...value.matchAll(/(\d{1,2})(?::(\d{2}))?\s*(am|pm)?/gi)];
  if (!matches.length) return null;
  const match = matches[matches.length - 1];
  const hour = Number(match[1]);
  const meridiem = match[3] || (hour >= 8 && hour <= 11 ? "am" : "pm");
  return minuteOfDay(hour, Number(match[2] || 0), meridiem);
}

function memoryFactsFromText(text) {
  const apps = requestedAppNames(text);
  const lunchMinute = lunchEndMinute(text);
  const facts = {};
  if (apps.length) facts.main_apps = apps;
  if (lunchMinute != null) {
    facts.lunch_end_minute = lunchMinute;
    facts.weak_hours = [Math.floor(lunchMinute / 60)];
  }
  return facts;
}

async function agentContext(from, prompt) {
  let savedMemory = {};
  try {
    savedMemory = await getAssistantMemory("whatsapp", from);
  } catch (_) {
    savedMemory = {};
  }
  const newFacts = memoryFactsFromText(prompt);
  const memory = {
    ...savedMemory,
    ...newFacts,
    main_apps: newFacts.main_apps || savedMemory.main_apps,
    weak_hours: newFacts.weak_hours || savedMemory.weak_hours,
  };
  if (Object.keys(newFacts).length) {
    try {
      await recordAssistantMemory({ channel: "whatsapp", channelUser: from, memory: newFacts, source: prompt });
    } catch (_) {
      // Memory must never block a reply.
    }
  }
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
    memory,
  };
}

async function callBlankedAgent(prompt, from) {
  const response = await blankedAgentHandler({
    httpMethod: "POST",
    body: JSON.stringify({ prompt, context: await agentContext(from, prompt) }),
  });
  const body = JSON.parse(response.body || "{}");
  if (response.statusCode < 200 || response.statusCode >= 300 || !body.ok) {
    throw new Error(body.error || "blanked_agent_failed");
  }
  return body.plan;
}

async function recordAssistantConnection({ channel, connectCode, from }) {
  try {
    await recordAssistantChannel({
      event: "assistant_channel_connected",
      channel,
      connectCode,
      channelUser: from,
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
  const plan = await callBlankedAgent(message.text, message.from);
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
