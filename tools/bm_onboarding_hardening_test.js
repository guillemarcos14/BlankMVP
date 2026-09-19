"use strict";

const assert = require("assert");

process.env.SUPABASE_URL = "https://supabase.test";
process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role";
delete process.env.APNS_KEY_P8;
delete process.env.APNS_KEY_ID;
delete process.env.APNS_TEAM_ID;

const {
  ONBOARDING_VERSION,
  onboardingMessages,
  queueOnboardingPicker,
  markOnboardingDispatched,
  onboardingProgress,
  dispatchWhatsAppOnboarding,
} = require("../netlify/functions/bm-onboarding");

async function run() {
  const originalFetch = global.fetch;
  const posts = [];
  const activeAction = {
    id: "existing-action",
    fingerprint: "existing-fingerprint",
    type: "start_protection",
    minutes: 20,
    status: "queued",
    source: "assistant",
    expires_at: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
  };
  let memory = { pending_assistant_action: activeAction };

  global.fetch = async (target, options = {}) => {
    const method = String(options.method || "GET").toUpperCase();
    if (!String(target).startsWith("https://supabase.test/rest/v1/digital_wellness_feature_payloads")) {
      throw new Error(`unexpected_fetch:${target}`);
    }
    if (method === "POST") {
      const row = JSON.parse(options.body || "{}");
      posts.push(row);
      memory = { ...memory, ...(row.payload?.properties?.memory || {}) };
      return { ok: true, status: 201, text: async () => "", json: async () => ({}) };
    }
    const rows = [{
      payload: { event: "assistant_memory_updated", properties: { memory } },
      submitted_at: new Date().toISOString(),
    }];
    return { ok: true, status: 200, text: async () => JSON.stringify(rows), json: async () => rows };
  };

  try {
    const preserved = await queueOnboardingPicker({
      channel: "whatsapp",
      channelUser: "+34600000009",
      messages: onboardingMessages({}),
    });
    assert.strictEqual(preserved.preserved, true);
    assert.strictEqual(preserved.action.id, activeAction.id);
    assert.strictEqual(preserved.push.reason, "existing_action_preserved");
    assert.strictEqual(posts.length, 0, "onboarding replaced or mutated an active action");

    await markOnboardingDispatched("whatsapp", "+34600000009", {
      welcomeAccepted: true,
      setupAccepted: true,
      buttonRequired: false,
      buttonAccepted: true,
    });
    const update = posts.at(-1)?.payload?.properties?.memory || {};
    assert.strictEqual(update.assistant_onboarding_version, ONBOARDING_VERSION);
    assert.strictEqual(update.assistant_onboarding_status, "dispatched");
    assert.strictEqual(update.assistant_onboarding_delivery.welcome_accepted, true);

    memory = {};
    posts.length = 0;
    const messages = onboardingMessages({});
    const firstAttemptBodies = [];
    const firstAttempt = await dispatchWhatsAppOnboarding({
      channel: "whatsapp",
      channelUser: "+34600000009",
      messages,
      progress: {},
      sendMessage: async (_to, body) => {
        firstAttemptBodies.push(body);
        return body === messages.setup ? { skipped: true, reason: "temporary_provider_failure" } : { sid: "welcome-1" };
      },
    });
    assert.strictEqual(firstAttempt.dispatched, false);
    assert.deepStrictEqual(firstAttemptBodies, [messages.welcome, messages.setup]);
    assert.strictEqual(onboardingProgress(memory).welcomeAccepted, true);
    assert.strictEqual(onboardingProgress(memory).setupAccepted, false);

    const resumedBodies = [];
    const resumed = await dispatchWhatsAppOnboarding({
      channel: "whatsapp",
      channelUser: "+34600000009",
      messages,
      progress: onboardingProgress(memory),
      sendMessage: async (_to, body) => {
        resumedBodies.push(body);
        return { sid: "setup-2" };
      },
    });
    assert.strictEqual(resumed.dispatched, true);
    assert.deepStrictEqual(resumedBodies, [messages.setup], "retry duplicated an already accepted welcome message");
  } finally {
    global.fetch = originalFetch;
  }

  console.log("bm onboarding hardening tests passed");
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
