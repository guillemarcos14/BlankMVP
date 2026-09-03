const { json, parseJsonBody, requireMethod } = require("./_membership");

function cleanText(value, maxLength = 240) {
  return String(value || "").trim().replace(/\s+/g, " ").slice(0, maxLength);
}

function cleanNumber(value, fallback, min, max) {
  const number = Number(value);
  const resolved = Number.isFinite(number) ? Math.round(number) : fallback;
  return Math.min(max, Math.max(min, resolved));
}

function contains(text, needles) {
  return needles.some((needle) => text.includes(needle));
}

function userFacingText(value, maxLength = 140) {
  return cleanText(value, maxLength)
    .replace(/\bask the user\b/gi, "tell me")
    .replace(/\bask user\b/gi, "tell me")
    .replace(/\bthe user\b/gi, "you")
    .replace(/\buser's\b/gi, "your")
    .replace(/\buser\b/gi, "you");
}

function hasExplicitBlockRequest(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  return contains(text, ["block", "bloquea", "bloquear", "shield", "protect", "set ", "schedule", "limit", "from"]);
}

function hasBedtime(prompt, context = {}) {
  const text = cleanText(prompt, 600).toLowerCase();
  if (explicitSingleTime(prompt)) return true;
  const memory = context.memory && typeof context.memory === "object" ? context.memory : {};
  return Boolean(memory.bedtime_minute != null || contains(text, ["my bedtime", "go to sleep at", "me duermo a", "me voy a dormir a"]));
}

function hasKnownMainApp(context = {}) {
  const memory = context.memory && typeof context.memory === "object" ? context.memory : {};
  return Array.isArray(memory.main_apps) && memory.main_apps.length > 0;
}

function namedApp(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  const apps = [
    ["tiktok", "TikTok"],
    ["instagram", "Instagram"],
    ["youtube", "YouTube"],
    ["reddit", "Reddit"],
    ["twitter", "Twitter"],
    ["facebook", "Facebook"],
    ["snapchat", "Snapchat"],
  ];
  const match = apps.find(([key]) => text.includes(key));
  return match ? match[1] : "the app";
}

function requestedAppCategory(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  if (contains(text, ["social media", "social apps", "social networks", "redes sociales"])) return "social apps";
  return "";
}

function requestedUnknownApp(prompt) {
  const text = cleanText(prompt, 600);
  const match = text.match(/\b(?:block|limit|bloquea|bloquear)\s+([a-z][a-z0-9._+-]{1,30})\b/i);
  if (!match) return "";
  const raw = match[1];
  const lowered = raw.toLowerCase();
  const blockedWords = new Set(["everything", "all", "todos", "todas", "adult", "websites", "apps", "app", "social", "media", "networks", "redes", "my", "me", "now", "for", "from", "during", "strict", "hard"]);
  if (blockedWords.has(lowered)) return "";
  if (namedApp(raw) !== "the app") return "";
  return raw.charAt(0).toUpperCase() + raw.slice(1);
}

function availableModeNames(context = {}) {
  const modes = Array.isArray(context.available_modes) ? context.available_modes : [];
  return modes
    .map((mode) => typeof mode === "string" ? mode : mode && mode.name)
    .map((name) => cleanText(name, 40))
    .filter(Boolean)
    .slice(0, 8);
}

function requestedModeName(prompt, context = {}) {
  const text = cleanText(prompt, 600).toLowerCase();
  const modes = availableModeNames(context);
  const exact = modes.find((mode) => text.includes(mode.toLowerCase()));
  if (exact) return exact;
  const aliases = [
    { keys: ["sleep", "night", "bedtime"], mode: ["Sleep", "Night"] },
    { keys: ["study", "exam"], mode: ["Study"] },
    { keys: ["work", "focus", "deep work"], mode: ["Work", "Focus"] },
  ];
  for (const alias of aliases) {
    if (!contains(text, alias.keys)) continue;
    const match = modes.find((mode) => alias.mode.some((name) => mode.toLowerCase() === name.toLowerCase()));
    if (match) return match;
  }
  return "";
}

function hasWorkAppConflict(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  return contains(text, ["but i need", "but need", "need it", "need this app", "except i need", "for work", "work tutorials", "para trabajar"]) &&
    contains(text, ["block", "limit", "tiktok", "instagram", "youtube", "reddit", "twitter", "x", "facebook", "snapchat"]);
}

function asksAboutExactAppList(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  return contains(text, ["exact app list", "my app list", "which apps", "see my apps", "selected apps"]) &&
    contains(text, ["see", "know", "access", "visible", "can you"]);
}

function needsContextBeforeAction(prompt, intent, context = {}) {
  const text = cleanText(prompt, 600).toLowerCase();
  if (intent === "sleep" && !explicitTimeWindow(prompt) && !hasBedtime(prompt, context) && !hasExplicitBlockRequest(prompt)) {
    return "bedtime";
  }
  if (intent === "social" &&
      contains(text, ["scroll", "doomscroll", "checking my phone", "check my phone", "opening my phone", "use my phone", "notification", "notifications"]) &&
      !explicitTimeWindow(prompt) &&
      !hasKnownMainApp(context) &&
      !contains(text, ["tiktok", "instagram", "youtube", "app"])) {
    return "apps";
  }
  return null;
}

function classify(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  if (contains(text, ["porn", "porno", "adult", "xxx"])) return "adultContent";
  if (contains(text, ["losing control", "perdiendo el control", "urge", "emergency", "reca", "relapse", "broke the block", "break the block", "can't stop", "no puedo parar"])) return "emergency";
  if (contains(text, ["sleep", "night", "bed", "dormir", "noche", "tired", "cansado"])) return "sleep";
  if (contains(text, ["exam", "study", "estudio", "estudiar", "examen", "opos"])) return "study";
  if (contains(text, ["allow only", "whatsapp", "maps", "solo", "only"])) return "allowOnly";
  if (contains(text, ["vacation", "holiday", "vacaciones", "pause", "pausa", "resume my rules", "resume rules"])) return "vacation";
  if (contains(text, ["week", "semana", "analy", "diagn", "report", "review"])) return "weeklyReview";
  if (contains(text, ["social media", "social apps", "social networks", "redes sociales", "tiktok", "instagram", "youtube", "reddit", "twitter", "facebook", "snapchat", "gaming", "game", "dopamine", "scroll", "doomscroll", "notification", "notifications"])) return "social";
  if (requestedUnknownApp(prompt)) return "social";
  if (contains(text, ["anxious", "anxiety", "ansiedad", "bored", "boring", "aburr", "lonely", "stress", "guilt", "culpa"])) return "social";
  if (contains(text, ["focus", "work", "productiv", "foco", "trabaj", "deep work", "now"])) return "focus";
  return "general";
}

function behaviorCluster(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  if (contains(text, ["anxious", "anxiety", "ansiedad", "stress", "stressed"])) return "anxiety scroll";
  if (contains(text, ["bored", "boring", "aburr"])) return "boredom scroll";
  if (contains(text, ["revenge", "late", "night", "bed", "sleep", "dormir", "noche"])) return "bedtime scroll";
  if (contains(text, ["compare", "comparison", "instagram", "social", "twitter", "facebook", "snapchat"])) return "social comparison";
  if (contains(text, ["avoid", "procrast", "work", "study", "exam"])) return "avoidance loop";
  if (contains(text, ["check", "whatsapp", "notification", "notif"])) return "compulsive checking";
  if (contains(text, ["relapse", "reca", "failed", "broke"])) return "relapse pattern";
  if (contains(text, ["tired", "low energy", "cansado"])) return "low-energy scroll";
  return "screen habit loop";
}

function minuteOfDay(hour, minute, meridiem) {
  if (!Number.isInteger(hour) || !Number.isInteger(minute) || minute < 0 || minute > 59) return null;
  if (meridiem) {
    if (hour < 1 || hour > 12) return null;
    if (meridiem === "am") return (hour === 12 ? 0 : hour) * 60 + minute;
    if (meridiem === "pm") return (hour === 12 ? 12 : hour + 12) * 60 + minute;
    return null;
  }
  if (hour < 0 || hour > 23) return null;
  return hour * 60 + minute;
}

function explicitTimeWindow(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  const match = text.match(/(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(?:-|to|until|a)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?/i);
  if (!match) return null;
  const startHour = Number(match[1]);
  const endHour = Number(match[4]);
  const looksNightly =
    contains(text, ["night", "sleep", "bed", "dormir", "noche"]) ||
    (contains(text, ["block", "bloquea", "bloquear", "instagram", "tiktok", "youtube", "scroll"]) && startHour >= 9 && startHour <= 11 && endHour >= 1 && endHour <= 9);
  const endMeridiem = match[6] || (looksNightly && !match[3] ? "am" : null);
  const startMeridiem = match[3] || (looksNightly ? "pm" : endMeridiem);
  const start = minuteOfDay(startHour, Number(match[2] || 0), startMeridiem);
  const end = minuteOfDay(endHour, Number(match[5] || 0), endMeridiem);
  if (start == null || end == null || start === end) return null;
  return { start, end };
}

function explicitSingleTime(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  const match = text.match(/(?:sleep|bed|dormir|duermo|acuesto|bedtime)[^\d]*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?/i);
  if (!match) return null;
  const rawHour = Number(match[1]);
  const meridiem = match[3] || (rawHour >= 6 && rawHour <= 11 ? "pm" : rawHour === 12 ? "am" : null);
  return minuteOfDay(rawHour, Number(match[2] || 0), meridiem);
}

function looseSingleTime(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  const match = text.match(/\b(?:usually|normalmente|sobre|around|at|a las)?\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b/i);
  if (!match) return null;
  const rawHour = Number(match[1]);
  const meridiem = match[3] || (rawHour >= 6 && rawHour <= 11 ? "pm" : rawHour === 12 ? "am" : null);
  return minuteOfDay(rawHour, Number(match[2] || 0), meridiem);
}

function explicitDurationMinutes(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  const match = text.match(/(\d{1,3})\s*(?:min|mins|minute|minutes)/i);
  if (!match) return null;
  return cleanNumber(match[1], 30, 5, 240);
}

function wantsHardMode(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  return contains(text, ["hard mode", "strict", "hard block", "no exit", "no unlock", "intense"]);
}

function minuteText(minuteOfDayValue) {
  const hour = Math.max(0, Math.min(23, Math.floor(minuteOfDayValue / 60)));
  const minute = Math.max(0, Math.min(59, minuteOfDayValue % 60));
  const displayHour = hour % 12 === 0 ? 12 : hour % 12;
  const meridiem = hour < 12 ? "AM" : "PM";
  return `${displayHour}:${String(minute).padStart(2, "0")} ${meridiem}`;
}

function hourWindow(hourValue) {
  const hour = ((Math.round(Number(hourValue)) % 24) + 24) % 24;
  return `${minuteText(hour * 60)} to ${minuteText(((hour + 1) % 24) * 60)}`;
}

function action(type, values = {}) {
  return {
    type,
    minutes: values.minutes ?? null,
    hard_mode: values.hard_mode ?? null,
    name: values.name ?? null,
    start_minute: values.start_minute ?? null,
    end_minute: values.end_minute ?? null,
    weekdays: values.weekdays ?? null,
    duration_days: values.duration_days ?? null,
    hours: values.hours ?? null,
  };
}

function fallbackPlan(prompt, context = {}) {
  const intent = classify(prompt);
  const promptText = cleanText(prompt, 600).toLowerCase();
  const selected = context.has_selected_apps === true;
  const authorized = context.screen_time_authorized === true;
  const duration = cleanNumber(context.recommended_duration_minutes, 30, 5, 240);
  const riskWindow = cleanText(context.risk_window, 60) || "your next risk window";
  const cluster = behaviorCluster(prompt);
  const timeWindow = explicitTimeWindow(prompt);
  const memory = context.memory && typeof context.memory === "object" ? context.memory : {};
  const lastOutcome = cleanText(memory.last_plan_outcome, 40);
  const memoryApp = Array.isArray(memory.main_apps) && memory.main_apps.length > 0 ? cleanText(memory.main_apps[0], 40) : "";
  const promptApp = namedApp(prompt);
  const activeApp = promptApp !== "the app" ? promptApp : memoryApp;
  const appCategory = requestedAppCategory(prompt);
  const weakHours = Array.isArray(memory.weak_hours) ? memory.weak_hours.filter((hour) => Number.isFinite(Number(hour))).slice(0, 3) : [];
  const rememberedRisk = weakHours.length > 0 ? weakHours.map((hour) => hourWindow(Number(hour))).filter(Boolean)[0] : "";
  const missingContext = needsContextBeforeAction(prompt, intent, context);
  const modeName = requestedModeName(prompt, context);
  const setupLine = selected && authorized ? "Protection can run with your current setup." : "Setup comes first: choose apps and allow Screen Time.";
  const outcomeLine = lastOutcome === "broke"
    ? "Feedback: the last plan broke, so the next move should be easier and earlier."
    : lastOutcome === "held"
      ? "Feedback: the last plan held, so repeat before increasing difficulty."
      : setupLine;

  if (missingContext === "bedtime") {
    return {
      intent: "sleep",
      title: "Bedtime Scroll Read",
      response_text: "This sounds like a bedtime scroll loop. Before I block anything, I need your sleep target.",
      bullets: [
        "Read: you want nights to feel less automatic.",
        "Pattern: the risky window depends on when you actually go to sleep.",
        "Move: tell me your usual bedtime, then I can suggest the right boundary."
      ],
      primary_label: "Tell bedtime",
      secondary_label: "Not now",
      actions: [],
      requires_selected_apps: false,
      requires_screen_time_authorization: false,
    };
  }

  if (missingContext === "apps") {
    return {
      intent: "social",
      title: "Scroll Pattern",
      response_text: "I can help with that, but first I need to know where the loop happens.",
      bullets: [
        "Read: this is a scroll habit, not a generic focus issue.",
        "Pattern: the useful protection depends on the app and time window.",
        "Move: tell me the main app or the time of day it usually starts."
      ],
      primary_label: "Tell app",
      secondary_label: "Open report",
      actions: [],
      requires_selected_apps: false,
      requires_screen_time_authorization: false,
    };
  }

  if (intent === "social" && hasWorkAppConflict(prompt)) {
    const app = namedApp(prompt);
    return {
      intent: "social",
      title: "Work App Conflict",
      response_text: `Tell me when ${app} becomes non-work use, then I can set the boundary.`,
      bullets: [
        "Read: the same app has useful and risky contexts.",
        "Pattern: a full block could break work instead of improving control.",
        `Move: tell me when ${app} becomes non-work use, then I can set the boundary.`
      ],
      primary_label: "Tell window",
      secondary_label: "Not now",
      actions: [],
      requires_selected_apps: false,
      requires_screen_time_authorization: false,
    };
  }

  const unknownApp = requestedUnknownApp(prompt);
  if (intent === "social" && appCategory && hasExplicitBlockRequest(prompt) && (!selected || !authorized)) {
    const setupAction = !selected ? "open_app_picker" : "request_screen_time_permission";
    return {
      intent: "social",
      title: "Choose Apps",
      response_text: `Choose the social apps in Screen Time first, then I can apply the block.`,
      bullets: [
        "Read: this is a category of apps, not one exact app.",
        "Pattern: iOS needs you to choose the apps before Blanked can shield them.",
        "Move: choose the social apps now, then apply the boundary."
      ],
      primary_label: !selected ? "Choose apps" : "Allow Screen Time",
      secondary_label: "Not now",
      actions: [action(setupAction)],
      requires_selected_apps: false,
      requires_screen_time_authorization: false,
    };
  }
  if (intent === "social" && unknownApp) {
    return {
      intent: "social",
      title: "Choose App",
      response_text: `I can help block ${unknownApp}, but first you need to choose it in Screen Time.`,
      bullets: [
        `Read: ${unknownApp} is the app you want to control.`,
        "Pattern: iOS requires the exact app selection before Blanked can shield it.",
        "Move: choose the app now, then apply the boundary."
      ],
      primary_label: "Choose app",
      secondary_label: "Not now",
      actions: [action("open_app_picker")],
      requires_selected_apps: false,
      requires_screen_time_authorization: false,
    };
  }

  if (intent === "social" && promptApp !== "the app" && hasExplicitBlockRequest(prompt) && (!selected || !authorized)) {
    const setupAction = !selected ? "open_app_picker" : "request_screen_time_permission";
    return {
      intent: "social",
      title: "Choose App",
      response_text: `Choose ${promptApp} in Screen Time first, then I can apply the block.`,
      bullets: [
        `Read: ${promptApp} is the app you want to control.`,
        "Pattern: iOS needs that app inside your authorized selection before Blanked can shield it.",
        "Move: choose the app now, then apply the boundary."
      ],
      primary_label: !selected ? "Choose app" : "Allow Screen Time",
      secondary_label: "Not now",
      actions: [action(setupAction)],
      requires_selected_apps: false,
      requires_screen_time_authorization: false,
    };
  }

  if (asksAboutExactAppList(prompt)) {
    return {
      intent: "general",
      title: "App Privacy",
      response_text: "I can use counts and context you choose to share, but I do not need your exact app list to reason about the pattern.",
      bullets: [
        "Read: app privacy matters for this feature.",
        "Pattern: Blanked can work from selected counts, weak hours and your own description.",
        "Move: tell me the app only when it helps create a better boundary."
      ],
      primary_label: "Got it",
      secondary_label: "Not now",
      actions: [],
      requires_selected_apps: false,
      requires_screen_time_authorization: false,
    };
  }

  if (modeName && contains(promptText, ["start", "block", "protect", "activate", "use ", "switch", "mode"])) {
    const requestedDuration = explicitDurationMinutes(prompt) || duration;
    const hardMode = wantsHardMode(prompt);
    const modeAction = action("switch_mode", { name: modeName });
    if (timeWindow) {
      return {
        intent: intent === "sleep" || intent === "study" || intent === "focus" ? intent : "focus",
        title: `${modeName} Mode`,
        response_text: `I can use ${modeName} mode for this plan because that selection already exists.`,
        bullets: [
          `Read: ${modeName} mode is already available.`,
          `Move: switch to ${modeName} mode and protect from ${minuteText(timeWindow.start)} to ${minuteText(timeWindow.end)}.`,
          "Protection: use the apps already authorized for that mode."
        ],
        primary_label: `Use ${modeName}`,
        secondary_label: "Choose apps",
        actions: [
          modeAction,
          action("apply_schedule", { name: `${modeName} Mode`, start_minute: timeWindow.start, end_minute: timeWindow.end, weekdays: [1, 2, 3, 4, 5, 6, 7], duration_days: 7 })
        ],
        requires_selected_apps: false,
        requires_screen_time_authorization: true,
      };
    }
    return {
      intent: intent === "sleep" || intent === "study" || intent === "focus" ? intent : "focus",
      title: `${modeName} Mode`,
      response_text: `I can switch to ${modeName} mode and start protection on its existing app selection.`,
      bullets: [
        `Read: ${modeName} mode is already available.`,
        `Move: switch to ${modeName} mode for ${requestedDuration} minutes.`,
        "Protection: use the apps already authorized for that mode."
      ],
      primary_label: `Start ${modeName}`,
      secondary_label: "Choose apps",
      actions: [
        modeAction,
        action("start_protection", { minutes: requestedDuration, hard_mode: hardMode })
      ],
      requires_selected_apps: false,
      requires_screen_time_authorization: true,
    };
  }

  if (intent === "general" && cleanText(memory.pattern_cluster, 80).includes("bedtime")) {
    const followupBedtime = looseSingleTime(prompt);
    if (followupBedtime != null) {
      const start = (followupBedtime + 24 * 60 - 30) % (24 * 60);
      return {
        intent: "sleep",
        title: "Bedtime Boundary",
        response_text: `If ${minuteText(followupBedtime)} is your usual bedtime, the boundary should start before the final scroll begins.`,
        bullets: [
          `Read: your bedtime target is ${minuteText(followupBedtime)}.`,
          "Pattern: this continues the bedtime scroll loop we were already discussing.",
          `Move: protect distracting apps from ${minuteText(start)} to ${minuteText(followupBedtime)} first.`
        ],
        primary_label: "Apply boundary",
        secondary_label: "Not now",
        actions: [action("apply_schedule", { name: "Sleep Boundary", start_minute: start, end_minute: followupBedtime, weekdays: [1, 2, 3, 4, 5, 6, 7], duration_days: 7 })],
        requires_selected_apps: true,
        requires_screen_time_authorization: true,
      };
    }
  }

  if (intent === "general" && memoryApp && weakHours.length > 0 && contains(promptText, ["again", "evening", "bad", "worse", "same"])) {
    return {
      intent: "social",
      title: "Remembered Scroll Pattern",
      response_text: `This sounds like the same ${activeApp || "app"} loop returning, so the next move should use the pattern already known.`,
      bullets: [
        `Pattern: ${activeApp || "that app"} has been risky around ${rememberedRisk || riskWindow}.`,
        `Move: protect earlier than ${rememberedRisk || riskWindow}, especially because the last plan ${lastOutcome || "needs review"}.`,
        outcomeLine,
      ],
      primary_label: "Apply protection",
      secondary_label: "Open report",
      actions: selected && authorized ? [
        action("set_daily_limit", { minutes: 25 }),
        action("apply_schedule", { name: "Scroll Control", start_minute: weakHours[0] * 60, end_minute: ((weakHours[0] + 1) % 24) * 60, weekdays: [1, 2, 3, 4, 5, 6, 7], duration_days: 7 })
      ] : [action(selected ? "request_screen_time_permission" : "open_app_picker")],
      requires_selected_apps: !selected,
      requires_screen_time_authorization: !authorized,
    };
  }

  const base = {
    intent,
    title: "Digital Wellness Read",
    response_text: `This looks like a ${cluster}, not just a willpower problem.`,
    bullets: [
      `Pattern: your phone is becoming the default response around ${riskWindow}.`,
      `Move: add friction before ${rememberedRisk || riskWindow}, not after you are already scrolling.`,
      outcomeLine,
    ],
    primary_label: selected && authorized ? "Apply protection" : "Set up",
    secondary_label: "Open report",
    actions: selected && authorized ? [action("apply_ai_plan")] : [action(selected ? "request_screen_time_permission" : "open_app_picker")],
    requires_selected_apps: !selected,
    requires_screen_time_authorization: !authorized,
  };

  if (timeWindow && ["sleep", "focus", "social", "general"].includes(intent)) {
    const start = minuteText(timeWindow.start);
    const end = minuteText(timeWindow.end);
    const planIntent = intent === "general" ? "social" : intent;
    return {
      ...base,
      intent: planIntent,
      title: planIntent === "sleep" ? "Sleep Protection" : "Scheduled Protection",
      response_text: `I read this as a specific protection window: ${start} to ${end}.`,
      bullets: [
        "Pattern: the risky moment is already clear, so guessing is unnecessary.",
        `Move: shield distracting apps from ${start} to ${end}.`,
        selected ? "Use your current app selection." : "Choose the apps Blanked should control first.",
      ],
      primary_label: "Apply window",
      secondary_label: "Choose apps",
      actions: [action("apply_schedule", { name: planIntent === "sleep" ? "Sleep Protection" : "Scroll Control", start_minute: timeWindow.start, end_minute: timeWindow.end, weekdays: [1, 2, 3, 4, 5, 6, 7], duration_days: 7 })],
      requires_selected_apps: true,
      requires_screen_time_authorization: true,
    };
  }

  if (intent === "focus") {
    const requestedDuration = explicitDurationMinutes(prompt) || duration;
    const hardMode = wantsHardMode(prompt);
    return { ...base, title: hardMode ? "Strict Focus Protection" : "Focus Protection", response_text: "This is an execution moment, so the useful move is immediate friction.", bullets: [`Move: start ${requestedDuration} minutes now.`, "Keep the protected app list unchanged.", `Signal: ${riskWindow}.`], primary_label: "Start now", actions: [action("start_protection", { minutes: requestedDuration, hard_mode: hardMode })], requires_selected_apps: true, requires_screen_time_authorization: true };
  }

  if (intent === "study") {
    return {
      ...base,
      title: "24h Study Protection",
      response_text: "I read this as a study window, so the useful move is a short plan with friction already in place.",
      bullets: [
        "Read: studying needs fewer escape routes, not more motivation.",
        "Pattern: YouTube or social apps become fallback when effort rises.",
        "Move: block distractions during the next key study window and cap fallback scrolling."
      ],
      primary_label: "Apply study plan",
      secondary_label: "Choose apps",
      actions: [
        action("apply_schedule", { name: "Study Protection", start_minute: 9 * 60, end_minute: 12 * 60, weekdays: [1, 2, 3, 4, 5, 6, 7], duration_days: 1 }),
        action("set_daily_limit", { minutes: 30 })
      ],
      requires_selected_apps: true,
      requires_screen_time_authorization: true,
    };
  }

  if (intent === "sleep") {
    const bedtime = explicitSingleTime(prompt);
    const rememberedBedtime = memory.bedtime_minute == null ? null : cleanNumber(memory.bedtime_minute, 23 * 60, 0, 1439);
    const targetBedtime = bedtime ?? rememberedBedtime;
    if (targetBedtime != null) {
      const start = (targetBedtime + 24 * 60 - 30) % (24 * 60);
      return { ...base, title: "Bedtime Boundary", response_text: `If ${minuteText(targetBedtime)} is your sleep target, the useful boundary starts before that, not at random.`, bullets: [`Read: your target bedtime is ${minuteText(targetBedtime)}.`, "Pattern: the phone needs to become less available before the final scroll starts.", `Move: protect distracting apps from ${minuteText(start)} to ${minuteText(targetBedtime)} first.`], primary_label: "Apply boundary", actions: [action("apply_schedule", { name: "Sleep Boundary", start_minute: start, end_minute: targetBedtime, weekdays: [1, 2, 3, 4, 5, 6, 7], duration_days: 7 })] };
    }
    return { ...base, title: "Bedtime Scroll Loop", response_text: "This sounds like bedtime scrolling spilling into recovery, not a generic productivity issue.", bullets: ["Read: nights are the risky context.", "Pattern: the phone extends the day when your body needs shutdown.", "Move: tell me your usual bedtime before I suggest a block."], primary_label: "Tell bedtime", actions: [] };
  }

  if (intent === "emergency") {
    return {
      ...base,
      title: "Loss Of Control",
      response_text: context.is_blank_active ? "You are already protected; changing settings now would weaken the boundary." : "This is a high-risk moment. Reduce choice immediately.",
      bullets: context.is_blank_active ? [
        "Read: the urge is happening while protection is already on.",
        "Pattern: changing settings now would make the boundary weaker.",
        "Move: stay protected and review the trigger after the urge passes."
      ] : [
        `Read: emergency unlocks left today: ${cleanNumber(context.emergency_unlocks_remaining, 0, 0, 3)}.`,
        "Pattern: this is the wrong moment to redesign the whole plan.",
        "Move: use a short hard block, then review what triggered it."
      ],
      primary_label: context.is_blank_active ? "Stay protected" : "Start hard block",
      actions: context.is_blank_active ? [] : [action("start_protection", { minutes: 30, hard_mode: true })]
    };
  }

  if (intent === "allowOnly") {
    return { ...base, title: "Allow Only", response_text: "This is about reducing decisions: keep essentials available and remove the rest.", bullets: ["Move: allow only essential apps while protected.", "Use it when you need your phone but not the feed.", "Choose essentials like WhatsApp, Maps or calendar."], primary_label: "Enable Allow Only", secondary_label: "Choose apps", actions: [action("enable_allow_only"), action("open_app_picker")], requires_selected_apps: false };
  }

  if (intent === "vacation") {
    const active = context.vacation_mode_active === true;
    return { ...base, title: active ? "Resume Rules" : "Pause Rules", response_text: active ? "Your rules are paused; I can bring the structure back." : "Pausing is fine when the context changes, as long as it has an end.", bullets: active ? ["Read: the break is over.", "Pattern: structure should return without changing your selected apps.", "Move: resume schedules now."] : ["Read: your context changed for a short period.", "Pattern: open-ended pauses become accidental relapse.", "Move: pause scheduled protection for 7 days and keep manual blocks available."], primary_label: active ? "Resume rules" : "Pause 7 days", secondary_label: "Advanced", actions: active ? [action("disable_pause")] : [action("pause_rules", { hours: 168 })], requires_selected_apps: false, requires_screen_time_authorization: false };
  }

  if (intent === "weeklyReview") {
    return { ...base, title: "Weekly Read", response_text: "The useful question is whether the current protection is preventing breaks, not whether the plan sounds good.", bullets: [`Read: ${cleanNumber(context.weekly_protected_minutes, 0, 0, 10080)} protected minutes this week.`, `Pattern: ${cleanNumber(context.weekly_break_count, 0, 0, 100)} break signals detected.`, `Move: adapt the next plan around ${riskWindow}.`], primary_label: "Apply adaptive plan", secondary_label: "Open report", actions: [action("apply_ai_plan")] };
  }

  if (intent === "adultContent") {
    return { ...base, title: "Urge Protection", response_text: "This is a cue-control problem: make access harder before the urge peaks.", bullets: ["Read: this is an urge pattern, not a moral failure.", "Pattern: easy access keeps the loop available at the worst moment.", "Move: enable adult web filtering and keep distracting apps protected."], primary_label: "Enable protection", actions: [action("enable_adult_filter")], requires_selected_apps: false };
  }

  if (intent === "social") {
    return { ...base, title: "Scroll Loop", response_text: `This reads like ${cluster}: ${activeApp || "the app"} is filling a state, not just spare time.`, bullets: ["Pattern: the trigger matters more than total screen time.", `Move: block before ${rememberedRisk || "the usual scroll window"} and cap fallback use.`, "Start with a 25 minute daily limit plus an evening shield."], actions: [action("set_daily_limit", { minutes: 25 }), action("apply_schedule", { name: "Scroll Control", start_minute: 1230, end_minute: 1380, weekdays: [1, 2, 3, 4, 5, 6, 7], duration_days: 7 })] };
  }

  return { ...base, primary_label: "Got it", actions: [], requires_selected_apps: false, requires_screen_time_authorization: false };
}

const actionSchema = {
  type: "object",
  additionalProperties: false,
  required: ["type", "minutes", "hard_mode", "name", "start_minute", "end_minute", "weekdays", "duration_days", "hours"],
  properties: {
    type: { type: "string", enum: ["start_protection", "apply_schedule", "enable_allow_only", "enable_adult_filter", "set_daily_limit", "pause_rules", "disable_pause", "switch_mode", "open_app_picker", "request_screen_time_permission", "apply_ai_plan", "none"] },
    minutes: { type: ["integer", "null"], minimum: 5, maximum: 240 },
    hard_mode: { type: ["boolean", "null"] },
    name: { type: ["string", "null"], maxLength: 40 },
    start_minute: { type: ["integer", "null"], minimum: 0, maximum: 1439 },
    end_minute: { type: ["integer", "null"], minimum: 0, maximum: 1439 },
    weekdays: { type: ["array", "null"], items: { type: "integer", minimum: 1, maximum: 7 }, maxItems: 7 },
    duration_days: { type: ["integer", "null"], minimum: 1, maximum: 14 },
    hours: { type: ["integer", "null"], minimum: 1, maximum: 168 },
  },
};

const agentSchema = {
  type: "object",
  additionalProperties: false,
  required: ["interpretation", "behavior_pattern", "next_move", "plan"],
  properties: {
    interpretation: { type: "string", maxLength: 160 },
    behavior_pattern: { type: "string", maxLength: 160 },
    next_move: { type: "string", maxLength: 160 },
    plan: {
      type: "object",
      additionalProperties: false,
      required: ["intent", "title", "response_text", "bullets", "primary_label", "secondary_label", "actions", "requires_selected_apps", "requires_screen_time_authorization"],
      properties: {
        intent: { type: "string", enum: ["sleep", "focus", "study", "emergency", "allowOnly", "vacation", "weeklyReview", "adultContent", "social", "general"] },
        title: { type: "string", maxLength: 70 },
        response_text: { type: "string", maxLength: 180 },
        bullets: { type: "array", minItems: 2, maxItems: 4, items: { type: "string", maxLength: 140 } },
        primary_label: { type: "string", maxLength: 32 },
        secondary_label: { type: "string", maxLength: 32 },
        requires_selected_apps: { type: "boolean" },
        requires_screen_time_authorization: { type: "boolean" },
        actions: { type: "array", maxItems: 4, items: actionSchema },
      },
    },
  },
};

function normalizePlan(parsed, fallback) {
  const source = parsed && typeof parsed === "object" ? parsed : {};
  const plan = source.plan && typeof source.plan === "object" ? source.plan : source;
  const validIntents = new Set(["sleep", "focus", "study", "emergency", "allowOnly", "vacation", "weeklyReview", "adultContent", "social", "general"]);
  const modelActions = Array.isArray(plan.actions) ? plan.actions.slice(0, 4).map(normalizeAction).filter(Boolean) : null;
  const planIntent = validIntents.has(plan.intent) ? plan.intent : fallback.intent;
  if (planIntent !== fallback.intent) {
    return fallback;
  }
  const fallbackActionTypes = fallback.actions.filter((item) => item && item.type !== "none").map((item) => item.type).join("|");
  const modelActionTypes = (modelActions || []).filter((item) => item && item.type !== "none").map((item) => item.type).join("|");
  if (fallbackActionTypes !== modelActionTypes) {
    return fallback;
  }
  const bullets = Array.isArray(plan.bullets) ? plan.bullets.map((item) => userFacingText(item, 140)).filter(Boolean).slice(0, 4) : [];
  const interpretation = userFacingText(source.interpretation, 160);
  const behavior = userFacingText(source.behavior_pattern, 160);
  const nextMove = userFacingText(source.next_move, 160);
  const fallbackBullets = fallback.bullets;
  const actions = fallback.actions;
  const hasExecutableActions = actions.some((item) => item && item.type !== "none");
  const visibleBullets = hasExecutableActions ? bullets : bullets.filter((item) => !/^protection:/i.test(item));
  const structuredBullets = visibleBullets.filter((item) => /^(Read|Pattern|Move|Signal|Feedback):/i.test(item)).length >= 2;
  const preserveFallbackText = contains(fallback.response_text, [
    "already protected",
    "Choose the social apps in Screen Time first",
  ]);
  return {
    intent: planIntent,
    title: userFacingText(plan.title, 70) || fallback.title,
    response_text: preserveFallbackText ? fallback.response_text : userFacingText(plan.response_text, 180) || interpretation || fallback.response_text,
    bullets: visibleBullets.length >= 2 && structuredBullets ? visibleBullets : fallbackBullets,
    primary_label: cleanText(plan.primary_label, 32) || fallback.primary_label,
    secondary_label: cleanText(plan.secondary_label, 32) || fallback.secondary_label,
    actions,
    requires_selected_apps: hasExecutableActions ? fallback.requires_selected_apps : false,
    requires_screen_time_authorization: hasExecutableActions ? fallback.requires_screen_time_authorization : false,
  };
}

function normalizeAction(candidate) {
  if (!candidate || typeof candidate !== "object") return null;
  const type = cleanText(candidate.type, 60);
  const allowed = new Set(["start_protection", "apply_schedule", "enable_allow_only", "enable_adult_filter", "set_daily_limit", "pause_rules", "disable_pause", "switch_mode", "open_app_picker", "request_screen_time_permission", "apply_ai_plan", "none"]);
  if (!allowed.has(type)) return null;
  if (type === "none") return action("none");
  const candidateStart = candidate.start_minute == null ? null : cleanNumber(candidate.start_minute, 1320, 0, 1439);
  const candidateEnd = candidate.end_minute == null ? null : cleanNumber(candidate.end_minute, 420, 0, 1439);
  if (type === "enable_allow_only" && candidateStart != null && candidateEnd != null) {
    return action("apply_schedule", {
      name: cleanText(candidate.name, 40) || "Focus Protection",
      start_minute: candidateStart,
      end_minute: candidateEnd,
      weekdays: Array.isArray(candidate.weekdays) ? Array.from(new Set(candidate.weekdays.map((day) => cleanNumber(day, 1, 1, 7)))).slice(0, 7) : [1, 2, 3, 4, 5],
      duration_days: candidate.duration_days == null ? 7 : cleanNumber(candidate.duration_days, 7, 1, 14),
    });
  }
  const normalized = action(type, {
    minutes: candidate.minutes == null ? null : cleanNumber(candidate.minutes, 30, 5, 240),
    hard_mode: candidate.hard_mode === true ? true : candidate.hard_mode === false ? false : null,
    name: candidate.name == null ? null : cleanText(candidate.name, 40),
    start_minute: candidateStart,
    end_minute: candidateEnd,
    weekdays: Array.isArray(candidate.weekdays) ? Array.from(new Set(candidate.weekdays.map((day) => cleanNumber(day, 1, 1, 7)))).slice(0, 7) : null,
    duration_days: candidate.duration_days == null ? null : cleanNumber(candidate.duration_days, 7, 1, 14),
    hours: candidate.hours == null ? null : cleanNumber(candidate.hours, 168, 1, 168),
  });
  if (type === "set_daily_limit") return action(type, { minutes: normalized.minutes });
  if (type === "enable_allow_only" || type === "enable_adult_filter" || type === "open_app_picker" || type === "request_screen_time_permission" || type === "apply_ai_plan" || type === "disable_pause") return action(type);
  if (type === "switch_mode") return action(type, { name: normalized.name });
  if (type === "start_protection") return action(type, { minutes: normalized.minutes, hard_mode: normalized.hard_mode ?? false });
  if (type === "pause_rules") return action(type, { hours: normalized.hours });
  if (type === "apply_schedule") {
    return action(type, {
      name: normalized.name,
      start_minute: normalized.start_minute,
      end_minute: normalized.end_minute,
      weekdays: normalized.weekdays,
      duration_days: normalized.duration_days,
    });
  }
  return normalized;
}

function extractResponseText(responseBody) {
  if (typeof responseBody.output_text === "string") return responseBody.output_text;
  const output = Array.isArray(responseBody.output) ? responseBody.output : [];
  for (const item of output) {
    const content = Array.isArray(item.content) ? item.content : [];
    for (const part of content) {
      if (typeof part.text === "string") return part.text;
      if (typeof part.output_text === "string") return part.output_text;
    }
  }
  return "";
}

async function modelPlan(prompt, context, fallback) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) return { plan: fallback, source: "deterministic_fallback" };
  const model = process.env.OPENAI_MODEL || "gpt-4.1-mini";
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: { authorization: `Bearer ${apiKey}`, "content-type": "application/json" },
    body: JSON.stringify({
      model,
      input: [
        {
          role: "system",
          content:
            "You are Blanked, a conversational digital wellness AI for changing phone behavior. Your first job is to understand the user's screen habit, not to force a blocking plan. Ask one context question when a critical detail is missing. For night scrolling, do not propose or execute a schedule until you know the user's bedtime or the user gives an explicit time window. For vague scrolling, ask which app or when it happens before creating limits. Use actions only when the user's intent is clear enough to execute. Stay inside phone behavior, app blocking, Screen Time, sleep, attention, urges, relapse prevention, and healthier screen habits. Do not claim medical diagnosis, therapy, or treatment. Do not use the word coach. English only. Write directly to the person; never say user, the user, ask user, or mention internal implementation/QA/model/source/debug details. Keep response_text to 1-2 concrete sentences. Bullets should follow Read, Pattern, Move, Protection when relevant; omit Protection if no action should be taken yet. Action semantics: switch_mode selects one existing authorized mode by name; apply_schedule is the only action for recurring time windows; set_daily_limit is only a whole-day minute cap; start_protection is only an immediate timed block; enable_allow_only has no schedule; enable_adult_filter has no schedule; pause_rules uses hours only. Never describe an action as doing something its type cannot execute. Every action object must include all nullable action fields.",
        },
        {
          role: "user",
          content: JSON.stringify({
            prompt: cleanText(prompt, 600),
            context,
            memory_rules: [
              "Use context.memory.main_apps, bedtime_minute, weak_hours, pattern_cluster, and last_plan_outcome when present.",
              "If last_plan_outcome is broke, reduce intensity or move protection earlier instead of making the plan stricter.",
              "If last_plan_outcome is held, repeat the stable plan before increasing difficulty."
            ],
            examples: [
              { user: "I feel bad because I lose 3 hours on TikTok after work.", answer: "Read: decompression loop after work. Pattern: TikTok is being used to exit stress, then it becomes the evening. Move: protect the first 45 minutes after work and choose one offline decompression action." },
              { user: "How can I not scroll at nights?", answer: "Read: bedtime scrolling is the habit to understand. Pattern: the right boundary depends on the user's sleep target. Move: ask what time they usually want to be asleep before creating any block." },
              { user: "Block Instagram from 10 to 7.", answer: "Read: explicit schedule request. Pattern: bedtime risk window is clear. Move: apply a nightly shield from 10 PM to 7 AM." },
              { user: "I keep checking WhatsApp while working.", answer: "Read: compulsive checking loop. Pattern: the interruption is frequent and short, so app limits alone may be weak. Move: use Allow Only or a timed focus block." },
            ],
            output_contract: agentSchema,
          }),
        },
      ],
      text: { format: { type: "json_schema", name: "blanked_agent_response", strict: true, schema: agentSchema } },
      max_output_tokens: 800,
    }),
  });
  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`openai_failed_${response.status}:${detail.slice(0, 240)}`);
  }
  const body = await response.json();
  const parsed = JSON.parse(extractResponseText(body));
  return { plan: normalizePlan(parsed, fallback), source: `openai:${model}` };
}

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;
  try {
    const body = parseJsonBody(event);
    const prompt = cleanText(body.prompt, 600);
    if (!prompt) return json(400, { error: "missing_prompt" });
    const context = body.context && typeof body.context === "object" ? body.context : {};
    const fallback = fallbackPlan(prompt, context);
    let result;
    try {
      result = await modelPlan(prompt, context, fallback);
    } catch (error) {
      result = { plan: fallback, source: "deterministic_fallback_after_model_error", error: error.message };
    }
    return json(200, { ok: true, plan: result.plan, source: result.source, model_error: result.error || null });
  } catch (error) {
    return json(500, { error: "blanked_agent_failed", detail: error.message });
  }
};
