"use strict";
const assert = require("node:assert/strict");
const { reviewActionLink } = require("../netlify/functions/_bm_action_link");
const { actionDeepLink } = require("../netlify/functions/sms-agent");

for (const action of [
  { type: "start_protection", minutes: 17, hard_mode: false },
  { type: "apply_schedule", start_minute: 0, end_minute: 57, weekdays: [2, 4], duration_days: 1 },
  { type: "set_daily_limit", minutes: 43 },
  { type: "open_app_picker" },
  { type: "request_screen_time_permission" },
]) {
  const meta = new URL(reviewActionLink(action, ["Reddit"]));
  const sms = new URL(actionDeepLink([action], ["TikTok"], { apps: ["Reddit"] }));
  assert.equal(sms.href, meta.href, `Transport mismatch for ${action.type}`);
  assert.equal(meta.searchParams.get("action"), "review-action");
  assert.equal(meta.searchParams.get("type"), action.type);
  assert.equal(meta.searchParams.get("apps"), "Reddit");
  assert.equal(meta.searchParams.get("minutes"), action.minutes == null ? null : String(action.minutes));
  if (action.weekdays) assert.equal(meta.searchParams.get("weekdays"), "2,4");
}
assert.equal(reviewActionLink({ type: "apply_schedule", start_minute: 500 }), "");
assert.equal(reviewActionLink({ type: "apply_schedule", start_minute: 0, end_minute: 0 }), "");
const nineApps = ["Instagram", "TikTok", "Reddit", "YouTube", "Netflix", "Facebook", "X", "Snapchat", "Twitch"];
const namedAction = { type: "start_protection", minutes: 24, hard_mode: false };
for (const link of [reviewActionLink(namedAction, nineApps), actionDeepLink([namedAction], [], { apps: nineApps })]) {
  const url = new URL(link);
  assert.deepEqual(url.searchParams.get("apps").split(","), nineApps, "All nine requested apps must survive channel serialization");
  assert.equal(url.searchParams.get("minutes"), "24");
}
const twelveApps = [...nineApps, "Discord", "LinkedIn", "Pinterest"];
assert.deepEqual(new URL(reviewActionLink(namedAction, twelveApps)).searchParams.get("apps").split(","), twelveApps);
assert.equal(reviewActionLink(namedAction, [...twelveApps, "WhatsApp"]), "", "An oversized proposal must not be silently truncated");
const setup = new URL(actionDeepLink([{ type: "open_app_picker" }]));
for (const parameter of ["minutes", "start", "end", "days", "hard", "name"]) {
  assert.equal(setup.searchParams.get(parameter), null, `Setup must not fabricate ${parameter}`);
}
console.log("BM channel contract: review-only parity, corrections, midnight, recurrence and no-default setup passed");
