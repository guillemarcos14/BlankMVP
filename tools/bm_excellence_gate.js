"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const { createLoop, advanceLoop, publicLoop } = require("../netlify/functions/bm-loop");
const { buildAgentContext } = require("../netlify/functions/bm-context");
const { policyForPlan } = require("../netlify/functions/bm-policy");
const { normalizeOutcome, learningSignal } = require("../netlify/functions/bm-learning");

const ROOT = path.join(__dirname, "..");
const report = { gate: "bm-excellence", started_at: new Date().toISOString(), checks: [] };

function check(name, fn) {
  const started = Date.now();
  try {
    fn();
    report.checks.push({ name, status: "passed", duration_ms: Date.now() - started });
  } catch (error) {
    report.checks.push({ name, status: "failed", duration_ms: Date.now() - started, error: String(error.message || error) });
  }
}

function file(relative) { return fs.readFileSync(path.join(ROOT, relative), "utf8"); }

function runNode(name, relative, args = []) {
  check(name, () => {
    const result = spawnSync(process.execPath, [relative, ...args], { cwd: ROOT, encoding: "utf8", maxBuffer: 4 * 1024 * 1024 });
    assert.strictEqual(result.status, 0, `${relative}\n${String(result.stdout || "")}${String(result.stderr || "")}`);
  });
}

check("contract_invariants", () => {
  const contract = JSON.parse(file("netlify/functions/bm-loop-contract.json"));
  assert.strictEqual(contract.architecture, "loop-engineering-excellence");
  assert.ok(contract.required_fields.includes("verification"));
  assert.ok(contract.required_fields.includes("behavioral_outcome"));
  assert.ok(contract.invariants.some((item) => /never completes without verification/i.test(item)));
  for (const state of contract.states) assert.ok(Array.isArray(contract.transition_policy[state]), state);
});

check("context_budget_and_privacy", () => {
  const context = buildAgentContext({
    channel: "app",
    memory: { main_apps: ["Instagram"], last_prompt: "PRIVATE RAW PROMPT", weak_hours: [22] },
    recent_messages: [{ role: "user", content: "I need help" }],
    metrics: { pickup_pressure: 64 },
  });
  assert.deepStrictEqual(context.memory.main_apps, ["Instagram"]);
  assert.strictEqual(Object.prototype.hasOwnProperty.call(context.memory, "last_prompt"), false);
  assert.ok(context.context_fingerprint);
});

check("policy_fail_closed_and_autonomy_grant", () => {
  const plan = { actions: [{ type: "apply_schedule" }] };
  assert.strictEqual(policyForPlan(plan, {}).decision, "confirmation_required");
  assert.strictEqual(policyForPlan(plan, { autonomy_consent: true, authorized_action_types: ["apply_schedule"], device_execution_ready: true }).decision, "autonomous_execution");
  assert.strictEqual(policyForPlan({ actions: [{ type: "unknown_action" }] }, {}).blocked, true);
});

check("loop_replay_verification_and_conflict", () => {
  const prompt = "PRIVATE RAW PROMPT MUST NOT LEAK";
  const plan = { intent: "sleep", title: "Protection", response_text: "I would protect the window.", actions: [{ type: "apply_schedule" }] };
  let loop = createLoop({ prompt, runId: "gate_run", context: { has_selected_apps: true, screen_time_authorized: true }, plan });
  assert.strictEqual(loop.status, "awaiting_confirmation");
  assert.strictEqual(advanceLoop(loop, { type: "executed", event_id: "too_early", success: true }).accepted, false);
  loop = advanceLoop(loop, { type: "confirm", event_id: "confirm" }).loop;
  loop = advanceLoop(loop, { type: "execution_started", event_id: "start" }).loop;
  loop = advanceLoop(loop, { type: "executed", event_id: "executed", success: true }).loop;
  loop = advanceLoop(loop, { type: "verified", event_id: "verified", success: true, verification: "passed" }).loop;
  assert.strictEqual(loop.status, "completed");
  assert.strictEqual(loop.stop_reason, "verification_passed");
  assert.ok(!JSON.stringify(publicLoop(loop)).includes(prompt));
  const replay = advanceLoop(loop, { type: "verified", event_id: "verified", success: true, verification: "passed" });
  assert.strictEqual(replay.transition, "ignored_duplicate");
  assert.strictEqual(replay.duplicate, true);
  const conflict = advanceLoop(loop, { type: "verified", event_id: "verified", success: false, verification: "failed" });
  assert.strictEqual(conflict.transition, "rejected_event_conflict");
  assert.strictEqual(conflict.accepted, false);

  const learned = advanceLoop(loop, { type: "outcome_recorded", event_id: "outcome_held", outcome: "held", outcome_score: 24 });
  assert.strictEqual(learned.accepted, true);
  const duplicateOutcome = advanceLoop(learned.loop, { type: "outcome_recorded", event_id: "outcome_again", outcome: "broke", outcome_score: -24 });
  assert.strictEqual(duplicateOutcome.transition, "ignored_duplicate");
  assert.strictEqual(duplicateOutcome.duplicate, true);

  const legacy = createLoop({ prompt, runId: "legacy_consent_run", context: { has_selected_apps: true, screen_time_authorized: true }, plan });
  delete legacy.consent;
  const hydratedLegacy = advanceLoop(legacy, { type: "confirm", event_id: "legacy_confirm" });
  assert.strictEqual(hydratedLegacy.accepted, true);
  assert.strictEqual(hydratedLegacy.loop.consent.status, "confirmed");
});

