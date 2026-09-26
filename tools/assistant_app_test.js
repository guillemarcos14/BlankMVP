const assert = require("node:assert/strict");

const membership = require.resolve("../netlify/functions/_membership");
const identity = require.resolve("../netlify/functions/_identity");
const channel = require.resolve("../netlify/functions/_assistant_channel");
const semantic = require.resolve("../netlify/functions/_bm_semantic_store");
const whatsapp = require.resolve("../netlify/functions/whatsapp-agent");
for (const path of [membership, identity, channel, semantic, whatsapp]) require(path);

const rows = new Map();
let plannerCalls = 0;
let semanticCalls = 0;
let queuedPrefix = "";
let memory = {};
const userId = "11111111-1111-4111-8111-111111111111";
const turnId = "22222222-2222-4222-8222-222222222222";
const identityRecord = { app_install_id: "verified-install", assistant_connect_code: "ABCDEFGHIJ", phone_e164: "+34123456789" };

Object.assign(require.cache[membership].exports, {
  getSupabaseUser: async (event) => event.headers?.authorization === "Bearer valid" ? { id: userId } : null,
  json: (statusCode, body) => ({ statusCode, body: JSON.stringify(body) }),
  parseJsonBody: (event) => JSON.parse(event.body || "{}"),
  requireMethod: (event, method) => event.httpMethod === method ? null : { statusCode: 405 },
  supabaseFetch: async (path, options = {}) => {
    if (options.method === "POST") {
      const row = { ...JSON.parse(options.body), created_at: new Date().toISOString() };
      rows.set(row.id, row);
      return [];
    }
    if (options.method === "PATCH") {
      const id = new URLSearchParams(path.split("?")[1]).get("id").slice(3);
      const row = { ...rows.get(id), ...JSON.parse(options.body) };
      rows.set(id, row);
      return options.headers.prefer === "return=representation" ? [row] : [];
    }
    if (/[?&]id=eq\./.test(path)) {
      const id = new URLSearchParams(path.split("?")[1]).get("id").slice(3);
      return rows.has(id) ? [rows.get(id)] : [];
    }
    return [...rows.values()];
  },
});
Object.assign(require.cache[identity].exports, { identityForAuthUser: async () => identityRecord });
Object.assign(require.cache[channel].exports, {
  getAssistantMemory: async () => memory,
  recordAssistantConversationTurn: async () => { semanticCalls += 1; },
  recordAssistantMemory: async () => null,
});
Object.assign(require.cache[semantic].exports, { semanticPersistenceRequired: () => true });
Object.assign(require.cache[whatsapp].exports, {
  callBlankedAgent: async () => {
    plannerCalls += 1;
    return { plan: {
      message_text: "Vamos a proteger tus distracciones.",
      response_language: "es",
      blocking_user_request: true,
      blocking_ready: true,
      semantic_state: { status: "ready" },
    }, context: { language: "es", memory: { semantic_store_version: 1 } } };
  },
  queuePendingAssistantAction: async (_, __, ___, prefix) => {
    queuedPrefix = prefix;
    memory = { pending_assistant_action: { id: "app_action", status: "queued" } };
    return { action: { id: "app_action", type: "start_protection", minutes: 45, app_names: [] } };
  },
});

const { handler } = require("../netlify/functions/assistant-app");
const event = (token, body) => ({ httpMethod: "POST", headers: { authorization: `Bearer ${token}` }, body: JSON.stringify(body) });

(async () => {
  let response = await handler(event("invalid", { action: "history", app_install_id: "verified-install" }));
  assert.equal(response.statusCode, 401);
  response = await handler(event("valid", { action: "history", app_install_id: "other-install" }));
  assert.equal(response.statusCode, 403);
  response = await handler(event("valid", { action: "send", app_install_id: "verified-install", turn_id: turnId, text: "Bloquea ahora 45 min, una vez" }));
  assert.equal(response.statusCode, 200, response.body);
  assert.equal(JSON.parse(response.body).turn.action_label, "Bloquear 45 min");
  assert.equal(JSON.parse(response.body).turn.action_status, "queued");
  assert.equal(queuedPrefix, "app");
  assert.equal(semanticCalls, 1);
  response = await handler(event("valid", { action: "send", app_install_id: "verified-install", turn_id: turnId, text: "Bloquea ahora 45 min, una vez" }));
  assert.equal(JSON.parse(response.body).idempotent, true);
  assert.equal(plannerCalls, 1);
  memory = { last_assistant_action_outcome: { id: "app_action", status: "verified" } };
  response = await handler(event("valid", { action: "history", app_install_id: "verified-install" }));
  assert.equal(JSON.parse(response.body).turns[0].action_status, "verified");
  console.log("assistant app transport: auth, canonical action, idempotency, verified receipt passed");
})().catch((error) => { console.error(error); process.exitCode = 1; });
