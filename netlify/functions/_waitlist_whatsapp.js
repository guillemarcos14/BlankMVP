const crypto = require("crypto");
const { json } = require("./_membership");
const { cleanText } = require("./_identity");
const { phoneForStorage } = require("./_waitlist_store");

const OPENING_MESSAGE_1 = "Hey, I’m Blankmind. Tell me a bit about yourself.";
const OPENING_MESSAGE_2 = "What should I call you? How old are you? What’s a normal day like for you? A voice note’s fine too, if that’s easier.";
const TWILIO_OPENING_CONTENT_SIDS = {
  1: "HX8d2a6ae19f26e983695d248284b74c40",
  2: "HX99b42fe21aaa483720b97bcbb57020d2",
};

function header(event, name) {
  const target = name.toLowerCase();
  const match = Object.entries(event.headers || {}).find(([key]) => key.toLowerCase() === target);
  return match ? String(match[1] || "") : "";
}

function rawBody(event) {
  if (!event.body) return "";
  return event.isBase64Encoded ? Buffer.from(event.body, "base64").toString("utf8") : event.body;
}

function isProduction() {
  return process.env.NODE_ENV === "production"
    || process.env.CONTEXT === "production"
    || process.env.NETLIFY === "true";
}

function timingSafeEqual(left, right) {
  const leftBuffer = Buffer.from(left || "");
  const rightBuffer = Buffer.from(right || "");
  if (!leftBuffer.length || leftBuffer.length !== rightBuffer.length) return false;
  return crypto.timingSafeEqual(leftBuffer, rightBuffer);
}

function verifyMetaSignature(event) {
  const secret = process.env.WHATSAPP_APP_SECRET;
  if (!secret) return !isProduction() && process.env.WHATSAPP_REQUIRE_SIGNATURE !== "true";
  const signature = header(event, "x-hub-signature-256");
  if (!signature.startsWith("sha256=")) return false;
  const expected = `sha256=${crypto.createHmac("sha256", secret).update(rawBody(event), "utf8").digest("hex")}`;
  return timingSafeEqual(signature, expected);
}

function verifyMetaChallenge(event) {
  const params = event.queryStringParameters || {};
  if (params["hub.mode"] !== "subscribe" || !params["hub.challenge"]) {
    return json(400, { error: "invalid_whatsapp_challenge" });
  }
  if (!process.env.WHATSAPP_VERIFY_TOKEN || params["hub.verify_token"] !== process.env.WHATSAPP_VERIFY_TOKEN) {
    return json(403, { error: "invalid_whatsapp_verify_token" });
  }
  return {
    statusCode: 200,
    headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" },
    body: params["hub.challenge"],
  };
}

function parseMetaMessages(body) {
  const result = [];
  for (const entry of Array.isArray(body?.entry) ? body.entry : []) {
    for (const change of Array.isArray(entry?.changes) ? entry.changes : []) {
      for (const message of Array.isArray(change?.value?.messages) ? change.value.messages : []) {
        const text = cleanText(
          message?.text?.body
          || message?.button?.text
          || message?.button?.payload
          || message?.interactive?.button_reply?.title
          || message?.interactive?.button_reply?.id
          || message?.interactive?.list_reply?.title
          || message?.interactive?.list_reply?.id,
          4000,
        );
        const mediaId = cleanText(message?.audio?.id, 180);
        const phone = phoneForStorage(message?.from);
        if (!phone || (!text && !mediaId)) continue;
        result.push({
          provider: "meta",
          providerMessageId: cleanText(message?.id, 160),
          phone,
          text,
          audio: mediaId ? {
            mediaId,
            contentType: cleanText(message?.audio?.mime_type || "audio/ogg", 120),
          } : null,
        });
      }
    }
  }
  return result;
}

function twilioWebhookUrl(event) {
  const configured = cleanText(process.env.WAITLIST_TWILIO_WEBHOOK_URL, 800);
  if (configured) return configured;
  if (isProduction()) return "https://getblank.netlify.app/.netlify/functions/waitlist-agent";
  const protocol = header(event, "x-forwarded-proto") || "https";
  const host = header(event, "x-forwarded-host") || header(event, "host");
  const path = event.path || "/.netlify/functions/waitlist-agent";
  return host ? `${protocol}://${host}${path}` : "";
}

