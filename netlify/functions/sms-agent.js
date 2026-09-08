const { json, requireMethod } = require("./_membership");
const { handler: blankedAgentHandler } = require("./blanked-agent");
const {
  connectCodeFromText,
  getAssistantMemory,
  recordAssistantChannel,
  recordAssistantMemory,
} = require("./_assistant_channel");
const { buildSignedAudioUrl } = require("./_elevenlabs_voice");

function text(statusCode, body, contentType = "text/plain; charset=utf-8") {
  return {
    statusCode,
    headers: {
      "content-type": contentType,
      "cache-control": "no-store",
    },
    body,
  };
}

function rawBody(event) {
  if (!event.body) return "";
  return event.isBase64Encoded
    ? Buffer.from(event.body, "base64").toString("utf8")
    : event.body;
}

function parseSmsBody(event) {
  const headers = event.headers || {};
  const contentType = headers["content-type"] || headers["Content-Type"] || "";
  const raw = rawBody(event);
  if (contentType.includes("application/json")) {
    try {
      const parsed = JSON.parse(raw || "{}");
      const media = mediaItemsFromObject(parsed);
      return {
        from: cleanText(parsed.from || parsed.From, 80),
        body: cleanText(parsed.body || parsed.Body || parsed.text, 800),
        messageSid: cleanText(parsed.messageSid || parsed.MessageSid || parsed.SmsMessageSid, 80),
        media,
      };
    } catch {
      return { from: "", body: "", messageSid: "", media: [] };
    }
  }

  const params = new URLSearchParams(raw);
  const media = mediaItemsFromParams(params);
  return {
    from: cleanText(params.get("From") || params.get("from"), 80),
    body: cleanText(params.get("Body") || params.get("body"), 800),
    messageSid: cleanText(params.get("MessageSid") || params.get("SmsMessageSid") || params.get("MessageID"), 80),
    media,
  };
}

function channelFromSender(from) {
  return cleanText(from, 90).toLowerCase().startsWith("whatsapp:") ? "whatsapp" : "sms";
}

function cleanText(value, maxLength = 240) {
  return String(value || "").trim().slice(0, maxLength);
}

function mediaItemsFromObject(parsed) {
  const items = [];
  const count = Number(parsed.NumMedia || parsed.numMedia || 0);
  for (let index = 0; index < Math.min(Math.max(count || 0, 0), 10); index += 1) {
    const url = cleanText(parsed[`MediaUrl${index}`] || parsed[`mediaUrl${index}`], 1200);
    const contentType = cleanText(parsed[`MediaContentType${index}`] || parsed[`mediaContentType${index}`], 120);
    if (url) items.push({ url, contentType });
  }
  if (Array.isArray(parsed.media)) {
    for (const item of parsed.media.slice(0, 10)) {
      const url = cleanText(item?.url || item?.mediaUrl, 1200);
      const contentType = cleanText(item?.contentType || item?.mediaContentType, 120);
      if (url) items.push({ url, contentType });
    }
  }
  return items;
}

function mediaItemsFromParams(params) {
  const items = [];
  const count = Number(params.get("NumMedia") || params.get("numMedia") || 0);
  for (let index = 0; index < Math.min(Math.max(count || 0, 0), 10); index += 1) {
    const url = cleanText(params.get(`MediaUrl${index}`) || params.get(`mediaUrl${index}`), 1200);
    const contentType = cleanText(params.get(`MediaContentType${index}`) || params.get(`mediaContentType${index}`), 120);
    if (url) items.push({ url, contentType });
  }
  return items;
}

