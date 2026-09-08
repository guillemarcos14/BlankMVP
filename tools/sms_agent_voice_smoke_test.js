const assert = require("assert");

process.env.OPENAI_API_KEY = "";
process.env.ELEVENLABS_API_KEY = "test-elevenlabs-key";
process.env.ELEVENLABS_VOICE_ID = "test-voice-id";
process.env.ELEVENLABS_AUDIO_SIGNING_SECRET = "test-signing-secret";
process.env.BLANKED_PUBLIC_APP_LINK_BASE = "https://getblank.netlify.app";
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
  assert.match(response.body, /Use this link to open Blanked and review the protection window/);
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
  assert.match(response.body, /Use this link to open Blanked and review the protection window/);
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
    assert.match(response.body, /Use this link to open Blanked and review the protection window/);
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
  await whatsappTextWithoutVoiceDoesNotAttachAudio();
  await whatsappInputAudioGetsAudioAndTextContext();
  await voiceDisabledFallsBackToUsefulText();
  await signedAudioEndpoint();
  console.log("sms-agent voice smoke tests passed");
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
