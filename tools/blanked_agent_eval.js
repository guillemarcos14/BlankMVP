const assert = require("assert");
const fs = require("fs");
const path = require("path");

const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);
const useModel = args.has("--model");
const jsonOutput = args.has("--json");
const saveReport = args.has("--save");
const outIndex = rawArgs.indexOf("--out");
const outPath = outIndex >= 0 ? rawArgs[outIndex + 1] : null;
const urlIndex = rawArgs.indexOf("--url");
const endpointUrl = urlIndex >= 0 ? rawArgs[urlIndex + 1] : null;

if (!useModel && !endpointUrl) {
  process.env.OPENAI_API_KEY = "";
}

const { handler } = require("../netlify/functions/blanked-agent");

const CASES_PATH = path.join(__dirname, "blanked_agent_eval_cases.json");
const REPORTS_DIR = path.join(__dirname, "reports");
const DEBUG_TEXT_PATTERN = /source|model_error|openai|debug|QA|deterministic_fallback/i;
const BANNED_TEXT_PATTERN = /\bcoach\b|medical diagnosis|diagnose|therapy|treatment/i;
const GENERIC_TEXT_PATTERN = /you'?ve got this|stay strong|take control of your life|small steps|be mindful|try harder|willpower alone/i;

function cleanText(value, maxLength = 240) {
  return String(value || "").trim().replace(/\s+/g, " ").slice(0, maxLength);
}

function baseContext(overrides = {}) {
  const memory = {
    ...(overrides.memory || {}),
  };
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
    memory,
  };
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
  return actionTypes(plan).length === 0 ? cleanText(plan.response_text, 240) : visibleText(plan);
}

function assertSubset(actual, expected, label) {
  for (const [key, value] of Object.entries(expected)) {
    assert.deepStrictEqual(actual[key], value, `${label}.${key}`);
  }
}

function actionTypes(plan) {
  return (plan.actions || []).filter((action) => action.type !== "none").map((action) => action.type);
}

function qualityScore(plan) {
  const text = visibleText(plan);
  const bullets = Array.isArray(plan.bullets) ? plan.bullets : [];
  let score = 0;
  if (plan.response_text && plan.response_text.length >= 30 && plan.response_text.length <= 220 && bullets.length >= 2 && bullets.length <= 4) score += 1;
  if (/Read:|Pattern:|Move:|Signal:|Feedback:|Block|Pause|Resume|Enable|Start/i.test(text)) score += 1;
  if (!BANNED_TEXT_PATTERN.test(text) && !DEBUG_TEXT_PATTERN.test(text) && !/\bthe user\b|\bask user\b/i.test(text)) score += 1;
  return score;
}

function utilityScore(plan) {
  const text = visibleText(plan);
  const bullets = Array.isArray(plan.bullets) ? plan.bullets : [];
  const actions = actionTypes(plan);
  let score = 0;
  if (plan.response_text && plan.response_text.length >= 30 && plan.response_text.length <= 190) score += 1;
  if (bullets.length >= 2 && bullets.length <= 4) score += 1;
  if (/Read:|Pattern:|Move:/i.test(text)) score += 1;
  if (actions.length === 0 ? /tell me|which app|what time|bedtime|when|not visible|choose to share|stay protected/i.test(text) : /block|protect|start|apply|enable|pause|resume|limit|schedule/i.test(text)) score += 1;
  if (!GENERIC_TEXT_PATTERN.test(text) && !BANNED_TEXT_PATTERN.test(text) && !DEBUG_TEXT_PATTERN.test(text)) score += 1;
  return score;
}

function assertPlan(testCase, plan) {
  const expected = testCase.expect;
  assert.strictEqual(plan.intent, expected.intent, `${testCase.id}.intent`);

  assert.deepStrictEqual(actionTypes(plan), expected.action_types, `${testCase.id}.action_types`);

  if (expected.first_action) {
    assert.ok(plan.actions && plan.actions[0], `${testCase.id}.first_action exists`);
    assertSubset(plan.actions[0], expected.first_action, `${testCase.id}.first_action`);
  }

  if (typeof expected.requires_selected_apps === "boolean") {
    assert.strictEqual(plan.requires_selected_apps, expected.requires_selected_apps, `${testCase.id}.requires_selected_apps`);
  }

  if (typeof expected.requires_screen_time_authorization === "boolean") {
    assert.strictEqual(plan.requires_screen_time_authorization, expected.requires_screen_time_authorization, `${testCase.id}.requires_screen_time_authorization`);
  }

  const text = visibleText(plan);
  const uiText = userVisibleText(plan);
  for (const pattern of expected.text_matches || []) {
    assert.match(text, new RegExp(pattern, "i"), `${testCase.id}.text_matches:${pattern}`);
  }
  for (const pattern of expected.ui_text_matches || []) {
    assert.match(uiText, new RegExp(pattern, "i"), `${testCase.id}.ui_text_matches:${pattern}`);
  }
  for (const pattern of expected.ui_text_not_matches || []) {
    assert.doesNotMatch(uiText, new RegExp(pattern, "i"), `${testCase.id}.ui_text_not_matches:${pattern}`);
  }
  assert.doesNotMatch(text, DEBUG_TEXT_PATTERN, `${testCase.id}.no_internal_text`);
  assert.doesNotMatch(text, BANNED_TEXT_PATTERN, `${testCase.id}.no_banned_text`);

  const minQuality = expected.min_quality_score ?? 2;
  assert.ok(qualityScore(plan) >= minQuality, `${testCase.id}.quality_score`);

  const minUtility = expected.min_utility_score ?? 3;
  assert.ok(utilityScore(plan) >= minUtility, `${testCase.id}.utility_score`);
}

