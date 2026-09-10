const assert = require("assert");
const fs = require("fs");
const path = require("path");

const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);

function argValue(name, fallback = null) {
  const index = rawArgs.indexOf(name);
  return index >= 0 ? rawArgs[index + 1] : fallback;
}

const saveReport = args.has("--save");
const dryRun = args.has("--dry-run");
const outPath = argValue("--out");
const models = String(argValue("--models", "gpt-5.6-luna,gpt-4.1-mini,gpt-5-mini"))
  .split(",")
  .map((item) => item.trim())
  .filter(Boolean);

if (!dryRun && !process.env.OPENAI_API_KEY) {
  console.error("OPENAI_API_KEY is required. Use --dry-run to only validate scenarios.");
  process.exit(2);
}

const { handler } = require("../netlify/functions/blanked-agent");

const REPORTS_DIR = path.join(__dirname, "reports");
const AI_SOUNDS = /as an ai|this sounds like|real loop|sleep target|useful move|i can help you apply|i prepared a link|read:|pattern:|move:|signal:|feedback:|protection:/i;
const BAD_PRODUCT_SPLIT = /web version cannot help|messaging version|different product|less capable assistant/i;
const INTERNAL_TEXT = /openai|model_error|deterministic_fallback|backend|json|schema|debug/i;
const MALFORMED_RANGE = /\b\d{1,2}(?::\d{2})?\.\s+\d{1,2}(?::\d{2})?\b/;

function cleanText(value, maxLength = 600) {
  return String(value || "").trim().replace(/\s+/g, " ").slice(0, maxLength);
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
  return (plan.actions || [])
    .filter((action) => action && action.type && action.type !== "none")
    .map((action) => action.type);
}

function visibleText(plan) {
  return cleanText([
    plan.message_text,
    plan.response_text,
    plan.speech_text,
    plan.followup_text,
    plan.title,
    plan.primary_label,
    plan.secondary_label,
    ...(Array.isArray(plan.bullets) ? plan.bullets : []),
  ].filter(Boolean).join(" "), 1600);
}

function userVisibleText(plan) {
  return cleanText([
    plan.message_text,
    plan.response_text,
    plan.speech_text,
    plan.followup_text,
    plan.primary_label,
    plan.secondary_label,
  ].filter(Boolean).join(" "), 1200);
}

