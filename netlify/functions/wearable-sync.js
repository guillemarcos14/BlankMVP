const {
  json,
  parseJsonBody,
  requireMethod,
  supabaseFetch,
} = require("./_membership");
const {
  decryptToken,
  encryptToken,
  refreshAccessToken,
} = require("./_wearable_oauth");

const DIRECT_PROVIDERS = new Set(["oura", "whoop", "fitbit_google_health", "withings", "strava"]);
const SYNCABLE_STATUSES = "connected,partial,no_data,stale,error";

function cleanText(value, maxLength = 160) {
  return String(value || "").trim().slice(0, maxLength);
}

function cleanNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function dateOnly(date) {
  return date.toISOString().slice(0, 10);
}

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;

  try {
    const body = parseJsonBody(event);
    const anonymousUserId = cleanText(body.anonymous_user_id, 80);
    const provider = cleanText(body.provider, 64);
    const syncKind = cleanText(body.sync_kind, 40) || "incremental";
    if (!anonymousUserId || body.data_consent !== true) {
      return json(400, { error: "missing_consent_or_user_id" });
    }
    if (provider === "all") {
      const results = await syncAllProviders(anonymousUserId, syncKind);
      const hasFailure = results.some((result) => !result.ok);
      return json(hasFailure ? 207 : 200, { ok: !hasFailure, results });
    }
    if (provider === "garmin") return json(409, { error: "provider_requires_partner_access" });
    if (!DIRECT_PROVIDERS.has(provider)) return json(400, { error: "unsupported_provider" });

    const rows = await supabaseFetch(
      `wearable_connections?anonymous_user_id=eq.${encodeURIComponent(anonymousUserId)}&provider=eq.${encodeURIComponent(provider)}&status=in.(${SYNCABLE_STATUSES})&select=*&limit=1`,
      { method: "GET" }
    );
    const connection = rows?.[0];
    const result = await syncConnection(anonymousUserId, connection, syncKind);
    if (!result.ok && result.statusCode) return json(result.statusCode, { error: result.error });
    if (!result.ok) return json(500, result);
    return json(200, result);
  } catch (error) {
    await markErrorSafely(event, error);
    return json(500, { error: "wearable_sync_failed", detail: error.message });
  }
};

async function syncAllProviders(anonymousUserId, syncKind) {
  const rows = await supabaseFetch(
    `wearable_connections?anonymous_user_id=eq.${encodeURIComponent(anonymousUserId)}&status=in.(${SYNCABLE_STATUSES})&provider=in.(${Array.from(DIRECT_PROVIDERS).join(",")})&select=*`,
    { method: "GET" }
  );
  const results = [];
  for (const connection of rows || []) {
    results.push(await syncConnection(anonymousUserId, connection, syncKind).catch(async (error) => {
      await markConnectionError(anonymousUserId, connection.provider, error);
      return { ok: false, provider: connection.provider, error: cleanText(error.message, 180) };
    }));
  }
  return results;
}

async function syncConnection(anonymousUserId, connection, syncKind) {
  if (!connection?.encrypted_access_token) {
    return { ok: false, statusCode: 404, error: "wearable_connection_not_found" };
  }
  const provider = cleanText(connection.provider, 64);
  if (!DIRECT_PROVIDERS.has(provider)) {
    return { ok: false, statusCode: 400, provider, error: "unsupported_provider" };
  }

  const tokenState = await accessTokenForSync(connection);
  const accessToken = tokenState.accessToken;
  const days = syncKind === "initial_30d" ? 30 : 7;
  const end = new Date();
  const start = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
  const raw = await fetchProvider(provider, accessToken, start, end);
  const snapshot = normalizeProvider(provider, raw, start, end);

  await supabaseFetch("wearable_feature_snapshots", {
    method: "POST",
    headers: { prefer: "return=minimal" },
    body: JSON.stringify({
      anonymous_user_id: anonymousUserId,
      connection_id: connection.id,
      provider,
      period_start: start.toISOString(),
      period_end: end.toISOString(),
      common_features: snapshot.common_features,
      provider_features: snapshot.provider_features,
      source_confidence: snapshot.source_confidence,
      freshness: snapshot.freshness,
      raw_samples_sent: false,
      sync_kind: syncKind === "initial_30d" ? "initial_30d" : "incremental",
    }),
  });
  await patchConnection(connection.id, {
    status: snapshot.status,
    last_sync_at: new Date().toISOString(),
    last_error: null,
    ...tokenState.updates,
  });
  await recordSyncEvent(anonymousUserId, "wearable_sync_success", provider, {
    sync_kind: syncKind,
    status: snapshot.status,
    coverage: snapshot.common_features.coverage || "",
    confidence: snapshot.common_features.confidence || "",
  });
  return {
    ok: true,
    provider,
    status: snapshot.status,
    token_refreshed: tokenState.refreshed,
    common_features: snapshot.common_features,
    freshness: snapshot.freshness,
  };
}

