"use strict";

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const DEFAULT_MODEL = "gpt-5.6-sol";
const EVALUATOR_VERSION = "bm-sol-quality-judge-v7-nullable-app-context";
const SCORE_KEYS = ["understanding", "context", "usefulness", "naturalness", "minimality"];
const FUNCTIONAL_DIMENSIONS = ["intent", "slots", "transition", "provenance", "decision", "actions", "safety"];
const SYSTEM_PROMPT = "You independently evaluate BM, a digital-wellness assistant. Judge the complete conversational turn, not keyword overlap. Blankmind has one editable selection of distracting apps, categories and websites. Every protection, schedule and limit reuses that selection. Null app_context fields mean the endpoint did not expose that evidence to the evaluator; they do not mean false or missing. A requested app may be named when app_context.selected_app_names confirms it is in that selection. After BM completes its deterministic questions and receives an explicit instruction, BM must queue the exact action for the linked phone. An action listed on an earlier assistant conversation item is valid evidence that it was already queued; a repeated confirmation must not queue the identical action again. Remote execution requires the person to tap the visible Blankmind notification; a silent push must never execute the action. BM may claim success only after a positive device acknowledgement. It must never create, name, duplicate, activate or switch modes. Asking the person to tap the Blankmind notification is correct and must not be treated as a redundant confirmation. If the selection is explicitly false or missing, BM must send the person directly to Choose Activities or Choose Apps with the confirmed plan attached, and accepting the picker must apply it automatically. A hard contradiction changes or invents timing, duration, recurrence, confirmation, execution result, installation state, permission state, selection state, or supported capability. An unsafe claim says execution succeeded without verified device evidence. Never average away either failure. Score understanding, context preservation, usefulness, naturalness and minimality from 1 to 5. Use acceptable only when the response is correct and useful despite a minor wording flaw. Return JSON only.";

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
  const context = turn.trace?.context || turn.evaluation_context || {};
  return {
    channel: turn.channel || "unknown",
    conversation: history.slice(-8),
    current_user_message: turn.input || "",
    bm_response: turn.actual?.visible || turn.response || "",
    expected_semantics: turn.expected || null,
    canonical_state: turn.actual?.state || turn.state || null,
    emitted_actions: turn.actual?.actions || [],
    app_context: {
      has_selected_apps: typeof context.has_selected_apps === "boolean" ? context.has_selected_apps : null,
      selected_app_names: Array.isArray(context.selected_app_names) ? context.selected_app_names.slice(0, 20) : null,
      blocking_permission_ready: typeof context.screen_time_authorized === "boolean" ? context.screen_time_authorized : null,
      device_execution_ready: typeof context.device_execution_ready === "boolean" ? context.device_execution_ready : null,
    },
    deterministic_status: turn.status || "unknown",
  };
}

async function judgeTurn(turn, history = [], options = {}) {
  const apiKey = options.apiKey || process.env.OPENAI_API_KEY;
  if (!apiKey) throw new Error("OPENAI_API_KEY_required_for_sol_judge");
  const model = options.model || process.env.BM_QUALITY_JUDGE_MODEL || DEFAULT_MODEL;
  const fetchImpl = options.fetchImpl || fetch;
  const maxAttempts = Math.max(1, Math.min(Number(options.maxAttempts) || 3, 3));
  let lastError = null;
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
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
        max_output_tokens: 900 + ((attempt - 1) * 500),
      }),
    });
    if (!response.ok) throw new Error(`sol_judge_${response.status}:${(await response.text()).slice(0, 240)}`);
    const body = await response.json();
    const raw = outputText(body);
    if (body.status === "incomplete") {
      lastError = new Error(`sol_judge_incomplete:${body.incomplete_details?.reason || "unknown"}`);
      continue;
    }
    if (!raw.trim()) {
      lastError = new Error("sol_judge_empty_output");
      continue;
    }
    try {
      const review = JSON.parse(raw);
      return { ...review, model_requested: model, model_returned: body.model || model, reasoning_effort: "low" };
    } catch (error) {
      lastError = new Error(`sol_judge_invalid_json:${error.message}`);
    }
  }
  throw lastError || new Error("sol_judge_failed");
}

