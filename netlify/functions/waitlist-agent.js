const { json, parseJsonBody } = require("./_membership");
const { cleanText } = require("./_identity");
const { canonicalizeConversation, extractFacts, generateReply } = require("./_waitlist_ai");
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
  CAPABILITY_NOTICE_MESSAGE,
  AVAILABILITY_NOTICE_MESSAGE_1,
  AVAILABILITY_NOTICE_MESSAGE_2,
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

function spanishLanguage(language) {
  return String(language || "").toLowerCase().startsWith("es");
}

function detectedLanguage(prompt, history = [], user = {}) {
  const text = cleanText(prompt, 1200).toLowerCase();
  if (/\b(?:en espa[nñ]ol|en castellano|a partir de ahora.*(?:espa[nñ]ol|castellano))\b/i.test(text)) return "es";
  if (/\b(?:in english|in ingles|in inglés|from now on.*english)\b/i.test(text)) return "en";
  const spanishScore = [
    "¿", "á", "é", "í", "ó", "ú", "ñ", "hola", "buenas", "quiero", "puedes", "puedo",
    "bloquear", "bloquea", "móvil", "movil", "teléfono", "telefono", "después", "despues",
    "por favor", "gracias", "repite", "repetir", "última respuesta", "ultima respuesta",
    "castellano", "español", "espanol", "ahora", "noche", "dormir", "ayúdame", "ayudame",
  ].reduce((score, token) => score + (text.includes(token) ? 1 : 0), 0);
  const englishScore = [
    "how can i", "what should i", "please", "repeat", "last response", "phone", "block", "scroll",
    "morning", "night", "help me", "thanks", "hello", "hey",
  ].reduce((score, token) => score + (text.includes(token) ? 1 : 0), 0);
  if (spanishScore > englishScore) return "es";
  if (englishScore > spanishScore) return "en";
  const previous = [...(Array.isArray(history) ? history : [])]
    .reverse()
    .find((message) => message?.direction === "inbound" && /^(?:es|en)/i.test(message?.source_language || ""));
  if (previous?.source_language) return spanishLanguage(previous.source_language) ? "es" : "en";
  return spanishLanguage(user?.language || user?.locale) ? "es" : "en";
}

function isRepeatRequest(prompt) {
  const text = cleanText(prompt, 1200).toLowerCase();
  return /\b(?:repeat|rephrase|say again|last response|last answer)\b/i.test(text)
    || /\b(?:repite|repetir|vuelve a decir|última respuesta|ultima respuesta|respuesta anterior)\b/i.test(text);
}

function latestOutboundReply(history = []) {
  return [...(Array.isArray(history) ? history : [])]
    .reverse()
    .find((message) => message?.direction === "outbound")?.body || "";
}

function availabilityNoticeField(channel) {
  return channel === "sms"
    ? "availability_notice_sms_sent_at"
    : "availability_notice_whatsapp_sent_at";
}

function availabilityNoticeMessages(language = "en") {
  return spanishLanguage(language)
    ? [
      "Por cierto, ahora estás en la lista de acceso anticipado, así que el producto completo todavía no está disponible.",
      "El bloqueo de apps estará disponible el 1 de octubre. Hasta entonces, me interesa saber cómo encaja el móvil en tu día.",
    ]
    : [AVAILABILITY_NOTICE_MESSAGE_1, AVAILABILITY_NOTICE_MESSAGE_2];
}

function isCapabilityRequest(prompt) {
  const text = cleanText(prompt, 4000);
  const mentionsBlocking = /\b(?:block|blocking|limit|restrict|lock|bloquear|bloquea|limitar|restringir)\b/i.test(text);
  const mentionsTarget = /\b(?:app|apps|application|applications|phone|instagram|tiktok|youtube|reels|social media|aplicación|aplicaciones|móvil|movil|redes sociales)\b/i.test(text);
  const mentionsCurrentOrDirectRequest = /\b(?:right now|now|at the moment|this moment|today|from here|in this chat|through this chat|ahora|en este momento|hoy|en este chat)\b/i.test(text)
    || /\b(?:can|could|would|are you able|is it possible|please|help me|i want you to|puedes|podrías|podrias|por favor|quiero que|ayúdame|ayudame)\b/i.test(text);
  return mentionsBlocking && mentionsTarget && mentionsCurrentOrDirectRequest;
}

