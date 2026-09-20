const assert = require("assert");
const fs = require("fs");
const path = require("path");

process.env.SUPABASE_URL = "https://supabase.test";
process.env.SUPABASE_SERVICE_ROLE_KEY = "service-role";
process.env.OPENAI_API_KEY = "openai-test";
process.env.OPENAI_MODEL = "gpt-5.6-luna";
process.env.TWILIO_VALIDATE_WEBHOOK_SIGNATURE = "false";

const {
  OPENING_MESSAGE_1,
  OPENING_MESSAGE_2,
  parseMetaMessages,
  parseTwilioMessage,
  sendOpeningMessage,
} = require("../netlify/functions/_waitlist_whatsapp");
const {
  ageBand,
  deterministicFacts,
  generateReply,
  isRestrictedTopic,
  questionMemory,
  questionTopic,
  replyQualityIssues,
  safeReply,
  validateExtractedFacts,
} = require("../netlify/functions/_waitlist_ai");
const { handler } = require("../netlify/functions/waitlist-agent");
const { handler: waitlistStartHandler } = require("../netlify/functions/waitlist-start");
const { mergeValue } = require("../netlify/functions/_waitlist_store");

function response(status, body, headers = {}) {
  const text = typeof body === "string" ? body : JSON.stringify(body);
  return {
    ok: status >= 200 && status < 300,
    status,
    statusText: String(status),
    headers: { get: (name) => headers[String(name).toLowerCase()] || null },
    text: async () => text,
    json: async () => JSON.parse(text || "{}"),
    arrayBuffer: async () => Buffer.from(text),
  };
}

function openingContract() {
  assert.strictEqual(
    OPENING_MESSAGE_1,
    "Hey, I’m Blankmind. Tell me a bit about yourself.",
  );
  assert.strictEqual(
    OPENING_MESSAGE_2,
    "What should I call you? How old are you? What’s a normal day like for you? A voice note’s fine too, if that’s easier.",
  );
}

async function openingDeliveryContract() {
  const previous = {
    provider: process.env.WAITLIST_WHATSAPP_PROVIDER,
    sid: process.env.TWILIO_ACCOUNT_SID,
    token: process.env.TWILIO_AUTH_TOKEN,
    from: process.env.TWILIO_WHATSAPP_FROM_NUMBER,
    first: process.env.WAITLIST_WHATSAPP_OPENING_CONTENT_SID_1,
    second: process.env.WAITLIST_WHATSAPP_OPENING_CONTENT_SID_2,
  };
  process.env.WAITLIST_WHATSAPP_PROVIDER = "twilio";
  process.env.TWILIO_ACCOUNT_SID = "ACtest";
  process.env.TWILIO_AUTH_TOKEN = "token";
  process.env.TWILIO_WHATSAPP_FROM_NUMBER = "+13478366767";
  process.env.WAITLIST_WHATSAPP_OPENING_CONTENT_SID_1 = "HXopening1";
  process.env.WAITLIST_WHATSAPP_OPENING_CONTENT_SID_2 = "HXopening2";
  const requests = [];
  const fetchImpl = async (url, options) => {
    requests.push({ url, body: new URLSearchParams(options.body) });
    return response(201, { sid: `SM${requests.length}` });
  };
  try {
    const first = await sendOpeningMessage("+34600111222", 1, fetchImpl);
    const second = await sendOpeningMessage("+34600111222", 2, fetchImpl);
    assert.strictEqual(first.id, "SM1");
    assert.strictEqual(second.id, "SM2");
    assert.strictEqual(requests[0].body.get("ContentSid"), "HXopening1");
    assert.strictEqual(requests[1].body.get("ContentSid"), "HXopening2");
    assert.strictEqual(requests[0].body.get("To"), "whatsapp:+34600111222");
  } finally {
    const mapping = {
      WAITLIST_WHATSAPP_PROVIDER: previous.provider,
      TWILIO_ACCOUNT_SID: previous.sid,
      TWILIO_AUTH_TOKEN: previous.token,
      TWILIO_WHATSAPP_FROM_NUMBER: previous.from,
      WAITLIST_WHATSAPP_OPENING_CONTENT_SID_1: previous.first,
      WAITLIST_WHATSAPP_OPENING_CONTENT_SID_2: previous.second,
    };
    for (const [key, value] of Object.entries(mapping)) {
      if (value === undefined) delete process.env[key]; else process.env[key] = value;
    }
  }
}

