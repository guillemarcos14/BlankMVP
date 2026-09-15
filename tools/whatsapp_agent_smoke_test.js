const assert = require("assert");

process.env.OPENAI_API_KEY = "";
process.env.WHATSAPP_VERIFY_TOKEN = "test-token";
delete process.env.WHATSAPP_ACCESS_TOKEN;
delete process.env.WHATSAPP_PHONE_NUMBER_ID;

const { handler } = require("../netlify/functions/whatsapp-agent");

function recentAssistantMemoryResponse(target, options = {}) {
  if (!String(target).startsWith("https://supabase.test/rest/v1/")) return null;
  if ((options.method || "GET").toUpperCase() === "POST") {
    return { ok: true, status: 201, text: async () => "", json: async () => ({}) };
  }
  const result = [{
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
  return { ok: true, status: 200, text: async () => JSON.stringify(result), json: async () => result };
}

async function verifyWebhook() {
  const response = await handler({
    httpMethod: "GET",
    queryStringParameters: {
      "hub.mode": "subscribe",
      "hub.verify_token": "test-token",
      "hub.challenge": "challenge-ok",
    },
  });
  assert.strictEqual(response.statusCode, 200, response.body);
  assert.strictEqual(response.body, "challenge-ok");
}

async function receiveMessage() {
  const response = await handler({
    httpMethod: "POST",
    headers: {},
    body: JSON.stringify({
      entry: [
        {
          changes: [
            {
              value: {
                messages: [
                  {
                    from: "34600000000",
                    id: "wamid.test",
                    text: { body: "Block Instagram from 10 to 7" },
                  },
                ],
              },
            },
          ],
        },
      ],
    }),
  });
  assert.strictEqual(response.statusCode, 200, response.body);
  const body = JSON.parse(response.body);
  assert.strictEqual(body.ok, true);
  assert.strictEqual(body.received, 1);
  assert.strictEqual(body.results[0].skipped, true);
  assert.strictEqual(body.results[0].reason, "missing_whatsapp_credentials");
}

async function connectMessage() {
  const response = await handler({
    httpMethod: "POST",
    headers: {},
    body: JSON.stringify({
      entry: [
        {
          changes: [
            {
              value: {
                messages: [
                  {
                    from: "34600000000",
                    id: "wamid.connect",
                    text: { body: "CONNECT ABC123" },
                  },
                ],
              },
            },
          ],
        },
      ],
    }),
  });
  assert.strictEqual(response.statusCode, 200, response.body);
  const body = JSON.parse(response.body);
  assert.strictEqual(body.ok, true);
  assert.strictEqual(body.received, 1);
  assert.strictEqual(body.results[0].skipped, true);
  assert.strictEqual(body.results[0].reason, "missing_whatsapp_credentials");
}

async function connectGreeting() {
  process.env.WHATSAPP_ACCESS_TOKEN = "test-access-token";
  process.env.WHATSAPP_PHONE_NUMBER_ID = "test-phone-number-id";
  let outboundText = "";
  const originalFetch = global.fetch;
  global.fetch = async (_url, options) => {
    outboundText = JSON.parse(options.body).text.body;
    return {
      ok: true,
      json: async () => ({ ok: true }),
    };
  };

  try {
    const response = await handler({
      httpMethod: "POST",
      headers: {},
      body: JSON.stringify({
        entry: [
          {
            changes: [
              {
                value: {
                  messages: [
                    {
                      from: "34600000000",
                      id: "wamid.connect.greeting",
                      text: { body: "CONNECT ABC123" },
                    },
                  ],
                },
              },
            ],
          },
        ],
      }),
    });
    assert.strictEqual(response.statusCode, 200, response.body);
    assert.match(outboundText, /Hey! Blanked here/);
    assert.match(outboundText, /Connected/);
  } finally {
    global.fetch = originalFetch;
    delete process.env.WHATSAPP_ACCESS_TOKEN;
    delete process.env.WHATSAPP_PHONE_NUMBER_ID;
  }
}

async function linkIncludesRequestedApps() {
  process.env.SUPABASE_URL = "https://supabase.test";
  process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role";
  process.env.WHATSAPP_ACCESS_TOKEN = "test-access-token";
  process.env.WHATSAPP_PHONE_NUMBER_ID = "test-phone-number-id";
  let outboundText = "";
  const originalFetch = global.fetch;
  global.fetch = async (_url, options = {}) => {
    const memoryResponse = recentAssistantMemoryResponse(_url, options);
    if (memoryResponse) return memoryResponse;
    outboundText = JSON.parse(options.body).text.body;
    return {
      ok: true,
      json: async () => ({ ok: true }),
    };
  };

  try {
    const response = await handler({
      httpMethod: "POST",
      headers: {},
      body: JSON.stringify({
        entry: [
          {
            changes: [
              {
                value: {
                  messages: [
                    {
                      from: "34600000000",
                      id: "wamid.plan",
                      text: { body: "Block Instagram TikTok from 10 pm to 7 am every day" },
                    },
                  ],
                },
              },
            ],
          },
        ],
      }),
    });
    assert.strictEqual(response.statusCode, 200, response.body);
    assert.match(outboundText, /https:\/\/getblank\.netlify\.app\/open\?action=review-action/);
    assert.match(outboundText, /apps=(?:Instagram%2CTikTok|TikTok%2CInstagram)/);
  } finally {
    global.fetch = originalFetch;
    delete process.env.SUPABASE_URL;
    delete process.env.SUPABASE_SERVICE_ROLE_KEY;
    delete process.env.WHATSAPP_ACCESS_TOKEN;
    delete process.env.WHATSAPP_PHONE_NUMBER_ID;
  }
}

async function twilioButtonTemplateHidesRawUrlFromMainReply() {
  process.env.SUPABASE_URL = "https://supabase.test";
  process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role";
  process.env.TWILIO_ACCOUNT_SID = "ACtest";
  process.env.TWILIO_AUTH_TOKEN = "test-token";
  process.env.TWILIO_WHATSAPP_FROM_NUMBER = "+13478366767";
  process.env.TWILIO_WHATSAPP_REVIEW_CONTENT_SID = "HXbutton";
  process.env.TWILIO_WHATSAPP_REVIEW_TEMPLATE_ENABLED = "true";
  const requests = [];
  const originalFetch = global.fetch;
  global.fetch = async (_url, options = {}) => {
    const memoryResponse = recentAssistantMemoryResponse(_url, options);
    if (memoryResponse) return memoryResponse;
    const params = new URLSearchParams(options.body);
    requests.push(Object.fromEntries(params.entries()));
    return {
      ok: true,
      json: async () => ({ ok: true }),
    };
  };

  try {
    const response = await handler({
      httpMethod: "POST",
      headers: {},
      body: JSON.stringify({
        entry: [
          {
            changes: [
              {
                value: {
                  messages: [
                    {
                      from: "34600000000",
                      id: "wamid.button",
                      text: { body: "Block selected apps from 10 pm to 7 am every day" },
                    },
                  ],
                },
              },
            ],
          },
        ],
      }),
    });
    assert.strictEqual(response.statusCode, 200, response.body);
    assert.strictEqual(requests.length, 2);
    assert.doesNotMatch(requests[0].Body, /https?:\/\//);
    assert.strictEqual(requests[1].ContentSid, "HXbutton");
    assert.match(requests[1].ContentVariables, /open\?action=review-action/);
  } finally {
    global.fetch = originalFetch;
    delete process.env.SUPABASE_URL;
    delete process.env.SUPABASE_SERVICE_ROLE_KEY;
    delete process.env.TWILIO_ACCOUNT_SID;
    delete process.env.TWILIO_AUTH_TOKEN;
    delete process.env.TWILIO_WHATSAPP_FROM_NUMBER;
    delete process.env.TWILIO_WHATSAPP_REVIEW_CONTENT_SID;
    delete process.env.TWILIO_WHATSAPP_REVIEW_TEMPLATE_ENABLED;
  }
}

async function modePhraseOpensActivateModeLink() {
  process.env.WHATSAPP_ACCESS_TOKEN = "test-access-token";
  process.env.WHATSAPP_PHONE_NUMBER_ID = "test-phone-number-id";
  let outboundText = "";
  const originalFetch = global.fetch;
  global.fetch = async (_url, options) => {
    outboundText = JSON.parse(options.body).text.body;
    return {
      ok: true,
      json: async () => ({ ok: true }),
    };
  };

  try {
    const response = await handler({
      httpMethod: "POST",
      headers: {},
      body: JSON.stringify({
        entry: [
          {
            changes: [
              {
                value: {
                  messages: [
                    {
                      from: "34600000000",
                      id: "wamid.mode",
                      text: { body: "I'm in social mode now for 45 minutes" },
                    },
                  ],
                },
              },
            ],
          },
        ],
      }),
    });
    assert.strictEqual(response.statusCode, 200, response.body);
    assert.doesNotMatch(outboundText, /review-action/);
    assert.match(outboundText, /Which apps|Should it start now|How long/i);
  } finally {
    global.fetch = originalFetch;
    delete process.env.WHATSAPP_ACCESS_TOKEN;
    delete process.env.WHATSAPP_PHONE_NUMBER_ID;
  }
}

async function categoryRequestOpensActivateModeLink() {
  process.env.WHATSAPP_ACCESS_TOKEN = "test-access-token";
  process.env.WHATSAPP_PHONE_NUMBER_ID = "test-phone-number-id";
  let outboundText = "";
  const originalFetch = global.fetch;
  global.fetch = async (_url, options) => {
    outboundText = JSON.parse(options.body).text.body;
    return {
      ok: true,
      json: async () => ({ ok: true }),
    };
  };

  try {
    const response = await handler({
      httpMethod: "POST",
      headers: {},
      body: JSON.stringify({
        entry: [
          {
            changes: [
              {
                value: {
                  messages: [
                    {
                      from: "34600000000",
                      id: "wamid.social.category",
                      text: { body: "Block social media" },
                    },
                  ],
                },
              },
            ],
          },
        ],
      }),
    });
    assert.strictEqual(response.statusCode, 200, response.body);
    assert.doesNotMatch(outboundText, /review-action/);
    assert.match(outboundText, /Which apps|Should it start now|How long/i);
  } finally {
    global.fetch = originalFetch;
    delete process.env.WHATSAPP_ACCESS_TOKEN;
    delete process.env.WHATSAPP_PHONE_NUMBER_ID;
  }
}

async function whatsappAudioInputGetsTranscribedTextReply() {
  const previousApiKey = process.env.OPENAI_API_KEY;
  const previousAccessToken = process.env.WHATSAPP_ACCESS_TOKEN;
  const previousPhoneId = process.env.WHATSAPP_PHONE_NUMBER_ID;
  const originalFetch = global.fetch;
  let outboundText = "";
  let transcriptionCalled = false;
  process.env.OPENAI_API_KEY = "test-openai-key";
  process.env.WHATSAPP_ACCESS_TOKEN = "test-access-token";
  process.env.WHATSAPP_PHONE_NUMBER_ID = "test-phone-number-id";
  global.fetch = async (target, options = {}) => {
    const url = String(target);
    if (url === "https://graph.facebook.com/v26.0/audio-media") {
      return { ok: true, status: 200, json: async () => ({ url: "https://media.test/audio.ogg" }) };
    }
    if (url === "https://media.test/audio.ogg") {
      return {
        ok: true,
        status: 200,
        headers: { get: () => null },
        arrayBuffer: async () => Buffer.from("fake-audio"),
      };
    }
    if (url === "https://api.openai.com/v1/audio/transcriptions") {
      transcriptionCalled = true;
      return { ok: true, status: 200, text: async () => JSON.stringify({ text: "Hi, I need help with my focus." }) };
    }
    outboundText = JSON.parse(options.body).text.body;
    return { ok: true, json: async () => ({ ok: true }) };
  };

  try {
    const response = await handler({
      httpMethod: "POST",
      headers: {},
      body: JSON.stringify({
        entry: [{ changes: [{ value: { messages: [{
          from: "34600000002",
          id: "wamid.audio",
          audio: { id: "audio-media", mime_type: "audio/ogg" },
        }] } }] }],
      }),
    });
    assert.strictEqual(response.statusCode, 200, response.body);
    assert.strictEqual(JSON.parse(response.body).ok, true);
    assert.strictEqual(transcriptionCalled, true);
    assert.ok(outboundText);
  } finally {
    global.fetch = originalFetch;
    if (previousApiKey) process.env.OPENAI_API_KEY = previousApiKey; else delete process.env.OPENAI_API_KEY;
    if (previousAccessToken) process.env.WHATSAPP_ACCESS_TOKEN = previousAccessToken; else delete process.env.WHATSAPP_ACCESS_TOKEN;
    if (previousPhoneId) process.env.WHATSAPP_PHONE_NUMBER_ID = previousPhoneId; else delete process.env.WHATSAPP_PHONE_NUMBER_ID;
  }
}

async function duplicateInboundIsIgnoredAcrossRetries() {
  const previousSupabaseUrl = process.env.SUPABASE_URL;
  const previousSupabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const previousAccessToken = process.env.WHATSAPP_ACCESS_TOKEN;
  const previousPhoneId = process.env.WHATSAPP_PHONE_NUMBER_ID;
  const originalFetch = global.fetch;
  const rows = [];
  let outboundCount = 0;
  process.env.SUPABASE_URL = "https://supabase.test";
  process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role";
  process.env.WHATSAPP_ACCESS_TOKEN = "test-access-token";
  process.env.WHATSAPP_PHONE_NUMBER_ID = "test-phone-number-id";
  global.fetch = async (target, options = {}) => {
    const url = String(target);
    if (url.startsWith("https://supabase.test/rest/v1/")) {
      if ((options.method || "GET").toUpperCase() === "POST") {
        const row = JSON.parse(options.body || "{}");
        rows.push(row);
        return { ok: true, status: 201, text: async () => "", json: async () => ({}) };
      }
      return { ok: true, status: 200, text: async () => JSON.stringify(rows), json: async () => rows };
    }
    outboundCount += 1;
    return { ok: true, json: async () => ({ ok: true }) };
  };

  const event = {
    httpMethod: "POST",
    headers: {},
    body: JSON.stringify({
      entry: [{ changes: [{ value: { messages: [{
        from: "34600000003",
        id: "wamid.retry",
        text: { body: "Hi" },
      }] } }] }],
    }),
  };
  try {
    const first = await handler(event);
    const second = await handler(event);
    assert.strictEqual(first.statusCode, 200, first.body);
    assert.strictEqual(second.statusCode, 200, second.body);
    assert.strictEqual(JSON.parse(second.body).results[0].reason, "duplicate_inbound");
    assert.strictEqual(outboundCount, 1);
  } finally {
    global.fetch = originalFetch;
    if (previousSupabaseUrl) process.env.SUPABASE_URL = previousSupabaseUrl; else delete process.env.SUPABASE_URL;
    if (previousSupabaseKey) process.env.SUPABASE_SERVICE_ROLE_KEY = previousSupabaseKey; else delete process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (previousAccessToken) process.env.WHATSAPP_ACCESS_TOKEN = previousAccessToken; else delete process.env.WHATSAPP_ACCESS_TOKEN;
    if (previousPhoneId) process.env.WHATSAPP_PHONE_NUMBER_ID = previousPhoneId; else delete process.env.WHATSAPP_PHONE_NUMBER_ID;
  }
}

(async () => {
  await verifyWebhook();
  await receiveMessage();
  await connectMessage();
  await connectGreeting();
  await linkIncludesRequestedApps();
  await twilioButtonTemplateHidesRawUrlFromMainReply();
  await modePhraseOpensActivateModeLink();
  await categoryRequestOpensActivateModeLink();
  await whatsappAudioInputGetsTranscribedTextReply();
  await duplicateInboundIsIgnoredAcrossRetries();
  console.log("whatsapp-agent smoke tests passed");
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
