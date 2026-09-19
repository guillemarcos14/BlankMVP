"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { buildAgentContext, normalizeUserContext } = require("../netlify/functions/bm-context");
const { scheduleManagementPlan } = require("../netlify/functions/bm-schedule-management");
const { pendingActionFromPlan } = require("../netlify/functions/bm-pending-action");
const { enforceSemanticBoundary } = require("../netlify/functions/blanked-agent");

const root = path.join(__dirname, "..");
const upsertFix = fs.readFileSync(path.join(root, "supabase/migrations/017_fix_bm_context_upsert.sql"), "utf8");
const persistenceSource = fs.readFileSync(path.join(root, "netlify/functions/_bm_user_context.js"), "utf8");
const assistantChannelSource = fs.readFileSync(path.join(root, "netlify/functions/assistant-channel.js"), "utf8");
assert.match(upsertFix, /on conflict on constraint bm_user_context_snapshots_pkey/i);
assert.doesNotMatch(persistenceSource, /catch\s*\(_\)\s*\{\s*return null;\s*\}/);
assert.match(assistantChannelSource, /return await syncContext\(body\)/);
assert.match(assistantChannelSource, /assistant_identity_conflict/);

const windowId = "2D7B82F5-3F07-48F2-8D20-D4E7EA02967E";
const source = {
  anonymous_user_id: "anon-juan",
  canonical_user_id: "auth-juan",
  profile_name: "Juan",
  age_range: "25-34",
  personal_profile: { goal: "Focus after lunch", daily_hours: 5 },
  latest_insight: { pattern: "post_lunch_scroll" },
  recent_plan_outcomes: [{ outcome: "held", outcome_score: 0.9 }],
  schedule: {
    enabled: true,
    windows: [{
      id: windowId,
      name: "Lunch focus",
      enabled: true,
      start_minute: 13 * 60,
      end_minute: 14 * 60,
      weekdays: [1, 2, 3, 4, 5, 6, 7],
    }],
  },
};

const normalized = normalizeUserContext(source);
assert.equal(normalized.profile_name, "Juan");
assert.equal(normalized.personal_profile.goal, "Focus after lunch");
assert.equal(normalized.latest_insight.pattern, "post_lunch_scroll");
assert.equal(normalized.recent_plan_outcomes[0].outcome, "held");

const context = buildAgentContext({ user_context: source });
assert.equal(context.canonical_user_id, "auth-juan");
assert.equal(context.schedule.windows[0].id, windowId);

const listed = scheduleManagementPlan("What recurring blocking windows do I have?", context);
assert.match(listed.response_text, /1:00 PM to 2:00 PM/);
assert.deepEqual(listed.actions, []);
const listedAgain = scheduleManagementPlan("What recurring blocking windows do I have?", {
  ...context,
  recent_messages: [{ role: "user", content: "same question" }, { role: "assistant", content: listed.response_text }],
});
assert.notEqual(listedAgain.response_text, listed.response_text);

const moved = scheduleManagementPlan("Move my 1 PM to 2 PM blocking window one hour later", context);
assert.equal(moved.actions[0].type, "update_schedule");
assert.equal(moved.actions[0].window_id, windowId);
assert.equal(moved.actions[0].start_minute, 14 * 60);
assert.equal(moved.actions[0].end_minute, 15 * 60);
const pendingMove = pendingActionFromPlan(moved, { now: 1_700_000_000_000 });
assert.equal(pendingMove.window_id, windowId);

const deleted = scheduleManagementPlan("Quiero eliminar todos los bloques de bloqueo", context);
assert.equal(deleted.actions[0].type, "delete_all_schedules");

const removeOne = scheduleManagementPlan("Delete the 1 PM to 2 PM blocking window", context);
assert.equal(removeOne.actions[0].type, "delete_schedule");
assert.equal(removeOne.actions[0].window_id, windowId);

const recommendation = enforceSemanticBoundary({
  response_text: "Based on your stronger adherence, keep the lunch window and move it 15 minutes earlier on difficult days.",
  actions: [{ type: "apply_schedule", start_minute: 765, end_minute: 840 }],
}, { state: { status: "idle", intent: "advice" }, decision: { type: "none", slot: null } }, "en");
assert.deepEqual(recommendation.actions, []);
assert.match(recommendation.response_text, /keep the lunch window/i);
assert.doesNotMatch(recommendation.response_text, /couldn't validate/i);

console.log("BM global context: isolated identity, personal context and schedule CRUD passed");
