"use strict";

const crypto = require("crypto");
const contract = require("./bm-loop-contract.json");
const { json, parseJsonBody, requireMethod, supabaseFetch } = require("./_membership");
const {
  actionNeedsSetup,
  clean,
  fingerprint,
  normalizePlan,
  planFingerprint,
  validatePlan,
} = require("./bm-contracts");
const { policyForPlan } = require("./bm-policy");
const { isPositiveVerification, publicVerification, verificationFromEvent } = require("./bm-verification");
const { learningSignal, normalizeOutcome, publicOutcome } = require("./bm-learning");

const LOOP_VERSION = contract.loop_version;
const LOOP_SCHEMA_VERSION = 1;
const LOOP_CONTRACT_VERSION = contract.contract_version;
const TERMINAL = new Set(contract.terminal_states || ["completed", "stopped", "failed"]);
const MAX_EVENT_ID_LENGTH = 160;

function now() { return new Date(); }
function iso(date) { return date.toISOString(); }
function clone(value) { return JSON.parse(JSON.stringify(value)); }
function eventId(value) { return clean(value, MAX_EVENT_ID_LENGTH); }
function eventType(value) { return clean(value, 48).toLowerCase(); }
function actionTypes(plan) { return (plan.actions || []).map((action) => action.type).filter(Boolean); }
function anonymousUserId(value) {
  const normalized = clean(value, 160);
  return normalized
    ? `anon_${crypto.createHash("sha256").update(normalized).digest("hex")}`
    : "";
}

function deriveGoal(plan, prompt) {
  return clean(plan.intent && plan.intent !== "general" ? plan.intent : plan.title || prompt, 96) || "digital_wellness_support";
}

function deriveHypothesis(plan, context) {
  const action = plan.actions?.[0]?.type || "conversation";
  const trigger = clean(context.trigger || context.mode, 64) || "user_request";
  return clean(`A bounded ${action} intervention during ${trigger} will improve digital control.`, 220);
}

function nextStep(loop) {
  if (!loop) return "none";
  if (loop.status === "awaiting_input") return "answer_one_question";
  if (loop.status === "awaiting_setup") return "complete_app_setup";
  if (loop.status === "awaiting_confirmation") return "confirm_in_app";
  if (loop.status === "awaiting_execution") return loop.phase === "verify" ? "report_app_verification" : "execute_in_app";
  if (loop.status === "retryable") return "adapt_and_confirm";
  if (loop.status === "failed") return "inspect_failure";
  if (loop.status === "completed" || loop.status === "stopped") return "record_outcome_or_stop";
  return "none";
}

function initialStatus(plan, context, policy, validation) {
  if (!validation.valid || policy.blocked) return { status: "failed", phase: "stop" };
  if (!plan.actions.length || plan.actions.every((action) => action.type === "none")) return { status: "awaiting_input", phase: "understand" };
  if (plan.actions.some((action) => actionNeedsSetup(action, context))) return { status: "awaiting_setup", phase: "setup" };
  if (policy.autonomous_allowed) return { status: "awaiting_execution", phase: "execute" };
  return { status: "awaiting_confirmation", phase: "propose" };
}

