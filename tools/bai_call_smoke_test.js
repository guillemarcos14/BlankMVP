const assert = require("assert");

process.env.ELEVENLABS_CONVAI_API_KEY = "test-convai-key";
process.env.ELEVENLABS_AGENT_ID = "agent_test";
process.env.BAI_CALL_ADMIN_SECRET = "test-admin-secret";
process.env.TWILIO_ACCOUNT_SID = "ACtest";
process.env.TWILIO_AUTH_TOKEN = "test-auth-token";
process.env.TWILIO_VOICE_FROM_NUMBER = "+13478366767";
process.env.BLANKED_PUBLIC_APP_LINK_BASE = "https://getblank.netlify.app";

const { handler: twimlHandler } = require("../netlify/functions/bai-call-twiml");
const { handler: callHandler } = require("../netlify/functions/bai-call");
const { handler: configureHandler } = require("../netlify/functions/twilio-voice-configure");

async function inboundVoiceRepliesAreDisabled() {
  const response = await twimlHandler({
    httpMethod: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded", host: "getblank.netlify.app" },
    body: "",
  });
  assert.strictEqual(response.statusCode, 410, response.body);
  assert.strictEqual(response.body, "<Response><Hangup/></Response>");
}

async function outboundCallsAreDisabled() {
  const response = await callHandler({
    httpMethod: "POST",
    headers: { "x-bai-call-secret": "test-admin-secret" },
    body: JSON.stringify({ to: "+34600000000" }),
  });
  assert.strictEqual(response.statusCode, 410, response.body);
  assert.strictEqual(JSON.parse(response.body).error, "voice_replies_disabled");
}

async function voiceConfigurationIsDisabled() {
  const response = await configureHandler({
    httpMethod: "POST",
    headers: { "x-bai-call-secret": "test-admin-secret" },
  });
  assert.strictEqual(response.statusCode, 410, response.body);
  assert.strictEqual(JSON.parse(response.body).error, "voice_replies_disabled");
}

(async () => {
  await inboundVoiceRepliesAreDisabled();
  await outboundCallsAreDisabled();
  await voiceConfigurationIsDisabled();
  console.log("bai-call disabled smoke tests passed");
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
