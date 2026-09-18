const crypto = require("crypto");
const { sendAssistantActionPush } = require("./_assistant_push");
const { json, parseJsonBody } = require("./_membership");
const {
  attachAssistantUserContext,
  claimAssistantInboundMessage,
  connectCodeFromText,
  completeAssistantInboundMessage,
  releaseAssistantInboundMessage,
  ensureAssistantConnectionForPhone,
  getAssistantMemory,
  recordAssistantConversationTurn,
  recordAssistantChannel,
  recordAssistantMemory,
  sendWhatsAppMessage,
} = require("./_assistant_channel");
const { handler: blankedAgentHandler } = require("./blanked-agent");
const { freshConversationState } = require("./bm-context");
const { semanticPersistenceRequired } = require("./_bm_semantic_store");

const WHATSAPP_RUNTIME_CONTRACT = "bm-immediate-v4";

function cleanText(value, maxLength = 600) {
  return String(value || "").trim().replace(/\s+/g, " ").slice(0, maxLength);
}

function explicitDurationMinutes(text) {
  const match = cleanText(text, 600).toLowerCase().match(/(\d{1,3})\s*[-–]?\s*(?:min|mins|minute|minutes|minutos?)/i);
  if (!match) return null;
  return Math.min(Math.max(Number(match[1]), 5), 240);
}

function asksForDailyLimit(text) {
  const value = cleanText(text, 600).toLowerCase();
  return /\b(daily limit|per day|each day|every day|l[ií]mite diario|por d[ií]a)\b/i.test(value)
    || (/\b(limit|l[ií]mite|cap|tope)\b/i.test(value) && /\d+\s*(?:min|mins|minute|minutes|minutos?)/i.test(value));
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

function isProductionEnvironment() {
  return process.env.NODE_ENV === "production"
    || process.env.CONTEXT === "production"
    || process.env.NETLIFY === "true";
}

function audioExtension(contentType) {
  const type = cleanText(contentType, 120).toLowerCase();
  if (type.includes("ogg")) return "ogg";
  if (type.includes("mpeg") || type.includes("mp3")) return "mp3";
  if (type.includes("mp4") || type.includes("m4a")) return "m4a";
  if (type.includes("wav")) return "wav";
  if (type.includes("webm")) return "webm";
  if (type.includes("amr")) return "amr";
  return "audio";
}

async function transcribeMetaAudio(message) {
  const token = process.env.WHATSAPP_ACCESS_TOKEN;
  const mediaId = cleanText(message.audio_id, 160);
  const apiKey = process.env.OPENAI_API_KEY;
  if (!token || !mediaId) throw new Error("whatsapp_audio_media_not_configured");
  if (!apiKey) throw new Error("OPENAI_API_KEY is not configured");
  const graphVersion = process.env.WHATSAPP_GRAPH_API_VERSION || "v26.0";
  const mediaResponse = await fetch(`https://graph.facebook.com/${graphVersion}/${encodeURIComponent(mediaId)}`, {
    headers: { authorization: `Bearer ${token}` },
  });
  if (!mediaResponse.ok) throw new Error(`whatsapp_media_metadata_failed_${mediaResponse.status}`);
  const media = await mediaResponse.json();
  const mediaUrl = cleanText(media.url, 1600);
  if (!mediaUrl) throw new Error("whatsapp_media_url_missing");
  const audioResponse = await fetch(mediaUrl, {
    headers: { authorization: `Bearer ${token}` },
  });
  if (!audioResponse.ok) throw new Error(`whatsapp_media_download_failed_${audioResponse.status}`);
  const contentLength = Number(audioResponse.headers?.get?.("content-length") || 0);
  if (contentLength > 24 * 1024 * 1024) throw new Error("whatsapp_audio_too_large");
  const audio = Buffer.from(await audioResponse.arrayBuffer());
  if (audio.length > 24 * 1024 * 1024) throw new Error("whatsapp_audio_too_large");
  const contentType = cleanText(message.audio_content_type, 120) || "audio/ogg";
  const form = new FormData();
  form.append("model", process.env.OPENAI_TRANSCRIPTION_MODEL || "whisper-1");
  form.append("file", new Blob([audio], { type: contentType }), `whatsapp-audio.${audioExtension(contentType)}`);
  const transcriptionResponse = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: { authorization: `Bearer ${apiKey}` },
    body: form,
  });
  const raw = await transcriptionResponse.text();
  let parsed = {};
  try { parsed = raw ? JSON.parse(raw) : {}; } catch (_) { parsed = {}; }
  if (!transcriptionResponse.ok) throw new Error(`openai_transcription_failed_${transcriptionResponse.status}:${cleanText(parsed.error?.message || raw, 180)}`);
  const transcript = cleanText(parsed.text, 800);
  if (!transcript) throw new Error("whatsapp_transcription_empty");
  return transcript;
}