function createLoop({ prompt, context = {}, plan, runId, promptHash, contextFingerprint } = {}) {
  const validation = validatePlan(plan);
  const normalizedPlan = validation.plan || normalizePlan(plan);
  const policy = policyForPlan(normalizedPlan, context);
  const initial = initialStatus(normalizedPlan, context, policy, validation);
  const created = now();
  const maxDurationHours = Number(contract.limits?.max_duration_hours || 168);
  const expires = new Date(created.getTime() + maxDurationHours * 60 * 60 * 1000);
  const actionList = actionTypes(normalizedPlan);
  const planHash = planFingerprint(normalizedPlan);
  const resolvedPromptHash = promptHash || fingerprint(clean(prompt, 600));
  const resolvedContextFingerprint = contextFingerprint || fingerprint(context);
  const loopIdentity = fingerprint({
    prompt_hash: resolvedPromptHash,
    context_fingerprint: resolvedContextFingerprint,
    plan: normalizedPlan,
    run_id: clean(runId, 120) || null,
  });
  const loopId = clean(context.loop_id, 160) || `loop_${loopIdentity}`;
  const loop = {
    loop_version: LOOP_VERSION,
    schema_version: LOOP_SCHEMA_VERSION,
    contract_version: LOOP_CONTRACT_VERSION,
    architecture: "loop-engineering-excellence",
    loop_id: loopId,
    idempotency_key: fingerprint({
      prompt_hash: resolvedPromptHash,
      context_fingerprint: resolvedContextFingerprint,
      plan: normalizedPlan,
      run_id: clean(runId, 120) || null,
    }),
    run_id: clean(runId, 120) || null,
    trace_id: clean(runId, 120) || `trace_${crypto.randomUUID().slice(0, 12)}`,
    status: initial.status,
    phase: initial.phase,
    goal: deriveGoal(normalizedPlan, prompt),
    hypothesis: deriveHypothesis(normalizedPlan, context),
    trigger: clean(context.trigger || context.mode || "reactive", 64) || "reactive",
    action_types: actionList,
    intervention: { action_types: actionList, plan_fingerprint: planHash, recommendation_id: normalizedPlan.recommendation_id },
    plan_fingerprint: planHash,
    success_criteria: {
      execution: actionList.length === 0 ? "conversation_delivered" : "device_state_matches_requested_action",
      verification_required: actionList.length > 0,
      behavioral_outcome: "collect_after_intervention",
    },
    stop_conditions: ["user_declined", "user_cancelled", "verification_failed_after_budget", "event_or_duration_budget_exhausted"],
    budget: {
      max_iterations: Number(contract.limits?.max_iterations || 3),
      max_events: Number(contract.limits?.max_events || 32),
      max_actions: Number(contract.limits?.max_actions || 4),
      max_notifications: Number(contract.limits?.max_notifications || 3),
      max_duration_hours: maxDurationHours,
      iteration: 0,
      event_count: 0,
      notification_count: 0,
    },
    iteration: 0,
    max_iterations: Number(contract.limits?.max_iterations || 3),
    next_step: null,
    consent: {
      required: policy.requires_confirmation,
      status: policy.autonomous_allowed ? "pre_authorized" : policy.requires_confirmation ? "pending" : "not_required",
      source: context.autonomy_consent === true || context.autonomy_grant?.active === true ? "explicit_autonomy_grant" : "per_action_confirmation",
    },
    policy,
    verification: { status: "not_started", attempts: 0, evidence: null, source: null, reason: null },
    behavioral_outcome: { status: "awaiting", score: null, measured_at: null, source: null },
    adaptation: { status: "not_needed", attempts: 0, last_signal: null, next_action: null },
    provenance: {
      run_id: clean(runId, 120) || null,
      prompt_hash: resolvedPromptHash,
      context_fingerprint: resolvedContextFingerprint,
      plan_fingerprint: planHash,
    },
    contract_warnings: [...validation.errors, ...validation.warnings, ...(policy.blocked ? ["policy_blocked"] : [])],
    stop_reason: null,
    last_event: { type: "planned", at: iso(created) },
    last_rejection: null,
    state_version: 1,
    event_sequence: 0,
    created_at: iso(created),
    updated_at: iso(created),
    expires_at: iso(expires),
    event_ids: [],
    events: [],
  };
  if (!validation.valid || policy.blocked) {
    loop.status = "failed";
    loop.phase = "stop";
    loop.stop_reason = "invalid_plan_contract";
  }
  loop.next_step = nextStep(loop);
  return loop;
}

function isExpired(loop) { return Boolean(loop?.expires_at && new Date(loop.expires_at).getTime() <= Date.now()); }

function eventFingerprint(event = {}, iteration = 0) {
  return fingerprint({
    iteration,
    type: eventType(event.type),
    success: event.success === true,
    verification: clean(event.verification?.status || event.verification, 32) || null,
    reason: clean(event.reason, 180) || null,
    source: clean(event.source, 40) || "client",
    evidence_hash: clean(event.evidence?.evidence_hash || event.evidence_hash, 120) || null,
    outcome: clean(event.outcome || event.behavioral_outcome?.status, 40) || null,
    outcome_score: Number.isFinite(Number(event.outcome_score)) ? Number(event.outcome_score) : null,
  });
}

