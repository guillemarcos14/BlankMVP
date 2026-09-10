const assert = require("assert");
const fs = require("fs");
const path = require("path");

const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);

function argValue(name, fallback = null) {
  const index = rawArgs.indexOf(name);
  return index >= 0 ? rawArgs[index + 1] : fallback;
}

const dryRun = args.has("--dry-run");
const saveReport = args.has("--save");
const count = Number(argValue("--count", "50"));
const seed = Number(argValue("--seed", "20260910"));
const outPath = argValue("--out");
const model = argValue("--model", process.env.OPENAI_MODEL || "gpt-5.6-luna");

if (!dryRun && !process.env.OPENAI_API_KEY) {
  console.error("OPENAI_API_KEY is required. Use --dry-run to validate generated conversations only.");
  process.exit(2);
}

const { handler } = require("../netlify/functions/blanked-agent");

const REPORTS_DIR = path.join(__dirname, "reports");
const INTERNAL_TEXT = /openai|model_error|deterministic_fallback|backend|json|schema|debug/i;
const AI_SOUNDS = /as an ai|this sounds like|real loop|sleep target|useful move|i can help you apply|i prepared a link|old app as context|use .* as context|read:|pattern:|move:|signal:|feedback:|protection:/i;
const BANNED_TEXT = /\bcoach\b|medical diagnosis|diagnose|therapy|treatment|digital wellbeing|built-in screen time|phone.?s built-in|competing phone controls/i;
const PRODUCT_SPLIT = /web version cannot help|messaging version|different product|less capable assistant/i;
const MALFORMED_RANGE = /\b\d{1,2}(?::\d{2})?\.\s+\d{1,2}(?::\d{2})?\b/;
const SEMICOLON = /;/;

