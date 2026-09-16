"use strict";

const fs = require("fs");
const path = require("path");
const assert = require("assert");
const { normalizeAction } = require("../netlify/functions/bm-contracts");
const { pendingAssistantActionFromPlan } = require("../netlify/functions/sms-agent");
const { normalizePendingAction } = require("../netlify/functions/assistant-channel");

const ROOT = path.resolve(__dirname, "..");
const contract = JSON.parse(fs.readFileSync(path.join(__dirname, "bm_action_envelope_contract.json"), "utf8"));
assert.strictEqual(contract.schema_version, 1, "unsupported action-envelope contract");

const canonical = normalizeAction(contract.critical_fields);
assert(canonical, "canonical action was rejected");
for (const [field, expected] of Object.entries(contract.critical_fields)) {
  assert.deepStrictEqual(canonical[field], expected, `canonical layer stripped or changed ${field}`);
}

const queued = pendingAssistantActionFromPlan({
  actions: [canonical],
  message_text: "Contract probe",
}, contract.app_names);
assert(queued, "SMS layer did not create a pending action");
const delivered = normalizePendingAction(queued);
assert(delivered, "assistant channel rejected the pending action");
for (const [field, expected] of Object.entries(contract.critical_fields)) {
  assert.deepStrictEqual(queued[field], expected, `SMS layer stripped or changed ${field}`);
  assert.deepStrictEqual(delivered[field], expected, `channel layer stripped or changed ${field}`);
}
assert.deepStrictEqual(queued.app_names, contract.app_names, "SMS layer changed app_names");
assert.deepStrictEqual(delivered.app_names, contract.app_names, "channel layer changed app_names");

const swiftPath = path.join(ROOT, "ios", "Blank", "Blank", "HomeView.swift");
const swift = fs.readFileSync(swiftPath, "utf8");
for (const [wireKey, property] of Object.entries(contract.native_coding_keys)) {
  assert(
    swift.includes(`case ${property} = "${wireKey}"`),
    `native decoder is missing ${wireKey}`,
  );
}
for (const route of contract.native_copy_routes) {
  assert(swift.includes(`.${route}(`), `native copy route is missing ${route}`);
}

console.log(`bm_action_envelope_contract passed: ${Object.keys(contract.critical_fields).length} critical fields across canonical, SMS, channel and native decoder`);