function hydrateLoop(loop) {
  const next = clone(loop || {});
  next.events = Array.isArray(next.events) && next.events.length
    ? next.events.slice()
    : Array.isArray(next.event_history) ? next.event_history.slice() : [];
  next.event_ids = Array.isArray(next.event_ids) ? next.event_ids.slice() : next.events.map((event) => event.event_id).filter(Boolean);
  next.budget = {
    max_iterations: Number(contract.limits?.max_iterations || 3),
    max_events: Number(contract.limits?.max_events || 32),
    max_actions: Number(contract.limits?.max_actions || 4),
    max_notifications: Number(contract.limits?.max_notifications || 3),
    max_duration_hours: Number(contract.limits?.max_duration_hours || 168),
    iteration: 0,
    event_count: next.events.length,
    notification_count: 0,
    ...(next.budget && typeof next.budget === "object" ? next.budget : {}),
  };
  next.state_version = Number.isInteger(next.state_version) ? next.state_version : 1 + next.budget.event_count;
  next.event_sequence = Number.isInteger(next.event_sequence) ? next.event_sequence : next.budget.event_count;
  next.loop_version = next.loop_version || LOOP_VERSION;
  next.schema_version = next.schema_version || LOOP_SCHEMA_VERSION;
  next.contract_version = next.contract_version || LOOP_CONTRACT_VERSION;
  next.action_types = Array.isArray(next.action_types) ? next.action_types : next.intervention?.action_types || [];
  next.intervention = next.intervention || { action_types: next.action_types };
  const consent = next.consent && typeof next.consent === "object" ? next.consent : {};
  const policy = next.policy && typeof next.policy === "object" ? next.policy : {};
  next.consent = {
    required: consent.required === true || policy.requires_confirmation === true,
    status: clean(consent.status, 32) || (policy.autonomous_allowed === true ? "pre_authorized" : "pending"),
    source: clean(consent.source, 64) || "per_action_confirmation",
  };
  next.verification = next.verification || { status: "not_started", attempts: 0 };
  next.behavioral_outcome = next.behavioral_outcome || { status: "awaiting", score: null };
  next.adaptation = next.adaptation || { status: "not_needed", attempts: 0 };
  return next;
}

function hasEvent(loop, type, iteration = loop.iteration) {
  return (loop.events || []).some((item) => item.type === type
    && (iteration == null || item.iteration === iteration)
    && item.accepted !== false);
}

function canTransition(loop, type) {
  const allowed = contract.transition_policy?.[loop.status];
  return Array.isArray(allowed) && allowed.includes(type);
}

function appendEvent(next, event, transition, accepted = true) {
  const safeEvent = {
    event_id: eventId(event.event_id),
    type: eventType(event.type),
    at: iso(now()),
    transition,
    accepted,
    iteration: next.iteration,
    event_fingerprint: eventFingerprint(event, next.iteration),
    success: event.success === true,
    verification: clean(event.verification?.status || event.verification, 32) || null,
    source: clean(event.source || "client", 40) || "client",
    evidence_hash: clean(event.evidence?.evidence_hash || event.evidence_hash, 120) || null,
  };
  next.events.push(safeEvent);
  next.event_ids.push(safeEvent.event_id);
  next.budget.event_count += 1;
  next.state_version += 1;
  next.updated_at = safeEvent.at;
  next.last_event = { type: safeEvent.type, at: safeEvent.at, transition, accepted };
  next.next_step = nextStep(next);
  next.event_sequence = next.budget.event_count;
  if (TERMINAL.has(next.status)) next.terminal_at = safeEvent.at;
}

function terminal(next, status, phase, reason) {
  next.status = status;
  next.phase = phase;
  next.stop_reason = reason || next.stop_reason || null;
  next.next_step = nextStep(next);
  if (TERMINAL.has(status)) next.terminal_at = next.updated_at;
}

function reject(loop, transition, error, event = null) {
  const next = clone(loop);
  next.last_rejection = { transition, error, event_id: event ? eventId(event.event_id || event.idempotency_key) : null, at: iso(now()) };
  return { loop: next, transition, accepted: false, error, ...(event ? { event_id: eventId(event.event_id || event.idempotency_key) } : {}) };
}

