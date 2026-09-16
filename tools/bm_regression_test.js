"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const {
  advanceLoop,
  createLoop,
  publicLoop,
} = require("../netlify/functions/bm-loop");
const { buildAgentContext } = require("../netlify/functions/bm-context");
const { policyForPlan } = require("../netlify/functions/bm-policy");

const ROOT = path.join(__dirname, "..");
const ios = fs.readFileSync(path.join(ROOT, "ios/Blank/Blank/ContentView.swift"), "utf8");
const blankApp = fs.readFileSync(path.join(ROOT, "ios/Blank/Blank/BlankApp.swift"), "utf8");
const home = fs.readFileSync(path.join(ROOT, "ios/Blank/Blank/HomeView.swift"), "utf8");
const sessionStore = fs.readFileSync(path.join(ROOT, "ios/Blank/Blank/SessionStore.swift"), "utf8");
const assistantChannel = fs.readFileSync(path.join(ROOT, "netlify/functions/assistant-channel.js"), "utf8");
const assistantChannelShared = fs.readFileSync(path.join(ROOT, "netlify/functions/_assistant_channel.js"), "utf8");
const bmContext = fs.readFileSync(path.join(ROOT, "netlify/functions/bm-context.js"), "utf8");
const whatsapp = fs.readFileSync(path.join(ROOT, "netlify/functions/whatsapp-agent.js"), "utf8");
const agent = fs.readFileSync(path.join(ROOT, "netlify/functions/blanked-agent.js"), "utf8");
const openPage = fs.readFileSync(path.join(ROOT, "web/landing/open.html"), "utf8");
const android = fs.readFileSync(
  path.join(ROOT, "app/src/main/java/com/blanknfc/app/data/DigitalWellnessRemoteStore.kt"),
  "utf8",
);

const failures = [];

function check(name, fn) {
  try {
    fn();
    console.log(`PASS ${name}`);
  } catch (error) {
    failures.push({ name, error: error.message || String(error) });
    console.error(`FAIL ${name}: ${error.message || error}`);
  }
}

function blockBetween(source, startMarker, endMarker) {
  const start = source.indexOf(startMarker);
  const end = source.indexOf(endMarker, start + startMarker.length);
  assert.ok(start >= 0, `missing:${startMarker}`);
  assert.ok(end > start, `missing:${endMarker}`);
  return source.slice(start, end);
}

function iosLikeLoop(loop) {
  const publicState = publicLoop(loop);
  return {
    loop_version: publicState.loop_version,
    loop_id: publicState.loop_id,
    idempotency_key: publicState.idempotency_key,
    status: publicState.status,
    phase: publicState.phase,
    goal: publicState.goal,
    iteration: publicState.iteration,
    max_iterations: publicState.max_iterations,
    next_step: publicState.next_step,
    action_types: publicState.action_types,
    trigger: publicState.trigger,
    consent: publicState.consent,
    verification: publicState.verification,
    stop_conditions: publicState.stop_conditions,
    last_event: publicState.last_event,
    event_ids: publicState.event_ids,
    event_history: publicState.event_history,
    state_version: publicState.state_version,
    event_sequence: publicState.event_sequence,
  };
}

check("ios_loop_round_trip_preserves_confirmation_contract", () => {
  const loopBlock = blockBetween(ios, "private struct AgentLoop: Codable, Equatable {", "private struct AgentPlan:");
  assert.match(loopBlock, /\bvar\s+consent\b/, "iOS AgentLoop must carry consent across JSON round-trips");

  const loop = createLoop({
    prompt: "Block the evening scroll",
    runId: "regression_ios_round_trip",
    context: { has_selected_apps: true, screen_time_authorized: true },
    plan: { intent: "focus", title: "Focus", response_text: "ok", actions: [{ type: "apply_schedule" }] },
  });
  const result = advanceLoop(iosLikeLoop(loop), { type: "confirm", event_id: "ios_round_trip_confirm" });
  assert.strictEqual(result.accepted, true);
  assert.strictEqual(result.transition, "ready_for_execution");
});

