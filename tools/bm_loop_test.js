const assert = require("assert");
const {
  createLoop,
  advanceLoop,
  publicLoop,
  LOOP_VERSION,
  LOOP_SCHEMA_VERSION,
} = require("../netlify/functions/bm-loop");

const plan = {
  intent: "sleep",
  title: "Scheduled Protection",
  response_text: "I would protect the risky window.",
  actions: [{ type: "apply_schedule", start_minute: 1320, end_minute: 420 }],
};

function startLoop() {
  return createLoop({
    prompt: "Block Instagram from 10 PM to 7 AM",
    context: { channel: "app", has_selected_apps: true, screen_time_authorized: true },
    plan,
    runId: "bm_test_run",
  });
}

const repeatA = startLoop();
const repeatB = startLoop();
assert.strictEqual(repeatA.loop_id, repeatB.loop_id);
assert.strictEqual(repeatA.idempotency_key, repeatB.idempotency_key);

assert.strictEqual(LOOP_VERSION, "bm-loop-excellence-v1");
assert.strictEqual(LOOP_SCHEMA_VERSION, 1);

let loop = startLoop();
assert.strictEqual(loop.status, "awaiting_confirmation");
assert.strictEqual(loop.phase, "propose");
assert.strictEqual(loop.contract_warnings.length, 0);

let result = advanceLoop(loop, { type: "executed", event_id: "event_too_early", success: true });
assert.strictEqual(result.transition, "rejected_invalid_transition");
assert.strictEqual(result.accepted, false);
assert.strictEqual(result.loop.status, "awaiting_confirmation");

result = advanceLoop(loop, { type: "confirm", event_id: "event_confirm" });
loop = result.loop;
assert.strictEqual(result.transition, "ready_for_execution");
assert.strictEqual(loop.status, "awaiting_execution");

result = advanceLoop(loop, { type: "execution_started", event_id: "event_start" });
loop = result.loop;
assert.strictEqual(result.transition, "execution_started");

result = advanceLoop(loop, {
  type: "executed",
  event_id: "event_executed",
  success: true,
});
assert.strictEqual(result.transition, "awaiting_verification");
assert.strictEqual(result.loop.status, "awaiting_execution");

result = advanceLoop(result.loop, {
  type: "verified",
  event_id: "event_verified",
  success: true,
  verification: "passed",
});
loop = result.loop;
assert.strictEqual(result.transition, "verified");
assert.strictEqual(loop.status, "completed");
assert.strictEqual(loop.verification.status, "passed");
assert.strictEqual(loop.stop_reason, "verification_passed");

result = advanceLoop(loop, {
  type: "verified",
  event_id: "event_verified",
  success: true,
  verification: "passed",
});
assert.strictEqual(result.transition, "ignored_duplicate");
assert.strictEqual(result.duplicate, true);

const terminalLater = advanceLoop(loop, {
  type: "verified",
  event_id: "event_after_terminal",
  success: true,
  verification: "passed",
});
assert.strictEqual(terminalLater.transition, "ignored_terminal");

const learned = advanceLoop(loop, {
  type: "outcome_recorded",
  event_id: "outcome_held",
  outcome: "held",
  outcome_score: 42,
});
assert.strictEqual(learned.accepted, true);
assert.strictEqual(learned.loop.status, "completed");
assert.strictEqual(learned.loop.behavioral_outcome.status, "held");
assert.strictEqual(learned.loop.adaptation.last_signal.adjustment, "preserve");

let duplicate = startLoop();
duplicate = advanceLoop(duplicate, { type: "confirm", event_id: "confirm_one" }).loop;
const duplicateAgain = advanceLoop(duplicate, { type: "confirm", event_id: "confirm_two" });
assert.strictEqual(duplicateAgain.transition, "ignored_duplicate");
assert.strictEqual(duplicateAgain.loop.events.length, 1);

let conflict = startLoop();
conflict = advanceLoop(conflict, { type: "confirm", event_id: "same_event", reason: "first" }).loop;
const conflictResult = advanceLoop(conflict, { type: "confirm", event_id: "same_event", reason: "different" });
assert.strictEqual(conflictResult.transition, "rejected_event_conflict");
assert.strictEqual(conflictResult.loop.status, "awaiting_execution");

let failedVerification = startLoop();
failedVerification = advanceLoop(failedVerification, { type: "confirm", event_id: "failed_confirm" }).loop;
failedVerification = advanceLoop(failedVerification, { type: "execution_started", event_id: "failed_start" }).loop;
failedVerification = advanceLoop(failedVerification, {
  type: "executed",
  event_id: "failed_executed",
  success: true,
}).loop;
const failedResult = advanceLoop(failedVerification, {
  type: "verified",
  event_id: "failed_verified",
  success: false,
  verification: "failed",
});
assert.strictEqual(failedResult.transition, "retryable_failure");
assert.strictEqual(failedResult.loop.status, "retryable");

const retryWithoutConfirmation = advanceLoop(failedResult.loop, {
  type: "execution_started",
  event_id: "retry_start_too_early",
});
assert.strictEqual(retryWithoutConfirmation.transition, "rejected_invalid_transition");

const invalidPlan = createLoop({ plan: { title: "Unsafe", actions: [{ type: "delete_everything" }] } });
assert.strictEqual(invalidPlan.status, "failed");
assert.strictEqual(invalidPlan.stop_reason, "invalid_plan_contract");
assert.ok(invalidPlan.contract_warnings.includes("unknown_action_type"));

const publicState = publicLoop(loop);
assert.strictEqual(publicState.loop_id, loop.loop_id);
assert.strictEqual(publicState.loop_version, "bm-loop-excellence-v1");
assert.strictEqual(publicState.schema_version, 1);
assert.strictEqual(publicState.contract_version, "bm-loop-contract-excellence-v1");
assert.deepStrictEqual(publicState.action_types, ["apply_schedule"]);
assert.strictEqual(publicState.verification.status, "passed");
assert.strictEqual(publicState.event_ids.length, 4);
assert.strictEqual(Object.prototype.hasOwnProperty.call(publicState, "events"), false);
assert.strictEqual(publicState.event_sequence, 4);
assert.ok(Array.isArray(publicState.event_history));
assert.doesNotMatch(JSON.stringify(publicState), /Block Instagram from 10 PM to 7 AM/);

let roundTrip = publicLoop(startLoop());
roundTrip = publicLoop(advanceLoop(roundTrip, { type: "confirm", event_id: "round_confirm" }).loop);
roundTrip = publicLoop(advanceLoop(roundTrip, { type: "execution_started", event_id: "round_start" }).loop);
roundTrip = publicLoop(advanceLoop(roundTrip, { type: "executed", event_id: "round_executed", success: true }).loop);
const roundTripResult = advanceLoop(roundTrip, {
  type: "verified",
  event_id: "round_verified",
  success: true,
  verification: "passed",
});
assert.strictEqual(roundTripResult.accepted, true);
assert.strictEqual(roundTripResult.loop.status, "completed");

console.log("bm_loop_test: ok");
