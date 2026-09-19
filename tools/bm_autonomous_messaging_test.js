"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { apnsCredentials, normalizeDevicePush, pushPayload } = require("../netlify/functions/_assistant_push");

const root = path.resolve(__dirname, "..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");

const device = normalizeDevicePush({
  token: "AA".repeat(32),
  environment: "sandbox",
  app_install_id: "install-1",
  updated_at: "2026-09-16T12:00:00.000Z",
});
assert.equal(device.token, "aa".repeat(32));
assert.equal(device.environment, "sandbox");
assert.equal(normalizeDevicePush({ token: "invalid" }), null);

const executable = pushPayload({ id: "action-1", type: "start_protection" });
assert.equal(executable.aps["content-available"], 1);
assert.equal(executable.aps.category, "BM_PENDING_ACTION");
assert.match(executable.aps.alert.body, /tap.*apply/i, "blocking actions must wait for an explicit notification tap");
assert.equal(executable.bm_action_id, "action-1");

const setup = pushPayload({ id: "action-2", type: "open_app_picker" });
assert.equal(setup.aps["content-available"], 1);
assert.match(setup.aps.alert.body, /tap.*choose/i);
assert.doesNotMatch(setup.aps.alert.body, /block/i, "onboarding selection must not imply that a block already exists");

const previousAuthKey = process.env.APNS_AUTH_KEY;
const compactScalar = Buffer.concat([Buffer.alloc(31), Buffer.from([1])]).toString("base64url");
process.env.APNS_AUTH_KEY = `${compactScalar}.D9A2SJAVZ2.GS54UV79RG`;
const compactCredentials = apnsCredentials();
assert.equal(compactCredentials.keyId, "D9A2SJAVZ2");
assert.equal(compactCredentials.teamId, "GS54UV79RG");
assert.equal(compactCredentials.privateKey.type, "private");
if (previousAuthKey === undefined) delete process.env.APNS_AUTH_KEY;
else process.env.APNS_AUTH_KEY = previousAuthKey;

const assistantChannel = read("netlify/functions/assistant-channel.js");
const smsAgent = read("netlify/functions/sms-agent.js");
const whatsappAgent = read("netlify/functions/whatsapp-agent.js");
const blankApp = read("ios/Blank/Blank/BlankApp.swift");
const home = read("ios/Blank/Blank/HomeView.swift");
const info = read("ios/Blank/Blank/Info.plist");

assert.match(assistantChannel, /register_device_push/);
assert.match(assistantChannel, /status === "verified"/);
assert.match(assistantChannel, /applied and verified/);
assert.match(smsAgent, /sendAssistantActionPush/);
assert.match(whatsappAgent, /sendAssistantActionPush/);
assert.match(whatsappAgent, /Tap the Blankmind notification to apply it/);
assert.match(whatsappAgent, /Tap the Blankmind notification to start your/);
assert.match(whatsappAgent, /Number\.isInteger\(action\.minutes\)/);
assert.doesNotMatch(smsAgent, /Open Blankmind to review and apply it/);
assert.doesNotMatch(whatsappAgent, /Open Blankmind to review and apply it/);
assert.match(blankApp, /didReceiveRemoteNotification/);
assert.match(blankApp, /BM_PENDING_ACTION/);
assert.match(blankApp, /BM_APPLY_NOW/);
assert.match(blankApp, /Apply Now/);
assert.match(blankApp, /UNUserNotificationCenterDelegate/);
assert.match(blankApp, /completionHandler\(\.noData\)/);
assert.doesNotMatch(blankApp, /AssistantBackgroundActionRunner/);
assert.match(home, /applyAssistantProtection/);
assert.match(home, /requestedDurationMinutes/);
assert.match(assistantChannel, /invalid_execution_evidence/);
assert.match(whatsappAgent, /last_assistant_push_attempt/);
assert.doesNotMatch(blankApp, /duplicateMode\(named:/);
assert.match(home, /confirmPendingAssistantAction\(\)/);
assert.match(home, /blankAssistantApplyNowRequested/);
assert.match(home, /applyNowRequested/);
assert.match(home, /guard applyNowRequested else/);
assert.match(home, /Read this after the network round-trip/);
assert.match(blankApp, /tappedActionIDKey/);
assert.match(home, /native_state_applied_after_selection/);
assert.match(info, /<string>remote-notification<\/string>/);

console.log("BM autonomous messaging contract passed: push, canonical selection, picker and verified acknowledgement");
