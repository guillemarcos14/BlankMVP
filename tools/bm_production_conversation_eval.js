"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");

const args = process.argv.slice(2);

function argValue(name, fallback) {
  const index = args.indexOf(name);
  return index >= 0 && args[index + 1] ? args[index + 1] : fallback;
}

const endpoint = argValue(
  "--url",
  process.env.BM_PRODUCTION_ENDPOINT || "https://getblank.netlify.app/.netlify/functions/blanked-agent",
);
const repeats = Math.min(5, Math.max(1, Number(argValue("--repeats", "2")) || 2));
const outPath = argValue("--out", path.join("tmp", "bm-production-eval", "latest.json"));
const jsonOutput = args.includes("--json");

function clean(value, maxLength = 420) {
  return String(value || "").trim().replace(/\s+/g, " ").slice(0, maxLength);
}

function visibleText(plan) {
  return clean([
    plan?.title,
    plan?.response_text,
    plan?.message_text,
    plan?.speech_text,
    plan?.followup_text,
    ...(Array.isArray(plan?.bullets) ? plan.bullets : []),
  ].filter(Boolean).join(" "), 1600);
}

function actions(plan) {
  return (Array.isArray(plan?.actions) ? plan.actions : [])
    .filter((item) => item && item.type && item.type !== "none");
}

function baseContext(overrides = {}) {
  return {
    channel: "whatsapp",
    assistant_channel: "whatsapp",
    has_selected_apps: true,
    selection_count: 3,
    screen_time_authorized: true,
    is_blank_active: false,
    app_presence: {
      app_present: true,
      app_ready: true,
      last_seen_at: new Date().toISOString(),
    },
    memory: {},
    ...overrides,
  };
}

function callLabel(trace, index, prompt) {
  return `${trace.id}.turn_${index + 1}:${prompt}`;
}

function assertNoAction(plan, label) {
  assert.deepStrictEqual(actions(plan), [], `${label}.no_actions`);
}

function assertNoPrematureLink(plan, label) {
  assert.doesNotMatch(
    clean(`${plan?.message_text || ""} ${plan?.followup_text || ""}`, 900),
    /https?:\/\/|blank:\/\/|app store|download|open blankmind/i,
    `${label}.no_premature_link`,
  );
}

function assertNoInventedLimit(plan, label) {
  assert.doesNotMatch(
    visibleText(plan),
    /25[- ]minute daily limit|25 minutes per day|set a 25|daily limit/i,
    `${label}.no_invented_limit`,
  );
}

function assertSafeSurface(plan, label) {
  assert.doesNotMatch(visibleText(plan), /source|model_error|openai|backend|schema|debug|qa/i, `${label}.no_internal_text`);
  assert.doesNotMatch(visibleText(plan), /medical diagnosis|therapy|treatment|\bcoach\b/i, `${label}.no_unsafe_claims`);
}

function assertContains(plan, pattern, label) {
  assert.match(clean(plan?.message_text || plan?.response_text, 500), pattern, label);
}