async function smsOpeningDeliveryContract() {
  const previous = {
    sid: process.env.TWILIO_ACCOUNT_SID,
    token: process.env.TWILIO_AUTH_TOKEN,
    from: process.env.TWILIO_FROM_NUMBER,
    messagingServiceSid: process.env.TWILIO_MESSAGING_SERVICE_SID,
  };
  process.env.TWILIO_ACCOUNT_SID = "ACtest";
  process.env.TWILIO_AUTH_TOKEN = "token";
  process.env.TWILIO_FROM_NUMBER = "+13478366767";
  process.env.TWILIO_MESSAGING_SERVICE_SID = "MGtest";
  const state = {
    user: {
      id: "11111111-1111-4111-8111-111111111111",
      auth_user_id: "22222222-2222-4222-8222-222222222222",
      phone_e164: "+13475550123",
      status: "active",
      data_consent: true,
      whatsapp_consent: true,
      opening_first_sent_at: "2026-09-19T18:00:00.000Z",
      opening_second_sent_at: "2026-09-19T18:00:01.000Z",
      opening_sent_at: "2026-09-19T18:00:01.000Z",
      opening_sms_first_sent_at: null,
      opening_sms_second_sent_at: null,
    },
    twilio: [],
    events: [],
  };
  const previousFetch = global.fetch;
  global.fetch = async (url, options = {}) => {
    const value = String(url);
    if (value === "https://supabase.test/auth/v1/user") {
      return response(200, { id: state.user.auth_user_id, phone: state.user.phone_e164 });
    }
    if (value.includes("api.twilio.com/2010-04-01/Accounts/")) {
      const body = new URLSearchParams(options.body);
      state.twilio.push(body);
      return response(201, { sid: `SM-opening-${state.twilio.length}` });
    }
    if (!value.startsWith("https://supabase.test/rest/v1/")) throw new Error(`unexpected fetch ${value}`);
    const parsed = new URL(value);
    const resource = parsed.pathname.replace("/rest/v1/", "");
    const method = options.method || "GET";
    const body = options.body ? JSON.parse(options.body) : {};
    if (resource === "waitlist_users" && method === "GET") return response(200, [state.user]);
    if (resource === "waitlist_users" && method === "PATCH") {
      state.user = { ...state.user, ...body };
      return response(200, [state.user]);
    }
    if (resource === "waitlist_messages" && method === "POST") return response(201, [{ id: "message" }]);
    if (resource === "waitlist_events" && method === "POST") {
      state.events.push(body);
      return response(201, []);
    }
    throw new Error(`unexpected supabase operation ${method} ${resource}`);
  };

  try {
    const result = await waitlistStartHandler({
      httpMethod: "POST",
      headers: { authorization: "Bearer access-token" },
      body: JSON.stringify({ data_consent: true, messaging_consent: true, channel: "sms" }),
    });
    assert.strictEqual(result.statusCode, 200);
    const payload = JSON.parse(result.body);
    assert.deepStrictEqual(payload.sent, [1, 2]);
    assert.strictEqual(payload.channel, "sms");
    assert.strictEqual(state.twilio.length, 2);
    assert.strictEqual(state.twilio[0].get("To"), "+13475550123");
    assert.strictEqual(state.twilio[0].get("From"), null);
    assert.strictEqual(state.twilio[0].get("MessagingServiceSid"), "MGtest");
    assert.strictEqual(state.twilio[0].get("Body"), OPENING_MESSAGE_1);
    assert.strictEqual(state.twilio[1].get("Body"), OPENING_MESSAGE_2);
    assert.strictEqual(state.events[0].properties.channel, "sms");
  } finally {
    global.fetch = previousFetch;
    const mapping = {
      TWILIO_ACCOUNT_SID: previous.sid,
      TWILIO_AUTH_TOKEN: previous.token,
      TWILIO_FROM_NUMBER: previous.from,
      TWILIO_MESSAGING_SERVICE_SID: previous.messagingServiceSid,
    };
    for (const [key, value] of Object.entries(mapping)) {
      if (value === undefined) delete process.env[key]; else process.env[key] = value;
    }
  }
}

