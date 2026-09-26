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

async function isFinalAppLinkedWhatsApp(channel, sender, text = "") {
  if (process.env.BM_FINAL_APP_LINKED_ROUTING_ENABLED !== "true" || channel !== "whatsapp") return false;
  const phone = phoneForStorage(sender);
  if (!phone) return false;
  const { identityForPhone } = require("./_identity");
  const identity = await identityForPhone(phone);
  if (!identity?.app_install_id || !identity?.assistant_connect_code) return false;
  const { connectCodeFromText, findAssistantConnectionForChannelUser } = require("./_assistant_channel");
  if (connectCodeFromText(text) === identity.assistant_connect_code) return true;
  const connection = await findAssistantConnectionForChannelUser("whatsapp", phone);
  return connection?.connectCode === identity.assistant_connect_code;
}

module.exports = { isFinalQaWhatsApp, isFinalAppLinkedWhatsApp, qaPhone, privateQaGateConfigured };
