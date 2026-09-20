const { json, parseJsonBody } = require("./_membership");
const { cleanText } = require("./_identity");
const { extractFacts, generateReply } = require("./_waitlist_ai");
const {
  claimInbound,
  completeInbound,
  currentFacts,
  deleteUserData,
  markFirstReply,
  patchUser,
  persistFacts,
  recentMessages,
  recordEvent,
  recordMessage,
  releaseInbound,
  userByPhone,
  withdrawConsent,
} = require("./_waitlist_store");
const {
  isTwilioEvent,
  enqueueTwilioMessage,
  parseMetaMessages,
  parseTwilioMessage,
  sendMetaText,
  shouldUseAsyncTwilio,
  transcribeAudio,
  twimlResponse,
  verifyMetaChallenge,
  verifyMetaSignature,
  verifyTwilioSignature,
} = require("./_waitlist_whatsapp");

const DELETE_REQUEST = /\b(delete|erase|forget|remove)\b.{0,40}\b(my data|my information|everything|my profile|all data)\b/i;
const DELETE_CONFIRMATION = /^DELETE$/i;
const STOP_COMMAND = /^(STOP|UNSUBSCRIBE|CANCEL|END|QUIT)$/i;

function publicJoinUrl() {
  return cleanText(process.env.WAITLIST_PUBLIC_URL, 800) || "https://blankmind.ai/signup?channel=whatsapp";
}

function naturalFallbackReply(prompt, history) {
  const text = cleanText(prompt, 4000).toLowerCase();
  const hasSubstantiveInbound = history.some((message) =>
    message.direction === "inbound"
    && !/^(hi|hello|hey|hola)\b/i.test(cleanText(message.body, 4000))
  );
  const isOpening = /^(hi|hello|hey|hola)\b/.test(text) && !hasSubstantiveInbound;
  if (isOpening) {
    return "Hey, good to have you here. What usually happens when you start scrolling? You can write it out or send a voice note.";
  }
  if (/(wake|woke|morning|breakfast|first thing|8\s*am|40\s*(?:to|-)\s*45)/i.test(text)) {
    return "I’m curious what usually keeps you scrolling during those first 40 or 45 minutes before breakfast.";
  }
  if (/(scroll|phone|instagram|tiktok|youtube|help me|want to stop)/i.test(text)) {
    return "I’m curious what you usually end up looking at once you start scrolling.";
  }
  return "I’m curious what part of that moment keeps bringing you back to your phone.";
}

function noConsentReply() {
  return `I can continue once you join Blankmind Early Access and confirm that I can save this conversation. You can do that here: ${publicJoinUrl()}`;
}

function deletionIsPending(user) {
  const requestedAt = Date.parse(user?.deletion_requested_at || "");
  return Number.isFinite(requestedAt) && Date.now() - requestedAt <= 24 * 60 * 60 * 1000;
}

async function saveOutbound(user, provider, reply, kind = "text", providerMessageId = null) {
  return recordMessage({
    userId: user.id,
    provider,
    providerMessageId,
    direction: "outbound",
    messageKind: kind,
    body: reply,
  });
}

async function privacyReply({ user, provider, prompt }) {
  if (STOP_COMMAND.test(prompt)) {
    await withdrawConsent(user);
    await recordEvent(user.id, "consent_withdrawn", { provider });
    return "I’ve stopped the Early Access conversation and I won’t save anything else from here.";
  }
  if (DELETE_CONFIRMATION.test(prompt)) {
    if (!deletionIsPending(user)) {
      await patchUser(user.id, { deletion_requested_at: new Date().toISOString() });
      return "I can delete everything I’ve saved about you. Reply DELETE once more within 24 hours to confirm.";
    }
    const userId = user.id;
    await deleteUserData(userId);
    return "I’ve deleted your Early Access profile, messages, and extracted information.";
  }
  if (DELETE_REQUEST.test(prompt)) {
    await patchUser(user.id, { deletion_requested_at: new Date().toISOString() });
    await recordEvent(user.id, "deletion_requested", { provider });
    return "I can delete everything I’ve saved about you. Reply DELETE within 24 hours to confirm.";
  }
  return "";
}

