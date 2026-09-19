"use strict";

function clean(value, max = 600) {
  return String(value == null ? "" : value).trim().replace(/\s+/g, " ").slice(0, max);
}

function fold(value) {
  return clean(value).normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
}

function windows(context = {}) {
  const values = context.schedule?.windows || context.user_context?.schedule?.windows || [];
  return Array.isArray(values) ? values.filter((item) => item && item.enabled !== false) : [];
}

function clockLabel(value) {
  const minute = ((Number(value) % 1440) + 1440) % 1440;
  const hour24 = Math.floor(minute / 60);
  const hour12 = hour24 % 12 || 12;
  return `${hour12}:${String(minute % 60).padStart(2, "0")} ${hour24 < 12 ? "AM" : "PM"}`;
}

function parseClock(hour, minute, meridiem) {
  let h = Number(hour), m = Number(minute || 0);
  if (!Number.isInteger(h) || !Number.isInteger(m) || m > 59 || h > 23) return null;
  const marker = fold(meridiem).replace(/\./g, "");
  if (marker) {
    if (h < 1 || h > 12) return null;
    h = h % 12 + (/pm|tarde|noche/.test(marker) ? 12 : 0);
  }
  return h * 60 + m;
}

function mentionedRanges(prompt) {
  const text = fold(prompt);
  const pattern = /(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?|am|pm|de la manana|de la tarde|de la noche)?\s*(?:to|until|through|a|hasta|[-–])\s*(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?|am|pm|de la manana|de la tarde|de la noche)?/g;
  const result = [];
  for (const match of text.matchAll(pattern)) {
    const shared = match[6] || match[3] || "";
    const start = parseClock(match[1], match[2], match[3] || shared);
    const end = parseClock(match[4], match[5], match[6] || shared);
    if (start != null && end != null && start !== end) result.push({ start, end });
  }
  return result;
}

function findWindow(items, range) {
  if (!range) return null;
  const matches = items.filter((item) => item.start_minute === range.start && item.end_minute === range.end);
  return matches.length === 1 ? matches[0] : null;
}

function basePlan(text, actions = []) {
  const requiresScreenTime = actions.some((item) => item?.type === "update_schedule");
  return {
    intent: "schedule_management",
    title: "Blocking schedules",
    response_text: text,
    message_text: text,
    speech_text: text,
    followup_text: "",
    bullets: [],
    primary_label: "",
    secondary_label: "",
    actions,
    requires_selected_apps: false,
    requires_screen_time_authorization: requiresScreenTime,
    blocking_ready: actions.length > 0,
    blocking_user_request: actions.length > 0,
    blocking_missing_fields: [],
    blocking_data: null,
  };
}

function responseVariant(context, values) {
  const turnCount = Array.isArray(context.recent_messages) ? context.recent_messages.length : 0;
  return values[Math.abs(turnCount) % values.length];
}

