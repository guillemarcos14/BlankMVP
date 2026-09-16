"use strict";

const APP_ALIASES = [
  ["youtube shorts", "YouTube Shorts"],
  ["tik tok", "TikTok"],
  ["tiktok", "TikTok"],
  ["instagram", "Instagram"],
  ["insta", "Instagram"],
  ["reels", "Reels"],
  ["youtube", "YouTube"],
  ["reddit", "Reddit"],
  ["twitter", "Twitter"],
  ["facebook", "Facebook"],
  ["snapchat", "Snapchat"],
  ["whatsapp", "WhatsApp"],
  ["slack", "Slack"],
  ["duolingo", "Duolingo"],
];

const BLOCKING_ACTION_TYPES = new Set([
  "start_protection",
  "apply_schedule",
  "set_daily_limit",
  "activate_mode",
]);

const MISSING_FIELD_ORDER = ["apps", "action", "start", "end", "recurrence"];
const PENDING_BLOCKING_TTL_MS = 2 * 60 * 60 * 1000;

function clean(value, maxLength = 600) {
  return String(value || "").trim().replace(/\s+/g, " ").slice(0, maxLength);
}

function lower(value, maxLength = 600) {
  return clean(value, maxLength).toLowerCase();
}

function hasAny(text, values) {
  return values.some((value) => text.includes(value));
}

function canonicalAppName(value) {
  const normalized = lower(value, 80);
  const alias = APP_ALIASES.find(([name]) => normalized === name || normalized.includes(name));
  return alias ? alias[1] : clean(value, 60);
}

function modeCatalog(context = {}) {
  const catalog = Array.isArray(context.available_mode_catalog)
    ? context.available_mode_catalog
    : Array.isArray(context.available_modes) ? context.available_modes : [];
  return catalog
    .map((mode) => {
      if (typeof mode === "string") return { name: clean(mode, 60), app_names: [] };
      if (!mode || typeof mode !== "object" || Array.isArray(mode)) return null;
      const name = clean(mode.name, 60);
      if (!name) return null;
      const rawApps = Array.isArray(mode.app_names) ? mode.app_names : Array.isArray(mode.apps) ? mode.apps : [];
      return {
        ...mode,
        name,
        app_names: Array.from(new Set(rawApps.map(canonicalAppName).filter(Boolean))).sort(),
      };
    })
    .filter(Boolean);
}

function modeForApps(apps, context = {}) {
  const requested = Array.from(new Set(apps.map(canonicalAppName).filter(Boolean))).sort();
  if (!requested.length) return null;
  return modeCatalog(context).find((mode) => {
    if (!mode.app_names.length) return false;
    return mode.app_names.length === requested.length
      && mode.app_names.every((app, index) => app === requested[index]);
  }) || null;
}

function userConversationText(prompt, context = {}) {
  const messages = Array.isArray(context.recent_messages)
    ? context.recent_messages
    : Array.isArray(context.conversation) ? context.conversation : [];
  const memory = context.memory && typeof context.memory === "object" ? context.memory : {};
  const pending = context.pending_blocking || memory.pending_blocking;
  const conversationState = context.conversation_state || memory.conversation_state;
  const stateUpdatedAt = Date.parse(conversationState?.updated_at || "");
  const recentAssistant = [...messages].reverse().find((message) => lower(message && message.role, 20) === "assistant");
  const recentAssistantQuestion = /\b(?:what time|when do you|should it|which apps|how long|a qué hora|cuándo|qué aplicaciones|durante cuánto)\b/i.test(
    clean(recentAssistant && (recentAssistant.content || recentAssistant.text || recentAssistant.message), 800),
  );
  const activeShortTermContext = Boolean(pending && typeof pending === "object" && Object.keys(pending).length)
    || (Number.isFinite(stateUpdatedAt) && Date.now() - stateUpdatedAt <= 2 * 60 * 60 * 1000)
    || recentAssistantQuestion;
  const userMessages = messages
    .filter(() => activeShortTermContext)
    .filter((message) => lower(message && message.role, 20) === "user")
    .map((message) => message && (message.content || message.text || message.message))
    .map((message) => clean(message, 800))
    .filter(Boolean);
  return [...userMessages, clean(prompt, 800)].join(" ");
}

