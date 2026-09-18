const crypto = require("crypto");
const {
  getSupabaseUser,
  json,
  parseJsonBody,
  requireMethod,
  supabaseFetch,
} = require("./_membership");

const EVENT_TABLE = "digital_wellness_feature_payloads";
const REQUIRED_REFERRALS = 3;
const REWARD_DAYS = 7;

function cleanText(value, maxLength = 160) {
  return String(value || "").trim().slice(0, maxLength);
}

function eventFilter(eventName) {
  return `${encodeURIComponent("payload->>event")}=eq.${encodeURIComponent(eventName)}`;
}

async function currentUser(event) {
  const user = await getSupabaseUser(event);
  return user && cleanText(user.id, 80) ? user : null;
}

async function identityFor(userId) {
  const rows = await supabaseFetch(
    `privacy_user_links?auth_user_id=eq.${encodeURIComponent(userId)}&select=anonymous_user_id&limit=1`,
    { method: "GET" },
  );
  return cleanText(rows[0]?.anonymous_user_id, 120);
}

function makeCode() {
  return `BLANK-${crypto.randomBytes(5).toString("hex").toUpperCase()}`;
}

async function codeFor(userId, anonymousUserId) {
  const existing = await supabaseFetch(
    `referral_codes?auth_user_id=eq.${encodeURIComponent(userId)}&select=code,anonymous_user_id&limit=1`,
    { method: "GET" },
  );
  if (existing[0]) return existing[0];

  const rows = await supabaseFetch("referral_codes", {
    method: "POST",
    headers: { prefer: "return=representation" },
    body: JSON.stringify({
      auth_user_id: userId,
      anonymous_user_id: anonymousUserId,
      code: makeCode(),
    }),
  });
  return rows[0];
}

async function activationsFor(anonymousUserId) {
  return supabaseFetch(
    `${EVENT_TABLE}?anonymous_user_id=eq.${encodeURIComponent(anonymousUserId)}&${eventFilter("referral_activation")}&select=payload,submitted_at`,
    { method: "GET" },
  );
}

function referralCount(rows) {
  return new Set(rows.map((row) => cleanText(row.payload?.referred_anonymous_user_id, 120)).filter(Boolean)).size;
}

async function rewardFor(anonymousUserId, count) {
  const existing = await supabaseFetch(
    `${EVENT_TABLE}?anonymous_user_id=eq.${encodeURIComponent(anonymousUserId)}&${eventFilter("referral_reward")}&select=payload&order=submitted_at.desc&limit=1`,
    { method: "GET" },
  );
  if (existing[0]?.payload) return existing[0].payload;
  if (count < REQUIRED_REFERRALS) return null;

  const payload = {
    event: "referral_reward",
    reward_days: REWARD_DAYS,
    reward_ends_at: new Date(Date.now() + REWARD_DAYS * 86400000).toISOString(),
    required_referrals: REQUIRED_REFERRALS,
    referral_count_at_unlock: count,
  };
  await supabaseFetch(EVENT_TABLE, {
    method: "POST",
    headers: { prefer: "return=minimal" },
    body: JSON.stringify({
      anonymous_user_id: anonymousUserId,
      schema_version: 1,
      payload,
      insight: { event: "referral_reward" },
      platform: "web",
      data_consent: true,
      consent_text: "Referral reward",
      privacy_raw_health_samples_sent: false,
      privacy_raw_sleep_stage_timestamps_sent: false,
      privacy_exact_app_selection_sent: false,
      privacy_exact_location_sent: false,
      submitted_at: new Date().toISOString(),
    }),
  });
  return payload;
}

async function statusFor(codeRecord) {
  const activations = await activationsFor(codeRecord.anonymous_user_id);
  const count = referralCount(activations);
  const reward = await rewardFor(codeRecord.anonymous_user_id, count);
  const active = reward?.reward_ends_at && new Date(reward.reward_ends_at).getTime() > Date.now();
  return {
    code: codeRecord.code,
    referral_count: count,
    required_referrals: REQUIRED_REFERRALS,
    reward_days: REWARD_DAYS,
    reward_unlocked: Boolean(active),
    reward_ends_at: active ? reward.reward_ends_at : null,
  };
}

async function status(event) {
  const user = await currentUser(event);
  if (!user) return json(401, { error: "authentication_required" });
  const anonymousUserId = await identityFor(user.id);
  if (!anonymousUserId) return json(409, { error: "identity_not_linked" });
  const record = await codeFor(user.id, anonymousUserId);
  const data = await statusFor(record);
  const base = process.env.PUBLIC_WEB_URL || "https://blankmind.ai";
  return json(200, { ok: true, ...data, referral_link: `${base.replace(/\/$/, "")}/signup?ref=${encodeURIComponent(record.code)}` });
}

async function activate(event) {
  const user = await currentUser(event);
  if (!user) return json(401, { error: "authentication_required" });
  const body = parseJsonBody(event);
  const code = cleanText(body.referral_code, 40).toUpperCase();
  const referred = await identityFor(user.id);
  if (!code || !referred) return json(400, { error: "missing_referral_code_or_identity" });

  const rows = await supabaseFetch(
    `referral_codes?code=eq.${encodeURIComponent(code)}&select=auth_user_id,anonymous_user_id,code&limit=1`,
    { method: "GET" },
  );
  const record = rows[0];
  if (!record) return json(404, { error: "referral_code_not_found" });
  if (record.anonymous_user_id === referred) return json(200, { ok: true, accepted: false, reason: "self_referral", ...(await statusFor(record)) });

  const existing = await supabaseFetch(
    `${EVENT_TABLE}?${eventFilter("referral_activation")}&${encodeURIComponent("payload->>referred_anonymous_user_id")}=eq.${encodeURIComponent(referred)}&select=anonymous_user_id,payload`,
    { method: "GET" },
  );
  if (existing.length && !existing.some((row) => row.anonymous_user_id === record.anonymous_user_id)) {
    return json(200, { ok: true, accepted: false, reason: "already_referred", ...(await statusFor(record)) });
  }
  if (!existing.some((row) => row.anonymous_user_id === record.anonymous_user_id)) {
    await supabaseFetch(EVENT_TABLE, {
      method: "POST",
      headers: { prefer: "return=minimal" },
      body: JSON.stringify({
        anonymous_user_id: record.anonymous_user_id,
        schema_version: 1,
        payload: {
          event: "referral_activation",
          referrer_anonymous_user_id: record.anonymous_user_id,
          referred_anonymous_user_id: referred,
          referral_code: record.code,
          source: "web_workspace_activation",
        },
        insight: { event: "referral_activation" },
        platform: "web",
        data_consent: true,
        consent_text: "Referral activation",
        privacy_raw_health_samples_sent: false,
        privacy_raw_sleep_stage_timestamps_sent: false,
        privacy_exact_app_selection_sent: false,
        privacy_exact_location_sent: false,
        submitted_at: new Date().toISOString(),
      }),
    });
  }
  return json(200, { ok: true, accepted: true, ...(await statusFor(record)) });
}

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;
  try {
    const action = cleanText(parseJsonBody(event).action, 40) || "status";
    if (action === "status") return await status(event);
    if (action === "activate") return await activate(event);
    return json(400, { error: "unsupported_action" });
  } catch (error) {
    return json(500, { error: "referral_program_failed", detail: error.message });
  }
};
