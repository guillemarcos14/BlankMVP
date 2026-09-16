"use strict";

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const { advanceSemanticState } = require("../netlify/functions/bm-semantic-state");
const { normalizeUserContext } = require("../netlify/functions/bm-context");
const { pendingAssistantActionFromPlan } = require("../netlify/functions/sms-agent");
const { normalizePendingAction } = require("../netlify/functions/assistant-channel");

const ROOT = path.resolve(__dirname, "..");
const rawArgs = process.argv.slice(2);

function argValue(name, fallback) {
  const index = rawArgs.indexOf(name);
  return index >= 0 && rawArgs[index + 1] ? rawArgs[index + 1] : fallback;
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function pathParts(value) {
  return String(value || "").split(".").filter(Boolean).map((part) => /^\d+$/.test(part) ? Number(part) : part);
}

function readPath(source, targetPath) {
  let current = source;
  for (const part of pathParts(targetPath)) {
    if (current == null || !Object.prototype.hasOwnProperty.call(Object(current), part)) return { present: false, value: undefined };
    current = current[part];
  }
  return { present: true, value: current };
}

function writePath(source, targetPath, value) {
  const parts = pathParts(targetPath);
  let current = source;
  for (let index = 0; index < parts.length - 1; index += 1) {
    const part = parts[index];
    const next = parts[index + 1];
    if (current[part] == null || typeof current[part] !== "object") current[part] = typeof next === "number" ? [] : {};
    current = current[part];
  }
  current[parts[parts.length - 1]] = value;
}

function equal(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

function evaluateAssertion(trace, assertion) {
  const actual = readPath(trace, assertion.path);
  switch (assertion.op) {
    case "eq": return actual.present && equal(actual.value, assertion.value);
    case "not_eq": return !actual.present || !equal(actual.value, assertion.value);
    case "length": return actual.present && actual.value != null && Number(actual.value.length) === assertion.value;
    case "absent": return !actual.present || actual.value == null;
    case "includes": return actual.present && String(actual.value).includes(String(assertion.value));
    case "excludes": return !actual.present || !String(actual.value).includes(String(assertion.value));
    default: throw new Error(`unsupported_assertion_op:${assertion.op}`);
  }
}

function evaluateTrace(trace, assertions) {
  const failures = assertions.filter((assertion) => !evaluateAssertion(trace, assertion));
  return { passed: failures.length === 0, failures };
}

function mutantValue(value) {
  if (typeof value === "boolean") return !value;
  if (typeof value === "number") return value + 1;
  if (typeof value === "string") return `${value}__mutated`;
  if (Array.isArray(value)) return [...value, "__mutated"];
  if (value == null) return "__mutated";
  return { __mutated: true };
}

function mutateForAssertion(trace, assertion) {
  const mutated = clone(trace);
  if (assertion.op === "not_eq" || assertion.op === "excludes") writePath(mutated, assertion.path, assertion.value);
  else if (assertion.op === "length") writePath(mutated, assertion.path, assertion.value === 0 ? ["__mutated"] : []);
  else if (assertion.op === "absent") writePath(mutated, assertion.path, "__mutated");
  else if (assertion.op === "includes") writePath(mutated, assertion.path, "__mutated_without_required_text");
  else writePath(mutated, assertion.path, mutantValue(assertion.value));
  return mutated;
}

function semanticTrace(incident) {
  const context = normalizeUserContext(incident.context || {});
  let previousState;
  const turns = incident.prompts.map((prompt) => {
    const result = advanceSemanticState({ prompt, previousState, context, language: context.language || "en", now: Date.parse("2026-09-16T12:00:00Z") });
    previousState = result.state;
    return {
      decision: result.decision,
      actions: result.actions,
      state: result.state,
      response_text: result.responseText,
    };
  });
  return { turns };
}

function transportTrace(incident) {
  const pending = pendingAssistantActionFromPlan(incident.plan, incident.app_names || []);
  return { pending, delivered: normalizePendingAction(pending) };
}

function runIncident(incident) {
  if (incident.runner === "semantic") return semanticTrace(incident);
  if (incident.runner === "transport") return transportTrace(incident);
  if (incident.runner === "reply_contract") return { reply: incident.reply };
  throw new Error(`unsupported_runner:${incident.runner}`);
}

const datasetPath = path.resolve(ROOT, argValue("--dataset", "tools/datasets/bm_real_incidents_v1.json"));
const reportPath = path.resolve(ROOT, argValue("--out", "tmp/bm-semantic/evaluator-integrity.json"));
const dataset = readJson(datasetPath);
if (dataset.schema_version !== 1 || !Array.isArray(dataset.incidents) || dataset.incidents.length < 6) {
  throw new Error("invalid_or_insufficient_real_incident_dataset");
}

const ids = new Set();
const results = [];
for (const incident of dataset.incidents) {
  if (!incident.id || ids.has(incident.id)) throw new Error(`duplicate_or_missing_incident_id:${incident.id || "missing"}`);
  ids.add(incident.id);
  if (incident.source !== "physical_whatsapp") throw new Error(`untrusted_incident_source:${incident.id}`);
  if (!Array.isArray(incident.assertions) || incident.assertions.length < 2) throw new Error(`insufficient_assertions:${incident.id}`);
  const trace = runIncident(incident);
  const canonical = evaluateTrace(trace, incident.assertions);
  const mutations = incident.assertions.map((assertion, index) => {
    const mutatedTrace = mutateForAssertion(trace, assertion);
    const verdict = evaluateTrace(mutatedTrace, incident.assertions);
    return {
      id: `${incident.id}:assertion-${index + 1}`,
      assertion,
      detected: !verdict.passed,
    };
  });
  results.push({
    id: incident.id,
    failure_class: incident.failure_class,
    canonical_passed: canonical.passed,
    canonical_failures: canonical.failures,
    mutations_detected: mutations.filter((item) => item.detected).length,
    mutations_total: mutations.length,
    mutations,
  });
}

const totalMutations = results.reduce((sum, item) => sum + item.mutations_total, 0);
const detectedMutations = results.reduce((sum, item) => sum + item.mutations_detected, 0);
const passed = results.every((item) => item.canonical_passed && item.mutations_detected === item.mutations_total);
const report = {
  gate: "bm-evaluator-integrity-v1",
  revision: execFileSync("git", ["rev-parse", "HEAD"], { cwd: ROOT, encoding: "utf8", windowsHide: true }).trim(),
  dataset: path.relative(ROOT, datasetPath).replace(/\\/g, "/"),
  generated_at: new Date().toISOString(),
  incidents: results.length,
  canonical_passed: results.filter((item) => item.canonical_passed).length,
  mutations_detected: detectedMutations,
  mutations_total: totalMutations,
  false_negative_rate: totalMutations ? (totalMutations - detectedMutations) / totalMutations : 1,
  passed,
  results,
  limitations: [
    "Historical incidents are reconstructed from observed failures; they are not fresh physical executions.",
    "Native effects require separately signed physical evidence and cannot be certified by this gate.",
  ],
};
fs.mkdirSync(path.dirname(reportPath), { recursive: true });
fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, "utf8");
console.log(`bm_evaluator_integrity ${passed ? "passed" : "failed"}: ${report.canonical_passed}/${report.incidents} incidents, mutations ${detectedMutations}/${totalMutations}`);
console.log(`report: ${path.relative(ROOT, reportPath)}`);
if (!passed) process.exitCode = 1;

module.exports = { evaluateAssertion, evaluateTrace, readPath, writePath };