function pendingState(context = {}) {
  const memory = context.memory && typeof context.memory === "object" ? context.memory : {};
  const candidate = context.pending_blocking || memory.pending_blocking;
  if (!candidate || typeof candidate !== "object" || Array.isArray(candidate)) return {};
  const updatedAt = Date.parse(candidate.updated_at || "");
  if (Number.isFinite(updatedAt) && (updatedAt > Date.now() + 5 * 60 * 1000 || Date.now() - updatedAt > PENDING_BLOCKING_TTL_MS)) return {};
  const conversationState = context.conversation_state || memory.conversation_state;
  const stateUpdatedAt = Date.parse(conversationState?.updated_at || "");
  if (Number.isFinite(stateUpdatedAt) && Date.now() - stateUpdatedAt > PENDING_BLOCKING_TTL_MS) return {};
  return candidate;
}

function isBlockingRequest(prompt, context = {}) {
  const currentText = lower(prompt);
  const retrospectiveMention = hasAny(currentText, ["broke the block", "broke my block", "last block", "yesterday after", "relapse", "recaída", "recaida"])
    && !hasAny(currentText, ["block now", "protect now", "start now", "bloquea ahora", "proteger ahora", "inicia ahora"]);
  if (retrospectiveMention) return false;
  const blockingTerms = ["block", "bloquea", "bloquear", "limit", "protect", "proteger", "instagram", "tiktok", "tik tok", "youtube", "reddit", "twitter", "facebook", "snapchat"];
  const workConflict = hasAny(currentText, ["but i need", "but need", "need it", "for work", "for studying", "for study", "para trabajar", "para estudiar", "lo necesito", "la necesito"])
    && hasAny(currentText, blockingTerms);
  if (workConflict) return false;
  const webOnly = /\b(?:adult websites?|websites?|porn|porno|contenido adulto|p[aá]ginas? web)\b/i.test(currentText)
    && !/\b(?:app|apps|aplicaci[oó]n|aplicaciones|instagram|tiktok|youtube|reddit|twitter|facebook|snapchat)\b/i.test(currentText);
  if (webOnly) return false;
  const nonBlockingProductAction = /\b(?:allow only|essentials?-only|solo esenciales|s[oó]lo esenciales|everything except|todo excepto|except essentials|excepto lo esencial|only allow|solo permitir|reminder|recordatorio|notification|notificaci[oó]n)\b/i.test(currentText);
  if (nonBlockingProductAction) return false;
  if (hasAny(currentText, ["resume", "reanuda", "resume my rules", "resume rules", "quita la pausa", "quitar la pausa", "remove pause", "disable pause"]) &&
      !hasAny(currentText, ["block", "bloquea", "bloquear", "protect", "proteger"])) return false;
  if (isStandaloneNonBlockingTurn(currentText)) return false;
  if (Object.keys(pendingState(context)).length > 0) return true;
  const text = lower(userConversationText(prompt, context));
  const permanent = hasAny(currentText, ["forever", "permanently", "para siempre", "ever again", "impossible to use"])
    && hasAny(currentText, ["block", "bloquea", "bloquear", "everything", "todo", "phone", "distractions"]);
  if (permanent) return false;
  const imperative = hasAny(text, [
    "block", "bloquea", "bloquear", "bloqueo", "protect", "proteger", "protection",
    "shield", "start protection", "start a block", "inicia un bloqueo", "activa un bloqueo",
    "daily limit", "límite diario", "limite diario", "set a limit", "set a daily",
    "schedule", "programa", "programar", "activate", "activa", "inicia", "start ",
  ]);
  const modeRequest = /\b(?:mode|modo|profile|perfil)\b/i.test(text) && hasAny(text, ["now", "ahora", "start", "activate", "inicia", "activa", "use", "usa", "i'm in", "im in", "estoy en"]);
  const knownModes = modeCatalog(context);
  if (modeRequest && knownModes.length === 0) return false;
  if (modeRequest && knownModes.length > 0 && !knownModes.some((mode) => text.includes(mode.name.toLowerCase()))) return false;
  if (!imperative && !modeRequest) return false;
  const adviceOnly = /\b(?:how can i|what should i|can you explain|como puedo|qué debería|que deberia|puedes explicar)\b/i.test(text)
    && !/\b(?:i want|quiero|block|bloquea|bloquear|start|inicia|activa|programa)\b/i.test(text);
  return !adviceOnly || /\b(?:use|usa)\b[^.?!]{0,40}\b(?:mode|modo|profile|perfil)\b/i.test(text);
}

