const DIRECT_PROVIDER_WEIGHT = {
  oura: 18,
  whoop: 18,
  fitbit_google_health: 14,
  strava: 14,
  withings: 12,
  apple_health: 8,
  health_connect: 8,
};

const METRIC_KEYS = {
  sleep: ["sleep"],
  sleep_timing: ["sleep_timing"],
  recovery: ["recovery"],
  activity: ["activity"],
  strain_load: ["strain_load"],
  stress_proxy: ["stress_proxy"],
};

function cleanNumber(value, fallback = null) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function cleanText(value, maxLength = 160) {
  return String(value || "").trim().slice(0, maxLength);
}

function compactObject(value) {
  return Object.fromEntries(Object.entries(value).filter(([, rawValue]) => rawValue !== null && rawValue !== undefined && rawValue !== ""));
}

function snapshotProvider(snapshot = {}) {
  return cleanText(snapshot.provider || snapshot.source_provider || "unknown", 64);
}

function providerMetricConfidence(snapshot, metric) {
  const confidence = snapshot.source_confidence || {};
  return cleanNumber(confidence[metric], cleanNumber(confidence[snapshotProvider(snapshot)], cleanNumber(snapshot.common_features?.confidence, 0)));
}

function providerFreshnessHours(snapshot, metric) {
  const freshness = snapshot.freshness || {};
  const provider = snapshotProvider(snapshot);
  return cleanNumber(
    freshness[metric],
    cleanNumber(freshness[`${provider}_latest_signal_age_hours`], cleanNumber(snapshot.common_features?.freshness, 9999))
  );
}

function metricValue(snapshot, metric) {
  const common = snapshot.common_features || {};
  for (const key of METRIC_KEYS[metric] || [metric]) {
    if (common[key] !== null && common[key] !== undefined && common[key] !== "") return common[key];
  }
  return null;
}

function scoreSnapshot(snapshot, metric) {
  const provider = snapshotProvider(snapshot);
  const confidence = providerMetricConfidence(snapshot, metric);
  const freshnessHours = providerFreshnessHours(snapshot, metric);
  const freshnessScore = Math.max(0, 40 - Math.min(40, Math.round(freshnessHours / 2)));
  return confidence + freshnessScore + (DIRECT_PROVIDER_WEIGHT[provider] || 0);
}

function resolveWearableSources({ currentPayload = {}, snapshots = [] } = {}) {
  const currentProvider = Object.keys(currentPayload.provider_features || {})[0] || currentPayload.provider || "app_payload";
  const currentSnapshot = {
    provider: currentProvider,
    common_features: currentPayload.common_features || {},
    provider_features: currentPayload.provider_features || {},
    source_confidence: currentPayload.source_confidence || {},
    freshness: currentPayload.freshness || {},
  };
  const candidates = [currentSnapshot, ...snapshots].filter((snapshot) => snapshot && snapshot.common_features);
  const resolved = {};
  const sourceMap = {};
  const sourceConfidence = {};
  const sourceFreshness = {};
  const rankedProviders = {};

  for (const metric of Object.keys(METRIC_KEYS)) {
    const ranked = candidates
      .filter((snapshot) => metricValue(snapshot, metric) !== null)
      .map((snapshot) => ({
        provider: snapshotProvider(snapshot),
        value: metricValue(snapshot, metric),
        confidence: providerMetricConfidence(snapshot, metric),
        freshness_hours: providerFreshnessHours(snapshot, metric),
        score: scoreSnapshot(snapshot, metric),
      }))
      .sort((left, right) => right.score - left.score);

    if (!ranked.length) continue;
    const best = ranked[0];
    resolved[metric] = best.value;
    sourceMap[metric] = best.provider;
    sourceConfidence[metric] = String(best.confidence);
    sourceFreshness[metric] = String(best.freshness_hours);
    rankedProviders[metric] = ranked.slice(0, 4);
  }

  const coverage = Math.round(Object.keys(resolved).length / Object.keys(METRIC_KEYS).length * 100);
  const confidenceValues = Object.values(sourceConfidence).map((value) => cleanNumber(value, 0));
  const avgConfidence = confidenceValues.length
    ? Math.round(confidenceValues.reduce((sum, value) => sum + value, 0) / confidenceValues.length)
    : 0;
  const staleMetrics = Object.entries(sourceFreshness)
    .filter(([, value]) => cleanNumber(value, 9999) > 72)
    .map(([metric]) => metric);

  return {
    common_features: compactObject({
      ...resolved,
      coverage,
      confidence: avgConfidence,
    }),
    source_map: sourceMap,
    source_confidence: sourceConfidence,
    freshness: sourceFreshness,
    ranked_providers: rankedProviders,
    data_quality: {
      coverage,
      confidence: avgConfidence,
      stale_metrics: staleMetrics,
      status: coverage === 0 ? "no_data" : staleMetrics.length ? "partial_stale" : "ready",
    },
  };
}

function wearableDecisionContext(resolved = {}) {
  const common = resolved.common_features || {};
  const quality = resolved.data_quality || {};
  const recovery = cleanNumber(common.recovery);
  const sleepMinutes = cleanNumber(common.sleep);
  const strain = cleanNumber(common.strain_load);
  const confidence = cleanNumber(quality.confidence, 0);
  const context = [];

  if (confidence < 35) context.push("low_confidence");
  if (quality.status === "partial_stale") context.push("stale_signals");
  if (sleepMinutes !== null && sleepMinutes < 390) context.push("short_sleep");
  if (recovery !== null && recovery < 45) context.push("low_recovery");
  if (strain !== null && strain > 70) context.push("high_strain");

  return {
    flags: context,
    recommended_intensity: context.includes("low_recovery") || context.includes("short_sleep")
      ? "gentle"
      : confidence >= 65
        ? "standard"
        : "learning",
    explanation: context.length
      ? `Wearable context: ${context.join(", ")}.`
      : "Wearable context is stable enough for a normal preventive plan.",
  };
}

module.exports = {
  resolveWearableSources,
  wearableDecisionContext,
};