function twilioBackgroundUrl(event) {
  const configured = cleanText(process.env.WAITLIST_TWILIO_BACKGROUND_URL, 800);
  if (configured) return configured;
  if (isProduction()) return "https://getblank.netlify.app/.netlify/functions/waitlist-agent-background";
  const protocol = header(event, "x-forwarded-proto") || "https";
  const host = header(event, "x-forwarded-host") || header(event, "host");
  return host
    ? `${protocol}://${host}/.netlify/functions/waitlist-agent-background`
    : "https://getblank.netlify.app/.netlify/functions/waitlist-agent-background";
}

function shouldUseAsyncTwilio() {
  // Async delivery is the safe default. Only local/test callers may explicitly
  // opt back into the legacy inline TwiML path.
  return process.env.WAITLIST_TWILIO_ASYNC !== "false";
}

function verifyTwilioSignature(event) {
  const configured = process.env.TWILIO_VALIDATE_WEBHOOK_SIGNATURE;
  const shouldValidate = configured === "true" || (isProduction() && configured !== "false");
  if (!shouldValidate) return true;
  const token = process.env.TWILIO_AUTH_TOKEN;
  const signature = header(event, "x-twilio-signature");
  const url = twilioWebhookUrl(event);
  if (!token || !signature || !url) return false;
  const params = new URLSearchParams(rawBody(event));
  const canonical = Array.from(params.entries())
    .sort(([leftKey, leftValue], [rightKey, rightValue]) => leftKey.localeCompare(rightKey) || leftValue.localeCompare(rightValue))
    .map(([key, value]) => `${key}${value}`)
    .join("");
  const expected = crypto.createHmac("sha1", token).update(`${url}${canonical}`, "utf8").digest("base64");
  return timingSafeEqual(signature, expected);
}

function parseTwilioMessage(event) {
  const params = new URLSearchParams(rawBody(event));
  const from = cleanText(params.get("From"), 90);
  const phone = phoneForStorage(from);
  const channel = /^whatsapp:/i.test(from) ? "whatsapp" : "sms";
  const text = cleanText(params.get("Body"), 4000);
  const providerMessageId = cleanText(params.get("MessageSid") || params.get("SmsMessageSid"), 160);
  const count = Math.min(Math.max(Number(params.get("NumMedia") || 0), 0), 10);
  let audio = null;
  for (let index = 0; index < count; index += 1) {
    const url = cleanText(params.get(`MediaUrl${index}`), 1600);
    const contentType = cleanText(params.get(`MediaContentType${index}`), 120);
    if (url && /^audio\//i.test(contentType)) {
      audio = { url, contentType };
      break;
    }
  }
  return phone && (text || audio)
    ? [{ provider: "twilio", providerMessageId, phone, channel, text, audio }]
    : [];
}

function isTwilioEvent(event) {
  const contentType = header(event, "content-type").toLowerCase();
  return contentType.includes("application/x-www-form-urlencoded")
    || Boolean(header(event, "x-twilio-signature"));
}

function escapeXml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

function twimlResponse(messages) {
  const body = (Array.isArray(messages) ? messages : [messages])
    .filter(Boolean)
    .map((message) => `<Message><Body>${escapeXml(message)}</Body></Message>`)
    .join("");
  return {
    statusCode: 200,
    headers: { "content-type": "text/xml; charset=utf-8", "cache-control": "no-store" },
    body: `<?xml version="1.0" encoding="UTF-8"?><Response>${body}</Response>`,
  };
}

function audioExtension(contentType) {
  const value = cleanText(contentType, 120).toLowerCase();
  if (value.includes("ogg")) return "ogg";
  if (value.includes("mpeg") || value.includes("mp3")) return "mp3";
  if (value.includes("mp4") || value.includes("m4a")) return "m4a";
  if (value.includes("wav")) return "wav";
  if (value.includes("webm")) return "webm";
  if (value.includes("amr")) return "amr";
  return "audio";
}

function twilioAuthorization() {
  const sid = process.env.TWILIO_ACCOUNT_SID;
  const token = process.env.TWILIO_AUTH_TOKEN;
  return sid && token ? `Basic ${Buffer.from(`${sid}:${token}`).toString("base64")}` : "";
}