function isStandaloneNonBlockingTurn(text) {
  if (!text) return false;
  if (hasAny(text, ["block", "bloquea", "bloquear", "limit", "protect", "proteger", "schedule", "programa", "programar", "start", "inicia", "activa"])) return false;
  if (/^(?:hey|hi|hello|yo|hola|buenas|good morning|good afternoon|good evening|buenos d[ií]as|buenas tardes|buenas noches|thanks|thank you|thx|gracias|ok|okay|vale|perfect|perfecto|cool|nice|great|genial)\b/i.test(text)) return true;
  if (/^(?:how are you|how are u|how you doing|what's up|whats up|qué tal|que tal|cómo estás|como estas)\b/i.test(text)) return true;
  if (/^(?:how can i|how do i|what should i|what can i do|can you explain|why do i|como puedo|qué debería|que deberia|puedes explicar)\b/i.test(text)) return true;
  return false;
}

function parseApps(text, context = {}) {
  const value = lower(text);
  const apps = Array.from(new Set(
    APP_ALIASES
      .filter(([alias]) => value.includes(alias))
      .map(([, app]) => app),
  ));
  if (apps.length) {
    const matchingMode = modeForApps(apps, context);
    if (matchingMode) {
      return { value: [`mode:${matchingMode.name}`], source: "mode", resolved: true, mode_name: matchingMode.name };
    }
    return { value: apps, source: "conversation", resolved: true };
  }

  const pending = pendingState(context);
  if (Array.isArray(pending.apps) && pending.apps.length) {
    const pendingApps = pending.apps.map((app) => clean(app, 60)).filter(Boolean);
    const matchingMode = modeForApps(pendingApps, context);
    if (matchingMode) {
      return { value: [`mode:${matchingMode.name}`], source: "mode", resolved: true, mode_name: matchingMode.name };
    }
    return { value: pendingApps, source: "pending", resolved: true };
  }

  const memory = context.memory && typeof context.memory === "object" ? context.memory : {};
  if (Array.isArray(memory.main_apps) && memory.main_apps.length && /\b(?:it|that app|esa app|esa|the same|la misma)\b/i.test(value)) {
    return { value: memory.main_apps.map((app) => clean(app, 60)).filter(Boolean), source: "memory", resolved: true };
  }

  if (hasAny(value, ["selected apps", "current apps", "my selected apps", "apps already selected", "apps elegidas", "aplicaciones seleccionadas"])) {
    return { value: ["selected_apps"], source: "device_selection", resolved: context.has_selected_apps === true };
  }

  const modeName = modeCatalog(context)
    .map((mode) => mode.name)
    .map((mode) => clean(mode, 60))
    .find((mode) => mode && value.includes(mode.toLowerCase()));
  if (modeName && hasAny(value, [" mode", "modo", "profile", "perfil", "activate", "activa", "start", "inicia", "use ", "usa "])) {
    return { value: [`mode:${modeName}`], source: "mode", resolved: true, mode_name: modeName };
  }

  if (context.has_selected_apps === true) {
    return { value: ["selected_apps"], source: "device_selection", resolved: true };
  }

  if (hasAny(value, ["social media", "social apps", "social networks", "redes sociales"])) {
    return { value: [], source: "category", category: "social_apps", resolved: false };
  }
  return { value: [], source: "missing", resolved: false };
}

function parseAction(text) {
  const value = lower(text);
  if (hasAny(value, ["daily limit", "límite diario", "limite diario", "per day", "por día", "por dia", "set a limit", "set daily"])) {
    return "daily_limit";
  }
  return "hard_block";
}

function durationNumber(value) {
  const token = lower(value, 20);
  if (/^\d{1,3}$/.test(token)) return Number(token);
  const words = {
    a: 1,
    an: 1,
    one: 1,
    un: 1,
    una: 1,
  };
  return words[token] || null;
}

function parseDurationMinutes(text) {
  const value = lower(text);
  let total = 0;
  let found = false;
  const pattern = /\b(\d{1,3}|a|an|one|un|una)\b\s*[-–]?\s*(hours?|hrs?|h|horas?|hora|minutes?|mins?|m|minutos?|minuto)\b/gi;
  for (const match of value.matchAll(pattern)) {
    const amount = durationNumber(match[1]);
    if (!Number.isFinite(amount)) continue;
    found = true;
    total += /hour|hr|\bh\b|hora/i.test(match[2]) ? amount * 60 : amount;
  }
  if (!found || total < 1) return null;
  return Math.min(240, Math.max(1, Math.round(total)));
}

function parseClock(hourText, minuteText, meridiem, suffix) {
  const hour = Number(hourText);
  const minute = Number(minuteText || 0);
  if (!Number.isInteger(hour) || !Number.isInteger(minute) || minute < 0 || minute > 59) return null;
  const marker = lower(`${meridiem || ""} ${suffix || ""}`, 40);
  let resolvedMeridiem = marker.includes("pm") || marker.includes("tarde") || marker.includes("noche") ? "pm" : marker.includes("am") || marker.includes("mañana") || marker.includes("manana") ? "am" : "";
  if (!resolvedMeridiem && hour > 23) return null;
  if (!resolvedMeridiem && hour > 12) return hour * 60 + minute;
  if (!resolvedMeridiem) return { ambiguous: true, hour, minute };
  if (hour < 1 || hour > 12) return null;
  const normalizedHour = resolvedMeridiem === "am" ? (hour === 12 ? 0 : hour) : (hour === 12 ? 12 : hour + 12);
  return normalizedHour * 60 + minute;
}

function parseTimeParts(value, expression) {
  const match = value.match(expression);
  if (!match) return null;
  const parsed = parseClock(match[1], match[2], match[3], match[4]);
  return parsed == null ? null : { parsed, raw: match[0] };
}

function relativeMomentKey(text) {
  const value = lower(text);
  if (hasAny(value, ["after breakfast", "right after breakfast", "despues de desayunar", "después de desayunar"])) return "breakfast";
  if (hasAny(value, ["after lunch", "right after lunch", "despues de comer", "después de comer", "despues de lunch", "después de lunch"])) return "lunch";
  if (hasAny(value, ["after dinner", "right after dinner", "despues de cenar", "después de cenar", "despues de dinner", "después de dinner"])) return "dinner";
  if (hasAny(value, ["after work", "right after work", "despues de trabajar", "después de trabajar", "despues de work", "después de work", "when work ends", "when i finish work", "cuando termine de trabajar", "cuando termino de trabajar", "al terminar de trabajar"])) return "work";
  return "";
}

function relativeMomentDefaults(text) {
  const key = relativeMomentKey(text);
  if (!key) return null;
  const value = lower(text);
  const matches = [...value.matchAll(/\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b/gi)];
  const match = matches[matches.length - 1];
  if (!match) return null;
  const rawHour = Number(match[1]);
  const meridiem = match[3] || (rawHour > 12 ? "" : key === "breakfast" ? "am" : "pm");
  const minute = meridiem
    ? parseClock(rawHour, match[2], meridiem, "")
    : rawHour >= 0 && rawHour <= 23 ? rawHour * 60 + Number(match[2] || 0) : null;
  if (typeof minute !== "number") return null;
  const offset = key === "work" && hasAny(value, ["finish", "ends", "termine", "termino", "al terminar"])
    ? 10
    : 0;
  const startMinute = (minute + offset) % (24 * 60);
  const duration = key === "dinner" ? 90 : key === "work" ? 60 : 60;
  return {
    start: { type: "time", value: startMinute, source: "relative_followup" },
    end: { type: "duration", value: duration, source: "relative_default" },
    recurrence: { type: "daily", value: [1, 2, 3, 4, 5, 6, 7], source: "relative_default" },
  };
}

function parseTimeWindow(text, context = {}) {
  const value = lower(text);
  const expression = /(\d{1,2})(?::(\d{2}))?\s*(am|pm|de la mañana|de la manana|de la tarde|de la noche)?\s*(?:-|to|until|a)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm|de la mañana|de la manana|de la tarde|de la noche)?/i;
  const match = value.match(expression);
  if (!match) return null;
  let start = parseClock(match[1], match[2], match[3], "");
  let end = parseClock(match[4], match[5], match[6], "");
  if ((start && typeof start === "object" && start.ambiguous) || (end && typeof end === "object" && end.ambiguous)) {
    const startWasExplicit24Hour = typeof start === "number";
    const startHour = Number(match[1]);
    const endHour = Number(match[4]);
    const memory = contextSafeMemory(context.memory);
    const lastTopic = lower(memory.last_topic || memory.last_intent || "", 40);
    const nightly = hasAny(value, ["tonight", "at night", "night", "bedtime", "sleep", "noche", "dormir", "acostarme"])
      || lastTopic === "sleep"
      || (hasAny(value, ["block", "bloquea", "bloquear", "instagram", "tiktok", "youtube", "scroll"]) && startHour >= 9 && startHour <= 11 && endHour >= 1 && endHour <= 9 && endHour <= startHour);
    const startMarker = match[3] || (nightly ? "pm" : "am");
    const startsInPm = nightly || /pm|tarde|noche/i.test(match[3] || "") || startHour >= 13;
    const endMarker = match[6] || (startsInPm
      ? (endHour <= startHour ? "am" : "pm")
      : (endHour <= startHour ? "pm" : "am"));
    start = startWasExplicit24Hour ? start : parseClock(match[1], match[2], startMarker, "");
    end = parseClock(match[4], match[5], endMarker, "");
  }
  if (start == null || end == null || typeof start !== "number" || typeof end !== "number" || start === end) {
    return { ambiguous: true };
  }
  return { start, end, raw: match[0] };
}

function parseStart(text, context = {}) {
  const value = lower(text);
  if (hasAny(value, ["right now", "now", "immediately", "ahora mismo", "ahora", "ya", "en este momento"])) {
    return { type: "now", value: "now", source: "conversation" };
  }
  const window = parseTimeWindow(value, context);
  if (window && !window.ambiguous) return { type: "time", value: window.start, source: "conversation", raw: window.raw };
  const single = parseTimeParts(value, /\b(?:at|around|about|starting at|from|a las|sobre|a partir de las|a partir de)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm|de la mañana|de la manana|de la tarde|de la noche)?/i);
  if (single && typeof single.parsed === "number") return { type: "time", value: single.parsed, source: "conversation", raw: single.raw };
  if (hasAny(value, [" mode", "modo", "profile", "perfil"]) && hasAny(value, ["start", "activate", "inicia", "activa", "use", "usa"])) {
    return { type: "now", value: "now", source: "mode_default" };
  }
  const relative = hasAny(value, ["after breakfast", "after lunch", "after dinner", "after work", "después de desayunar", "despues de desayunar", "después de comer", "despues de comer", "después de cenar", "despues de cenar", "después de trabajar", "despues de trabajar"]);
  if (relative) {
    const memory = contextSafeMemory(context.memory);
    const key = value.includes("breakfast") || value.includes("desayun") ? "breakfast" : value.includes("lunch") || value.includes("comer") ? "lunch" : value.includes("dinner") || value.includes("cenar") ? "dinner" : "work";
    const remembered = Number(memory[`${key}_end_minute`]);
    if (Number.isFinite(remembered)) return { type: "time", value: remembered, source: "memory", relative: key };
  }
  return { type: "missing", value: null };
}

