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
  const smallTalk = await call("how you doing?", baseContext({ channel: "whatsapp", assistant_channel: "whatsapp" }));
  assert.strictEqual(smallTalk.intent, "general");
  assert.strictEqual(smallTalk.actions.length, 0);
  assert.ok(smallTalk.message_text.length >= 8);
  assert.doesNotMatch(smallTalk.message_text, /Blanked|app|block|plan|screen-habit|diagnosis|protection|Open/i);

  const goodMorning = await call("Good morning", baseContext({ channel: "whatsapp", assistant_channel: "whatsapp" }));
  assert.strictEqual(goodMorning.intent, "general");
  assert.strictEqual(goodMorning.actions.length, 0);
  assert.ok(goodMorning.message_text.length >= 8);
  assert.doesNotMatch(goodMorning.message_text, /Blanked|app|block|plan|screen-habit|diagnosis|protection|Open/i);

  const thanks = await call("thanks", baseContext({ channel: "sms", assistant_channel: "sms" }));
  assert.strictEqual(thanks.intent, "general");
  assert.strictEqual(thanks.actions.length, 0);
  assert.doesNotMatch(thanks.message_text, /Blanked|app|block|plan|screen-habit|diagnosis|protection|Open/i);

  const webPrediction = await call("How can you know that tomorrow I will be more tired than today?", baseContext({
    channel: "web_preview",
    assistant_channel: "web",
    web_preview: true,
  }));
  assert.strictEqual(webPrediction.intent, "general");
  assert.strictEqual(webPrediction.actions.length, 0);
  assert.match(webPrediction.message_text, /sleep|recovery|Screen Time|baseline|probabilistic/i);
  assert.doesNotMatch(webPrediction.message_text, /download|App Store|get the app|Free Access/i);

  const webSleepAdvice = await call("How can I sleep better?", baseContext({
    channel: "web_preview",
    assistant_channel: "web",
    web_preview: true,
  }));
  assert.strictEqual(webSleepAdvice.intent, "general");
  assert.strictEqual(webSleepAdvice.actions.length, 0);
  assert.match(webSleepAdvice.message_text, /wake|daylight|caffeine|meal|lights|screen|bed/i);
  assert.doesNotMatch(webSleepAdvice.message_text, /download|App Store|get the app|Free Access/i);

  const webRunningAdvice = await call("How can I run more?", baseContext({
    channel: "web_preview",
    assistant_channel: "web",
    web_preview: true,
  }));
  assert.strictEqual(webRunningAdvice.intent, "general");
  assert.strictEqual(webRunningAdvice.actions.length, 0);
  assert.match(webRunningAdvice.message_text, /runs|volume|strength|recovery|intervals|hill/i);
  assert.doesNotMatch(webRunningAdvice.message_text, /download|App Store|get the app|Free Access|block apps|blocking apps/i);

  const webProductivity = await call("I want to boost productivity", baseContext({
    channel: "web_preview",
    assistant_channel: "web",
    web_preview: true,
  }));
  assert.strictEqual(webProductivity.intent, "general");
  assert.strictEqual(webProductivity.actions.length, 0);
  assert.match(webProductivity.message_text, /priority|25-50|notifications|block social|scroll apps/i);
  assert.doesNotMatch(webProductivity.message_text, /—|–|download|App Store|get the app|Free Access/i);

  const webPolitics = await call("israel or palestina?", baseContext({
    channel: "web_preview",
    assistant_channel: "web",
    web_preview: true,
  }));
  assert.strictEqual(webPolitics.intent, "general");
  assert.strictEqual(webPolitics.actions.length, 0);
  assert.match(webPolitics.message_text, /wellness|habits|sleep|energy|focus|bienestar|hábitos|habitos/i);
  assert.doesNotMatch(webPolitics.message_text, /history|politic|conflict|identity|affected|israel|palestin/i);

  const missingBedtime = await call("How can I not scroll at night?", baseContext());
  assert.strictEqual(missingBedtime.actions.length, 0);
  assert.match(missingBedtime.response_text, /bed|asleep|phone/i);

  const rememberedBedtime = await call("How can I not scroll at night?", baseContext({
    memory: { bedtime_minute: 23 * 60, weak_hours: [22], main_apps: ["TikTok"] },
  }));
  assert.strictEqual(rememberedBedtime.actions.length, 0);
  assert.match(rememberedBedtime.message_text, /11:00 PM|bed|boundary|asleep/i);

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
  assert.match(explicitWindow.message_text, /protect Instagram from 10:00 PM to 7:00 AM/i);
  assert.doesNotMatch(explicitWindow.message_text, /I can help|apply it in Blanked|Read:|Pattern:|Move:/i);

  const appSpanishLocale = await call("Block Instagram from 10 to 7.", baseContext({ locale: "es-ES", channel: "app" }));
  assert.match(appSpanishLocale.message_text, /protect Instagram/i);
  assert.doesNotMatch(appSpanishLocale.message_text, /Protegería|bloqueo|franja/i);

  const whatsappSpanish = await call("Bloquea Instagram de 10 a 7.", baseContext({ channel: "whatsapp" }));
  assert.match(whatsappSpanish.message_text, /Protegería|bloquearía|Instagram/i);

  const sleepGoalWindow = await call("I want to sleep good from 11pm to 7am", baseContext());
  assert.ok(sleepGoalWindow.actions.some((action) => action.type === "apply_schedule"));
  assert.strictEqual(sleepGoalWindow.actions[0].start_minute, 22 * 60 + 45);
  assert.strictEqual(sleepGoalWindow.actions[0].end_minute, 23 * 60);
  assert.match(sleepGoalWindow.message_text, /before 11:00 PM|10:45 PM|last 15/i);

  const serialized = JSON.stringify([missingBedtime, rememberedBedtime, missingApp, rememberedApp, explicitWindow, sleepGoalWindow]);
  assert.doesNotMatch(serialized, /source|model_error|openai|debug|QA/i);

  console.log("blanked-agent smoke tests passed");
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
