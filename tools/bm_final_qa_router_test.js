const assert = require("assert");
const crypto = require("crypto");

const envNames = [
  "CONTEXT", "NODE_ENV", "NETLIFY", "BM_FINAL_QA_WHATSAPP_PHONE", "TWILIO_AUTH_TOKEN",
  "TWILIO_WHATSAPP_FROM_NUMBER", "TWILIO_FROM_NUMBER",
  "TWILIO_VALIDATE_WEBHOOK_SIGNATURE", "WAITLIST_TWILIO_ASYNC",
  "WAITLIST_TWILIO_WEBHOOK_URL", "TWILIO_WEBHOOK_URL",
  "WHATSAPP_APP_SECRET",
];
const previousEnv = Object.fromEntries(envNames.map((name) => [name, process.env[name]]));
const storePath = require.resolve("../netlify/functions/_waitlist_store");
const whatsappPath = require.resolve("../netlify/functions/whatsapp-agent");
const dispatchPath = require.resolve("../netlify/functions/_bm_final_qa_dispatch");
const previousModules = new Map([storePath, whatsappPath, dispatchPath].map((path) => [path, require.cache[path]]));
const realStore = require(storePath);
const waitlistTransport = require("../netlify/functions/_waitlist_whatsapp");
const previousMetaSend = waitlistTransport.sendMetaText;
const finalCalls = [];
const waitlistPhones = [];
const metaReplies = [];

function replaceModule(path, exports) {
  require.cache[path] = { id: path, filename: path, loaded: true, exports };
}

function signedTwilio(url, from, id) {
  const body = new URLSearchParams({ From: from, Body: "Hola", MessageSid: id }).toString();
  const params = Array.from(new URLSearchParams(body).entries())
    .sort(([leftKey, leftValue], [rightKey, rightValue]) => leftKey.localeCompare(rightKey) || leftValue.localeCompare(rightValue))
    .map(([key, value]) => `${key}${value}`).join("");
  const signature = crypto.createHmac("sha1", process.env.TWILIO_AUTH_TOKEN)
    .update(`${url}${params}`, "utf8").digest("base64");
  return {
    httpMethod: "POST",
    path: new URL(url).pathname,
    headers: { "content-type": "application/x-www-form-urlencoded", "x-twilio-signature": signature },
    body,
  };
}

function signedMeta(messages) {
  const body = JSON.stringify({ entry: [{ changes: [{ value: { messages } }] }] });
  return {
    httpMethod: "POST",
    headers: { "content-type": "application/json", "x-hub-signature-256": `sha256=${crypto.createHmac("sha256", process.env.WHATSAPP_APP_SECRET).update(body).digest("hex")}` },
    body,
  };
}