function failOrRetry(next, event, reason) {
  next.verification = { ...next.verification, status: "failed", attempts: next.verification.attempts + 1, reason: clean(reason || event.reason, 180) || "verification_failed" };
  const nextIteration = next.iteration + 1;
  if (nextIteration < next.max_iterations) {
    next.status = "retryable";
    next.phase = "adapt";
    next.iteration = nextIteration;
    next.budget.iteration = nextIteration;
    next.adaptation = { status: "required", attempts: nextIteration, last_signal: learningSignal(next, { ...event, outcome: "failed" }), next_action: "adapt_and_confirm" };
    return "retryable_failure";
  }
  terminal(next, "failed", "stop", "verification_failed_after_budget");
  next.adaptation = { status: "stopped_after_budget", attempts: nextIteration, last_signal: learningSignal(next, { ...event, outcome: "failed" }), next_action: "none" };
  return "failed_terminal";
}

function advanceLoop(loop, event = {}) {
  if (!loop || typeof loop !== "object") return reject(loop, "rejected_invalid_loop", "invalid_loop");
  loop = hydrateLoop(loop);
  const type = eventType(event.type);
  const id = eventId(event.event_id || event.idempotency_key);
  if (!id) return reject(loop, "rejected_invalid_event", "missing_event_id");
  if (!type || !contract.events.includes(type)) return reject(loop, "rejected_invalid_event", "unsupported_event_type", event);
  const knownById = (loop.events || []).find((item) => item.event_id === id);
  if (knownById) {
    const incoming = eventFingerprint(event, knownById.iteration);
    if (knownById.event_fingerprint !== incoming) return reject(loop, "rejected_event_conflict", "event_id_reused_with_different_payload", event);
    return { loop, transition: "ignored_duplicate", accepted: false, duplicate: true, event_id: id };
  }
  if (type === "outcome_recorded" && hasEvent(loop, "outcome_recorded", null)) {
    return { loop, transition: "ignored_duplicate", accepted: false, duplicate: true, event_id: id };
  }
  if (TERMINAL.has(loop.status) && type !== "outcome_recorded") return { loop, transition: "ignored_terminal", accepted: false, event_id: id };
  if (["confirm", "setup_completed", "execution_started"].includes(type) && hasEvent(loop, type)) return { loop, transition: "ignored_duplicate", accepted: false, duplicate: true, event_id: id };
  if (isExpired(loop)) {
    const next = clone(loop);
    terminal(next, "stopped", "stop", "loop_expired");
    appendEvent(next, { ...event, event_id: id, type: "cancelled", reason: "loop_expired" }, "expired");
    return { loop: next, transition: "expired", accepted: true, event_id: id };
  }
  if (loop.budget.event_count >= loop.budget.max_events) return reject(loop, "rejected_budget", "event_budget_exhausted", event);
  if (!canTransition(loop, type)) return reject(loop, "rejected_invalid_transition", `${loop.status}:${type}`, event);
  if (type === "executed" && !hasEvent(loop, "execution_started")) return reject(loop, "rejected_invalid_transition", "execution_started_required", event);
  if (type === "verified" && !hasEvent(loop, "executed")) return reject(loop, "rejected_invalid_transition", "executed_required", event);

  const next = hydrateLoop(loop);
  let transition = type;
  if (type === "confirm") {
    next.status = "awaiting_execution";
    next.phase = "execute";
    next.consent.status = "confirmed";
    transition = "ready_for_execution";
  } else if (type === "setup_completed") {
    next.status = "awaiting_confirmation";
    next.phase = "propose";
    transition = "setup_completed";
  } else if (type === "execution_started") {
    next.status = "awaiting_execution";
    next.phase = "execute";
    transition = "execution_started";
  } else if (type === "executed") {
    if (isPositiveVerification(event)) {
      const verification = verificationFromEvent(event);
      next.verification = { ...verification, attempts: next.verification.attempts + 1 };
      terminal(next, "completed", "learn", "verification_passed");
      transition = "verified";
    } else if (event.success === true) {
      next.status = "awaiting_execution";
      next.phase = "verify";
      next.verification = { ...next.verification, status: "pending", source: clean(event.source || "device", 40) || "device", reason: "execution_reported_without_positive_verification" };
      transition = "awaiting_verification";
    } else {
      transition = failOrRetry(next, event, "execution_failed");
    }
  } else if (type === "verified") {
    if (isPositiveVerification(event)) {
      const verification = verificationFromEvent(event);
      next.verification = { ...verification, attempts: next.verification.attempts + 1 };
      terminal(next, "completed", "learn", "verification_passed");
      transition = "verified";
    } else {
      transition = failOrRetry(next, event, "verification_failed");
    }
  } else if (type === "failed") {
    transition = failOrRetry(next, event, event.reason || "execution_failed");
  } else if (type === "declined" || type === "cancelled") {
    terminal(next, "stopped", "stop", type === "declined" ? "user_declined" : "user_cancelled");
    next.consent.status = type === "declined" ? "declined" : "cancelled";
    transition = type;
  } else if (type === "outcome_recorded") {
    next.behavioral_outcome = normalizeOutcome(event);
    next.adaptation = { ...next.adaptation, status: "recorded", last_signal: learningSignal(next, event), next_action: "apply_on_next_recommendation" };
    if (next.status === "awaiting_input") terminal(next, "completed", "learn", "outcome_recorded");
    transition = "outcome_recorded";
  }
  appendEvent(next, { ...event, event_id: id, type }, transition);
  return { loop: next, transition, accepted: true, event_id: id };
}

