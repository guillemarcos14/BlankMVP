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
  const text = fold(prompt).replace(/\bmidnight\b|\bmedianoche\b/g, "12:00 am").replace(/\bnoon\b|\bmediodia\b/g, "12:00 pm");
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

function mentionedClocks(prompt) {
  const text = fold(prompt).replace(/\bmidnight\b|\bmedianoche\b/g, "12:00 am").replace(/\bnoon\b|\bmediodia\b/g, "12:00 pm");
  const pattern = /\b(?:(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?|am|pm|de la manana|de la tarde|de la noche)|(\d{1,2}):(\d{2}))\b/g;
  const result = [];
  for (const match of text.matchAll(pattern)) {
    const value = match[1] != null ? parseClock(match[1], match[2], match[3]) : parseClock(match[4], match[5], "");
    if (value != null) result.push(value);
  }
  return result;
}

const DAYS = [
  ["Sunday", /\b(?:sunday|sundays|domingo|domingos)\b/],
  ["Monday", /\b(?:monday|mondays|lunes)\b/],
  ["Tuesday", /\b(?:tuesday|tuesdays|martes)\b/],
  ["Wednesday", /\b(?:wednesday|wednesdays|miercoles)\b/],
  ["Thursday", /\b(?:thursday|thursdays|jueves)\b/],
  ["Friday", /\b(?:friday|fridays|viernes)\b/],
  ["Saturday", /\b(?:saturday|saturdays|sabado|sabados)\b/],
];

function parsedWeekdays(text) {
  if (/\b(?:every day|daily|all days|todos los dias|cada dia)\b/.test(text)) return [1, 2, 3, 4, 5, 6, 7];
  if (/\b(?:weekdays|monday (?:to|through) friday|entre semana|lunes a viernes)\b/.test(text)) return [2, 3, 4, 5, 6];
  if (/\b(?:weekends|weekend|fin de semana|fines de semana)\b/.test(text)) return [1, 7];
  const days = DAYS.map(([, pattern], index) => pattern.test(text) ? index + 1 : null).filter(Boolean);
  return days.length ? days : null;
}

function weekdayLabel(values) {
  const days = Array.from(new Set((Array.isArray(values) ? values : []).filter((day) => Number.isInteger(day) && day >= 1 && day <= 7))).sort();
  if (!days.length || days.length === 7) return "every day";
  if (days.join(",") === "2,3,4,5,6") return "on weekdays";
  if (days.join(",") === "1,7") return "on weekends";
  const names = days.map((day) => DAYS[day - 1][0]);
  return `on ${names.length > 1 ? `${names.slice(0, -1).join(", ")} and ${names.at(-1)}` : names[0]}`;
}

function recentText(context = {}) {
  return (Array.isArray(context.recent_messages) ? context.recent_messages : []).slice(-6).map((message) => fold(message?.content)).join(" ");
}

function hasScheduleContext(context = {}) {
  return /\b(?:block|blocking|window|schedule|protection|recurring|routine|rule|bloqueo|ventana|horario|proteccion)\b/.test(recentText(context));
}

function responseVariant(context, values) {
  const recent = new Set((Array.isArray(context.recent_messages) ? context.recent_messages : []).filter((message) => message?.role === "assistant").map((message) => fold(message.content)));
  const start = (Array.isArray(context.recent_messages) ? context.recent_messages.length : 0) % values.length;
  for (let offset = 0; offset < values.length; offset += 1) {
    const candidate = values[(start + offset) % values.length];
    if (!recent.has(fold(candidate))) return candidate;
  }
  return values[start];
}

function basePlan(text, actions = [], responseContract = null) {
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
    ...(responseContract ? { response_contract: responseContract } : {}),
  };
}

function contract(operation, facts, requiredPhrases = [], allowedMinutes = []) {
  return { operation, facts, required_phrases: requiredPhrases, allowed_minutes: allowedMinutes };
}

function exactRangeMatches(items, range) {
  if (!range) return [];
  return items.filter((item) => item.start_minute === range.start && item.end_minute === range.end);
}