async function accessTokenForSync(connection) {
  const tokenExpiresAt = connection.token_expires_at ? new Date(connection.token_expires_at).getTime() : 0;
  const shouldRefresh = tokenExpiresAt && tokenExpiresAt - Date.now() < 5 * 60 * 1000 && connection.encrypted_refresh_token;
  if (!shouldRefresh) {
    return { accessToken: decryptToken(connection.encrypted_access_token), refreshed: false, updates: {} };
  }

  const refreshToken = decryptToken(connection.encrypted_refresh_token);
  const token = await refreshAccessToken(connection.provider, refreshToken);
  const expiresIn = Number(token.expires_in || 0);
  const tokenExpiresAtNext = expiresIn > 0 ? new Date(Date.now() + expiresIn * 1000).toISOString() : null;
  return {
    accessToken: token.access_token,
    refreshed: true,
    updates: {
      encrypted_access_token: encryptToken(token.access_token),
      encrypted_refresh_token: token.refresh_token ? encryptToken(token.refresh_token) : connection.encrypted_refresh_token,
      token_expires_at: tokenExpiresAtNext,
    },
  };
}

async function fetchProvider(provider, accessToken, start, end) {
  if (provider === "oura") return fetchOura(accessToken, start, end);
  if (provider === "whoop") return fetchWhoop(accessToken, start, end);
  if (provider === "fitbit_google_health") return fetchGoogleHealth(accessToken, start, end);
  if (provider === "withings") return fetchWithings(accessToken, start, end);
  if (provider === "strava") return fetchStrava(accessToken, start, end);
  throw new Error("unsupported_provider");
}

async function providerGet(url, accessToken) {
  const response = await fetch(url, { headers: { authorization: `Bearer ${accessToken}` } });
  const text = await response.text();
  const data = text ? JSON.parse(text) : {};
  if (!response.ok) throw new Error(`provider_fetch_failed_${response.status}:${text.slice(0, 180)}`);
  return data;
}