async function callAgent(model, prompt, context) {
  if (dryRun) {
    return {
      ok: true,
      source: "dry_run",
      plan: {
        intent: "general",
        message_text: "Dry run.",
        response_text: "Dry run.",
        actions: [],
      },
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

const scenarios = [
  {
    id: "context_retention_after_lunch_reels",
    goal: "Remember details from earlier turns and avoid drifting to bedtime.",
    turns: [
      { role: "user", prompt: "I lose control after lunch." },
      { role: "assistant", text: "What usually pulls you in after lunch?" },
      { role: "user", prompt: "Reels. I usually finish eating around 2:30." },
      { role: "assistant", text: "Got it, post-lunch Reels around 2:30." },
      {
        role: "user",
        prompt: "What should I do?",
        context: { channel: "web", web_preview: true },
        mustMatch: [/reels/i, /2:30|2:35|2:40|lunch|after lunch|post-lunch/i],
        mustNotMatch: [/bedtime|sleep target|download/i],
      },
    ],
  },
  {
    id: "correction_overrides_old_context",
    goal: "Accept user correction and stop using incompatible memory.",
    context: { memory: { main_apps: ["TikTok"], last_topic: "sleep", weak_hours: [23] } },
    turns: [
      {
        role: "user",
        prompt: "No, I do not use TikTok and this is after lunch, not bedtime.",
        context: { channel: "whatsapp", assistant_channel: "whatsapp" },
        mustMatch: [/got it|not use|won.?t use|after lunch|lunch/i],
        mustNotMatch: [/TikTok is|bedtime|sleep target|night/i],
      },
    ],
  },
  {
    id: "web_same_product_but_no_permissions",
    goal: "Web feels like the same assistant, while explaining execution needs the app.",
    turns: [
      {
        role: "user",
        prompt: "Can you block Instagram for me from 10 to 7?",
        context: { channel: "web", web_preview: true },
        mustMatch: [/Instagram/i, /10|7/i, /app|permission|execute|apply/i],
        mustNotMatch: [/web version cannot help|different product|copy this manually/i],
      },
    ],
  },
  {
    id: "messaging_short_same_brain",
    goal: "Messaging stays short but not dumber than web.",
    turns: [
      {
        role: "user",
        prompt: "I keep opening Instagram right after work and then lose the evening.",
        context: { channel: "whatsapp", assistant_channel: "whatsapp" },
        mustMatch: [/after work|evening|Instagram|protect|block|boundary|finish work/i],
        mustNotMatch: [/download|long report|dashboard|as an ai/i],
        maxWords: 80,
      },
    ],
  },
  {
    id: "productivity_recommends_blocking_when_relevant",
    goal: "Recommend blocking when productivity clearly depends on phone control.",
    turns: [
      {
        role: "user",
        prompt: "I need to be more productive this afternoon but I always end up on Shorts.",
        context: { channel: "web", web_preview: true },
        mustMatch: [/productive|priority|work block|shorts|scroll|block|protect/i],
        mustNotMatch: [/medical|therapy|coach/i],
      },
    ],
  },
  {
    id: "general_sleep_first_no_funnel",
    goal: "Answer wellness question first, without forcing a download.",
    turns: [
      {
        role: "user",
        prompt: "How can I sleep better?",
        context: { channel: "web", web_preview: true },
        mustMatch: [/wake|light|caffeine|routine|screen|sleep/i],
        mustNotMatch: [/download|install|trial|open the app/i],
      },
    ],
  },
  {
    id: "small_talk_natural_no_capabilities",
    goal: "Small talk should feel human and not route to product.",
    turns: [
      {
        role: "user",
        prompt: "how you doing?",
        context: { channel: "whatsapp", assistant_channel: "whatsapp" },
        mustMatch: [/good|doing|here|you|mind/i],
        mustNotMatch: [/Blanked|app|block|plan|capabilities|screen/i],
        maxWords: 30,
      },
    ],
  },
  {
    id: "out_of_scope_stays_wellness",
    goal: "Do not answer general politics/trivia.",
    turns: [
      {
        role: "user",
        prompt: "Israel or Palestine?",
        context: { channel: "web", web_preview: true },
        mustMatch: [/wellness|habits|sleep|energy|focus|phone/i],
        mustNotMatch: [/Israel should|Palestine should|war started|history/i],
      },
    ],
  },
  {
    id: "ask_one_missing_detail_before_action",
    goal: "Missing routine time should produce one contextual question, not blind blocking.",
    turns: [
      {
        role: "user",
        prompt: "Can you block YouTube after dinner?",
        context: { channel: "whatsapp", assistant_channel: "whatsapp" },
        mustMatch: [/dinner|finish|what time|usually|when/i],
        mustNotAction: ["apply_schedule", "start_protection"],
      },
    ],
  },
  {
    id: "clear_window_action_fit",
    goal: "Clear blocking request should create the right action.",
    turns: [
      {
        role: "user",
        prompt: "Block Instagram from 10 pm to 7 am.",
        context: { channel: "whatsapp", assistant_channel: "whatsapp" },
        mustAction: ["apply_schedule"],
        mustMatch: [/10|7|Instagram|protect|block/i],
      },
    ],
  },
];

function scoreTurn(expectation, plan) {
  const text = visibleText(plan);
  const userText = userVisibleText(plan);
  const words = cleanText(plan.message_text || plan.response_text, 1000).split(/\s+/).filter(Boolean).length;
  const types = actionTypes(plan);
  const failures = [];
  let score = 0;
  const dimensions = {};

  function pass(name, ok, message) {
    dimensions[name] = ok ? 1 : 0;
    if (ok) score += 1;
    else failures.push(message);
  }

  pass("safety", !INTERNAL_TEXT.test(userText), "Internal/debug text leaked.");
  pass("natural_tone", !AI_SOUNDS.test(userText), "Answer sounds like an AI/product template.");
  pass("copy_quality", !MALFORMED_RANGE.test(userText), "Malformed range punctuation.");
  pass("same_product", !BAD_PRODUCT_SPLIT.test(userText), "Web/messaging is framed as a different product.");

  if (expectation.mustMatch) {
    pass("context_or_usefulness", expectation.mustMatch.every((pattern) => pattern.test(userText)), "Missing required context/useful content.");
  } else {
    pass("context_or_usefulness", cleanText(plan.message_text || plan.response_text).length >= 12, "Response is too thin.");
  }

  if (expectation.mustNotMatch) {
    pass("wrong_context_avoidance", expectation.mustNotMatch.every((pattern) => !pattern.test(userText)), "Used banned or wrong-context content.");
  } else {
    pass("wrong_context_avoidance", true, "");
  }

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
    score,
    max_score: Object.keys(dimensions).length,
    pass_rate: Number((score / Math.max(1, Object.keys(dimensions).length)).toFixed(3)),
    dimensions,
    failures,
  };
}

async function runScenario(model, scenario) {
  const recentMessages = [];
  const turnResults = [];

  for (const turn of scenario.turns) {
    if (turn.role === "assistant") {
      recentMessages.push({ role: "assistant", content: turn.text });
      continue;
    }

    const context = {
      ...(scenario.context || {}),
      ...(turn.context || {}),
      recent_messages: recentMessages.slice(-8),
    };
    const body = await callAgent(model, turn.prompt, context);
    const plan = body.plan;
    const scored = scoreTurn(turn, plan);
    turnResults.push({
      prompt: turn.prompt,
      context,
      source: body.source,
      ok: scored.failures.length === 0,
      score: scored.score,
      max_score: scored.max_score,
      pass_rate: scored.pass_rate,
      dimensions: scored.dimensions,
      failures: scored.failures,
      action_types: actionTypes(plan),
      message_text: plan.message_text || plan.response_text,
      visible_text: visibleText(plan),
      plan,
    });
    recentMessages.push({ role: "user", content: turn.prompt });
    recentMessages.push({ role: "assistant", content: plan.message_text || plan.response_text || "" });
  }

  const score = turnResults.reduce((sum, item) => sum + item.score, 0);
  const maxScore = turnResults.reduce((sum, item) => sum + item.max_score, 0);
  return {
    id: scenario.id,
    goal: scenario.goal,
    ok: turnResults.every((item) => item.ok),
    score,
    max_score: maxScore,
    pass_rate: Number((score / Math.max(1, maxScore)).toFixed(3)),
    turns: turnResults,
  };
}

async function main() {
  const startedAt = new Date();
  const modelResults = [];

  for (const model of models) {
    const scenariosForModel = [];
    console.log(`\nModel: ${model}`);
    for (const scenario of scenarios) {
      const result = await runScenario(model, scenario);
      scenariosForModel.push(result);
      const mark = result.ok ? "PASS" : "FAIL";
      console.log(`${mark} ${scenario.id} ${result.score}/${result.max_score}`);
    }
    const score = scenariosForModel.reduce((sum, item) => sum + item.score, 0);
    const maxScore = scenariosForModel.reduce((sum, item) => sum + item.max_score, 0);
    modelResults.push({
      model,
      score,
      max_score: maxScore,
      pass_rate: Number((score / Math.max(1, maxScore)).toFixed(3)),
      passed_scenarios: scenariosForModel.filter((item) => item.ok).length,
      failed_scenarios: scenariosForModel.filter((item) => !item.ok).length,
      scenarios: scenariosForModel,
    });
  }

  modelResults.sort((a, b) => b.pass_rate - a.pass_rate || b.score - a.score);
  const report = {
    mode: dryRun ? "dry_run" : "model_comparison",
    primary_candidate: "gpt-5.6-luna",
    models,
    started_at: startedAt.toISOString(),
    finished_at: new Date().toISOString(),
    metrics: {
      scenario_count: scenarios.length,
      winner: modelResults[0] ? modelResults[0].model : null,
    },
    results: modelResults,
  };

  if (saveReport || outPath) {
    fs.mkdirSync(REPORTS_DIR, { recursive: true });
    const safeTimestamp = new Date().toISOString().replace(/[:.]/g, "-");
    const reportPath = outPath || path.join(REPORTS_DIR, `bai_training_benchmark_${safeTimestamp}.json`);
    fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`);
    console.log(`Report written: ${reportPath}`);
  }

  console.log("\nRanking");
  for (const item of modelResults) {
    console.log(`${item.model}: ${item.score}/${item.max_score} pass_rate=${item.pass_rate} failed=${item.failed_scenarios}`);
  }

  if (dryRun) {
    console.log("\nDry run only validated benchmark structure; no model quality was measured.");
    return;
  }

  const current = modelResults.find((item) => item.model === "gpt-4.1-mini");
  const candidate = modelResults.find((item) => item.model === "gpt-5.6-luna");
  if (candidate && current) {
    const delta = Number((candidate.pass_rate - current.pass_rate).toFixed(3));
    console.log(`\ngpt-5.6-luna vs gpt-4.1-mini delta: ${delta}`);
  }

  const best = modelResults[0];
  if (best && best.failed_scenarios > 0) process.exitCode = 1;
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