function verifySignature(event) {
  const secret = process.env.WHATSAPP_APP_SECRET;
  if (!secret) return !isProductionEnvironment() && process.env.WHATSAPP_REQUIRE_SIGNATURE !== "true";
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
    headers: {
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "no-store",
      "x-bm-runtime-contract": WHATSAPP_RUNTIME_CONTRACT,
    },
    body: params["hub.challenge"],
  };
}

function incomingMessages(body) {
  const messages = [];
  for (const entry of Array.isArray(body?.entry) ? body.entry : []) {
    if (!entry || typeof entry !== "object") continue;
    for (const change of Array.isArray(entry.changes) ? entry.changes : []) {
      if (!change || typeof change !== "object") continue;
      const value = change.value || {};
      for (const message of Array.isArray(value.messages) ? value.messages : []) {
        if (!message || typeof message !== "object") continue;
        const text = cleanText(
          (message.text && message.text.body)
          || (message.button && (message.button.text || message.button.payload))
          || (message.interactive && message.interactive.button_reply && (message.interactive.button_reply.title || message.interactive.button_reply.id))
          || (message.interactive && message.interactive.list_reply && (message.interactive.list_reply.title || message.interactive.list_reply.id))
        );
        const from = cleanText(message.from, 40);
        const audioId = cleanText(message.audio && message.audio.id, 160);
        const audioContentType = cleanText(message.audio && (message.audio.mime_type || message.audio.mimeType), 120);
        if ((!text && !audioId) || !from) continue;
        messages.push({
          from,
          id: cleanText(message.id, 120),
          text,
          audio_id: audioId,
          audio_content_type: audioContentType,
        });
      }
    }
  }
  return messages;
}

function acceptsProactiveUpdate(text) {
  return /^(yes|yes,?\s*(show|please)|show( me)?|tell me|show update|sure|go ahead|okay|ok)$/i.test(cleanText(text, 120));
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

function detectedLanguage(text) {
  const value = cleanText(text, 800).toLowerCase();
  return /[¿áéíóúñ]|\b(quiero|bloquea|bloquear|despues|después|comer|cenar|dormir|ayudame|ayúdame|consejo|redes sociales|hola|buenas|gracias|puedes|s[ií])\b/i.test(value)
    ? "es"
    : "en";
}

function messageLanguage(text, savedLanguage = "") {
  const value = cleanText(text, 120).toLowerCase();
  if (/^(?:sí|si|vale|perfecto?|gracias)\.?$/i.test(value)) return "es";
  if (/^(?:yes|yeah|yep|sure|thanks?)\.?$/i.test(value)) return "en";
  const neutralFollowup = /^(?:ok|okay|\d{1,2}(?::\d{2})?\s*(?:am|pm)?|usually\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)?|sobre\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)?)\.?$/i.test(value);
  if (neutralFollowup && /^es|^en/i.test(savedLanguage)) return savedLanguage.toLowerCase().startsWith("es") ? "es" : "en";
  return detectedLanguage(text);
}

const PENDING_ACTION_TYPES = new Set([
  "start_protection", "apply_schedule", "set_daily_limit",
  "enable_allow_only", "enable_adult_filter", "pause_rules", "disable_pause", "apply_ai_plan",
  "open_app_picker", "request_screen_time_permission",
]);

