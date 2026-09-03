const assert = require("assert");

process.env.OPENAI_API_KEY = "";

const { handler } = require("../netlify/functions/blanked-agent");

async function call(prompt, context = {}) {
  const response = await handler({
    httpMethod: "POST",
    body: JSON.stringify({ prompt, context }),
  });
  assert.strictEqual(response.statusCode, 200, response.body);
  const body = JSON.parse(response.body);
  assert.strictEqual(body.ok, true);
  return body.plan;
}

function baseContext(overrides = {}) {
  return {
    is_blank_active: false,
    has_selected_apps: true,
    selection_count: 3,
    screen_time_authorized: true,
    emergency_unlocks_remaining: 3,
    vacation_mode_active: false,
    adherence_score: 55,
    weekly_protected_minutes: 80,
    weekly_break_count: 0,
    risk_window: "9:00 PM to 10:00 PM",
    recommended_duration_minutes: 35,
    weekly_goal: "Complete 3 protected sessions.",
    memory: {},
    ...overrides,
  };
}

(async () => {
  const missingBedtime = await call("How can I not scroll at night?", baseContext());
  assert.strictEqual(missingBedtime.actions.length, 0);
  assert.match(missingBedtime.response_text, /sleep target|bedtime/i);

  const rememberedBedtime = await call("How can I not scroll at night?", baseContext({
    memory: { bedtime_minute: 23 * 60, weak_hours: [22], main_apps: ["TikTok"] },
  }));
  assert.ok(rememberedBedtime.actions.some((action) => action.type === "apply_schedule"));
  assert.strictEqual(rememberedBedtime.actions[0].end_minute, 23 * 60);

  const missingApp = await call("I keep doomscrolling.", baseContext());
  assert.strictEqual(missingApp.actions.length, 0);
  assert.match(missingApp.response_text, /where|app|loop/i);

  const rememberedApp = await call("I keep doomscrolling.", baseContext({
    memory: { main_apps: ["Instagram"], weak_hours: [21], last_plan_outcome: "broke" },
  }));
  assert.ok(rememberedApp.actions.length > 0);
  assert.match(rememberedApp.bullets.join(" "), /broke|earlier|usual|9:00 PM/i);

  const explicitWindow = await call("Block Instagram from 10 to 7.", baseContext());
  assert.ok(explicitWindow.actions.some((action) => action.type === "apply_schedule"));
  assert.strictEqual(explicitWindow.actions[0].start_minute, 22 * 60);
  assert.strictEqual(explicitWindow.actions[0].end_minute, 7 * 60);

  const serialized = JSON.stringify([missingBedtime, rememberedBedtime, missingApp, rememberedApp, explicitWindow]);
  assert.doesNotMatch(serialized, /source|model_error|openai|debug|QA/i);

  console.log("blanked-agent smoke tests passed");
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
