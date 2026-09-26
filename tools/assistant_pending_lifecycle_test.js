"use strict";
const assert = require("node:assert/strict");
process.env.BM_SEMANTIC_PERSISTENCE = "required";
const membership = require("../netlify/functions/_membership");
const identity = require("../netlify/functions/_identity");
const push = require("../netlify/functions/_assistant_push");
const turnId = "11111111-1111-4111-8111-111111111111";
const actionId = `app_${turnId}`;
const owner = { auth_user_id: "owner-1", app_install_id: "install-1", assistant_connect_code: "ABCDEFGH23", phone_e164: "+15555550101" };
let memory;
let savedReceipt;
let beforeTransition;
let pushes = 0;
const history = new Map();
const operations = [];
membership.supabaseFetch = async (path, options = {}) => {
  if (path.startsWith("assistant_app_turns?")) {
    const query = new URLSearchParams(path.split("?")[1]);
    assert.equal(query.get("auth_user_id"), `eq.${owner.auth_user_id}`);
    assert.equal(query.get("action_id"), `eq.${actionId}`);
    savedReceipt = JSON.parse(options.body).action_status;
    operations.push("receipt");
    return [{ id: turnId }];
  }
  if (path.startsWith("digital_wellness_feature_payloads?")) {
    const query = new URLSearchParams(path.split("?")[1]);
    assert.equal(query.get("anonymous_user_id"), `eq.${channel.assistantChannelUserId("whatsapp", owner.phone_e164)}`);
    const snapshot = history.get(actionId);
    return snapshot ? [{ payload: { properties: { memory: { pending_assistant_action: snapshot } } } }] : [];
  }
  if (path === "rpc/transition_assistant_pending_action") {
    const args = JSON.parse(options.body);
    if (beforeTransition) { beforeTransition(); beforeTransition = null; }
    const pending = memory.pending_assistant_action;
    const sameId = (pending?.id || null) === args.p_expected_action_id;
    const sameStatus = (pending ? pending.status || "queued" : null) === args.p_expected_status;
    const matches = sameId && sameStatus;
    const status = matches ? "updated" : sameId ? "status_changed" : "superseded";
    if (matches) memory.pending_assistant_action = args.p_action;
    if (args.p_outcome && status !== "status_changed") memory.last_assistant_action_outcome = args.p_outcome;
    operations.push("transition");
    return [{ updated: matches, status }];
  }
  throw new Error(`Unexpected storage request ${path}`);
};
const channel = require("../netlify/functions/_assistant_channel");
channel.getAssistantMemory = async () => structuredClone(memory);
channel.findAssistantConnection = async () => ({ channel: "whatsapp", channelUser: owner.phone_e164 });
channel.sendAssistantMessage = async () => { throw new Error("App receipts must not send WhatsApp messages"); };
identity.identityForAppInstall = async () => owner;
identity.identityForPhone = async () => owner;
push.sendAssistantActionPush = async () => { pushes += 1; return { sent: true }; };
const { handler } = require("../netlify/functions/assistant-channel");
const { queueOnboardingPicker } = require("../netlify/functions/bm-onboarding");
const action = (id = actionId, status = "queued") => ({ id, status, type: "delete_schedule", window_id: "window-1", expires_at: new Date(Date.now() + 60_000).toISOString() });
const request = (fields) => handler({ httpMethod: "POST", body: JSON.stringify({
  connect_code: owner.assistant_connect_code, app_install_id: owner.app_install_id, channel: "whatsapp", ...fields,
}) });
function reset(pending) { memory = { pending_assistant_action: pending, semantic_store_version: 3 }; savedReceipt = null; beforeTransition = null; history.clear(); operations.length = 0; }
const installB = () => { memory.pending_assistant_action = action("wa_B"); };

(async () => {
  reset(action());
  beforeTransition = installB;
  let response = await request({ action: "poll_pending_action" });
  assert.equal(response.statusCode, 200, response.body);
  assert.equal(JSON.parse(response.body).pending_action, null, "stale poll returned executable A");
  assert.equal(memory.pending_assistant_action.id, "wa_B");

  reset(action());
  beforeTransition = () => { memory.pending_assistant_action.status = "confirmed"; };
  response = await request({ action: "poll_pending_action" });
  assert.equal(JSON.parse(response.body).pending_action, null);
  assert.equal(memory.pending_assistant_action.status, "confirmed", "stale poll demoted the same action");

  reset(action(actionId, "execution_started"));
  beforeTransition = installB;
  response = await request({ action: "ack_pending_action", action_id: actionId, status: "verified" });
  assert.equal(JSON.parse(response.body).acknowledged, true, response.body);
  assert.equal(savedReceipt, "verified");
  assert.deepEqual(operations, ["receipt", "transition"]);
  assert.equal(memory.pending_assistant_action.id, "wa_B", "late terminal receipt cleared B");
  assert.equal(memory.last_assistant_action_outcome.id, actionId);

  reset(action("wa_B"));
  history.set(actionId, action(actionId, "execution_started"));
  response = await request({ action: "ack_pending_action", action_id: actionId, status: "verified" });
  assert.equal(JSON.parse(response.body).acknowledged, true, "a late receipt must recover its own scoped historical action");
  assert.equal(savedReceipt, "verified");
  assert.equal(memory.pending_assistant_action.id, "wa_B");

  reset({ ...action(), expires_at: "2020-01-01T00:00:00Z" });
  beforeTransition = installB;
  response = await request({ action: "poll_pending_action" });
  assert.equal(response.statusCode, 200, response.body);
  assert.equal(savedReceipt, "expired");
  assert.equal(memory.pending_assistant_action.id, "wa_B", "stale expiry erased B");

  reset(null);
  beforeTransition = installB;
  const onboarding = await queueOnboardingPicker({ channel: "whatsapp", channelUser: owner.phone_e164, messages: { setup: "Choose distractions" } });
  assert.equal(onboarding.preserved, true);
  assert.equal(onboarding.action, null);
  assert.equal(memory.pending_assistant_action.id, "wa_B");
  assert.equal(pushes, 0);
  await assert.rejects(() => channel.recordAssistantMemory({ channel: "whatsapp", channelUser: owner.phone_e164,
    memory: { pending_assistant_action: null } }), /pending_action_requires_atomic_write/);
  console.log("Pending lifecycle: observed action/status CAS fences poll, ack, expiry and onboarding; late receipts persist without clearing newer actions; direct canonical writes forbidden");
})().catch((error) => { console.error(error); process.exitCode = 1; });