function partOfDayMatches(items, text) {
  if (/\b(?:morning|manana)\b/.test(text)) return items.filter((item) => item.start_minute < 12 * 60);
  if (/\b(?:afternoon|tarde)\b/.test(text)) return items.filter((item) => item.start_minute >= 12 * 60 && item.start_minute < 18 * 60);
  if (/\b(?:evening|night|noche)\b/.test(text)) return items.filter((item) => item.start_minute >= 18 * 60 || item.start_minute < 5 * 60);
  return [];
}

function resolveWindow(items, prompt, context, ranges) {
  const text = fold(prompt);
  if (ranges[0]) {
    const exact = exactRangeMatches(items, ranges[0]);
    if (exact.length === 1) return { target: exact[0], consumedRange: 0 };
    if (exact.length > 1) return { ambiguous: true };
  }
  const named = items.filter((item) => clean(item.name, 80) && text.includes(fold(item.name)));
  if (named.length === 1) return { target: named[0], consumedRange: -1 };
  if (named.length > 1) return { ambiguous: true };
  const part = partOfDayMatches(items, text);
  if (part.length === 1) return { target: part[0], consumedRange: -1 };
  if (part.length > 1) return { ambiguous: true };
  const ordinal = text.match(/\b(?:first|second|third|last|primero|segundo|tercero|ultimo)\b/)?.[0];
  if (ordinal) {
    const index = /second|segundo/.test(ordinal) ? 1 : /third|tercero/.test(ordinal) ? 2 : /last|ultimo/.test(ordinal) ? items.length - 1 : 0;
    if (items[index]) return { target: items[index], consumedRange: -1 };
  }
  const recentRanges = mentionedRanges(recentText(context));
  for (const range of recentRanges.reverse()) {
    const exact = exactRangeMatches(items, range);
    if (exact.length === 1) return { target: exact[0], consumedRange: -1 };
  }
  if (items.length === 1 && (/\b(?:it|that|this|one|window|block|schedule|rule|la|esa|esta|ese|ventana|bloqueo|horario|regla)\b/.test(text) || hasScheduleContext(context))) {
    return { target: items[0], consumedRange: -1 };
  }
  return { target: null, ambiguous: items.length > 1 };
}

function amountMinutes(text) {
  const numeric = text.match(/\b(\d+)\s*(minutes?|mins?|minutos?|hours?|hrs?|horas?|h)\b/);
  if (numeric) return Number(numeric[1]) * (/hour|hr|hora|\bh\b/.test(numeric[2]) ? 60 : 1);
  if (/\b(?:half an hour|half hour|media hora)\b/.test(text)) return 30;
  if (/\b(?:one|una?)\s+(?:hour|hora)\b/.test(text)) return 60;
  if (/\b(?:two|dos)\s+(?:hours|horas)\b/.test(text)) return 120;
  return 0;
}

function renamedWindow(prompt, currentName) {
  const match = clean(prompt).match(/\b(?:rename(?: it)?(?: to)?|call it|llam(?:a|alo)|renombra(?:lo)?(?: a)?)\s+["']?([^"']{2,60})["']?$/i);
  return clean(match?.[1], 60) || currentName;
}

