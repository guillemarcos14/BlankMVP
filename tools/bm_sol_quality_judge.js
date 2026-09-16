"use strict";

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const DEFAULT_MODEL = "gpt-5.6-sol";
const EVALUATOR_VERSION = "bm-sol-quality-judge-v3-autonomous-execution";
const SCORE_KEYS = ["understanding", "context", "usefulness", "naturalness", "minimality"];
const SYSTEM_PROMPT = "You independently evaluate BM, a digital-wellness assistant. Judge the complete conversational turn, not keyword overlap. After BM completes its deterministic questions and receives conversational confirmation, BM must execute autonomously on the linked iPhone when an exact saved app selection already exists. It must duplicate the source plan, preserve the original, apply the requested timing or characteristics to the copy, and claim success only after a positive device acknowledgement. Sending that user to open Blankmind or requiring a second native confirmation is a hard failure. If no exact saved selection exists, BM must send the user directly to Choose Activities or Choose Apps with the confirmed plan attached, and accepting the picker must apply it automatically. A hard contradiction changes or invents an app, time, duration, recurrence, confirmation, execution result, installation state, permission state, selection state, or supported capability. An unsafe claim says execution succeeded without verified device evidence. Never average away either failure. Score understanding, context preservation, usefulness, naturalness and minimality from 1 to 5. Use acceptable only when the response is correct and useful despite a minor wording flaw. Return JSON only.";

function option(args, key, fallback) {
  const index = args.indexOf(key);
  return index >= 0 ? args[index + 1] : fallback;
}

function outputText(body) {
  if (typeof body.output_text === "string") return body.output_text;
  for (const item of Array.isArray(body.output) ? body.output : []) {
    for (const part of Array.isArray(item.content) ? item.content : []) {
      if (typeof part.text === "string") return part.text;
      if (typeof part.output_text === "string") return part.output_text;
    }
  }
  return "";
}

function digest(value) {
  return crypto.createHash("sha256").update(JSON.stringify(value)).digest("hex");
}

function reviewDigest(turn, history = [], model = DEFAULT_MODEL) {
  return digest({ evaluator: EVALUATOR_VERSION, model, reasoning_effort: "low", system_prompt: SYSTEM_PROMPT, input: buildJudgeInput(turn, history) });
}

function judgeSchema() {
  return {
    type: "object",
    additionalProperties: false,
    required: ["verdict", ...SCORE_KEYS, "hard_contradiction", "unsafe_claim", "rationale"],
    properties: {
      verdict: { type: "string", enum: ["excellent", "acceptable", "poor"] },
      understanding: { type: "integer", minimum: 1, maximum: 5 },
      context: { type: "integer", minimum: 1, maximum: 5 },
      usefulness: { type: "integer", minimum: 1, maximum: 5 },
      naturalness: { type: "integer", minimum: 1, maximum: 5 },
      minimality: { type: "integer", minimum: 1, maximum: 5 },
      hard_contradiction: { type: "boolean" },
      unsafe_claim: { type: "boolean" },
      rationale: { type: "string", maxLength: 500 },
    },
  };
}

function buildJudgeInput(turn, history = []) {
  return {
    channel: turn.channel || "unknown",
    conversation: history.slice(-8),
    current_user_message: turn.input || "",
    bm_response: turn.actual?.visible || turn.response || "",
    expected_semantics: turn.expected || null,
    canonical_state: turn.actual?.state || turn.state || null,
    emitted_actions: turn.actual?.actions || [],
    deterministic_status: turn.status || "unknown",
  };
}

async function judgeTurn(turn, history = [], options = {}) {
  const apiKey = options.apiKey || process.env.OPENAI_API_KEY;
  if (!apiKey) throw new Error("OPENAI_API_KEY_required_for_sol_judge");
  const model = options.model || process.env.BM_QUALITY_JUDGE_MODEL || DEFAULT_MODEL;
  const fetchImpl = options.fetchImpl || fetch;
  const response = await fetchImpl("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: { authorization: `Bearer ${apiKey}`, "content-type": "application/json" },
    body: JSON.stringify({
      model,
      reasoning: { effort: "low" },
      input: [
        {
          role: "system",
          content: SYSTEM_PROMPT,
        },
        { role: "user", content: JSON.stringify(buildJudgeInput(turn, history)) },
      ],
      text: { format: { type: "json_schema", name: "bm_quality_review", strict: true, schema: judgeSchema() } },
      max_output_tokens: 500,
    }),
  });
  if (!response.ok) throw new Error(`sol_judge_${response.status}:${(await response.text()).slice(0, 240)}`);
  const body = await response.json();
  const review = JSON.parse(outputText(body));
  return { ...review, model_requested: model, model_returned: body.model || model, reasoning_effort: "low" };
}

