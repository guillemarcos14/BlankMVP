const assert = require("assert");
const fs = require("fs");
const path = require("path");

const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);

function argValue(name, fallback = null) {
  const index = rawArgs.indexOf(name);
  return index >= 0 ? rawArgs[index + 1] : fallback;
}

const useModel = args.has("--model");
const endpointUrl = argValue("--url");
const saveReport = args.has("--save");
const countPerRound = Number(argValue("--count", "120"));
const rounds = Number(argValue("--rounds", "3"));
const seed = Number(argValue("--seed", "20260904"));
const stopCleanRounds = Number(argValue("--stop-clean-rounds", "2"));
const maxCostUsd = Number(argValue("--max-cost-usd", "0"));
const estimatedCostPerCase = Number(argValue("--estimated-cost-per-case", "0.00035"));
const outPath = argValue("--out");

if (!useModel && !endpointUrl) {
  process.env.OPENAI_API_KEY = "";
}

const { handler } = require("../netlify/functions/blanked-agent");

const REPORTS_DIR = path.join(__dirname, "reports");
const DEBUG_TEXT_PATTERN = /source|model_error|openai|debug|QA|deterministic_fallback/i;
const BANNED_TEXT_PATTERN = /\bcoach\b|medical diagnosis|diagnose|therapy|treatment/i;
const GENERIC_TEXT_PATTERN = /you'?ve got this|stay strong|take control of your life|small steps|be mindful|try harder|willpower alone/i;

function cleanText(value, maxLength = 400) {
  return String(value || "").trim().replace(/\s+/g, " ").slice(0, maxLength);
}

function makeRng(initialSeed) {
  let state = initialSeed >>> 0;
  return function next() {
    state = (state * 1664525 + 1013904223) >>> 0;
    return state / 0x100000000;
  };
}

const rng = makeRng(seed);

function pick(items) {
  return items[Math.floor(rng() * items.length)];
}

function chance(probability) {
  return rng() < probability;
}

function weightedPick(items) {
  const total = items.reduce((sum, item) => sum + item.weight, 0);
  let cursor = rng() * total;
  for (const item of items) {
    cursor -= item.weight;
    if (cursor <= 0) return item;
  }
  return items[items.length - 1];
}

function baseContext(overrides = {}) {
  return {
    is_blank_active: false,
    has_selected_apps: true,
    selection_count: 3,
    screen_time_authorized: true,
    emergency_unlocks_remaining: 3,
    vacation_mode_active: false,
    adherence_score: 55,
    weekly_protected_minutes: 80,
    weekly_break_count: 0,
    risk_window: "9:00 PM to 10:00 PM",
    recommended_duration_minutes: 35,
    weekly_goal: "Complete 3 protected sessions.",
    ...overrides,
    memory: {
      ...((overrides && overrides.memory) || {}),
    },
  };
}

function actionTypes(plan) {
  return (plan.actions || []).filter((action) => action.type !== "none").map((action) => action.type);
}

function visibleText(plan) {
  return [
    plan.title,
    plan.response_text,
    plan.primary_label,
    plan.secondary_label,
    ...(Array.isArray(plan.bullets) ? plan.bullets : []),
  ].filter(Boolean).join(" ");
}

function userVisibleText(plan) {
  return actionTypes(plan).length === 0 ? cleanText(plan.response_text, 300) : visibleText(plan);
}

async function callAgent(testCase) {
  const payload = {
    prompt: testCase.prompt,
    context: baseContext(testCase.context || {}),
  };
  if (endpointUrl) {
    const response = await fetch(endpointUrl, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
    });
    const bodyText = await response.text();
    assert.strictEqual(response.status, 200, bodyText);
    const body = JSON.parse(bodyText);
    assert.strictEqual(body.ok, true, bodyText);
    return body;
  }

  const response = await handler({
    httpMethod: "POST",
    body: JSON.stringify(payload),
  });
  assert.strictEqual(response.statusCode, 200, response.body);
  const body = JSON.parse(response.body);
  assert.strictEqual(body.ok, true, response.body);
  return body;
}