function scheduleManagementPlan(prompt, context = {}) {
  const text = fold(prompt);
  const items = windows(context);
  const scheduleWords = /\b(?:blocks?|blocking windows?|schedules?|protection windows?|protections?|recurring|routines?|rules?|bloqueos?|ventanas? de bloqueo|horarios?|protecciones?|rutinas?|reglas?)\b/.test(text);
  const edit = /\b(?:change|move|shift|edit|modify|update|extend|shorten|rename|make|set|adjust|mueve|cambia|modifica|edita|retrasa|adelanta|amplia|acorta|renombra|pon|ajusta)\b/.test(text);
  const remove = /\b(?:delete|remove|clear|erase|elimina|eliminar|borra|borrar|quita|quitar)\b/.test(text);
  const contextualReference = items.length > 0 && hasScheduleContext(context) && /\b(?:it|that|this|one|all|every|everything|la|esa|esta|todos|todo)\b/.test(text);
  if (!scheduleWords && !(contextualReference && (edit || remove))) return null;

  const promptRanges = mentionedRanges(prompt);
  const pluralDelete = /\b(?:blocking windows|schedules|protection windows|bloqueos|ventanas de bloqueo|horarios)\b/.test(text) && promptRanges.length === 0;
  const deleteAll = remove && (/\b(?:all|every|everything|todos|todas|todo)\b/.test(text) || pluralDelete);
  if (deleteAll) {
    if (!items.length) return basePlan("You don't have any blocking windows to remove.", [], contract("delete_all_schedules", { count: 0 }));
    const countPhrase = `${items.length} blocking ${items.length === 1 ? "window" : "windows"}`;
    return basePlan(responseVariant(context, [
      `I found ${countPhrase}. Tap the Blankmind notification to remove ${items.length === 1 ? "it" : "all of them"}.`,
      `There ${items.length === 1 ? "is" : "are"} ${countPhrase} to clear. The final confirmation is in the Blankmind notification.`,
      `${countPhrase[0].toUpperCase()}${countPhrase.slice(1)} will be cleared together once you tap the Blankmind notification.`,
    ]), [{ type: "delete_all_schedules" }], contract("delete_all_schedules", { count: items.length }, ["Blankmind notification"]));
  }

  const query = /\b(?:what|which|show|list|tell me|do i have|active|current|que|cuales|dime|muestra|ensena|tengo)\b/.test(text) && !edit && !remove;
  if (query) {
    if (!items.length) return basePlan("You don't currently have any recurring blocking windows.", [], contract("list_schedules", { windows: [] }));
    const list = items.map((item) => `${clockLabel(item.start_minute)} to ${clockLabel(item.end_minute)} ${weekdayLabel(item.weekdays)}`);
    const details = list.join(". ");
    return basePlan(responseVariant(context, [
      `You currently have ${items.length} blocking ${items.length === 1 ? "window" : "windows"}: ${details}.`,
      `Right now your recurring protection is ${details}.`,
      `${items.length === 1 ? "Your active window runs" : "Your active windows run"} ${details}.`,
      `I can see ${items.length === 1 ? "one recurring window" : `${items.length} recurring windows`}: ${details}.`,
    ]), [], contract("list_schedules", { windows: list }, list, items.flatMap((item) => [item.start_minute, item.end_minute])));
  }

  if (edit) {
    const ranges = promptRanges;
    const resolved = resolveWindow(items, prompt, context, ranges);
    if (!resolved.target) {
      return basePlan(items.length ? "I can change it, but I can't identify exactly one current window yet. Tell me its current time or name." : "You don't currently have a blocking window to change.", [], contract("clarify_schedule_target", { count: items.length }));
    }
    const target = resolved.target;
    if (!clean(target.id, 80)) return basePlan("I can see that window, but it needs one fresh sync from Blankmind before I can change it. Open the app once, then ask me again.", [], contract("refresh_schedule_identity", { time: `${clockLabel(target.start_minute)}–${clockLabel(target.end_minute)}` }));
    const newRange = ranges.find((_, index) => index !== resolved.consumedRange);
    let start = newRange?.start ?? target.start_minute;
    let end = newRange?.end ?? target.end_minute;
    const amount = amountMinutes(text);
    const clockValues = mentionedClocks(prompt);
    const explicitClock = !newRange && (ranges.length === 0 || clockValues.length > 2) ? clockValues.at(-1) : null;
    const later = /\b(?:later|after|extend|retrasa|mas tarde|despues|amplia)\b/.test(text);
    const earlier = /\b(?:earlier|before|shorten|adelanta|antes|acorta)\b/.test(text);
    if (explicitClock != null) {
      if (/\b(?:end|finish|final|termine|acabe)\b/.test(text)) end = explicitClock;
      else if (/\b(?:start|begin|inicio|empiece|empieza)\b/.test(text)) start = explicitClock;
      else {
        const duration = (target.end_minute - target.start_minute + 1440) % 1440;
        start = explicitClock;
        end = (explicitClock + duration) % 1440;
      }
    } else if (!newRange && amount && (later || earlier)) {
      const delta = amount * (earlier ? -1 : 1);
      if (/\b(?:start|begin|inicio|empiece|empieza)\b/.test(text)) start = (start + delta + 1440) % 1440;
      else if (/\b(?:end|finish|final|termine|acabe|extend|amplia|shorten|acorta)\b/.test(text)) end = (end + (/shorten|acorta/.test(text) ? -Math.abs(amount) : delta) + 1440) % 1440;
      else {
        start = (start + delta + 1440) % 1440;
        end = (end + delta + 1440) % 1440;
      }
    }
    const weekdays = parsedWeekdays(text) || (Array.isArray(target.weekdays) ? target.weekdays : [1, 2, 3, 4, 5, 6, 7]);
    const currentName = clean(target.name, 80) || "Protection";
    const name = renamedWindow(prompt, currentName);
    const changed = start !== target.start_minute || end !== target.end_minute || name !== currentName || weekdays.join(",") !== (target.weekdays || [1, 2, 3, 4, 5, 6, 7]).join(",");
    if (!changed) return basePlan("I found that window. What would you like to change: its time, days, or name?", [], contract("clarify_schedule_change", { window_id: clean(target.id, 80) }));
    const oldRange = `${clockLabel(target.start_minute)}–${clockLabel(target.end_minute)}`;
    const newRangeText = `${clockLabel(start)}–${clockLabel(end)}`;
    const newDays = weekdayLabel(weekdays);
    return basePlan(responseVariant(context, [
      `I'll change ${oldRange} to ${newRangeText} ${newDays}. Tap the Blankmind notification to confirm it.`,
      `Found it. The new setup is ${newRangeText} ${newDays}, with the final tap in the Blankmind notification.`,
      `That window is ready to move from ${oldRange} to ${newRangeText} ${newDays}. Confirm it from the Blankmind notification.`,
      `The update keeps everything else intact and changes this window to ${newRangeText} ${newDays}. Tap the Blankmind notification when you're ready.`,
    ]), [{ type: "update_schedule", window_id: clean(target.id, 80), name, start_minute: start, end_minute: end, weekdays }], contract("update_schedule", { window_id: clean(target.id, 80), previous_time: oldRange, new_time: newRangeText, weekdays: newDays, name }, ["Blankmind notification"], [target.start_minute, target.end_minute, start, end]));
  }

  if (remove) {
    const ranges = promptRanges;
    const resolved = resolveWindow(items, prompt, context, ranges);
    if (!resolved.target) return basePlan(items.length ? "Which blocking window should I remove? Tell me its time or name." : "You don't currently have a blocking window to remove.", [], contract("clarify_schedule_target", { count: items.length }));
    const target = resolved.target;
    if (!clean(target.id, 80)) return basePlan("I can see that window, but it needs one fresh sync from Blankmind before I can remove it. Open the app once, then ask me again.", [], contract("refresh_schedule_identity", { time: `${clockLabel(target.start_minute)}–${clockLabel(target.end_minute)}` }));
    const range = `${clockLabel(target.start_minute)}–${clockLabel(target.end_minute)}`;
    return basePlan(responseVariant(context, [
      `I found the ${range} window. Tap the Blankmind notification to remove it.`,
      `The ${range} window is ready to be deleted after you confirm the Blankmind notification.`,
      `Yes, ${range} is one of your current windows. One tap on the Blankmind notification will remove it.`,
      `I'll keep the rest and remove only ${range} once you tap the Blankmind notification.`,
    ]), [{ type: "delete_schedule", window_id: clean(target.id, 80) }], contract("delete_schedule", { window_id: clean(target.id, 80), time: range }, ["Blankmind notification"], [target.start_minute, target.end_minute]));
  }
  return null;
}

