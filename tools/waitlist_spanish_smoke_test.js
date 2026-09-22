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
      return response({
        output_text: JSON.stringify({
          reply: "Entendido. Te responderé en castellano a partir de ahora.",
          focus: "language_preference",
          profile_useful: false,
        }),
      });
    },
  });
  assert.strictEqual(spanishReply.reply, "Entendido. Te responderé en castellano a partir de ahora.");
  assert.match(requests[0].input[0].content[0].text, /only in Spanish/i);
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
      return response({
        output_text: JSON.stringify({
          reply: "Claro. Te responderé en castellano a partir de ahora.",
          focus: "repeat_response",
          profile_useful: false,
        }),
      });
    },
  });
  assert.strictEqual(repeatReply.reply, "Claro. Te responderé en castellano a partir de ahora.");
  assert.match(requests[0].input[0].content[0].text, /explicit request to repeat/i);
  assert.doesNotMatch(repeatReply.reply, /\?/);

  console.log("waitlist Spanish smoke tests passed");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
