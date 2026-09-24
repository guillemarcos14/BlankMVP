const { isFinalQaWhatsApp } = require("./_bm_final_qa_access");
const { transcribeAudio } = require("./_waitlist_whatsapp");

async function processFinalTwilioMessage(message) {
  if (!isFinalQaWhatsApp(message?.channel, message?.phone)) {
    return { skipped: true, reason: "bm_final_qa_not_allowed" };
  }
  if (!message.providerMessageId) {
    return { skipped: true, reason: "bm_final_qa_message_id_required" };
  }
  let text = message.text || "";
  if (message.audio) {
    try {
      const transcript = await transcribeAudio(message);
      text = text ? `${text}\n${transcript}` : transcript;
    } catch (_) {
      // The final agent sends its standard unreadable-audio reply when empty.
    }
  }
  const { processTrustedQaMessage } = require("./whatsapp-agent");
  return processTrustedQaMessage({
    from: message.phone,
    id: message.providerMessageId,
    text,
  });
}

module.exports = { processFinalTwilioMessage };
