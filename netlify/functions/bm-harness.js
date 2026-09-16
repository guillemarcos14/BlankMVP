const crypto = require("crypto");
const loopContract = require("./bm-loop-contract.json");
const { planFingerprint, validatePlan } = require("./bm-contracts");

const HARNESS_VERSION = "bm-harness-v2";
const HARNESS_SCHEMA_VERSION = 2;
const RUNTIME_CONTRACT_VERSION = loopContract.contract_version;
const STAGES = new Set([
  "received",
  "route_selected",
  "planner_started",
  "planner_completed",
  "planner_fallback",
  "semantic_reduced",
  "action_gate",
  "loop_planned",
  "completed",
  "failed",
]);

function clean(value, maxLength = 120) {
  return String(value || "").trim().replace(/\s+/g, " ").slice(0, maxLength);
}

function safeDetail(value, depth = 0) {
  if (depth > 2) return "[truncated]";
  if (typeof value === "string") return clean(value, 180);
  if (typeof value === "number" || typeof value === "boolean" || value === null) return value;
  if (Array.isArray(value)) return value.slice(0, 12).map((item) => safeDetail(item, depth + 1));
  if (value && typeof value === "object") {
    const blocked = /prompt|context|conversation|message|response|token|secret|password|key/i;
    return Object.keys(value).slice(0, 24).reduce((result, key) => {
      if (!blocked.test(key)) result[key] = safeDetail(value[key], depth + 1);
      return result;
    }, {});
  }
  return null;
}

function stableValue(value) {
  if (Array.isArray(value)) return value.map(stableValue);
  if (!value || typeof value !== "object") return value;
  return Object.keys(value).sort().reduce((result, key) => {
    result[key] = stableValue(value[key]);
    return result;
  }, {});
}

function fingerprint(value) {
  return crypto.createHash("sha256").update(JSON.stringify(stableValue(value))).digest("hex").slice(0, 16);
}

function contextShape(context = {}) {
  const memory = context.memory && typeof context.memory === "object" ? context.memory : {};
  return {
    channel: clean(context.channel || context.assistant_channel, 30).toLowerCase(),
    assistant_channel: clean(context.assistant_channel, 30).toLowerCase(),
    language: clean(context.language || context.locale, 12).toLowerCase(),
    trigger: clean(context.trigger || context.mode, 40).toLowerCase(),
    web_preview: context.web_preview === true,
    has_selected_apps: context.has_selected_apps === true,
    screen_time_authorized: context.screen_time_authorized === true,
    app_presence_state: clean(context.app_presence_state, 24) || "never_seen",
    app_presence_recent: context.app_presence_recent === true,
    app_ready: context.app_ready === true,
    is_blank_active: context.is_blank_active === true,
    recent_messages_count: Array.isArray(context.recent_messages)
      ? context.recent_messages.length
      : Array.isArray(context.conversation)
        ? context.conversation.length
        : 0,
    memory_keys: Object.keys(memory).sort().slice(0, 30),
  };
}

function createRun({ prompt, context = {} } = {}) {
  const now = new Date().toISOString();
  const runId = `bm_${Date.now()}_${crypto.randomUUID().slice(0, 8)}`;
  const shape = contextShape(context);
  return {
    harness_version: HARNESS_VERSION,
    schema_version: HARNESS_SCHEMA_VERSION,
    contract_version: RUNTIME_CONTRACT_VERSION,
    run_id: runId,
    trace_id: runId,
    started_at: now,
    started_ms: Date.now(),
    status: "running",
    route: null,
    source: null,
    prompt_hash: fingerprint(clean(prompt, 600)),
    prompt_length: clean(prompt, 600).length,
    context_fingerprint: fingerprint(shape),
    context_shape: shape,
    plan_fingerprint: null,
    stage_count: 0,
    failure_class: null,
    stages: [],
  };
}

function recordStage(run, stage, details = {}) {
  if (!run) return;
  const normalizedStage = clean(stage, 60);
  if (!STAGES.has(normalizedStage)) throw new Error(`unsupported_harness_stage:${normalizedStage}`);
  const event = {
    sequence: run.stages.length + 1,
    stage: normalizedStage,
    at: new Date().toISOString(),
    ...safeDetail(details),
  };
  run.stages.push(event);
  run.stage_count = run.stages.length;
  console.info("bm_harness", JSON.stringify({
    harness_version: run.harness_version,
    run_id: run.run_id,
    ...event,
  }));
}

function planSummary(plan) {
  const source = plan && typeof plan === "object" ? plan : {};
  const actions = Array.isArray(source.actions) ? source.actions : [];
  const actionTypes = actions.map((item) => clean(item && item.type, 60)).filter(Boolean);
  const warnings = [];
  if (!clean(source.message_text || source.response_text, 600)) warnings.push("missing_message");
  const validation = validatePlan(source);
  warnings.push(...validation.warnings.filter((warning) => !warnings.includes(warning)));
  return {
    intent: clean(source.intent, 40) || null,
    title: clean(source.title, 80) || null,
    action_types: actionTypes.slice(0, 8),
    action_count: actionTypes.length,
    message_length: clean(source.message_text || source.response_text, 600).length,
    warnings,
    plan_fingerprint: planFingerprint(source),
    contract_valid: validation.valid,
  };
}

function finishRun(run, { plan, source, error = null } = {}) {
  if (!run) return null;
  const summary = planSummary(plan);
  run.status = error ? "failed" : "completed";
  run.source = clean(source, 120) || null;
  run.finished_at = new Date().toISOString();
  run.duration_ms = Math.max(0, Date.now() - run.started_ms);
  run.output = summary;
  run.plan_fingerprint = summary.plan_fingerprint;
  run.failure_class = error ? (clean(error.code || error.name, 80) || "runtime_error") : null;
  recordStage(run, error ? "failed" : "completed", {
    source: run.source,
    duration_ms: run.duration_ms,
    action_types: summary.action_types,
    warnings: summary.warnings,
    error_code: error ? clean(error.code || error.name, 80) : null,
  });
  return run;
}

function publicMeta(run) {
  if (!run) return null;
  return {
    harness_version: run.harness_version,
    schema_version: run.schema_version,
    contract_version: run.contract_version,
    run_id: run.run_id,
    trace_id: run.trace_id,
    route: run.route,
    status: run.status,
    source: run.source,
    duration_ms: run.duration_ms,
    action_types: run.output ? run.output.action_types : [],
    warnings: run.output ? run.output.warnings : [],
    plan_fingerprint: run.plan_fingerprint,
    failure_class: run.failure_class,
    stage_count: run.stage_count,
  };
}

module.exports = {
  HARNESS_VERSION,
  createRun,
  recordStage,
  finishRun,
  publicMeta,
  planSummary,
  safeDetail,
};
