"use strict";

const assert = require("assert");
const { buildAgentContext } = require("../netlify/functions/bm-context");
const { resolveBlockingContract } = require("../netlify/functions/bm-blocking-contract");

function contract(prompt, context = {}) {
  return resolveBlockingContract(prompt, buildAgentContext(context));
}

const missingDuration = contract("I want to block Instagram now.");
assert.strictEqual(missingDuration.ready, false);
assert.deepStrictEqual(missingDuration.missing_fields, ["end"]);

const immediate = contract("Block TikTok indefinitely now.");
assert.strictEqual(immediate.ready, true);
assert.deepStrictEqual(immediate.data.apps, ["TikTok"]);
assert.strictEqual(immediate.data.start.type, "now");
assert.strictEqual(immediate.data.end.type, "indefinite");
assert.deepStrictEqual(immediate.data.recurrence.value, [0]);

const scheduled = contract("Block Instagram for 1 hour at 7 pm every day.");
assert.strictEqual(scheduled.ready, true);
assert.strictEqual(scheduled.data.start.value, 19 * 60);
assert.strictEqual(scheduled.data.end.value, 60);
assert.deepStrictEqual(scheduled.data.recurrence.value, [1, 2, 3, 4, 5, 6, 7]);

const ambiguous = contract("Bloquea Instagram de 10 a 7.");
assert.strictEqual(ambiguous.ready, true);
assert.strictEqual(ambiguous.data.start.value, 22 * 60);
assert.strictEqual(ambiguous.data.end.value, 7 * 60);
assert.deepStrictEqual(ambiguous.data.recurrence.value, [0]);

const overnight = contract("Block Instagram from 10 pm to 7 am.");
assert.strictEqual(overnight.ready, true);
assert.strictEqual(overnight.data.start.value, 22 * 60);
assert.strictEqual(overnight.data.end.value, 7 * 60);
assert.deepStrictEqual(overnight.data.recurrence.value, [0]);

const spanishOvernight = contract("Bloquea TikTok de 22 a 7.");
assert.strictEqual(spanishOvernight.ready, true);
assert.strictEqual(spanishOvernight.data.start.value, 22 * 60);
assert.strictEqual(spanishOvernight.data.end.value, 7 * 60);
assert.deepStrictEqual(spanishOvernight.data.recurrence.value, [0]);

const dailyLimit = contract("Set a 25-minute daily limit for Instagram.");
assert.strictEqual(dailyLimit.ready, true);
assert.strictEqual(dailyLimit.data.action, "daily_limit");
assert.strictEqual(dailyLimit.data.end.value, 25);

const mode = contract("Start Work mode for 45 minutes.", { has_selected_apps: true });
assert.strictEqual(mode.ready, true);
assert.deepStrictEqual(mode.data.apps, ["selected_apps"]);
assert.strictEqual(mode.data.start.type, "now");
assert.strictEqual(mode.data.end.value, 45);

const legacyModeLanguage = contract("Start Gaming mode for 30 minutes.", { has_selected_apps: true });
assert.strictEqual(legacyModeLanguage.is_blocking_request, true);
assert.deepStrictEqual(legacyModeLanguage.data.apps, ["selected_apps"]);

const modeByApps = contract("Block Instagram now for 45 minutes. Only one time.", { has_selected_apps: true });
assert.strictEqual(modeByApps.ready, true);
assert.deepStrictEqual(modeByApps.data.apps, ["selected_apps"]);
assert.strictEqual(modeByApps.app_source, "device_selection");

const modeBySyncedContext = contract("Block Instagram indefinitely now.", {
  user_context: {
    has_selected_apps: true,
  },
});
assert.deepStrictEqual(modeBySyncedContext.data.apps, ["selected_apps"]);

const scheduledMode = contract("Block Instagram for 1 hour at 7 pm every day.", {
  user_context: {
    has_selected_apps: true,
  },
});
assert.deepStrictEqual(scheduledMode.data.apps, ["selected_apps"]);

const pendingModeFollowup = contract("3 mins", {
  user_context: {
    has_selected_apps: true,
  },
  pending_blocking: {
    apps: ["Instagram"],
    start: { type: "now", value: "now" },
    recurrence: { type: "once", value: [0] },
  },
});
assert.deepStrictEqual(pendingModeFollowup.data.apps, ["selected_apps"]);

const continuation = contract("45 minutes", {
  pending_blocking: {
    apps: ["Instagram"],
    start: { type: "now", value: "now" },
    recurrence: { type: "once", value: [0] },
  },
});
assert.strictEqual(continuation.ready, true);
assert.deepStrictEqual(continuation.data.apps, ["Instagram"]);
assert.strictEqual(continuation.data.end.value, 45);

const naturalContinuation = contract("Start now for an hour. Only one time", {
  pending_blocking: {
    apps: ["Instagram"],
    action: "hard_block",
  },
});
assert.strictEqual(naturalContinuation.ready, true);
assert.strictEqual(naturalContinuation.data.end.value, 60);
assert.deepStrictEqual(naturalContinuation.data.recurrence.value, [0]);

const relativeContinuation = contract("Usually 9.", {
  recent_messages: [
    { role: "user", content: "Can you block Instagram after dinner?" },
    { role: "assistant", content: "What time do you usually finish dinner?" },
  ],
});
assert.strictEqual(relativeContinuation.ready, true);
assert.strictEqual(relativeContinuation.data.start.value, 21 * 60);
assert.strictEqual(relativeContinuation.data.end.value, 90);
assert.deepStrictEqual(relativeContinuation.data.recurrence.value, [1, 2, 3, 4, 5, 6, 7]);

const workConflict = contract("Block Instagram, but I need it for work.");
assert.strictEqual(workConflict.is_blocking_request, false);

const normalizedPending = buildAgentContext({
  memory: { pending_blocking: { apps: ["TikTok"], end: { type: "indefinite", value: null } } },
});
assert.deepStrictEqual(normalizedPending.memory.pending_blocking.apps, ["TikTok"]);

const oldContextDoesNotContaminateThanks = contract("Thanks", {
  recent_messages: [
    { role: "user", content: "Block Instagram from 10 pm to 7 am every day." },
    { role: "assistant", content: "I can prepare that." },
  ],
});
assert.strictEqual(oldContextDoesNotContaminateThanks.is_blocking_request, false);

const relativeClockFollowup = contract("2:30", {
  recent_messages: [
    { role: "user", content: "Block Instagram after lunch." },
    { role: "assistant", content: "What time do you usually finish lunch?" },
  ],
  conversation_state: { updated_at: new Date().toISOString() },
});
assert.strictEqual(relativeClockFollowup.ready, true);
assert.strictEqual(relativeClockFollowup.data.start.value, 14 * 60 + 30);

const expiredPending = contract("2:30", {
  pending_blocking: {
    apps: ["Instagram"],
    updated_at: new Date(Date.now() - 3 * 60 * 60 * 1000).toISOString(),
  },
});
assert.strictEqual(expiredPending.is_blocking_request, false);

const permanentLockout = contract("Block everything forever.");
assert.strictEqual(permanentLockout.is_blocking_request, false);

console.log("bm blocking contract tests passed");
