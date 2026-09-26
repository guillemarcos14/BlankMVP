"use strict";
const assert = require("node:assert/strict");
const { extractWithModel, parseCandidate, schema } = require("../netlify/functions/bm-semantic-extraction");
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
    for (const key of ["duration_minutes", "schedule_horizon_days"]) {
      const valueSchema=schema.properties.fields.items.anyOf.find(item=>item.properties.slot.enum[0]===key).properties.value;
      assert.deepEqual(valueSchema,{type:"integer"},"extraction represents unsupported quantities; action limits stay downstream");
    }
    const unsupportedPrompt="Block selected apps from 10am to 11am weekdays for 40 days.";
    const unsupported=await extractWithModel({prompt:unsupportedPrompt,fetchImpl:async()=>({ok:true,json:async()=>bodyFor([field("schedule_horizon_days",40,"40 days")])})});
    assert.equal(unsupported.extraction.set.schedule_horizon_days,40);
    assert.deepEqual(unsupported.rejected,[{slot:"schedule_horizon_days",code:"ungrounded_model_fact"}]);
    const unsupportedResult=advanceSemanticState({prompt:unsupportedPrompt,extraction:unsupported.extraction});
    assert.deepEqual(unsupportedResult.actions,[]);
    assert.equal(unsupportedResult.decision.slot,"schedule_horizon_days");
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
    let retryCalls = 0;
    const repaired = await extractWithModel({ prompt: "45 minutes", previousState:first.state,
      fetchImpl: async (_url, options) => {
        retryCalls++;
        if (retryCalls === 2) assert.match(JSON.parse(options.body).input.at(-1).content,/repeated a slot/);
        return { ok:true, json:async()=>bodyFor(retryCalls === 1
          ? [field("duration_minutes",30,"45 minutes"),field("duration_minutes",45,"45 minutes")]
          : [field("duration_minutes",45,"45 minutes")]) };
      } });
    assert.equal(retryCalls,2); assert.equal(repaired.extraction.set.duration_minutes,45);
    assert.deepEqual(repaired.attempt_errors,["duplicate_semantic_extraction_slot"]);
    assert.deepEqual(repaired.trace.attempt_errors,repaired.attempt_errors);
    let failedCalls=0;
    await assert.rejects(()=>extractWithModel({prompt:"45 minutes",fetchImpl:async()=>{
      failedCalls++; return {ok:true,json:async()=>bodyFor([field("duration_minutes",30,"45 minutes"),field("duration_minutes",45,"45 minutes")])};
    }}),error=>{
      assert.match(error.message,/duplicate/); assert.equal(error.semantic_attempt_count,2);
      assert.deepEqual(error.semantic_attempt_errors,["duplicate_semantic_extraction_slot","duplicate_semantic_extraction_slot"]);return true;
    });
    assert.equal(failedCalls,2,"malformed extraction retry is bounded");
    const realNow=Date.now, realTimeout=AbortSignal.timeout;
    const budgets=[]; let elapsed=0;
    try {
      Date.now=()=>100000+elapsed;
      AbortSignal.timeout=(milliseconds)=>{budgets.push(milliseconds);return new AbortController().signal;};
      await extractWithModel({prompt:"45 minutes",fetchImpl:async()=>{
        const firstAttempt=elapsed===0; elapsed+=5000;
        return {ok:true,json:async()=>bodyFor(firstAttempt
          ? [field("duration_minutes",30,"45 minutes"),field("duration_minutes",45,"45 minutes")]
          : [field("duration_minutes",45,"45 minutes")])};
      }});
      assert.deepEqual(budgets,[12000,12000],"each attempt is bounded within the shared20-second deadline");
    } finally { Date.now=realNow; AbortSignal.timeout=realTimeout; }
    let timeoutCalls=0;
    await assert.rejects(()=>extractWithModel({prompt:"yes",fetchImpl:async()=>{
      timeoutCalls++; const error=new Error("timed out");error.name="TimeoutError";throw error;
    }}),{name:"TimeoutError"});
    assert.equal(timeoutCalls,2,"a transient timeout gets one retry inside the same deadline");
    let incompleteCalls=0;
    const recovered=await extractWithModel({prompt:"45 minutes",fetchImpl:async(_url,options)=>{
      incompleteCalls++; const candidateRequest=JSON.parse(options.body);
      if(incompleteCalls===1) return {ok:true,json:async()=>({status:"incomplete",incomplete_details:{reason:"max_output_tokens"}})};
      assert.equal(candidateRequest.max_output_tokens,1400);
      return {ok:true,json:async()=>bodyFor([field("duration_minutes",45,"45 minutes")])};
    }});
    assert.deepEqual(recovered.attempt_errors,["semantic_model_incomplete"]);
    assert.equal(recovered.attempt_count,2);
    const timeoutBudgets=[]; let timeoutElapsed=0, boundedCalls=0;
    try {
      Date.now=()=>100000+timeoutElapsed;
      AbortSignal.timeout=(milliseconds)=>{timeoutBudgets.push(milliseconds);return new AbortController().signal;};
      const bounded=await extractWithModel({prompt:"45 minutes",fetchImpl:async()=>{
        boundedCalls++;
        if(boundedCalls===1){timeoutElapsed+=12000;const error=new Error("timeout");error.name="TimeoutError";throw error;}
        return {ok:true,json:async()=>bodyFor([field("duration_minutes",45,"45 minutes")])};
      }});
      assert.deepEqual(timeoutBudgets,[12000,8000]);
      assert.deepEqual(bounded.attempt_errors,["semantic_model_timeout"]);
    } finally { Date.now=realNow; AbortSignal.timeout=realTimeout; }
    let authCalls=0;
    await assert.rejects(()=>extractWithModel({prompt:"yes",fetchImpl:async()=>{authCalls++;return {ok:false,status:401};}}),/semantic_model_http_401/);
    assert.equal(authCalls,1,"authentication failure must not trigger repeated requests");
    await assert.rejects(() => extractWithModel({ prompt: "yes", fetchImpl: async () => ({ ok: false, status: 503 }) }), /semantic_model_http_503/);
    await assert.rejects(() => extractWithModel({ prompt: "yes", fetchImpl: async () => ({ ok: true, json: async () => ({ status: "incomplete" }) }) }), /semantic_model_incomplete/);
    console.log("semantic extraction: evidence, hostile fields, authority, duplicate/schema and API failure checks passed");
  } finally {
    if (oldKey === undefined) delete process.env.OPENAI_API_KEY;
    else process.env.OPENAI_API_KEY = oldKey;
  }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
