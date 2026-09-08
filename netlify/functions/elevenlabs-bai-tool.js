const { json, parseJsonBody, requireMethod } = require("./_membership");
const { handler: blankedAgentHandler } = require("./blanked-agent");
const { cleanText } = require("./_elevenlabs_voice");

function publicOpenLink(actionName, params = {}) {
  const base = (process.env.BLANKED_PUBLIC_APP_LINK_BASE || "https://getblank.netlify.app").replace(/\/$/, "");
  const query = new URLSearchParams({ action: actionName });
  for (const [key, value] of Object.entries(params)) {
    if (value == null || value === "") continue;
    query.set(key, String(value));
  }
  return `${base}/open?${query.toString()}`;
}

function primaryAction(actions) {
  const executable = Array.isArray(actions) ? actions.filter((item) => item && item.type && item.type !== "none") : [];
  return executable.find((item) => item.type === "apply_schedule") || executable[0] || null;
}

function clamp(value, lower, upper) {
  const number = Number(value);
  if (!Number.isFinite(number)) return lower;
  return Math.min(Math.max(Math.round(number), lower), upper);
}

function actionLink(actions) {
  const action = primaryAction(actions);
  if (!action) return "";
  if (action.type === "start_protection") {
    return publicOpenLink("start-focus", { minutes: clamp(action.minutes || 25, 5, 240), hard: action.hard_mode ? "true" : "" });
  }
  if (action.type === "apply_schedule") {
    return publicOpenLink("apply-plan", {
      start: clamp(action.start_minute || 1260, 0, 1439),
      end: clamp(action.end_minute || 1380, 0, 1439),
      days: clamp(action.duration_days || 7, 1, 14),
    });
  }
  if (action.type === "set_daily_limit") return publicOpenLink("daily-limit", { minutes: clamp(action.minutes || 25, 5, 240) });
  if (action.type === "open_app_picker" || action.type === "request_screen_time_permission") return publicOpenLink("open-picker", { source: "elevenlabs" });
  if (action.type === "enable_allow_only") return publicOpenLink("allow-only");
  if (action.type === "enable_adult_filter") return publicOpenLink("adult-filter");
  if (action.type === "pause_rules") return publicOpenLink("pause-rules", { hours: clamp(action.hours || 24, 1, 168) });
  if (action.type === "disable_pause") return publicOpenLink("resume-rules");
  return "";
}

function toolResult(plan) {
  const message = cleanText(plan.message_text || plan.response_text, 900) || "I can help with that in Blanked.";
  const link = actionLink(plan.actions || []);
  return link ? `${message}\n\nOpen Blanked to apply it: ${link}` : message;
}

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;

  try {
    const body = parseJsonBody(event);
    const prompt = cleanText(body.prompt || body.text || body.transcript || body.user_message, 900);
    if (!prompt) return json(400, { error: "missing_prompt" });

    const response = await blankedAgentHandler({
      httpMethod: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        prompt,
        locale: body.locale || "en-US",
        context: {
          channel: "elevenlabs",
          assistant_channel: body.assistant_channel || "call",
          has_selected_apps: body.has_selected_apps !== false,
          screen_time_authorized: body.screen_time_authorized !== false,
          memory: body.memory && typeof body.memory === "object" ? body.memory : {},
        },
      }),
    });
    const parsed = JSON.parse(response.body || "{}");
    if (response.statusCode < 200 || response.statusCode >= 300 || !parsed.ok) {
      return json(502, { error: "blanked_agent_failed" });
    }
    return json(200, { result: toolResult(parsed.plan || {}) });
  } catch (error) {
    return json(500, { error: "elevenlabs_bai_tool_failed", detail: error.message });
  }
};