function pendingActionFromPlan(plan, prompt = "") {
  const action = (Array.isArray(plan.actions) ? plan.actions : [])
    .find((item) => item && PENDING_ACTION_TYPES.has(item.type));
  if (!action) return null;
  if (action.type === "apply_schedule" && (
    !Number.isInteger(action.start_minute)
    || !Number.isInteger(action.end_minute)
    || action.start_minute === action.end_minute
  )) return null;
  const createdAt = new Date().toISOString();
  const immediateDurationMs = action.type === "start_protection" && Number.isInteger(action.minutes)
    ? action.minutes * 60 * 1000
    : null;
  const expiresAt = new Date(Date.now() + (immediateDurationMs || 2 * 60 * 60 * 1000)).toISOString();
  const payload = {
    type: action.type,
    name: action.name || null,
    minutes: Number.isInteger(action.minutes) ? action.minutes : null,
    hard_mode: action.hard_mode === true,
    start_minute: Number.isInteger(action.start_minute) ? action.start_minute : null,
    end_minute: Number.isInteger(action.end_minute) ? action.end_minute : null,
    weekdays: Array.isArray(action.weekdays) ? action.weekdays : [],
    duration_days: Number.isInteger(action.duration_days) ? action.duration_days : null,
    hours: Number.isInteger(action.hours) ? action.hours : null,
    // App mentions remain conversational context only. Native execution always
    // targets the one canonical distraction selection.
    app_names: [],
  };
  const fingerprint = crypto.createHash("sha256").update(JSON.stringify(payload)).digest("hex").slice(0, 32);
  return {
    id: `wa_${Date.now().toString(36)}_${crypto.randomBytes(6).toString("hex")}`,
    contract_version: WHATSAPP_RUNTIME_CONTRACT,
    fingerprint,
    ...payload,
    status: "queued",
    summary: cleanText(plan.message_text || plan.response_text, 320),
    created_at: createdAt,
    requested_at: createdAt,
    expires_at: expiresAt,
  };
}

async function recordPushAttempt(connection, pending, pushResult) {
  const attempt = {
    action_id: pending.id,
    action_type: pending.type,
    sent: pushResult?.sent === true,
    reason: cleanText(pushResult?.reason, 200),
    status: Number(pushResult?.status || 0),
    apns_id: cleanText(pushResult?.apns_id, 80),
    attempted_at: pushResult?.accepted_at || pushResult?.attempted_at || new Date().toISOString(),
  };
  await recordAssistantMemory({
    channel: connection.channel,
    channelUser: connection.channelUser,
    memory: { last_assistant_push_attempt: attempt },
    source: attempt.sent ? "assistant_push_accepted" : "assistant_push_failed",
  });
  return attempt;
}

async function scheduleActionRetry(connection, pending) {
  const siteURL = String(process.env.URL || "").replace(/\/$/, "");
  const secret = String(process.env.WHATSAPP_APP_SECRET || "");
  if (!siteURL || !secret || !connection?.channelUser || !pending?.id) return { scheduled: false };
  const message = `${connection.channel}:${connection.channelUser}:${pending.id}`;
  const signature = crypto.createHmac("sha256", secret).update(message).digest("hex");
  try {
    const response = await fetch(`${siteURL}/.netlify/functions/assistant-action-retry-background`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ channel: connection.channel, channel_user: connection.channelUser, action_id: pending.id, signature }),
    });
    return { scheduled: response.ok, status: response.status };
  } catch (error) {
    return { scheduled: false, reason: cleanText(error.message, 160) };
  }
}

function canReusePendingAction(existing, pending, now = Date.now()) {
  const requestedAt = Date.parse(existing?.requested_at || "");
  const expiresAt = Date.parse(existing?.expires_at || "");
  return existing?.fingerprint === pending?.fingerprint
    && Number.isFinite(requestedAt)
    && Number.isFinite(expiresAt)
    && requestedAt <= now
    && expiresAt > now;
}