function selectedRecommendationWindow(items, context) {
  const riskHour = Number(context.risk_hour ?? context.weak_hour ?? context.strongest_hour);
  if (!Number.isFinite(riskHour)) return items[0];
  const targetMinute = riskHour * 60;
  return [...items].sort((a, b) => Math.abs(a.start_minute - targetMinute) - Math.abs(b.start_minute - targetMinute))[0];
}

function personalizedRecommendationPlan(prompt, context = {}) {
  const text = fold(prompt);
  const asksForRecommendation = /\b(?:what.*(?:best|better|suit)|recommend.*(?:week|me)|what should i do.*week|que.*(?:conviene|recomiendas|vendria mejor|seria mejor).*semana)\b/.test(text);
  if (!asksForRecommendation) return null;
  const items = windows(context);
  const outcomes = Array.isArray(context.recent_plan_outcomes) ? context.recent_plan_outcomes : [];
  const latestOutcome = outcomes[0] || null;
  const outcome = fold(latestOutcome?.outcome);
  const insight = clean(context.latest_insight?.summary || context.latest_insight?.pattern || context.personal_profile?.weak_moment, 160);
  const breakCount = Number.isFinite(Number(context.weekly_break_count)) ? Number(context.weekly_break_count) : null;
  const adherence = Number.isFinite(Number(context.adherence_score)) ? Number(context.adherence_score) : null;

  if (items.length) {
    const current = selectedRecommendationWindow(items, context);
    const range = `${clockLabel(current.start_minute)}–${clockLabel(current.end_minute)}`;
    const reason = insight ? ` The clearest recent signal is that ${insight.charAt(0).toLowerCase()}${insight.slice(1)}.` : "";
    const measure = breakCount != null ? ` Use ${Math.max(0, breakCount - 1)} or fewer breaks as the test before making it stricter.` : adherence != null ? ` Keep it stable until adherence is consistently above ${Math.max(80, Math.round(adherence))}%.` : " Review it after seven days before increasing the restriction.";
    if (outcome === "held") {
      const textValue = responseVariant(context, [`This week, keep your ${range} blocking window.${reason}${measure}`, `I wouldn't make the plan stricter yet. ${range} held up, so consistency is the better experiment this week.${reason}${measure}`, `The strongest move this week is to leave ${range} unchanged.${reason}${measure}`]);
      return basePlan(textValue, [], contract("weekly_recommendation", { recommendation: "keep_current_window", time: range, evidence: insight, latest_outcome: outcome, success_measure: measure.trim() }, [range], [current.start_minute, current.end_minute]));
    }
    if (/^(?:broke|failed)$/.test(outcome)) {
      const earlierStart = (current.start_minute + 1425) % 1440;
      const proposed = `${clockLabel(earlierStart)}–${clockLabel(current.end_minute)}`;
      const textValue = responseVariant(context, [`Your latest plan didn't hold, so I'd change one thing only this week: start the ${range} window 15 minutes earlier, at ${clockLabel(earlierStart)}.${reason} If that feels right, I can prepare the change.`, `A smaller adjustment fits the evidence better than adding more restriction. Shift ${range} to ${proposed} for seven days.${reason} I can prepare it when you want.`, `This week I'd protect the same moment a little earlier: ${proposed}, without changing anything else.${reason} Say the word and I'll prepare it.`]);
      return basePlan(textValue, [], contract("weekly_recommendation", { recommendation: "start_15_minutes_earlier", current_time: range, proposed_time: proposed, evidence: insight, latest_outcome: outcome }, [proposed], [current.start_minute, current.end_minute, earlierStart]));
    }
    const textValue = responseVariant(context, [`This week, keep ${range} steady and judge it by whether your breaks fall.${reason}${measure}`, `Your cleanest experiment is the existing ${range} protection for seven days.${reason}${measure}`, `I would hold ${range} this week instead of adding another rule.${reason}${measure}`]);
    return basePlan(textValue, [], contract("weekly_recommendation", { recommendation: "test_current_window", time: range, evidence: insight, latest_outcome: outcome || "unknown", success_measure: measure.trim() }, [range], [current.start_minute, current.end_minute]));
  }

  const weakMoment = clean(context.personal_profile?.weak_moment || context.latest_insight?.summary, 120);
  if (weakMoment) return basePlan(`This week, start with one small protection around ${weakMoment.charAt(0).toLowerCase()}${weakMoment.slice(1)}. What exact start and end time would fit that moment?`, [], contract("weekly_recommendation_needs_time", { weak_moment: weakMoment }));
  return basePlan("I don't have enough recent phone context to choose a useful weekly change yet. When does your phone cost you the most attention right now?", [], contract("weekly_recommendation_needs_context", {}));
}

module.exports = { clockLabel, mentionedRanges, personalizedRecommendationPlan, responseVariant, scheduleManagementPlan, weekdayLabel };
