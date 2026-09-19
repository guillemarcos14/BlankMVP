"use strict";

const assert = require("assert");
const { DEFAULT_MODEL, buildJudgeInput, digest, flattenReport, functionalFailures, judgeTurn, oracleReviews, reviewDigest, summarize } = require("./bm_sol_quality_judge");

async function run() {
  let requestBody = null;
  let requestCount = 0;
  const fetchImpl = async (_url, options) => {
    requestCount += 1;
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
  assert.strictEqual(requestBody.max_output_tokens, 900);
  assert.strictEqual(requestCount, 1);
  assert.strictEqual(review.verdict, "excellent");
  assert.strictEqual(digest({ a: 1 }), digest({ a: 1 }));
  assert.notStrictEqual(reviewDigest({ input: "x" }), reviewDigest({ input: "x" }, [], "another-model"));
  assert.strictEqual(summarize([{ review }]).release_eligible, true);
  const unsafe = { ...review, verdict: "acceptable", unsafe_claim: true };
  assert.strictEqual(summarize([{ review: unsafe }]).release_eligible, false);
  const binding = { response_sha256: "a".repeat(64), expectation_sha256: "b".repeat(64) };
  assert.deepStrictEqual(oracleReviews([{ review, review_binding: binding, language: "en" }])[0], {
    ...binding,
    reviewer: "gpt-5.6-sol:low",
    rationale: review.rationale,
    verdict: "equivalent",
    language: "en",
  });
  assert.strictEqual(oracleReviews([{ review: unsafe, review_binding: binding, language: "en" }])[0].verdict, "not_equivalent");
  const appInput = buildJudgeInput({ trace: { context: { has_selected_apps: true, selected_app_names: ["Instagram"] } } });
  assert.deepStrictEqual(appInput.app_context.selected_app_names, ["Instagram"]);
  const remoteInput = buildJudgeInput({ actual: { visible: "Tap the notification.", actions: [] } });
  assert.strictEqual(remoteInput.app_context.has_selected_apps, null);
  assert.strictEqual(remoteInput.app_context.selected_app_names, null);
  const replayInput = buildJudgeInput({ evaluation_context: { has_selected_apps: true, selected_app_names: ["Instagram"] } });
  assert.strictEqual(replayInput.app_context.has_selected_apps, true);
  assert.deepStrictEqual(replayInput.app_context.selected_app_names, ["Instagram"]);
  const flattened = flattenReport({ runs: [{ id: "replay", channel: "sms", turns: [
    { turn: 1, input: "Do it", actual: { visible: "Tap the notification.", actions: [{ type: "start_protection" }] } },
    { turn: 2, input: "Yes", actual: { visible: "It is already waiting.", actions: [] } },
  ] }] });
  assert.deepStrictEqual(flattened[1].history[1].emitted_actions, [{ type: "start_protection" }]);
  assert.strictEqual(functionalFailures([{ dimensions: { intent: "passed", slots: "passed", transition: "passed", provenance: "passed", decision: "passed", actions: "passed", safety: "passed", visible_equivalence: "unverified" } }]).length, 0);
  assert.strictEqual(functionalFailures([{ dimensions: { intent: "passed", slots: "failed" } }]).length, 1);

  let retryCount = 0;
  const retryReview = await judgeTurn({ input: "Move it later", actual: { visible: "Done." } }, [], {
    apiKey: "test",
    fetchImpl: async () => {
      retryCount += 1;
      return {
        ok: true,
        json: async () => retryCount === 1
          ? { status: "incomplete", incomplete_details: { reason: "max_output_tokens" }, output_text: '{"verdict":"excellent"' }
          : { model: DEFAULT_MODEL, status: "completed", output_text: JSON.stringify({ ...review, model_requested: undefined, model_returned: undefined, reasoning_effort: undefined }) },
      };
    },
  });
  assert.strictEqual(retryCount, 2);
  assert.strictEqual(retryReview.verdict, "excellent");
  console.log("BM Sol quality judge tests passed");
}

run().catch(error => { console.error(error); process.exitCode = 1; });
