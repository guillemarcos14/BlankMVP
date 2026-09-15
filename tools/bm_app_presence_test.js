"use strict";

const assert = require("assert");

process.env.OPENAI_API_KEY = "";
process.env.BLANKMIND_APP_DOWNLOAD_URL = "https://apps.apple.com/es/app/blanked/id6789519152";

const { buildAgentContext, deriveAppPresence } = require("../netlify/functions/bm-context");
const { recordAssistantUserContext } = require("../netlify/functions/_assistant_channel");
const { handler } = require("../netlify/functions/blanked-agent");

function request(prompt, context) {
  return handler({
    httpMethod: "POST",
    body: JSON.stringify({ prompt, context }),
  }).then((response) => {
    assert.strictEqual(response.statusCode, 200, response.body);
    return JSON.parse(response.body).plan;
  });
}

async function run() {
  const now = Date.now();
  assert.strictEqual(deriveAppPresence({}).state, "never_seen");
  assert.strictEqual(
    deriveAppPresence({ app_present: true, last_seen_at: new Date(now - 48 * 60 * 60 * 1000).toISOString() }, now).state,
    "stale",
  );
  assert.strictEqual(
    deriveAppPresence({ app_present: true, app_ready: true, last_seen_at: new Date(now - 60 * 60 * 1000).toISOString() }, now).ready,
    true,
  );

  const neverSeen = buildAgentContext({ channel: "whatsapp" });
  assert.strictEqual(neverSeen.app_presence_state, "never_seen");
  assert.strictEqual(neverSeen.app_presence_recent, false);
  assert.strictEqual(neverSeen.app_ready, false);

  const recent = buildAgentContext({
    channel: "whatsapp",
    has_selected_apps: true,
    screen_time_authorized: true,
    app_presence: {
      app_present: true,
      app_ready: true,
      last_seen_at: new Date(now - 60 * 60 * 1000).toISOString(),
    },
  });
  assert.strictEqual(recent.app_presence_state, "recently_seen");
  assert.strictEqual(recent.app_presence_recent, true);
  assert.strictEqual(recent.app_ready, true);

  process.env.SUPABASE_URL = "https://supabase.test";
  process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role";
  const originalFetch = global.fetch;
  let syncedRow = null;
  global.fetch = async (target, options = {}) => {
    if (String(target).startsWith("https://supabase.test/rest/v1/digital_wellness_feature_payloads")) {
      syncedRow = JSON.parse(options.body || "{}");
      return { ok: true, status: 201, text: async () => "", json: async () => ({}) };
    }
    return originalFetch(target, options);
  };
  try {
    await recordAssistantUserContext({
      connectCode: "ABC123",
      channel: "whatsapp",
      context: {
        app_presence: {
          app_present: true,
          app_ready: true,
          last_seen_at: new Date(now - 7 * 24 * 60 * 60 * 1000).toISOString(),
        },
      },
    });
  } finally {
    global.fetch = originalFetch;
  }
  const serverSeenAt = syncedRow?.payload?.properties?.context?.app_presence?.last_seen_at;
  assert.ok(serverSeenAt && Date.now() - Date.parse(serverSeenAt) < 5000);
  assert.strictEqual(syncedRow.payload.properties.context.app_presence.source, "assistant_context_sync");

  const installGuidance = await request("Block Instagram from 10 pm to 7 am every day", { channel: "whatsapp" });
  assert.strictEqual(installGuidance.actions.length, 0);
  assert.match(installGuidance.message_text, /Blankmind/);
  assert.match(installGuidance.message_text, /apps\.apple\.com/);
  assert.match(installGuidance.message_text, /If you already have it|Si ya la tienes/);
  assert.doesNotMatch(installGuidance.message_text, /review-action/);

  const incompleteRequest = await request("Block Instagram", { channel: "whatsapp" });
  assert.strictEqual(incompleteRequest.actions.length, 0);
  assert.match(incompleteRequest.message_text, /what time|Should it start|a qué hora|hora/i);
  assert.doesNotMatch(incompleteRequest.message_text, /apps\.apple\.com|download|descarga/i);

  const staleGuidance = await request(
    "Block Instagram from 10 pm to 7 am every day",
    {
      channel: "sms",
      app_presence: {
        app_present: true,
        app_ready: true,
        last_seen_at: new Date(now - 48 * 60 * 60 * 1000).toISOString(),
      },
    },
  );
  assert.strictEqual(staleGuidance.actions.length, 0);
  assert.match(staleGuidance.message_text, /If you no longer have it installed/);

  const recentPlan = await request(
    "Block Instagram from 10 pm to 7 am every day",
    {
      channel: "whatsapp",
      has_selected_apps: true,
      screen_time_authorized: true,
      app_presence: {
        app_present: true,
        app_ready: true,
        last_seen_at: new Date(now - 60 * 60 * 1000).toISOString(),
      },
    },
  );
  assert.ok(recentPlan.actions.length > 0);
  assert.doesNotMatch(recentPlan.message_text, /apps\.apple\.com|download it here|descárgala aquí/);

  const confirmedWindowContext = [
    { role: "user", content: "How can I scroll less in the morning?" },
    { role: "assistant", content: "Got it. Before making a block, tell me where the scrolling usually starts: app, moment, or time of day." },
    { role: "user", content: "Instagram around 11am" },
    { role: "assistant", content: "Got it: Instagram is the app and 11:00 AM is when it starts. What time should the protection end?" },
    { role: "user", content: "At 12" },
    { role: "assistant", content: "Got it: protect Instagram from 11:00 AM to 12:00 PM. Do you want me to use that as the morning protection window?" },
  ];
  const confirmedWithoutPresence = await request("yes", {
    channel: "whatsapp",
    recent_messages: confirmedWindowContext,
  });
  assert.deepStrictEqual(confirmedWithoutPresence.actions.map((item) => item.type), ["apply_schedule"]);
  assert.match(confirmedWithoutPresence.message_text, /Open Blankmind|Blankmind/);
  assert.doesNotMatch(confirmedWithoutPresence.message_text, /apps\.apple\.com|download|create a plan/i);
  const installedContinuation = await request("I have it", {
    channel: "whatsapp",
    recent_messages: [
      ...confirmedWindowContext,
      { role: "user", content: "yes" },
      { role: "assistant", content: confirmedWithoutPresence.message_text },
    ],
  });
  assert.deepStrictEqual(installedContinuation.actions.map((item) => item.type), ["apply_schedule"]);
  assert.match(installedContinuation.message_text, /plan|review/i);
  assert.doesNotMatch(installedContinuation.message_text, /apps\.apple\.com|download|create a plan/i);

  const smallTalk = await request("Hey", { channel: "whatsapp" });
  assert.doesNotMatch(smallTalk.message_text, /apps\.apple\.com|download|descarga/i);

  console.log("BM app presence tests passed");
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
