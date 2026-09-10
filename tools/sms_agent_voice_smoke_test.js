const assert = require("assert");

process.env.OPENAI_API_KEY = "";
process.env.ELEVENLABS_API_KEY = "test-elevenlabs-key";
process.env.ELEVENLABS_VOICE_ID = "test-voice-id";
process.env.ELEVENLABS_AUDIO_SIGNING_SECRET = "test-signing-secret";
process.env.BLANKED_PUBLIC_APP_LINK_BASE = "https://getblank.netlify.app";
process.env.SUPABASE_URL = "https://supabase.test";
process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role";
delete process.env.TWILIO_ACCOUNT_SID;
delete process.env.TWILIO_AUTH_TOKEN;

const { handler: smsHandler } = require("../netlify/functions/sms-agent");
const { handler: audioHandler } = require("../netlify/functions/assistant-audio");

function mediaUrlFromTwiML(body) {
  const match = body.match(/<Media>([^<]+)<\/Media>/);
  return match ? match[1].replace(/&amp;/g, "&") : "";
}

function assertAudioBeforeText(body) {
  const mediaIndex = body.indexOf("<Media>");
  const bodyIndex = body.indexOf("<Body>");
  assert.ok(mediaIndex >= 0, body);
  assert.ok(bodyIndex > mediaIndex, body);
}

async function withAssistantMemoryMock(callback) {
  const rows = new Map();
  const originalFetch = global.fetch;
  global.fetch = async (target, options = {}) => {
    const url = String(target);
    if (url.startsWith("https://supabase.test/rest/v1/digital_wellness_feature_payloads")) {
      if ((options.method || "GET").toUpperCase() === "POST") {
        const row = JSON.parse(options.body || "{}");
        const list = rows.get(row.anonymous_user_id) || [];
        list.push({ payload: row.payload, submitted_at: row.submitted_at });
        rows.set(row.anonymous_user_id, list);
        return { ok: true, status: 201, text: async () => "", json: async () => ({}) };
      }
      const match = url.match(/anonymous_user_id=eq\.([^&]+)/);
      const key = match ? decodeURIComponent(match[1]) : "";
      return { ok: true, status: 200, text: async () => JSON.stringify(rows.get(key) || []), json: async () => rows.get(key) || [] };
    }
    return originalFetch(target, options);
  };
  try {
    return await callback();
  } finally {
    global.fetch = originalFetch;
  }
}

async function whatsappTextWithVoiceMedia() {
  const response = await smsHandler({
    httpMethod: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded", host: "getblank.netlify.app" },
    body: new URLSearchParams({
      From: "whatsapp:+34600000000",
      Body: "Can you say it as a voice note? Block Instagram from 10 to 7.",
      MessageSid: "SMvoice",
    }).toString(),
  });

  assert.strictEqual(response.statusCode, 200, response.body);
  assert.match(response.body, /<Body>/);
  assert.doesNotMatch(response.body, /Action:/i);
  assert.doesNotMatch(response.body, /I prepared a Blanked link/i);
  assert.match(response.body, /This opens Blanked with a protection window for Instagram from 10:00 PM to 7:00 AM\./);
  assert.match(response.body, /Open Blanked to review and apply the window/);
  assert.doesNotMatch(response.body, /Open Blanked to apply the protection window:/);
  assert.match(response.body, /<Media>https:\/\/getblank\.netlify\.app\/\.netlify\/functions\/assistant-audio\?/);
  assert.match(response.body, /action=setup-plan/);
  assertAudioBeforeText(response.body);
  assert.match(response.body, /<\/Media><\/Message><Message><Body>/);
  const audioUrl = new URL(mediaUrlFromTwiML(response.body));
  assert.doesNotMatch(audioUrl.searchParams.get("text"), /Action:/i);
  assert.doesNotMatch(audioUrl.searchParams.get("text"), /I prepared a Blanked link/i);
  assert.doesNotMatch(audioUrl.searchParams.get("text"), /one concrete Blanked action/i);
  assert.match(audioUrl.searchParams.get("text"), /I left the link in the next message\./);
}

