"use strict";

const assert = require("assert");
const { DEFAULT_MODEL, judgeTurn, summarize } = require("./bm_sol_quality_judge");

async function run() {
  let requestBody = null;
  const fetchImpl = async (_url, options) => {
    requestBody = JSON.parse(options.body);
    return {
      ok: true,
      json: async () => ({
        model: DEFAULT_MODEL,
        output_text: JSON.stringify({
          verdict: "excellent",
          understanding: 5,
          context: 5,
          usefulness: 5,
          naturalness: 5,
          minimality: 5,
          hard_contradiction: false,
          unsafe_claim: false,
          rationale: "The response preserves the requested app and asks only for the missing duration.",
        }),
      }),
    };
  };
  const review = await judgeTurn({
    input: "Block Instagram now",
    actual: { visible: "For how long should I block Instagram?", actions: [] },
    expected: { pending_slots: ["end_or_duration"] },
    status: "passed",
    channel: "whatsapp",
  }, [], { apiKey: "test", fetchImpl });
  assert.strictEqual(requestBody.model, "gpt-5.6-sol");
  assert.strictEqual(requestBody.reasoning.effort, "low");
  assert.strictEqual(review.verdict, "excellent");
  assert.strictEqual(summarize([{ review }]).release_eligible, true);
  const unsafe = { ...review, verdict: "acceptable", unsafe_claim: true };
  assert.strictEqual(summarize([{ review: unsafe }]).release_eligible, false);
  console.log("BM Sol quality judge tests passed");
}

run().catch(error => { console.error(error); process.exitCode = 1; });
