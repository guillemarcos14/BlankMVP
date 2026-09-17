// Links are only for setup that requires the user to select apps or grant permission.
const REVIEW_TYPES = new Set([
  "start_protection", "apply_schedule", "set_daily_limit",
  "enable_allow_only", "enable_adult_filter", "pause_rules", "disable_pause",
  "open_app_picker", "request_screen_time_permission", "apply_ai_plan",
]);

function reviewActionLink(action, appNames = []) {
  if (!action || !REVIEW_TYPES.has(action.type)) return "";
  if (action.type === "apply_schedule" && (
    !Number.isInteger(action.start_minute) || action.start_minute < 0 || action.start_minute > 1439
    || !Number.isInteger(action.end_minute) || action.end_minute < 0 || action.end_minute > 1439
    || action.start_minute === action.end_minute
  )) return "";
  const base = (process.env.BLANKED_PUBLIC_APP_LINK_BASE || "https://getblank.netlify.app").replace(/\/$/, "");
  const query = new URLSearchParams({ action: "review-action", type: action.type });
  const apps = Array.isArray(appNames)
    ? appNames.filter((app) => app && app !== "selected_apps" && !String(app).startsWith("mode:"))
    : [];
  // Match the canonical state capacity; partial app lists misrepresent the proposal.
  if (apps.length > 12) return "";
  const params = {
    apps: apps.length ? apps.join(",") : null,
    name: action.name || null,
    minutes: Number.isFinite(action.minutes) ? action.minutes : null,
    hard: action.hard_mode === true ? "true" : null,
    start: Number.isFinite(action.start_minute) ? action.start_minute : null,
    end: Number.isFinite(action.end_minute) ? action.end_minute : null,
    days: Number.isFinite(action.duration_days) ? action.duration_days : null,
    weekdays: Array.isArray(action.weekdays) && action.weekdays.length ? action.weekdays.join(",") : null,
    hours: Number.isFinite(action.hours) ? action.hours : null,
  };
  for (const [key, value] of Object.entries(params)) {
    if (value !== null) query.set(key, String(value));
  }
  return `${base}/open?${query.toString()}`;
}

module.exports = { reviewActionLink };
