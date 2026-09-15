const assert = require("assert");

process.env.OPENAI_API_KEY = "";
process.env.SUPABASE_URL = "https://supabase.test";
process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role";
process.env.BLANKED_PUBLIC_APP_LINK_BASE = "https://getblank.netlify.app";
delete process.env.TWILIO_ACCOUNT_SID;
delete process.env.TWILIO_AUTH_TOKEN;
delete process.env.TWILIO_FROM_NUMBER;
delete process.env.TWILIO_MESSAGING_SERVICE_SID;

const { handler: whatsappHandler } = require("../netlify/functions/whatsapp-agent");
const { handler: smsHandler } = require("../netlify/functions/sms-agent");
const { handler: agentHandler } = require("../netlify/functions/blanked-agent");
const { buildAgentContext } = require("../netlify/functions/bm-context");

function seededMemory() {
  return {
    user_context: {
      has_selected_apps: true,
      selection_count: 3,
      screen_time_authorized: true,
      app_presence: {
        app_present: true,
        app_ready: true,
        last_seen_at: new Date().toISOString(),
      },
    },
  };
}

function seededRow() {
  return {
    payload: {
      event: "assistant_memory_updated",
      properties: { memory: seededMemory() },
    },
    submitted_at: new Date().toISOString(),
  };
}

async function withMemoryStore(callback) {
  const rows = new Map();
  const originalFetch = global.fetch;
  let clock = Date.now();
  global.fetch = async (target, options = {}) => {
    const url = String(target);
    if (!url.startsWith("https://supabase.test/rest/v1/")) {
      return {
        ok: true,
        status: 200,
        json: async () => ({ ok: true }),
        text: async () => "",
      };
    }
    const method = (options.method || "GET").toUpperCase();
    const isMemoryEvent = url.includes("digital_wellness_feature_payloads");
    if (method === "POST" && isMemoryEvent) {
      const row = JSON.parse(options.body || "{}");
      const list = rows.get(row.anonymous_user_id) || [seededRow()];
      list.push({ payload: row.payload, submitted_at: new Date(++clock).toISOString() });
      rows.set(row.anonymous_user_id, list);
      return { ok: true, status: 201, json: async () => ({}), text: async () => "" };
    }
    if (method === "GET" && isMemoryEvent) {
      const match = url.match(/anonymous_user_id=eq\.([^&]+)/);
      const key = match ? decodeURIComponent(match[1]) : "";
      const result = rows.get(key) || [seededRow()];
      return { ok: true, status: 200, json: async () => result, text: async () => JSON.stringify(result) };
    }
    return { ok: true, status: 200, json: async () => [], text: async () => "[]" };
  };
  try {
    return await callback();
  } finally {
    global.fetch = originalFetch;
  }
}

function whatsappEvent(from, textValue, id) {
  return {
    httpMethod: "POST",
    headers: {},
    body: JSON.stringify({
      entry: [{ changes: [{ value: { messages: [{ from, id, text: { body: textValue } }] } }] }],
    }),
  };
}

function smsEvent(from, textValue, id) {
  return {
    httpMethod: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded", host: "getblank.netlify.app" },
    body: new URLSearchParams({ From: from, Body: textValue, MessageSid: id }).toString(),
  };
}

async function whatsappKeepsBedtimeQuestion() {
  const outbound = [];
  process.env.WHATSAPP_ACCESS_TOKEN = "test-access-token";
  process.env.WHATSAPP_PHONE_NUMBER_ID = "test-phone-number-id";
  try {
    await withMemoryStore(async () => {
      const memoryFetch = global.fetch;
      global.fetch = async (target, options = {}) => {
        const url = String(target);
        if (url.startsWith("https://graph.facebook.com/")) {
          outbound.push(JSON.parse(options.body).text.body);
          return { ok: true, status: 200, json: async () => ({ ok: true }), text: async () => "" };
        }
        return memoryFetch(target, options);
      };
      try {
        const first = await whatsappHandler(whatsappEvent("34600000010", "How can I scroll less at night?", "wa-memory-1"));
        assert.strictEqual(first.statusCode, 200, first.body);
        const second = await whatsappHandler(whatsappEvent("34600000010", "11pm", "wa-memory-2"));
        assert.strictEqual(second.statusCode, 200, second.body);
      } finally {
        global.fetch = memoryFetch;
      }
    });
  } finally {
    delete process.env.WHATSAPP_ACCESS_TOKEN;
    delete process.env.WHATSAPP_PHONE_NUMBER_ID;
  }
  assert.ok(outbound.length >= 2, "WhatsApp should send both replies");
  assert.match(outbound[0], /asleep|bedtime/i);
  assert.match(outbound[1], /10:30 PM/);
  assert.match(outbound[1], /11:00 PM/);
  assert.doesNotMatch(outbound[1], /I'm here\. Tell me what's going on/i);
}

async function smsKeepsBedtimeQuestion() {
  await withMemoryStore(async () => {
    const first = await smsHandler(smsEvent("+34600000011", "How can I scroll less at night?", "sms-memory-1"));
    assert.strictEqual(first.statusCode, 200, first.body);
    const second = await smsHandler(smsEvent("+34600000011", "11pm", "sms-memory-2"));
    assert.strictEqual(second.statusCode, 200, second.body);
    assert.match(second.body, /10:30 PM/);
    assert.match(second.body, /11:00 PM/);
    assert.doesNotMatch(second.body, /I'm here\. Tell me what's going on/i);
  });
}

async function webContextKeepsBedtimeQuestion() {
  const first = await agentHandler({
    httpMethod: "POST",
    body: JSON.stringify({
      prompt: "How can I scroll less at night?",
      context: { channel: "web_preview", assistant_channel: "web", web_preview: true },
    }),
  });
  const firstPlan = JSON.parse(first.body).plan;
  const second = await agentHandler({
    httpMethod: "POST",
    body: JSON.stringify({
      prompt: "11pm",
      context: {
        channel: "web_preview",
        assistant_channel: "web",
        web_preview: true,
        recent_messages: [
          { role: "user", content: "How can I scroll less at night?" },
          { role: "assistant", content: firstPlan.message_text },
        ],
      },
    }),
  });
  const secondPlan = JSON.parse(second.body).plan;
  assert.match(secondPlan.message_text, /10:30 AM|10:30 PM/);
  assert.match(secondPlan.message_text, /11:00 AM|11:00 PM/);
  assert.doesNotMatch(secondPlan.message_text, /I'm here\. Tell me what's on my mind/i);
}

function expiredConversationIsIgnored() {
  const context = buildAgentContext({
    memory: {
      conversation_state: {
        updated_at: new Date(Date.now() - 3 * 60 * 60 * 1000).toISOString(),
        pending_slot: "bedtime",
        recent_messages: [{ role: "assistant", content: "Tell me your usual bedtime." }],
      },
    },
  });
  assert.deepStrictEqual(context.recent_messages, []);
  assert.strictEqual(context.memory.conversation_state, undefined);
}

(async () => {
  expiredConversationIsIgnored();
  await whatsappKeepsBedtimeQuestion();
  await smsKeepsBedtimeQuestion();
  await webContextKeepsBedtimeQuestion();
  console.log("assistant conversation memory tests passed");
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