const apps = ["TikTok", "Instagram", "YouTube", "Reddit", "Twitter", "Snapchat"];
const dirtyApps = ["tiktok", "tik tok", "insta", "ig", "yt", "youtube shorts", "reels", "reddit", "x"];
const moods = ["bored", "anxious", "stressed", "lonely", "tired", "overwhelmed", "procrastinating"];
const relativeMoments = [
  { key: "lunch", phrase: "after lunch", expectedText: /finish eating|lunch|real routine|terminar de comer|después de comer|rutina real/i },
  { key: "dinner", phrase: "after dinner", expectedText: /finish dinner|dinner|real risk|terminar de cenar|después de cenar|riesgo real/i },
  { key: "wake", phrase: "when I wake up", expectedText: /wake up|wake-up|despert|primera revisión/i },
  { key: "work", phrase: "after work", expectedText: /finish work|work usually ends|decompression|terminar de trabajar|trabajo|desconexión/i },
];

function mutate(prompt) {
  let text = prompt;
  if (chance(0.22)) text = text.replace(/\bI\b/g, pick(["i", "I", "bro I"]));
  if (chance(0.18)) text = text.replace(/\bInstagram\b/gi, pick(["insta", "ig", "Instagram"]));
  if (chance(0.15)) text = text.replace(/\bYouTube\b/gi, pick(["yt", "youtube", "YouTube"]));
  if (chance(0.12)) text = text.replace(/\bblock\b/gi, pick(["block", "blok", "bloquear", "shield"]));
  if (chance(0.18)) text = text.replace(/\bafter\b/gi, pick(["after", "right after", "despues de", "después de"]));
  if (chance(0.16)) text = text.replace(/[?.]$/g, "");
  if (chance(0.12)) text = `${text} lol`;
  if (chance(0.08)) text = `${text} pls`;
  if (chance(0.08)) text = text.toLowerCase();
  return cleanText(text, 300);
}

function noActions(plan) {
  return actionTypes(plan).length === 0;
}

function hasAnyAction(plan, expectedTypes) {
  const types = actionTypes(plan);
  return expectedTypes.some((type) => types.includes(type));
}

function hasOnlyActions(plan, expectedTypes) {
  return JSON.stringify(actionTypes(plan)) === JSON.stringify(expectedTypes);
}

function family(name, weight, build, evaluate) {
  return { name, weight, build, evaluate };
}