function availabilityNoticeForPrompt(prompt, isFirstReply, user, noticeField, language = "en") {
  if (user[noticeField]) return [];
  if (isCapabilityRequest(prompt)) {
    return [spanishLanguage(language)
      ? "Esto sigue siendo una demo de acceso anticipado y estás en la lista de espera. La app completa estará disponible para descargar el 1 de octubre, y el bloqueo se hará desde la app."
      : CAPABILITY_NOTICE_MESSAGE];
  }
  return isFirstReply ? availabilityNoticeMessages(language) : [];
}

function naturalFallbackReply(prompt, history, language = "en", repeatRequest = false, repeatSourceReply = "") {
  const spanish = spanishLanguage(language);
  const text = cleanText(prompt, 4000).toLowerCase();
  if (repeatRequest) {
    if (!spanish) return repeatSourceReply ? `Here’s that last reply again: ${repeatSourceReply}` : "Sure, I’ll repeat my last reply.";
    if (/i['’]?ll reply in spanish|respond in spanish|won['’]?t change the setting/i.test(repeatSourceReply)) {
      return "Claro. A partir de ahora te responderé en castellano y no cambiaré ninguna configuración.";
    }
    return "Claro. Te repito la respuesta anterior en castellano.";
  }
  const hasSubstantiveInbound = history.some((message) =>
    message.direction === "inbound"
    && !/^(hi|hello|hey|hola)\b/i.test(cleanText(message.body, 4000))
  );
  const isOpening = /^(hi|hello|hey|hola)\b/.test(text) && !hasSubstantiveInbound;
  if (/^(hi|hello|hey|hola)\b/.test(text) && hasSubstantiveInbound) {
    return spanish ? "¡Hola! ¿Cómo te ha ido con el móvil desde la última vez que hablamos?" : "Hey! How’s it been with your phone since we last spoke?";
  }
  if (isOpening) {
    return spanish
      ? "Qué bien tenerte por aquí. ¿Qué suele pasar cuando empiezas a mirar el móvil? Puedes escribirlo o enviar una nota de voz."
      : "Hey, good to have you here. What usually happens when you start scrolling? You can write it out or send a voice note.";
  }
  if (/(wake|woke|morning|breakfast|first thing|8\s*am|40\s*(?:to|-)\s*45)/i.test(text)) {
    return spanish ? "Me interesa saber qué suele hacer que sigas mirando el móvil durante esos primeros 40 o 45 minutos antes de desayunar." : "I’m curious what usually keeps you scrolling during those first 40 or 45 minutes before breakfast.";
  }
  if (/(scroll|phone|instagram|tiktok|youtube|help me|want to stop)/i.test(text)) {
    return spanish ? "Me interesa saber qué acabas mirando normalmente cuando empiezas a desplazarte por el móvil." : "I’m curious what you usually end up looking at once you start scrolling.";
  }
  return spanish ? "Me interesa saber qué parte de ese momento hace que vuelvas al móvil." : "I’m curious what part of that moment keeps bringing you back to your phone.";
}

function noConsentReply(language = "en") {
  return spanishLanguage(language)
    ? `Puedo continuar cuando te unas a Blankmind Early Access y confirmes que puedo guardar esta conversación. Puedes hacerlo aquí: ${publicJoinUrl()}`
    : `I can continue once you join Blankmind Early Access and confirm that I can save this conversation. You can do that here: ${publicJoinUrl()}`;
}

function deletionIsPending(user) {
  const requestedAt = Date.parse(user?.deletion_requested_at || "");
  return Number.isFinite(requestedAt) && Date.now() - requestedAt <= 24 * 60 * 60 * 1000;
}

