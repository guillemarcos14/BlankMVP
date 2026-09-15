"use strict";
const assert = require("node:assert/strict");
process.env.BM_SEMANTIC_PERSISTENCE = "required";
process.env.OPENAI_API_KEY = "";
const membership = require("../netlify/functions/_membership");
const records = new Map();
let forceFailure = false;
let forceCommitFailure = false;
let auditFailure = false;
const released = [];
membership.supabaseFetch = async (path, options = {}) => {
  if (path.startsWith("assistant_semantic_conversations?")) {
    if (forceFailure) throw new Error("semantic_store_unavailable");
    const key = decodeURIComponent(path.match(/anonymous_user_id=eq\.([^&]+)/)[1]);
    return records.has(key) ? [structuredClone(records.get(key))] : [];
  }
  if (path === "rpc/commit_assistant_semantic_conversation") {
    if (forceFailure || forceCommitFailure) throw new Error("semantic_store_unavailable");
    const input = JSON.parse(options.body);
    const row = records.get(input.p_anonymous_user_id);
    const version = row?.storage_version || 0;
    if (version !== input.p_expected_version) return [{ committed: false, storage_version: version, status: "conflict" }];
    records.set(input.p_anonymous_user_id, {
      state: input.p_state, storage_version: version + 1, expires_at: new Date(Date.now() + 7200000).toISOString(),
    });
    return [{ committed: true, storage_version: version + 1, status: "committed" }];
  }
  if (path === "rpc/claim_assistant_inbound_message") return [{ claimed: true, status: "claimed" }];
  if (path === "rpc/release_assistant_inbound_message") { released.push(JSON.parse(options.body).p_message_id); return true; }
  if (path.startsWith("digital_wellness_feature_payloads")) {
    if (options.method === "POST") {
      if (auditFailure) throw new Error("audit_unavailable");
      return {};
    }
    return [{ payload: { properties: { memory: { pending_blocking: { apps: ["old"] }, conversation_state: { updated_at: new Date().toISOString(), recent_messages: [{ role: "user", content: "old plan" }] } } } } }];
  }
  if (path.startsWith("blank_")) return [];
  throw new Error(`Unexpected mock request ${path}`);
};
const { semanticPersistenceRequired, readSemanticConversation, commitSemanticConversation } = require("../netlify/functions/_bm_semantic_store");
const { getAssistantMemory, recordAssistantConversationTurn } = require("../netlify/functions/_assistant_channel");
const { handler: smsHandler } = require("../netlify/functions/sms-agent");
const { handler: whatsappHandler } = require("../netlify/functions/whatsapp-agent");
const key = `assistant:${"a".repeat(32)}`;
const state = { semantic_state: { ...require("../netlify/functions/bm-semantic-state").emptyState(), intent: "block" }, updated_at: new Date().toISOString() };

async function run() {
  const previousNodeEnv = process.env.NODE_ENV;
  delete process.env.BM_SEMANTIC_PERSISTENCE;
  process.env.NODE_ENV = "production";
  assert.equal(semanticPersistenceRequired(), true, "Production cannot silently opt out of CAS");
  process.env.BM_SEMANTIC_PERSISTENCE = "legacy";
  assert.equal(semanticPersistenceRequired(), false);
  process.env.BM_SEMANTIC_PERSISTENCE = "required";
  if (previousNodeEnv === undefined) delete process.env.NODE_ENV; else process.env.NODE_ENV = previousNodeEnv;
  assert.deepEqual(await readSemanticConversation(key), { state: null, storageVersion: 0 });
  const args = { anonymousUserId: key, channel: "sms", expectedVersion: 0, state };
  const race = await Promise.allSettled([commitSemanticConversation(args), commitSemanticConversation(args)]);
  assert.equal(race.filter((item) => item.status === "fulfilled").length, 1);
  assert.match(race.find((item) => item.status === "rejected").reason.message, /semantic_store_conflict/);
  assert.equal((await readSemanticConversation(key)).storageVersion, 1);
  const expired = await readSemanticConversation(key, Date.now() + 3 * 3600000);
  assert.equal(expired.state, null);
  assert.equal(expired.storageVersion, 1, "Expiry cannot reset the CAS version");
  await assert.rejects(commitSemanticConversation({ ...args, expectedVersion: undefined }), /missing_version/);
  await assert.rejects(readSemanticConversation("+34999999999"), /invalid_identity/);

  const emptyMemory = await getAssistantMemory("sms", "+34000000000");
  assert.equal(emptyMemory.semantic_store_version, 0);
  assert.equal(emptyMemory.conversation_state, undefined, "Old event log must not resurrect a missing dedicated session");
  assert.equal(emptyMemory.pending_blocking, undefined);

  // An audit-log failure after CAS must not turn a durable success into an unsafe retry.
  auditFailure = true;
  await recordAssistantConversationTurn({ channel: "sms", channelUser: "+34000000000", expectedVersion: 0, semanticState: state.semantic_state, userMessage: "Block Instagram", assistantMessage: "When should it start?" });
  auditFailure = false;
  const stored = await getAssistantMemory("sms", "+34000000000");
  assert.equal(stored.semantic_store_version, 1);
  assert.equal(stored.conversation_state.semantic_state.intent, "block");

  forceFailure = true;
  await assert.rejects(getAssistantMemory("sms", "+34000000000"), /semantic_store_unavailable/);
  await assert.rejects(smsHandler({ httpMethod: "POST", body: new URLSearchParams({ From: "+34000000000", Body: "Block Instagram now for 15 minutes once" }).toString() }), /semantic_store_unavailable/);
  await assert.rejects(smsHandler({ httpMethod: "POST", body: new URLSearchParams({ From: "+34000000000", Body: "OPEN" }).toString() }), /semantic_store_unavailable/);
  const failedMeta = await whatsappHandler({ httpMethod: "POST", body: JSON.stringify({ entry: [{ changes: [{ value: { messages: [{ from: "34000000000", text: { body: "Block Instagram now for 15 minutes once" } }] } }] }] }) });
  assert.equal(failedMeta.statusCode, 500);
  assert.doesNotMatch(failedMeta.body, /review-action/);
  forceFailure = false;
  forceCommitFailure = true;
  await assert.rejects(smsHandler({ httpMethod: "POST", body: new URLSearchParams({ From: "+34000000000", Body: "Block Instagram", MessageSid: "SMcas" }).toString() }), /semantic_store_unavailable/);
  assert.ok(released.includes("SMcas"), "A CAS failure must release the inbound lease for provider retry");
  const failedMetaCommit = await whatsappHandler({ httpMethod: "POST", body: JSON.stringify({ entry: [{ changes: [{ value: { messages: [{ id: "wamid.cas", from: "34000000000", text: { body: "Block Instagram" } }] } }] }] }) });
  assert.equal(failedMetaCommit.statusCode, 500);
  assert.doesNotMatch(failedMetaCommit.body, /review-action/);
  assert.ok(released.includes("wamid.cas"));
  console.log("BM semantic store tests passed: CAS race, expiry, version fencing, event-log isolation, durable audit failure and channel fail-closed reads");
}
run().catch((error) => { console.error(error); process.exitCode = 1; });