function audioMedia(media) {
  return (Array.isArray(media) ? media : []).find((item) => /^audio\//i.test(item.contentType || ""));
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

function twilioAuthHeader() {
  const sid = process.env.TWILIO_ACCOUNT_SID;
  const token = process.env.TWILIO_AUTH_TOKEN;
  if (!sid || !token) return "";
  return `Basic ${Buffer.from(`${sid}:${token}`).toString("base64")}`;
}

async function downloadTwilioMedia(item) {
  const headers = {};
  const authorization = twilioAuthHeader();
  if (authorization) headers.authorization = authorization;
  const response = await fetch(item.url, { headers });
  if (!response.ok) {
    throw new Error(`twilio_media_download_failed_${response.status}`);
  }
  const contentLength = Number(response.headers.get("content-length") || 0);
  if (contentLength > 24 * 1024 * 1024) {
    throw new Error("twilio_audio_too_large");
  }
  return Buffer.from(await response.arrayBuffer());
}

async function transcribeAudio(item) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    throw new Error("OPENAI_API_KEY is not configured");
  }

  const audio = await downloadTwilioMedia(item);
  if (audio.length > 24 * 1024 * 1024) {
    throw new Error("twilio_audio_too_large");
  }

  const contentType = item.contentType || "application/octet-stream";
  const extension = audioExtension(contentType);
  const form = new FormData();
  form.append("model", process.env.OPENAI_TRANSCRIPTION_MODEL || "whisper-1");
  form.append("file", new Blob([audio], { type: contentType }), `whatsapp-audio.${extension}`);

  const response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: {
      authorization: `Bearer ${apiKey}`,
    },
    body: form,
  });
  const raw = await response.text();
  let parsed = {};
  try {
    parsed = raw ? JSON.parse(raw) : {};
  } catch (_) {
    parsed = {};
  }
  if (!response.ok) {
    throw new Error(`openai_transcription_failed_${response.status}:${cleanText(parsed.error?.message || raw, 180)}`);
  }
  return cleanText(parsed.text, 800);
}

function twiml(message, mediaUrl = "") {
  if (!mediaUrl) {
    return `<?xml version="1.0" encoding="UTF-8"?><Response><Message><Body>${escapeXml(message)}</Body></Message></Response>`;
  }
  return [
    `<?xml version="1.0" encoding="UTF-8"?>`,
    `<Response>`,
    `<Message><Media>${escapeXml(mediaUrl)}</Media></Message>`,
    `<Message><Body>${escapeXml(message)}</Body></Message>`,
    `</Response>`,
  ].join("");
}

function escapeXml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

function connectReply(from, channel) {
  const label = channel === "whatsapp" ? "WhatsApp" : "SMS";
  return `Hey! Blanked here 👋 Connected. BAI will use ${label} for this number${from ? ` (${from})` : ""}.`;
}

function actionIntro(actions) {
  const first = primaryAction(actions);
  if (!first) return "";
  if (first.type === "set_daily_limit") return "Use this link to open Blanked and review the daily limit.";
  if (first.type === "apply_schedule") return "Use this link to open Blanked and review the protection window.";
  if (first.type === "start_protection") return "Use this link to open Blanked and start the block.";
  if (first.type === "open_app_picker" || first.type === "request_screen_time_permission") return "Use this link to open Blanked and finish setup.";
  return "Use this link to open Blanked and review the next step.";
}

function minuteText(value) {
  const minute = clamp(value, 0, 1439);
  const hour24 = Math.floor(minute / 60);
  const minutePart = String(minute % 60).padStart(2, "0");
  const suffix = hour24 >= 12 ? "PM" : "AM";
  const hour12 = hour24 % 12 || 12;
  return `${hour12}:${minutePart} ${suffix}`;
}

function appTargetText(appNames = []) {
  const names = Array.isArray(appNames) ? appNames.filter(Boolean).slice(0, 4) : [];
  if (names.length === 1) return names[0];
  if (names.length > 1) return `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`;
  return "selected apps";
}

function actionSentence(actions, appNames = []) {
  const first = primaryAction(actions);
  if (!first) return "";
  if (first.type === "apply_schedule") {
    return `This opens Blanked with a protection window for ${appTargetText(appNames)} from ${minuteText(first.start_minute)} to ${minuteText(first.end_minute)}.`;
  }
  if (first.type === "start_protection") {
    return `This opens Blanked with a ${clamp(first.minutes || 25, 5, 240)}-minute app block ready to review.`;
  }
  if (first.type === "open_app_picker" || first.type === "request_screen_time_permission") {
    return "This opens Blanked so you can choose the apps to block.";
  }
  if (first.type === "set_daily_limit") {
    return `This opens Blanked with a ${clamp(first.minutes || 25, 5, 240)}-minute daily limit ready to review.`;
  }
  if (first.type === "enable_allow_only") return "This opens Blanked so you can turn on Allow Only.";
  if (first.type === "enable_adult_filter") return "This opens Blanked so you can turn on adult web protection.";
  if (first.type === "pause_rules") return "This opens Blanked so you can pause scheduled protection.";
  if (first.type === "disable_pause") return "This opens Blanked so you can resume scheduled protection.";
  return "This opens Blanked so you can review the next step.";
}

