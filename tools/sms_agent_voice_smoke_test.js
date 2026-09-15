const assert = require("assert");

process.env.OPENAI_API_KEY = "";
process.env.BLANKED_PUBLIC_APP_LINK_BASE = "https://getblank.netlify.app";
process.env.SUPABASE_URL = "https://supabase.test";
process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role";
delete process.env.TWILIO_ACCOUNT_SID;
delete process.env.TWILIO_AUTH_TOKEN;

const { handler: smsHandler } = require("../netlify/functions/sms-agent");
const { handler: audioHandler } = require("../netlify/functions/assistant-audio");

async function withAssistantMemoryMock(callback) {
  const rows = new Map();
  const originalFetch = global.fetch;
  global.fetch = async (target, options = {}) => {
    const url = String(target);
    if (url.startsWith("https://supabase.test/rest/v1/digital_wellness_feature_payloads")) {
      if ((options.method || "GET").toUpperCase() === "POST") {
        const row = JSON.parse(options.body || "{}");
        const list = rows.get(row.anonymous_user_id) || [{
          payload: {
            event: "assistant_memory_updated",
            properties: {
              memory: {
                user_context: {
                  has_selected_apps: true,
                  selection_count: 3,
                  screen_time_authorized: true,
                  app_presence: {
                    app_present: true,
                    app_ready: true,
                    last_seen_at: new Date(Date.now() - 60 * 60 * 1000).toISOString(),
                  },
                },
              },
            },
          },
          submitted_at: new Date().toISOString(),
        }];
        list.push({ payload: row.payload, submitted_at: row.submitted_at });
        rows.set(row.anonymous_user_id, list);
        return { ok: true, status: 201, text: async () => "", json: async () => ({}) };
      }
      const match = url.match(/anonymous_user_id=eq\.([^&]+)/);
      const key = match ? decodeURIComponent(match[1]) : "";
      const seeded = {
        payload: {
          event: "assistant_memory_updated",
          properties: {
            memory: {
              user_context: {
                has_selected_apps: true,
                selection_count: 3,
                screen_time_authorized: true,
                app_presence: {
                  app_present: true,
                  app_ready: true,
                  last_seen_at: new Date(Date.now() - 60 * 60 * 1000).toISOString(),
                },
              },
            },
          },
        },
        submitted_at: new Date().toISOString(),
      };
      const result = rows.get(key) || [seeded];
      return { ok: true, status: 200, text: async () => JSON.stringify(result), json: async () => result };
    }
    return originalFetch(target, options);
  };
  try {
    return await callback();
  } finally {
    global.fetch = originalFetch;
  }
}

async function whatsappVoiceRequestStaysText() {
  const response = await smsHandler({
    httpMethod: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded", host: "getblank.netlify.app" },
    body: new URLSearchParams({
      From: "whatsapp:+34600000000",
      Body: "Can you say it as a voice note? Block Instagram from 10 pm to 7 am every day.",
      MessageSid: "SMvoice",
    }).toString(),
  });

  assert.strictEqual(response.statusCode, 200, response.body);
  assert.match(response.body, /<Body>/);
  assert.doesNotMatch(response.body, /Action:/i);
  assert.doesNotMatch(response.body, /I prepared a Blanked link/i);
  assert.match(response.body, /Choose Instagram in Blankmind first\./);
  assert.match(response.body, /Blankmind/);
  assert.match(response.body, /apps\.apple\.com/);
  assert.doesNotMatch(response.body, /Open Blanked to apply the protection window:/);
  assert.doesNotMatch(response.body, /<Media>/);
  assert.doesNotMatch(response.body, /action=review-action/);
  assert.doesNotMatch(response.body, /type=open_app_picker/);
}