async function saveOutbound(user, provider, reply, kind = "text", providerMessageId = null, language = "en") {
  return recordMessage({
    userId: user.id,
    provider,
    providerMessageId,
    direction: "outbound",
    messageKind: kind,
    body: reply,
    sourceLanguage: language,
  });
}

async function saveOutboundReplies(user, provider, replies, language = "en") {
  for (const reply of replies) {
    await saveOutbound(user, provider, reply, "text", null, language);
  }
}

async function privacyReply({ user, provider, prompt, language = "en" }) {
  const spanish = spanishLanguage(language);
  if (STOP_COMMAND.test(prompt)) {
    await withdrawConsent(user);
    await recordEvent(user.id, "consent_withdrawn", { provider });
    return spanish ? "He detenido la conversación de Early Access y no guardaré nada más a partir de ahora." : "I’ve stopped the Early Access conversation and I won’t save anything else from here.";
  }
  if (DELETE_CONFIRMATION.test(prompt)) {
    if (!deletionIsPending(user)) {
      await patchUser(user.id, { deletion_requested_at: new Date().toISOString() });
      return spanish ? "Puedo borrar todo lo que he guardado sobre ti. Responde BORRAR otra vez en las próximas 24 horas para confirmarlo." : "I can delete everything I’ve saved about you. Reply DELETE once more within 24 hours to confirm.";
    }
    const userId = user.id;
    await deleteUserData(userId);
    return spanish ? "He borrado tu perfil de Early Access, tus mensajes y la información extraída." : "I’ve deleted your Early Access profile, messages, and extracted information.";
  }
  if (DELETE_REQUEST.test(prompt)) {
    await patchUser(user.id, { deletion_requested_at: new Date().toISOString() });
    await recordEvent(user.id, "deletion_requested", { provider });
    return spanish ? "Puedo borrar todo lo que he guardado sobre ti. Responde BORRAR en las próximas 24 horas para confirmarlo." : "I can delete everything I’ve saved about you. Reply DELETE within 24 hours to confirm.";
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
    return { reply: noConsentReply(detectedLanguage(message.text)), user: null, kind: "privacy", deliveryDeferred: deferDelivery };
  }

  try {
    const isFirstReply = !user.first_reply_at;
    let prompt = cleanText(message.text, 4000);
    let messageKind = "text";
    if (message.audio) {
      try {
        prompt = await transcribeAudio(message);
        messageKind = "audio_transcript";
        await recordEvent(user.id, "audio_transcribed", { provider: message.provider });
      } catch (error) {
        await recordEvent(user.id, "audio_transcription_failed", { provider: message.provider, reason: cleanText(error.message, 160) });
        const reply = spanishLanguage(detectedLanguage(message.text))
          ? "No he podido entender bien esa nota de voz. ¿Puedes enviarla otra vez o escribirlo aquí?"
          : "I couldn’t make out that voice note clearly. Could you send it again, or write it here instead?";
        if (!deferDelivery) {
          await saveOutbound(user, message.provider, reply, "text", null, detectedLanguage(message.text));
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
      const reply = spanishLanguage(detectedLanguage(message.text))
        ? "No he podido entender nada de ese mensaje. ¿Puedes intentarlo otra vez?"
        : "I didn’t catch anything in that message. Could you try again?";
      if (!deferDelivery) {
        await saveOutbound(user, message.provider, reply, "text", null, detectedLanguage(message.text));
        await completeInbound(message.provider, message.providerMessageId);
      }
      return { reply, user, kind: "text", deliveryDeferred: deferDelivery };
    }

    const previousHistory = await recentMessages(user.id);
    const language = detectedLanguage(prompt, previousHistory, user);
    const repeatRequest = isRepeatRequest(prompt);
    const privacy = await privacyReply({ user, provider: message.provider, prompt, language });
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
          sourceLanguage: language,
        });
        if (!deferDelivery) await saveOutbound(user, message.provider, privacy, "privacy", null, language);
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
      sourceLanguage: language,
    });
    user = await markFirstReply(user) || user;
    const [history, known] = await Promise.all([
      recentMessages(user.id),
      currentFacts(user.id),
    ]);
    let semanticContext = { message: prompt, history };
    if (language === "es") {
      try {
        semanticContext = await canonicalizeConversation({
          message: prompt,
          history,
          language,
        });
      } catch (error) {
        await recordEvent(user.id, "conversation_canonicalization_failed", {
          reason: cleanText(error.message, 160),
        });
      }
    }
    const repeatSourceReply = latestOutboundReply(semanticContext.history)
      || latestOutboundReply(previousHistory);

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
          language,
          repeatRequest,
          repeatSourceReply,
          semanticMessage: semanticContext.message,
          semanticHistory: semanticContext.history,
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
          reply: naturalFallbackReply(prompt, history, language, repeatRequest, repeatSourceReply),
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
          language,
          repeatRequest,
          repeatSourceReply,
          semanticMessage: semanticContext.message,
          semanticHistory: semanticContext.history,
        });
      } catch (error) {
        await recordEvent(user.id, "conversation_generation_failed", { reason: cleanText(error.message, 160) });
        generated = {
          reply: naturalFallbackReply(prompt, history, language, repeatRequest, repeatSourceReply),
          focus: "natural_followup",
          profile_useful: false,
          restricted: false,
        };
      }
    }

    if (message.audio) updated = await currentFacts(user.id);

    const channel = message.channel === "sms" ? "sms" : "whatsapp";
    const noticeField = availabilityNoticeField(channel);
    const noticeReplies = availabilityNoticeForPrompt(prompt, isFirstReply, user, noticeField, language);
    const replies = [generated.reply, ...noticeReplies];

    const completion = {
      provider: message.provider,
      input_kind: messageKind,
      language,
      facts_saved: saved.length,
      fact_keys: saved.map((fact) => fact.field_key),
      profile_fields: Object.keys(updated.profile),
      focus: generated.focus,
      conversation_goal_state: generated.goal_plan?.state || null,
      conversation_anchor_goal: generated.goal_plan?.anchor_goal || null,
      conversation_next_goal: generated.goal_plan?.next_goal || null,
      restricted_topic: generated.restricted === true,
      availability_notice: noticeReplies.length > 0,
      availability_notice_reason: isCapabilityRequest(prompt) ? "capability_request" : (noticeReplies.length > 0 ? "first_reply" : null),
    };
    if (!deferDelivery) {
      await saveOutboundReplies(user, message.provider, replies, language);
      if (noticeReplies.length === 2) {
        await patchUser(user.id, { [noticeField]: new Date().toISOString() });
        await recordEvent(user.id, "waitlist_availability_notice_sent", {
          channel,
          message_count: noticeReplies.length,
        });
      }
      await Promise.all([
        recordEvent(user.id, "waitlist_turn_completed", completion),
        completeInbound(message.provider, message.providerMessageId),
      ]);
    }
    return {
      reply: generated.reply,
      replies,
      availabilityNotice: noticeReplies,
      availabilityNoticeField: noticeReplies.length > 0 ? noticeField : null,
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
  return twimlResponse(result.replies || result.reply || "");
}

async function handleMeta(event) {
  if (!verifyMetaSignature(event)) return json(403, { error: "invalid_whatsapp_signature" });
  const body = parseJsonBody(event);
  if (!body || typeof body !== "object" || Array.isArray(body)) return json(400, { error: "invalid_whatsapp_payload" });
  const messages = parseMetaMessages(body).slice(0, 5);
  const results = [];
  for (const message of messages) {
    const result = await processMessage(message);
    const replies = result.replies || (result.reply ? [result.reply] : []);
    for (const reply of replies) {
      if (reply) {
        const delivery = await sendMetaText(message.phone, reply);
        if (result.user) {
          await recordEvent(result.user.id, "waitlist_reply_delivered", { provider: "meta", provider_message_id: delivery.id });
        }
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
module.exports.isCapabilityRequest = isCapabilityRequest;
module.exports.availabilityNoticeForPrompt = availabilityNoticeForPrompt;
module.exports.detectedLanguage = detectedLanguage;
module.exports.isRepeatRequest = isRepeatRequest;
