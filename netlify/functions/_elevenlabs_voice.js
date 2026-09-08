const crypto = require("crypto");

function cleanText(value, maxLength = 600) {
  return String(value || "").trim().replace(/\s+/g, " ").slice(0, maxLength);
}

function voiceConfig() {
  const apiKey = process.env.ELEVENLABS_API_KEY;
  const voiceId = process.env.ELEVENLABS_VOICE_ID;
  const signingSecret = process.env.ELEVENLABS_AUDIO_SIGNING_SECRET || process.env.TWILIO_AUTH_TOKEN || "";
  return {
    apiKey,
    voiceId,
    signingSecret,
    modelId: process.env.ELEVENLABS_TTS_MODEL || "eleven_multilingual_v2",
    outputFormat: process.env.ELEVENLABS_OUTPUT_FORMAT || "mp3_44100_128",
    enabled: Boolean(apiKey && voiceId && signingSecret),
  };
}

function baseUrl(event) {
  const configured = cleanText(process.env.BLANKED_PUBLIC_APP_LINK_BASE, 240).replace(/\/$/, "");
  if (configured) return configured;
  const host = event?.headers?.host || event?.headers?.Host || "getblank.netlify.app";
  const proto = event?.headers?.["x-forwarded-proto"] || event?.headers?.["X-Forwarded-Proto"] || "https";
  return `${proto}://${host}`;
}

function signAudioPayload({ text, expires }) {
  const { signingSecret } = voiceConfig();
  if (!signingSecret) return "";
  return crypto
    .createHmac("sha256", signingSecret)
    .update(`${expires}.${text}`)
    .digest("hex");
}

function timingSafeEqual(left, right) {
  const leftBuffer = Buffer.from(left || "");
  const rightBuffer = Buffer.from(right || "");
  if (leftBuffer.length !== rightBuffer.length) return false;
  return crypto.timingSafeEqual(leftBuffer, rightBuffer);
}

function buildSignedAudioUrl(event, text) {
  const normalizedText = cleanText(text, Number(process.env.ELEVENLABS_TTS_MAX_CHARS || 420));
  if (!normalizedText || !voiceConfig().enabled) return "";
  const expires = Math.floor(Date.now() / 1000) + Number(process.env.ELEVENLABS_AUDIO_URL_TTL_SECONDS || 600);
  const signature = signAudioPayload({ text: normalizedText, expires });
  if (!signature) return "";
  const params = new URLSearchParams({ text: normalizedText, expires: String(expires), sig: signature });
  return `${baseUrl(event)}/.netlify/functions/assistant-audio?${params.toString()}`;
}

function verifySignedAudioRequest(event) {
  const params = event.queryStringParameters || {};
  const text = cleanText(params.text, Number(process.env.ELEVENLABS_TTS_MAX_CHARS || 420));
  const expires = Number(params.expires || 0);
  const signature = cleanText(params.sig, 128);
  if (!text || !Number.isFinite(expires) || !signature) {
    return { ok: false, error: "missing_audio_signature" };
  }
  if (expires < Math.floor(Date.now() / 1000)) {
    return { ok: false, error: "audio_url_expired" };
  }
  const expected = signAudioPayload({ text, expires });
  if (!expected || !timingSafeEqual(expected, signature)) {
    return { ok: false, error: "invalid_audio_signature" };
  }
  return { ok: true, text };
}

async function generateSpeech(text) {
  const config = voiceConfig();
  if (!config.enabled) {
    throw new Error("elevenlabs_voice_not_configured");
  }
  const response = await fetch(
    `https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(config.voiceId)}?output_format=${encodeURIComponent(config.outputFormat)}`,
    {
      method: "POST",
      headers: {
        "xi-api-key": config.apiKey,
        "content-type": "application/json",
        accept: "audio/mpeg",
      },
      body: JSON.stringify({
        text: cleanText(text, Number(process.env.ELEVENLABS_TTS_MAX_CHARS || 420)),
        model_id: config.modelId,
        voice_settings: {
          stability: Number(process.env.ELEVENLABS_VOICE_STABILITY || 0.45),
          similarity_boost: Number(process.env.ELEVENLABS_VOICE_SIMILARITY_BOOST || 0.75),
          style: Number(process.env.ELEVENLABS_VOICE_STYLE || 0),
          use_speaker_boost: process.env.ELEVENLABS_USE_SPEAKER_BOOST !== "false",
        },
      }),
    }
  );
  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`elevenlabs_tts_failed_${response.status}:${cleanText(detail, 180)}`);
  }
  return Buffer.from(await response.arrayBuffer());
}

module.exports = {
  buildSignedAudioUrl,
  cleanText,
  generateSpeech,
  verifySignedAudioRequest,
  voiceConfig,
};