async function downloadAudio(message, fetchImpl = fetch) {
  if (message.provider === "meta") {
    const token = process.env.WHATSAPP_ACCESS_TOKEN;
    if (!token || !message.audio?.mediaId) throw new Error("waitlist_meta_audio_not_configured");
    const version = process.env.WHATSAPP_GRAPH_API_VERSION || "v26.0";
    const metadataResponse = await fetchImpl(`https://graph.facebook.com/${version}/${encodeURIComponent(message.audio.mediaId)}`, {
      headers: { authorization: `Bearer ${token}` },
    });
    if (!metadataResponse.ok) throw new Error(`waitlist_meta_media_metadata_${metadataResponse.status}`);
    const metadata = await metadataResponse.json();
    const mediaUrl = cleanText(metadata.url, 1600);
    if (!mediaUrl) throw new Error("waitlist_meta_media_url_missing");
    const response = await fetchImpl(mediaUrl, { headers: { authorization: `Bearer ${token}` } });
    if (!response.ok) throw new Error(`waitlist_meta_media_download_${response.status}`);
    return { response, contentType: message.audio.contentType || "audio/ogg" };
  }

  const authorization = twilioAuthorization();
  const response = await fetchImpl(message.audio.url, {
    headers: authorization ? { authorization } : {},
  });
  if (!response.ok) throw new Error(`waitlist_twilio_media_download_${response.status}`);
  return { response, contentType: message.audio.contentType || "application/octet-stream" };
}

async function transcribeAudio(message, fetchImpl = fetch) {
  if (!message.audio) return "";
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) throw new Error("OPENAI_API_KEY is not configured");
  const { response, contentType } = await downloadAudio(message, fetchImpl);
  const contentLength = Number(response.headers?.get?.("content-length") || 0);
  if (contentLength > 24 * 1024 * 1024) throw new Error("waitlist_audio_too_large");
  const bytes = Buffer.from(await response.arrayBuffer());
  if (bytes.length > 24 * 1024 * 1024) throw new Error("waitlist_audio_too_large");
  const form = new FormData();
  form.append("model", process.env.OPENAI_TRANSCRIPTION_MODEL || "whisper-1");
  form.append("file", new Blob([bytes], { type: contentType }), `waitlist-audio.${audioExtension(contentType)}`);
  const transcriptionResponse = await fetchImpl("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: { authorization: `Bearer ${apiKey}` },
    body: form,
  });
  const raw = await transcriptionResponse.text();
  let payload = {};
  try { payload = raw ? JSON.parse(raw) : {}; } catch (_) { payload = {}; }
  if (!transcriptionResponse.ok) {
    throw new Error(`waitlist_transcription_${transcriptionResponse.status}:${cleanText(payload.error?.message || raw, 180)}`);
  }
  const transcript = cleanText(payload.text, 4000);
  if (!transcript) throw new Error("waitlist_transcription_empty");
  return transcript;
}

async function sendMetaText(phone, body, fetchImpl = fetch) {
  const token = process.env.WHATSAPP_ACCESS_TOKEN;
  const phoneNumberId = process.env.WHATSAPP_PHONE_NUMBER_ID;
  if (!token || !phoneNumberId) throw new Error("waitlist_meta_credentials_missing");
  const version = process.env.WHATSAPP_GRAPH_API_VERSION || "v26.0";
  const response = await fetchImpl(`https://graph.facebook.com/${version}/${encodeURIComponent(phoneNumberId)}/messages`, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify({ messaging_product: "whatsapp", to: phone.replace(/^\+/, ""), type: "text", text: { body } }),
  });
  const raw = await response.text();
  let payload = {};
  try { payload = raw ? JSON.parse(raw) : {}; } catch (_) { payload = {}; }
  if (!response.ok) throw new Error(`waitlist_meta_send_${response.status}:${cleanText(payload.error?.message || raw, 180)}`);
  return { id: payload.messages?.[0]?.id || null, provider: "meta" };
}

async function sendMetaTemplate(phone, templateName, fetchImpl = fetch) {
  const token = process.env.WHATSAPP_ACCESS_TOKEN;
  const phoneNumberId = process.env.WHATSAPP_PHONE_NUMBER_ID;
  if (!token || !phoneNumberId || !templateName) throw new Error("waitlist_meta_template_missing");
  const version = process.env.WHATSAPP_GRAPH_API_VERSION || "v26.0";
  const response = await fetchImpl(`https://graph.facebook.com/${version}/${encodeURIComponent(phoneNumberId)}/messages`, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify({
      messaging_product: "whatsapp",
      to: phone.replace(/^\+/, ""),
      type: "template",
      template: {
        name: templateName,
        language: { code: process.env.WAITLIST_WHATSAPP_TEMPLATE_LANGUAGE || "en" },
      },
    }),
  });
  const raw = await response.text();
  let payload = {};
  try { payload = raw ? JSON.parse(raw) : {}; } catch (_) { payload = {}; }
  if (!response.ok) throw new Error(`waitlist_meta_template_send_${response.status}:${cleanText(payload.error?.message || raw, 180)}`);
  return { id: payload.messages?.[0]?.id || null, provider: "meta" };
}