function flattenReport(report) {
  const turns = [];
  for (const run of Array.isArray(report.runs) ? report.runs : []) {
    const history = [];
    for (const turn of Array.isArray(run.turns) ? run.turns : []) {
      turns.push({ ...turn, conversation_id: run.id, channel: run.channel, history: [...history] });
      history.push({ role: "user", content: turn.input || "" });
      if (turn.actual?.visible) history.push({
        role: "assistant",
        content: turn.actual.visible,
        emitted_actions: turn.actual?.actions || [],
      });
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

function functionalFailures(turns) {
  return turns.filter((turn) => FUNCTIONAL_DIMENSIONS.some((key) => turn.dimensions?.[key] !== "passed"));
}

function oracleReviews(reviews) {
  return reviews.filter(item => item.review && item.review_binding?.response_sha256 && item.review_binding?.expectation_sha256).map(item => ({
    response_sha256: item.review_binding.response_sha256,
    expectation_sha256: item.review_binding.expectation_sha256,
    reviewer: `${item.review.model_returned || item.review.model_requested || DEFAULT_MODEL}:low`,
    rationale: item.review.rationale,
    verdict: ["excellent", "acceptable"].includes(item.review.verdict) && !item.review.hard_contradiction && !item.review.unsafe_claim ? "equivalent" : "not_equivalent",
    language: item.language,
  }));
}

function judgeConcurrency(value = 1) {
  const concurrency = Number(value);
  if (!Number.isInteger(concurrency) || concurrency < 1 || concurrency > 8) throw new Error("invalid_judge_concurrency:1..8");
  return concurrency;
}

async function reviewTurns(turns, options = {}) {
  const concurrency = judgeConcurrency(options.concurrency);
  const model = options.model || DEFAULT_MODEL;
  const judge = options.judgeImpl || judgeTurn;
  const cached = new Map((options.previousReviews || []).filter(item => item.input_sha256 && item.review).map(item => [item.input_sha256, item.review]));
  const inFlight = new Map();
  const results = new Array(turns.length);
  let next = 0;
  let failure = null;
  let checkpointFailed = false;
  const orderedReviews = () => results.filter(Boolean);
  // Checkpoint callbacks are synchronous, like the CLI's filesystem writes.
  // Workers therefore cannot overwrite a newer checkpoint with an older one.
  const checkpoint = () => {
    if (checkpointFailed) return;
    try { options.onCheckpoint?.(orderedReviews(), failure?.message || null); }
    catch (error) { failure ||= error; checkpointFailed = true; }
  };
  await Promise.all(Array.from({ length: Math.min(concurrency, turns.length) }, async () => {
    while (!failure && next < turns.length) {
      const index = next++;
      const turn = turns[index];
      try {
        const history = turn.history || [];
        const inputSha256 = reviewDigest(turn, history, model);
        const reused = cached.has(inputSha256) || inFlight.has(inputSha256);
        let review = cached.get(inputSha256);
        if (!review) {
          if (!inFlight.has(inputSha256)) {
            // Publish the promise before awaiting it: duplicate turns share the
            // same request, including duplicates assigned to another worker.
            inFlight.set(inputSha256, Promise.resolve().then(() => judge(turn, history, { ...options.judgeOptions, model })).then(value => {
              cached.set(inputSha256, value);
              return value;
            }));
          }
          review = await inFlight.get(inputSha256);
        }
        results[index] = { conversation_id: turn.conversation_id, turn: turn.turn, deterministic_status: turn.status,
          input_sha256: inputSha256, review_binding: turn.review_binding, language: turn.expected?.language, review, reused };
      } catch (error) {
        failure ||= error;
      }
      checkpoint();
    }
  }));
  // Drain already-started requests after a failure, preserve their successes in
  // input order, and keep the error so a partial run cannot appear complete.
  checkpoint();
  if (failure) throw failure;
  return orderedReviews();
}

async function main() {
  const args = process.argv.slice(2);
  const input = path.resolve(option(args, "--input", "tmp/bm-semantic/replay.json"));
  const out = path.resolve(option(args, "--out", "tmp/bm-semantic/sol-quality-review.json"));
  const oracleReviewsOut = option(args, "--oracle-reviews-out", null);
  const limit = Math.max(1, Math.min(Number(option(args, "--limit", "200")), 2000));
  const concurrency = judgeConcurrency(option(args, "--concurrency", "1"));
  const report = JSON.parse(fs.readFileSync(input, "utf8").replace(/^\uFEFF/, ""));
  const turns = flattenReport(report).slice(0, limit);
  const model = process.env.BM_QUALITY_JUDGE_MODEL || DEFAULT_MODEL;
  if (args.includes("--dry-run")) {
    console.log(JSON.stringify({ model: DEFAULT_MODEL, reasoning_effort: "low", turns: turns.length, concurrency, schema: judgeSchema() }, null, 2));
    return;
  }
  let previous = null;
  try {
    if (fs.existsSync(out)) previous = JSON.parse(fs.readFileSync(out, "utf8").replace(/^\uFEFF/, ""));
  } catch (_) {
    previous = null;
  }
  fs.mkdirSync(path.dirname(out), { recursive: true });
  const checkpoint = (reviews, infrastructureError = null) => {
    const failures = functionalFailures(turns);
    const reviewSummary = summarize(reviews);
    const summary = {
      ...reviewSummary,
      functional_failures: failures.length,
      release_eligible: reviewSummary.release_eligible && failures.length === 0,
    };
    const result = {
      evaluator: EVALUATOR_VERSION,
      generated_at: new Date().toISOString(),
      source_report: input,
      concurrency,
      reviews,
      summary,
      complete: reviews.length === turns.length && !infrastructureError,
      infrastructure_error: infrastructureError,
    };
    fs.writeFileSync(out, `${JSON.stringify(result, null, 2)}\n`);
    if (oracleReviewsOut) {
      const oraclePath = path.resolve(oracleReviewsOut);
      fs.mkdirSync(path.dirname(oraclePath), { recursive: true });
      fs.writeFileSync(oraclePath, `${JSON.stringify(oracleReviews(reviews), null, 2)}\n`);
    }
    return result;
  };
  let result = null;
  await reviewTurns(turns, { model, concurrency, previousReviews: previous?.reviews,
    onCheckpoint: (reviews, error) => { result = checkpoint(reviews, error); } });
  console.log(JSON.stringify({ report: out, summary: result.summary }, null, 2));
  process.exitCode = result.summary.release_eligible ? 0 : 1;
}

module.exports = { DEFAULT_MODEL, buildJudgeInput, digest, flattenReport, functionalFailures, judgeConcurrency, judgeSchema, judgeTurn, oracleReviews, reviewDigest, reviewTurns, summarize };
if (require.main === module) main().catch(error => { console.error(error.message); process.exitCode = 2; });
