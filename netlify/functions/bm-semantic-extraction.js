"use strict";

// The model extracts evidence. It cannot emit actions or authorize a proposal.
const { validateSemanticPatch } = require("./bm-semantic-state");
const object = properties => ({ type: "object", additionalProperties: false, required: Object.keys(properties), properties });
const values = {
  apps: { type: "array", minItems: 1, maxItems: 12, items: { type: "string", minLength: 1, maxLength: 80 } },
  app_category: { type: "string", minLength: 1, maxLength: 179 },
  moment: { type: "string", minLength: 1, maxLength: 179 },
  action_type: { type: "string", enum: ["strict_block", "daily_limit"] },
  hard_mode: { type: "boolean" },
  start: { anyOf: [object({ type: { type: "string", enum: ["now"] } }), object({ type: { type: "string", enum: ["time"] }, minute: { type: "integer", minimum: 0, maximum: 1439 } })] },
  end: { type: "integer", minimum: 0, maximum: 1439 },
  // Evidence must be able to represent an unsupported request verbatim. Native
  // limits belong to validateSemanticPatch/reducer/action gates; constraining
  // extraction to 1–14 made a request for 40 days impossible to express.
  duration_minutes: { type: "integer" },
  schedule_horizon_days: { type: "integer" },
  recurrence: object({ type: { type: "string", enum: ["once", "daily", "weekly"] }, weekdays: { type: "array", maxItems: 7, items: { type: "integer", minimum: 1, maximum: 7 } } }),
};
const schema = {
  type: "object", additionalProperties: false,
  required: ["fields", "ambiguities"],
  properties: {
    // Each slot has its real JSON type. There is no second JSON document hidden
    // inside a string, so an ordinary value such as "mornings" needs no re-parse.
    fields: { type: "array", maxItems: 10, items: { anyOf: Object.entries(values).map(([slot, value]) => object({
      slot: { type: "string", enum: [slot] }, value, evidence: { type: "string", maxLength: 600 },
    })) } },
    ambiguities: { type: "array", maxItems: 8, items: { type: "string", maxLength: 100 } },
  },
};

function requestFor(prompt, state, context = {}) {
  const facts = state ? Object.fromEntries(Object.entries(state.slots || {}).map(([key, slot]) => [key, slot?.value ?? null])) : {};
  return {
    model: process.env.OPENAI_MODEL || "gpt-5.6-luna",
    input: [
      { role: "system", content: "Extract only facts asserted or corrected in the current user message. Prior state and conversation explain ellipsis but are not new evidence. Each evidence must be an exact substring of the current message. Do not invent missing values. Do not choose between ambiguous alternatives. Do not output actions or confirmation. Values are JSON: apps=[names], moment=string, app_category=string, action_type=strict_block|daily_limit, start={type:now} or {type:time,minute:0..1439}, end=minute integer, duration_minutes=integer, recurrence={type:once|daily|weekly,weekdays:[1=Monday..7=Sunday]}. Duration and clock time are different fields. Unknown values are omitted. A correction replaces the old value." },
      { role: "user", content: JSON.stringify({ current_message: prompt, previous: { intent: state?.intent || "general", facts, next_question: state?.next_question || null }, recent_messages: (context.recent_messages || []).filter(message => ["user", "assistant"].includes(message.role)).slice(-8) }) },
    ],
    text: { format: { type: "json_schema", name: "bm_semantic_evidence", strict: true, schema } },
    max_output_tokens: 700,
  };
}

