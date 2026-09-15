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

async function callRaw(prompt, context = {}) {
  const response = await handler({
    httpMethod: "POST",
    body: JSON.stringify({ prompt, context }),
  });
  assert.strictEqual(response.statusCode, 200, response.body);
  const body = JSON.parse(response.body);
  assert.strictEqual(body.ok, true);
  return body;
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
  assert.match(webSleepAdvice.message_text, /digital wellness|phone|screen|apps|móvil|pantallas/i);
  assert.doesNotMatch(webSleepAdvice.message_text, /caffeine|meal|daylight|training|runs/i);
  assert.doesNotMatch(webSleepAdvice.message_text, /download|App Store|get the app|Free Access/i);

  const webRunningAdvice = await call("How can I run more?", baseContext({
    channel: "web_preview",
    assistant_channel: "web",
    web_preview: true,
  }));
  assert.strictEqual(webRunningAdvice.intent, "general");
  assert.strictEqual(webRunningAdvice.actions.length, 0);
  assert.match(webRunningAdvice.message_text, /digital wellness|phone|screen|apps|móvil|pantallas/i);
  assert.doesNotMatch(webRunningAdvice.message_text, /runs|volume|strength|intervals|hill/i);
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
  assert.match(webPolitics.message_text, /digital wellness|phone|screen|apps|móvil|pantallas|bienestar digital/i);
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

  const appTimeContext = [
    { role: "user", content: "How can I scroll less in the morning?" },
    { role: "assistant", content: "Got it. Before making a block, tell me where the scrolling usually starts: app, moment, or time of day." },
  ];
  const appTimeFollowup = await call("11am Instagram", baseContext({
    channel: "whatsapp",
    assistant_channel: "whatsapp",
    recent_messages: appTimeContext,
    memory: { conversation_state: { recent_messages: appTimeContext } },
  }));
  assert.strictEqual(appTimeFollowup.actions.length, 0);
  assert.match(appTimeFollowup.message_text, /Instagram.*11:00 AM|11:00 AM.*Instagram/i);
  assert.match(appTimeFollowup.message_text, /what time.*end|end.*time/i);
  assert.doesNotMatch(appTimeFollowup.message_text, /25-minute|download|permission|App Store/i);
  const appTimeEndContext = [
    ...appTimeContext,
    { role: "user", content: "11am Instagram" },
    { role: "assistant", content: appTimeFollowup.message_text },
  ];
  const appTimeEndFollowup = await call("12pm", baseContext({
    channel: "whatsapp",
    assistant_channel: "whatsapp",
    recent_messages: appTimeEndContext,
  }));
  assert.strictEqual(appTimeEndFollowup.actions.length, 0);
  assert.match(appTimeEndFollowup.message_text, /Instagram.*11:00 AM.*12:00 PM|11:00 AM.*12:00 PM.*Instagram/i);
  assert.match(appTimeEndFollowup.message_text, /confirm|want me to use/i);
  assert.doesNotMatch(appTimeEndFollowup.message_text, /from 11:00 AM to\.?$|25-minute|download|permission|App Store/i);
  const tenAmContext = [
    ...appTimeContext,
    { role: "user", content: "Instagram at 10am" },
    { role: "assistant", content: "Got it: Instagram is the app and 10:00 AM is when it starts. What time should the protection end?" },
  ];
  const oneHourEndFollowup = await call("1 hour", baseContext({
    channel: "whatsapp",
    assistant_channel: "whatsapp",
    recent_messages: tenAmContext,
  }));
  assert.strictEqual(oneHourEndFollowup.actions.length, 0);
  assert.match(oneHourEndFollowup.message_text, /Instagram.*10:00 AM.*11:00 AM|10:00 AM.*11:00 AM.*Instagram/i);
  assert.doesNotMatch(oneHourEndFollowup.message_text, /\b1:00 AM|\b1:00 PM|\b10:00 PM/i);
  const correctedWindowFollowup = await call("No, from 10 to 11 am", baseContext({
    channel: "whatsapp",
    assistant_channel: "whatsapp",
    recent_messages: [
      ...tenAmContext,
      { role: "user", content: "1 hour" },
      { role: "assistant", content: oneHourEndFollowup.message_text },
    ],
  }));
  assert.strictEqual(correctedWindowFollowup.actions.length, 0);
  assert.match(correctedWindowFollowup.message_text, /Instagram.*10:00 AM.*11:00 AM|10:00 AM.*11:00 AM.*Instagram/i);
  assert.doesNotMatch(correctedWindowFollowup.message_text, /\b10:00 PM|\b1:00 AM/i);
  assert.match(correctedWindowFollowup.message_text, /confirm|want me to use/i);
  const appTimeBareNoon = await call("At 12", baseContext({
    channel: "whatsapp",
    assistant_channel: "whatsapp",
    recent_messages: appTimeEndContext,
  }));
  assert.strictEqual(appTimeBareNoon.actions.length, 0);
  assert.match(appTimeBareNoon.message_text, /11:00 AM.*12:00 PM|12:00 PM.*11:00 AM/i);
  assert.doesNotMatch(appTimeBareNoon.message_text, /12:00 AM/i);
  assert.match(appTimeBareNoon.message_text, /confirm|want me to use/i);
  const appTimeBareNoonConfirmedContext = [
    ...appTimeEndContext,
    { role: "user", content: "At 12" },
    { role: "assistant", content: appTimeBareNoon.message_text },
  ];
  const appTimeBareNoonConfirmed = await call("yes", baseContext({
    channel: "whatsapp",
    assistant_channel: "whatsapp",
    recent_messages: appTimeBareNoonConfirmedContext,
  }));
  assert.deepStrictEqual(appTimeBareNoonConfirmed.actions.map((item) => item.type), ["apply_schedule"]);
  assert.strictEqual(appTimeBareNoonConfirmed.actions[0].end_minute, 12 * 60);
  assert.doesNotMatch(appTimeBareNoonConfirmed.message_text, /apps\.apple\.com|download|create a plan|12:00 AM/i);
  const appTimeInstalledContext = [
    ...appTimeBareNoonConfirmedContext,
    { role: "user", content: "yes" },
    { role: "assistant", content: appTimeBareNoonConfirmed.message_text },
  ];
  const appTimeInstalledContinuation = await call("I have it", baseContext({
    channel: "whatsapp",
    assistant_channel: "whatsapp",
    recent_messages: appTimeInstalledContext,
  }));
  assert.deepStrictEqual(appTimeInstalledContinuation.actions.map((item) => item.type), ["apply_schedule"]);
  assert.match(appTimeInstalledContinuation.message_text, /plan.*ready|prepared|review/i);
  assert.doesNotMatch(appTimeInstalledContinuation.message_text, /apps\.apple\.com|download|create a plan/i);
  const appTimeConfirmedContext = [
    ...appTimeEndContext,
    { role: "user", content: "12pm" },
    { role: "assistant", content: appTimeEndFollowup.message_text },
  ];
  const appTimeConfirmed = await call("yes", baseContext({
    channel: "whatsapp",
    assistant_channel: "whatsapp",
    app_presence: {
      app_present: true,
      app_ready: true,
      last_seen_at: new Date().toISOString(),
    },
    recent_messages: appTimeConfirmedContext,
  }));
  assert.deepStrictEqual(appTimeConfirmed.actions.map((item) => item.type), ["apply_schedule"]);
  assert.strictEqual(appTimeConfirmed.actions[0].start_minute, 11 * 60);
  assert.strictEqual(appTimeConfirmed.actions[0].end_minute, 12 * 60);
  assert.doesNotMatch(appTimeConfirmed.message_text, /25-minute|daily limit|already (set|blocked)|download|App Store/i);

  const appTimeModelQuestionContext = [
    { role: "user", content: "How can I scroll less in the morning?" },
    { role: "assistant", content: "Got it. Which app pulls you in most, and when does it usually happen?" },
  ];
  const appTimeModelQuestion = await call("11am Instagram", baseContext({
    channel: "whatsapp",
    assistant_channel: "whatsapp",
    recent_messages: appTimeModelQuestionContext,
  }));
  assert.strictEqual(appTimeModelQuestion.actions.length, 0);
  assert.match(appTimeModelQuestion.message_text, /Instagram.*11:00 AM|11:00 AM.*Instagram/i);
  assert.match(appTimeModelQuestion.message_text, /what time.*end|end.*time/i);
  assert.doesNotMatch(appTimeModelQuestion.message_text, /25-minute|daily limit|download|permission|App Store/i);

  const breakfastWithoutTime = await call("I usually use social media after breakfast", baseContext({
    channel: "whatsapp",
    assistant_channel: "whatsapp",
  }));
  assert.strictEqual(breakfastWithoutTime.actions.length, 0);
  assert.match(breakfastWithoutTime.message_text, /finish breakfast/i);
  assert.strictEqual(breakfastWithoutTime.message_text, breakfastWithoutTime.response_text);
  assert.doesNotMatch(`${breakfastWithoutTime.message_text} ${breakfastWithoutTime.response_text}`, /Social mode|30 minutes|Start Social/i);

  const breakfastWithRememberedApp = await call("I usually use social media after breakfast", baseContext({
    memory: { main_apps: ["Instagram"] },
  }));
  assert.strictEqual(breakfastWithRememberedApp.actions.length, 0);
  assert.match(breakfastWithRememberedApp.message_text, /finish breakfast/i);
  assert.strictEqual(breakfastWithRememberedApp.message_text, breakfastWithRememberedApp.response_text);

  const breakfastWithTime = await call("I usually use social media after breakfast", baseContext({
    memory: { breakfast_end_minute: 8 * 60 },
  }));
  assert.strictEqual(breakfastWithTime.actions.length, 0);
  assert.strictEqual(breakfastWithTime.blocking_user_request, false);

  const rememberedApp = await call("I keep doomscrolling.", baseContext({
    memory: { main_apps: ["Instagram"], weak_hours: [21], last_plan_outcome: "broke" },
  }));
  assert.strictEqual(rememberedApp.actions.length, 1);
  assert.strictEqual(rememberedApp.actions[0].type, "apply_schedule");
  assert.strictEqual(rememberedApp.actions[0].start_minute, 21 * 60);
  assert.strictEqual(rememberedApp.actions[0].end_minute, 22 * 60);
  assert.strictEqual(rememberedApp.blocking_user_request, false);
  assert.match(rememberedApp.bullets.join(" "), /broke|earlier|usual|9:00 PM/i);
  assert.doesNotMatch(`${rememberedApp.message_text} ${rememberedApp.bullets.join(" ")}`, /25-minute|daily limit/i);

  const explicitWindow = await call("Block selected apps from 10 pm to 7 am every day.", baseContext());
  assert.ok(explicitWindow.actions.some((action) => action.type === "apply_schedule"));
  assert.strictEqual(explicitWindow.actions[0].start_minute, 22 * 60);
  assert.strictEqual(explicitWindow.actions[0].end_minute, 7 * 60);
  assert.match(explicitWindow.message_text, /Protect selected apps from 10:00 PM to 7:00 AM/i);
  assert.doesNotMatch(explicitWindow.message_text, /I can help|apply it in Blanked|Read:|Pattern:|Move:/i);

  const immediateBlock = await call("I want to block Instagram now.", baseContext());
  assert.strictEqual(immediateBlock.actions.length, 0);
  assert.deepStrictEqual(immediateBlock.blocking_missing_fields, ["end"]);
  assert.match(immediateBlock.message_text, /How long|cu[aá]nto tiempo/i);

  const completeImmediate = await call("Block TikTok indefinitely now.", baseContext());
  assert.strictEqual(completeImmediate.blocking_ready, true);
  assert.strictEqual(completeImmediate.actions[0].type, "open_app_picker");
  assert.strictEqual(completeImmediate.actions[0].name, "Immediate Protection");

  const savedInstagramMode = await call(
    "Block Instagram indefinitely now.",
    baseContext({
      available_modes: ["Instagram solo"],
      available_mode_catalog: [{ name: "Instagram solo", app_names: ["Instagram"], selection_count: 1 }],
    })
  );
  assert.strictEqual(savedInstagramMode.actions[0].type, "activate_mode");
  assert.strictEqual(savedInstagramMode.actions[0].name, "Instagram solo");
  assert.strictEqual(savedInstagramMode.requires_selected_apps, false);

  const savedInstagramScheduledMode = await call(
    "Block Instagram for 1 hour at 7 pm every day.",
    baseContext({
      available_modes: ["Instagram solo"],
      available_mode_catalog: [{ name: "Instagram solo", app_names: ["Instagram"], selection_count: 1 }],
    })
  );
  assert.strictEqual(savedInstagramScheduledMode.actions[0].type, "apply_schedule");
  assert.strictEqual(savedInstagramScheduledMode.actions[0].name, "Instagram solo");
  assert.strictEqual(savedInstagramScheduledMode.requires_selected_apps, false);

  const savedInstagramFollowupMode = await call(
    "3 mins",
    baseContext({
      available_modes: ["Instagram solo"],
      available_mode_catalog: [{ name: "Instagram solo", app_names: ["Instagram"], selection_count: 1 }],
      pending_blocking: {
        apps: ["Instagram"],
        start: { type: "now", value: "now" },
        recurrence: { type: "once", value: [0] },
      },
    })
  );
  assert.strictEqual(savedInstagramFollowupMode.actions[0].type, "activate_mode");
  assert.strictEqual(savedInstagramFollowupMode.actions[0].name, "Instagram solo");
  assert.strictEqual(savedInstagramFollowupMode.requires_selected_apps, false);

  const selectedImmediate = await call("Block selected apps for 45 minutes now.", baseContext());
  assert.strictEqual(selectedImmediate.actions[0].type, "start_protection");
  assert.strictEqual(selectedImmediate.actions[0].minutes, 45);

  const scheduledDuration = await call("Block Instagram for 1 hour at 7 pm every day.", baseContext());
  assert.strictEqual(scheduledDuration.actions[0].type, "open_app_picker");
  assert.strictEqual(scheduledDuration.actions[0].start_minute, 19 * 60);
  assert.strictEqual(scheduledDuration.actions[0].end_minute, 20 * 60);

  const completedFollowup = await call("45 minutes", baseContext({
    pending_blocking: {
      apps: ["Instagram"],
      start: { type: "now", value: "now" },
      recurrence: { type: "once", value: [0] },
    },
  }));
  assert.strictEqual(completedFollowup.blocking_ready, true);
  assert.strictEqual(completedFollowup.actions[0].type, "open_app_picker");
  assert.strictEqual(completedFollowup.actions[0].minutes, 45);

  const claimedSelectionImmediate = await call(
    "I have already selected the app. Now block it.",
    baseContext({ has_selected_apps: false, selection_count: 0 })
  );
  assert.strictEqual(claimedSelectionImmediate.actions.length, 0);
  assert.ok(claimedSelectionImmediate.blocking_missing_fields.includes("apps"));
  assert.match(claimedSelectionImmediate.message_text, /Which apps|qu[eé] aplicaciones/i);

  const explicitDailyLimit = await call("Set a 25-minute daily limit for Instagram.", baseContext());
  assert.ok(explicitDailyLimit.actions.some((action) => action.type === "open_app_picker"));
  assert.strictEqual(explicitDailyLimit.blocking_ready, true);

  const dailyLimitNeedsAmount = await call("Set a daily limit for Instagram.", baseContext());
  assert.strictEqual(dailyLimitNeedsAmount.actions.length, 0);
  assert.match(dailyLimitNeedsAmount.message_text, /how many minutes|cu[aá]ntos minutos/i);
  assert.doesNotMatch(dailyLimitNeedsAmount.message_text, /25-minute|25 minutos/i);

  const appSpanishLocale = await call("Block selected apps from 10 pm to 7 am every day.", baseContext({ locale: "es-ES", channel: "app" }));
  assert.match(appSpanishLocale.message_text, /Protect selected apps/i);
  assert.doesNotMatch(appSpanishLocale.message_text, /Protegería|bloqueo|franja/i);

  const whatsappSpanish = await call("Bloquea Instagram de 10 de la noche a 7 de la mañana cada día.", baseContext({ channel: "whatsapp" }));
  assert.match(whatsappSpanish.message_text, /Puedo bloquear|Instagram/i);

  const sleepGoalWindow = await call("I want to sleep good from 11pm to 7am", baseContext());
  assert.strictEqual(sleepGoalWindow.actions.length, 1);
  assert.strictEqual(sleepGoalWindow.actions[0].type, "apply_schedule");
  assert.strictEqual(sleepGoalWindow.actions[0].start_minute, 22 * 60 + 45);
  assert.strictEqual(sleepGoalWindow.actions[0].end_minute, 23 * 60);
  assert.strictEqual(sleepGoalWindow.blocking_user_request, false);

  const rawContract = await callRaw("Block selected apps from 10 pm to 7 am every day.", baseContext());
  assert.match(rawContract.harness.run_id, /^bm_/);
  assert.strictEqual(rawContract.harness.harness_version, "bm-harness-v2");
  assert.strictEqual(rawContract.harness.status, "completed");
  assert.strictEqual(rawContract.loop.loop_version, "bm-loop-excellence-v1");
  assert.strictEqual(rawContract.loop.schema_version, 1);
  assert.ok(rawContract.loop.action_types.includes("apply_schedule"));
  assert.doesNotMatch(JSON.stringify(rawContract.harness), /Block selected apps from 10 pm to 7 am every day/i);

  const serialized = JSON.stringify([missingBedtime, rememberedBedtime, missingApp, rememberedApp, explicitWindow, sleepGoalWindow]);
  assert.doesNotMatch(serialized, /source|model_error|openai|debug|QA/i);

  console.log("blanked-agent smoke tests passed");
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
