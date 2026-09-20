const { json, parseJsonBody } = require("./_membership");
const { cleanText } = require("./_identity");
const {
  completeInbound,
  patchUser,
  recordEvent,
  releaseInbound,
} = require("./_waitlist_store");
const {
  sendTwilioText,
  verifyBackgroundSignature,
} = require("./_waitlist_whatsapp");
const { processMessage, saveOutbound } = require("./waitlist-agent");

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function retryable(error) {
  return /waitlist_twilio_text_send_(408|425|429|5\d\d):/i.test(String(error?.message || ""))
    || /fetch failed|network|timeout|socket|econnreset/i.test(String(error?.message || ""));
}

async function withRetry(task, attempts = 3) {
  let lastError;
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      return await task();
    } catch (error) {
      lastError = error;
      if (attempt === attempts - 1 || !retryable(error)) throw error;
      await sleep(300 * (attempt + 1));
    }
  }
  throw lastError || new Error("waitlist_retry_failed");
}

function validMessage(message) {
  return message
    && message.provider === "twilio"
    && cleanText(message.providerMessageId, 160)
    && cleanText(message.phone, 90);
}

async function deliverMessage(message) {
  let result;
  let lastError;
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      result = await processMessage(message, { deferDelivery: true });
      break;
    } catch (error) {
      lastError = error;
      if (attempt === 0) await sleep(500);
    }
  }
  if (!result) throw lastError || new Error("waitlist_background_processing_failed");
  if (result.skipped || !result.reply) return result;

  const replies = Array.isArray(result.replies) && result.replies.length
    ? result.replies
    : [result.reply];
  const deliveries = [];
  for (const reply of replies) {
    deliveries.push(await withRetry(() => sendTwilioText(message.phone, reply, message.channel), 4));
  }
  try {
    if (result.user) {
      for (const [index, delivery] of deliveries.entries()) {
        await withRetry(() => saveOutbound(result.user, "twilio", replies[index], result.kind === "privacy" ? "privacy" : "text", delivery.id), 3);
        await withRetry(() => recordEvent(result.user.id, "waitlist_reply_delivered", {
          provider: "twilio",
          provider_message_id: delivery.id,
          delivery_status: delivery.status,
        }), 3);
      }
      if (result.availabilityNoticeField && result.availabilityNotice?.length === 2) {
        await withRetry(() => patchUser(result.user.id, {
          [result.availabilityNoticeField]: new Date().toISOString(),
        }), 3);
        await withRetry(() => recordEvent(result.user.id, "waitlist_availability_notice_sent", {
          channel: message.channel === "sms" ? "sms" : "whatsapp",
          message_count: result.availabilityNotice.length,
        }), 3);
      }
      if (result.inputKind) {
        await withRetry(() => recordEvent(result.user.id, "waitlist_turn_completed", {
          provider: "twilio",
          input_kind: result.inputKind,
          facts_saved: result.factsSaved || 0,
          focus: result.focus || "natural_followup",
          restricted_topic: result.restricted === true,
        }), 3);
      }
    }
    await withRetry(() => completeInbound(message.provider, message.providerMessageId), 3);
  } catch (error) {
    error.delivery = deliveries.at(-1);
    throw error;
  }
  return { ...result, delivery: deliveries.at(-1) };
}

exports.handler = async (event) => {
  if (event.httpMethod === "OPTIONS") return json(204, {});
  if (event.httpMethod !== "POST") return json(405, { error: "method_not_allowed" });
  if (!verifyBackgroundSignature(event)) return json(403, { error: "invalid_background_signature" });
  const body = parseJsonBody(event);
  const message = body?.message;
  if (!validMessage(message)) return json(400, { error: "invalid_waitlist_message" });

  let result = null;
  try {
    result = await deliverMessage(message);
    return json(200, {
      ok: true,
      skipped: result.skipped === true,
      reason: result.reason || null,
      provider_message_id: result.delivery?.id || null,
    });
  } catch (error) {
    if (error.delivery?.id) {
      await completeInbound(message.provider, message.providerMessageId).catch(() => null);
    } else {
      await releaseInbound(message.provider, message.providerMessageId).catch(() => null);
    }
    await recordEvent(result?.user?.id || null, "waitlist_reply_delivery_failed", {
      provider: "twilio",
      provider_message_id: message.providerMessageId,
      reason: cleanText(error.message, 240),
    }).catch(() => null);
    return json(500, { error: "waitlist_background_failed", detail: cleanText(error.message, 240) });
  }
};

module.exports.deliverMessage = deliverMessage;