(async () => {
  if (useModel && !process.env.OPENAI_API_KEY) {
    console.error("OPENAI_API_KEY is required for --model eval");
    process.exit(2);
  }

  const cases = JSON.parse(fs.readFileSync(CASES_PATH, "utf8"));
  const failures = [];
  const results = [];
  const metrics = {
    total: cases.length,
    passed: 0,
    failed: 0,
    contract: {
      intent: 0,
      actions: 0,
      first_action: 0,
      requirements: 0,
      text: 0,
      safety: 0,
      quality: 0,
    },
  };

  for (const testCase of cases) {
    try {
      const body = await callAgent(testCase);
      const plan = body.plan;
      assertPlan(testCase, plan);
      metrics.passed += 1;
      metrics.contract.intent += plan.intent === testCase.expect.intent ? 1 : 0;
      metrics.contract.actions += JSON.stringify(actionTypes(plan)) === JSON.stringify(testCase.expect.action_types) ? 1 : 0;
      metrics.contract.first_action += testCase.expect.first_action ? 1 : 0;
      metrics.contract.requirements += (typeof testCase.expect.requires_selected_apps === "boolean" || typeof testCase.expect.requires_screen_time_authorization === "boolean") ? 1 : 0;
      metrics.contract.text += (testCase.expect.text_matches || []).length;
      metrics.contract.safety += 1;
      metrics.contract.quality += qualityScore(plan);
      results.push({
        id: testCase.id,
        ok: true,
        source: body.source,
        prompt: testCase.prompt,
        quality_score: qualityScore(plan),
        utility_score: utilityScore(plan),
        intent: plan.intent,
        action_types: actionTypes(plan),
        visible_text: visibleText(plan),
        user_visible_text: userVisibleText(plan),
        plan,
      });
      if (!jsonOutput) console.log(`PASS ${testCase.id} q=${qualityScore(plan)}/3 u=${utilityScore(plan)}/5`);
    } catch (error) {
      metrics.failed += 1;
      failures.push({ id: testCase.id, error });
      results.push({ id: testCase.id, ok: false, error: error.message });
      if (!jsonOutput) console.error(`FAIL ${testCase.id}: ${error.message}`);
    }
  }

  const report = {
    mode: endpointUrl ? "remote" : useModel ? "model" : "deterministic",
    model: useModel ? (process.env.OPENAI_MODEL || "gpt-4.1-mini") : null,
    endpoint_url: endpointUrl || null,
    metrics: {
      total: metrics.total,
      passed: metrics.passed,
      failed: metrics.failed,
    pass_rate: Number((metrics.passed / metrics.total).toFixed(3)),
    average_quality_score: Number((metrics.contract.quality / Math.max(1, metrics.passed)).toFixed(2)),
      average_utility_score: Number((results.filter((item) => item.ok).reduce((sum, item) => sum + item.utility_score, 0) / Math.max(1, metrics.passed)).toFixed(2)),
    },
    results,
  };

  if (saveReport || outPath) {
    fs.mkdirSync(REPORTS_DIR, { recursive: true });
    const safeTimestamp = new Date().toISOString().replace(/[:.]/g, "-");
    const reportPath = outPath || path.join(REPORTS_DIR, `blanked_agent_eval_${report.mode}_${safeTimestamp}.json`);
    fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`);
    if (!jsonOutput) console.log(`Report written: ${reportPath}`);
  }

  if (jsonOutput) {
    console.log(JSON.stringify(report, null, 2));
  }

  if (failures.length > 0) {
    if (!jsonOutput) console.error(`\n${failures.length}/${cases.length} Blanked AI eval cases failed`);
    process.exit(1);
  }

  if (!jsonOutput) {
    console.log(`\n${cases.length} Blanked AI eval cases passed`);
    console.log(`Average quality score: ${report.metrics.average_quality_score}/3`);
    console.log(`Average utility score: ${report.metrics.average_utility_score}/5`);
  }
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