function parseCandidate(body, prompt) {
  const text = body.output_text || (body.output || []).flatMap(item => item.content || []).map(item => item.type === "output_text" ? item.text : "").join("");
  const parsed = JSON.parse(text);
  if (!Array.isArray(parsed.fields) || parsed.fields.length > 10 || !Array.isArray(parsed.ambiguities)) throw new Error("invalid_semantic_extraction_shape");
  const candidate = { set: {}, evidence: {} };
  for (const field of parsed.fields) {
    if (!field || !Object.hasOwn(values, field.slot)) throw new Error("invalid_semantic_extraction_slot");
    if (!Object.hasOwn(field, "value") || Object.keys(field).some(key => !["slot", "value", "evidence"].includes(key))) throw new Error("invalid_semantic_extraction_field");
    if (Object.hasOwn(candidate.set, field.slot)) throw new Error("duplicate_semantic_extraction_slot");
    if (typeof field.evidence !== "string" || !field.evidence.trim() || !prompt.includes(field.evidence)) throw new Error("ungrounded_semantic_extraction_evidence");
    candidate.set[field.slot] = field.value;
    candidate.evidence[field.slot] = field.evidence;
  }
  return { candidate, ambiguities: parsed.ambiguities };
}

async function extractWithModel({ prompt, previousState, context = {}, fetchImpl = fetch }) {
  if (!process.env.OPENAI_API_KEY) return { enabled: false, extraction: null, source: "deterministic_semantic_extraction" };
  const request = requestFor(prompt, previousState, context);
  request.input[0].content += " Return each slot at most once. If alternatives conflict, omit that slot and report the ambiguity. Quantities describing a past event are observations, not requested future action parameters. Copy requested quantities exactly, including unsupported values: never clamp, truncate or replace them to fit device capabilities. The separate action validator decides what the device supports.";
  const deadline = Date.now() + 20000;
  const attemptErrors = [];
  for (let attempt = 1; attempt <= 2; attempt++) {
    try {
      // Both attempts share the original 20-second extraction budget. A retry
      // cannot consume a second timeout window or exhaust the app turn lease.
      const response = await fetchImpl("https://api.openai.com/v1/responses", {
        method: "POST", headers: { authorization: `Bearer ${process.env.OPENAI_API_KEY}`, "content-type": "application/json" },
        body: JSON.stringify(request), signal: AbortSignal.timeout(Math.max(1, Math.min(12000, deadline - Date.now()))),
      });
      if (!response.ok) throw new Error(`semantic_model_http_${response.status}`);
      const body = await response.json();
      if (body.status === "incomplete") throw new Error("semantic_model_incomplete");
      const { candidate, ambiguities } = parseCandidate(body, prompt);
      const validation = validateSemanticPatch(candidate, { prompt, state: previousState, context });
      return { enabled: true, extraction: candidate, source: `openai:${body.model || request.model}:semantic`,
        model_requested: request.model, model_returned: body.model || null, rejected: validation.rejected, ambiguities,
        attempt_count: attempt, attempt_errors: attemptErrors,
        trace: { request, candidate, validation, attempt_count: attempt, attempt_errors: attemptErrors } };
    } catch (error) {
      attemptErrors.push(error.name === "TimeoutError" ? "semantic_model_timeout" : error.message);
      // Extraction has no side effects. One bounded retry can recover malformed
      // output or a transient model request, without hiding either attempt or
      // allowing a second 20-second timeout window. Auth/quota failures fail fast.
      const retryable = error.name === "TimeoutError"
        || ["duplicate_semantic_extraction_slot", "semantic_model_incomplete", "semantic_model_http_502", "semantic_model_http_503", "semantic_model_http_504"].includes(error.message);
      if (attempt !== 1 || !retryable || deadline - Date.now() < 1000) {
        error.semantic_attempt_count = attempt;
        error.semantic_attempt_errors = [...attemptErrors];
        throw error;
      }
      if (error.message === "duplicate_semantic_extraction_slot") request.input.push({ role: "system", content: "The previous extraction repeated a slot and was rejected. Return at most one entry per slot. Omit conflicting alternatives; report their ambiguity instead." });
      if (error.message === "semantic_model_incomplete") request.max_output_tokens = 1400;
    }
  }
}

module.exports = { extractWithModel, requestFor, parseCandidate, schema };