function loopSummary(loop) {
  return {
    loop_id: loop?.loop_id || null,
    status: loop?.status || null,
    phase: loop?.phase || null,
    action_types: loop?.action_types || [],
    iteration: loop?.iteration || 0,
    event_count: loop?.budget?.event_count || 0,
    verification: loop?.verification?.status || "not_started",
    outcome: loop?.behavioral_outcome?.status || "awaiting",
  };
}

function publicLoop(loop) {
  if (!loop) return null;
  return {
    loop_version: loop.loop_version,
    schema_version: loop.schema_version,
    contract_version: loop.contract_version,
    architecture: loop.architecture,
    loop_id: loop.loop_id,
    idempotency_key: loop.idempotency_key,
    run_id: loop.run_id,
    trace_id: loop.trace_id,
    status: loop.status,
    phase: loop.phase,
    goal: loop.goal,
    hypothesis: loop.hypothesis,
    trigger: loop.trigger,
    action_types: loop.action_types,
    intervention: loop.intervention,
    plan_fingerprint: loop.plan_fingerprint,
    success_criteria: loop.success_criteria,
    stop_conditions: loop.stop_conditions,
    budget: loop.budget,
    iteration: loop.iteration,
    max_iterations: loop.max_iterations,
    next_step: loop.next_step,
    consent: loop.consent,
    policy: loop.policy,
    verification: publicVerification(loop.verification),
    behavioral_outcome: publicOutcome(loop.behavioral_outcome),
    adaptation: loop.adaptation,
    contract_warnings: loop.contract_warnings,
    stop_reason: loop.stop_reason || null,
    last_event: loop.last_event,
    provenance: {
      run_id: loop.provenance?.run_id || null,
      prompt_hash: loop.provenance?.prompt_hash || null,
      context_fingerprint: loop.provenance?.context_fingerprint || null,
      plan_fingerprint: loop.provenance?.plan_fingerprint || null,
    },
    state_version: loop.state_version,
    event_sequence: loop.event_sequence || loop.budget?.event_count || 0,
    created_at: loop.created_at,
    updated_at: loop.updated_at,
    expires_at: loop.expires_at,
    event_ids: Array.isArray(loop.event_ids) ? loop.event_ids.slice() : [],
    event_history: Array.isArray(loop.events) ? loop.events.map((event) => ({
      event_id: event.event_id,
      type: event.type,
      at: event.at,
      transition: event.transition,
      accepted: event.accepted !== false,
      iteration: event.iteration || 0,
      event_fingerprint: event.event_fingerprint || null,
      success: event.success === true,
      verification: event.verification || null,
      source: event.source || null,
      evidence_hash: event.evidence_hash || null,
    })) : [],
  };
}

function persistenceState(loop) {
  const state = clone(loop || {});
  delete state.current_state;
  state.event_sequence = state.event_sequence || state.budget?.event_count || 0;
  state.current_state = clone(state);
  return state;
}

function canPersist(body = {}) {
  return body.data_consent === true
    && anonymousUserId(body.anonymous_user_id) !== ""
    && Boolean(process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY);
}