async function processMessage(message, options = {}) {
  const deferDelivery = options.deferDelivery === true;
  const claim = await claimInbound(message.provider, message.providerMessageId);
  if (!claim.claimed) return { skipped: true, reason: "duplicate_inbound" };

  let user = await userByPhone(message.phone);
  if (!user || user.status !== "active" || user.data_consent !== true || user.whatsapp_consent !== true) {
    if (!deferDelivery) await completeInbound(message.provider, message.providerMessageId);
    return { reply: noConsentReply(), user: null, kind: "privacy", deliveryDeferred: deferDelivery };
  }

  try {
    let prompt = cleanText(message.text, 4000);
    let messageKind = "text";
    if (message.audio) {
      try {
        prompt = await transcribeAudio(message);
        messageKind = "audio_transcript";
        await recordEvent(user.id, "audio_transcribed", { provider: message.provider });
      } catch (error) {
        await recordEvent(user.id, "audio_transcription_failed", { provider: message.provider, reason: cleanText(error.message, 160) });
        const reply = "I couldn’t make out that voice note clearly. Could you send it again, or write it here instead?";
        if (!deferDelivery) {
          await saveOutbound(user, message.provider, reply);
          await completeInbound(message.provider, message.providerMessageId);
        }
        return {
          reply,
          user,
          kind: "text",
          deliveryDeferred: deferDelivery,
        };
      }
    }
    if (!prompt) {
      const reply = "I didn’t catch anything in that message. Could you try again?";
      if (!deferDelivery) {
        await saveOutbound(user, message.provider, reply);
        await completeInbound(message.provider, message.providerMessageId);
      }
      return { reply, user, kind: "text", deliveryDeferred: deferDelivery };
    }

    const privacy = await privacyReply({ user, provider: message.provider, prompt });
    if (privacy) {
      const currentUser = await userByPhone(message.phone);
      if (currentUser?.status === "active" && currentUser.data_consent === true) {
        await recordMessage({
          userId: user.id,
          provider: message.provider,
          providerMessageId: message.providerMessageId,
          direction: "inbound",
          messageKind: "privacy",
          body: prompt,
        });
        if (!deferDelivery) await saveOutbound(user, message.provider, privacy, "privacy");
      }
      if (!deferDelivery) await completeInbound(message.provider, message.providerMessageId);
      return { reply: privacy, user: null, kind: "privacy", deliveryDeferred: deferDelivery };
    }

    const inbound = await recordMessage({
      userId: user.id,
      provider: message.provider,
      providerMessageId: message.providerMessageId,
      direction: "inbound",
      messageKind,
      body: prompt,
    });
    user = await markFirstReply(user) || user;
    const [history, known] = await Promise.all([
      recentMessages(user.id),
      currentFacts(user.id),
    ]);

    let extracted = [];
    let saved = [];
    let generated;
    let updated = known;
    if (message.audio) {
      // Voice notes become plain text here. Run the two independent model calls together
      // so the Twilio webhook can return before its delivery window becomes unreliable.
      const [extractionResult, generationResult] = await Promise.all([
        extractFacts({ message: prompt, history, profile: known.profile })
          .then((facts) => ({ facts }))
          .catch((error) => ({ error })),
        generateReply({
          message: prompt,
          history,
          profile: known.profile,
          newlySavedFacts: [],
        })
          .then((result) => ({ result }))
          .catch((error) => ({ error })),
      ]);

      if (extractionResult.error) {
        await recordEvent(user.id, "fact_extraction_failed", { reason: cleanText(extractionResult.error.message, 160) });
      } else {
        extracted = extractionResult.facts;
        try {
          saved = await persistFacts({ user, sourceMessageId: inbound?.id, facts: extracted });
        } catch (error) {
          await recordEvent(user.id, "fact_extraction_failed", { reason: cleanText(error.message, 160) });
        }
      }

      if (generationResult.error) {
        await recordEvent(user.id, "conversation_generation_failed", { reason: cleanText(generationResult.error.message, 160) });
        generated = {
          reply: naturalFallbackReply(prompt, history),
          focus: "natural_followup",
          profile_useful: false,
          restricted: false,
        };
      } else {
        generated = generationResult.result;
      }
    } else {
      try {
        extracted = await extractFacts({ message: prompt, history, profile: known.profile });
        saved = await persistFacts({ user, sourceMessageId: inbound?.id, facts: extracted });
      } catch (error) {
        await recordEvent(user.id, "fact_extraction_failed", { reason: cleanText(error.message, 160) });
      }

      updated = await currentFacts(user.id);
      try {
        generated = await generateReply({
          message: prompt,
          history,
          profile: updated.profile,
          newlySavedFacts: saved,
        });
      } catch (error) {
        await recordEvent(user.id, "conversation_generation_failed", { reason: cleanText(error.message, 160) });
        generated = {
          reply: naturalFallbackReply(prompt, history),
          focus: "natural_followup",
          profile_useful: false,
          restricted: false,
        };
      }
    }

    if (message.audio) updated = await currentFacts(user.id);

    const completion = {
      provider: message.provider,
      input_kind: messageKind,
      facts_saved: saved.length,
      fact_keys: saved.map((fact) => fact.field_key),
      profile_fields: Object.keys(updated.profile),
      focus: generated.focus,
      conversation_goal_state: generated.goal_plan?.state || null,
      conversation_anchor_goal: generated.goal_plan?.anchor_goal || null,
      conversation_next_goal: generated.goal_plan?.next_goal || null,
      restricted_topic: generated.restricted === true,
    };
    if (!deferDelivery) {
      await saveOutbound(user, message.provider, generated.reply);
      await Promise.all([
        recordEvent(user.id, "waitlist_turn_completed", completion),
        completeInbound(message.provider, message.providerMessageId),
      ]);
    }
    return {
      reply: generated.reply,
      user,
      kind: "text",
      factsSaved: saved.length,
      inputKind: messageKind,
      focus: generated.focus,
      restricted: generated.restricted === true,
      deliveryDeferred: deferDelivery,
    };
  } catch (error) {
    await releaseInbound(message.provider, message.providerMessageId).catch(() => null);
    throw error;
  }
}

