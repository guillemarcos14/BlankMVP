const {
  json,
  parseJsonBody,
  requireMethod,
  supabaseFetch,
} = require("./_membership");

const EVENT_TABLE = "digital_wellness_feature_payloads";
const REQUIRED_REFERRALS_FOR_REWARD = 3;
const REWARD_DAYS = 7;

function cleanText(value, maxLength = 160) {
  return String(value || "").trim().slice(0, maxLength);
}

function eventFilter(eventName) {
  return `${encodeURIComponent("payload->>event")}=eq.${encodeURIComponent(eventName)}`;
}

function payloadFilter(field, value) {
  return `${encodeURIComponent(`payload->>${field}`)}=eq.${encodeURIComponent(value)}`;
}

async function fetchReferralActivations(referrerAnonymousUserId) {
  return supabaseFetch(
    `${EVENT_TABLE}?anonymous_user_id=eq.${encodeURIComponent(referrerAnonymousUserId)}&${eventFilter("referral_activation")}&select=payload,submitted_at`,
    { method: "GET" }
  );
}

async function fetchReferredActivation(referredAnonymousUserId) {
  return supabaseFetch(
    `${EVENT_TABLE}?${eventFilter("referral_activation")}&${payloadFilter("referred_anonymous_user_id", referredAnonymousUserId)}&select=anonymous_user_id,payload`,
    { method: "GET" }
  );
}

async function fetchReward(anonymousUserId) {
  const rows = await supabaseFetch(
    `${EVENT_TABLE}?anonymous_user_id=eq.${encodeURIComponent(anonymousUserId)}&${eventFilter("referral_reward")}&select=payload,submitted_at&order=submitted_at.desc&limit=1`,
    { method: "GET" }
  );
  return rows[0]?.payload || null;
}

function uniqueReferralCount(rows) {
  return new Set(
    rows
      .map((row) => cleanText(row.payload?.referred_anonymous_user_id, 80))
      .filter(Boolean)
  ).size;
}

function rewardPayload(reward) {
  const active = reward?.reward_ends_at && new Date(reward.reward_ends_at).getTime() > Date.now();
  return {
    reward_unlocked: Boolean(active),
    reward_ends_at: active ? reward.reward_ends_at : null,
  };
}

async function ensureReward(referrerAnonymousUserId, count) {
  const existing = await fetchReward(referrerAnonymousUserId);
  if (existing) return existing;
  if (count < REQUIRED_REFERRALS_FOR_REWARD) return null;

  const rewardEndsAt = new Date(Date.now() + REWARD_DAYS * 24 * 60 * 60 * 1000).toISOString();
  const payload = {
    event: "referral_reward",
    reward_days: REWARD_DAYS,
    reward_ends_at: rewardEndsAt,
    required_referrals: REQUIRED_REFERRALS_FOR_REWARD,
    referral_count_at_unlock: count,
  };

  await supabaseFetch(EVENT_TABLE, {
    method: "POST",
    headers: { prefer: "return=minimal" },
    body: JSON.stringify({
      anonymous_user_id: referrerAnonymousUserId,
      schema_version: 1,
      payload,
      insight: { event: "referral_reward" },
      platform: "ios",
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

async function statusFor(referrerAnonymousUserId) {
  const activations = await fetchReferralActivations(referrerAnonymousUserId);
  const count = uniqueReferralCount(activations);
  const reward = await ensureReward(referrerAnonymousUserId, count);
  return {
    referral_count: count,
    required_referrals: REQUIRED_REFERRALS_FOR_REWARD,
    reward_days: REWARD_DAYS,
    ...rewardPayload(reward),
  };
}

async function registerActivation(body) {
  const referrer = cleanText(body.referrer_anonymous_user_id, 80);
  const referred = cleanText(body.referred_anonymous_user_id, 80);

  if (!referrer || !referred) {
    return json(400, { error: "missing_referrer_or_referred" });
  }

  if (referrer === referred) {
    return json(200, {
      ok: true,
      accepted: false,
      reason: "self_referral",
      ...(await statusFor(referrer)),
    });
  }

  const existing = await fetchReferredActivation(referred);
  const alreadyAccepted = existing.find((row) => row.anonymous_user_id === referrer);
  const alreadyOtherReferrer = existing.find((row) => row.anonymous_user_id !== referrer);

  if (alreadyOtherReferrer) {
    return json(200, {
      ok: true,
      accepted: false,
      reason: "already_referred",
      ...(await statusFor(referrer)),
    });
  }

  if (!alreadyAccepted) {
    await supabaseFetch(EVENT_TABLE, {
      method: "POST",
      headers: { prefer: "return=minimal" },
      body: JSON.stringify({
        anonymous_user_id: referrer,
        schema_version: 1,
        payload: {
          event: "referral_activation",
          referrer_anonymous_user_id: referrer,
          referred_anonymous_user_id: referred,
          source: cleanText(body.source, 40) || "ios",
        },
        insight: { event: "referral_activation" },
        platform: "ios",
        locale: cleanText(body.locale, 40),
        app_version: cleanText(body.app_version, 40),
        build_number: cleanText(body.build_number, 40),
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

  return json(200, {
    ok: true,
    accepted: true,
    ...(await statusFor(referrer)),
  });
}

async function status(body) {
  const referrer = cleanText(body.anonymous_user_id, 80);
  if (!referrer) {
    return json(400, { error: "missing_user_id" });
  }

  return json(200, {
    ok: true,
    ...(await statusFor(referrer)),
  });
}

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;

  try {
    const body = parseJsonBody(event);
    const action = cleanText(body.action, 40);

    if (action === "register_activation") {
      return registerActivation(body);
    }
    if (action === "status") {
      return status(body);
    }

    return json(400, { error: "unknown_action" });
  } catch (error) {
    return json(500, { error: "referral_request_failed", detail: error.message });
  }
};