function extractionContract() {
  const message = "I'm Marta, I'm 29 and I work as a product designer. I end up on TikTok after work. My email is Marta@example.com.";
  const extracted = {
    facts: [
      { key: "preferred_name", value_text: "Marta", value_items: [], evidence: "Marta", confidence: "high", explicit: true, operation: "set" },
      { key: "age", value_text: "29", value_items: [], evidence: "I'm 29", confidence: "high", explicit: true, operation: "set" },
      { key: "occupation", value_text: "product designer", value_items: [], evidence: "I work as a product designer", confidence: "high", explicit: true, operation: "set" },
      { key: "apps", value_text: "", value_items: ["TikTok"], evidence: "TikTok", confidence: "high", explicit: true, operation: "add" },
      { key: "scroll_moments", value_text: "", value_items: ["after work"], evidence: "after work", confidence: "high", explicit: true, operation: "add" },
      { key: "email", value_text: "Marta@example.com", value_items: [], evidence: "Marta@example.com", confidence: "high", explicit: true, operation: "set" },
      { key: "impact", value_text: "anxious", value_items: [], evidence: "anxious", confidence: "high", explicit: false, operation: "set" },
      { key: "other_personal_context", value_text: "political preference", value_items: [], evidence: "Marta", confidence: "high", explicit: true, operation: "set" },
    ],
  };
  const facts = validateExtractedFacts(message, extracted);
  assert.strictEqual(facts.find((fact) => fact.key === "preferred_name").value, "Marta");
  assert.strictEqual(facts.find((fact) => fact.key === "age").value, 29);
  assert.strictEqual(facts.find((fact) => fact.key === "age_band").value, "25_34");
  assert.strictEqual(facts.find((fact) => fact.key === "email").value, "marta@example.com");
  assert.deepStrictEqual(facts.find((fact) => fact.key === "apps").value, ["TikTok"]);
  assert.ok(!facts.some((fact) => fact.key === "impact"), "inferred impact must be rejected");
  assert.ok(!facts.some((fact) => fact.key === "other_personal_context"), "sensitive inferred context must be rejected");
  assert.strictEqual(ageBand("I am 67"), "65_plus");
  const deterministic = deterministicFacts("My name is Marta and I am 29 years old.");
  assert.strictEqual(deterministic.find((fact) => fact.key === "preferred_name").value, "Marta");
  assert.strictEqual(deterministic.find((fact) => fact.key === "age").value, 29);
  assert.strictEqual(deterministic.find((fact) => fact.key === "age_band").value, "25_34");
}

