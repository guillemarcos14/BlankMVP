const { getSupabaseUser, json, parseJsonBody, requireMethod, supabaseFetch } = require("./_membership");
const { cleanText } = require("./_identity");
const {
  currentFacts,
  deleteUserData,
  recordEvent,
  userByAuthUser,
  withdrawConsent,
} = require("./_waitlist_store");

async function exportData(user) {
  const [facts, messages, events] = await Promise.all([
    currentFacts(user.id),
    supabaseFetch(
      `waitlist_messages?user_id=eq.${encodeURIComponent(user.id)}&select=direction,message_kind,body,source_language,created_at&order=created_at.asc`,
      { method: "GET" },
    ),
    supabaseFetch(
      `waitlist_events?user_id=eq.${encodeURIComponent(user.id)}&select=event_name,created_at&order=created_at.asc`,
      { method: "GET" },
    ),
  ]);
  return {
    profile: facts.profile,
    facts: facts.rows.map((fact) => ({
      field: fact.field_key,
      value: fact.value,
      evidence: fact.evidence_excerpt,
      confidence: fact.confidence,
      status: fact.status,
      created_at: fact.created_at,
    })),
    messages,
    events,
  };
}

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;
  try {
    const authUser = await getSupabaseUser(event);
    if (!authUser?.id) return json(401, { error: "waitlist_auth_required" });
    const user = await userByAuthUser(authUser.id);
    if (!user) return json(404, { error: "waitlist_user_not_found" });
    const body = parseJsonBody(event);
    const action = cleanText(body.action, 40).toLowerCase();

    if (action === "status") {
      const facts = await currentFacts(user.id);
      return json(200, {
        ok: true,
        status: user.status,
        opening_sent: Boolean(user.opening_sent_at),
        profile_useful: Boolean(user.profile_useful_at),
        known_fields: Object.keys(facts.profile),
      });
    }
    if (action === "export") {
      await recordEvent(user.id, "data_exported", {});
      return json(200, { ok: true, data: await exportData(user) });
    }
    if (action === "withdraw") {
      await recordEvent(user.id, "consent_withdrawn_web", {});
      await withdrawConsent(user);
      return json(200, { ok: true, status: "withdrawn" });
    }
    if (action === "delete" && body.confirm === true) {
      await deleteUserData(user.id);
      return json(200, { ok: true, deleted: true });
    }
    return json(400, { error: "unsupported_action" });
  } catch (error) {
    return json(500, { error: "waitlist_data_failed", detail: cleanText(error.message, 240) });
  }
};
