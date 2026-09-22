const { supabaseFetch } = require("./_membership");
const { cleanText, normalizePhone } = require("./_identity");

const PROFILE_USEFUL_KEYS = new Set([
  "preferred_name",
  "age",
  "occupation",
  "studies",
  "scroll_moments",
  "scroll_contexts",
  "apps",
  "impact",
  "desired_change",
]);

const MERGEABLE_LIST_KEYS = new Set([
  "scroll_moments",
  "scroll_contexts",
  "apps",
  "content_types",
  "triggers",
  "feelings",
  "attempted_solutions",
  "goals",
  "interests",
  "responsibilities",
  "relationships",
]);

function now() {
  return new Date().toISOString();
}

function phoneForStorage(value) {
  const normalized = normalizePhone(value);
  if (!normalized) return "";
  return normalized.startsWith("+") ? normalized : `+${normalized}`;
}

async function userByPhone(phoneValue) {
  const phone = phoneForStorage(phoneValue);
  if (!phone) return null;
  const rows = await supabaseFetch(
    `waitlist_users?phone_e164=eq.${encodeURIComponent(phone)}&select=*`,
    { method: "GET" },
  );
  return rows[0] || null;
}

async function userByAuthUser(authUserId) {
  const id = cleanText(authUserId, 80);
  if (!id) return null;
  const rows = await supabaseFetch(
    `waitlist_users?auth_user_id=eq.${encodeURIComponent(id)}&select=*`,
    { method: "GET" },
  );
  return rows[0] || null;
}

async function ensureUser({ authUserId = "", phone, dataConsent = false, whatsappConsent = false }) {
  const normalizedPhone = phoneForStorage(phone);
  const normalizedAuthUserId = cleanText(authUserId, 80);
  if (!normalizedPhone) throw new Error("waitlist_phone_invalid");

  const [byPhone, byAuth] = await Promise.all([
    userByPhone(normalizedPhone),
    normalizedAuthUserId ? userByAuthUser(normalizedAuthUserId) : Promise.resolve(null),
  ]);

  if (byPhone && byAuth && byPhone.id !== byAuth.id) throw new Error("waitlist_identity_conflict");
  const existing = byPhone || byAuth;
  const consented = dataConsent === true && whatsappConsent === true;
  const update = {
    phone_e164: normalizedPhone,
    updated_at: now(),
    ...(normalizedAuthUserId ? { auth_user_id: normalizedAuthUserId } : {}),
    ...(consented ? {
      data_consent: true,
      whatsapp_consent: true,
      consented_at: existing?.consented_at || now(),
      status: "active",
    } : {}),
  };

  if (existing) {
    if (existing.auth_user_id && normalizedAuthUserId && existing.auth_user_id !== normalizedAuthUserId) {
      throw new Error("waitlist_identity_conflict");
    }
    const rows = await supabaseFetch(`waitlist_users?id=eq.${encodeURIComponent(existing.id)}&select=*`, {
      method: "PATCH",
      headers: { prefer: "return=representation" },
      body: JSON.stringify(update),
    });
    return rows[0] || { ...existing, ...update };
  }

  const rows = await supabaseFetch("waitlist_users?select=*", {
    method: "POST",
    headers: { prefer: "return=representation" },
    body: JSON.stringify({
      ...update,
      data_consent: consented,
      whatsapp_consent: consented,
      consented_at: consented ? now() : null,
      status: consented ? "active" : "paused",
    }),
  });
  return rows[0];
}

async function patchUser(userId, updates) {
  const rows = await supabaseFetch(`waitlist_users?id=eq.${encodeURIComponent(userId)}&select=*`, {
    method: "PATCH",
    headers: { prefer: "return=representation" },
    body: JSON.stringify({ ...updates, updated_at: now() }),
  });
  return rows[0] || null;
}

async function recordMessage({
  userId,
  provider,
  providerMessageId = null,
  direction,
  messageKind = "text",
  body,
  sourceLanguage = null,
}) {
  const rows = await supabaseFetch("waitlist_messages?select=*", {
    method: "POST",
    headers: { prefer: "return=representation,resolution=ignore-duplicates" },
    body: JSON.stringify({
      user_id: userId,
      provider,
      provider_message_id: providerMessageId || null,
      direction,
      message_kind: messageKind,
      body: cleanText(body, 4000),
      source_language: cleanText(sourceLanguage, 20) || null,
    }),
  });
  await patchUser(userId, {
    last_message_at: now(),
  }).catch(() => null);
  return rows[0] || null;
}

async function markFirstReply(user) {
  if (!user || user.first_reply_at) return user;
  return patchUser(user.id, { first_reply_at: now() });
}

async function recentMessages(userId, limit = 16) {
  const safeLimit = Math.min(Math.max(Number(limit) || 16, 1), 30);
  const rows = await supabaseFetch(
    `waitlist_messages?user_id=eq.${encodeURIComponent(userId)}&select=id,direction,message_kind,body,source_language,created_at&order=created_at.desc&limit=${safeLimit}`,
    { method: "GET" },
  );
  return rows.reverse();
}