function contextSafeMemory(text) {
  return text && typeof text === "object" ? text : {};
}

function parseEnd(text, start, context = {}) {
  const duration = parseDurationMinutes(text);
  if (duration != null) return { type: "duration", value: duration, source: "conversation" };
  const value = lower(text);
  if (hasAny(value, ["indefinite", "indefinitely", "forever", "without an end", "sin límite", "sin limite", "indefinido", "indefinida", "indefinidamente", "para siempre", "hasta que lo quite", "until i stop"])) {
    return { type: "indefinite", value: null, source: "conversation" };
  }
  const window = parseTimeWindow(value, context);
  if (window && !window.ambiguous) return { type: "time", value: window.end, source: "conversation" };
  if (start && start.type === "time" && start.raw && /\bfrom\b|\bto\b|\buntil\b|\ba\b|-/i.test(value)) return { type: "missing", value: null };
  return { type: "missing", value: null };
}

function parseRecurrence(text, start) {
  const value = lower(text);
  if (hasAny(value, ["every day", "daily", "each day", "all week", "cada día", "cada dia", "todos los días", "todos los dias", "diariamente", "cada día de la semana", "cada dia de la semana"])) {
    return { type: "daily", value: [1, 2, 3, 4, 5, 6, 7], source: "conversation" };
  }
  if (hasAny(value, ["weekdays", "monday to friday", "monday through friday", "entre semana", "de lunes a viernes"])) {
    return { type: "weekly", value: [1, 2, 3, 4, 5], source: "conversation" };
  }
  if (hasAny(value, ["weekends", "saturday and sunday", "fin de semana", "fines de semana"])) {
    return { type: "weekly", value: [6, 7], source: "conversation" };
  }
  const days = [];
  const dayAliases = [
    [["monday", "lunes"], 1], [["tuesday", "martes"], 2], [["wednesday", "miércoles", "miercoles"], 3],
    [["thursday", "jueves"], 4], [["friday", "viernes"], 5], [["saturday", "sábado", "sabado"], 6], [["sunday", "domingo"], 7],
  ];
  for (const [aliases, day] of dayAliases) if (aliases.some((alias) => value.includes(alias))) days.push(day);
  if (days.length) return { type: "weekly", value: Array.from(new Set(days)).sort((a, b) => a - b), source: "conversation" };
  if (hasAny(value, ["once", "one time", "just today", "today", "tonight", "tomorrow", "hoy", "esta noche", "mañana", "manana", "solo esta vez", "sólo esta vez"])) {
    return { type: "once", value: [0], source: "conversation" };
  }
  if (start && start.type === "now") return { type: "once", value: [0], source: "immediate_default" };
  return { type: "missing", value: null };
}