const traces = [
  {
    id: "morning_scroll_window",
    context: baseContext(),
    turns: [
      {
        prompt: "How can I scroll less in the morning?",
        check: (plan, label) => {
          assertNoAction(plan, label);
          assertContains(plan, /app|when|time|start/i, `${label}.asks_for_context`);
          assertNoPrematureLink(plan, label);
          assertNoInventedLimit(plan, label);
        },
      },
      {
        prompt: "11am Instagram",
        check: (plan, label) => {
          assertNoAction(plan, label);
          assertContains(plan, /Instagram/i, `${label}.keeps_app`);
          assertContains(plan, /11:00 AM|11 AM|11am/i, `${label}.keeps_start_time`);
          assertContains(plan, /end|finish|time/i, `${label}.asks_for_end_time`);
          assertNoPrematureLink(plan, label);
          assertNoInventedLimit(plan, label);
        },
      },
      {
        prompt: "12pm",
        check: (plan, label) => {
          assertNoAction(plan, label);
          assertContains(plan, /Instagram/i, `${label}.keeps_app`);
          assertContains(plan, /11:00 AM|11 AM|11am/i, `${label}.keeps_start_time`);
          assertContains(plan, /12:00 PM|12 PM|12pm/i, `${label}.keeps_end_time`);
          assertContains(plan, /once|recurring|which days/i, `${label}.asks_recurrence_before_action`);
          assertNoPrematureLink(plan, label);
          assertNoInventedLimit(plan, label);
        },
      },
      {
        prompt: "yes",
        check: (plan, label) => {
          assertNoAction(plan, label);
          assertContains(plan, /once|recurring|which days/i, `${label}.keeps_recurrence_gate`);
          assert.doesNotMatch(clean(plan?.message_text || plan?.response_text, 500), /25[- ]minute daily limit|set a 25|already (set|blocked)/i, `${label}.no_action_hallucination`);
        },
      },
    ],
  },
  {
    id: "confirmed_plan_survives_unknown_presence",
    context: baseContext({
      app_presence: {},
      app_presence_state: "never_seen",
      app_presence_recent: false,
    }),
    turns: [
      {
        prompt: "How can I scroll less in the morning?",
        check: (plan, label) => {
          assertNoAction(plan, label);
          assertNoInventedLimit(plan, label);
        },
      },
      {
        prompt: "Instagram at 11am",
        check: (plan, label) => {
          assertNoAction(plan, label);
          assertContains(plan, /Instagram.*11:00 AM|11:00 AM.*Instagram/i, `${label}.keeps_context`);
          assertContains(plan, /end|finish|time/i, `${label}.asks_for_end_time`);
        },
      },
      {
        prompt: "12pm",
        check: (plan, label) => {
          assertNoAction(plan, label);
          assertContains(plan, /11:00 AM.*12:00 PM|12:00 PM.*11:00 AM/i, `${label}.infers_noon`);
          assert.doesNotMatch(visibleText(plan), /12:00 AM/i, `${label}.not_midnight`);
        },
      },
      {
        prompt: "yes",
        check: (plan, label) => {
          assertNoAction(plan, label);
          assertContains(plan, /once|recurring|which days/i, `${label}.keeps_recurrence_gate`);
          assert.doesNotMatch(visibleText(plan), /apps\.apple\.com|download|create a plan|12:00 AM/i, `${label}.no_manual_creation_or_download`);
        },
      },
      {
        prompt: "I have it",
        check: (plan, label) => {
          assertNoAction(plan, label);
          assertContains(plan, /once|recurring|which days/i, `${label}.preserves_recurrence_gate`);
          assert.doesNotMatch(visibleText(plan), /apps\.apple\.com|download|create a plan/i, `${label}.no_manual_creation_or_download`);
        },
      },
    ],
  },
  {
    id: "morning_scroll_duration_and_correction",
    context: baseContext({
      app_presence: {},
      app_presence_state: "never_seen",
      app_presence_recent: false,
    }),
    turns: [
      {
        prompt: "How can I scroll less in the morning?",
        check: (plan, label) => {
          assertNoAction(plan, label);
          assertNoInventedLimit(plan, label);
        },
      },
      {
        prompt: "Instagram at 10am",
        check: (plan, label) => {
          assertNoAction(plan, label);
          assertContains(plan, /Instagram.*10:00 AM|10:00 AM.*Instagram/i, `${label}.keeps_context`);
          assertContains(plan, /end|finish|time/i, `${label}.asks_for_end_time`);
        },
      },
      {
        prompt: "1 hour",
        check: (plan, label) => {
          assertNoAction(plan, label);
          assertContains(plan, /Instagram.*10:00 AM.*11:00 AM|10:00 AM.*11:00 AM.*Instagram/i, `${label}.uses_duration_from_start`);
          assert.doesNotMatch(visibleText(plan), /\b1:00 AM|\b1:00 PM|\b10:00 PM/i, `${label}.does_not_treat_duration_as_clock`);
        },
      },
      {
        prompt: "No, from 10 to 11 am",
        check: (plan, label) => {
          assertNoAction(plan, label);
          assertContains(plan, /Instagram.*10:00 AM.*11:00 AM|10:00 AM.*11:00 AM.*Instagram/i, `${label}.uses_corrected_window`);
          assertContains(plan, /once|recurring|which days/i, `${label}.asks_recurrence_before_action`);
          assert.doesNotMatch(visibleText(plan), /\b10:00 PM|\b1:00 AM/i, `${label}.does_not_drift_to_pm`);
        },
      },
      {
        prompt: "yes",
        check: (plan, label) => {
          assertNoAction(plan, label);
          assertContains(plan, /once|recurring|which days/i, `${label}.keeps_recurrence_gate`);
        },
      },
    ],
  },
  {
    id: "bedtime_context_continuity",
    context: baseContext(),
    turns: [
      {
        prompt: "How can I scroll less at night?",
        check: (plan, label) => {
          assertNoAction(plan, label);
          assertContains(plan, /bed|sleep|time|asleep/i, `${label}.asks_for_bedtime`);
          assertNoPrematureLink(plan, label);
        },
      },
      {
        prompt: "11pm",
        check: (plan, label) => {
          assertNoAction(plan, label);
          assertContains(plan, /10:30 PM|11:00 PM|bed|asleep|boundary/i, `${label}.uses_previous_context`);
          assertNoPrematureLink(plan, label);
          assertNoInventedLimit(plan, label);
        },
      },
    ],
  },
  {
    id: "explicit_schedule_contract",
    context: baseContext(),
    turns: [
      {
        prompt: "Block selected apps from 10 pm to 7 am every day.",
        check: (plan, label) => {
          assertNoAction(plan, label);
          assertContains(plan, /how many days|1 to 14 days|days should it repeat/i, `${label}.asks_for_horizon`);
          assertNoInventedLimit(plan, label);
        },
      },
      {
        prompt: "7 days",
        check: (plan, label) => {
          assertNoAction(plan, label);
          assertContains(plan, /22:00.*07:00|10:00 PM.*7:00 AM/i, `${label}.keeps_window`);
          assertContains(plan, /confirm|do you/i, `${label}.asks_confirmation`);
        },
      },
      {
        prompt: "yes",
        check: (plan, label) => {
          const schedule = actions(plan).find((item) => item.type === "apply_schedule");
          assert.ok(schedule, `${label}.schedule_exists`);
          assert.strictEqual(schedule.start_minute, 22 * 60, `${label}.start_minute`);
          assert.strictEqual(schedule.end_minute, 7 * 60, `${label}.end_minute`);
          assert.strictEqual(schedule.duration_days, 7, `${label}.duration_days`);
          assertContains(plan, /review|apply/i, `${label}.review_in_app`);
        },
      },
    ],
  },
  {
    id: "daily_limit_requires_amount",
    context: baseContext(),
    turns: [
      {
        prompt: "Set a daily limit for Instagram.",
        check: (plan, label) => {
          assertNoAction(plan, label);
          assertContains(plan, /how many minutes|minutes per day|amount/i, `${label}.asks_for_amount`);
          assert.doesNotMatch(visibleText(plan), /25[- ]minute|25 minutes/i, `${label}.no_default_amount`);
          assertNoPrematureLink(plan, label);
        },
      },
    ],
  },
  {
    id: "small_talk_stays_conversation",
    context: baseContext(),
    turns: [
      {
        prompt: "How are you doing?",
        check: (plan, label) => {
          assertNoAction(plan, label);
          assert.doesNotMatch(clean(plan?.message_text || plan?.response_text, 500), /blankmind|blanked|app|block|plan|https?:\/\//i, `${label}.no_product_route`);
        },
      },
    ],
  },
  {
    id: "stale_presence_blocks_execution",
    context: baseContext({
      app_presence: {
        app_present: true,
        app_ready: true,
        last_seen_at: new Date(Date.now() - (48 * 60 * 60 * 1000)).toISOString(),
      },
      app_presence_state: "stale",
      app_presence_recent: false,
    }),
    turns: [
      {
        prompt: "Block Instagram now for 30 minutes.",
        check: (plan, label) => {
          assertNoAction(plan, label);
          assertContains(plan, /once|recurring|which days|open|download|Blankmind|permissions/i, `${label}.keeps_execution_gated`);
        },
      },
    ],
  },
];

async function callAgent(prompt, context) {
  const response = await fetch(endpoint, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ prompt, context }),
  });
  const bodyText = await response.text();
  assert.strictEqual(response.status, 200, bodyText.slice(0, 500));
  const body = JSON.parse(bodyText);
  assert.strictEqual(body.ok, true, bodyText.slice(0, 500));
  assert.ok(body.plan && typeof body.plan === "object", "plan_exists");
  return body;
}