async function currentFacts(userId) {
  const rows = await supabaseFetch(
    `waitlist_facts?user_id=eq.${encodeURIComponent(userId)}&status=in.(confirmed,uncertain)&select=*&order=created_at.asc`,
    { method: "GET" },
  );
  const profile = {};
  for (const fact of rows) {
    if (fact.status === "confirmed" || profile[fact.field_key] === undefined) {
      profile[fact.field_key] = fact.value;
    }
  }
  return { rows, profile };
}

function mergeValue(previous, next, operation, fieldKey) {
  if (operation === "correct") return next;
  if (operation !== "add" && !MERGEABLE_LIST_KEYS.has(fieldKey)) return next;
  const left = Array.isArray(previous) ? previous : previous == null ? [] : [previous];
  const right = Array.isArray(next) ? next : next == null ? [] : [next];
  const seen = new Set();
  return [...left, ...right].filter((item) => {
    const key = JSON.stringify(item).toLowerCase();
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

async function persistFacts({ user, sourceMessageId, facts }) {
  if (!Array.isArray(facts) || !facts.length) return [];
  const existing = await currentFacts(user.id);
  const saved = [];

  for (const fact of facts) {
    const previousRows = existing.rows.filter((item) => item.field_key === fact.key && item.status !== "superseded");
    const previous = previousRows.at(-1) || null;
    const value = mergeValue(previous?.value, fact.value, fact.operation, fact.key);

    if (fact.operation === "remove") {
      if (previous) {
        await supabaseFetch(`waitlist_facts?id=eq.${encodeURIComponent(previous.id)}`, {
          method: "PATCH",
          body: JSON.stringify({ status: "superseded", updated_at: now() }),
        });
      }
      continue;
    }

    if (previous) {
      await supabaseFetch(`waitlist_facts?id=eq.${encodeURIComponent(previous.id)}`, {
        method: "PATCH",
        body: JSON.stringify({ status: "superseded", updated_at: now() }),
      });
    }

    const rows = await supabaseFetch("waitlist_facts?select=*", {
      method: "POST",
      headers: { prefer: "return=representation" },
      body: JSON.stringify({
        user_id: user.id,
        field_key: fact.key,
        value,
        normalized_text: fact.normalizedText || null,
        source_message_id: sourceMessageId || null,
        evidence_excerpt: fact.evidence,
        confidence: fact.confidence,
        status: fact.status,
        supersedes_fact_id: previous?.id || null,
      }),
    });
    if (rows[0]) {
      saved.push(rows[0]);
      existing.rows.push(rows[0]);
      existing.profile[fact.key] = value;
    }
  }

  const usefulCount = Array.from(PROFILE_USEFUL_KEYS).filter((key) => existing.profile[key] !== undefined).length;
  const hasIdentity = Boolean(existing.profile.preferred_name && (existing.profile.age !== undefined || existing.profile.age_band));
  if (!user.profile_useful_at && usefulCount >= 4 && hasIdentity) {
    await patchUser(user.id, { profile_useful_at: now() });
    await recordEvent(user.id, "profile_useful", { useful_fields: usefulCount });
  }
  return saved;
}

async function recordEvent(userId, eventName, properties = {}) {
  await supabaseFetch("waitlist_events", {
    method: "POST",
    body: JSON.stringify({
      user_id: userId || null,
      event_name: cleanText(eventName, 80),
      properties,
    }),
  });
}

async function claimInbound(provider, providerMessageId) {
  if (!providerMessageId) return { claimed: true, status: "no_id" };
  const rows = await supabaseFetch("rpc/claim_waitlist_inbound", {
    method: "POST",
    body: JSON.stringify({
      p_provider: provider,
      p_provider_message_id: providerMessageId,
      p_lease_seconds: 300,
    }),
  });
  return rows[0] || { claimed: false, status: "unknown" };
}

async function completeInbound(provider, providerMessageId) {
  if (!providerMessageId) return true;
  return supabaseFetch("rpc/complete_waitlist_inbound", {
    method: "POST",
    body: JSON.stringify({ p_provider: provider, p_provider_message_id: providerMessageId }),
  });
}

async function releaseInbound(provider, providerMessageId) {
  if (!providerMessageId) return true;
  return supabaseFetch("rpc/release_waitlist_inbound", {
    method: "POST",
    body: JSON.stringify({ p_provider: provider, p_provider_message_id: providerMessageId }),
  });
}

async function withdrawConsent(user) {
  return patchUser(user.id, {
    status: "withdrawn",
    data_consent: false,
    whatsapp_consent: false,
  });
}

async function deleteUserData(userId) {
  await supabaseFetch(`waitlist_users?id=eq.${encodeURIComponent(userId)}`, { method: "DELETE" });
}

module.exports = {
  claimInbound,
  completeInbound,
  currentFacts,
  deleteUserData,
  ensureUser,
  markFirstReply,
  mergeValue,
  patchUser,
  persistFacts,
  phoneForStorage,
  recentMessages,
  recordEvent,
  recordMessage,
  releaseInbound,
  userByAuthUser,
  userByPhone,
  withdrawConsent,
};
