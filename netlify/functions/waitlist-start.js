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

function openingGapMs() {
  const configured = Number(process.env.WAITLIST_OPENING_GAP_MS);
  if (Number.isFinite(configured) && configured >= 0) return Math.min(configured, 5000);
  return 1500;
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function safeRecordEvent(userId, eventName, properties) {
  try {
    await recordEvent(userId, eventName, properties);
  } catch {
    // Observability must never turn a successful opening into a failed request.
  }
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

function deliveryFailureCode(error) {
  const message = String(error?.message || '').toLowerCase();
  if (/template|content_sid/.test(message)) return 'template_not_configured_or_rejected';
  if (/twilio|provider|message/.test(message)) return 'provider_send_failed';
  if (/timeout|network|fetch/.test(message)) return 'network_or_provider';
  return 'opening_delivery_failed';
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

  await safeRecordEvent(user.id, "waitlist_start_requested", { channel });

  const fields = openingFields(channel);
  const sent = [];
  const deliveries = [];
  const persistenceErrors = [];
  let deliveryError = null;
  let previousDeliveryIndex = null;

  // Deliver both messages before persisting either delivery. A Supabase write
  // must never prevent the second opening message from reaching the phone.
  for (const index of [1, 2]) {
    const field = index === 1 ? fields.first : fields.second;
    if (user[field]) continue;
    if (index === 2 && previousDeliveryIndex === 1) {
      // Give Twilio time to enqueue the first template before creating the
      // second one, so WhatsApp/SMS cannot present the opening out of order.
      await wait(openingGapMs());
    }
    try {
      const result = await sendOpeningMessage(user.phone_e164, index, channel);
      deliveries.push({ index, result });
      sent.push(index);
      previousDeliveryIndex = index;
    } catch (error) {
      deliveryError = error;
      break;
    }
  }

  for (const delivery of deliveries) {
    const { index, result } = delivery;
    const body = index === 1 ? OPENING_MESSAGE_1 : OPENING_MESSAGE_2;
    try {
      await recordMessage({
        userId: user.id,
        provider: result.provider,
        providerMessageId: result.id,
        direction: "outbound",
        messageKind: "opening",
        body,
      });
    } catch (error) {
      persistenceErrors.push({ index, stage: "message", error });
    }

    const updates = index === 1
      ? { [fields.first]: now() }
      : { [fields.second]: now(), opening_sent_at: now() };
    try {
      user = await patchUser(user.id, updates) || { ...user, ...updates };
    } catch (error) {
      persistenceErrors.push({ index, stage: "user", error });
    }
  }

  if (user[fields.second] && !user.opening_sent_at && !deliveryError) {
    // Keep the legacy aggregate marker populated for older records that have
    // both channel-specific timestamps but no opening_sent_at value.
    try {
      user = await patchUser(user.id, { opening_sent_at: now() }) || user;
    } catch (error) {
      persistenceErrors.push({ index: 2, stage: "user", error });
    }
  }

  if (sent.length) {
    try {
      await recordEvent(user.id, "waitlist_started", {
        channel,
        opening_messages_sent: sent,
        persistence_warning: persistenceErrors.length > 0,
      });
    } catch (error) {
      persistenceErrors.push({ index: 0, stage: "event", error });
    }
  }

  if (deliveryError) {
    await safeRecordEvent(user.id, "waitlist_start_failed", {
      channel,
      stage: "opening_delivery",
      opening_messages_sent: sent,
      error_code: deliveryFailureCode(deliveryError),
    });
    throw deliveryError;
  }

  const openingSent = Boolean(user.opening_sent_at) || sent.includes(2);
  await safeRecordEvent(user.id, "waitlist_start_completed", {
    channel,
    opening_messages_sent: sent,
    opening_already_sent: sent.length === 0,
    persistence_warning: persistenceErrors.length > 0,
  });
  return json(200, {
    ok: true,
    waitlist_status: user.status,
    channel,
    opening_sent: openingSent,
    sent,
    persistence_warning: persistenceErrors.length > 0,
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
