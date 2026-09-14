const assert = require("assert");
const {
  createRun,
  finishRun,
  planSummary,
  publicMeta,
  recordStage,
} = require("../netlify/functions/bm-harness");

const prompt = "Block Instagram from 22 to 7";
const run = createRun({
  prompt,
  context: {
    channel: "whatsapp",
    language: "en",
    memory: { main_apps: ["Instagram"], weak_hours: [22] },
    recent_messages: [{ role: "user", content: prompt }],
  },
});

assert.match(run.run_id, /^bm_/);
assert.strictEqual(run.harness_version, "bm-harness-v2");
assert.strictEqual(run.schema_version, 2);
assert.strictEqual(run.contract_version, "bm-loop-contract-excellence-v1");
assert.strictEqual(JSON.stringify(run).includes(prompt), false);
recordStage(run, "route_selected", { route: "app" });
run.route = "app";

const plan = {
  intent: "sleep",
  title: "Scheduled Protection",
  response_text: "I would protect Instagram from 10 PM to 7 AM.",
  message_text: "I would protect Instagram from 10 PM to 7 AM.",
  actions: [{ type: "apply_schedule", start_minute: 1320, end_minute: 420 }],
};

assert.deepStrictEqual(planSummary(plan).action_types, ["apply_schedule"]);
finishRun(run, { plan, source: "deterministic_test" });
const meta = publicMeta(run);
assert.strictEqual(meta.status, "completed");
assert.strictEqual(meta.schema_version, 2);
assert.strictEqual(meta.contract_version, "bm-loop-contract-excellence-v1");
assert.strictEqual(meta.route, "app");
assert.deepStrictEqual(meta.action_types, ["apply_schedule"]);
assert.ok(run.stages.some((stage) => stage.stage === "completed"));
assert.ok(run.stages.every((stage, index) => stage.sequence === index + 1));
assert.strictEqual(run.plan_fingerprint, meta.plan_fingerprint);

console.log("bm_harness_test: ok");