async function runTrace(trace, repetition) {
  let history = [];
  const turns = [];
  for (let index = 0; index < trace.turns.length; index += 1) {
    const turn = trace.turns[index];
    const label = callLabel(trace, index, turn.prompt);
    const body = await callAgent(turn.prompt, {
      ...trace.context,
      recent_messages: history,
    });
    turn.check(body.plan, label);
    assertSafeSurface(body.plan, label);
    turns.push({
      prompt: turn.prompt,
      source: body.source || null,
      route: body.harness?.route || null,
      plan: {
        intent: body.plan.intent,
        title: body.plan.title,
        message_text: clean(body.plan.message_text || body.plan.response_text, 500),
        action_types: actions(body.plan).map((item) => item.type),
        actions: actions(body.plan),
      },
    });
    history = [
      ...history,
      { role: "user", content: turn.prompt },
      { role: "assistant", content: body.plan.message_text || body.plan.response_text || "" },
    ].slice(-8);
  }
  return { id: trace.id, repetition, turns };
}

async function main() {
  const results = [];
  for (let repetition = 1; repetition <= repeats; repetition += 1) {
    for (const trace of traces) results.push(await runTrace(trace, repetition));
  }
  const sources = results.flatMap((trace) => trace.turns.map((turn) => turn.source).filter(Boolean));
  assert.ok(sources.some((source) => /^openai:/i.test(source)), "active_model_response_required");
  const report = {
    evaluator: "bm-production-conversation-eval-v1",
    generated_at: new Date().toISOString(),
    endpoint,
    repeats,
    traces: results,
    metrics: {
      traces: results.length,
      turns: results.reduce((sum, trace) => sum + trace.turns.length, 0),
      active_model_turns: sources.filter((source) => /^openai:/i.test(source)).length,
      deterministic_turns: sources.filter((source) => /^deterministic/i.test(source)).length,
    },
    status: "passed",
  };
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, `${JSON.stringify(report, null, 2)}\n`, "utf8");
  if (jsonOutput) {
    console.log(JSON.stringify(report, null, 2));
    return;
  }
  console.log(`BM production conversation eval passed: ${report.metrics.traces} traces, ${report.metrics.turns} turns`);
  console.log(`Active model turns: ${report.metrics.active_model_turns}; deterministic turns: ${report.metrics.deterministic_turns}`);
  console.log(`Report: ${outPath}`);
}

main().catch((error) => {
  console.error(`BM production conversation eval failed: ${error.message}`);
  process.exitCode = 1;
});