async function queuePendingAssistantAction(connection, plan, prompt = "") {
  if (!connection?.connectCode) return null;
  const pending = pendingActionFromPlan(plan, prompt);
  if (!pending) return null;
  let memory = {};
  try {
    memory = await getAssistantMemory(connection.channel, connection.channelUser);
  } catch (error) {
    if (semanticPersistenceRequired()) throw error;
  }
  const existing = memory.pending_assistant_action;
  if (canReusePendingAction(existing, pending)) {
    let pushResult;
    try { pushResult = await sendAssistantActionPush(memory.assistant_device_push, existing); }
    catch (error) { pushResult = { sent: false, reason: `push_exception:${error.message}` }; }
    const push = await recordPushAttempt(connection, existing, pushResult);
    await scheduleActionRetry(connection, existing);
    return { action: existing, push, duplicate: true };
  }
  await recordAssistantMemory({
    channel: connection.channel,
    channelUser: connection.channelUser,
    memory: { pending_assistant_action: pending },
    source: "assistant_action_pending",
  });
  let pushResult;
  try { pushResult = await sendAssistantActionPush(memory.assistant_device_push, pending); }
  catch (error) { pushResult = { sent: false, reason: `push_exception:${error.message}` }; }
  const push = await recordPushAttempt(connection, pending, pushResult);
  await scheduleActionRetry(connection, pending);
  return { action: pending, push, duplicate: false };
}

function whatsappReplyText(plan, delivery = null) {
  const action = (Array.isArray(plan.actions) ? plan.actions : []).find((item) => item && PENDING_ACTION_TYPES.has(item.type));
  const text = cleanText(plan.message_text || plan.response_text, 480)
    .replace(/(?:https?|blank):\/\/\S+/gi, "")
    .replace(/(?:open|abre|abrir)\s+(?:blankmind|blanked)[^.?!]*(?:[.?!]|$)/gi, "")
    .replace(/[^.?!]*(?:review|revisa|revisar)[^.?!]*(?:blankmind|blanked)[^.?!]*(?:[.?!]|$)/gi, "")
    .replace(/\s{2,}/g, " ")
    .trim()
    .slice(0, 320) || "I can help with that in Blanked.";
  if (!action) return text;
  const spanish = String(plan.response_language || plan.semantic_state?.language || "").toLowerCase().startsWith("es");
  if (action.type === "open_app_picker") {
    return `${text}\n\n${spanish ? "Abre Blankmind para seleccionar las apps. El plan se aplicará al confirmar la selección." : "Open Blankmind to choose the apps. The plan will apply when you confirm the selection."}`;
  }
  if (action.type === "request_screen_time_permission") {
    return `${text}\n\n${spanish ? "Abre Blankmind para que iOS compruebe el permiso de Tiempo de uso. No necesitas volver a elegir las apps." : "Open Blankmind so iOS can verify Screen Time permission. You do not need to choose the apps again."}`;
  }
  if (delivery?.push?.sent === false) {
    return `${text}\n\n${spanish ? "No he podido despertar el iPhone ahora. La orden queda pendiente hasta que iOS permita ejecutarla; no la confirmaré como aplicada sin evidencia del dispositivo." : "I couldn't wake the iPhone now. The request remains pending until iOS allows it to run; I won't confirm it as applied without device evidence."}`;
  }
  if (!/\b(?:applying|aplicando|executing|ejecutando)\b/i.test(text)) return `${text}\n\n${spanish ? "Lo estoy aplicando ahora." : "I'm applying it now."}`;
  return text;
}

async function sendPlanReply(to, plan, delivery = null) {
  return sendWhatsAppMessage(to, whatsappReplyText(plan, delivery));
}

function minuteOfDay(hour, minute, meridiem) {
  if (!Number.isFinite(hour) || hour < 1 || hour > 12 || !Number.isFinite(minute) || minute < 0 || minute > 59) return null;
  const normalized = meridiem === "pm" && hour !== 12 ? hour + 12 : meridiem === "am" && hour === 12 ? 0 : hour;
  return normalized * 60 + minute;
}

