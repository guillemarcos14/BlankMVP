const { json, parseJsonBody, requireMethod } = require("./_membership");
const {
  cleanChannel,
  cleanText,
  findAssistantConnection,
  normalizeConnectCode,
  recordAssistantChannel,
  proactiveGate,
  sendAssistantMessage,
} = require("./_assistant_channel");

async function registerPreference(body) {
  const connectCode = normalizeConnectCode(body.connect_code);
  const preferredChannel = cleanChannel(body.preferred_channel || body.channel);
  if (!connectCode || !preferredChannel) {
    return json(400, { error: "missing_connect_code_or_channel" });
  }

  await recordAssistantChannel({
    event: "assistant_channel_preference_set",
    channel: preferredChannel,
    preferredChannel,
    connectCode,
    userPhone: body.user_phone || body.phone_number || "",
  });

  return json(200, { ok: true, connect_code: connectCode, preferred_channel: preferredChannel });
}

async function sendProactive(body) {
  const connectCode = normalizeConnectCode(body.connect_code);
  const preferredChannel = cleanChannel(body.preferred_channel || body.channel);
  const message = cleanText(body.message || body.body || body.text, 900);
  if (!connectCode || !message) {
    return json(400, { error: "missing_connect_code_or_message" });
  }

  const connection = await findAssistantConnection(connectCode, preferredChannel);
  const gate = await proactiveGate(connectCode, message, connection?.channel || preferredChannel, body.update_key || body.signal_id || "", connection?.channelUser || "");
  if (!gate.allowed) {
    await recordAssistantChannel({
      event: "assistant_proactive_delivery_skipped",
      channel: connection?.channel || preferredChannel,
      preferredChannel,
      connectCode,
      channelUser: connection?.channelUser || "",
      metadata: { reason: gate.reason },
    });
    return json(200, { ok: true, delivered: false, channel: connection?.channel || preferredChannel || "", reason: gate.reason });
  }
  if (connection?.channel === "whatsapp" && !gate.contentSid) {
    return json(200, { ok: true, delivered: false, channel: "whatsapp", reason: "missing_proactive_template" });
  }
  const result = await sendAssistantMessage(connection, message, gate.contentSid ? { contentSid: gate.contentSid } : {});
  await recordAssistantChannel({
    event: result.skipped ? "assistant_proactive_delivery_skipped" : "assistant_proactive_delivered",
    channel: connection?.channel || preferredChannel,
    preferredChannel,
    connectCode,
    channelUser: connection?.channelUser || "",
    metadata: {
      proactive_fingerprint: gate.proactiveFingerprint,
      update_key: cleanText(body.update_key || body.signal_id, 120),
      template_index: gate.templateIndex,
      content_sid: gate.contentSid,
    },
  });

  if (!result.skipped && connection?.channel === "whatsapp") {
    await require("./_assistant_channel").recordAssistantMemory({
      channel: "whatsapp",
      channelUser: connection.channelUser,
      memory: {
        pending_proactive_message: message,
        pending_proactive_update_key: cleanText(body.update_key || body.signal_id, 120),
        pending_proactive_sent_at: new Date().toISOString(),
      },
      source: "assistant_proactive_template",
    });
  }

  return json(200, {
    ok: true,
    delivered: !result.skipped,
    channel: connection?.channel || preferredChannel || "",
    reason: result.reason || "",
  });
}

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;

  try {
    const body = parseJsonBody(event);
    const action = cleanText(body.action, 60).toLowerCase();
    if (action === "register_preference") return registerPreference(body);
    if (action === "send_proactive") return sendProactive(body);
    return json(400, { error: "unsupported_action" });
  } catch (error) {
    return json(500, { error: "assistant_channel_failed", detail: error.message });
  }
};
