const { getSupabaseUser, json, parseJsonBody, requireMethod } = require("./_membership");
const {
  ensureUser,
  patchUser,
  recordEvent,
  recordMessage,
} = require("./_waitlist_store");
const {
  OPENING_MESSAGE_1,
  OPENING_MESSAGE_2,
  sendOpeningMessage,
} = require("./_waitlist_whatsapp");

function now() {
  return new Date().toISOString();
}

function openingFields(channel) {
  return channel === "sms"
    ? {
      first: "opening_sms_first_sent_at",
      second: "opening_sms_second_sent_at",
    }
    : {
      first: "opening_first_sent_at",
      second: "opening_second_sent_at",
    };
}

async function startWaitlist(event) {
  const authUser = await getSupabaseUser(event);
  if (!authUser?.id || !authUser?.phone) return json(401, { error: "waitlist_auth_required" });
  const body = parseJsonBody(event);
  const channel = String(body.channel || "whatsapp").trim().toLowerCase();
  const messagingConsent = body.messaging_consent === true || body.whatsapp_consent === true;
  if (!["whatsapp", "sms"].includes(channel)) return json(400, { error: "waitlist_channel_invalid" });
  if (body.data_consent !== true || !messagingConsent) {
    return json(400, { error: "waitlist_consent_required" });
  }

  let user = await ensureUser({
    authUserId: authUser.id,
    phone: authUser.phone,
    dataConsent: true,
    whatsappConsent: true,
  });

  const fields = openingFields(channel);
  const sent = [];
  if (!user[fields.first]) {
    const result = await sendOpeningMessage(user.phone_e164, 1, channel);
    await recordMessage({
      userId: user.id,
      provider: result.provider,
      providerMessageId: result.id,
      direction: "outbound",
      messageKind: "opening",
      body: OPENING_MESSAGE_1,
    });
    user = await patchUser(user.id, { [fields.first]: now() });
    sent.push(1);
  }

  if (!user[fields.second]) {
    const result = await sendOpeningMessage(user.phone_e164, 2, channel);
    await recordMessage({
      userId: user.id,
      provider: result.provider,
      providerMessageId: result.id,
      direction: "outbound",
      messageKind: "opening",
      body: OPENING_MESSAGE_2,
    });
    user = await patchUser(user.id, { [fields.second]: now(), opening_sent_at: now() });
    sent.push(2);
  } else if (!user.opening_sent_at) {
    user = await patchUser(user.id, { opening_sent_at: now() });
  }

  if (sent.length) await recordEvent(user.id, "waitlist_started", { channel, opening_messages_sent: sent });
  return json(200, {
    ok: true,
    waitlist_status: user.status,
    channel,
    opening_sent: Boolean(user.opening_sent_at),
    sent,
  });
}

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;
  try {
    return await startWaitlist(event);
  } catch (error) {
    const detail = error.message || "unknown";
    const templateMissing = /opening_templates_missing|template_missing/i.test(detail);
    return json(templateMissing ? 503 : 500, {
      error: templateMissing ? "waitlist_opening_templates_not_configured" : "waitlist_start_failed",
      detail,
    });
  }
};

module.exports.startWaitlist = startWaitlist;