function mealEndMinute(text, terms) {
  const value = cleanText(text, 800).toLowerCase();
  if (!terms.test(value)) return null;
  const matches = [...value.matchAll(/(\d{1,2})(?::(\d{2}))?\s*(am|pm)?/gi)];
  if (!matches.length) return null;
  const match = matches[matches.length - 1];
  const hour = Number(match[1]);
  const meridiem = match[3] || (hour >= 8 && hour <= 11 ? "am" : "pm");
  return minuteOfDay(hour, Number(match[2] || 0), meridiem);
}

function breakfastEndMinute(text) {
  return mealEndMinute(text, /(breakfast|desayuno|desayunar)/i);
}

function lunchEndMinute(text) {
  return mealEndMinute(text, /(lunch|comida|comer|almuerzo)/i);
}

function memoryFactsFromText(text, savedMemory = {}) {
  const value = cleanText(text, 800).toLowerCase();
  const apps = requestedAppNames(text);
  const minutes = explicitDurationMinutes(text);
  const breakfastMinute = breakfastEndMinute(text);
  const lunchMinute = lunchEndMinute(text);
  const facts = {};
  if (/(sleep|bed|night|dormir|duermo|cama|noche)/i.test(value)) facts.last_topic = "sleep";
  else if (/(scroll|social|instagram|tiktok|youtube|reddit|reels|shorts|redes)/i.test(value)) facts.last_topic = "social";
  else if (/(focus|work|study|foco|trabaj|estudi)/i.test(value)) facts.last_topic = "focus";
  if (apps.length) facts.main_apps = apps;
  if (lunchMinute != null) {
    facts.lunch_end_minute = lunchMinute;
    facts.weak_hours = [Math.floor(lunchMinute / 60)];
  }
  if (breakfastMinute != null) {
    facts.breakfast_end_minute = breakfastMinute;
    facts.weak_hours = [Math.floor(breakfastMinute / 60)];
  }
  if (savedMemory.pending_action === "set_daily_limit" && minutes != null) {
    facts.pending_action = "";
    facts.pending_app_names = [];
  } else if (asksForDailyLimit(text) && minutes == null) {
    facts.pending_action = "set_daily_limit";
    facts.pending_app_names = apps.length
      ? apps
      : (Array.isArray(savedMemory.main_apps) ? savedMemory.main_apps.slice(0, 8) : []);
  }
  return facts;
}

async function agentContext(from, prompt) {
  let savedMemory = {};
  try {
    savedMemory = await getAssistantMemory("whatsapp", from);
  } catch (error) {
    if (semanticPersistenceRequired()) throw error;
    savedMemory = {};
  }
  const newFacts = memoryFactsFromText(prompt, savedMemory);
  const language = messageLanguage(prompt, savedMemory.language);
  const conversationState = freshConversationState(savedMemory.conversation_state);
  const memory = {
    ...savedMemory,
    ...newFacts,
    language,
    main_apps: newFacts.main_apps || savedMemory.main_apps,
    weak_hours: newFacts.weak_hours || savedMemory.weak_hours,
    conversation_state: conversationState,
  };
  const userContext = savedMemory.user_context && typeof savedMemory.user_context === "object"
    ? savedMemory.user_context
    : {};
  if (Object.keys(newFacts).length) {
    try {
      await recordAssistantMemory({ channel: "whatsapp", channelUser: from, memory: { ...newFacts, language }, source: prompt });
    } catch (_) {
      // Memory must never block a reply.
    }
  }
  return {
    ...userContext,
    channel: "whatsapp",
    assistant_channel: "whatsapp",
    language,
    allow_spanish_response: true,
    is_blank_active: userContext.is_blank_active === undefined ? false : userContext.is_blank_active,
    has_selected_apps: userContext.has_selected_apps === true,
    selection_count: Number.isFinite(userContext.selection_count) ? userContext.selection_count : 0,
    screen_time_authorized: userContext.screen_time_authorized === true,
    emergency_unlocks_remaining: Number.isFinite(userContext.emergency_unlocks_remaining) ? userContext.emergency_unlocks_remaining : 3,
    vacation_mode_active: userContext.vacation_mode_active === undefined ? false : userContext.vacation_mode_active,
    risk_window: userContext.risk_window || "the usual risk window",
    recommended_duration_minutes: Number.isFinite(userContext.recommended_duration_minutes) ? userContext.recommended_duration_minutes : 30,
    user_context: userContext,
    memory,
    recent_messages: conversationState?.recent_messages || [],

  };
}

