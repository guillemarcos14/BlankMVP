const {
  json,
  parseJsonBody,
  requireMethod,
  supabaseFetch,
} = require("./_membership");
const { decryptToken } = require("./_wearable_oauth");

const DIRECT_PROVIDERS = new Set(["oura", "whoop", "fitbit_google_health", "withings"]);

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
    if (provider === "garmin") return json(409, { error: "provider_requires_partner_access" });
    if (!DIRECT_PROVIDERS.has(provider)) return json(400, { error: "unsupported_provider" });

    const rows = await supabaseFetch(
      `wearable_connections?anonymous_user_id=eq.${encodeURIComponent(anonymousUserId)}&provider=eq.${encodeURIComponent(provider)}&status=eq.connected&select=*&limit=1`,
      { method: "GET" }
    );
    const connection = rows?.[0];
    if (!connection?.encrypted_access_token) return json(404, { error: "wearable_connection_not_found" });

    const accessToken = decryptToken(connection.encrypted_access_token);
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
    await patchConnection(connection.id, { status: snapshot.status, last_sync_at: new Date().toISOString(), last_error: null });
    await recordSyncEvent(anonymousUserId, "wearable_sync_success", provider, {
      sync_kind: syncKind,
      status: snapshot.status,
      coverage: snapshot.common_features.coverage || "",
      confidence: snapshot.common_features.confidence || "",
    });
    return json(200, { ok: true, provider, status: snapshot.status, common_features: snapshot.common_features, freshness: snapshot.freshness });
  } catch (error) {
    await markErrorSafely(event, error);
    return json(500, { error: "wearable_sync_failed", detail: error.message });
  }
};

async function fetchProvider(provider, accessToken, start, end) {
  if (provider === "oura") return fetchOura(accessToken, start, end);
  if (provider === "whoop") return fetchWhoop(accessToken, start, end);
  if (provider === "fitbit_google_health") return fetchFitbit(accessToken, start, end);
  if (provider === "withings") return fetchWithings(accessToken, start, end);
  throw new Error("unsupported_provider");
}

async function providerGet(url, accessToken) {
  const response = await fetch(url, { headers: { authorization: `Bearer ${accessToken}` } });
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

async function fetchFitbit(accessToken, start, end) {
  const startDate = dateOnly(start);
  const endDate = dateOnly(end);
  return {
    sleep: await providerGet(`https://api.fitbit.com/1.2/user/-/sleep/date/${startDate}/${endDate}.json`, accessToken),
    activity: await providerGet(`https://api.fitbit.com/1/user/-/activities/date/${endDate}.json`, accessToken),
    hrv: await providerGet(`https://api.fitbit.com/1/user/-/hrv/date/${startDate}/${endDate}.json`, accessToken),
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

function normalizeProvider(provider, raw, start, end) {
  if (provider === "oura") return normalizeOura(raw, start, end);
  if (provider === "whoop") return normalizeWhoop(raw, start, end);
  if (provider === "fitbit_google_health") return normalizeFitbit(raw, start, end);
  if (provider === "withings") return normalizeWithings(raw, start, end);
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

function normalizeFitbit(raw, start, end) {
  const sleep = raw.sleep?.sleep || [];
  const hrv = raw.hrv?.hrv || [];
  const summary = raw.activity?.summary || {};
  const common = makeCommon({
    sleepMinutes: average(sleep.map((item) => cleanNumber(item.minutesAsleep)).filter(Number.isFinite)),
    recovery: null,
    steps: cleanNumber(summary.steps),
    strain: cleanNumber(summary.activeZoneMinutes?.totalMinutes),
    stress: average(hrv.map((item) => cleanNumber(item.value?.dailyRmssd)).filter(Number.isFinite)),
  }, "fitbit_google_health", start, end);
  return {
    status: statusFromCommon(common),
    common_features: common,
    provider_features: compactObject({
      sleep_efficiency: average(sleep.map((item) => cleanNumber(item.efficiency)).filter(Number.isFinite)),
      active_zone_minutes: common.strain_load,
      hrv_daily_rmssd: common.stress_proxy,
      calories_out: cleanNumber(summary.caloriesOut),
    }),
    source_confidence: confidence(common, "fitbit_google_health"),
    freshness: freshness(raw, "fitbit_google_health"),
  };
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
  } catch (_) {}
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