check("learning_contract", () => {
  assert.strictEqual(normalizeOutcome({ outcome: "broke", outcome_score: -30, source: "ios" }).status, "broke");
  const signal = learningSignal({ goal: "focus", action_types: ["apply_schedule"] }, { outcome: "broke", outcome_score: -30 });
  assert.strictEqual(signal.adjustment, "adapt_timing_or_intensity");
  assert.ok(signal.signal_key.startsWith("bm:"));
});

check("native_platform_parity", () => {
  const ios = `${file("ios/Blank/Blank/ContentView.swift")}\n${file("ios/Blank/Blank/BlankDomainModels.swift")}`;
  const android = file("app/src/main/java/com/blanknfc/app/data/DigitalWellnessRemoteStore.kt");
  for (const event of ["execution_started", "executed", "verified"]) {
    assert.ok(ios.includes(`"${event}"`), `iOS missing ${event}`);
    assert.ok(android.includes(`"${event}"`), `Android missing ${event}`);
  }
  assert.ok(ios.includes("bai-outcome") && android.includes("bai-outcome"));
  assert.ok(ios.includes("bm-loop") && android.includes("bm-loop"));
});

check("durable_store_security", () => {
  const migration = file("supabase/migrations/012_bm_loop_engineering.sql");
  assert.ok(migration.includes("create or replace function bm_append_loop_event"));
  assert.ok(migration.includes("for update"));
  assert.ok(migration.includes("unique (loop_id, event_id)"));
  assert.ok(migration.includes("enable row level security"));
  assert.ok(migration.includes("revoke all on function"));
});

for (const relative of [
  "netlify/functions/bm-contracts.js",
  "netlify/functions/bm-context.js",
  "netlify/functions/bm-policy.js",
  "netlify/functions/bm-verification.js",
  "netlify/functions/bm-learning.js",
  "netlify/functions/bm-harness.js",
  "netlify/functions/bm-loop.js",
]) runNode(`syntax_${path.basename(relative)}`, "-c", [relative]);

runNode("bm_harness_runtime", "tools/bm_harness_test.js");
runNode("bm_loop_runtime", "tools/bm_loop_test.js");
runNode("bm_loop_contract", "tools/bm_loop_contract_test.js");
runNode("bm_regressions", "tools/bm_regression_test.js");
runNode("product_harness_runtime", "tools/product_harness_test.js");
runNode("agent_behavior_smoke", "tools/blanked_agent_smoke_test.js");

report.finished_at = new Date().toISOString();
report.passed = report.checks.every((item) => item.status === "passed");
report.failed = report.checks.filter((item) => item.status === "failed").map((item) => item.name);
const reportPath = path.join(ROOT, "tmp", "reports", "bm_excellence_gate.json");
fs.mkdirSync(path.dirname(reportPath), { recursive: true });
fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, "utf8");
console.log(`bm_excellence_gate ${report.passed ? "passed" : "failed"} ${report.checks.length} checks`);
if (!report.passed) {
  for (const item of report.checks.filter((checkItem) => checkItem.status === "failed")) console.error(`${item.name}: ${item.error}`);
  process.exitCode = 1;
}
