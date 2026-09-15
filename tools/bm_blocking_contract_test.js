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
assert.strictEqual(ambiguous.ready, false);
assert.ok(ambiguous.missing_fields.includes("start"));
assert.ok(ambiguous.missing_fields.includes("end"));

const dailyLimit = contract("Set a 25-minute daily limit for Instagram.");
assert.strictEqual(dailyLimit.ready, true);
assert.strictEqual(dailyLimit.data.action, "daily_limit");
assert.strictEqual(dailyLimit.data.end.value, 25);

const mode = contract("Start Work mode for 45 minutes.", { available_modes: ["Work"] });
assert.strictEqual(mode.ready, true);
assert.deepStrictEqual(mode.data.apps, ["mode:Work"]);
assert.strictEqual(mode.data.start.type, "now");
assert.strictEqual(mode.data.end.value, 45);

const modeByApps = contract("Block Instagram now for 45 minutes. Only one time.", {
  available_mode_catalog: [{ name: "Instagram solo", app_names: ["Instagram"], selection_count: 1 }],
});
assert.strictEqual(modeByApps.ready, true);
assert.deepStrictEqual(modeByApps.data.apps, ["mode:Instagram solo"]);
assert.strictEqual(modeByApps.app_source, "mode");

const modeBySyncedContext = contract("Block Instagram indefinitely now.", {
  user_context: {
    available_mode_catalog: [{ name: "Instagram solo", app_names: ["Instagram"] }],
  },
});
assert.deepStrictEqual(modeBySyncedContext.data.apps, ["mode:Instagram solo"]);

const scheduledMode = contract("Block Instagram for 1 hour at 7 pm every day.", {
  user_context: {
    available_mode_catalog: [{ name: "Instagram solo", app_names: ["Instagram"] }],
  },
});
assert.deepStrictEqual(scheduledMode.data.apps, ["mode:Instagram solo"]);

const pendingModeFollowup = contract("3 mins", {
  user_context: {
    available_mode_catalog: [{ name: "Instagram solo", app_names: ["Instagram"] }],
  },
  pending_blocking: {
    apps: ["Instagram"],
    start: { type: "now", value: "now" },
    recurrence: { type: "once", value: [0] },
  },
});
assert.deepStrictEqual(pendingModeFollowup.data.apps, ["mode:Instagram solo"]);

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

const normalizedPending = buildAgentContext({
  memory: { pending_blocking: { apps: ["TikTok"], end: { type: "indefinite", value: null } } },
});
assert.deepStrictEqual(normalizedPending.memory.pending_blocking.apps, ["TikTok"]);

console.log("bm blocking contract tests passed");
