const { spawnSync } = require("child_process");
const path = require("path");
const fs = require("fs");
const report = { version: 2, started_at: new Date().toISOString(), checks: [], legacy_diagnostics: [], production_release_verified: false };

const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);

function argValue(name, fallback = null) {
  const index = rawArgs.indexOf(name);
  return index >= 0 ? rawArgs[index + 1] : fallback;
}

const rootDir = path.join(__dirname, "..");
const hasApiKey = Boolean(process.env.OPENAI_API_KEY);
const forceModel = args.has("--model");
const quick = args.has("--quick");
const production = args.has("--production");
const qualityJudge = args.has("--quality-judge");
const save = args.has("--save");
const wideCount = argValue("--count", "125");
const seed = argValue("--seed", "20260910");

if (qualityJudge && !hasApiKey) {
  throw new Error("OPENAI_API_KEY_required_for_quality_judge");
}

function run(label, commandArgs, options = {}) {
  console.log(`\n== ${label} ==`);
  const result = spawnSync(process.execPath, commandArgs, {
    cwd: rootDir,
    env: {
      ...process.env,
      ...(options.env || {}),
      ...(options.diagnostic ? { OPENAI_API_KEY: "" } : {}),
    },
    encoding: "utf8", maxBuffer: 16 * 1024 * 1024, timeout: options.timeoutMs || 180000, windowsHide: true,
  });
  const output = `${result.stdout || ""}${result.stderr || ""}`;
  const item = { name: label, args: commandArgs, passed: result.status === 0 && !result.error, exit_code: result.status, output, error: result.error?.message || null };
  (options.diagnostic ? report.legacy_diagnostics : report.checks).push(item);
  console.log(`${options.diagnostic ? "DIAGNOSTIC" : item.passed ? "PASS" : "FAIL"} ${label} (exit ${result.status})`);
  if (!item.passed && !options.diagnostic) console.error(output.slice(-2000));
}

function syntheticArgs(extraArgs = []) {
  return [
    "tools/bai_synthetic_conversation_suite.js",
    "--seed", seed,
    "--dry-run",
    ...(save ? ["--save"] : []),
    ...extraArgs,
  ];
}

if (!hasApiKey && !quick && !forceModel) {
  console.log("OPENAI_API_KEY is not set. Active-model semantic replay is not measured.");
  console.log("Legacy synthetic diagnostics only generate scenarios; their scores never authorize release.");
}

// Original lexical evaluators remain reproducible diagnostics. Mutation tests
// prove that their scores cannot authorize release; semantic checks replace them.
run("Legacy compatibility contract eval", [
  "tools/blanked_agent_eval.js",
  ...(save ? ["--save"] : []),
], { diagnostic: true });

run("BM golden set", syntheticArgs([
  "--golden",
  "--count", "25",
  "--min-pass-rate", "0.99",
  "--max-real-failures", "0",
  "--allow-rubric-failures",
]), { diagnostic: true });

run("BM wide synthetic suite", syntheticArgs([
  "--count", wideCount,
  "--min-pass-rate", "0.99",
  "--max-real-failures", "0",
  "--allow-rubric-failures",
]), { diagnostic: true });

for (const [label, file] of [
  ["Canonical state invariants", "bm_semantic_state_test.js"],
  ["Model extraction evidence and hostile output", "bm_semantic_extraction_test.js"],
  ["Independent oracle mutation checks", "bm_semantic_oracle_test.js"],
  ["Durable conversation state and version conflicts", "bm_semantic_store_test.js"],
  ["Channel review action contracts", "bm_channel_contract_test.js"],
  ["SMS stale proposal protection", "bm_sms_pending_action_test.js"],
]) run(label, ["tools/" + file]);

const replayArgs = ["tools/bm_semantic_replay.js", "--dataset", "tools/datasets/bm_semantic_development_v2.json", "--reviews", "tools/datasets/bm_semantic_development_reviews.json", "--repeats", "2", "--concurrency", "4"];
run("Reviewed multi-turn semantic replay", [...replayArgs, "--out", "tmp/bm-semantic/development-gate.json"]);
if (forceModel || qualityJudge || (hasApiKey && !quick)) run("Active model repeated semantic replay", [...replayArgs, "--model", "--out", "tmp/bm-semantic/active-model-gate.json"]);
if (qualityJudge) {
  run("Independent GPT-5.6 Sol Low quality review", [
    "tools/bm_sol_quality_judge.js",
    "--input", "tmp/bm-semantic/active-model-gate.json",
    "--limit", argValue("--quality-limit", "48"),
    "--out", "tmp/bm-semantic/sol-quality-release-gate.json",
  ], { timeoutMs: 600000 });
}

run("BM web/app smoke", ["tools/blanked_agent_smoke_test.js"]);
run("BM harness runtime", ["tools/bm_harness_test.js"]);
run("BM loop runtime", ["tools/bm_loop_test.js"]);
run("BM loop contract", ["tools/bm_loop_contract_test.js"]);
run("BM excellence architecture gate", ["tools/bm_excellence_gate.js"]);
run("BM product harness", ["tools/product_harness_test.js"]);
run("Messaging compatibility smoke", ["tools/whatsapp_agent_smoke_test.js"]);
run("SMS/audio-input compatibility smoke", ["tools/sms_agent_voice_smoke_test.js"]);
run("Assistant conversation memory", ["tools/assistant_conversation_memory_test.js"]);
if (production) run("Deployed planner semantic replay", [...replayArgs, "--url", argValue("--url", "https://getblank.netlify.app/.netlify/functions/blanked-agent"), "--out", "tmp/bm-semantic/deployed-gate.json"]);

report.finished_at = new Date().toISOString();
report.automated_checks_passed = report.checks.length > 0 && report.checks.every(check => check.passed);
report.active_model_checked = forceModel || qualityJudge || (hasApiKey && !quick);
report.independent_quality_judge_checked = qualityJudge;
report.limitations = ["Original evaluator scores are diagnostic, never averaged with semantic checks.", "Automated checks do not verify an unseen holdout, real Postgres concurrency, native compilation or physical execution. Those release requirements remain mandatory."];
const out = path.resolve(rootDir, argValue("--report", "tmp/bm-semantic/release-gate.json"));
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, JSON.stringify(report, null, 2) + "\n");
console.log(`BM automated checks: ${report.checks.filter(check => check.passed).length}/${report.checks.length}. Production release verification: pending. Report: ${out}`);
process.exitCode = report.automated_checks_passed ? 0 : 1;