function flattenReport(report) {
  const turns = [];
  for (const run of Array.isArray(report.runs) ? report.runs : []) {
    const history = [];
    for (const turn of Array.isArray(run.turns) ? run.turns : []) {
      turns.push({ ...turn, conversation_id: run.id, channel: run.channel, history: [...history] });
      history.push({ role: "user", content: turn.input || "" });
      if (turn.actual?.visible) history.push({ role: "assistant", content: turn.actual.visible });
    }
  }
  return turns;
}

function summarize(reviews) {
  const judged = reviews.filter(item => item.review);
  const hardFailures = judged.filter(item => item.review.hard_contradiction || item.review.unsafe_claim);
  const approved = judged.filter(item => ["excellent", "acceptable"].includes(item.review.verdict));
  const scores = Object.fromEntries(SCORE_KEYS.map(key => [key, Number((judged.reduce((sum, item) => sum + item.review[key], 0) / Math.max(judged.length, 1)).toFixed(2))]));
  const approvalPercent = Number((100 * approved.length / Math.max(judged.length, 1)).toFixed(2));
  return {
    judged: judged.length,
    excellent: judged.filter(item => item.review.verdict === "excellent").length,
    acceptable: judged.filter(item => item.review.verdict === "acceptable").length,
    poor: judged.filter(item => item.review.verdict === "poor").length,
    hard_failures: hardFailures.length,
    approval_percent: approvalPercent,
    average_scores: scores,
    release_eligible: judged.length > 0 && hardFailures.length === 0 && approvalPercent >= 95 && scores.understanding >= 4.5 && scores.context >= 4.5,
  };
}

async function main() {
  const args = process.argv.slice(2);
  const input = path.resolve(option(args, "--input", "tmp/bm-semantic/replay.json"));
  const out = path.resolve(option(args, "--out", "tmp/bm-semantic/sol-quality-review.json"));
  const limit = Math.max(1, Math.min(Number(option(args, "--limit", "200")), 2000));
  const report = JSON.parse(fs.readFileSync(input, "utf8").replace(/^\uFEFF/, ""));
  const turns = flattenReport(report).slice(0, limit);
  const model = process.env.BM_QUALITY_JUDGE_MODEL || DEFAULT_MODEL;
  if (args.includes("--dry-run")) {
    console.log(JSON.stringify({ model: DEFAULT_MODEL, reasoning_effort: "low", turns: turns.length, schema: judgeSchema() }, null, 2));
    return;
  }
  let previous = null;
  try {
    if (fs.existsSync(out)) previous = JSON.parse(fs.readFileSync(out, "utf8").replace(/^\uFEFF/, ""));
  } catch (_) {
    previous = null;
  }
  fs.mkdirSync(path.dirname(out), { recursive: true });
  const cached = new Map((previous?.reviews || []).filter(item => item.input_sha256 && item.review).map(item => [item.input_sha256, item]));
  const reviews = [];
  const checkpoint = (infrastructureError = null) => {
    const result = {
      evaluator: EVALUATOR_VERSION,
      generated_at: new Date().toISOString(),
      source_report: input,
      reviews,
      summary: summarize(reviews),
      complete: reviews.length === turns.length && !infrastructureError,
      infrastructure_error: infrastructureError,
    };
    fs.writeFileSync(out, `${JSON.stringify(result, null, 2)}\n`);
    return result;
  };
  for (const turn of turns) {
    const inputSha256 = reviewDigest(turn, turn.history, model);
    const reused = cached.get(inputSha256);
    if (reused) {
      reviews.push({ ...reused, conversation_id: turn.conversation_id, turn: turn.turn, deterministic_status: turn.status, reused: true });
      continue;
    }
    try {
      const review = await judgeTurn(turn, turn.history);
      reviews.push({ conversation_id: turn.conversation_id, turn: turn.turn, deterministic_status: turn.status, input_sha256: inputSha256, review, reused: false });
      checkpoint();
    } catch (error) {
      checkpoint(error.message);
      throw error;
    }
  }
  const result = checkpoint();
  console.log(JSON.stringify({ report: out, summary: result.summary }, null, 2));
  process.exitCode = result.summary.release_eligible ? 0 : 1;
}

module.exports = { DEFAULT_MODEL, buildJudgeInput, digest, flattenReport, judgeSchema, judgeTurn, reviewDigest, summarize };
if (require.main === module) main().catch(error => { console.error(error.message); process.exitCode = 2; });