check("ios_persists_loop_before_first_advance", () => {
  const clientBlock = blockBetween(ios, "private struct BMLoopClient", "private struct RemoteAgentResponse");
  const reportBlock = blockBetween(ios, "private func reportAgentExecution", "private func agentAnonymousUserId");
  assert.match(clientBlock, /operation\s*=\s*["']start["']|startLoop\(/, "iOS BMLoopClient must expose a start operation");
  assert.match(reportBlock, /\.start\(|startLoop\(/, "iOS execution reporting must persist the loop before advancing it");
});

check("context_preserves_autonomy_and_native_control_fields", () => {
  const context = buildAgentContext({
    autonomy_consent: true,
    authorized_action_types: ["apply_schedule"],
    autonomy_grant: { active: true, action_types: ["apply_schedule"] },
    device_execution_ready: true,
    available_modes: ["Deep Focus"],
    mode_name: "Routine",
  });

  assert.ok(Array.isArray(context.authorized_action_types));
  assert.ok(context.autonomy_grant && context.autonomy_grant.active === true);
  assert.deepStrictEqual(context.available_modes, ["Deep Focus"]);
  assert.strictEqual(context.mode_name, "Routine");
  assert.strictEqual(
    policyForPlan({ actions: [{ type: "apply_schedule" }] }, context).decision,
    "autonomous_execution",
  );
});

check("ios_verification_uses_device_state_not_label_count", () => {
  const reportBlock = blockBetween(ios, "private func reportAgentExecution", "private func agentAnonymousUserId");
  assert.doesNotMatch(
    ios,
    /verified:\s*appliedLabels\.count\s*>=\s*plan\.executableActionCount/,
    "verification cannot be inferred from UI labels");
  assert.match(
    reportBlock,
    /evidence|deviceState|actualState|stateMatches|verifyDevice/i,
    "execution reporting must include explicit device-state verification");
});

check("native_clients_close_loop_with_outcome_recorded", () => {
  const reportBlock = blockBetween(ios, "private func reportAgentExecution", "private func agentAnonymousUserId");
  const executionBlock = blockBetween(android, "fun recordExecution(", "private fun startLoop(");
  assert.match(reportBlock, /outcome_recorded/, "iOS must send outcome_recorded after execution");
  assert.match(executionBlock, /outcome_recorded/, "Android must send outcome_recorded after execution");
});

check("immediate_protection_does_not_invent_duration", () => {
  assert.match(agent, /const requestedDuration = explicitDurationMinutes\(prompt\);/);
  assert.match(agent, /normalized\.minutes = null/);
  assert.match(agent, /set_daily_limit.*explicitDurationMinutes/);
  const reviewLink = require("../netlify/functions/_bm_action_link").reviewActionLink({ type: "start_protection", minutes: 17 });
  assert.strictEqual(new URL(reviewLink).searchParams.get("action"), "review-action");
  assert.strictEqual(new URL(reviewLink).searchParams.get("minutes"), "17");
  assert.match(whatsapp, /queuePendingAssistantAction/);
  assert.doesNotMatch(whatsapp, /TWILIO_WHATSAPP_REVIEW_TEMPLATE_ENABLED/);
  assert.doesNotMatch(whatsapp, /Review and confirm in Blankmind:\\n/);
  assert.doesNotMatch(whatsapp, /start-focus.*minutes.*30/);
});

check("messaging_actions_execute_without_native_confirmation", () => {
  assert.match(whatsapp, /I'm applying it now/);
  assert.doesNotMatch(whatsapp, /Open Blankmind to review and apply it/);
  assert.match(assistantChannel, /poll_pending_action/);
  assert.match(assistantChannel, /ack_pending_action/);
  assert.match(assistantChannel, /register_device_push/);
  assert.match(blankApp, /action == "review-action"/);
  assert.match(blankApp, /didReceiveRemoteNotification/);
  assert.match(blankApp, /AssistantBackgroundActionRunner/);
  assert.match(sessionStore, /pendingAssistantAction/);
  assert.match(home, /AssistantActionInboxClient/);
  assert.match(home, /confirmPendingAssistantAction\(\)/);
  assert.match(assistantChannel, /execution_started/);
  assert.match(assistantChannel, /last_assistant_action_outcome/);
  assert.match(home, /status:\s*"verified"/);
  assert.match(home, /blankPendingAssistantActionId/);
});

check("assistant_context_sync_reaches_messaging_identity", () => {
  assert.match(assistantChannel, /action === "sync_context"/);
  assert.match(assistantChannel, /recordAssistantUserContext/);
  assert.match(assistantChannelShared, /assistant_user_context_synced/);
  assert.match(assistantChannelShared, /attachAssistantUserContext/);
  assert.match(assistantChannel, /const connection = await findAssistantConnection\(connectCode, preferredChannel\)/);
  assert.match(bmContext, /available_mode_catalog/);
  assert.match(bmContext, /deriveAppPresence/);
  assert.match(bmContext, /app_presence_state/);
  assert.match(assistantChannelShared, /last_seen_at: now/);
  assert.match(ios, /AssistantContextSyncClient/);
  assert.match(ios, /BlankmindAppPresence\.payload/);
  assert.match(home, /BlankmindAppPresence\.payload/);
  assert.match(ios, /availableModeCatalog/);
  assert.match(home, /assistantContextPayload/);
  assert.match(home, /syncAssistantContext/);
  assert.match(sessionStore, /func assistantModeCatalog/);
});

check("daily_limit_applies_screen_time_state", () => {
  const dailyLimitBlock = blockBetween(blankApp, 'if action == "daily-limit"', 'if action == "pause-rules"');
  assert.match(dailyLimitBlock, /refreshDailyLimitMonitoring\(\)/);
  assert.match(dailyLimitBlock, /applyScreenTimeState\(\)/);
  assert.match(agent, /title: "Daily Limit"/);
  assert.match(agent, /How many minutes per day do you want to allow/);
});

check("adaptive_schedule_appends_windows", () => {
  const scheduleBlock = blockBetween(sessionStore, "func applyAdaptivePlan(", "func applyAIPlan(");
  assert.match(scheduleBlock, /var windows = schedule\.windows/);
  assert.match(scheduleBlock, /windows\.append\(window\)/);
  assert.doesNotMatch(ios, /sessionStore\.schedule\.windows = \[window\]/);
});

check("why_now_layout_preserves_conversational_design", () => {
  const whyNowBlock = blockBetween(home, "private struct RelapseReviewSheet", "private struct RelapseReasonTile");
  assert.match(whyNowBlock, /ZStack\(alignment: \.bottomLeading\)/);
  assert.match(whyNowBlock, /frame\(maxWidth: \.infinity, maxHeight: \.infinity, alignment: \.leading\)/);
  assert.match(whyNowBlock, /VStack\(alignment: \.leading, spacing: -8\)/);
  assert.match(home, /sessionStore\.recordRelapseReview\(reason\)[\s\S]{0,160}sessionStore\.applyAIPlan\(\)/);
});

check("assistant_actions_reuse_saved_modes_and_ignore_stale_timer", () => {
  assert.match(sessionStore, /func restoreSavedSelectionForAssistant\(appNames: \[String\] = \[\]\)/);
  assert.match(sessionStore, /usePendingWidgetTimer: Bool = true/);
  assert.match(home, /restoreSavedSelectionForAssistant\(appNames: appNames\)/);
  assert.match(home, /usePendingWidgetTimer: false/);
});

check("review_action_survives_landing_redirect", () => {
  assert.match(openPage, /"review-action"/);
  assert.match(openPage, /Review and confirm in Blankmind/);
  assert.match(openPage, />Review and confirm</);
});

if (failures.length > 0) {
  console.error(`\nBM regression suite failed: ${failures.length}/12 checks`);
  process.exitCode = 1;
} else {
  console.log("\nBM regression suite passed: 12/12 checks");
}