function broadFactCaptureContract() {
  const message = "I study architecture part time, live with my partner, love cooking and running, and work late shifts. I feel tired after work, keep my phone beside me, and have tried leaving it in another room. I want to sleep earlier.";
  const extracted = {
    facts: [
      { key: "studies", value_text: "architecture part time", value_items: [], evidence: "I study architecture part time", confidence: "high", explicit: true, operation: "set" },
      { key: "relationships", value_text: "", value_items: ["my partner"], evidence: "live with my partner", confidence: "high", explicit: true, operation: "add" },
      { key: "interests", value_text: "", value_items: ["cooking", "running"], evidence: "love cooking and running", confidence: "high", explicit: true, operation: "add" },
      { key: "responsibilities", value_text: "late shifts", value_items: [], evidence: "work late shifts", confidence: "high", explicit: true, operation: "set" },
      { key: "feelings", value_text: "", value_items: ["tired"], evidence: "I feel tired", confidence: "high", explicit: true, operation: "add" },
      { key: "phone_relationship", value_text: "keeps phone beside them", value_items: [], evidence: "keep my phone beside me", confidence: "high", explicit: true, operation: "set" },
      { key: "attempted_solutions", value_text: "", value_items: ["leaving it in another room"], evidence: "tried leaving it in another room", confidence: "high", explicit: true, operation: "add" },
      { key: "desired_change", value_text: "sleep earlier", value_items: [], evidence: "I want to sleep earlier", confidence: "high", explicit: true, operation: "set" },
    ],
  };
  const facts = validateExtractedFacts(message, extracted);
  assert.deepStrictEqual(facts.map((fact) => fact.key), [
    "studies",
    "relationships",
    "interests",
    "responsibilities",
    "feelings",
    "phone_relationship",
    "attempted_solutions",
    "desired_change",
  ]);
  assert.deepStrictEqual(mergeValue(["Instagram"], ["TikTok"], "set", "apps"), ["Instagram", "TikTok"]);
  assert.deepStrictEqual(mergeValue(["Instagram"], ["TikTok"], "correct", "apps"), ["TikTok"]);
}

