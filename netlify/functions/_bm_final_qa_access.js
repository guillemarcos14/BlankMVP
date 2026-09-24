const { phoneForStorage } = require("./_waitlist_store");

// One exact E.164 number. Missing or malformed configuration grants no access.
function qaPhone() {
  const configured = process.env.BM_FINAL_QA_WHATSAPP_PHONE || "";
  return /^\+[1-9]\d{7,14}$/.test(configured) ? configured : "";
}

function privateQaGateConfigured() {
  return Object.prototype.hasOwnProperty.call(process.env, "BM_FINAL_QA_WHATSAPP_PHONE");
}

function isFinalQaWhatsApp(channel, sender) {
  const allowed = qaPhone();
  return channel === "whatsapp" && Boolean(allowed) && phoneForStorage(sender) === allowed;
}

module.exports = { isFinalQaWhatsApp, qaPhone, privateQaGateConfigured };
