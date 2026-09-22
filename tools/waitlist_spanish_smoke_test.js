const assert = require("assert");

process.env.OPENAI_API_KEY = "openai-test";
process.env.WAITLIST_CONVERSATION_POLISH = "false";

const {
  canonicalizeConversation,
  generateReply,
  naturalGoalPlan,
  replyQualityIssues,
} = require("../netlify/functions/_waitlist_ai");
const {
  detectedLanguage,
  isRepeatRequest,
  naturalFallbackReply,
} = require("../netlify/functions/waitlist-agent");

function response(body) {
  const text = JSON.stringify(body);
  return {
    ok: true,
    status: 200,
    text: async () => text,
    json: async () => body,
  };
}

async function main() {
  const canonicalRequests = [];
  const canonical = await canonicalizeConversation({
    message: "Me levanto y miro el móvil antes de desayunar.",
    history: [{ direction: "inbound", body: "Suelo hacerlo durante unos cuarenta minutos." }],
    language: "es",
    fetchImpl: async (url, options) => {
      canonicalRequests.push(JSON.parse(options.body));
      return response({
        output_text: JSON.stringify({
          latest_message_en: "I wake up and look at my phone before breakfast.",
          history_en: [{ direction: "inbound", body: "I usually do it for about forty minutes." }],
        }),
      });
    },
  });
  assert.strictEqual(canonical.message, "I wake up and look at my phone before breakfast.");
  assert.strictEqual(canonical.history[0].body, "I usually do it for about forty minutes.");
  assert.match(canonicalRequests[0].input[0].content[0].text, /faithful canonical English/i);
  assert.deepStrictEqual(
    naturalGoalPlan({ message: canonical.message, history: canonical.history, profile: {}, newlySavedFacts: [] }),
    naturalGoalPlan({ message: "I wake up and look at my phone before breakfast.", history: canonical.history, profile: {}, newlySavedFacts: [] }),
  );

  assert.strictEqual(detectedLanguage("A partir de ahora quiero hablar contigo en castellano."), "es");
  assert.strictEqual(detectedLanguage("En castellano, por favor, ¿puedes repetir tu última respuesta?"), "es");
  assert.strictEqual(isRepeatRequest("En castellano, por favor, ¿puedes repetir tu última respuesta?"), true);
  assert.match(naturalFallbackReply("No sé qué hacer.", [], "es"), /interesa|móvil/i);
  assert.deepStrictEqual(
    replyQualityIssues("Entiendo. Te responderé en castellano a partir de ahora.", { language: "es" }),
    [],
  );

  const requests = [];
  const spanishReply = await generateReply({
    message: "A partir de ahora quiero hablar contigo en castellano.",
    history: [],
    profile: {},
    newlySavedFacts: [],
    language: "es",
    fetchImpl: async (url, options) => {
      requests.push(JSON.parse(options.body));
      const system = JSON.parse(options.body).input[0].content[0].text;
      return response({
        output_text: JSON.stringify({
          reply: /Translate the canonical assistant reply/i.test(system)
            ? "Entendido. Te responderé en castellano a partir de ahora."
            : "I understand. I will reply in Spanish from now on.",
          focus: "language_preference",
          profile_useful: false,
        }),
      });
    },
  });
  assert.strictEqual(spanishReply.reply, "Entendido. Te responderé en castellano a partir de ahora.");
  assert.match(requests[0].input[0].content[0].text, /canonical reply in relaxed everyday English/i);
  assert.match(requests[0].input[0].content[0].text, /present that same reply in Spanish/i);
  assert.match(requests[0].input[1].content[0].text, /"language":"es"/);

  requests.length = 0;
  const repeatReply = await generateReply({
    message: "En castellano, por favor, ¿puedes repetir tu última respuesta?",
    history: [{ direction: "outbound", body: "I will reply in Spanish from now on." }],
    profile: {},
    newlySavedFacts: [],
    language: "es",
    repeatRequest: true,
    repeatSourceReply: "I will reply in Spanish from now on.",
    fetchImpl: async (url, options) => {
      requests.push(JSON.parse(options.body));
      const system = JSON.parse(options.body).input[0].content[0].text;
      return response({
        output_text: JSON.stringify({
          reply: /Translate the canonical assistant reply/i.test(system)
            ? "Claro. Te responderé en castellano a partir de ahora."
            : "I will reply in Spanish from now on.",
          focus: "repeat_response",
          profile_useful: false,
        }),
      });
    },
  });
  assert.strictEqual(repeatReply.reply, "Claro. Te responderé en castellano a partir de ahora.");
  assert.match(requests[0].input[0].content[0].text, /explicit request to repeat/i);
  assert.doesNotMatch(repeatReply.reply, /\?/);

  requests.length = 0;
  const directQuestionReply = await generateReply({
    message: "¿Qué información tienes sobre mí para ampliar el contexto?",
    history: [],
    profile: { preferred_name: "Guillem", apps: ["Instagram"] },
    newlySavedFacts: [],
    language: "es",
    fetchImpl: async (url, options) => {
      requests.push(JSON.parse(options.body));
      const system = JSON.parse(options.body).input[0].content[0].text;
      if (/Translate the canonical assistant reply/i.test(system)) {
        return response({
          output_text: JSON.stringify({
            reply: "Ahora mismo tengo tu nombre, Guillem, y que usas Instagram. Si quieres, puedes contarme algo más sobre tu rutina.",
            focus: "identity",
            profile_useful: false,
          }),
        });
      }
      return response({
        output_text: JSON.stringify({
          reply: "Right now I have your name, Guillem, and that you use Instagram. If you want, you can tell me a little more about your routine.",
          focus: "identity",
          profile_useful: false,
        }),
      });
    },
  });
  assert.match(directQuestionReply.reply, /Guillem|Instagram/i);
  assert.strictEqual(requests.length, 2);
  assert.match(requests[0].input[0].content[0].text, /internal canonical reply in relaxed everyday English/i);
  assert.match(requests[0].input[0].content[0].text, /direct question about what you know/i);
  assert.match(requests[1].input[0].content[0].text, /Translate the canonical assistant reply into Spanish/i);

  const parityBodies = { en: [], es: [] };
  const sharedSemanticHistory = [{ direction: "inbound", body: "I usually scroll for about forty minutes before breakfast." }];
  const sharedProfile = { preferred_name: "Guillem", scroll_moments: ["before breakfast"] };
  const parityReply = {
    reply: "I understand. I am curious what usually keeps you scrolling before breakfast?",
    focus: "scroll_context",
    profile_useful: false,
  };
  await generateReply({
    message: "I usually scroll for about forty minutes before breakfast.",
    semanticMessage: "I usually scroll for about forty minutes before breakfast.",
    semanticHistory: sharedSemanticHistory,
    history: sharedSemanticHistory,
    profile: sharedProfile,
    newlySavedFacts: [],
    language: "en",
    fetchImpl: async (url, options) => {
      parityBodies.en.push(JSON.parse(options.body));
      return response({ output_text: JSON.stringify(parityReply) });
    },
  });
  await generateReply({
    message: "Suelo mirar el móvil unos cuarenta minutos antes de desayunar.",
    semanticMessage: "I usually scroll for about forty minutes before breakfast.",
    semanticHistory: sharedSemanticHistory,
    history: sharedSemanticHistory,
    profile: sharedProfile,
    newlySavedFacts: [],
    language: "es",
    fetchImpl: async (url, options) => {
      parityBodies.es.push(JSON.parse(options.body));
      const system = JSON.parse(options.body).input[0].content[0].text;
      return response({
        output_text: JSON.stringify(system.startsWith("Translate the canonical assistant reply")
          ? { reply: "Entiendo. Me interesa saber qué suele hacer que sigas mirando el móvil antes de desayunar.", focus: "scroll_context", profile_useful: false }
          : parityReply),
      });
    },
  });
  const enInput = JSON.parse(parityBodies.en[0].input[1].content[0].text);
  const esInput = JSON.parse(parityBodies.es[0].input[1].content[0].text);
  for (const key of [
    "latest_message",
    "recent_history",
    "known_profile",
    "newly_saved_facts",
    "coverage",
    "natural_goal_plan",
    "conversation_reentry",
    "question_memory",
    "restricted_topic_present",
    "repeat_request",
    "canonical_output_language",
  ]) {
    assert.deepStrictEqual(esInput[key], enInput[key], `shared context diverged at ${key}`);
  }
  assert.strictEqual(enInput.target_language, "English");
  assert.strictEqual(esInput.target_language, "Spanish");

  console.log("waitlist Spanish smoke tests passed");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