async function main() {
  process.env.CONTEXT = "production";
  process.env.BM_FINAL_QA_WHATSAPP_PHONE = "+34658991584";
  process.env.TWILIO_AUTH_TOKEN = "qa-test-token";
  process.env.TWILIO_VALIDATE_WEBHOOK_SIGNATURE = "false"; // Production must still verify.
  process.env.WAITLIST_TWILIO_ASYNC = "false";
  process.env.WAITLIST_TWILIO_WEBHOOK_URL = "https://getblank.netlify.app/.netlify/functions/waitlist-agent";
  process.env.TWILIO_WEBHOOK_URL = "https://getblank.netlify.app/.netlify/functions/sms-agent";
  process.env.WHATSAPP_APP_SECRET = "qa-test-meta-secret";
  process.env.TWILIO_WHATSAPP_FROM_NUMBER = "whatsapp:+13478366767";

  replaceModule(storePath, {
    ...realStore,
    claimInbound: async () => ({ claimed: true }),
    completeInbound: async () => null,
    releaseInbound: async () => null,
    userByPhone: async (phone) => { waitlistPhones.push(phone); return null; },
  });
  replaceModule(whatsappPath, {
    processTrustedQaMessage: async (message) => { finalCalls.push(message); return { sent: true }; },
  });
  replaceModule(dispatchPath, {
    processFinalTwilioMessage: async (message) => { finalCalls.push(message); return { sent: true }; },
  });
  waitlistTransport.sendMetaText = async (phone, reply) => {
    metaReplies.push({ phone, reply });
    return { id: "meta-test" };
  };

  const { isFinalQaWhatsApp } = require("../netlify/functions/_bm_final_qa_access");
  const waitlist = require("../netlify/functions/waitlist-agent");
  const sms = require("../netlify/functions/sms-agent");

  assert.strictEqual(isFinalQaWhatsApp("whatsapp", "whatsapp:+34658991584"), true);
  assert.strictEqual(isFinalQaWhatsApp("sms", "+34658991584"), false);
  assert.strictEqual(isFinalQaWhatsApp("whatsapp", "+34658991585"), false);
  assert.strictEqual(isFinalQaWhatsApp("whatsapp", "+346589915840"), false);
  for (const invalid of ["", "34658991584", "+34658991584,+34600000000", " +34658991584 "]) {
    process.env.BM_FINAL_QA_WHATSAPP_PHONE = invalid;
    assert.strictEqual(isFinalQaWhatsApp("whatsapp", "+34658991584"), false);
  }
  process.env.BM_FINAL_QA_WHATSAPP_PHONE = "+34658991584";

  const waitlistUrl = process.env.WAITLIST_TWILIO_WEBHOOK_URL;
  let response = await waitlist.handler(signedTwilio(waitlistUrl, "whatsapp:+34658991584", "SM-owner"));
  assert.strictEqual(response.statusCode, 200);
  assert.strictEqual(finalCalls.length, 1);
  assert.strictEqual(waitlistPhones.length, 0);

  response = await waitlist.handler(signedTwilio(waitlistUrl, "whatsapp:+34658991585", "SM-other"));
  assert.strictEqual(response.statusCode, 200);
  assert.match(response.body, /<Message>/);
  assert.strictEqual(finalCalls.length, 1);
  assert.strictEqual(waitlistPhones.length, 1);

  response = await waitlist.handler(signedTwilio(waitlistUrl, "+34658991584", "SM-owner-sms"));
  assert.strictEqual(response.statusCode, 200);
  assert.strictEqual(finalCalls.length, 1);
  assert.strictEqual(waitlistPhones.length, 2);

  process.env.BM_FINAL_QA_WHATSAPP_PHONE = "";
  response = await waitlist.handler(signedTwilio(waitlistUrl, "whatsapp:+34658991584", "SM-disabled"));
  assert.strictEqual(response.statusCode, 200);
  assert.strictEqual(finalCalls.length, 1);
  process.env.BM_FINAL_QA_WHATSAPP_PHONE = "+34658991584";

  const unsigned = signedTwilio(waitlistUrl, "whatsapp:+34658991584", "SM-unsigned");
  delete unsigned.headers["x-twilio-signature"];
  response = await waitlist.handler(unsigned);
  assert.strictEqual(response.statusCode, 403);
  assert.strictEqual(finalCalls.length, 1);

  response = await waitlist.handler(signedMeta([
    { from: "34658991584", id: "wamid.owner", text: { body: "Hola" } },
    { from: "34658991585", id: "wamid.other", text: { body: "Hola" } },
  ]));
  assert.strictEqual(response.statusCode, 200, response.body);
  assert.strictEqual(finalCalls.length, 2);
  assert.strictEqual(metaReplies.length, 1);
  assert.strictEqual(metaReplies[0].phone, "+34658991585");
  const badMeta = signedMeta([{ from: "34658991584", id: "wamid.bad", text: { body: "Hola" } }]);
  badMeta.headers["x-hub-signature-256"] = "sha256=bad";
  response = await waitlist.handler(badMeta);
  assert.strictEqual(response.statusCode, 403);
  assert.strictEqual(finalCalls.length, 2);

  response = await sms.handler(signedTwilio(process.env.TWILIO_WEBHOOK_URL, "whatsapp:+34658991584", "SM-legacy-owner"));
  assert.strictEqual(response.statusCode, 200);
  assert.strictEqual(finalCalls.length, 3);
  response = await sms.handler(signedTwilio(process.env.TWILIO_WEBHOOK_URL, "+34658991584", "SM-legacy-sms"));
  assert.strictEqual(response.statusCode, 200);
  assert.strictEqual(finalCalls.length, 3);
  response = await sms.handler(signedTwilio(process.env.TWILIO_WEBHOOK_URL, "whatsapp:+34658991585", "SM-legacy-other"));
  assert.strictEqual(response.statusCode, 200);
  assert.strictEqual(finalCalls.length, 3);

  delete require.cache[whatsappPath];
  const directWhatsapp = require(whatsappPath);
  response = await directWhatsapp.handler(signedMeta([
    { from: "34658991585", id: "wamid.direct.other", text: { body: "Hola" } },
  ]));
  assert.strictEqual(response.statusCode, 200);
  assert.strictEqual(finalCalls.length, 3);
  assert.strictEqual(metaReplies.length, 2);

  process.env.WAITLIST_TWILIO_ASYNC = "true";
  const previousFetch = global.fetch;
  let queued = null;
  try {
    global.fetch = async (_url, options) => {
      queued = options;
      return { ok: true, status: 202, text: async () => "" };
    };
    response = await waitlist.handler(signedTwilio(waitlistUrl, "whatsapp:+34658991584", "SM-background-owner"));
    assert.strictEqual(response.statusCode, 200);
    assert.ok(queued?.body);
    assert.strictEqual(finalCalls.length, 3);
  } finally {
    global.fetch = previousFetch;
  }
  const background = require("../netlify/functions/waitlist-agent-background");
  response = await background.handler({
    httpMethod: "POST",
    headers: { "x-waitlist-background-signature": queued.headers["x-waitlist-background-signature"] },
    body: queued.body,
  });
  assert.strictEqual(response.statusCode, 200, response.body);
  assert.strictEqual(finalCalls.length, 4);
  response = await background.handler({
    httpMethod: "POST",
    headers: { "x-waitlist-background-signature": "sha256=bad" },
    body: queued.body,
  });
  assert.strictEqual(response.statusCode, 403);
  assert.strictEqual(finalCalls.length, 4);

  // Netlify functions may not expose a production marker at runtime. The
  // configured private gate must still close both legacy public endpoints.
  delete process.env.CONTEXT;
  delete process.env.NODE_ENV;
  delete process.env.NETLIFY;
  process.env.WAITLIST_TWILIO_ASYNC = "false";
  response = await sms.handler(signedTwilio(process.env.TWILIO_WEBHOOK_URL, "whatsapp:+34658991585", "SM-no-context-other"));
  assert.strictEqual(response.statusCode, 200);
  assert.strictEqual(finalCalls.length, 4);
  assert.strictEqual(waitlistPhones.at(-1), "+34658991585");
  response = await sms.handler(signedTwilio(process.env.TWILIO_WEBHOOK_URL, "whatsapp:+13478366767", "SM-outbound-status"));
  assert.strictEqual(response.statusCode, 200);
  assert.doesNotMatch(response.body, /<Message>/);
  assert.strictEqual(finalCalls.length, 4);
  response = await waitlist.handler(signedTwilio(waitlistUrl, "whatsapp:+13478366767", "SM-outbound-status-waitlist"));
  assert.strictEqual(response.statusCode, 200);
  assert.doesNotMatch(response.body, /<Message>/);
  const unsignedLegacy = signedTwilio(process.env.TWILIO_WEBHOOK_URL, "whatsapp:+34658991584", "SM-no-context-unsigned");
  delete unsignedLegacy.headers["x-twilio-signature"];
  assert.strictEqual((await sms.handler(unsignedLegacy)).statusCode, 403);
  assert.strictEqual((await directWhatsapp.handler(signedMeta([
    { from: "34658991585", id: "wamid.no-context.other", text: { body: "Hola" } },
  ]))).statusCode, 200);
  assert.strictEqual(finalCalls.length, 4);

  process.stdout.write("BM Final private WhatsApp router tests passed\n");
}

main().catch((error) => { console.error(error); process.exitCode = 1; }).finally(() => {
  waitlistTransport.sendMetaText = previousMetaSend;
  for (const [path, previous] of previousModules) {
    if (previous) require.cache[path] = previous; else delete require.cache[path];
  }
  for (const [name, value] of Object.entries(previousEnv)) {
    if (value === undefined) delete process.env[name]; else process.env[name] = value;
  }
});
