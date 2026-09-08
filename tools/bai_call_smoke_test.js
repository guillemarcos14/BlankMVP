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

async function inboundTwimlRegistersElevenLabsCall() {
  const originalFetch = global.fetch;
  global.fetch = async (url, options) => {
    assert.strictEqual(url, "https://api.elevenlabs.io/v1/convai/twilio/register-call");
    assert.strictEqual(options.headers["xi-api-key"], "test-convai-key");
    const body = JSON.parse(options.body);
    assert.strictEqual(body.agent_id, "agent_test");
    assert.strictEqual(body.from_number, "+34600000000");
    assert.strictEqual(body.to_number, "+13478366767");
    assert.strictEqual(body.direction, "inbound");
    assert.strictEqual(body.conversation_initiation_client_data.dynamic_variables.assistant_channel, "voice_call");
    return { ok: true, text: async () => "<Response><Connect><Stream/></Connect></Response>" };
  };

  try {
    const response = await twimlHandler({
      httpMethod: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded", host: "getblank.netlify.app" },
      queryStringParameters: { direction: "inbound" },
      body: new URLSearchParams({ From: "+34600000000", To: "+13478366767", CallSid: "CAinbound" }).toString(),
    });
    assert.strictEqual(response.statusCode, 200, response.body);
    assert.match(response.body, /<Connect>/);
  } finally {
    global.fetch = originalFetch;
  }
}

async function outboundCallRequiresAdminSecret() {
  const response = await callHandler({
    httpMethod: "POST",
    headers: {},
    body: JSON.stringify({ to: "+34600000000" }),
  });
  assert.strictEqual(response.statusCode, 401, response.body);
}

async function outboundCallCreatesTwilioCall() {
  const originalFetch = global.fetch;
  global.fetch = async (url, options) => {
    assert.match(url, /https:\/\/api\.twilio\.com\/2010-04-01\/Accounts\/ACtest\/Calls\.json/);
    assert.match(options.headers.authorization, /^Basic /);
    const params = new URLSearchParams(options.body.toString());
    assert.strictEqual(params.get("To"), "+34600000000");
    assert.strictEqual(params.get("From"), "+13478366767");
    assert.strictEqual(params.get("Url"), "https://getblank.netlify.app/.netlify/functions/bai-call-twiml?direction=outbound");
    return { ok: true, text: async () => JSON.stringify({ sid: "CAoutbound", status: "queued" }) };
  };

  try {
    const response = await callHandler({
      httpMethod: "POST",
      headers: { "x-bai-call-secret": "test-admin-secret" },
      body: JSON.stringify({ to: "+34600000000" }),
    });
    assert.strictEqual(response.statusCode, 200, response.body);
    const body = JSON.parse(response.body);
    assert.strictEqual(body.ok, true);
    assert.strictEqual(body.sid, "CAoutbound");
  } finally {
    global.fetch = originalFetch;
  }
}

async function configureUpdatesTwilioNumberVoiceUrl() {
  const originalFetch = global.fetch;
  let requests = 0;
  global.fetch = async (url, options = {}) => {
    requests += 1;
    assert.match(options.headers.authorization, /^Basic /);
    if (requests === 1) {
      assert.match(url, /IncomingPhoneNumbers\.json\?PhoneNumber=%2B13478366767$/);
      return {
        ok: true,
        json: async () => ({ incoming_phone_numbers: [{ sid: "PNtest" }] }),
      };
    }
    assert.match(url, /IncomingPhoneNumbers\/PNtest\.json$/);
    const params = new URLSearchParams(options.body.toString());
    assert.strictEqual(params.get("VoiceUrl"), "https://getblank.netlify.app/.netlify/functions/bai-call-twiml?direction=inbound");
    assert.strictEqual(params.get("VoiceMethod"), "POST");
    return {
      ok: true,
      text: async () => JSON.stringify({
        phone_number: "+13478366767",
        voice_url: params.get("VoiceUrl"),
        voice_method: "POST",
      }),
    };
  };

  try {
    const response = await configureHandler({
      httpMethod: "POST",
      headers: { "x-bai-call-secret": "test-admin-secret" },
    });
    assert.strictEqual(response.statusCode, 200, response.body);
    assert.strictEqual(requests, 2);
  } finally {
    global.fetch = originalFetch;
  }
}

(async () => {
  await inboundTwimlRegistersElevenLabsCall();
  await outboundCallRequiresAdminSecret();
  await outboundCallCreatesTwilioCall();
  await configureUpdatesTwilioNumberVoiceUrl();
  console.log("bai-call smoke tests passed");
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
