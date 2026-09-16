"use strict";

const assert = require("assert");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { execFileSync, spawnSync } = require("child_process");

const ROOT = path.resolve(__dirname, "..");
const DIR = path.join(ROOT, "tmp", "bm-release", "gate-test");
fs.mkdirSync(DIR, { recursive: true });

function write(name, value) {
  const filePath = path.join(DIR, name);
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
  return path.relative(ROOT, filePath).replace(/\\/g, "/");
}

function writeEvidence(name, content) {
  const filePath = path.join(DIR, name);
  fs.writeFileSync(filePath, content, "utf8");
  return {
    path: path.relative(ROOT, filePath).replace(/\\/g, "/"),
    sha256: crypto.createHash("sha256").update(content).digest("hex"),
  };
}

function run(evidence) {
  return spawnSync(process.execPath, [
    "tools/bm_release_readiness_gate.js",
    "--evidence", evidence,
    "--out", "tmp/bm-release/gate-test/result.json",
    "--head",
  ], { cwd: ROOT, encoding: "utf8", windowsHide: true });
}

const commit = execFileSync("git", ["rev-parse", "HEAD"], { cwd: ROOT, encoding: "utf8", windowsHide: true }).trim();
const integrityPath = write("integrity.json", { revision: commit, passed: true, incidents: 6, mutations_detected: 24, mutations_total: 24 });
const releasePath = write("release.json", { revision: commit, automated_checks_passed: true, active_model_checked: true, independent_quality_judge_checked: true });
const modelPath = write("active-model.json", {
  revision: commit,
  dataset: { id: "fresh-release-holdout", sha256: "d".repeat(64) },
  execution: { model_requested: true, repeats: 1 },
  release_eligible: true,
  summary: { conversations: 200, turns: 400, active_model_turns: 400, passed: 400, failed: 0, unverified: 0 },
});
const qualityPath = write("quality.json", {
  source_report: path.resolve(ROOT, modelPath),
  complete: true,
  summary: { judged: 400, excellent: 388, acceptable: 0, poor: 12, hard_failures: 0, approval_percent: 97, release_eligible: true },
});
const groups = {
  immediate_block: 4,
  schedule: 4,
  daily_limit: 3,
  app_state: 3,
  permissions_selection: 3,
  robustness: 3,
};
const physicalCases = [];
for (const [group, count] of Object.entries(groups)) {
  for (let index = 0; index < count; index += 1) {
    const physicalEvidence = writeEvidence(`${group}-${index + 1}.txt`, `verified ${group} ${index + 1}`);
    physicalCases.push({
      id: `${group}-${index + 1}`,
      group,
      result: "passed",
      candidate_commit: commit,
      backend_deploy_id: "a".repeat(24),
      ios_build: 73,
      trace_id: `trace-${group}-${index + 1}`,
      observed_device_state: "verified expected native state",
      evidence_path: physicalEvidence.path,
      evidence_sha256: physicalEvidence.sha256,
    });
  }
}
const artifact = writeEvidence("Blank-1.9-73.ipa", "signed-ios-artifact-fixture");
const valid = {
  schema_version: 1,
  candidate: {
    commit,
    backend_deploy_id: "a".repeat(24),
    ios_marketing_version: "1.9",
    ios_build: 73,
    ios_build_run_id: "35092552341",
    ios_artifact_path: artifact.path,
    ios_artifact_sha256: artifact.sha256,
  },
  evaluator: { integrity_report: integrityPath, release_report: releasePath, active_model_report: modelPath, quality_report: qualityPath },
  conversation_evidence: {
    dataset_id: "fresh-release-holdout",
    dataset_sha256: "d".repeat(64),
    unique_conversations: 200,
    unique_turns: 400,
    hard_failures: 0,
    unverified: 0,
    independent_quality_pass_rate: 0.97,
  },
  physical_cases: physicalCases,
};

const validPath = write("valid.json", valid);
const success = run(validPath);
assert.strictEqual(success.status, 0, `${success.stdout}\n${success.stderr}`);

const failedPhysical = JSON.parse(JSON.stringify(valid));
failedPhysical.physical_cases[0].result = "failed";
const failedPath = write("failed-physical.json", failedPhysical);
const failure = run(failedPath);
assert.notStrictEqual(failure.status, 0, "a failed physical case must block release");
assert.match(failure.stdout, /physical_case_failed/);

const missingEvidence = run("tmp/bm-release/gate-test/does-not-exist.json");
assert.notStrictEqual(missingEvidence.status, 0, "missing evidence must block release");
assert.match(missingEvidence.stdout, /evidence_missing/);

const inflatedCoverage = JSON.parse(JSON.stringify(valid));
inflatedCoverage.conversation_evidence.unique_conversations = 201;
const inflatedPath = write("inflated-coverage.json", inflatedCoverage);
const inflatedFailure = run(inflatedPath);
assert.notStrictEqual(inflatedFailure.status, 0, "declared conversation coverage must match the measured report");
assert.match(inflatedFailure.stdout, /conversation_count_mismatch/);

console.log("bm_release_readiness_gate_test passed: valid evidence accepted; missing, failed or inflated evidence blocked");