async function smsDoesNotAttachVoice() {
  await withAssistantMemoryMock(async () => {
    const response = await smsHandler({
      httpMethod: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded", host: "getblank.netlify.app" },
      body: new URLSearchParams({
        From: "+34600000000",
        Body: "Can you say it as a voice note? Block Instagram from 10 to 7.",
        MessageSid: "SMsms",
      }).toString(),
    });

    assert.strictEqual(response.statusCode, 200, response.body);
    assert.doesNotMatch(response.body, /<Media>/);
    assert.doesNotMatch(response.body, /https?:\/\//);
    assert.match(response.body, /Reply BLOCK to open Blanked with this ready\./);
  });
}

async function smsCommandOpensStoredAction() {
  await withAssistantMemoryMock(async () => {
    const first = await smsHandler({
      httpMethod: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded", host: "getblank.netlify.app" },
      body: new URLSearchParams({
        From: "+34600000000",
        Body: "Block Instagram from 10 to 7.",
        MessageSid: "SMsms-plan",
      }).toString(),
    });
    assert.strictEqual(first.statusCode, 200, first.body);
    assert.match(first.body, /Reply BLOCK/);
    assert.doesNotMatch(first.body, /https?:\/\//);

    const second = await smsHandler({
      httpMethod: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded", host: "getblank.netlify.app" },
      body: new URLSearchParams({
        From: "+34600000000",
        Body: "BLOCK",
        MessageSid: "SMsms-block",
      }).toString(),
    });
    assert.strictEqual(second.statusCode, 200, second.body);
    assert.match(second.body, /Open Blanked: https:\/\/getblank\.netlify\.app\/open\?action=setup-plan/);
    assert.match(second.body, /apps=Instagram/);
  });
}

async function whatsappTextWithoutVoiceDoesNotAttachAudio() {
  const response = await smsHandler({
    httpMethod: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded", host: "getblank.netlify.app" },
    body: new URLSearchParams({
      From: "whatsapp:+34600000000",
      Body: "Block Instagram from 10 to 7.",
      MessageSid: "SMtext",
    }).toString(),
  });

  assert.strictEqual(response.statusCode, 200, response.body);
  assert.doesNotMatch(response.body, /<Media>/);
  assert.match(response.body, /Open Blanked to review and apply the window/);
}

async function whatsappInputAudioGetsAudioAndTextContext() {
  const response = await smsHandler({
    httpMethod: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded", host: "getblank.netlify.app" },
    body: new URLSearchParams({
      From: "whatsapp:+34600000000",
      Body: "Block Instagram from 10 to 7.",
      NumMedia: "1",
      MediaUrl0: "https://api.twilio.com/fake-audio.ogg",
      MediaContentType0: "audio/ogg",
      MessageSid: "SMinputaudio",
    }).toString(),
  });

  assert.strictEqual(response.statusCode, 200, response.body);
  assert.match(response.body, /I understood your voice note as/);
  assert.match(response.body, /<Media>https:\/\/getblank\.netlify\.app\/\.netlify\/functions\/assistant-audio\?/);
  assertAudioBeforeText(response.body);
}

async function voiceDisabledFallsBackToUsefulText() {
  const voiceId = process.env.ELEVENLABS_VOICE_ID;
  delete process.env.ELEVENLABS_VOICE_ID;
  try {
    const response = await smsHandler({
      httpMethod: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded", host: "getblank.netlify.app" },
      body: new URLSearchParams({
        From: "whatsapp:+34600000000",
        Body: "Reply in audio. Block Instagram from 10 to 7.",
        MessageSid: "SMnoaudio",
      }).toString(),
    });

    assert.strictEqual(response.statusCode, 200, response.body);
    assert.doesNotMatch(response.body, /<Media>/);
    assert.match(response.body, /Open Blanked to review and apply the window/);
    assert.match(response.body, /action=setup-plan/);
  } finally {
    process.env.ELEVENLABS_VOICE_ID = voiceId;
  }
}

async function signedAudioEndpoint() {
  const response = await smsHandler({
    httpMethod: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded", host: "getblank.netlify.app" },
    body: new URLSearchParams({
      From: "whatsapp:+34600000000",
      Body: "Reply in audio. I keep scrolling at night.",
      MessageSid: "SMsigned",
    }).toString(),
  });
  const url = mediaUrlFromTwiML(response.body);
  const parsed = new URL(url);

  const originalFetch = global.fetch;
  global.fetch = async (target, options) => {
    assert.match(String(target), /https:\/\/api\.elevenlabs\.io\/v1\/text-to-speech\/test-voice-id/);
    assert.strictEqual(options.headers["xi-api-key"], "test-elevenlabs-key");
    const payload = JSON.parse(options.body);
    assert.ok(payload.text.length > 0);
    return {
      ok: true,
      arrayBuffer: async () => Buffer.from("fake-mp3").buffer,
    };
  };

  try {
    const audio = await audioHandler({
      httpMethod: "GET",
      headers: {},
      queryStringParameters: Object.fromEntries(parsed.searchParams.entries()),
    });
    assert.strictEqual(audio.statusCode, 200, audio.body);
    assert.strictEqual(audio.headers["content-type"], "audio/mpeg");
    assert.strictEqual(audio.isBase64Encoded, true);
  } finally {
    global.fetch = originalFetch;
  }
}

(async () => {
  await whatsappTextWithVoiceMedia();
  await smsDoesNotAttachVoice();
  await smsCommandOpensStoredAction();
  await whatsappTextWithoutVoiceDoesNotAttachAudio();
  await whatsappInputAudioGetsAudioAndTextContext();
  await voiceDisabledFallsBackToUsefulText();
  await signedAudioEndpoint();
  console.log("sms-agent voice smoke tests passed");
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
