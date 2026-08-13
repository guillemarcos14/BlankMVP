const {
  json,
  parseJsonBody,
  requireMethod,
  supabaseFetch,
} = require("./_membership");

function cleanText(value, maxLength = 160) {
  return String(value || "").trim().slice(0, maxLength);
}

function cleanNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;

  try {
    const body = parseJsonBody(event);
    const anonymousUserId = cleanText(body.anonymous_user_id, 80);

    if (!anonymousUserId || body.data_consent !== true) {
      return json(400, { error: "missing_consent_or_user_id" });
    }

    await supabaseFetch("onboarding_responses?on_conflict=anonymous_user_id", {
      method: "POST",
      headers: { prefer: "return=minimal,resolution=merge-duplicates" },
      body: JSON.stringify({
        anonymous_user_id: anonymousUserId,
        name: cleanText(body.name, 120),
        age_range: cleanText(body.age_range, 40),
        goal: cleanText(body.goal, 120),
        profile: cleanText(body.profile, 80),
        daily_hours: cleanNumber(body.daily_hours),
        ai_goal: cleanText(body.ai_goal, 180),
        weak_moment: cleanText(body.weak_moment, 180),
        selected_plan: cleanText(body.selected_plan, 40),
        locale: cleanText(body.locale, 40),
        app_version: cleanText(body.app_version, 40),
        build_number: cleanText(body.build_number, 40),
        platform: "ios",
        data_consent: true,
        consent_text: cleanText(body.consent_text, 240),
        submitted_at: new Date().toISOString(),
      }),
    });

    return json(200, { ok: true });
  } catch (error) {
    return json(500, { error: "onboarding_response_failed", detail: error.message });
  }
};
