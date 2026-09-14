"use strict";

const { clean, fingerprint } = require("./bm-contracts");

const OUTCOME_TYPES = Object.freeze([
  "awaiting",
  "held",
  "broke",
  "improved",
  "relapse",
  "failed",
  "dismissed",
]);

function normalizeOutcome(event = {}) {
  const raw = clean(event.behavioral_outcome?.status || event.outcome || event.behavioral_outcome, 32).toLowerCase();
  const status = OUTCOME_TYPES.includes(raw) ? raw : "awaiting";
  const score = Number(event.outcome_score ?? event.behavioral_outcome?.score);
  return {
    status,
    score: Number.isFinite(score) ? Math.max(-100, Math.min(100, Math.round(score))) : null,
    measured_at: clean(event.measured_at || event.observed_at, 64) || null,
    source: clean(event.source || "device", 40) || "device",
    note: clean(event.note, 240) || null,
  };
}

function learningSignal(loop, event = {}) {
  const outcome = normalizeOutcome(event);
  const actionTypes = Array.isArray(loop?.action_types) ? loop.action_types : [];
  const key = fingerprint({
    goal: loop?.goal,
    trigger: loop?.trigger,
    actionTypes,
  });
  const adjustment = {
    held: "preserve",
    improved: "preserve_or_reduce_friction",
    broke: "adapt_timing_or_intensity",
    relapse: "move_intervention_earlier",
    failed: "repair_execution_before_adapting",
    dismissed: "reduce_unsolicited_interventions",
    awaiting: "collect_outcome",
  }[outcome.status];
  return {
    signal_type: "bm_loop_outcome",
    signal_key: `bm:${key}`,
    outcome: outcome.status,
    score: outcome.score,
    adjustment,
    confidence: outcome.status === "awaiting" ? 0 : 60,
    action_types: actionTypes.slice(0, 4),
  };
}

function publicOutcome(outcome = {}) {
  return {
    status: OUTCOME_TYPES.includes(outcome.status) ? outcome.status : "awaiting",
    score: Number.isFinite(outcome.score) ? outcome.score : null,
    measured_at: clean(outcome.measured_at, 64) || null,
    source: clean(outcome.source, 40) || null,
  };
}

module.exports = {
  OUTCOME_TYPES,
  learningSignal,
  normalizeOutcome,
  publicOutcome,
};
