const { spawnSync } = require("child_process");
const path = require("path");

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
const save = args.has("--save");
const model = argValue("--model", process.env.OPENAI_MODEL || "gpt-5.6-luna");
const wideCount = argValue("--count", "125");
const seed = argValue("--seed", "20260910");

function run(label, commandArgs, options = {}) {
  console.log(`\n== ${label} ==`);
  const result = spawnSync(process.execPath, commandArgs, {
    cwd: rootDir,
    env: {
      ...process.env,
      ...(options.env || {}),
    },
    stdio: "inherit",
  });
  if (result.status !== 0) {
    console.error(`\n${label} failed with exit code ${result.status}`);
    process.exit(result.status || 1);
  }
}

function syntheticArgs(extraArgs = []) {
  const usingModel = hasApiKey && !quick;
  return [
    "tools/bai_synthetic_conversation_suite.js",
    "--seed", seed,
    ...(usingModel || forceModel ? ["--model", model] : ["--dry-run"]),
    ...(save ? ["--save"] : []),
    ...extraArgs,
  ];
}

if (!hasApiKey && !quick && !forceModel) {
  console.log("OPENAI_API_KEY is not set. Synthetic gates will run in --dry-run mode to avoid accidental spend.");
  console.log("Set OPENAI_API_KEY or pass --model to measure model quality before a real release.");
}

run("Legacy compatibility contract eval", [
  "tools/blanked_agent_eval.js",
  ...(forceModel ? ["--model"] : []),
  ...(save ? ["--save"] : []),
]);

run("BM golden set", syntheticArgs([
  "--golden",
  "--count", "25",
  "--min-pass-rate", "0.99",
  "--max-real-failures", "0",
  "--allow-rubric-failures",
]));

run("BM wide synthetic suite", syntheticArgs([
  "--count", wideCount,
  "--min-pass-rate", "0.99",
  "--max-real-failures", "0",
  "--allow-rubric-failures",
]));

run("BM web/app smoke", ["tools/blanked_agent_smoke_test.js"]);
run("BM harness runtime", ["tools/bm_harness_test.js"]);
run("BM loop runtime", ["tools/bm_loop_test.js"]);
run("BM loop contract", ["tools/bm_loop_contract_test.js"]);
run("BM excellence architecture gate", ["tools/bm_excellence_gate.js"]);
run("BM product harness", ["tools/product_harness_test.js"]);
run("Messaging compatibility smoke", ["tools/whatsapp_agent_smoke_test.js"]);
run("SMS/voice compatibility smoke", ["tools/sms_agent_voice_smoke_test.js"]);

console.log("\nBM release gate passed.");