function voiceActionText(actions, appNames, link) {
  const summary = actionSentence(actions, appNames);
  const intro = actionIntro(actions);
  if (!summary || !link) return "";
  return `${summary}\n\n${intro}\n${link}`;
}

function voiceActionCue(actions, appNames = []) {
  const summary = actionSentence(actions, appNames);
  if (!summary) return "";
  return `${summary} I left the link in the text message.`;
}

function voiceInputSummary(prompt) {
  const value = cleanText(prompt, 160);
  return value ? `I understood your voice note as "${value}".` : "";
}

function withVoiceInputContext(text, prompt) {
  const summary = voiceInputSummary(prompt);
  if (!summary) return text;
  return `${summary}\n\n${text}`;
}

function naturalVoiceText(text) {
  return cleanText(text, 800)
    .replace(/\b(Read|Pattern|Move|Signal|Feedback|Protection|Lectura|Patrón|Movimiento|Señal|Protección):\s*/gi, "")
    .replace(/\bAction:\s*/gi, "")
    .replace(/\bI[’']ll give you one concrete Blanked action for it\.?/gi, "I prepared the next step in Blanked for it.")
    .replace(/\bone concrete Blanked action\b/gi, "the next step in Blanked");
}

function naturalReplyText(text) {
  return cleanText(text, 1400)
    .replace(/\b(Read|Pattern|Move|Signal|Feedback|Protection|Lectura|Patrón|Movimiento|Señal|Protección):\s*/gi, "")
    .replace(/\bAction:\s*/gi, "")
    .replace(/\bI prepared a Blanked link\b/gi, "This Blanked link")
    .replace(/\bI[’']ll give you one concrete Blanked action for it\.?/gi, "I can help you apply it in Blanked.")
    .replace(/\bone concrete Blanked action\b/gi, "a simple next step in Blanked")
    .trim();
}

async function recordMessageConnection(connectCode, from, channel) {
  try {
    await recordAssistantChannel({
      event: "assistant_channel_connected",
      channel,
      preferredChannel: channel,
      connectCode,
      channelUser: from,
    });
  } catch (_) {
    return;
  }
}

function namedApps(text) {
  const value = ` ${cleanText(text, 800).toLowerCase()} `;
  const apps = [
    ["tiktok", "TikTok"],
    ["tik tok", "TikTok"],
    ["instagram", "Instagram"],
    ["insta", "Instagram"],
    ["youtube", "YouTube"],
    ["yt", "YouTube"],
    ["reddit", "Reddit"],
    ["twitter", "Twitter"],
    ["facebook", "Facebook"],
    ["snapchat", "Snapchat"],
  ];
  return Array.from(new Set(apps.filter(([key]) => value.includes(` ${key} `) || value.includes(key)).map(([, app]) => app)));
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
  const value = cleanText(text, 800).toLowerCase();
  const apps = namedApps(text);
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
  return facts;
}

async function askBAI(prompt, from, channel) {
  let savedMemory = {};
  try {
    savedMemory = await getAssistantMemory(channel, from);
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
  const response = await blankedAgentHandler({
    httpMethod: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      prompt,
      locale: "en-US",
      context: {
        channel,
        assistant_channel: channel,
        has_selected_apps: true,
        screen_time_authorized: true,
        memory,
      },
    }),
  });

  if (Object.keys(newFacts).length) {
    try {
      await recordAssistantMemory({ channel, channelUser: from, memory: newFacts, source: prompt });
    } catch (_) {
      // Memory must never block a reply.
    }
  }

  if (response.statusCode < 200 || response.statusCode >= 300) {
    const fallback = "BAI could not read that yet. Try again in a moment.";
    return { text: fallback, speechText: fallback };
  }
  const parsed = JSON.parse(response.body || "{}");
  const plan = parsed.plan || {};
  const message = naturalReplyText(plan.message_text || plan.response_text);
  const actions = plan.actions || [];
  const actionLink = actionDeepLink(actions, memory.main_apps);
  const modelSpeech = naturalVoiceText(plan.speech_text || "");
  const modelFollowup = naturalReplyText(plan.followup_text || "");
  const speechBase = modelSpeech || message;
  const speechActionCue = actionLink && !/\blink\b/i.test(speechBase) ? "I left the link in the next message." : "";
  return {
    text: actionLink ? `${message}\n\n${modelFollowup || actionIntro(actions)}\n${actionLink}` : message,
    actionText: actionLink ? `${actionSentence(actions, memory.main_apps)}\n\n${modelFollowup || actionIntro(actions)}\n${actionLink}` : "",
    speechText: naturalVoiceText(speechActionCue ? `${speechBase} ${speechActionCue}` : speechBase),
  };
}

function wantsVoiceReply(text) {
  return /\b(audio|voice|voice note|speak|spoken|say it|nota de voz|audio|voz|hablame|háblame|dimelo|dímelo)\b/i.test(cleanText(text, 800));
}

function publicOpenLink(actionName, params = {}) {
  const base = (process.env.BLANKED_PUBLIC_APP_LINK_BASE || "https://getblank.netlify.app").replace(/\/$/, "");
  const query = new URLSearchParams({ action: actionName });
  for (const [key, value] of Object.entries(params)) {
    if (value == null || value === "") continue;
    query.set(key, String(value));
  }
  return `${base}/open?${query.toString()}`;
}

function appsQuery(appNames) {
  const names = Array.isArray(appNames) ? appNames.filter(Boolean).slice(0, 8) : [];
  return names.length ? `&apps=${encodeURIComponent(names.join(","))}` : "";
}

function actionDeepLink(actions, appNames = []) {
  const first = primaryAction(actions);
  if (!first) return "";

  if (first.type === "start_protection") {
    return publicOpenLink("start-focus", {
      minutes: clamp(first.minutes || 25, 5, 240),
      hard: first.hard_mode ? "true" : "",
    });
  }
  if (first.type === "apply_schedule") {
    const start = clamp(first.start_minute || 1260, 0, 1439);
    const end = clamp(first.end_minute || 1380, 0, 1439);
    const days = clamp(first.duration_days || 7, 1, 14);
    const route = Array.isArray(appNames) && appNames.length ? "setup-plan" : "apply-plan";
    return publicOpenLink(route, {
      start,
      end,
      days,
      apps: Array.isArray(appNames) && appNames.length ? appNames.slice(0, 8).join(",") : "",
    });
  }
  if (first.type === "set_daily_limit") {
    return publicOpenLink("daily-limit", { minutes: clamp(first.minutes || 25, 5, 240) });
  }
  if (first.type === "open_app_picker") {
    return publicOpenLink("open-picker");
  }
  if (first.type === "request_screen_time_permission") {
    return publicOpenLink("choose-apps");
  }
  if (first.type === "enable_allow_only") {
    return publicOpenLink("allow-only");
  }
  if (first.type === "enable_adult_filter") {
    return publicOpenLink("adult-filter");
  }
  if (first.type === "pause_rules") {
    return publicOpenLink("pause-rules", { hours: clamp(first.hours || 24, 1, 168) });
  }
  if (first.type === "disable_pause") {
    return publicOpenLink("resume-rules");
  }
  return "";
}

function primaryAction(actions) {
  const executable = Array.isArray(actions) ? actions.filter((item) => item && item.type && item.type !== "none") : [];
  return executable.find((item) => item.type === "apply_schedule") || executable[0] || null;
}

function clamp(value, lower, upper) {
  const number = Number(value);
  if (!Number.isFinite(number)) return lower;
  return Math.min(Math.max(Math.round(number), lower), upper);
}

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;

  const { from, body, media } = parseSmsBody(event);
  const audio = audioMedia(media);
  let prompt = body;
  if (!prompt && audio) {
    try {
      prompt = await transcribeAudio(audio);
    } catch (error) {
      return text(200, twiml("I could not understand that voice note yet. Send it as text or try another audio."), "application/xml; charset=utf-8");
    }
  }

  if (!prompt) {
    return json(400, { error: "missing_sms_body" });
  }

  const connectCode = connectCodeFromText(prompt);
  const channel = channelFromSender(from);
  const reply = connectCode
    ? { text: (await recordMessageConnection(connectCode, from, channel), connectReply(from, channel)), speechText: "" }
    : await askBAI(prompt, from, channel);

  const shouldAttachAudio = channel === "whatsapp" && !connectCode && (audio || wantsVoiceReply(body));
  const mediaUrl = shouldAttachAudio
    ? buildSignedAudioUrl(event, reply.speechText || reply.text)
    : "";
  const baseReplyText = mediaUrl && reply.actionText ? reply.actionText : reply.text;
  const replyText = audio ? withVoiceInputContext(baseReplyText, prompt) : baseReplyText;

  return text(200, twiml(replyText, mediaUrl), "application/xml; charset=utf-8");
};