const families = [
  family("broad_advice_requested", 9, () => ({
    prompt: mutate(pick([
      "How can I improve my digital wellness?",
      "What should I do to stop using my phone so much?",
      "Can you help me understand my screen habits?",
      "Any advice for using my phone less?",
      "No se por donde empezar with my phone habits",
    ])),
    context: { memory: { main_apps: ["TikTok", "Instagram"], weak_hours: [22] } },
  }), (plan) => [
    ["P1", noActions(plan), "Broad advice should not execute actions."],
    ["P1", !/TikTok|Instagram/i.test(userVisibleText(plan)), "Broad advice should not reuse remembered apps unless current prompt names them."],
    ["P2", /moment|automatic|habit|pattern|trigger|phone|momento|automático|hábito|patrón|disparador|móvil/i.test(userVisibleText(plan)), "Advice should identify the habit loop, not generic motivation."],
  ]),

  family("broad_observation_no_advice", 7, () => ({
    prompt: mutate(pick([
      "I use my phone too much",
      "my screen time is bad",
      "phone is killing my focus",
      "lately I'm always on my phone",
      "estoy demasiado con el movil",
    ])),
    context: { memory: { main_apps: ["TikTok"], weak_hours: [21] } },
  }), (plan) => [
    ["P1", noActions(plan), "A broad observation should not execute a plan."],
    ["P1", !/TikTok|Instagram|YouTube/i.test(userVisibleText(plan)), "A broad observation should not inject remembered apps."],
    ["P2", /advice|diagnosis|plan|want|go further|tell me|consejo|lectura|quieres|ir más allá|dime/i.test(userVisibleText(plan)), "BAI should ask what kind of help is wanted."],
  ]),

  family("too_broad_plan", 8, () => ({
    prompt: mutate(pick([
      "make me a plan",
      "create a plan to use my phone less",
      "I need a focus plan",
      "hazme un plan para usar menos el movil",
      "set up a plan for digital wellness",
    ])),
  }), (plan) => [
    ["P1", noActions(plan), "A plan without app/moment/habit should not execute actions."],
    ["P1", /which app|moment|habit|real loop|focus on|qué app|que app|momento|hábito|bucle real|centr/i.test(userVisibleText(plan)), "BAI should ask for the real loop."],
  ]),

  family("relative_moment_social", 12, () => {
    const moment = pick(relativeMoments);
    const app = pick(dirtyApps);
    return {
      prompt: mutate(pick([
        `I always open ${app} ${moment.phrase}`,
        `Can you block ${app} ${moment.phrase}?`,
        `${app} ruins me ${moment.phrase}`,
        `Quiero bloquear ${app} ${moment.phrase}`,
      ])),
      expectedMoment: moment,
    };
  }, (plan, testCase) => [
    ["P1", noActions(plan), "Relative routine moments need one more timing question before actions."],
    ["P1", testCase.expectedMoment.expectedText.test(userVisibleText(plan)), "BAI should ask the routine-specific timing question."],
  ]),

  family("explicit_window_executes", 8, () => {
    const app = pick(["TikTok", "Instagram", "YouTube", "Reddit"]);
    return {
      prompt: mutate(pick([
        `Block ${app} from 10 pm to 7 am`,
        `Limit ${app} from 9 to 11 tonight`,
        `bloquear ${app} from 22:00 to 23:00`,
        `shield ${app} 8 pm to 9 pm`,
      ])),
    };
  }, (plan) => [
    ["P1", hasAnyAction(plan, ["apply_schedule"]), "Explicit windows should create a schedule."],
    ["P1", !hasAnyAction(plan, ["start_protection"]), "Explicit windows should not become immediate blocks."],
  ]),

  family("immediate_focus", 7, () => ({
    prompt: mutate(pick([
      "Start focus mode for 30 minutes now",
      "I need to work now, block distractions for 45 min",
      "hard block everything for 25 minutes",
      "bloquea distracciones ahora 30 min",
    ])),
  }), (plan) => [
    ["P1", hasAnyAction(plan, ["start_protection"]), "Immediate focus should start protection."],
  ]),

  family("app_correction", 9, () => ({
    prompt: mutate(pick([
      "No, I dont use TikTok or ig. What do you mean?",
      "I don't use Instagram, stop saying that",
      "no uso TikTok",
      "that's wrong I never use youtube",
    ])),
    context: { memory: { main_apps: ["TikTok", "Instagram", "YouTube"], weak_hours: [22] } },
  }), (plan) => [
    ["P1", noActions(plan), "App correction should not execute actions."],
    ["P1", /will not use that app|not use that app|Which app|moment|habit|focus on|no usaré esa app|qué app|que app|momento|hábito|centr/i.test(userVisibleText(plan)), "BAI should accept correction and ask for the real focus."],
    ["P1", !/TikTok is|Instagram is|YouTube is|filling a state/i.test(userVisibleText(plan)), "BAI should not diagnose the negated app."],
  ]),

  family("work_conflict", 8, () => {
    const app = pick(["TikTok", "Instagram", "YouTube", "Reddit"]);
    return {
      prompt: mutate(pick([
        `Block ${app} but I need it for work`,
        `I need ${app} for studying but it distracts me`,
        `Limit ${app} except I use it for work tutorials`,
        `quiero bloquear ${app} pero lo necesito para trabajar`,
      ])),
    };
  }, (plan) => [
    ["P1", noActions(plan), "Work/study conflicts should not execute a blind block."],
    ["P2", /work|study|non-work|boundary|when|trabajo|estudio|uso no laboral|límite|cuando|cuándo/i.test(userVisibleText(plan)), "BAI should ask for the non-work boundary."],
  ]),

  family("privacy_boundary", 5, () => ({
    prompt: mutate(pick([
      "Can you see my exact app list?",
      "Do you know which apps I selected?",
      "Can you access all my apps?",
      "puedes ver mi lista exacta de apps?",
    ])),
  }), (plan) => [
    ["P1", noActions(plan), "Privacy questions should not execute actions."],
    ["P1", /exact app|app list|selected|choose to share|not visible|counts|lista exacta|apps|compartir|conteos/i.test(visibleText(plan)), "BAI should state the privacy boundary."],
  ]),

  family("bedtime_ambiguous", 8, () => ({
    prompt: mutate(pick([
      "I scroll in bed until 2",
      "I end up on my phone until 3am in bed",
      "me quedo scrolleando hasta las 2",
      "I can't sleep because I scroll late",
    ])),
  }), (plan) => [
    ["P1", noActions(plan), "Scrolling until late should not treat that late hour as bedtime target."],
    ["P1", /bedtime|sleep target|target sleep|sleep time|usual bedtime|aim to be asleep|want to be asleep|hora objetivo|dormir|hora de dormir/i.test(userVisibleText(plan)), "BAI should ask for bedtime or sleep target."],
  ]),

  family("bedtime_explicit_target", 5, () => ({
    prompt: mutate(pick([
      "I usually go to bed at midnight",
      "my bedtime is 12:30",
      "I sleep at 11:45 pm",
      "me duermo a las 12",
    ])),
  }), (plan) => [
    ["P1", hasAnyAction(plan, ["apply_schedule"]), "Explicit sleep target should create a boundary."],
  ]),

  family("permissions_missing", 6, () => ({
    prompt: mutate(pick([
      "Block Instagram from 10 to 11",
      "Start focus now for 30 minutes",
      "block tiktok from 9 pm to 10 pm",
      "hard block now pls",
    ])),
    context: chance(0.5) ? { has_selected_apps: false, selection_count: 0 } : { screen_time_authorized: false },
  }), (plan) => [
    ["P1", hasAnyAction(plan, ["open_app_picker", "request_screen_time_permission", "apply_schedule", "start_protection"]), "Missing setup should produce a setup step or executable action with requirements."],
    ["P1", plan.requires_selected_apps === true || plan.requires_screen_time_authorization === true || hasAnyAction(plan, ["open_app_picker", "request_screen_time_permission"]), "Missing setup must be visible in requirements/actions."],
  ]),

  family("overreach_forever_everything", 5, () => ({
    prompt: mutate(pick([
      "block everything forever",
      "make it impossible to use my phone ever again",
      "bloquea todo para siempre",
      "delete my distractions permanently",
    ])),
  }), (plan) => [
    ["P1", !/forever|permanent|impossible forever/i.test(visibleText(plan)), "BAI should not promise permanent lockout."],
    ["P2", !hasAnyAction(plan, ["pause_rules"]), "Overreach should not map to pause rules."],
  ]),
];