function mergePending(field, parsed, pending) {
  if (parsed && parsed.type !== "missing" && parsed.value !== null && parsed.value !== undefined) return parsed;
  const prior = pending[field];
  return prior && typeof prior === "object" ? prior : parsed;
}

function resolveBlockingContract(prompt, context = {}, plan = null) {
  const combinedText = userConversationText(prompt, context);
  const pending = pendingState(context);
  const userRequest = isBlockingRequest(prompt, context);
  const planCandidate = Boolean(plan && Array.isArray(plan.actions) && plan.actions.some((item) => BLOCKING_ACTION_TYPES.has(item && item.type)));
  const request = userRequest || planCandidate;
  if (!request) {
    return { is_blocking_request: false, user_request: false, ready: false, missing_fields: [], data: null };
  }

  const apps = parseApps(combinedText, context);
  const actionType = pending.action || parseAction(combinedText);
  let start = mergePending("start", parseStart(combinedText, context), pending);
  let end = mergePending("end", parseEnd(combinedText, start, context), pending);
  let recurrence = mergePending("recurrence", parseRecurrence(combinedText, start), pending);
  const explicitWindow = parseTimeWindow(combinedText, context);
  if (explicitWindow && !explicitWindow.ambiguous && recurrence && recurrence.type === "missing") {
    recurrence = { type: "once", value: [0], source: "explicit_window_default" };
  }
  const relativeDefaults = relativeMomentDefaults(combinedText);
  if (relativeDefaults) {
    const relativeWorkFinish = relativeMomentKey(combinedText) === "work" && hasAny(combinedText.toLowerCase(), ["finish", "ends", "termine", "termino", "al terminar"]);
    if (!start || start.type === "missing" || relativeWorkFinish) start = relativeDefaults.start;
    if (!end || end.type === "missing") end = relativeDefaults.end;
    if (!recurrence || recurrence.type === "missing") recurrence = relativeDefaults.recurrence;
  }
  if (actionType === "daily_limit") {
    if (!start || start.type === "missing") start = { type: "now", value: "now", source: "daily_limit_default" };
    if (!recurrence || recurrence.type === "missing") recurrence = { type: "daily", value: [1, 2, 3, 4, 5, 6, 7], source: "daily_limit_default" };
  }
  const fields = {
    apps: apps.resolved ? apps.value : null,
    action: actionType || null,
    start: start && start.type !== "missing" ? start : null,
    end: end && end.type !== "missing" ? end : null,
    recurrence: recurrence && recurrence.type !== "missing" ? recurrence : null,
  };
  const missingFields = MISSING_FIELD_ORDER.filter((field) => {
    if (field === "apps") return !apps.resolved;
    return !fields[field];
  });
  if (actionType !== "daily_limit" && fields.start && fields.start.type === "now" && fields.recurrence && fields.recurrence.type !== "once" && !missingFields.includes("start")) {
    missingFields.push("start");
  }
  if (fields.start && fields.start.type === "time" && fields.end && fields.end.type === "indefinite") {
    missingFields.push("end");
  }
  missingFields.sort((left, right) => MISSING_FIELD_ORDER.indexOf(left) - MISSING_FIELD_ORDER.indexOf(right));
  return {
    is_blocking_request: true,
    user_request: userRequest,
    ready: missingFields.length === 0,
    missing_fields: missingFields,
    data: fields,
    app_source: apps.source,
    app_category: apps.category || null,
  };
}

