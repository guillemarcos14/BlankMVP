const assert = require("assert");

const previousKey = process.env.OPENAI_API_KEY;
const previousFetch = global.fetch;
process.env.OPENAI_API_KEY = "test-key";
const requests = [];
global.fetch = async (url, options = {}) => {
  assert.strictEqual(String(url), "https://api.openai.com/v1/responses");
  const request = JSON.parse(options.body);
  assert.ok(Array.isArray(request.input) && request.input.length > 0);
  for (const [index, item] of request.input.entries()) {
    assert.ok(typeof item.content === "string" && item.content.length > 0, `input[${index}].content missing`);
  }
  requests.push(request);
  const text = request.text?.format?.name === "blanked_agent_response"
    ? JSON.stringify({ plan: { intent: "general", response_text: "What time does the scrolling usually begin?", message_text: "What time does the scrolling usually begin?", actions: [] } })
    : "Hola, ¿cómo estás?";
  return {
    ok: true,
    status: 200,
    json: async () => ({ output: [{ content: [{ type: "output_text", text }] }] }),
    text: async () => JSON.stringify({ output: [{ content: [{ type: "output_text", text }] }] }),
  };
};

async function main() {
  const agent = require("../netlify/functions/blanked-agent");
  const greeting = await agent.handler({
    httpMethod: "POST",
    body: JSON.stringify({ prompt: "Hola", context: { channel: "whatsapp", assistant_channel: "whatsapp" } }),
  });
  assert.strictEqual(greeting.statusCode, 200, greeting.body);
  const greetingBody = JSON.parse(greeting.body);
  assert.match(greetingBody.source, /^openai:/);
  assert.ok(requests.some((request) => !request.text));

  await agent._evaluation.traceTurn({
    prompt: "How can I stop scrolling at night?",
    context: { channel: "whatsapp", assistant_channel: "whatsapp" },
    mode: "bm_raw",
  });
  assert.ok(requests.some((request) => request.text?.format?.name === "blanked_agent_response"));
  process.stdout.write("BM OpenAI request contract tests passed\n");
}

main().catch((error) => { console.error(error); process.exitCode = 1; }).finally(() => {
  if (previousKey === undefined) delete process.env.OPENAI_API_KEY; else process.env.OPENAI_API_KEY = previousKey;
  global.fetch = previousFetch;
});
