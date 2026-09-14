"use strict";

const { clean } = require("./bm-contracts");

function normalizeChecks(value) {
  if (!Array.isArray(value)) return [];
  return value.slice(0, 12).map((check) => ({
    name: clean(check?.name, 80),
    expected: clean(check?.expected, 160),
    actual: clean(check?.actual, 160),
    passed: check?.passed === true,
  })).filter((check) => check.name || check.expected || check.actual);
}

function normalizeEvidence(event = {}) {
  const source = event.evidence && typeof event.evidence === "object" ? event.evidence : event;
  return {
    source: clean(source.source || event.source || "device", 40) || "device",
    device_state: clean(source.device_state || source.observed_state || event.device_state, 240) || null,
    checks: normalizeChecks(source.checks),
    observed_at: clean(source.observed_at || event.observed_at, 64) || null,
    evidence_hash: clean(source.evidence_hash || event.evidence_hash, 120) || null,
  };
}

function verificationFromEvent(event = {}) {
  const explicit = clean(event.verification?.status || event.verification, 32).toLowerCase();
  const passed = event.success === true && explicit === "passed";
  const failed = event.success === false || ["failed", "rejected", "timeout"].includes(explicit);
  return {
    status: passed ? "passed" : failed ? "failed" : "pending",
    evidence: normalizeEvidence(event),
    source: clean(event.source || event.verification?.source || "device", 40) || "device",
    reason: clean(event.reason || event.verification?.reason, 180) || null,
  };
}

function isPositiveVerification(event = {}) {
  return verificationFromEvent(event).status === "passed";
}

function publicVerification(verification = {}) {
  return {
    status: clean(verification.status, 24) || "not_started",
    source: clean(verification.source, 40) || null,
    reason: clean(verification.reason, 180) || null,
    evidence: verification.evidence ? {
      source: clean(verification.evidence.source, 40) || null,
      device_state: clean(verification.evidence.device_state, 240) || null,
      checks: Array.isArray(verification.evidence.checks) ? verification.evidence.checks : [],
      observed_at: clean(verification.evidence.observed_at, 64) || null,
      evidence_hash: clean(verification.evidence.evidence_hash, 120) || null,
    } : null,
  };
}

module.exports = {
  isPositiveVerification,
  normalizeEvidence,
  publicVerification,
  verificationFromEvent,
};