function missingQuestion(contract, language = "en") {
  const missing = contract.missing_fields;
  if (contract.data && contract.data.action === "daily_limit" && missing.includes("end")) {
    return language === "es"
      ? "¿Cuántos minutos al día quieres permitir para esas aplicaciones?"
      : "How many minutes per day do you want to allow for those apps?";
  }
  if (language === "es") {
    if (missing.includes("apps") && missing.includes("start") && missing.includes("end")) return "¿Qué aplicaciones quieres bloquear, lo iniciamos ahora o a qué hora exacta, y durante cuánto tiempo?";
    if (missing.includes("apps")) return "¿Qué aplicaciones quieres bloquear? Puedes decirme los nombres o elegirlas manualmente en Blanked.";
    if (missing.includes("start") && missing.includes("end") && missing.includes("recurrence")) return "¿Lo iniciamos ahora o a qué hora exacta, durante cuánto tiempo y es solo una vez o se repite?";
    if (missing.includes("start")) return "¿Lo iniciamos ahora o prefieres programarlo para una hora exacta?";
    if (missing.includes("end")) return "¿Durante cuánto tiempo quieres bloquearlas, o lo dejamos indefinido?";
    if (missing.includes("recurrence")) return "¿Es solo una vez o quieres repetirlo? Si se repite, ¿qué días?";
    if (missing.includes("action")) return "¿Quieres un bloqueo estricto o un límite diario?";
    return "Dime los detalles del bloqueo que faltan y lo prepararé.";
  }
  if (missing.includes("apps") && missing.includes("start") && missing.includes("end")) return "Which apps should I block, should it start now or at an exact time, and for how long?";
  if (missing.includes("apps")) return "Which apps do you want to block? You can name them or choose them manually in Blanked.";
  if (missing.includes("start") && missing.includes("end") && missing.includes("recurrence")) return "Should it start now or at an exact time, for how long, and is it one time or recurring?";
  if (missing.includes("start")) return "Should I start it now, or would you like to schedule it for an exact time?";
  if (missing.includes("end")) return "How long should I block them, or should it stay indefinite?";
  if (missing.includes("recurrence")) return "Is this just once, or should it repeat? If it repeats, which days?";
  if (missing.includes("action")) return "Do you want a strict block or a daily limit?";
  return "Tell me the missing blocking details and I will prepare it.";
}