function safetyContract() {
  assert.strictEqual(isRestrictedTopic("What do you think about the war?"), true);
  assert.strictEqual(isRestrictedTopic("I work in design and scroll after meetings"), false);
  const cleaned = safeReply("**I hear you.** — Tell me more at https://example.com");
  assert.doesNotMatch(cleaned, /\*\*|—|https?:\/\//);
}

async function conversationMemoryContract() {
  const history = [
    {
      direction: "outbound",
      body: "After you put your phone down in the morning, what usually happens next?",
      created_at: "2026-09-20T00:13:52.000Z",
    },
    {
      direction: "inbound",
      body: "I go to eat breakfast and then I start working around 9am.",
      created_at: "2026-09-20T00:41:50.000Z",
    },
  ];
  assert.strictEqual(questionTopic(history[0].body), "after_scroll");
  assert.deepStrictEqual(questionMemory(history), [{
    topic: "after_scroll",
    question: history[0].body,
    answered: true,
    created_at: history[0].created_at,
  }]);
  assert.ok(replyQualityIssues("I’m curious what finally makes you put your phone down?", { history })
    .includes("repeated_question:after_scroll"));
  assert.deepStrictEqual(replyQualityIssues("I’m curious how that morning affects the rest of your day?", { history }), []);

  const previousPolish = process.env.WAITLIST_CONVERSATION_POLISH;
  process.env.WAITLIST_CONVERSATION_POLISH = "false";
  let calls = 0;
  try {
    const result = await generateReply({
      message: "The alarm goes off and I start scrolling straight away.",
      history: [...history, {
        direction: "inbound",
        body: "The alarm goes off and I start scrolling straight away.",
        created_at: "2026-09-20T00:44:16.000Z",
      }],
      profile: {},
      newlySavedFacts: [],
      fetchImpl: async (url, options) => {
        assert.strictEqual(url, "https://api.openai.com/v1/responses");
        calls += 1;
        const request = JSON.parse(options.body);
        const input = request.input[1].content[0].text;
        assert.match(input, /question_memory/);
        if (calls === 1) {
          return response(200, {
            output_text: JSON.stringify({
              reply: "I’m curious what finally makes you put your phone down after that scroll?",
              focus: "scroll_context",
              profile_useful: false,
            }),
          });
        }
        assert.strictEqual(request.text.format.name, "waitlist_conversation_reply_repair");
        return response(200, {
          output_text: JSON.stringify({
            reply: "I’m curious how that first scroll changes the rest of your morning?",
            focus: "impact",
            profile_useful: false,
          }),
        });
      },
    });
    assert.strictEqual(calls, 2, "a repeated question must be repaired before delivery");
    assert.doesNotMatch(result.reply, /put your phone down/i);
  } finally {
    if (previousPolish === undefined) delete process.env.WAITLIST_CONVERSATION_POLISH;
    else process.env.WAITLIST_CONVERSATION_POLISH = previousPolish;
  }
}

function providerParsingContract() {
  const meta = parseMetaMessages({
    entry: [{ changes: [{ value: { messages: [{ id: "wamid.1", from: "34600111222", text: { body: "Hello" } }] } }] }],
  });
  assert.strictEqual(meta[0].phone, "+34600111222");
  assert.strictEqual(meta[0].text, "Hello");

  const body = new URLSearchParams({
    From: "whatsapp:+34600111222",
    Body: "Hello",
    MessageSid: "SM1",
  }).toString();
  const twilio = parseTwilioMessage({ body, headers: { "content-type": "application/x-www-form-urlencoded" } });
  assert.strictEqual(twilio[0].phone, "+34600111222");
  assert.strictEqual(twilio[0].providerMessageId, "SM1");
}

async function fullTurnContract(from = "whatsapp:+34600111222") {
  const state = {
    user: {
      id: "11111111-1111-4111-8111-111111111111",
      auth_user_id: "22222222-2222-4222-8222-222222222222",
      phone_e164: "+34600111222",
      status: "active",
      data_consent: true,
      whatsapp_consent: true,
      first_reply_at: null,
      profile_useful_at: null,
    },
    messages: [],
    facts: [],
    events: [],
    responseCalls: 0,
  };
  const previousFetch = global.fetch;
  global.fetch = async (url, options = {}) => {
    const value = String(url);
    if (value === "https://api.openai.com/v1/responses") {
      state.responseCalls += 1;
      const request = JSON.parse(options.body);
      const schemaName = request.text.format.name;
      if (schemaName === "waitlist_fact_extraction") {
        return response(200, {
          output_text: JSON.stringify({ facts: [
            { key: "occupation", value_text: "architect", value_items: [], evidence: "I work as an architect", confidence: "high", explicit: true, operation: "set" },
            { key: "apps", value_text: "", value_items: ["Instagram"], evidence: "Instagram", confidence: "high", explicit: true, operation: "add" },
            { key: "scroll_moments", value_text: "", value_items: ["after client calls"], evidence: "after client calls", confidence: "high", explicit: true, operation: "add" },
          ] }),
        });
      }
      if (schemaName === "waitlist_conversation_reply") {
        assert.match(request.input[0].content[0].text, /work, studies, routines/i);
        assert.match(request.input[0].content[0].text, /wars, armed conflicts, abortion/i);
      }
      return response(200, {
        output_text: JSON.stringify({
          reply: "I can see how those client calls leave you looking for a quick reset. What tends to keep you on Instagram once you open it?",
          focus: "scroll_context",
          profile_useful: false,
        }),
      });
    }
    if (!value.startsWith("https://supabase.test/rest/v1/")) throw new Error(`unexpected fetch ${value}`);
    const parsed = new URL(value);
    const resource = parsed.pathname.replace("/rest/v1/", "");
    const method = options.method || "GET";
    const body = options.body ? JSON.parse(options.body) : {};
    if (resource === "rpc/claim_waitlist_inbound") return response(200, [{ claimed: true, status: "claimed" }]);
    if (resource === "rpc/complete_waitlist_inbound" || resource === "rpc/release_waitlist_inbound") return response(200, true);
    if (resource === "waitlist_users" && method === "GET") return response(200, [state.user]);
    if (resource === "waitlist_users" && method === "PATCH") {
      state.user = { ...state.user, ...body };
      return response(200, [state.user]);
    }
    if (resource === "waitlist_messages" && method === "POST") {
      const row = { id: `message-${state.messages.length + 1}`, created_at: new Date().toISOString(), ...body };
      state.messages.push(row);
      return response(201, [row]);
    }
    if (resource === "waitlist_messages" && method === "GET") return response(200, [...state.messages].reverse());
    if (resource === "waitlist_facts" && method === "GET") return response(200, state.facts.filter((fact) => ["confirmed", "uncertain"].includes(fact.status)));
    if (resource === "waitlist_facts" && method === "POST") {
      const row = { id: `fact-${state.facts.length + 1}`, created_at: new Date().toISOString(), ...body };
      state.facts.push(row);
      return response(201, [row]);
    }
    if (resource === "waitlist_facts" && method === "PATCH") {
      const id = parsed.searchParams.get("id")?.replace("eq.", "");
      const row = state.facts.find((fact) => fact.id === id);
      if (row) Object.assign(row, body);
      return response(200, row ? [row] : []);
    }
    if (resource === "waitlist_events" && method === "POST") {
      state.events.push(body);
      return response(201, []);
    }
    throw new Error(`unexpected supabase operation ${method} ${resource}`);
  };

  try {
    const body = new URLSearchParams({
      From: from,
      Body: "I work as an architect and I open Instagram after client calls.",
      MessageSid: "SM-turn-1",
    }).toString();
    const result = await handler({
      httpMethod: "POST",
      path: "/.netlify/functions/waitlist-agent",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body,
    });
    assert.strictEqual(result.statusCode, 200);
    assert.match(result.body, /<Response><Message>/);
    assert.match(result.body, /client calls leave you looking for a quick reset/i);
    assert.strictEqual(state.responseCalls, 3, "extraction, conversation, and natural-language polish are required");
    assert.deepStrictEqual(state.facts.map((fact) => fact.field_key).sort(), ["apps", "occupation", "scroll_moments"]);
    assert.ok(state.messages.some((message) => message.direction === "inbound"));
    assert.ok(state.messages.some((message) => message.direction === "outbound"));
    assert.ok(state.events.some((event) => event.event_name === "waitlist_turn_completed"));
  } finally {
    global.fetch = previousFetch;
  }
}

function isolationContract() {
  const source = fs.readFileSync(path.join(__dirname, "../netlify/functions/waitlist-agent.js"), "utf8");
  assert.doesNotMatch(source, /require\(["']\.\/blanked-agent["']\)/);
  assert.doesNotMatch(source, /require\(["']\.\/_assistant_channel["']\)/);
  assert.doesNotMatch(source, /start_protection|apply_schedule|set_daily_limit|assistant-channel/);
  const migration = fs.readFileSync(path.join(__dirname, "../supabase/migrations/019_waitlist_early_access.sql"), "utf8");
  for (const table of ["waitlist_users", "waitlist_messages", "waitlist_facts", "waitlist_events"]) {
    assert.match(migration, new RegExp(`create table if not exists public\\.${table}`));
  }
  const page = fs.readFileSync(path.join(__dirname, "../web/landing/early-access.html"), "utf8");
  const client = fs.readFileSync(path.join(__dirname, "../web/landing/early-access.js"), "utf8");
  assert.match(page, /securely process this conversation, including voice-note transcripts/i);
  assert.match(client, /waitlist-start/);
  assert.match(client, /channel\s*[,}]/);
  assert.match(client, /messaging_consent:\s*true/);
}

async function main() {
  openingContract();
  await openingDeliveryContract();
  await smsOpeningDeliveryContract();
  extractionContract();
  broadFactCaptureContract();
  safetyContract();
  await conversationMemoryContract();
  providerParsingContract();
  isolationContract();
  await fullTurnContract("whatsapp:+34600111222");
  await fullTurnContract("+34600111222");
  console.log("waitlist early access tests passed");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
