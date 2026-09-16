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

  // These are integration assertions against independently specified facts. The
  // original smoke asserted guessed windows, automatic confirmation, seven-day
  // expiration and executable picker payloads. Those expectations were unsafe.
  function fact(plan, key) { return plan.semantic_state?.slots[key]?.value ?? null; }
  function noAction(plan) { assert.deepStrictEqual(plan.actions, []); }
  function question(plan, slot) { assert.deepStrictEqual(plan.semantic_decision, { type: "ask", slot }); }
  async function follow(prompt, previous, context = baseContext({channel:"app"})) {
    return call(prompt, {...context, semantic_state:previous.semantic_state});
  }

  const missingBedtime = await call("How can I not scroll at night?", baseContext());
  noAction(missingBedtime); question(missingBedtime,"start");
  assert.strictEqual(missingBedtime.semantic_state.intent,"advice");
  assert.strictEqual(fact(missingBedtime,"start"),null);
  assert.strictEqual(fact(missingBedtime,"duration_minutes"),null);
  const rememberedBedtime = await call("How can I not scroll at night?", baseContext({
    memory:{bedtime_minute:23*60,weak_hours:[22],main_apps:["TikTok"]},
  }));
  noAction(rememberedBedtime); question(rememberedBedtime,"start");
  assert.strictEqual(fact(rememberedBedtime,"apps"),null);

  const missingApp = await call("I keep doomscrolling.", baseContext());
  noAction(missingApp);
  assert.match(missingApp.response_text,/where|app|loop/i);
  const appTimeContext = [
    {role:"user",content:"How can I scroll less in the morning?"},
    {role:"assistant",content:"Which app pulls you in most, and when does it usually happen?"},
  ];
  const appTimeFollowup = await call("11am Instagram", baseContext({channel:"whatsapp",recent_messages:appTimeContext}));
  noAction(appTimeFollowup); question(appTimeFollowup,"end_or_duration");
  assert.deepStrictEqual(fact(appTimeFollowup,"apps"),["Instagram"]);
  assert.deepStrictEqual(fact(appTimeFollowup,"start"),{type:"time",minute:660});
  assert.match(appTimeFollowup.message_text,/Instagram/);
  assert.match(appTimeFollowup.message_text,/11:00 AM|11 AM|11am/i);
  assert.strictEqual(fact(appTimeFollowup,"action_type"),null);
  const appTimeEndFollowup = await follow("12pm",appTimeFollowup);
  noAction(appTimeEndFollowup); question(appTimeEndFollowup,"recurrence");
  assert.strictEqual(fact(appTimeEndFollowup,"end"),720);
  assert.strictEqual(fact(appTimeEndFollowup,"duration_minutes"),60);
  const ambiguousEnd = await follow("At 12",appTimeFollowup);
  noAction(ambiguousEnd); question(ambiguousEnd,"end");
  assert.strictEqual(fact(ambiguousEnd,"end"),null);
  assert.strictEqual(fact(ambiguousEnd,"confirmation"),null);
  noAction(await follow("yes",ambiguousEnd));
  noAction(await follow("I have it",ambiguousEnd));

  const tenAm = await call("Instagram at 10am",baseContext({recent_messages:appTimeContext}));
  const oneHour = await follow("1 hour",tenAm);
  noAction(oneHour); question(oneHour,"recurrence");
  assert.deepStrictEqual(fact(oneHour,"start"),{type:"time",minute:600});
  assert.strictEqual(fact(oneHour,"end"),660);
  assert.strictEqual(fact(oneHour,"duration_minutes"),60);
  const corrected = await follow("No, from 10 to 11 am",oneHour);
  noAction(corrected); question(corrected,"recurrence");
  assert.deepStrictEqual(fact(corrected,"start"),{type:"time",minute:600});
  assert.strictEqual(fact(corrected,"end"),660);
  const recurringAdvice = await follow("every day for 9 days",corrected);
  noAction(recurringAdvice); question(recurringAdvice,"action_type");
  const proposed = await follow("yes",recurringAdvice);
  noAction(proposed);
  assert.strictEqual(proposed.semantic_decision.type,"confirm");
  const scheduled = await follow("yes",proposed,baseContext({channel:"app",selected_app_names:["Instagram"]}));
  assert.deepStrictEqual(scheduled.actions.map(a=>a.type),["apply_schedule"]);
  assert.strictEqual(scheduled.actions[0].start_minute,600);
  assert.strictEqual(scheduled.actions[0].end_minute,660);
  assert.strictEqual(scheduled.actions[0].duration_days,9);
  assert.deepStrictEqual(scheduled.actions[0].weekdays,[1,2,3,4,5,6,7]);
  assert.match(scheduled.message_text,/10:00 to 11:00.*9 days/);

  const breakfastWithoutTime = await call("I usually use social media after breakfast",baseContext({channel:"whatsapp"}));
  noAction(breakfastWithoutTime);
  assert.match(breakfastWithoutTime.message_text,/finish breakfast/i);
  assert.strictEqual(breakfastWithoutTime.message_text,breakfastWithoutTime.response_text);
  assert.doesNotMatch(breakfastWithoutTime.message_text,/Social mode|30 minutes|Start Social/i);
  const breakfastWithRememberedApp = await call("I usually use social media after breakfast",baseContext({memory:{main_apps:["Instagram"]}}));
  noAction(breakfastWithRememberedApp);
  assert.match(breakfastWithRememberedApp.message_text,/finish breakfast/i);
  const breakfastWithTime = await call("I usually use social media after breakfast",baseContext({memory:{breakfast_end_minute:480}}));
  noAction(breakfastWithTime);
  const rememberedApp = await call("I keep doomscrolling.",baseContext({memory:{main_apps:["Instagram"],weak_hours:[21],last_plan_outcome:"broke"}}));
  noAction(rememberedApp); // Habit evidence alone does not authorize a 21:00-22:00 rule.
  assert.notStrictEqual(rememberedApp.semantic_state.intent,"block");

  const explicitWindow = await call("Block selected apps from 10 pm to 7 am every day.",baseContext({channel:"app"}));
  noAction(explicitWindow); question(explicitWindow,"schedule_horizon_days");
  assert.deepStrictEqual(fact(explicitWindow,"start"),{type:"time",minute:1320});
  assert.strictEqual(fact(explicitWindow,"end"),420);
  const immediateBlock = await call("I want to block Instagram now.",baseContext());
  noAction(immediateBlock);
  assert.deepStrictEqual(immediateBlock.semantic_state.pending_slots,["end_or_duration","recurrence"]);
  const unbounded = await call("Block TikTok indefinitely now.",baseContext());
  noAction(unbounded);
  assert.ok(unbounded.semantic_state.errors.some(e=>e.code==="unbounded_duration"));
  assert.strictEqual(fact(unbounded,"duration_minutes"),null);

  const modeContext = baseContext({channel:"app",available_modes:["Instagram solo"],available_mode_catalog:[{name:"Instagram solo",app_names:["Instagram"],selection_count:1}]});
  const modeProposal = await call("Block Instagram now for 45 minutes once",modeContext);
  noAction(modeProposal);
  const savedMode = await follow("yes",modeProposal,modeContext);
  assert.deepStrictEqual(savedMode.actions.map(a=>a.type),["activate_mode"]);
  assert.strictEqual(savedMode.actions[0].name,"Instagram solo");
  assert.strictEqual(savedMode.actions[0].minutes,45);
  const selectedImmediate = await call("Block selected apps for 45 minutes now.",baseContext({channel:"app"}));
  noAction(selectedImmediate); question(selectedImmediate,"recurrence");
  const selectedOnce = await follow("just once",selectedImmediate);
  noAction(selectedOnce);
  const selectedConfirmed = await follow("yes",selectedOnce);
  assert.strictEqual(selectedConfirmed.actions[0].type,"start_protection");
  assert.strictEqual(selectedConfirmed.actions[0].minutes,45);

  const pickerProposal = await call("Block Instagram from 7pm for one hour every day for 7 days",baseContext({channel:"app"}));
  noAction(pickerProposal);
  const picker = await follow("yes",pickerProposal);
  assert.deepStrictEqual(picker.actions.map(a=>a.type),["open_app_picker"]);
  assert.strictEqual(picker.actions[0].minutes,null);
  assert.strictEqual(picker.actions[0].start_minute,1140);
  assert.strictEqual(picker.actions[0].end_minute,1200);
  assert.deepStrictEqual(picker.actions[0].weekdays,[1,2,3,4,5,6,7]);
  assert.strictEqual(picker.actions[0].duration_days,7);
  const claimedSelection = await call("I have already selected the app. Now block it.",baseContext({has_selected_apps:false,selection_count:0}));
  noAction(claimedSelection); question(claimedSelection,"apps");
  assert.strictEqual(fact(claimedSelection,"apps"),null);
  const orphanLegacyPending = await call("45 minutes",baseContext({pending_blocking:{apps:["Instagram"],start:{type:"now",value:"now"},recurrence:{type:"once",value:[0]}}}));
  noAction(orphanLegacyPending);
  assert.strictEqual(fact(orphanLegacyPending,"confirmation"),null);
  assert.strictEqual(orphanLegacyPending.semantic_decision.slot,orphanLegacyPending.semantic_state.next_question);
  if (orphanLegacyPending.semantic_state.intent === "general") {
    assert.deepStrictEqual(orphanLegacyPending.semantic_state.pending_slots,[]);
    assert.deepStrictEqual(orphanLegacyPending.semantic_decision,{type:"none",slot:null});
    assert.deepStrictEqual(orphanLegacyPending.blocking_missing_fields,[]);
  }

  const dailyLimit = await call("Set a 25-minute daily limit for Instagram.",baseContext({channel:"app"}));
  noAction(dailyLimit); assert.deepStrictEqual(dailyLimit.semantic_decision,{type:"confirm",slot:"confirmation"});
  assert.deepStrictEqual(fact(dailyLimit,"start"),{type:"now"});
  assert.strictEqual(fact(dailyLimit,"duration_minutes"),25);
  assert.strictEqual(fact(dailyLimit,"action_type"),"daily_limit");
  const dailyLimitConfirmed = await follow("yes",dailyLimit,baseContext({channel:"app",selected_app_names:["Instagram"]}));
  assert.strictEqual(dailyLimitConfirmed.actions[0].type,"set_daily_limit");
  assert.strictEqual(dailyLimitConfirmed.actions[0].minutes,25);
  const dailyLimitNeedsAmount = await call("Set a daily limit for Instagram.",baseContext());
  noAction(dailyLimitNeedsAmount);
  assert.strictEqual(fact(dailyLimitNeedsAmount,"duration_minutes"),null);
  assert.ok(dailyLimitNeedsAmount.semantic_state.pending_slots.includes("end_or_duration"));

  const appSpanishLocale = await call("Block selected apps from 10 pm to 7 am every day.",baseContext({locale:"es-ES",channel:"app"}));
  assert.strictEqual(appSpanishLocale.semantic_state.language,"en");
  noAction(appSpanishLocale);
  const whatsappSpanish = await call("Bloquea Instagram de 10 de la noche a 7 de la mañana cada día.",baseContext({channel:"whatsapp"}));
  assert.strictEqual(whatsappSpanish.semantic_state.language,"es");
  assert.deepStrictEqual(fact(whatsappSpanish,"start"),{type:"time",minute:1320});
  assert.strictEqual(fact(whatsappSpanish,"end"),420);
  noAction(whatsappSpanish);
  const sleepGoalWindow = await call("I want to sleep good from 11pm to 7am",baseContext());
  noAction(sleepGoalWindow); // A sleep goal is not authorization for a guessed 22:45 block.
  assert.notStrictEqual(sleepGoalWindow.semantic_state.intent,"block");

  const rawContract = await callRaw("Block selected apps from 10 pm to 7 am every day.",baseContext());
  assert.match(rawContract.harness.run_id,/^bm_/);
  assert.strictEqual(rawContract.harness.harness_version,"bm-harness-v2");
  assert.strictEqual(rawContract.harness.status,"completed");
  assert.strictEqual(rawContract.loop.loop_version,"bm-loop-excellence-v1");
  assert.strictEqual(rawContract.loop.schema_version,1);
  assert.deepStrictEqual(rawContract.loop.action_types,[]);
  assert.doesNotMatch(JSON.stringify(rawContract.harness),/Block selected apps from 10 pm to 7 am every day/i);
  // Source provenance is required in state, but internal metadata is not prose.
  const visible = JSON.stringify([missingBedtime,rememberedBedtime,missingApp,rememberedApp,explicitWindow,sleepGoalWindow].map(p=>({text:p.message_text,bullets:p.bullets})));
  assert.doesNotMatch(visible,/model_error|openai|debug|QA/i);
  console.log("blanked-agent smoke tests passed (canonical semantic contract)");
})().catch(error=>{ console.error(error); process.exit(1); });
