"use strict";
const assert = require("node:assert/strict");
process.env.OPENAI_API_KEY = "";
process.env.BM_SEMANTIC_PERSISTENCE = "legacy"; // In-memory transport diagnostic; CAS is tested separately.
process.env.BLANKED_PUBLIC_APP_LINK_BASE = "https://getblank.netlify.app";
const channel = require("../netlify/functions/_assistant_channel");
let memory;
let rejectAudit = false;
function reset() {
  memory = { user_context: {
    has_selected_apps: true, selected_app_names: ["Instagram"], screen_time_authorized: true,
    app_presence: { app_present: true, app_ready: true, last_seen_at: new Date().toISOString() },
  } };
  rejectAudit = false;
}
channel.getAssistantMemory = async () => structuredClone(memory);
channel.ensureAssistantConnectionForPhone = async () => null;
channel.recordAssistantMemory = async ({ memory: patch }) => {
  if (rejectAudit) throw new Error("audit_unavailable");
  memory = { ...memory, ...patch };
};
channel.recordAssistantConversationTurn = async ({ semanticState, userMessage, assistantMessage }) => {
  memory.conversation_state = { semantic_state: semanticState, updated_at: new Date().toISOString(),
    recent_messages: [{ role: "user", content: userMessage }, { role: "assistant", content: assistantMessage }] };
};
const { handler, pendingActionFromMemory } = require("../netlify/functions/sms-agent");
async function send(input) {
  return handler({ httpMethod: "POST", body: new URLSearchParams({ From: "+34000000000", Body: input }).toString() });
}
async function prepare() {
  reset();
  await send("Block Instagram now for 18 minutes, once.");
  const response = await send("Yes");
  assert.match(response.body, /Reply BLOCK/);
  assert.ok(pendingActionFromMemory(memory), "Confirmed current proposal is available");
}
async function prepareWithoutPresence() {
  memory = { user_context: { screen_time_authorized: true, app_presence: {} } };
  await send("Block Instagram from 22:00 to 23:00 every day for 3 days.");
  const response = await send("Yes");
  assert.match(response.body, /Reply BLOCK/);
  assert.ok(pendingActionFromMemory(memory), "Confirmed proposal remains reviewable before a fresh heartbeat");
}
async function run() {
  await prepare();
  const valid = await send("OPEN");
  assert.match(valid.body, /action=review-action/);
  assert.match(valid.body, /minutes=18/);
  assert.equal(memory.pending_action_link, null);

  await prepare();
  await send("Actually make it 22 minutes.");
  assert.equal(memory.pending_action_link, null);
  assert.doesNotMatch((await send("OPEN")).body, /review-action|minutes=18/);

  await prepare();
  rejectAudit = true; // Even failed cache deletion cannot override the new canonical fingerprint.
  await send("Actually make it 22 minutes.");
  assert.ok(memory.pending_action_link);
  assert.doesNotMatch((await send("OPEN")).body, /review-action/);

  await prepare();
  await send("Cancel that block.");
  assert.doesNotMatch((await send("OPEN")).body, /review-action/);

  await prepare();
  memory.pending_action_expires_at = new Date(Date.now() - 1).toISOString();
  assert.doesNotMatch((await send("OPEN")).body, /review-action/);
  await prepare();
  delete memory.pending_action_expires_at;
  delete memory.pending_proposal_fingerprint;
  assert.doesNotMatch((await send("OPEN")).body, /review-action/);

  await prepare();
  memory.pending_action_link = memory.pending_action_link.replace("minutes=18", "minutes=99");
  assert.doesNotMatch((await send("OPEN")).body, /review-action/);
  await prepare();
  memory.pending_action_link = memory.pending_action_link.replace("action=review-action", "action=start-focus");
  assert.doesNotMatch((await send("OPEN")).body, /start-focus/);

  await prepareWithoutPresence();
  const reviewBeforeHeartbeat = await send("OPEN");
  assert.match(reviewBeforeHeartbeat.body, /action=review-action/);
  assert.match(reviewBeforeHeartbeat.body, /type=apply_schedule/);
  console.log("SMS pending action tests passed: current review, correction/cancellation, failed deletion, expiry, legacy and tampered-link rejection");
}
run().catch((error) => { console.error(error); process.exitCode = 1; });
