const assert = require("assert");

const phone = process.env.BM_FINAL_QA_WHATSAPP_PHONE;
process.env.BM_FINAL_QA_WHATSAPP_PHONE = "+34658991584";
const finalPath = require.resolve("../netlify/functions/whatsapp-agent");
const previousFinal = require.cache[finalPath];
const transport = require("../netlify/functions/_waitlist_whatsapp");
const previousTranscribe = transport.transcribeAudio;
const received = [];
require.cache[finalPath] = {
  id: finalPath, filename: finalPath, loaded: true,
  exports: { processTrustedQaMessage: async (message) => { received.push(message); return { sent: true }; } },
};
transport.transcribeAudio = async () => "Nota transcrita";

async function main() {
  const { processFinalTwilioMessage } = require("../netlify/functions/_bm_final_qa_dispatch");
  let result = await processFinalTwilioMessage({
    provider: "twilio", channel: "whatsapp", phone: "+34658991584",
    providerMessageId: "SM-one", text: "Hola", audio: { url: "https://media.test/audio", contentType: "audio/ogg" },
  });
  assert.strictEqual(result.sent, true);
  assert.deepStrictEqual(received[0], { from: "+34658991584", id: "SM-one", text: "Hola\nNota transcrita" });

  result = await processFinalTwilioMessage({ channel: "sms", phone: "+34658991584", providerMessageId: "SM-sms", text: "Hola" });
  assert.strictEqual(result.reason, "bm_final_qa_not_allowed");
  result = await processFinalTwilioMessage({ channel: "whatsapp", phone: "+34658991585", providerMessageId: "SM-other", text: "Hola" });
  assert.strictEqual(result.reason, "bm_final_qa_not_allowed");
  result = await processFinalTwilioMessage({ channel: "whatsapp", phone: "+34658991584", text: "Hola" });
  assert.strictEqual(result.reason, "bm_final_qa_message_id_required");
  assert.strictEqual(received.length, 1);
  process.stdout.write("BM Final private WhatsApp dispatch tests passed\n");
}

main().catch((error) => { console.error(error); process.exitCode = 1; }).finally(() => {
  if (phone === undefined) delete process.env.BM_FINAL_QA_WHATSAPP_PHONE; else process.env.BM_FINAL_QA_WHATSAPP_PHONE = phone;
  if (previousFinal) require.cache[finalPath] = previousFinal; else delete require.cache[finalPath];
  transport.transcribeAudio = previousTranscribe;
});
