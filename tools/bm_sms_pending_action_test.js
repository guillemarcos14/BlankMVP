"use strict";

const assert = require("node:assert/strict");
process.env.OPENAI_API_KEY = "";
process.env.BM_SEMANTIC_PERSISTENCE = "legacy";
process.env.BLANKED_PUBLIC_APP_LINK_BASE = "https://getblank.netlify.app";

const channel = require("../netlify/functions/_assistant_channel");
let memory;

function reset() {
  memory = {
    user_context: {
      has_selected_apps: true,
      selected_app_names: ["Instagram"],
      screen_time_authorized: true,
      device_execution_ready: true,
      app_presence: { app_present: true, app_ready: true, last_seen_at: new Date().toISOString() },
    },
  };
}

channel.getAssistantMemory = async () => structuredClone(memory);
channel.ensureAssistantConnectionForPhone = async ({ channel: name, channelUser }) => ({
  channel: name,
  channelUser,
  connectCode: "ABC123",
  appInstallId: "install-sms",
});
channel.recordAssistantMemory = async ({ memory: patch }) => { memory = { ...memory, ...patch }; };
channel.recordAssistantConversationTurn = async ({ semanticState, userMessage, assistantMessage }) => {
  memory.conversation_state = {
    semantic_state: semanticState,
    updated_at: new Date().toISOString(),
    recent_messages: [{ role: "user", content: userMessage }, { role: "assistant", content: assistantMessage }],
  };
};

const { handler } = require("../netlify/functions/sms-agent");

async function send(input) {
  return handler({ httpMethod: "POST", body: new URLSearchParams({ From: "+34000000000", Body: input }).toString() });
}

async function prepare() {
  reset();
  await send("Block Instagram now for 18 minutes, once.");
  const response = await send("Yes");
  assert.match(response.body, /applying it now/i);
  assert.doesNotMatch(response.body, /Reply BLOCK|Open Blankmind|review-action/i);
  assert.equal(memory.pending_assistant_action.type, "start_protection");
  assert.equal(memory.pending_assistant_action.minutes, 18);
  assert.deepStrictEqual(memory.pending_assistant_action.app_names, ["Instagram"]);
}

async function run() {
  await prepare();
  const firstId = memory.pending_assistant_action.id;
  const open = await send("OPEN");
  assert.doesNotMatch(open.body, /review-action|minutes=18|Reply BLOCK/i, "OPEN must not expose a stale executable link");
  assert.equal(memory.pending_assistant_action.id, firstId, "A non-blocking follow-up must not replace the queued command");

  await prepare();
  await send("Actually make it 22 minutes.");
  assert.equal(memory.pending_assistant_action, null, "A correction must invalidate the previously confirmed command");

  await prepare();
  await send("Cancel that block.");
  assert.equal(memory.pending_assistant_action, null, "Cancellation must invalidate the queued command");

  await prepare();
  memory.pending_assistant_action.expires_at = new Date(Date.now() - 1).toISOString();
  const { normalizePendingAction } = require("../netlify/functions/assistant-channel");
  assert.equal(normalizePendingAction(memory.pending_assistant_action), null, "Expired commands must never execute");

  console.log("SMS pending action tests passed: autonomous queue, no review link, correction/cancellation and expiry");
}

run().catch((error) => { console.error(error); process.exitCode = 1; });