function inferredBlockingIntent(prompt) {
  const text = lower(prompt);
  if (hasAny(text, ["relapse", "reca", "broke the block", "break the block", "can't stop", "cannot stop", "no puedo parar", "terrible today", "fatal hoy"])) return "emergency";
  if (hasAny(text, ["sleep", "night", "bed", "bedtime", "dormir", "duermo", "acuesto", "noche"])) return "sleep";
  if (hasAny(text, ["exam", "study", "estudio", "estudiar", "examen"])) return "study";
  if (hasAny(text, ["focus", "concentrate", "concentration", "deep work", "work", "foco", "concentrarme", "trabajar"])
    || (hasAny(text, ["strict", "hard block", "bloqueo fuerte", "bloqueo estricto"]) && /\b\d+\s*(?:minutes?|mins?|minutos?)\b/i.test(text))) return "focus";
  return "social";
}

function publicBlockingData(data) {
  if (!data || typeof data !== "object") return null;
  const publicField = (field) => {
    if (!field || typeof field !== "object") return null;
    return { type: field.type || null, value: field.value ?? null };
  };
  return {
    apps: Array.isArray(data.apps) ? data.apps.slice(0, 8) : null,
    action: data.action || null,
    start: publicField(data.start),
    end: publicField(data.end),
    recurrence: publicField(data.recurrence),
  };
}