async function callBlankedAgent(prompt, from) {
  const context = await agentContext(from, prompt);
  const response = await blankedAgentHandler({
    httpMethod: "POST",
    body: JSON.stringify({ prompt, context }),
  });
  const body = JSON.parse(response.body || "{}");
  if (response.statusCode < 200 || response.statusCode >= 300 || !body.ok) {
    throw new Error(body.error || "blanked_agent_failed");
  }
  return { plan: body.plan, context };
}

async function recordAssistantConnection({ channel, connectCode, from }) {
  try {
    await recordAssistantChannel({
      event: "assistant_channel_connected",
      channel,
      connectCode,
      channelUser: from,
    });
    await recordAssistantMemory({
      channel,
      channelUser: from,
      memory: {
        proactive_updates_paused: false,
        assistant_connect_code: String(connectCode || "").toUpperCase(),
        pending_assistant_action: null,
      },
      source: "assistant_channel_connected",
    });
    await attachAssistantUserContext({ connectCode, channel, channelUser: from });
  } catch (_) {
    return;
  }
}

async function processMessage(message) {
  let prompt = message.text;
  if (message.audio_id) {
    try {
      const transcript = await transcribeMetaAudio(message);
      prompt = prompt ? `${prompt}\n${transcript}` : transcript;
    } catch (_) {
      return sendWhatsAppMessage(message.from, "I could not understand that voice note yet. Send it as text or try another audio.");
    }
  }
  if (!prompt) return sendWhatsAppMessage(message.from, "I could not read that message yet. Send it as text or try another audio.");
  const connectCode = connectCodeFromText(prompt);
  if (connectCode) {
    await recordAssistantConnection({ channel: "whatsapp", connectCode, from: message.from });
    return sendWhatsAppMessage(
      message.from,
      "Hey! Blanked here 👋 Connected. This WhatsApp thread is now linked to your digital wellness assistant. Open the app to see blocks, Health, reports and settings."
    );
  }

  let linkedConnection = null;
  try {
    linkedConnection = await ensureAssistantConnectionForPhone({ channel: "whatsapp", channelUser: message.from });
  } catch (_) {
    // Automatic identity matching is additive; legacy CONNECT remains available.
  }

  const command = prompt.toLowerCase();
  if (command === "stop" || command === "disconnect") {
    await recordAssistantMemory({
      channel: "whatsapp",
      channelUser: message.from,
      memory: {
        proactive_updates_paused: true,
        pending_proactive_message: "",
        pending_assistant_action: null,
      },
      source: "assistant_channel_paused",
    });
    return sendWhatsAppMessage(message.from, "WhatsApp updates paused. Reconnect from Blanked when you want to use this channel again.");
  }
  let pendingMemory = {};
  try {
    pendingMemory = await getAssistantMemory("whatsapp", message.from);
  } catch (_) {
    pendingMemory = {};
  }
  if (!linkedConnection && pendingMemory.assistant_connect_code) {
    linkedConnection = {
      channel: "whatsapp",
      channelUser: message.from,
      connectCode: String(pendingMemory.assistant_connect_code).toUpperCase(),
    };
  }
  const pendingMessage = cleanText(pendingMemory.pending_proactive_message, 900);
  if (pendingMessage && acceptsProactiveUpdate(prompt)) {
    await recordAssistantMemory({
      channel: "whatsapp",
      channelUser: message.from,
      memory: { pending_proactive_message: "", pending_proactive_update_key: "", pending_proactive_sent_at: "" },
      source: "assistant_proactive_opened",
    });
    return sendWhatsAppMessage(message.from, pendingMessage);
  }
  const result = await callBlankedAgent(prompt, message.from);
  const plan = result.plan;
  try {
    await recordAssistantConversationTurn({
      channel: "whatsapp",
      channelUser: message.from,
      previousState: result.context.memory?.conversation_state,
      userMessage: prompt,
      assistantMessage: plan.message_text || plan.response_text || "",
      semanticState: plan.semantic_state,
      expectedVersion: result.context.memory?.semantic_store_version,
      topic: result.context.memory?.last_topic || "",
    });
  } catch (error) {
    if (semanticPersistenceRequired()) throw error;
    // Short-term memory must never block the user-facing reply.
  }
  if (plan.blocking_user_request === true) {
    try {
      await recordAssistantMemory({
        channel: "whatsapp",
        channelUser: message.from,
        memory: {
          pending_blocking: plan.blocking_ready === false
            ? { ...(plan.blocking_data || {}), updated_at: new Date().toISOString() }
            : null,
        },
        source: plan.blocking_ready === false ? "blocking_details_requested" : "blocking_contract_completed",
      });
    } catch (_) {
      // Pending blocking state must never block the user-facing reply.
    }
  }
  let queued = null;
  try {
    queued = await queuePendingAssistantAction(linkedConnection, plan, prompt);
    const invalidatesQueuedAction = plan.semantic_state?.intent === "cancelled"
      || (plan.semantic_state?.intent === "block" && ["collecting", "awaiting_confirmation"].includes(plan.semantic_state?.status));
    if (!queued && linkedConnection?.connectCode && invalidatesQueuedAction) {
      await recordAssistantMemory({
        channel: linkedConnection.channel,
        channelUser: linkedConnection.channelUser,
        memory: { pending_assistant_action: null },
        source: "assistant_action_invalidated",
      });
    }
  } catch (error) {
    if (semanticPersistenceRequired()) throw error;
  }
  return sendPlanReply(message.from, plan, queued);
}