async function sendTwilioContent(phone, contentSid, fetchImpl = fetch) {
  const sid = process.env.TWILIO_ACCOUNT_SID;
  const token = process.env.TWILIO_AUTH_TOKEN;
  const from = phoneForStorage(process.env.TWILIO_WHATSAPP_FROM_NUMBER || process.env.TWILIO_FROM_NUMBER);
  if (!sid || !token || !from || !contentSid) throw new Error("waitlist_twilio_template_missing");
  const form = new URLSearchParams({
    From: `whatsapp:${from}`,
    To: `whatsapp:${phone}`,
    ContentSid: contentSid,
  });
  const response = await fetchImpl(`https://api.twilio.com/2010-04-01/Accounts/${encodeURIComponent(sid)}/Messages.json`, {
    method: "POST",
    headers: {
      authorization: `Basic ${Buffer.from(`${sid}:${token}`).toString("base64")}`,
      "content-type": "application/x-www-form-urlencoded",
    },
    body: form.toString(),
  });
  const raw = await response.text();
  let payload = {};
  try { payload = raw ? JSON.parse(raw) : {}; } catch (_) { payload = {}; }
  if (!response.ok) throw new Error(`waitlist_twilio_template_send_${response.status}:${cleanText(payload.message || raw, 180)}`);
  return { id: payload.sid || null, provider: "twilio" };
}

async function sendTwilioText(phone, body, channelOrFetch = "whatsapp", maybeFetch = fetch) {
  const sid = process.env.TWILIO_ACCOUNT_SID;
  const token = process.env.TWILIO_AUTH_TOKEN;
  const message = cleanText(body, 4000);
  const { channel, fetchImpl } = openingArguments(channelOrFetch, maybeFetch);
  if (!sid || !token || !phone || !message) throw new Error("waitlist_twilio_text_missing");

  let form;
  if (channel === "sms") {
    const from = phoneForStorage(process.env.TWILIO_FROM_NUMBER);
    const messagingServiceSid = cleanText(process.env.TWILIO_MESSAGING_SERVICE_SID, 80);
    if (!from && !messagingServiceSid) throw new Error("waitlist_sms_credentials_missing");
    form = new URLSearchParams({ To: phone, Body: message });
    if (messagingServiceSid) form.set("MessagingServiceSid", messagingServiceSid);
    else form.set("From", from);
  } else if (channel === "whatsapp") {
    const from = phoneForStorage(process.env.TWILIO_WHATSAPP_FROM_NUMBER || process.env.TWILIO_FROM_NUMBER);
    if (!from) throw new Error("waitlist_twilio_text_missing");
    form = new URLSearchParams({
      From: `whatsapp:${from}`,
      To: `whatsapp:${phone}`,
      Body: message,
    });
  } else {
    throw new Error("waitlist_channel_invalid");
  }

  const response = await fetchImpl(`https://api.twilio.com/2010-04-01/Accounts/${encodeURIComponent(sid)}/Messages.json`, {
    method: "POST",
    headers: {
      authorization: `Basic ${Buffer.from(`${sid}:${token}`).toString("base64")}`,
      "content-type": "application/x-www-form-urlencoded",
    },
    body: form.toString(),
  });
  const raw = await response.text();
  let payload = {};
  try { payload = raw ? JSON.parse(raw) : {}; } catch (_) { payload = {}; }
  if (!response.ok) throw new Error(`waitlist_twilio_text_send_${response.status}:${cleanText(payload.message || raw, 180)}`);
  if (!payload.sid) throw new Error("waitlist_twilio_text_send_missing_sid");
  return { id: payload.sid, provider: "twilio", channel, status: payload.status || null };
}

async function sendTwilioSms(phone, body, fetchImpl = fetch) {
  const sid = process.env.TWILIO_ACCOUNT_SID;
  const token = process.env.TWILIO_AUTH_TOKEN;
  const from = phoneForStorage(process.env.TWILIO_FROM_NUMBER);
  const messagingServiceSid = cleanText(process.env.TWILIO_MESSAGING_SERVICE_SID, 80);
  if (!sid || !token || (!from && !messagingServiceSid)) throw new Error("waitlist_sms_credentials_missing");

  const form = new URLSearchParams({ To: phone, Body: body });
  if (messagingServiceSid) form.set("MessagingServiceSid", messagingServiceSid);
  else form.set("From", from);
  const response = await fetchImpl(`https://api.twilio.com/2010-04-01/Accounts/${encodeURIComponent(sid)}/Messages.json`, {
    method: "POST",
    headers: {
      authorization: `Basic ${Buffer.from(`${sid}:${token}`).toString("base64")}`,
      "content-type": "application/x-www-form-urlencoded",
    },
    body: form.toString(),
  });
  const raw = await response.text();
  let payload = {};
  try { payload = raw ? JSON.parse(raw) : {}; } catch (_) { payload = {}; }
  if (!response.ok) throw new Error(`waitlist_sms_send_${response.status}:${cleanText(payload.message || raw, 180)}`);
  return { id: payload.sid || null, provider: "twilio" };
}