function buildSyntheticCase(roundIndex, caseIndex) {
  const selected = weightedPick(families);
  const built = selected.build();
  return {
    id: `synthetic_round_${roundIndex + 1}_${caseIndex + 1}_${selected.name}`,
    family: selected.name,
    prompt: built.prompt,
    context: built.context || {},
    expectedMoment: built.expectedMoment || null,
    evaluate: selected.evaluate,
  };
}

function evaluatePlan(testCase, plan) {
  const checks = [];
  const text = visibleText(plan);
  checks.push(["P0", !DEBUG_TEXT_PATTERN.test(text), "No internal/debug text should be visible."]);
  checks.push(["P0", !BANNED_TEXT_PATTERN.test(text), "No banned medical/therapy/coach language should be visible."]);
  checks.push(["P2", !GENERIC_TEXT_PATTERN.test(text), "Avoid generic motivational filler."]);
  checks.push(["P2", cleanText(plan.response_text).length >= 24 && cleanText(plan.response_text).length <= 220, "Response text should be concise but useful."]);
  checks.push(...testCase.evaluate(plan, testCase));
  return checks
    .filter(([, ok]) => !ok)
    .map(([severity, , message]) => ({ severity, message }));
}

async function runCase(testCase) {
  const body = await callAgent(testCase);
  const plan = body.plan;
  const failures = evaluatePlan(testCase, plan);
  return {
    id: testCase.id,
    family: testCase.family,
    prompt: testCase.prompt,
    context: testCase.context,
    ok: failures.length === 0,
    failures,
    source: body.source,
    intent: plan.intent,
    action_types: actionTypes(plan),
    visible_text: visibleText(plan),
    user_visible_text: userVisibleText(plan),
    plan,
  };
}