function incompleteBlockingPlan(contract, language = "en", prompt = "", context = {}) {
  if (!contract.is_blocking_request || !contract.user_request || contract.ready) return null;
  const data = contract.data || {};
  const apps = Array.isArray(data.apps) ? data.apps.filter((app) => app && app !== "selected_apps") : [];
  const combinedText = userConversationText(prompt, context);
  const requestedMode = combinedText.match(/\b(?:start|activate|use|inicia|activa|usa)\s+([a-z][a-z0-9 _-]{0,30})\s+(?:mode|modo)\b/i)?.[1]?.trim() || "";
  const target = apps.length
    ? apps.map((app) => String(app).replace(/^mode:/, "")).join(" and ")
    : requestedMode ? `${requestedMode} mode` : "the selected apps";
  const windowMatch = String(prompt || "").match(/\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(?:-|to|until|a)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b/i);
  const knownWindow = windowMatch ? ` from ${windowMatch[1]}${windowMatch[3] ? ` ${windowMatch[3].toUpperCase()}` : ""} to ${windowMatch[4]}${windowMatch[6] ? ` ${windowMatch[6].toUpperCase()}` : ""}` : "";
  const webChannel = context && (context.web_preview === true || context.channel === "web" || context.assistant_channel === "web");
  const webNote = webChannel
    ? language === "es"
      ? " Desde la web puedo planearlo, pero Blankmind App es quien puede ejecutarlo automáticamente porque ahí están los permisos."
      : " I can plan it here, but Blankmind App is what executes it automatically because the permissions live there."
    : "";
  const relativeKey = relativeMomentKey(combinedText);
  const relativeQuestions = {
    breakfast: language === "es" ? "¿a qué hora sueles terminar de desayunar?" : "what time do you usually finish breakfast?",
    lunch: language === "es" ? "¿a qué hora sueles terminar de comer?" : "what time do you usually finish eating?",
    dinner: language === "es" ? "¿a qué hora sueles terminar de cenar?" : "what time do you usually finish dinner?",
    work: language === "es" ? "¿a qué hora sueles terminar de trabajar?" : "what time do you usually finish work?",
  };
  const missing = relativeKey && !relativeMomentDefaults(combinedText)
    ? relativeQuestions[relativeKey]
    : missingQuestion(contract, language);
  const inferredIntent = inferredBlockingIntent(prompt);
  const timingLabel = inferredIntent === "sleep" && hasAny(lower(prompt), ["tonight", "at night", "noche", "bedtime", "esta noche"])
    ? language === "es" ? " esta noche" : " tonight"
    : "";
  const question = language === "es"
    ? `Puedo preparar un bloqueo para ${target}${knownWindow}${timingLabel}, pero ${missing}${webNote}`
    : `I can prepare a block for ${target}${knownWindow}${timingLabel}, but ${missing.charAt(0).toLowerCase()}${missing.slice(1)}${webNote}`;
  return {
    intent: inferredIntent,
    title: language === "es" ? "Detalles del bloqueo" : "Blocking details",
    response_text: question,
    bullets: language === "es"
      ? ["Aún faltan datos para ejecutar este bloqueo.", "No voy a inventar ninguna aplicación, hora o duración.", "Cuando estén completos, buscaré un modo o abriré la selección de apps."]
      : ["A few details are still needed before this block can run.", "I will not invent an app, time or duration.", "Once they are complete, I will look for a saved mode or open app selection."],
    primary_label: language === "es" ? "Decir detalles" : "Tell me the details",
    secondary_label: language === "es" ? "Ahora no" : "Not now",
    actions: [],
    requires_selected_apps: false,
    requires_screen_time_authorization: false,
    message_text: question,
    speech_text: question,
    followup_text: "",
    blocking_ready: false,
    blocking_user_request: true,
    blocking_missing_fields: contract.missing_fields,
    blocking_data: publicBlockingData(contract.data),
  };
}

function isBlockingActionType(type) {
  return BLOCKING_ACTION_TYPES.has(type);
}

module.exports = {
  BLOCKING_ACTION_TYPES,
  incompleteBlockingPlan,
  isBlockingActionType,
  isBlockingRequest,
  publicBlockingData,
  resolveBlockingContract,
};