async function persistState({ body = {}, loop, event = {}, transition, expectedStateVersion }) {
  const persistedUserId = anonymousUserId(body.anonymous_user_id);
  if (!body.data_consent || !persistedUserId) {
    return { persisted: false, reason: "consent_or_user_missing" };
  }
  if (!canPersist(body)) return { persisted: false, reason: "persistence_not_configured" };
  const eventIdValue = eventId(event.event_id || event.id || event.idempotency_key) || `planned_${loop.loop_id}`;
  const payload = {
    type: eventType(event.type || "planned"),
    success: event.success === true,
    verification: clean(event.verification?.status || event.verification, 32) || null,
    source: clean(event.source || "client", 40) || "client",
    evidence_hash: clean(event.evidence?.evidence_hash || event.evidence_hash, 120) || null,
    reason: clean(event.reason, 180) || null,
    outcome: clean(event.outcome || event.behavioral_outcome?.status, 40) || null,
    outcome_score: Number.isFinite(Number(event.outcome_score)) ? Number(event.outcome_score) : null,
  };
  const state = persistenceState(loop);
  try {
    const result = await supabaseFetch("rpc/bm_append_loop_event", {
      method: "POST",
      body: JSON.stringify({
        p_loop_id: loop.loop_id,
        p_anonymous_user_id: persistedUserId,
        p_expected_state_version: Number.isInteger(expectedStateVersion) ? expectedStateVersion : 0,
        p_transition: clean(transition || "planned", 80),
        p_event_id: eventIdValue,
        p_event_type: payload.type,
        p_event_payload: payload,
        p_next_state: state,
      }),
    });
    const resultValue = Array.isArray(result) ? result[0] : result;
    if (resultValue?.status === "conflict") {
      return { persisted: false, reason: "state_conflict", state_version: resultValue.state_version || null };
    }
    if (resultValue?.status === "duplicate") return { persisted: true, duplicate: true, status: "duplicate" };
    return { persisted: true, status: resultValue?.status || "applied" };
  } catch (error) {
    console.warn("bm_loop_persistence_failed", JSON.stringify({
      loop_id: loop.loop_id,
      error: clean(error.code || error.name, 80) || "persistence_error",
    }));
    return { persisted: false, reason: "persistence_failed" };
  }
}

async function handler(event) {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;
  try {
    const body = parseJsonBody(event);
    const operation = clean(body.operation || "start", 32).toLowerCase();
    if (operation === "start") {
      const loop = createLoop({
        prompt: body.prompt || body.prompt_hash,
        context: body.context && typeof body.context === "object" ? body.context : {},
        plan: body.plan,
        runId: body.run_id,
        promptHash: body.prompt_hash,
        contextFingerprint: body.context_fingerprint,
      });
      const persistence = await persistState({
        body,
        loop,
        event: { type: "planned", event_id: `planned_${loop.loop_id}` },
        transition: "planned",
        expectedStateVersion: 0,
      });
      const startStatus = persistence.reason === "state_conflict" ? 409 : 200;
      return json(startStatus, { ok: startStatus === 200, loop: publicLoop(loop), summary: loopSummary(loop), persistence });
    }
    if (operation === "advance") {
      const previous = body.loop;
      const incoming = body.event && typeof body.event === "object" ? body.event : body;
      const result = advanceLoop(previous, incoming);
      const accepted = result.accepted === true;
      const persistence = accepted
        ? await persistState({
          body,
          loop: result.loop,
          event: incoming,
          transition: result.transition,
          expectedStateVersion: Number(previous?.state_version || 0),
        })
        : { persisted: false, reason: result.transition };
      const persistenceConflict = persistence.reason === "state_conflict";
      return json(persistenceConflict ? 409 : 200, {
        ok: !persistenceConflict,
        accepted,
        transition: result.transition,
        error: result.error || null,
        duplicate: result.duplicate === true,
        loop: publicLoop(persistenceConflict ? previous : result.loop),
        summary: loopSummary(result.loop),
        persistence,
      });
    }
    return json(400, { error: "unsupported_loop_operation" });
  } catch (error) {
    return json(400, { error: "bm_loop_failed", detail: clean(error.message, 160) });
  }
}

module.exports = {
  CONTRACT_VERSION: LOOP_CONTRACT_VERSION,
  LOOP_SCHEMA_VERSION,
  LOOP_VERSION,
  advanceLoop,
  createLoop,
  loopSummary,
  publicLoop,
  handler,
};