exports.handler = async (event) => {
  if (event.httpMethod === "GET") return verifyChallenge(event);
  if (event.httpMethod === "OPTIONS") return { statusCode: 204, headers: json(200, {}).headers, body: "" };
  if (event.httpMethod !== "POST") return json(405, { error: "method_not_allowed" });
  if (!verifySignature(event)) return json(403, { error: "invalid_whatsapp_signature" });

  try {
    const body = parseJsonBody(event);
    if (!body || typeof body !== "object" || Array.isArray(body)) return json(400, { error: "invalid_whatsapp_payload" });
    const messages = incomingMessages(body);
    const results = [];
    const seenInRequest = new Set();
    for (const message of messages.slice(0, 5)) {
      if (message.id) {
        if (seenInRequest.has(message.id)) {
          results.push({ skipped: true, reason: "duplicate_inbound" });
          continue;
        }
        seenInRequest.add(message.id);
        try {
          const claim = await claimAssistantInboundMessage("whatsapp", message.from, message.id);
          if (!claim.claimed) {
            results.push({ skipped: true, reason: "duplicate_inbound" });
            continue;
          }
        } catch (_) {
          // A temporary memory outage must not discard an inbound message.
        }
      }
      let result;
      try {
        result = await processMessage(message);
      } catch (error) {
        try { await releaseAssistantInboundMessage("whatsapp", message.from, message.id); } catch (_) { /* Return failure; never deliver an uncommitted action. */ }
        throw error;
      }
      results.push(result);
      const deliveryFailed = result?.skipped === true && /credentials|template_requires/i.test(result.reason || "")
        || result?.text?.skipped === true && /credentials|template_requires/i.test(result.text.reason || "");
      if (message.id && !deliveryFailed) {
        try {
          await completeAssistantInboundMessage("whatsapp", message.from, message.id);
        } catch (_) {
          // Inbound idempotency is best effort when memory persistence is unavailable.
        }
      }
    }
    return json(200, { ok: true, received: Math.min(messages.length, 5), results });
  } catch (error) {
    return json(500, { error: "whatsapp_agent_failed", detail: error.message });
  }
};

exports._test = { canReusePendingAction, whatsappReplyText };
