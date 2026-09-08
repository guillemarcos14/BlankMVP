const assert = require("assert");

const {
  resolveWearableSources,
  wearableDecisionContext,
} = require("../netlify/functions/_wearable_intelligence");
const {
  normalizeProvider,
} = require("../netlify/functions/wearable-sync");

function conflictResolverPrefersFreshConfidentDirectSource() {
  const resolved = resolveWearableSources({
    currentPayload: {
      provider_features: { apple_health: {} },
      common_features: { sleep: "430", recovery: "52", activity: "5000", coverage: "50", confidence: "55" },
      source_confidence: { apple_health: "55", sleep: "55", recovery: "55", activity: "55" },
      freshness: { apple_health_latest_signal_age_hours: "1" },
    },
    snapshots: [
      {
        provider: "oura",
        common_features: { sleep: 405, recovery: 38, activity: 6200, strain_load: 24, stress_proxy: 72, confidence: 88 },
        source_confidence: { oura: "88", sleep: "88", recovery: "92", activity: "84", strain_load: "80", stress_proxy: "86" },
        freshness: { oura_latest_signal_age_hours: "2" },
      },
    ],
  });

  assert.strictEqual(resolved.common_features.recovery, 38);
  assert.strictEqual(resolved.source_map.recovery, "oura");
  assert.strictEqual(resolved.source_map.sleep, "oura");
  assert.ok(resolved.data_quality.coverage >= 80);
}

function wearableDecisionFlagsLowRecoveryAndGentlePlan() {
  const context = wearableDecisionContext({
    common_features: { sleep: 360, recovery: 34, strain_load: 25 },
    data_quality: { confidence: 82, status: "ready" },
  });

  assert.ok(context.flags.includes("low_recovery"));
  assert.ok(context.flags.includes("short_sleep"));
  assert.strictEqual(context.recommended_intensity, "gentle");
}

function normalizesWhoopFixtureWithoutRawSamples() {
  const normalized = normalizeProvider(
    "whoop",
    {
      recovery: { records: [{ score: { recovery_score: 41, hrv_rmssd_milli: 38, resting_heart_rate: 61 } }] },
      cycles: { records: [{ score: { strain: 12.3 } }] },
      sleep: { records: [{ score: { stage_summary: { total_in_bed_time_milli: 24_600_000 }, sleep_performance_percentage: 74 } }] },
      workout: { records: [] },
    },
    new Date("2026-09-01T00:00:00Z"),
    new Date("2026-09-08T00:00:00Z")
  );

  assert.strictEqual(normalized.status, "connected");
  assert.strictEqual(normalized.common_features.recovery, 41);
  assert.strictEqual(normalized.provider_features.hrv_rmssd, 38);
  assert.ok(!("raw" in normalized));
}

function normalizesGoogleHealthFixture() {
  const normalized = normalizeProvider(
    "fitbit_google_health",
    {
      profile: { resourceName: "users/me" },
      steps: { rollupDataPoints: [{ steps: { countSum: 7800 } }] },
      sleep: { rollupDataPoints: [{ sleep: { durationMillisSum: 25_200_000 } }] },
      activeZoneMinutes: { rollupDataPoints: [{ activeZoneMinutes: { minutesSum: 42 } }] },
      hrv: { rollupDataPoints: [{ heartRateVariabilityPersonalRange: { averageHeartRateVariabilityMillisecondsMin: 35, averageHeartRateVariabilityMillisecondsMax: 45 } }] },
      restingHeartRate: { rollupDataPoints: [{ restingHeartRatePersonalRange: { beatsPerMinuteMin: 58, beatsPerMinuteMax: 62 } }] },
    },
    new Date("2026-09-01T00:00:00Z"),
    new Date("2026-09-08T00:00:00Z")
  );

  assert.strictEqual(normalized.status, "connected");
  assert.strictEqual(normalized.common_features.sleep, 420);
  assert.strictEqual(normalized.common_features.activity, 7800);
  assert.strictEqual(normalized.provider_features.resting_heart_rate, 60);
}

(async () => {
  conflictResolverPrefersFreshConfidentDirectSource();
  wearableDecisionFlagsLowRecoveryAndGentlePlan();
  normalizesWhoopFixtureWithoutRawSamples();
  normalizesGoogleHealthFixture();
  console.log("wearable_excellence_smoke_test: ok");
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
