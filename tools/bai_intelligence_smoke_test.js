const assert = require("assert");

process.env.SUPABASE_URL = "https://blank-test.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role";

const { handler: intelligenceHandler } = require("../netlify/functions/bai-intelligence");
const { handler: outcomeHandler } = require("../netlify/functions/bai-outcome");

function response(status, data) {
  return {
    ok: status >= 200 && status < 300,
    status,
    statusText: status >= 200 && status < 300 ? "OK" : "Error",
    text: async () => JSON.stringify(data || null),
  };
}

function post(body) {
  return {
    httpMethod: "POST",
    body: JSON.stringify(body),
  };
}

const baseRequest = {
  anonymous_user_id: "anon-1",
  data_consent: true,
  profile: {
    age: 29,
    gender: "male",
    goal: "sleep",
  },
  pattern: {
    key: "sleep",
  },
  candidate_recommendation: {
    kind: "sleep_boundary",
    minutes_before_target: 30,
    start_minute: 1350,
    end_minute: 1380,
    duration_days: 7,
  },
};

async function macroWinsWithoutPersonalEvidence() {
  global.fetch = async (url, options = {}) => {
    const target = String(url);
    if (target.includes("/rest/v1/bai_global_plan_patterns")) {
      return response(200, [
        {
          proposed_value: { minutes_before_target: 30, start_minute: 1350, end_minute: 1380, duration_days: 7 },
          positive_rate: 68,
          sample_size: 42,
        },
      ]);
    }
    if (target.includes("/rest/v1/bai_user_plan_outcomes")) return response(200, []);
    if (target.includes("/rest/v1/bai_recommendation_decisions") && options.method === "POST") return response(201, null);
    throw new Error(`Unexpected request: ${url}`);
  };

  const result = await intelligenceHandler(post(baseRequest));
  const body = JSON.parse(result.body);
  assert.strictEqual(result.statusCode, 200, result.body);
  assert.strictEqual(body.decision_source, "macro");
  assert.strictEqual(body.final_recommendation.minutes_before_target, 30);
}

async function microOverridesMacroWhenUserHistoryContradictsIt() {
  global.fetch = async (url, options = {}) => {
    const target = String(url);
    if (target.includes("/rest/v1/bai_global_plan_patterns")) {
      return response(200, [
        {
          proposed_value: { minutes_before_target: 30, start_minute: 1350, end_minute: 1380, duration_days: 7 },
          positive_rate: 70,
          sample_size: 80,
        },
      ]);
    }
    if (target.includes("/rest/v1/bai_user_plan_outcomes")) {
      return response(200, [
        {
          proposed_value: { minutes_before_target: 45, start_minute: 1335, end_minute: 1380, duration_days: 7 },
          outcome: "held",
          outcome_score: 86,
          created_at: "2026-09-08T10:00:00.000Z",
        },
      ]);
    }
    if (target.includes("/rest/v1/bai_recommendation_decisions") && options.method === "POST") {
      const payload = JSON.parse(options.body);
      assert.strictEqual(payload.decision_source, "micro");
      assert.strictEqual(payload.final_recommendation.minutes_before_target, 45);
      return response(201, null);
    }
    throw new Error(`Unexpected request: ${url}`);
  };

  const result = await intelligenceHandler(post(baseRequest));
  const body = JSON.parse(result.body);
  assert.strictEqual(result.statusCode, 200, result.body);
  assert.strictEqual(body.decision_source, "micro");
  assert.strictEqual(body.final_recommendation.minutes_before_target, 45);
  assert.match(body.reason, /personal evidence wins/i);
  assert.strictEqual(body.evidence.contradiction, true);
}

async function exploresWhenEvidenceIsWeak() {
  global.fetch = async (url, options = {}) => {
    const target = String(url);
    if (target.includes("/rest/v1/bai_global_plan_patterns")) {
      return response(200, [
        {
          proposed_value: { minutes_before_target: 30, start_minute: 1350, end_minute: 1380, duration_days: 7 },
          positive_rate: 50,
          sample_size: 2,
          positive_count: 1,
          negative_count: 1,
        },
      ]);
    }
    if (target.includes("/rest/v1/bai_user_plan_outcomes")) return response(200, []);
    if (target.includes("/rest/v1/bai_recommendation_decisions") && options.method === "POST") {
      const payload = JSON.parse(options.body);
      assert.strictEqual(payload.decision_source, "experiment");
      assert.strictEqual(payload.evidence.exploration, true);
      return response(201, null);
    }
    throw new Error(`Unexpected request: ${url}`);
  };

  const result = await intelligenceHandler(post({
    ...baseRequest,
    anonymous_user_id: "anon-explore-1",
    exploration_enabled: true,
    exploration_rate: 1,
  }));
  const body = JSON.parse(result.body);
  assert.strictEqual(result.statusCode, 200, result.body);
  assert.strictEqual(body.decision_source, "experiment");
  assert.notStrictEqual(body.final_recommendation.minutes_before_target, 30);
}

async function recordsOutcomesForBothGlobalAndPersonalLearning() {
  let inserted = null;
  global.fetch = async (url, options = {}) => {
    if (String(url).includes("/rest/v1/bai_user_plan_outcomes") && options.method === "POST") {
      inserted = JSON.parse(options.body);
      return response(201, null);
    }
    throw new Error(`Unexpected request: ${url}`);
  };

  const result = await outcomeHandler(post({
    ...baseRequest,
    recommendation: {
      kind: "sleep_boundary",
      minutes_before_target: 45,
      start_minute: 1335,
      end_minute: 1380,
      duration_days: 7,
    },
    outcome: "held",
    outcome_score: 86,
  }));
  const body = JSON.parse(result.body);
  assert.strictEqual(result.statusCode, 200, result.body);
  assert.strictEqual(body.ok, true);
  assert.strictEqual(inserted.pattern_key, "sleep_night_scroll");
  assert.strictEqual(inserted.proposed_value.minutes_before_target, 45);
}

(async () => {
  await macroWinsWithoutPersonalEvidence();
  await microOverridesMacroWhenUserHistoryContradictsIt();
  await exploresWhenEvidenceIsWeak();
  await recordsOutcomesForBothGlobalAndPersonalLearning();
  console.log("bai_intelligence_smoke_test: ok");
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