async function handleTwilio(event) {
  if (!verifyTwilioSignature(event)) return json(403, { error: "invalid_twilio_signature" });
  const messages = parseTwilioMessage(event);
  if (!messages.length) return twimlResponse("");
  if (shouldUseAsyncTwilio()) {
    try {
      await enqueueTwilioMessage(messages[0], event);
      return twimlResponse("");
    } catch (error) {
      return json(503, { error: "waitlist_twilio_queue_failed", detail: cleanText(error.message, 240) });
    }
  }
  const result = await processMessage(messages[0]);
  return twimlResponse(result.reply || "");
}

async function handleMeta(event) {
  if (!verifyMetaSignature(event)) return json(403, { error: "invalid_whatsapp_signature" });
  const body = parseJsonBody(event);
  if (!body || typeof body !== "object" || Array.isArray(body)) return json(400, { error: "invalid_whatsapp_payload" });
  const messages = parseMetaMessages(body).slice(0, 5);
  const results = [];
  for (const message of messages) {
    const result = await processMessage(message);
    if (result.reply) {
      const delivery = await sendMetaText(message.phone, result.reply);
      if (result.user) {
        await recordEvent(result.user.id, "waitlist_reply_delivered", { provider: "meta", provider_message_id: delivery.id });
      }
    }
    results.push({ skipped: result.skipped === true, reason: result.reason || null, facts_saved: result.factsSaved || 0 });
  }
  return json(200, { ok: true, received: messages.length, results });
}

exports.handler = async (event) => {
  if (event.httpMethod === "GET") return verifyMetaChallenge(event);
  if (event.httpMethod === "OPTIONS") return { statusCode: 204, headers: json(200, {}).headers, body: "" };
  if (event.httpMethod !== "POST") return json(405, { error: "method_not_allowed" });
  try {
    return isTwilioEvent(event) ? await handleTwilio(event) : await handleMeta(event);
  } catch (error) {
    return json(500, { error: "waitlist_agent_failed", detail: cleanText(error.message, 240) });
  }
};

module.exports.processMessage = processMessage;
module.exports.saveOutbound = saveOutbound;
module.exports.naturalFallbackReply = naturalFallbackReply;