async function providerPost(url, accessToken, body) {
  const response = await fetch(url, {
    method: "POST",
    headers: { authorization: `Bearer ${accessToken}`, "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  const text = await response.text();
  const data = text ? JSON.parse(text) : {};
  if (!response.ok) throw new Error(`provider_fetch_failed_${response.status}:${text.slice(0, 180)}`);
  return data;
}

async function fetchOura(accessToken, start, end) {
  const params = `start_date=${dateOnly(start)}&end_date=${dateOnly(end)}`;
  return {
    daily_sleep: await providerGet(`https://api.ouraring.com/v2/usercollection/daily_sleep?${params}`, accessToken),
    daily_readiness: await providerGet(`https://api.ouraring.com/v2/usercollection/daily_readiness?${params}`, accessToken),
    daily_activity: await providerGet(`https://api.ouraring.com/v2/usercollection/daily_activity?${params}`, accessToken),
    workouts: await providerGet(`https://api.ouraring.com/v2/usercollection/workout?${params}`, accessToken),
  };
}

async function fetchWhoop(accessToken, start, end) {
  const params = `start=${encodeURIComponent(start.toISOString())}&end=${encodeURIComponent(end.toISOString())}&limit=25`;
  return {
    cycles: await providerGet(`https://api.prod.whoop.com/developer/v2/cycle?${params}`, accessToken),
    recovery: await providerGet(`https://api.prod.whoop.com/developer/v2/recovery?${params}`, accessToken),
    sleep: await providerGet(`https://api.prod.whoop.com/developer/v2/activity/sleep?${params}`, accessToken),
    workout: await providerGet(`https://api.prod.whoop.com/developer/v2/activity/workout?${params}`, accessToken),
  };
}

async function fetchGoogleHealth(accessToken, start, end) {
  const rollup = (dataType) => providerPost(
    `https://health.googleapis.com/v4/users/me/dataTypes/${dataType}/dataPoints:dailyRollUp`,
    accessToken,
    {
      range: { start: civilDateTime(start), end: civilDateTime(end) },
      windowSizeDays: 1,
      dataSourceFamily: "users/me/dataSourceFamilies/all-sources",
    }
  ).catch((error) => ({ error: error.message }));
  return {
    profile: await providerGet("https://health.googleapis.com/v4/users/me/profile", accessToken).catch((error) => ({ error: error.message })),
    steps: await rollup("steps"),
    sleep: await rollup("sleep"),
    activeZoneMinutes: await rollup("active-zone-minutes"),
    heartRate: await rollup("heart-rate"),
    restingHeartRate: await rollup("daily-resting-heart-rate"),
    hrv: await rollup("daily-heart-rate-variability"),
    oxygenSaturation: await rollup("daily-oxygen-saturation"),
    vo2Max: await rollup("vo2-max"),
  };
}

async function fetchWithings(accessToken, start, end) {
  const startTs = Math.floor(start.getTime() / 1000);
  const endTs = Math.floor(end.getTime() / 1000);
  return {
    sleep: await providerGet(`https://wbsapi.withings.net/v2/sleep?action=getsummary&startdateymd=${dateOnly(start)}&enddateymd=${dateOnly(end)}`, accessToken),
    activity: await providerGet(`https://wbsapi.withings.net/v2/measure?action=getactivity&startdateymd=${dateOnly(start)}&enddateymd=${dateOnly(end)}`, accessToken),
    measures: await providerGet(`https://wbsapi.withings.net/measure?action=getmeas&startdate=${startTs}&enddate=${endTs}`, accessToken),
  };
}

async function fetchStrava(accessToken, start, end) {
  const params = new URLSearchParams({
    after: String(Math.floor(start.getTime() / 1000)),
    before: String(Math.floor(end.getTime() / 1000)),
    per_page: "80",
  });
  return {
    activities: await providerGet(`https://www.strava.com/api/v3/athlete/activities?${params.toString()}`, accessToken),
  };
}

function normalizeProvider(provider, raw, start, end) {
  if (provider === "oura") return normalizeOura(raw, start, end);
  if (provider === "whoop") return normalizeWhoop(raw, start, end);
  if (provider === "fitbit_google_health") return normalizeGoogleHealth(raw, start, end);
  if (provider === "withings") return normalizeWithings(raw, start, end);
  if (provider === "strava") return normalizeStrava(raw, start, end);
  throw new Error("unsupported_provider");
}

function normalizeOura(raw, start, end) {
  const sleep = raw.daily_sleep?.data || [];
  const readiness = raw.daily_readiness?.data || [];
  const activity = raw.daily_activity?.data || [];
  const workouts = raw.workouts?.data || [];
  const common = makeCommon({
    sleepMinutes: average(sleep.map((item) => cleanNumber(item.total_sleep_duration)).filter(Number.isFinite).map((value) => Math.round(value / 60))),
    recovery: average(readiness.map((item) => cleanNumber(item.score)).filter(Number.isFinite)),
    steps: average(activity.map((item) => cleanNumber(item.steps)).filter(Number.isFinite)),
    strain: workouts.length ? workouts.length * 12 : null,
    stress: average(readiness.map((item) => cleanNumber(item.contributors?.hrv_balance)).filter(Number.isFinite)),
  }, "oura", start, end);
  return {
    status: statusFromCommon(common),
    common_features: common,
    provider_features: compactObject({
      readiness_score: common.recovery,
      sleep_score: average(sleep.map((item) => cleanNumber(item.score)).filter(Number.isFinite)),
      activity_score: average(activity.map((item) => cleanNumber(item.score)).filter(Number.isFinite)),
      resilience: average(readiness.map((item) => cleanNumber(item.contributors?.recovery_index)).filter(Number.isFinite)),
    }),
    source_confidence: confidence(common, "oura"),
    freshness: freshness(raw, "oura"),
  };
}

function normalizeWhoop(raw, start, end) {
  const recovery = raw.recovery?.records || [];
  const cycles = raw.cycles?.records || [];
  const sleep = raw.sleep?.records || [];
  const workout = raw.workout?.records || [];
  const common = makeCommon({
    sleepMinutes: average(sleep.map((item) => cleanNumber(item.score?.stage_summary?.total_in_bed_time_milli)).filter(Number.isFinite).map((value) => Math.round(value / 60000))),
    recovery: average(recovery.map((item) => cleanNumber(item.score?.recovery_score)).filter(Number.isFinite)),
    steps: null,
    strain: average(cycles.map((item) => cleanNumber(item.score?.strain)).filter(Number.isFinite)),
    stress: average(recovery.map((item) => cleanNumber(item.score?.hrv_rmssd_milli)).filter(Number.isFinite)),
  }, "whoop", start, end);
  return {
    status: statusFromCommon(common),
    common_features: common,
    provider_features: compactObject({
      recovery_score: common.recovery,
      strain: common.strain_load,
      sleep_performance: average(sleep.map((item) => cleanNumber(item.score?.sleep_performance_percentage)).filter(Number.isFinite)),
      hrv_rmssd: common.stress_proxy,
      resting_hr: average(recovery.map((item) => cleanNumber(item.score?.resting_heart_rate)).filter(Number.isFinite)),
    }),
    source_confidence: confidence(common, "whoop"),
    freshness: freshness(raw, "whoop"),
  };
}

function normalizeGoogleHealth(raw, start, end) {
  const steps = dailyValues(raw.steps, "steps").map((value) => cleanNumber(value.countSum));
  const sleep = dailyValues(raw.sleep, "sleep").map((value) => cleanNumber(value.durationMillisSum) || cleanNumber(value.durationSecondsSum) * 1000);
  const activeZoneMinutes = dailyValues(raw.activeZoneMinutes, "activeZoneMinutes").map((value) =>
    cleanNumber(value.minutesSum) || cleanNumber(value.totalMinutesSum) || cleanNumber(value.durationMinutesSum)
  );
  const hrv = dailyValues(raw.hrv, "heartRateVariabilityPersonalRange").map((value) =>
    average([value.averageHeartRateVariabilityMillisecondsMin, value.averageHeartRateVariabilityMillisecondsMax])
  );
  const restingHr = dailyValues(raw.restingHeartRate, "restingHeartRatePersonalRange").map((value) =>
    average([value.beatsPerMinuteMin, value.beatsPerMinuteMax])
  );
  const heartRate = dailyValues(raw.heartRate, "heartRate").map((value) =>
    cleanNumber(value.beatsPerMinuteAvg) || cleanNumber(value.bpmAvg) || average([value.beatsPerMinuteMin, value.beatsPerMinuteMax])
  );
  const oxygen = dailyValues(raw.oxygenSaturation, "dailyOxygenSaturation").map((value) =>
    cleanNumber(value.percentageAvg) || cleanNumber(value.saturationPercentageAvg)
  );
  const vo2Max = dailyValues(raw.vo2Max, "runVo2Max").map((value) =>
    cleanNumber(value.millilitersPerMinuteKilogramAvg) || cleanNumber(value.vo2MillilitersPerMinuteKilogramAvg)
  );
  const common = makeCommon({
    sleepMinutes: average(sleep.filter(Number.isFinite).map((value) => Math.round(value / 60000))),
    recovery: null,
    steps: average(steps.filter(Number.isFinite)),
    strain: average(activeZoneMinutes.filter(Number.isFinite)),
    stress: average(hrv.filter(Number.isFinite)),
  }, "fitbit_google_health", start, end);
  return {
    status: statusFromCommon(common),
    common_features: common,
    provider_features: compactObject({
      google_health_profile_available: raw.profile && !raw.profile.error ? true : null,
      active_zone_minutes: common.strain_load,
      hrv_ms: common.stress_proxy,
      resting_heart_rate: average(restingHr.filter(Number.isFinite)),
      heart_rate: average(heartRate.filter(Number.isFinite)),
      oxygen_saturation: average(oxygen.filter(Number.isFinite)),
      vo2_max: average(vo2Max.filter(Number.isFinite)),
    }),
    source_confidence: confidence(common, "fitbit_google_health"),
    freshness: freshness(raw, "fitbit_google_health"),
  };
}

function civilDateTime(date) {
  return {
    year: date.getUTCFullYear(),
    month: date.getUTCMonth() + 1,
    day: date.getUTCDate(),
    hours: 0,
    minutes: 0,
    seconds: 0,
  };
}

function dailyValues(raw, field) {
  return (raw?.rollupDataPoints || []).map((point) => point?.[field]).filter(Boolean);
}

function normalizeWithings(raw, start, end) {
  const sleep = raw.sleep?.body?.series || [];
  const activity = raw.activity?.body?.activities || [];
  const measures = raw.measures?.body?.measuregrps || [];
  const common = makeCommon({
    sleepMinutes: average(sleep.map((item) => cleanNumber(item.data?.wakeupduration) && cleanNumber(item.data?.durationtosleep) ? null : cleanNumber(item.data?.total_sleep_time)).filter(Number.isFinite)),
    recovery: null,
    steps: average(activity.map((item) => cleanNumber(item.steps)).filter(Number.isFinite)),
    strain: average(activity.map((item) => cleanNumber(item.elevation)).filter(Number.isFinite)),
    stress: null,
  }, "withings", start, end);
  return {
    status: statusFromCommon(common),
    common_features: common,
    provider_features: compactObject({
      weight_measurements: measures.length,
      distance_meters: average(activity.map((item) => cleanNumber(item.distance)).filter(Number.isFinite)),
      calories: average(activity.map((item) => cleanNumber(item.calories)).filter(Number.isFinite)),
      sleep_score: average(sleep.map((item) => cleanNumber(item.data?.sleep_score)).filter(Number.isFinite)),
    }),
    source_confidence: confidence(common, "withings"),
    freshness: freshness(raw, "withings"),
  };
}

function normalizeStrava(raw, start, end) {
  const activities = Array.isArray(raw.activities) ? raw.activities : [];
  const movingMinutes = activities
    .map((item) => cleanNumber(item.moving_time))
    .filter(Number.isFinite)
    .map((value) => Math.round(value / 60));
  const distances = activities.map((item) => cleanNumber(item.distance)).filter(Number.isFinite);
  const elevation = activities.map((item) => cleanNumber(item.total_elevation_gain)).filter(Number.isFinite);
  const heartRates = activities.map((item) => cleanNumber(item.average_heartrate)).filter(Number.isFinite);
  const sufferScores = activities.map((item) => cleanNumber(item.suffer_score)).filter(Number.isFinite);
  const common = makeCommon({
    sleepMinutes: null,
    recovery: null,
    steps: null,
    strain: movingMinutes.reduce((sum, value) => sum + value, 0) || null,
    stress: average(heartRates),
  }, "strava", start, end);
  return {
    status: activities.length ? "connected" : "no_data",
    common_features: {
      ...common,
      workout_count: activities.length,
      active_minutes: movingMinutes.reduce((sum, value) => sum + value, 0) || null,
    },
    provider_features: compactObject({
      activity_count: activities.length,
      distance_meters: Math.round(distances.reduce((sum, value) => sum + value, 0)) || null,
      elevation_gain_meters: Math.round(elevation.reduce((sum, value) => sum + value, 0)) || null,
      average_heart_rate: average(heartRates),
      suffer_score: average(sufferScores),
      sport_types: [...new Set(activities.map((item) => cleanText(item.sport_type || item.type, 40)).filter(Boolean))].slice(0, 8).join(","),
    }),
    source_confidence: confidence(common, "strava"),
    freshness: freshness(raw, "strava"),
  };
}

function makeCommon(values, provider, start, end) {
  const coverage = ["sleepMinutes", "recovery", "steps", "strain", "stress"].filter((key) => values[key] !== null && values[key] !== undefined).length * 20;
  return compactObject({
    sleep: values.sleepMinutes,
    sleep_timing: values.sleepMinutes ? "available" : "learning",
    recovery: values.recovery,
    activity: values.steps,
    strain_load: values.strain,
    stress_proxy: values.stress,
    freshness: Math.round((Date.now() - end.getTime()) / 3600000),
    coverage,
    confidence: Math.min(100, coverage + (provider === "oura" || provider === "whoop" ? 15 : 5)),
    period_days: Math.round((end.getTime() - start.getTime()) / 86400000),
  });
}

function statusFromCommon(common) {
  if (!Object.keys(common).length || Number(common.coverage || 0) === 0) return "no_data";
  return Number(common.freshness || 0) > 72 ? "stale" : "connected";
}

function confidence(common, provider) {
  const base = String(common.confidence || 0);
  return {
    [provider]: base,
    sleep: common.sleep ? base : "0",
    recovery: common.recovery ? base : "0",
    activity: common.activity ? base : "0",
    vitals: common.stress_proxy ? base : "0",
  };
}

function freshness(raw, provider) {
  return {
    [`${provider}_latest_signal_age_hours`]: "0",
    status: hasProviderData(raw) ? "fresh" : "no_data",
  };
}

function hasProviderData(raw) {
  return JSON.stringify(raw || {}).length > 20;
}

function average(values) {
  const clean = values.map(cleanNumber).filter(Number.isFinite);
  if (!clean.length) return null;
  return Math.round(clean.reduce((sum, value) => sum + value, 0) / clean.length);
}

function compactObject(value) {
  return Object.fromEntries(Object.entries(value).filter(([, rawValue]) => rawValue !== null && rawValue !== undefined && rawValue !== ""));
}

async function patchConnection(id, updates) {
  await supabaseFetch(`wearable_connections?id=eq.${encodeURIComponent(id)}`, {
    method: "PATCH",
    headers: { prefer: "return=minimal" },
    body: JSON.stringify({ ...updates, updated_at: new Date().toISOString() }),
  });
}

async function markErrorSafely(event, error) {
  try {
    const body = parseJsonBody(event);
    const anonymousUserId = cleanText(body.anonymous_user_id, 80);
    const provider = cleanText(body.provider, 64);
    if (!anonymousUserId || !provider) return;
    await markConnectionError(anonymousUserId, provider, error);
  } catch (_) {}
}

async function markConnectionError(anonymousUserId, provider, error) {
  await supabaseFetch(
    `wearable_connections?anonymous_user_id=eq.${encodeURIComponent(anonymousUserId)}&provider=eq.${encodeURIComponent(provider)}`,
    {
      method: "PATCH",
      headers: { prefer: "return=minimal" },
      body: JSON.stringify({ status: "error", last_error: cleanText(error.message, 240), updated_at: new Date().toISOString() }),
    }
  );
  await recordSyncEvent(anonymousUserId, "wearable_sync_failed", provider, {
    error: cleanText(error.message, 180),
  });
}

async function recordSyncEvent(anonymousUserId, eventName, provider, properties) {
  await supabaseFetch("digital_wellness_feature_payloads", {
    method: "POST",
    headers: { prefer: "return=minimal" },
    body: JSON.stringify({
      anonymous_user_id: anonymousUserId,
      schema_version: 1,
      payload: { event: eventName, properties: { provider, ...properties } },
      insight: { event: eventName },
      platform: "backend",
      data_consent: true,
      consent_text: "Wearable sync analytics",
      privacy_raw_health_samples_sent: false,
      privacy_raw_sleep_stage_timestamps_sent: false,
      privacy_exact_app_selection_sent: false,
      privacy_exact_location_sent: false,
      submitted_at: new Date().toISOString(),
    }),
  });
}

module.exports = {
  handler: exports.handler,
  normalizeProvider,
  syncConnection,
};