function scheduleManagementPlan(prompt, context = {}) {
  const text = fold(prompt);
  const items = windows(context);
  const scheduleWords = /\b(?:blocks?|blocking windows?|schedules?|protection windows?|bloqueos?|ventanas? de bloqueo|horarios?)\b/.test(text);
  if (!scheduleWords) return null;

  const deleteAll = /\b(?:delete|remove|clear|erase|elimina|eliminar|borra|borrar|quita|quitar)\b/.test(text)
    && /\b(?:all|every|todos|todas)\b/.test(text);
  if (deleteAll) {
    if (!items.length) return basePlan("You don't have any blocking windows to remove.");
    const target = items.length === 1 ? "it" : "all of them";
    return basePlan(responseVariant(context, [
      `I found ${items.length} blocking ${items.length === 1 ? "window" : "windows"}. Tap the Blankmind notification to remove ${target}.`,
      `You have ${items.length} blocking ${items.length === 1 ? "window" : "windows"}. I've queued the removal, so just confirm it from the Blankmind notification.`,
      `There ${items.length === 1 ? "is" : "are"} ${items.length} blocking ${items.length === 1 ? "window" : "windows"} to clear. Confirm the Blankmind notification and ${target === "it" ? "it will be removed" : "they will all be removed"}.`,
    ]), [{
      type: "delete_all_schedules",
    }]);
  }

  const query = /\b(?:what|which|show|list|tell me|do i have|que|cuales|dime|muestra|ensena)\b/.test(text)
    && !/\b(?:change|move|shift|edit|modify|update|mueve|cambia|modifica|edita)\b/.test(text);
  if (query) {
    if (!items.length) return basePlan("You don't currently have any recurring blocking windows.");
    const list = items.map((item) => {
      const days = Array.isArray(item.weekdays) && item.weekdays.length < 7 ? ` on days ${item.weekdays.join(", ")}` : " every day";
      return `${clockLabel(item.start_minute)} to ${clockLabel(item.end_minute)}${days}`;
    });
    const details = list.join(". ");
    return basePlan(responseVariant(context, [
      `You currently have ${items.length} blocking ${items.length === 1 ? "window" : "windows"}: ${details}.`,
      `Right now, I can see ${items.length} recurring blocking ${items.length === 1 ? "window" : "windows"}. ${details}.`,
      `Your current recurring protection ${items.length === 1 ? "is" : "windows are"}: ${details}.`,
    ]));
  }

  const edit = /\b(?:change|move|shift|edit|modify|update|mueve|cambia|modifica|edita|retrasa|adelanta)\b/.test(text);
  if (edit) {
    const ranges = mentionedRanges(prompt);
    const target = findWindow(items, ranges[0]);
    if (!target) {
      return basePlan(items.length
        ? "I couldn't match that description to exactly one current blocking window. Tell me its current start and end time."
        : "You don't currently have a blocking window to change.");
    }
    let start = ranges[1]?.start, end = ranges[1]?.end;
    if (start == null || end == null) {
      const amount = text.match(/\b(\d+)\s*(?:hours?|hrs?|horas?|h)\b/);
      const minutes = Number(amount?.[1] || (/\b(?:one|una?)\s+(?:hour|hora)\b/.test(text) ? 1 : 0)) * 60;
      const direction = /\b(?:earlier|before|adelanta|antes)\b/.test(text) ? -1 : /\b(?:later|after|retrasa|mas tarde|despues)\b/.test(text) ? 1 : 0;
      if (minutes && direction) {
        start = (target.start_minute + direction * minutes + 1440) % 1440;
        end = (target.end_minute + direction * minutes + 1440) % 1440;
      }
    }
    if (start == null || end == null) return basePlan("I found that blocking window. What new start and end time do you want?");
    const oldRange = `${clockLabel(target.start_minute)}–${clockLabel(target.end_minute)}`;
    const newRange = `${clockLabel(start)}–${clockLabel(end)}`;
    return basePlan(responseVariant(context, [
      `I'll move that window from ${oldRange} to ${newRange}. Tap the Blankmind notification to apply it.`,
      `Found it. The change is ${oldRange} to ${newRange}. Confirm the Blankmind notification and it's done.`,
      `That window can move one hour to ${newRange}. I've left the final confirmation in Blankmind.`,
    ]), [{
      type: "update_schedule",
      window_id: clean(target.id, 80),
      name: clean(target.name, 80) || "Protection",
      start_minute: start,
      end_minute: end,
      weekdays: Array.isArray(target.weekdays) ? target.weekdays : [1, 2, 3, 4, 5, 6, 7],
    }]);
  }

  const remove = /\b(?:delete|remove|erase|elimina|eliminar|borra|borrar|quita|quitar)\b/.test(text);
  if (remove) {
    const target = findWindow(items, mentionedRanges(prompt)[0]);
    if (!target) return basePlan("Tell me the current start and end time of the blocking window you want to remove.");
    const range = `${clockLabel(target.start_minute)}–${clockLabel(target.end_minute)}`;
    return basePlan(responseVariant(context, [
      `I found the ${range} window. Tap the Blankmind notification to remove it.`,
      `Yes, the ${range} blocking window exists. Confirm the Blankmind notification and I'll remove it.`,
      `The ${range} window is ready to be deleted. It only needs your confirmation in Blankmind.`,
    ]), [{
      type: "delete_schedule",
      window_id: clean(target.id, 80),
    }]);
  }
  return null;
}