function backgroundSignature(body) {
  const token = process.env.TWILIO_AUTH_TOKEN;
  if (!token) return "";
  return `sha256=${crypto.createHmac("sha256", token).update(body, "utf8").digest("hex")}`;
}

function verifyBackgroundSignature(event) {
  const body = rawBody(event);
  const expected = backgroundSignature(body);
  return Boolean(expected) && timingSafeEqual(header(event, "x-waitlist-background-signature"), expected);
}

async function enqueueTwilioMessage(message, event, fetchImpl = fetch) {
  const url = twilioBackgroundUrl(event);
  const body = JSON.stringify({ message });
  const signature = backgroundSignature(body);
  if (!url || !signature) throw new Error("waitlist_twilio_background_not_configured");
  const response = await fetchImpl(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-waitlist-background-signature": signature,
    },
    body,
  });
  const raw = await response.text();
  if (!response.ok && response.status !== 202) {
    throw new Error(`waitlist_twilio_background_enqueue_${response.status}:${cleanText(raw, 180)}`);
  }
  return { accepted: true };
}

function openingArguments(channelOrFetch, maybeFetch) {
  if (typeof channelOrFetch === "function") {
    return { channel: "whatsapp", fetchImpl: channelOrFetch };
  }
  return {
    channel: cleanText(channelOrFetch, 20).toLowerCase() || "whatsapp",
    fetchImpl: typeof maybeFetch === "function" ? maybeFetch : fetch,
  };
}

async function sendOpeningMessage(phone, index, channelOrFetch = "whatsapp", maybeFetch = fetch) {
  if (![1, 2].includes(index)) throw new Error("waitlist_opening_index_invalid");
  const opening = index === 1 ? OPENING_MESSAGE_1 : OPENING_MESSAGE_2;
  const { channel, fetchImpl } = openingArguments(channelOrFetch, maybeFetch);
  if (channel === "sms") return sendTwilioSms(phone, opening, fetchImpl);
  if (channel !== "whatsapp") throw new Error("waitlist_channel_invalid");
  const provider = cleanText(process.env.WAITLIST_WHATSAPP_PROVIDER, 20).toLowerCase() || "twilio";
  if (!isProduction() && process.env.WAITLIST_ALLOW_FREEFORM_OPENING === "true") {
    if (provider !== "meta") throw new Error("waitlist_freeform_opening_meta_only");
    return sendMetaText(phone, opening, fetchImpl);
  }
  if (provider === "twilio") {
    const contentSid = process.env[`WAITLIST_WHATSAPP_OPENING_CONTENT_SID_${index}`] || TWILIO_OPENING_CONTENT_SIDS[index];
    if (!contentSid) throw new Error("waitlist_twilio_opening_templates_missing");
    return sendTwilioContent(phone, contentSid, fetchImpl);
  }
  const templateName = process.env[`WAITLIST_WHATSAPP_OPENING_TEMPLATE_${index}`];
  if (!templateName) throw new Error("waitlist_meta_opening_templates_missing");
  return sendMetaTemplate(phone, templateName, fetchImpl);
}

async function sendOpening(phone, fetchImpl = fetch) {
  return [
    await sendOpeningMessage(phone, 1, fetchImpl),
    await sendOpeningMessage(phone, 2, fetchImpl),
  ];
}

module.exports = {
  OPENING_MESSAGE_1,
  OPENING_MESSAGE_2,
  isTwilioEvent,
  parseMetaMessages,
  parseTwilioMessage,
  enqueueTwilioMessage,
  sendMetaText,
  sendTwilioText,
  sendOpening,
  sendOpeningMessage,
  shouldUseAsyncTwilio,
  sendTwilioSms,
  transcribeAudio,
  twimlResponse,
  verifyBackgroundSignature,
  verifyMetaChallenge,
  verifyMetaSignature,
  verifyTwilioSignature,
};
