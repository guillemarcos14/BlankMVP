const assert = require("assert");

process.env.SUPABASE_URL = "https://blank-test.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role";
process.env.OPENAI_API_KEY = "";

const { handler } = require("../netlify/functions/digital-wellness-features");

function response(status, data) {
  return {
    ok: status >= 200 && status < 300,
    status,
    statusText: status >= 200 && status < 300 ? "OK" : "Error",
    text: async () => JSON.stringify(data || null),
  };
}

async function resolvesWearableSourcesBeforePlanGeneration() {
  let storedPayload = null;
  global.fetch = async (url, options = {}) => {
    const target = String(url);
    if (target.includes("/rest/v1/wearable_feature_snapshots") && options.method === "POST") {
      return response(201, null);
    }
    if (target.includes("/rest/v1/wearable_feature_snapshots") && options.method === "GET") {
      return response(200, [
        {
          provider: "oura",
          common_features: { sleep: 370, recovery: 34, activity: 6500, strain_load: 20, stress_proxy: 70, confidence: 90 },
          source_confidence: { oura: "90", sleep: "88", recovery: "92", activity: "84", strain_load: "80", stress_proxy: "86" },
          freshness: { oura_latest_signal_age_hours: "1", status: "fresh" },
        },
      ]);
    }
    if (target.includes("/rest/v1/wearable_recommendation_outcomes")) {
      return response(200, []);
    }
    if (target.includes("/rest/v1/bai_global_plan_patterns")) return response(200, []);
    if (target.includes("/rest/v1/bai_user_plan_preferences")) return response(200, []);
    if (target.includes("/rest/v1/digital_wellness_feature_payloads") && options.method === "POST") {
      storedPayload = JSON.parse(options.body);
      return response(201, [{ id: "payload-1" }]);
    }
    throw new Error(`Unexpected request: ${url}`);
  };

  const result = await handler({
    httpMethod: "POST",
    body: JSON.stringify({
      anonymous_user_id: "anon-wearable-plan",
      platform: "ios",
      data_consent: true,
      payload: {
        schema_version: 1,
        period_start: "2026-09-01T00:00:00Z",
        period_end: "2026-09-08T00:00:00Z",
        common_features: { sleep: "430", recovery: "55", activity: "5000", coverage: "50", confidence: "55" },
        provider_features: { apple_health: { resting_heart_rate: "62" } },
        source_confidence: { apple_health: "55", sleep: "55", recovery: "55", activity: "55" },
        freshness: { apple_health_latest_signal_age_hours: "1", status: "fresh" },
        profile: { goal: "sleep" },
        weekly: { days_count: 7, active_days_7d: 4, plan_adherence_percent: 70, weakest_hour: 22, health_signal_coverage_percent: 70 },
        correlations: { screen_risk_after_bad_sleep: "high" },
        privacy: {
          raw_health_samples_sent: false,
          raw_sleep_stage_timestamps_sent: false,
          exact_app_selection_sent: false,
          exact_location_sent: false,
        },
      },
    }),
  });
  const body = JSON.parse(result.body);

  assert.strictEqual(result.statusCode, 200, result.body);
  assert.strictEqual(body.insight.plan_update.duration_days, 3);
  assert.match(body.insight.plan_update.evidence, /Recovery context is low/i);
  assert.strictEqual(storedPayload.payload.resolved_wearable.source_map.recovery, "oura");
  assert.ok(storedPayload.payload.wearable_decision_context.flags.includes("low_recovery"));
}

(async () => {
  await resolvesWearableSourcesBeforePlanGeneration();
  console.log("digital_wellness_wearable_smoke_test: ok");
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