function personalizedRecommendationPlan(prompt, context = {}) {
  const text = fold(prompt);
  const asksForRecommendation = /\b(?:what.*(?:best|better|suit)|recommend.*(?:week|me)|que.*(?:conviene|recomiendas).*semana|qué.*(?:conviene|recomiendas).*semana)\b/.test(text);
  if (!asksForRecommendation) return null;
  const items = windows(context);
  const outcomes = Array.isArray(context.recent_plan_outcomes) ? context.recent_plan_outcomes : [];
  const held = outcomes.find((item) => fold(item?.outcome) === "held");
  const broke = outcomes.find((item) => /^(?:broke|failed)$/.test(fold(item?.outcome)));
  const insight = clean(context.latest_insight?.summary || context.latest_insight?.pattern || context.personal_profile?.weak_moment, 160);
  const breakCount = Number.isFinite(Number(context.weekly_break_count)) ? Number(context.weekly_break_count) : null;
  const adherence = Number.isFinite(Number(context.adherence_score)) ? Number(context.adherence_score) : null;

  if (items.length) {
    const current = items[0];
    const range = `${clockLabel(current.start_minute)}–${clockLabel(current.end_minute)}`;
    const reason = insight ? ` Your recent context still points to ${insight.charAt(0).toLowerCase()}${insight.slice(1)}.` : "";
    const measure = breakCount != null
      ? ` Aim to bring breaks from ${breakCount} to ${Math.max(0, breakCount - 1)} before making it stricter.`
      : adherence != null ? ` Keep it stable until adherence is consistently above ${Math.max(80, Math.round(adherence))}%.` : " Review it after seven days before increasing intensity.";
    if (held) {
      return basePlan(responseVariant(context, [
        `This week, keep your ${range} blocking window.${reason}${measure}`,
        `I wouldn't make the plan stricter yet. Your ${range} window has held, so repeat it this week.${reason}${measure}`,
        `The best move this week is consistency: keep ${range} unchanged.${reason}${measure}`,
      ]));
    }
    if (broke) {
      const earlierStart = (current.start_minute + 1425) % 1440;
      return basePlan(responseVariant(context, [
        `This week, make the current window easier to hold: start at ${clockLabel(earlierStart)} and keep the same end time.${reason}`,
        `Your last plan broke, so I would change one thing only: move the ${range} window 15 minutes earlier.${reason}`,
        `A lighter adjustment fits this week better than more restriction. Shift ${range} 15 minutes earlier and review it after seven days.${reason}`,
      ]));
    }
    return basePlan(responseVariant(context, [
      `This week, keep the ${range} window and judge it by whether breaks fall.${reason}${measure}`,
      `Your clearest experiment is the existing ${range} protection for seven days.${reason}${measure}`,
      `I would hold ${range} steady this week instead of adding another rule.${reason}${measure}`,
    ]));
  }

  const weakMoment = clean(context.personal_profile?.weak_moment || context.latest_insight?.summary, 120);
  if (weakMoment) return basePlan(`This week, start with one small protection around ${weakMoment.charAt(0).toLowerCase()}${weakMoment.slice(1)}. Tell me the exact start and end time and I'll prepare it.`);
  return basePlan("I don't have enough recent phone context to choose a good weekly change yet. Which moment is costing you the most attention right now?");
}

module.exports = { scheduleManagementPlan, personalizedRecommendationPlan, mentionedRanges, responseVariant };
