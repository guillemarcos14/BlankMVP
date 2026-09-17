"use strict";
const assert = require("node:assert/strict");
const { extractWithModel, parseCandidate } = require("../netlify/functions/bm-semantic-extraction");
const { advanceSemanticState } = require("../netlify/functions/bm-semantic-state");

const bodyFor = fields => ({ model: "gpt-5.6-luna", status: "completed", output_text: JSON.stringify({ fields, ambiguities: [] }) });
const field = (slot, value, evidence) => ({ slot, value, evidence });

(async () => {
  const oldKey = process.env.OPENAI_API_KEY;
  process.env.OPENAI_API_KEY = "test-key-never-sent";
  try {
    const first = advanceSemanticState({ prompt: "Block Instagram now for 30 minutes" });
    let request;
    const extracted = await extractWithModel({
      prompt: "Just once", previousState: first.state,
      fetchImpl: async (_url, options) => { request = JSON.parse(options.body); return { ok: true, json: async () => bodyFor([field("recurrence", { type: "once", weekdays: [] }, "Just once")]) }; },
    });
    assert.equal(extracted.model_returned, "gpt-5.6-luna");
    assert.ok(!request.text.format.schema.properties.actions, "extractor cannot return executable actions");
    const accepted = advanceSemanticState({ prompt: "Just once", previousState: first.state, extraction: extracted.extraction });
    assert.equal(accepted.state.slots.recurrence.value.type, "once");
    assert.deepEqual(accepted.actions, [{ type:"start_protection", minutes:30, hard_mode:false }], "the user's final fact authorizes the explicit activation request");

    const hostile = await extractWithModel({ prompt: "45 minutes", previousState: first.state, fetchImpl: async () => ({ ok: true, json: async () => bodyFor([field("duration_minutes", 5, "45 minutes"), field("apps", ["TikTok"], "45 minutes")]) }) });
    const safe = advanceSemanticState({ prompt: "45 minutes", previousState: first.state, extraction: hostile.extraction });
    assert.equal(safe.state.slots.duration_minutes.value, 45);
    assert.deepEqual(safe.state.slots.apps.value, ["Instagram"]);
    assert.equal(hostile.rejected.length, 2, "wrong duration and unrelated app are rejected");
    assert.deepEqual(safe.actions, []);

    const morning = parseCandidate(bodyFor([field("moment", "mornings", "mornings")]), "I want to scroll less in the mornings");
    assert.equal(morning.candidate.set.moment, "mornings", "a native string must never be reparsed as a JSON document");
    assert.equal(parseCandidate(bodyFor([field("duration_minutes", 45, "45 minutes")]), "45 minutes").candidate.set.duration_minutes, 45);
    assert.deepEqual(parseCandidate(bodyFor([field("apps", ["Instagram"], "Instagram")]), "Instagram").candidate.set.apps, ["Instagram"]);
    assert.throws(() => parseCandidate(bodyFor([{slot:"moment",value_json:"mornings",evidence:"mornings"}]), "mornings"), /invalid_semantic_extraction_field/);

    assert.throws(() => parseCandidate(bodyFor([field("start", { type: "time", minute: 600 }, "10am")]), "11am"), /ungrounded/);
    assert.throws(() => parseCandidate(bodyFor([field("confirmation", true, "yes")]), "yes"), /invalid_semantic_extraction_slot/);
    assert.throws(() => parseCandidate(bodyFor([field("end", 600, "10am"), field("end", 660, "10am")]), "10am"), /duplicate/);
    await assert.rejects(() => extractWithModel({ prompt: "yes", fetchImpl: async () => ({ ok: false, status: 503 }) }), /semantic_model_http_503/);
    await assert.rejects(() => extractWithModel({ prompt: "yes", fetchImpl: async () => ({ ok: true, json: async () => ({ status: "incomplete" }) }) }), /semantic_model_incomplete/);
    console.log("semantic extraction: evidence, hostile fields, authority, duplicate/schema and API failure checks passed");
  } finally {
    if (oldKey === undefined) delete process.env.OPENAI_API_KEY;
    else process.env.OPENAI_API_KEY = oldKey;
  }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
