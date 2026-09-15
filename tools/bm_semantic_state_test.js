"use strict";

const assert = require("node:assert/strict");
const { advanceSemanticState, normalizeSemanticState, buildSemanticActions, extractSemanticPatch, validateSemanticPatch, TTL_MS } = require("../netlify/functions/bm-semantic-state");
const NOW = Date.parse("2026-09-15T10:00:00Z");
const DEVICE = { channel:"ios", screen_time_authorized:true, has_selected_apps:true, selected_app_names:["Instagram"] };
let checks = 0;
function test(name, fn) { try { fn(); checks++; } catch (error) { error.message = `${name}: ${error.message}`; throw error; } }
function turn(prompt, previousState, context = DEVICE, language = "en") { return advanceSemanticState({ prompt, previousState, context, language, now:NOW }); }
function chat(prompts, context = DEVICE, language = "en") { let state; return prompts.map(p => { const result = turn(p,state,context,language); state = result.state; return result; }); }
function slot(result,name) { return result.state.slots[name]?.value ?? null; }
function none(result) { assert.deepEqual(result.actions,[]); }
function equalSlot(result,name,expected) { assert.deepEqual(slot(result,name),expected); }

test("no invented duration or recurrence", () => {
  const r = turn("Block Instagram now");
  assert.deepEqual(r.state.pending_slots,["end_or_duration","recurrence"]);
  equalSlot(r,"duration_minutes",null); equalSlot(r,"recurrence",null); none(r);
});
test("data then exact proposal confirmation", () => {
  const [a,b,c] = chat(["Block Instagram now for 30 minutes", "Just once", "Yes"]);
  assert.deepEqual(a.state.pending_slots,["recurrence"]); none(a);
  assert.equal(b.state.status,"awaiting_confirmation"); none(b);
  assert.deepEqual(c.actions,[{type:"start_protection",minutes:30,hard_mode:false}]);
  assert.equal(c.state.slots.confirmation.source.text,"Yes");
});
test("a yes while a field is missing never authorizes later proposal", () => {
  const results = chat(["Block Instagram now for 30 minutes","yes","once"]);
  results.forEach(none); assert.equal(results[2].state.status,"awaiting_confirmation");
});
test("duration correction invalidates confirmed proposal", () => {
  const results = chat(["Block Instagram now for 30 minutes once","yes","Actually 45 minutes"]);
  const corrected = results[2]; equalSlot(corrected,"duration_minutes",45); equalSlot(corrected,"confirmation",null); none(corrected);
  assert.ok(corrected.state.corrections.some(c => c.slot === "duration_minutes" && c.previous === 30 && c.replacement === 45));
});
test("minutes are duration and never an hour of day", () => {
  const results = chat(["Block Instagram at 10am every day for 7 days", "one hour", "No, 45 minutes", "yes"]);
  const r = results[3]; equalSlot(r,"start",{type:"time",minute:600}); equalSlot(r,"end",645);
  assert.equal(r.actions[0].start_minute,600); assert.equal(r.actions[0].end_minute,645);
  assert.equal(r.state.slots.end.source.kind,"derived"); assert.deepEqual(r.state.slots.end.source.depends_on,["start","duration_minutes"]);
  assert.match(r.responseText,/10:00 to 10:45/);
});
test("end correction replaces duration and recalculates", () => {
  const results = chat(["Block Instagram at 10am for one hour every day", "Until 12pm"]);
  equalSlot(results[1],"end",720); equalSlot(results[1],"duration_minutes",120);
  assert.equal(results[1].state.slots.duration_minutes.source.kind,"derived");
});
test("start correction recalculates dependent end only", () => {
  const results = chat(["Block Instagram at 10am for one hour every day", "Actually start at 11am"]);
  equalSlot(results[1],"start",{type:"time",minute:660}); equalSlot(results[1],"end",720);
});
test("start correction preserves explicitly supplied end", () => {
  const results = chat(["Block Instagram from 10am to 12pm every day", "Actually start at 11am"]);
  equalSlot(results[1],"end",720); equalSlot(results[1],"duration_minutes",60);
});
test("same-turn inconsistent duration and end cannot act", () => {
  const results = chat(["Block Instagram from 10am to 11am for 90 minutes every day", "yes"]);
  results.forEach(none); assert.ok(results[1].state.errors.some(e => e.code === "time_duration_conflict"));
});
test("end correction resolves time conflict", () => {
  const results = chat(["Block Instagram from 10am to 11am for 90 minutes every day", "Until 11am"]);
  assert.equal(results[1].state.errors.length,0); equalSlot(results[1],"duration_minutes",60);
});
test("app correction replaces instead of concatenating history", () => {
  const results = chat(["Block Instagram now for 30 minutes once", "Not Instagram, TikTok"], {...DEVICE,selected_app_names:["TikTok"]});
  equalSlot(results[1],"apps",["TikTok"]); none(results[1]);
});
test("instead-of removes the rejected alternative", () => {
  const results = chat(["Block Instagram now for 30 minutes once", "TikTok instead of Instagram"], {...DEVICE,selected_app_names:["TikTok"]});
  equalSlot(results[1],"apps",["TikTok"]);
});
test("explicit app addition preserves earlier selection", () => {
  const results = chat(["Block Instagram now for 30 minutes once", "Add TikTok too"]);
  equalSlot(results[1],"apps",["Instagram","TikTok"]);
});
test("exclusion removes an app without adding it back", () => {
  const results = chat(["Block Instagram and TikTok now for 30 minutes once", "Remove TikTok"]);
  equalSlot(results[1],"apps",["Instagram"]);
});
test("nested app aliases cannot invent extra YouTube target", () => {
  const r = turn("Block YouTube Shorts now for 30 minutes once"); equalSlot(r,"apps",["YouTube Shorts"]);
});
test("category never expands to invented apps", () => {
  const r = turn("Block social media now for 30 minutes once"); equalSlot(r,"app_category","social_apps"); equalSlot(r,"apps",null); none(r);
});
test("preselected apps never silently replace requested named apps", () => {
  const results = chat(["Block TikTok now for 30 minutes once","yes"]);
  assert.equal(results[1].decision.slot,"app_selection"); assert.deepEqual(results[1].actions,[{type:"open_app_picker"}]);
});
test("explicit selected-apps reference can use known selection", () => {
  const results = chat(["Block my selected apps now for 30 minutes once","yes"], {...DEVICE,selected_app_names:undefined});
  assert.equal(results[1].actions[0].type,"start_protection");
});
test("verified exact saved mode uses only that mode", () => {
  const results = chat(["Block TikTok now for 30 minutes once","yes"], {...DEVICE,available_mode_catalog:[{name:"TikTok only",app_names:["TikTok"]}]});
  assert.deepEqual(results[1].actions,[{type:"activate_mode",name:"TikTok only",minutes:30,hard_mode:false}]);
});
test("bare ambiguous times ask AM/PM", () => {
  const r = turn("Block Instagram from 10 to 7 every day"); equalSlot(r,"start",null); equalSlot(r,"end",null); none(r);
  assert.ok(r.state.errors.some(e => e.code === "ambiguous_start"));
});
test("grammatically shared meridiem in range", () => {
  const r = turn("Block Instagram from 10 to 11 am every day"); equalSlot(r,"start",{type:"time",minute:600}); equalSlot(r,"end",660); none(r);
});
test("overnight explicit clocks stay exact", () => {
  const r = turn("Block Instagram from 10pm to 7am every day"); equalSlot(r,"start",{type:"time",minute:1320}); equalSlot(r,"end",420); equalSlot(r,"duration_minutes",540);
});
test("24-hour notation preserves midnight", () => {
  const r = turn("Block Instagram from 23:30 to 00:15 every day"); equalSlot(r,"start",{type:"time",minute:1410}); equalSlot(r,"end",15); equalSlot(r,"duration_minutes",45);
});
test("invalid clock never normalizes modulo 24", () => {
  const r = turn("Block Instagram from 25:30 to 27:15 every day"); equalSlot(r,"start",null); equalSlot(r,"end",null); none(r);
});
test("relative events do not invent 60 minutes or daily recurrence", () => {
  const results = chat(["Block Instagram after breakfast","at 10am"]);
  equalSlot(results[1],"duration_minutes",null); equalSlot(results[1],"recurrence",null); none(results[1]);
});
test("no implicit tomorrow datetime conversion", () => {
  const r = turn("Block Instagram tomorrow from 10am to 11am");
  assert.equal(r.decision.slot,"calendar_date"); none(r);
});
test("one-off schedule capability limit stays explicit", () => {
  const results = chat(["Block Instagram from 10am to 11am once","yes"]); results.forEach(none); assert.equal(results[1].decision.slot,"calendar_date");
});
test("a named date/day is not an inferred weekly recurrence", () => {
  const r = turn("Block Instagram on Monday from 10am to 11am"); equalSlot(r,"recurrence",null); none(r);
});
test("recurrence correction supersedes daily value", () => {
  const results = chat(["Block Instagram from 10am to 11am every day", "No, weekdays only"]);
  equalSlot(results[1],"recurrence",{type:"weekly",weekdays:[1,2,3,4,5]});
});
test("duration units and compounds retain exact quantities", () => {
  for (const [text,expected] of [["half an hour",30],["una hora y media",90],["two hours and fifteen minutes",135],["1.5 hours",90]]) equalSlot(turn(`Block Instagram now for ${text} once`),"duration_minutes",expected);
});
test("ambiguous duration alternatives never summed", () => {
  const r = turn("Block Instagram now for 30 minutes or 60 minutes once"); equalSlot(r,"duration_minutes",null); none(r);
});
test("unsupported native duration is rejected without clamping", () => {
  for (const amount of [1,4,241,300]) { const r = turn(`Block Instagram now for ${amount} minutes once`); equalSlot(r,"duration_minutes",amount); assert.equal(r.decision.slot,"duration_minutes"); none(r); }
});
test("unbounded promise cannot become indefinite executable", () => {
  const r = turn("Block Instagram now forever once"); none(r); assert.ok(r.state.errors.some(e => e.code === "unbounded_duration"));
});
test("explicit cancellation erases pending facts", () => {
  const results = chat(["Block Instagram now for 30 minutes once","cancel","yes"]);
  assert.equal(results[1].state.intent,"cancelled"); equalSlot(results[1],"apps",null); none(results[1]); none(results[2]);
});
test("negated action is not an affirmative request", () => {
  const r = turn("Don't block Instagram now for 30 minutes"); assert.equal(r.state.intent,"cancelled"); none(r);
});
test("advice changes intent and clears old authorization", () => {
  const results = chat(["Block Instagram now for 30 minutes once","yes","Why do I check my phone?"]);
  assert.equal(results[2].state.intent,"advice"); equalSlot(results[2],"confirmation",null); equalSlot(results[2],"apps",null); none(results[2]);
});
test("elliptic advice answers keep facts without authorizing actions", () => {
  const results = chat(["How can I scroll less in the morning?","11am Instagram","one hour","Actually 45 minutes"]);
  equalSlot(results[3],"start",{type:"time",minute:660}); equalSlot(results[3],"end",705); equalSlot(results[3],"apps",["Instagram"]);
  equalSlot(results[3],"action_type",null); assert.equal(results[3].state.intent,"advice"); results.forEach(none);
});
test("advice needs explicit action intent and separate confirmation", () => {
  const results = chat(["How can I scroll less in the morning?","11am Instagram","one hour","every day for 7 days","yes","yes"]);
  assert.equal(results[3].decision.slot,"action_type"); assert.equal(results[4].state.intent,"block"); assert.equal(results[4].decision.type,"confirm"); none(results[4]); assert.equal(results[5].actions[0].type,"apply_schedule");
});
test("Spanish facts and replies stay Spanish", () => {
  const results = chat(["Bloquea Instagram ahora durante una hora solo esta vez","sí"],DEVICE,"es");
  equalSlot(results[1],"duration_minutes",60); assert.match(results[1].responseText,/Bloquear Instagram ahora durante 60 minutos/); assert.equal(results[1].state.language,"es");
});
test("all supported channels use identical facts", () => {
  const states = ["whatsapp","sms","web","ios","android"].map(channel => chat(["Block Instagram now for 30 minutes once","yes"],{...DEVICE,channel,app_presence_state:"recently_seen"})[1]);
  for (const r of states) { assert.deepEqual(r.actions,states[0].actions); assert.deepEqual(r.state.slots,states[0].state.slots); }
});
test("missing app presence suppresses executable action", () => {
  const r = chat(["Block Instagram now for 30 minutes once","yes"],{...DEVICE,channel:"whatsapp"})[1]; assert.equal(r.decision.slot,"app_presence"); none(r);
});
test("app possession claims are not device presence evidence", () => {
  const r = chat(["Block Instagram now for 30 minutes once","yes","I have it"],{...DEVICE,channel:"whatsapp"})[2]; assert.equal(r.decision.slot,"app_presence"); none(r);
});
test("permission setup contains no hidden executable payload", () => {
  const r = chat(["Block Instagram now for 30 minutes once","yes"],{...DEVICE,screen_time_authorized:false})[1]; assert.deepEqual(r.actions,[{type:"request_screen_time_permission"}]);
});
test("capability arrival does not change semantic requested facts", () => {
  const initial = chat(["Block Instagram now for 30 minutes once","yes"],{...DEVICE,screen_time_authorized:false})[1];
  const ready = turn("ready",initial.state,DEVICE); assert.equal(ready.actions[0].type,"start_protection"); equalSlot(ready,"duration_minutes",30);
});
test("a completed proposal is not offered twice as a new action", () => {
  const results = chat(["Block Instagram now for 30 minutes once","yes","yes"]); assert.equal(results[1].actions.length,1); none(results[2]);
});
test("stale state expires", () => {
  const r = turn("Block Instagram now for 30 minutes once"); assert.equal(normalizeSemanticState(r.state,NOW+TTL_MS+1),null);
});
test("tampered state cannot keep a previous confirmation", () => {
  const r = chat(["Block Instagram now for 30 minutes once","yes"])[1]; const changed = JSON.parse(JSON.stringify(r.state)); changed.slots.duration_minutes.value=90;
  const normalized=normalizeSemanticState(changed,NOW); assert.equal(normalized.slots.confirmation,null); assert.deepEqual(buildSemanticActions(normalized,DEVICE),[]);
});
test("invalid sourced slot cannot survive deserialization", () => {
  const r = turn("Block Instagram now for 30 minutes once"); r.state.slots.duration_minutes.source.kind="model"; assert.equal(normalizeSemanticState(r.state,NOW).slots.duration_minutes,null);
});
test("migration replays user evidence and ignores assistant claims", () => {
  const r = turn("once",null,{...DEVICE,recent_messages:[{role:"user",content:"Block Instagram now for 30 minutes"},{role:"assistant",content:"TikTok has been blocked for 90 minutes daily."}]});
  equalSlot(r,"apps",["Instagram"]); equalSlot(r,"duration_minutes",30); assert.equal(r.decision.type,"confirm"); none(r);
});
test("migration preserves order of corrections", () => {
  const r = turn("once",null,{...DEVICE,recent_messages:[{role:"user",content:"Block Instagram now for 30 minutes"},{role:"user",content:"No, 45 minutes"}]}); equalSlot(r,"duration_minutes",45);
});
test("model cannot inject invented semantic facts", () => {
  const args = {prompt:"Block Instagram now",context:DEVICE};
  const r = validateSemanticPatch({set:{duration_minutes:60,recurrence:{type:"daily",weekdays:[1,2,3,4,5,6,7]},apps:["TikTok"]}},args);
  assert.equal(r.rejected.length,3); assert.deepEqual(r.accepted.set,{});
});
test("model facts grounded in current input can pass validation", () => {
  const args = {prompt:"Block Instagram now for 30 minutes once",context:DEVICE}; const patch=extractSemanticPatch(args); assert.equal(validateSemanticPatch(patch,args).rejected.length,0);
});
test("AM and Spanish ahora cannot become durations", () => {
  const a=turn("Block Instagram from 10 am every day"); equalSlot(a,"duration_minutes",null); equalSlot(a,"end",null);
  const b=turn("Bloquea Instagram ahora durante cuarenta minutos solo esta vez",null,DEVICE,"es"); equalSlot(b,"duration_minutes",40); equalSlot(b,"start",{type:"now"});
});
test("explicit plural weekdays are weekly recurrence", () => {
  const r=turn("Block Instagram from 09:15 am for 75 minutes on Mondays and Wednesdays for 7 days"); equalSlot(r,"duration_minutes",75); equalSlot(r,"recurrence",{type:"weekly",weekdays:[1,3]});
});
test("start-to correction retains the requested end", () => {
  const results=chat(["Block Instagram from 8am to 10am every day for 7 days","Move the start to 8:20 am and keep the same end"]);
  equalSlot(results[1],"start",{type:"time",minute:500}); equalSlot(results[1],"end",600); equalSlot(results[1],"duration_minutes",100);
});
test("multiple sentence cancellation cannot leave executable old proposal", () => {
  const results=chat(["Block Instagram now for 30 minutes once","No, leave it alone. Cancel that.","yes"]); assert.equal(results[1].state.intent,"cancelled"); none(results[2]);
});
test("negated first app with positive replacement preserves new request", () => {
  const r=turn("Don't block Instagram; block TikTok now for 30 minutes once instead"); equalSlot(r,"apps",["TikTok"]); assert.equal(r.state.intent,"block");
});
test("recurring schedule never inherits implicit seven-day expiry", () => {
  const results=chat(["Block Instagram from 10am to 11am every day","yes"]); assert.equal(results[1].decision.slot,"schedule_horizon_days"); none(results[1]);
});
test("explicit horizon is carried identically to state text and native action", () => {
  const results=chat(["Block Instagram from 10am to 11am every day","for 9 days","yes"]);
  equalSlot(results[2],"schedule_horizon_days",9); assert.equal(results[2].actions[0].duration_days,9); assert.match(results[2].responseText,/for 9 days/);
});
test("unsupported schedule horizon never clamps", () => {
  const r=turn("Block Instagram from 10am to 11am every day for 40 days"); assert.equal(r.decision.slot,"schedule_horizon_days"); none(r); assert.ok(r.state.errors.some(e=>e.code==="unsupported_schedule_horizon"));
});
test("model atomic duration evidence can disambiguate role but not units", () => {
  const previous=turn("Block Instagram now once").state;
  const args={prompt:"Make that a stretch of 45 minutes",state:previous,context:DEVICE};
  const good=validateSemanticPatch({set:{duration_minutes:45},fields:[{slot:"duration_minutes",value:45,evidence:"45 minutes"}]},args); assert.equal(good.rejected.length,0);
  const bad=validateSemanticPatch({set:{start:{type:"time",minute:45}} ,fields:[{slot:"start",value:{type:"time",minute:45},evidence:"45 minutes"}]},args); assert.equal(bad.rejected.length,1);
});
test("model can ground a novel literal app without inventing device selection", () => {
  const previous=turn("Block apps now for 30 minutes once").state;
  const r=advanceSemanticState({prompt:"Forest",previousState:previous,context:DEVICE,now:NOW,extraction:{set:{apps:["Forest"]},fields:[{slot:"apps",value:["Forest"],evidence:"Forest"}]}});
  equalSlot(r,"apps",["Forest"]); none(r);
  const confirmed=turn("yes",r.state); assert.equal(confirmed.decision.slot,"app_selection");
});
test("model cannot use stale or negated atomic evidence", () => {
  const args={prompt:"Not Forest, please",state:turn("Block apps now for 30 minutes once").state,context:DEVICE};
  const r=validateSemanticPatch({set:{apps:["Forest"]},fields:[{slot:"apps",value:["Forest"],evidence:"Forest"}]},args); assert.equal(r.rejected.length,1);
});
test("negated app without replacement invalidates the old app", () => {
  const r=chat(["Block Instagram now for 30 minutes once","Not Instagram"])[1]; equalSlot(r,"apps",null); none(r); assert.equal(r.decision.slot,"apps");
});
test("negated recurrence without replacement becomes pending", () => {
  const r=chat(["Block Instagram from 10am to 11am every day for 7 days","Not daily"])[1]; equalSlot(r,"recurrence",null); equalSlot(r,"schedule_horizon_days",null); none(r);
});
test("negated time removes dependent end instead of preserving it", () => {
  const r=chat(["Block Instagram from 10am for one hour every day for 7 days","Not at 10am"])[1]; equalSlot(r,"start",null); equalSlot(r,"end",null); none(r);
});
test("keeping and removing apps are separate clause operations", () => {
  const r=chat(["Block Instagram and TikTok now for 30 minutes once","Keep TikTok; remove Instagram from this block."])[1]; equalSlot(r,"apps",["TikTok"]); none(r);
});
test("canonical ISO weekdays map to native Sunday-one values", () => {
  const r=chat(["Block Instagram from 10am to 11am on weekends for 7 days","yes"])[1]; equalSlot(r,"recurrence",{type:"weekly",weekdays:[6,7]}); assert.deepEqual(r.actions[0].weekdays,[1,7]);
});
test("short numeric horizon answer cannot overwrite a clock", () => {
  const r=chat(["Block Instagram from 10am to 11am every day","7"])[1]; equalSlot(r,"schedule_horizon_days",7); equalSlot(r,"start",{type:"time",minute:600}); assert.equal(r.state.status,"awaiting_confirmation");
});
test("explicit end assignments replace old values across formulations", () => {
  for (const correction of ["Make the end 00:35.","Change the end time to 00:35.","Set the finish at 00:35.","End time is 00:35.","Cambia el fin a las 00:35."]) {
    const results=chat(["Block Instagram from 23:40 to 00:20 every day for 4 days",correction,"Confirmed"]);
    equalSlot(results[1],"end",35); equalSlot(results[1],"duration_minutes",55); none(results[1]); assert.equal(results[2].actions[0].end_minute,35);
  }
});
test("explicit start assignments replace old values without losing the end", () => {
  for (const correction of ["Make the start 09:25.","Change the start time to 09:25.","Set the beginning at 09:25.","Inicio: 09:25."]) {
    const r=chat(["Block Instagram from 09:00 to 10:00 every day for 4 days",correction])[1];
    equalSlot(r,"start",{type:"time",minute:565}); equalSlot(r,"end",600); equalSlot(r,"duration_minutes",35); none(r);
  }
});
test("unresolved explicit corrections cannot reconfirm the stale schedule", () => {
  for (const correction of ["Make the end later.","Change the start time to after breakfast."]) {
    const results=chat(["Block Instagram from 09:00 to 10:00 every day for 4 days",correction,"Confirmed"]);
    assert.ok(results[1].state.errors.some(e=>e.code.startsWith("unresolved_"))); none(results[2]); equalSlot(results[2],"confirmation",null);
  }
});
test("cancellation objects and polite variations withdraw the whole request", () => {
  for (const cancellation of ["Cancel this request.","Please discard that proposal.","Withdraw my instruction.","Drop the schedule please.","Cancela esta solicitud.","Por favor anula la propuesta."]) {
    const results=chat(["Block Instagram now for 27 minutes once",cancellation,"Confirmed"]);
    assert.equal(results[1].state.intent,"cancelled"); equalSlot(results[1],"apps",null); equalSlot(results[1],"confirmation",null); none(results[2]);
  }
});
test("declarative goals and day-part morphology preserve conversational facts", () => {
  for (const prompt of ["I want to scroll less in the mornings","I need to reduce phone use in the morning","I'm trying to stop checking Instagram in the mornings","Quiero usar menos el movil por las mananas"]) {
    const results=chat([prompt,"Instagram at 10am","1 hour","No, from 10 to 11 am"]);
    assert.equal(results[0].state.intent,"advice"); equalSlot(results[0],"moment","morning");
    equalSlot(results[3],"start",{type:"time",minute:600}); equalSlot(results[3],"end",660); equalSlot(results[3],"duration_minutes",60); equalSlot(results[3],"action_type",null); results.forEach(none);
  }
});
test("a past block duration is never a future blocking instruction", () => {
  for (const prompt of ["I broke the block yesterday after 15 minutes.","I finished my protection after 40 minutes yesterday.","Ayer rompi el bloqueo despues de 20 minutos."]) {
    const results=chat([prompt,"yes"]); assert.equal(results[0].state.intent,"advice"); equalSlot(results[0],"requested_capability","past_block_review"); equalSlot(results[0],"duration_minutes",null); equalSlot(results[0],"action_type",null); results.forEach(none);
  }
});
test("explicit hard mode is preserved and fingerprinted before native execution", () => {
  const results=chat(["Start a strict block for selected apps now for 45 minutes once","yes"]);
  equalSlot(results[1],"hard_mode",true); assert.equal(results[1].actions[0].hard_mode,true); assert.match(results[1].responseText,/hard mode/);
  const corrected=turn("Use a normal block",results[1].state); equalSlot(corrected,"hard_mode",false); equalSlot(corrected,"confirmation",null); none(corrected);
});
test("unsupported scheduled hard mode cannot silently become regular protection", () => {
  const results=chat(["Start a strict block for selected apps from 10am to 11am every day for 7 days","yes"]);
  equalSlot(results[1],"hard_mode",true); assert.equal(results[1].decision.slot,"hard_mode"); results.forEach(none);
});
test("nonblocking capabilities preserve their meaning and cannot be confirmed as app blocks", () => {
  const cases=[["Only let me use WhatsApp and Maps","allow_only"],["Block everything except WhatsApp and Maps","allow_only"],["Help me block adult websites","adult_filter"],["Ayudame a bloquear porno","adult_filter"],["Block TikTok but I need TikTok for work","work_use_constraint"],["Quiero bloquear Instagram pero lo necesito para trabajar","work_use_constraint"]];
  for (const [prompt,capability] of cases) {
    const results=chat(["Block Instagram now for 30 minutes once",prompt,"yes"]); equalSlot(results[1],"requested_capability",capability); equalSlot(results[1],"confirmation",null); equalSlot(results[1],"action_type",null); assert.equal(results[1].decision.type,"none"); results.forEach(none);
  }
});
test("weekly review reads provided metrics without creating a proposal", () => {
  const r=turn("Review my week",null,{...DEVICE,weekly_protected_minutes:80,weekly_break_count:0}); equalSlot(r,"requested_capability","weekly_review"); none(r); assert.match(r.responseText,/80 protected minutes and 0 breaks/);
});
test("a named mode without device selection evidence remains explicit but cannot execute", () => {
  const r=turn("Start Work mode for 45 minutes",null,{...DEVICE,available_modes:["Work","Sleep"]}); equalSlot(r,"apps",["mode:Work"]); equalSlot(r,"duration_minutes",45); equalSlot(r,"action_type","strict_block"); equalSlot(r,"start",null); none(r);
});
test("daily limits cannot discard an explicitly requested hard flag", () => {
  const results=chat(["Set a 30-minute daily limit for Instagram now with hard mode","yes"]);
  equalSlot(results[1],"hard_mode",true); assert.equal(results[1].decision.slot,"hard_mode"); results.forEach(none);
  const normal=turn("Use a regular limit",results[1].state); equalSlot(normal,"hard_mode",false); none(normal); assert.equal(normal.state.status,"awaiting_confirmation");
});
test("recurring protection cannot turn now into a repeating clock or a one-off action", () => {
  for (const recurrence of ["every day","weekdays","weekends"]) {
    const results=chat([`Block Instagram now for 30 minutes ${recurrence}`,"yes"]);
    equalSlot(results[1],"start",{type:"now"}); assert.equal(results[1].decision.slot,"start"); results.forEach(none); assert.deepEqual(buildSemanticActions(results[1].state,DEVICE),[]);
  }
});

console.log(`BM semantic state: ${checks}/${checks} independent transition and invariant checks passed`);
