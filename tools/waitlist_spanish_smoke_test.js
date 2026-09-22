const assert = require("assert");

process.env.OPENAI_API_KEY = "openai-test";
process.env.WAITLIST_CONVERSATION_POLISH = "false";

const {
  generateReply,
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

  console.log("waitlist Spanish smoke tests passed");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