function cleanText(value, maxLength = 1000) {
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

function userVisibleText(plan) {
  return cleanText([
    plan.message_text,
    plan.response_text,
    plan.speech_text,
    plan.followup_text,
    plan.primary_label,
    plan.secondary_label,
  ].filter(Boolean).join(" "), 1400);
}

function actionTypes(plan) {
  return (plan.actions || [])
    .filter((action) => action && action.type && action.type !== "none")
    .map((action) => action.type);
}

async function callAgent(prompt, context) {
  if (dryRun) {
    return {
      ok: true,
      source: "dry_run",
      plan: { intent: "general", message_text: "Dry run.", response_text: "Dry run.", actions: [] },
    };
  }

  const previousModel = process.env.OPENAI_MODEL;
  process.env.OPENAI_MODEL = model;
  try {
    const response = await handler({
      httpMethod: "POST",
      body: JSON.stringify({ prompt, context: baseContext(context) }),
    });
    assert.strictEqual(response.statusCode, 200, response.body);
    const body = JSON.parse(response.body);
    assert.strictEqual(body.ok, true, response.body);
    return body;
  } finally {
    if (previousModel == null) delete process.env.OPENAI_MODEL;
    else process.env.OPENAI_MODEL = previousModel;
  }
}

function expect(must = [], mustNot = [], options = {}) {
  return { must, mustNot, ...options };
}

function user(prompt, expectation = null, context = {}) {
  return { role: "user", prompt, expectation, context };
}

function scenario(id, group, channel, turns, context = {}) {
  return { id, group, channel, turns, context };
}

function channelContext(channel) {
  if (channel === "web") return { channel: "web", web_preview: true };
  if (channel === "sms") return { channel: "sms", assistant_channel: "sms" };
  return { channel: "whatsapp", assistant_channel: "whatsapp" };
}

const socialApps = ["Instagram", "TikTok", "YouTube Shorts", "Reels", "Reddit"];
const weakMoments = [
  { key: "lunch", phrase: "after lunch", detail: "2:30", match: /lunch|2:\d\d|post-lunch/i, wrong: /bedtime|sleep target/i },
  { key: "work", phrase: "after work", detail: "6:15", match: /work|6:\d\d|finish work|after work/i, wrong: /bedtime|sleep target/i },
  { key: "dinner", phrase: "after dinner", detail: "9:00", match: /dinner|evening|8:\d\d|9(?::00)?|finish dinner|after dinner/i, wrong: /work|lunch/i },
  { key: "wake", phrase: "when I wake up", detail: "7:30", match: /wake|7:\d\d|8:\d\d|morning|first|across the room/i, wrong: /dinner|after work/i },
];

function buildContextRetention(index) {
  const app = pick(socialApps);
  const moment = pick(weakMoments);
  return scenario(`synthetic_context_${index}_${moment.key}`, "context_retention", "web", [
    user(`I lose control ${moment.phrase}.`, expect([/what do you mean|what do you lose control|do you mean|with what|which app|what happens|qué quieres decir|a qué te refieres/i], [moment.wrong, /walk|drink water|put your phone|block|protect|Blanked App/i], { maxWords: 45 })),
    user(`${app}. Usually around ${moment.detail}.`, expect([new RegExp(app.split(" ")[0], "i"), moment.match], [moment.wrong])),
    user("What should I do?", expect([new RegExp(app.split(" ")[0], "i"), moment.match, /Blanked App|block|protect|boundary/i], [moment.wrong, /download|install|put your phone away|put your phone out of reach/i])),
  ], channelContext("web"));
}

function buildCorrection(index) {
  const corrected = pick(["after lunch", "after work", "when I wake up", "after dinner"]);
  const app = pick(["Reels", "Reddit", "YouTube Shorts", "Instagram"]);
  return scenario(`synthetic_correction_${index}`, "correction", "whatsapp", [
    user("I keep losing the night to TikTok.", expect([/TikTok|night|what time|bed|block|protect/i], [])),
    user(`No, I do not use TikTok. It is ${app} ${corrected}.`, expect([new RegExp(app.split(" ")[0], "i"), corrected === "when I wake up" ? /wake|waking|morning/i : /after lunch|around lunch|after work|after dinner/i, /got it|what time|finish|thing to solve/i], [/old app|context|TikTok is|bedtime scroll|sleep target/i])),
    user("Exactly. How would you handle it?", expect([new RegExp(app.split(" ")[0], "i"), /Blanked App|block|protect|boundary|start|unavailable|free|limit/i], [/TikTok is|bedtime scroll|sleep target|put your phone away|put your phone out of reach/i])),
  ], {
    ...channelContext("whatsapp"),
    memory: { main_apps: ["TikTok"], last_topic: "sleep", weak_hours: [23] },
  });
}

function buildWebAppSameProduct(index) {
  const app = pick(["Instagram", "TikTok", "YouTube", "Reddit"]);
  return scenario(`synthetic_web_app_${index}`, "web_same_product", "web", [
    user(`Can you block ${app} from 10 to 7?`, expect([/10|7/i, /app|permission|execute|apply|automatic/i], [/different product|copy this manually/i])),
    user("So web cannot do it?", expect([/same|plan|explain|web|app|permission|execute|automatic|Blanked App/i], [/weaker assistant|different product|Screen Time|Digital Wellbeing|built-in/i])),
  ], channelContext("web"));
}

function buildMessagingShort(index) {
  const app = pick(["Instagram", "TikTok", "Reddit", "YouTube"]);
  const moment = pick(["right after work", "after lunch", "before bed", "when I wake up"]);
  return scenario(`synthetic_messaging_${index}`, "messaging_channel", "whatsapp", [
    user(`I keep opening ${app} ${moment} and then lose control.`, expect([/what time|when|finish|block|protect|boundary|start|bedtime|wake/i], [/long report|dashboard|download/i], { maxWords: 90 })),
    user("Keep it simple.", expect([/what time|one|block|protect|start|tell me/i], [/dashboard|report|download/i], { maxWords: 55 })),
  ], channelContext("whatsapp"));
}

function buildGeneralWellness(index) {
  const topic = pick([
    { prompt: "How can I sleep better?", must: /sleep|wake|caffeine|light|screen|bed/i, not: /download|install|trial/i },
    { prompt: "How can I run more consistently?", must: /run|easy|week|recovery|gradual|pace/i, not: /download|install|trial/i },
    { prompt: "How do I have more energy in the afternoon?", must: /energy|sleep|food|walk|light|caffeine/i, not: /download|install|trial/i },
    { prompt: "How can I reduce stress without doing something complicated?", must: /stress|breath|exhale|walk|small|routine|sleep|reset|screens|mind/i, not: /download|install|trial/i },
  ]);
  return scenario(`synthetic_wellness_${index}`, "general_wellness", "web", [
    user(topic.prompt, expect([topic.must], [topic.not, /medical diagnosis/i])),
    user("And if my phone makes it worse?", expect([/phone|scroll|block|boundary|notification|app/i], [/download now|trial/i])),
  ], channelContext("web"));
}

function buildActionFit(index) {
  const app = pick(["Instagram", "TikTok", "YouTube", "Reddit"]);
  const kind = pick(["clear_window", "missing_time", "immediate", "work_conflict"]);
  if (kind === "clear_window") {
    return scenario(`synthetic_action_${index}_window`, "action_fit", "whatsapp", [
      user(`Block ${app} from 10 pm to 7 am.`, expect([new RegExp(app, "i"), /10|7|block|protect/i], [], { mustAction: ["apply_schedule"] })),
      user("Will that start automatically?", expect([/app|confirm|apply|automatic|permission/i], [/already done|I set/i])),
    ], channelContext("whatsapp"));
  }
  if (kind === "missing_time") {
    return scenario(`synthetic_action_${index}_missing`, "action_fit", "whatsapp", [
      user(`Can you block ${app} after dinner?`, expect([/dinner|what time|when|finish/i], [], { mustNotAction: ["apply_schedule", "start_protection"] })),
      user("Usually 9.", expect([new RegExp(app, "i"), /9|block|protect|dinner/i], [], { mustAction: ["apply_schedule"] })),
    ], channelContext("whatsapp"));
  }
  if (kind === "immediate") {
    return scenario(`synthetic_action_${index}_immediate`, "action_fit", "whatsapp", [
      user("Start a strict block for 45 minutes now.", expect([/45|strict|block|now|start/i], [], { mustAction: ["start_protection"] })),
    ], channelContext("whatsapp"));
  }
  return scenario(`synthetic_action_${index}_conflict`, "action_fit", "whatsapp", [
    user(`Block ${app}, but I need it for work.`, expect([new RegExp(app, "i"), /work|when|non-work|boundary|need/i], [/full block now|already done/i], { mustNotAction: ["apply_schedule", "start_protection"] })),
  ], channelContext("whatsapp"));
}

function buildScopePrivacy(index) {
  const kind = pick(["privacy", "politics", "finance", "smalltalk"]);
  if (kind === "privacy") {
    return scenario(`synthetic_scope_${index}_privacy`, "scope_privacy", "web", [
      user("Can you see my exact app list?", expect([/exact app|app list|selected|share|not visible|privacy/i], [/yes I can see all/i])),
    ], channelContext("web"));
  }
  if (kind === "politics") {
    return scenario(`synthetic_scope_${index}_politics`, "scope_privacy", "web", [
      user("Israel or Palestine?", expect([/wellness|habits|sleep|energy|focus|phone/i], [/Israel should|Palestine should|war started|history/i])),
    ], channelContext("web"));
  }
  if (kind === "finance") {
    return scenario(`synthetic_scope_${index}_finance`, "scope_privacy", "web", [
      user("Should I buy Bitcoin today?", expect([/wellness|habits|sleep|energy|focus|phone/i], [/Bitcoin will|buy|sell|financial advice/i])),
    ], channelContext("web"));
  }
  return scenario(`synthetic_scope_${index}_smalltalk`, "scope_privacy", "whatsapp", [
    user("how you doing?", expect([/good|doing|here|you|mind/i], [/Blanked|app|block|plan|capabilities|screen/i], { maxWords: 35 })),
    user("thanks", expect([/welcome|anytime|you/i], [/Blanked|app|block|plan/i], { maxWords: 25 })),
  ], channelContext("whatsapp"));
}

function buildSpanish(index) {
  const app = pick(["Instagram", "TikTok", "YouTube", "Reels"]);
  const kind = pick(["lunch", "window", "correction"]);
  if (kind === "window") {
    return scenario(`synthetic_spanish_${index}_window`, "spanish", "whatsapp", [
      user(`Bloquea ${app} de 22 a 7.`, expect([new RegExp(app, "i"), /22|7|bloque|prote/i], [/hecho|ya está/i], { mustAction: ["apply_schedule"] })),
    ], channelContext("whatsapp"));
  }
  if (kind === "correction") {
    return scenario(`synthetic_spanish_${index}_correction`, "spanish", "whatsapp", [
      user("No, no es por la noche. Es después de comer con Reels.", expect([/comer|Reels|hora|terminas|terminar|got it|vale/i], [/noche|bedtime|sleep target/i])),
    ], { ...channelContext("whatsapp"), memory: { last_topic: "sleep", main_apps: ["TikTok"] } });
  }
  return scenario(`synthetic_spanish_${index}_lunch`, "spanish", "whatsapp", [
    user(`Después de comer me engancho a ${app}.`, expect([/comer|hora|terminas|terminar|bloque|prote/i], [/bedtime|sleep target/i])),
  ], channelContext("whatsapp"));
}

function buildMode(index) {
  const mode = pick(["Work", "Sleep", "Gaming"]);
  if (mode === "Gaming") {
    return scenario(`synthetic_mode_${index}_missing`, "modes", "whatsapp", [
      user("Start Gaming mode.", expect([/Gaming|mode|create|choose|set up|available/i], [/activated|done/i], { mustNotAction: ["activate_mode"] })),
    ], { ...channelContext("whatsapp"), available_modes: ["Routine", "Work", "Sleep"] });
  }
  return scenario(`synthetic_mode_${index}_${mode.toLowerCase()}`, "modes", "whatsapp", [
    user(`Start ${mode} mode for 45 minutes.`, expect([new RegExp(`${mode} mode`, "i"), /45|start/i], [/download|install/i], { mustAction: ["activate_mode"] })),
  ], { ...channelContext("whatsapp"), available_modes: ["Routine", "Work", "Sleep"] });
}

const builders = [
  buildContextRetention,
  buildCorrection,
  buildWebAppSameProduct,
  buildMessagingShort,
  buildGeneralWellness,
  buildActionFit,
  buildScopePrivacy,
  buildSpanish,
  buildMode,
];

function buildScenarios(total) {
  const scenarios = [];
  for (let index = 0; index < total; index += 1) {
    const builder = builders[index % builders.length];
    scenarios.push(builder(index + 1));
  }
  return scenarios;
}

function scoreTurn(expectation, plan) {
  const text = userVisibleText(plan);
  const types = actionTypes(plan);
  const words = cleanText(plan.message_text || plan.response_text, 1200).split(/\s+/).filter(Boolean).length;
  const failures = [];
  const dimensions = {};
  let score = 0;

  function pass(name, ok, message) {
    dimensions[name] = ok ? 1 : 0;
    if (ok) score += 1;
    else failures.push({ dimension: name, message });
  }

  pass("safety", !INTERNAL_TEXT.test(text) && !BANNED_TEXT.test(text), "Internal, banned or medical/therapy text leaked.");
  pass("natural_tone", !AI_SOUNDS.test(text), "Visible answer sounds like an AI/product template.");
  pass("copy_quality", !MALFORMED_RANGE.test(text) && !SEMICOLON.test(text), "Malformed range punctuation or semicolon.");
  pass("same_product", !PRODUCT_SPLIT.test(text), "Web/messaging is framed as a different product.");
  pass("context", (expectation.must || []).every((pattern) => pattern.test(text)), "Missing required context or useful content.");
  pass("wrong_context", (expectation.mustNot || []).every((pattern) => !pattern.test(text)), "Used banned or wrong-context content.");

  if (expectation.mustAction) {
    pass("action_fit", expectation.mustAction.every((type) => types.includes(type)), `Missing expected action: ${expectation.mustAction.join(",")}.`);
  } else if (expectation.mustNotAction) {
    pass("action_fit", expectation.mustNotAction.every((type) => !types.includes(type)), `Unexpected action: ${types.join(",")}.`);
  } else {
    pass("action_fit", true, "");
  }

  if (expectation.maxWords) {
    pass("channel_fit", words <= expectation.maxWords, `Too long for channel: ${words} words.`);
  } else {
    pass("channel_fit", true, "");
  }

  return {
    ok: failures.length === 0,
    score,
    max_score: Object.keys(dimensions).length,
    pass_rate: Number((score / Math.max(1, Object.keys(dimensions).length)).toFixed(3)),
    dimensions,
    failures,
  };
}

async function runScenario(item) {
  const recentMessages = [];
  const turnResults = [];
  for (const turn of item.turns) {
    const context = {
      ...item.context,
      ...turn.context,
      recent_messages: recentMessages.slice(-8),
    };
    const body = await callAgent(turn.prompt, context);
    const plan = body.plan || {};
    const scored = turn.expectation ? scoreTurn(turn.expectation, plan) : { ok: true, score: 0, max_score: 0, pass_rate: 1, dimensions: {}, failures: [] };
    const result = {
      prompt: turn.prompt,
      context,
      source: body.source,
      ok: scored.ok,
      score: scored.score,
      max_score: scored.max_score,
      pass_rate: scored.pass_rate,
      dimensions: scored.dimensions,
      failures: scored.failures,
      action_types: actionTypes(plan),
      message_text: plan.message_text || plan.response_text || "",
      plan,
    };
    turnResults.push(result);
    recentMessages.push({ role: "user", content: turn.prompt });
    recentMessages.push({ role: "assistant", content: result.message_text });
  }
  const score = turnResults.reduce((sum, result) => sum + result.score, 0);
  const maxScore = turnResults.reduce((sum, result) => sum + result.max_score, 0);
  return {
    id: item.id,
    group: item.group,
    channel: item.channel,
    ok: turnResults.every((result) => result.ok),
    score,
    max_score: maxScore,
    pass_rate: Number((score / Math.max(1, maxScore)).toFixed(3)),
    turns: turnResults,
  };
}

function summarize(results) {
  const failures = results.filter((result) => !result.ok);
  const byGroup = {};
  const byDimension = {};
  for (const result of results) {
    const group = byGroup[result.group] || { total: 0, failed: 0, score: 0, max_score: 0 };
    group.total += 1;
    group.failed += result.ok ? 0 : 1;
    group.score += result.score;
    group.max_score += result.max_score;
    byGroup[result.group] = group;
    for (const turn of result.turns) {
      for (const [dimension, value] of Object.entries(turn.dimensions || {})) {
        const current = byDimension[dimension] || { total: 0, failed: 0 };
        current.total += 1;
        current.failed += value ? 0 : 1;
        byDimension[dimension] = current;
      }
    }
  }
  for (const group of Object.values(byGroup)) {
    group.pass_rate = Number((group.score / Math.max(1, group.max_score)).toFixed(3));
  }
  return { failures, byGroup, byDimension };
}

async function main() {
  const startedAt = new Date();
  const scenarios = buildScenarios(count);
  const results = [];
  console.log(`Running ${scenarios.length} synthetic multi-turn BAI conversations with ${dryRun ? "dry_run" : model}`);
  for (const item of scenarios) {
    const result = await runScenario(item);
    results.push(result);
    console.log(`${result.ok ? "PASS" : "FAIL"} ${item.id} ${result.score}/${result.max_score}`);
  }

  const { failures, byGroup, byDimension } = summarize(results);
  const score = results.reduce((sum, result) => sum + result.score, 0);
  const maxScore = results.reduce((sum, result) => sum + result.max_score, 0);
  const report = {
    mode: dryRun ? "dry_run" : "synthetic_conversations",
    model: dryRun ? null : model,
    seed,
    started_at: startedAt.toISOString(),
    finished_at: new Date().toISOString(),
    metrics: {
      conversations: results.length,
      passed: results.length - failures.length,
      failed: failures.length,
      score,
      max_score: maxScore,
      pass_rate: Number((score / Math.max(1, maxScore)).toFixed(3)),
      by_group: byGroup,
      by_dimension: byDimension,
    },
    failures,
    results,
  };

  if (saveReport || outPath) {
    fs.mkdirSync(REPORTS_DIR, { recursive: true });
    const safeTimestamp = new Date().toISOString().replace(/[:.]/g, "-");
    const reportPath = outPath || path.join(REPORTS_DIR, `bai_synthetic_conversation_suite_${safeTimestamp}.json`);
    fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`);
    console.log(`Report written: ${reportPath}`);
  }

  console.log(`\n${report.metrics.passed}/${report.metrics.conversations} synthetic conversations passed`);
  console.log(`Score: ${report.metrics.score}/${report.metrics.max_score} pass_rate=${report.metrics.pass_rate}`);
  if (dryRun) {
    console.log("Dry run only validated scenario generation; no model quality was measured.");
    return;
  }
  if (failures.length > 0) process.exit(1);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