async function main() {
  if (useModel && !process.env.OPENAI_API_KEY) {
    console.error("OPENAI_API_KEY is required for --model.");
    process.exit(2);
  }

  const startedAt = new Date();
  const results = [];
  let cleanRounds = 0;
  let estimatedSpend = 0;
  let stoppedReason = "completed_rounds";

  for (let roundIndex = 0; roundIndex < rounds; roundIndex += 1) {
    const roundResults = [];
    for (let caseIndex = 0; caseIndex < countPerRound; caseIndex += 1) {
      const nextEstimatedSpend = estimatedSpend + estimatedCostPerCase;
      if (maxCostUsd > 0 && nextEstimatedSpend > maxCostUsd) {
        stoppedReason = "budget_limit";
        break;
      }
      estimatedSpend = nextEstimatedSpend;
      const testCase = buildSyntheticCase(roundIndex, caseIndex);
      const result = await runCase(testCase);
      roundResults.push(result);
      results.push(result);
      const mark = result.ok ? "PASS" : "FAIL";
      const severity = result.failures.map((failure) => failure.severity).sort()[0] || "";
      console.log(`${mark} ${testCase.id}${severity ? ` ${severity}` : ""}`);
    }

    const roundFailures = roundResults.filter((item) => !item.ok);
    cleanRounds = roundFailures.length === 0 ? cleanRounds + 1 : 0;
    if (stoppedReason === "budget_limit") break;
    if (cleanRounds >= stopCleanRounds) {
      stoppedReason = "clean_round_limit";
      break;
    }
  }

  const failures = results.filter((item) => !item.ok);
  const bySeverity = failures.reduce((acc, item) => {
    for (const failure of item.failures) {
      acc[failure.severity] = (acc[failure.severity] || 0) + 1;
    }
    return acc;
  }, {});
  const byFamily = results.reduce((acc, item) => {
    const current = acc[item.family] || { total: 0, failed: 0 };
    current.total += 1;
    current.failed += item.ok ? 0 : 1;
    acc[item.family] = current;
    return acc;
  }, {});

  const report = {
    mode: endpointUrl ? "remote" : useModel ? "model" : "deterministic",
    endpoint_url: endpointUrl || null,
    seed,
    started_at: startedAt.toISOString(),
    finished_at: new Date().toISOString(),
    stopped_reason: stoppedReason,
    parameters: {
      count_per_round: countPerRound,
      rounds,
      stop_clean_rounds: stopCleanRounds,
      max_cost_usd: maxCostUsd,
      estimated_cost_per_case: estimatedCostPerCase,
    },
    metrics: {
      total: results.length,
      passed: results.length - failures.length,
      failed: failures.length,
      pass_rate: Number(((results.length - failures.length) / Math.max(1, results.length)).toFixed(3)),
      estimated_spend_usd: Number(estimatedSpend.toFixed(4)),
      failures_by_severity: bySeverity,
      results_by_family: byFamily,
    },
    failures,
    results,
  };

  if (saveReport || outPath) {
    fs.mkdirSync(REPORTS_DIR, { recursive: true });
    const safeTimestamp = new Date().toISOString().replace(/[:.]/g, "-");
    const reportPath = outPath || path.join(REPORTS_DIR, `blanked_agent_synthetic_loop_${report.mode}_${safeTimestamp}.json`);
    fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`);
    console.log(`Report written: ${reportPath}`);
  }

  console.log(`\n${report.metrics.passed}/${report.metrics.total} synthetic BAI cases passed`);
  console.log(`Stopped: ${stoppedReason}`);
  console.log(`Estimated spend: $${report.metrics.estimated_spend_usd}`);
  if (failures.length) {
    console.log(`Failures: ${failures.length} ${JSON.stringify(bySeverity)}`);
    process.exit(1);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