async function smsDoesNotAttachVoice() {
  await withAssistantMemoryMock(async () => {
    const response = await smsHandler({
      httpMethod: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded", host: "getblank.netlify.app" },
      body: new URLSearchParams({
        From: "+34600000000",
        Body: "Can you say it as a voice note? Block Instagram from 10 pm to 7 am every day.",
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
        Body: "Block Instagram from 10 pm to 7 am every day.",
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
    assert.match(second.body, /Open Blanked: https:\/\/getblank\.netlify\.app\/open\?action=review-action/);
    assert.match(second.body, /type=open_app_picker/);
    assert.match(second.body, /apps=Instagram/);
  });
}

async function whatsappBlockingFollowupKeepsPendingContract() {
  await withAssistantMemoryMock(async () => {
    const first = await smsHandler({
      httpMethod: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded", host: "getblank.netlify.app" },
      body: new URLSearchParams({
        From: "whatsapp:+34600000001",
        Body: "Block Instagram",
        MessageSid: "SMpending-1",
      }).toString(),
    });
    assert.strictEqual(first.statusCode, 200, first.body);
    assert.match(first.body, /Should it start now or at an exact time/);
    assert.doesNotMatch(first.body, /https?:\/\//);

    const second = await smsHandler({
      httpMethod: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded", host: "getblank.netlify.app" },
      body: new URLSearchParams({
        From: "whatsapp:+34600000001",
        Body: "Start now for an hour. Only one time",
        MessageSid: "SMpending-2",
      }).toString(),
    });
    assert.strictEqual(second.statusCode, 200, second.body);
    assert.match(second.body, /Open Blanked to finish setup/);
    assert.match(second.body, /type=open_app_picker/);
    assert.match(second.body, /apps=Instagram/);
    assert.match(second.body, /minutes=60/);
  });
}

async function whatsappTextHasNoAudioAttachment() {
  const response = await smsHandler({
    httpMethod: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded", host: "getblank.netlify.app" },
    body: new URLSearchParams({
      From: "whatsapp:+34600000000",
      Body: "Block Instagram from 10 pm to 7 am every day.",
      MessageSid: "SMtext",
    }).toString(),
  });

  assert.strictEqual(response.statusCode, 200, response.body);
  assert.doesNotMatch(response.body, /<Media>/);
  assert.match(response.body, /Blankmind/);
  assert.match(response.body, /apps\.apple\.com/);
  assert.doesNotMatch(response.body, /action=review-action/);
}

async function whatsappInputAudioGetsTranscribedTextReply() {
  const previousApiKey = process.env.OPENAI_API_KEY;
  const originalFetch = global.fetch;
  process.env.OPENAI_API_KEY = "test-openai-key";
  global.fetch = async (target, options = {}) => {
    const url = String(target);
    if (url === "https://api.twilio.com/fake-audio.ogg") {
      return {
        ok: true,
        status: 200,
        headers: { get: () => null },
        arrayBuffer: async () => Buffer.from("fake-audio"),
      };
    }
    if (url === "https://api.openai.com/v1/audio/transcriptions") {
      return {
        ok: true,
        status: 200,
        text: async () => JSON.stringify({ text: "I usually scroll Instagram after breakfast." }),
      };
    }
    return originalFetch(target, options);
  };

  try {
    const response = await withAssistantMemoryMock(() => smsHandler({
      httpMethod: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded", host: "getblank.netlify.app" },
      body: new URLSearchParams({
        From: "whatsapp:+34600000000",
        Body: "",
        NumMedia: "1",
        MediaUrl0: "https://api.twilio.com/fake-audio.ogg",
        MediaContentType0: "audio/ogg",
        MessageSid: "SMinputaudio",
      }).toString(),
    }));

    assert.strictEqual(response.statusCode, 200, response.body);
    assert.match(response.body, /I understood your voice note as &quot;I usually scroll Instagram after breakfast\.&quot;\./);
    assert.doesNotMatch(response.body, /<Media>/);
  } finally {
    global.fetch = originalFetch;
    if (previousApiKey) process.env.OPENAI_API_KEY = previousApiKey;
    else delete process.env.OPENAI_API_KEY;
  }
}

async function audioEndpointIsDisabled() {
  const response = await audioHandler({ httpMethod: "GET" });
  assert.strictEqual(response.statusCode, 410, response.body);
  assert.strictEqual(response.body, "audio_replies_disabled");
}

(async () => {
  await whatsappVoiceRequestStaysText();
  await smsDoesNotAttachVoice();
  await smsCommandOpensStoredAction();
  await whatsappBlockingFollowupKeepsPendingContract();
  await whatsappTextHasNoAudioAttachment();
  await whatsappInputAudioGetsTranscribedTextReply();
  await audioEndpointIsDisabled();
  console.log("sms-agent audio input smoke tests passed");
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
