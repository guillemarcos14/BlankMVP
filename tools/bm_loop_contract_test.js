"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const contract = require("../netlify/functions/bm-loop-contract.json");
const {
  advanceLoop,
  createLoop,
  publicLoop,
  handler,
} = require("../netlify/functions/bm-loop");

const migration = fs.readFileSync(
  path.join(__dirname, "..", "supabase", "migrations", "012_bm_loop_engineering.sql"),
  "utf8",
);

assert.strictEqual(contract.contract_version, "bm-loop-contract-excellence-v1");
assert.ok(contract.invariants.length >= 6);
assert.ok(contract.required_fields.includes("event_sequence"));
for (const state of contract.states) assert.ok(contract.transition_policy[state]);
for (const token of ["bm_loop_runs", "bm_loop_events", "bm_append_loop_event", "bm_loop_learning_summary", "row level security"]) {
  assert.ok(migration.toLowerCase().includes(token.toLowerCase()), `migration_missing:${token}`);
}

const plan = {
  intent: "sleep",
  title: "Scheduled Protection",
  response_text: "I would protect the risky window.",
  actions: [{ type: "apply_schedule", start_minute: 1320, end_minute: 420 }],
};

let loop = createLoop({
  prompt: "Block Instagram at night",
  context: { channel: "app", has_selected_apps: true, screen_time_authorized: true },
  plan,
  runId: "contract_test_run",
});
const publicState = publicLoop(loop);
for (const field of contract.required_fields) {
  assert.ok(Object.prototype.hasOwnProperty.call(publicState, field), `public_field_missing:${field}`);
}
assert.strictEqual(Object.prototype.hasOwnProperty.call(publicState, "events"), false);
assert.strictEqual(Object.prototype.hasOwnProperty.call(publicState, "prompt"), false);

for (const [index, event] of [
  { type: "confirm", event_id: "contract_confirm" },
  { type: "execution_started", event_id: "contract_started" },
  { type: "executed", event_id: "contract_executed", success: true },
  { type: "verified", event_id: "contract_verified", success: true, verification: "passed" },
].entries()) {
  const result = advanceLoop(loop, event);
  assert.strictEqual(result.accepted, true, `event_rejected:${index}`);
  loop = result.loop;
}
assert.strictEqual(loop.status, "completed");
const outcome = advanceLoop(loop, {
  type: "outcome_recorded",
  event_id: "contract_outcome",
  outcome: "improved",
  outcome_score: 1,
});
assert.strictEqual(outcome.accepted, true);
assert.strictEqual(outcome.loop.status, "completed");
assert.strictEqual(outcome.loop.behavioral_outcome.status, "improved");

handler({
  httpMethod: "POST",
  body: JSON.stringify({ operation: "start", plan, prompt: "contract handler" }),
}).then((response) => {
  assert.strictEqual(response.statusCode, 200);
  const body = JSON.parse(response.body);
  assert.strictEqual(body.ok, true);
  assert.strictEqual(body.loop.contract_version, contract.contract_version);
  assert.strictEqual(body.persistence.persisted, false);
  console.log("bm_loop_contract_test: ok");
}).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
