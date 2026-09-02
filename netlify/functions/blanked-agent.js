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

function classify(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  if (contains(text, ["porn", "porno", "adult", "xxx"])) return "adultContent";
  if (contains(text, ["losing control", "perdiendo el control", "urge", "emergency", "reca", "relapse", "can't stop", "no puedo parar"])) return "emergency";
  if (contains(text, ["sleep", "night", "bed", "dormir", "noche", "tired", "cansado", "morning"])) return "sleep";
  if (contains(text, ["exam", "study", "estudio", "estudiar", "examen", "opos"])) return "study";
  if (contains(text, ["allow only", "whatsapp", "maps", "solo", "only"])) return "allowOnly";
  if (contains(text, ["vacation", "holiday", "vacaciones", "pause", "pausa"])) return "vacation";
  if (contains(text, ["week", "semana", "analy", "diagn", "report", "review"])) return "weeklyReview";
  if (contains(text, ["tiktok", "instagram", "youtube", "gaming", "game", "dopamine", "scroll", "doomscroll"])) return "social";
  if (contains(text, ["anxious", "anxiety", "ansiedad", "bored", "boring", "aburr", "lonely", "stress", "guilt", "culpa"])) return "social";
  if (contains(text, ["focus", "work", "productiv", "foco", "trabaj", "deep work", "now"])) return "focus";
  return "general";
}

function behaviorCluster(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  if (contains(text, ["anxious", "anxiety", "ansiedad", "stress", "stressed"])) return "anxiety scroll";
  if (contains(text, ["bored", "boring", "aburr"])) return "boredom scroll";
  if (contains(text, ["revenge", "late", "night", "bed", "sleep", "dormir", "noche"])) return "bedtime scroll";
  if (contains(text, ["compare", "comparison", "instagram", "social"])) return "social comparison";
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
  const endMeridiem = match[6] || null;
  const startMeridiem = match[3] || endMeridiem;
  const start = minuteOfDay(Number(match[1]), Number(match[2] || 0), startMeridiem);
  const end = minuteOfDay(Number(match[4]), Number(match[5] || 0), endMeridiem);
  if (start == null || end == null || start === end) return null;
  return { start, end };
}

function minuteText(minuteOfDayValue) {
  const hour = Math.max(0, Math.min(23, Math.floor(minuteOfDayValue / 60)));
  const minute = Math.max(0, Math.min(59, minuteOfDayValue % 60));
  const displayHour = hour % 12 === 0 ? 12 : hour % 12;
  const meridiem = hour < 12 ? "AM" : "PM";
  return `${displayHour}:${String(minute).padStart(2, "0")} ${meridiem}`;
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
  const selected = context.has_selected_apps === true;
  const authorized = context.screen_time_authorized === true;
  const duration = cleanNumber(context.recommended_duration_minutes, 30, 5, 240);
  const riskWindow = cleanText(context.risk_window, 60) || "your next risk window";
  const cluster = behaviorCluster(prompt);
  const timeWindow = explicitTimeWindow(prompt);
  const setupLine = selected && authorized ? "Protection can run with your current setup." : "Setup comes first: choose apps and allow Screen Time.";
  const base = {
    intent,
    title: "Digital Wellness Read",
    response_text: `This looks like a ${cluster}, not just a willpower problem.`,
    bullets: [
      `Pattern: your phone is becoming the default response around ${riskWindow}.`,
      "Move: add friction before the loop starts, not after you are already scrolling.",
      setupLine,
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
    return { ...base, title: "Focus Protection", response_text: "This is an execution moment, so the useful move is immediate friction.", bullets: [`Move: start ${duration} minutes now.`, "Keep the protected app list unchanged.", `Signal: ${riskWindow}.`], primary_label: "Start now", actions: [action("start_protection", { minutes: duration, hard_mode: false })], requires_selected_apps: true, requires_screen_time_authorization: true };
  }

  if (intent === "sleep") {
    return { ...base, title: "Bedtime Scroll Loop", response_text: "This sounds like bedtime scrolling spilling into recovery, not a generic productivity issue.", bullets: ["Pattern: the phone is extending the day when your body needs shutdown.", "Move: protect the last hour before bed first.", "Start with a 10:30 PM to 7:30 AM shield for 7 days."], primary_label: "Apply sleep shield", actions: [action("apply_schedule", { name: "Sleep Protection", start_minute: 1350, end_minute: 450, weekdays: [1, 2, 3, 4, 5, 6, 7], duration_days: 7 })] };
  }

  if (intent === "emergency") {
    return { ...base, title: "Loss Of Control", response_text: context.is_blank_active ? "You are already protected; changing settings now would weaken the boundary." : "This is a high-risk moment. Reduce choice immediately.", bullets: [`Emergency unlocks left: ${cleanNumber(context.emergency_unlocks_remaining, 0, 0, 3)}.`, "Move: use a short hard block, then review what triggered it.", "Do not redesign the whole plan while the urge is active."], primary_label: context.is_blank_active ? "Stay protected" : "Start hard block", actions: context.is_blank_active ? [] : [action("start_protection", { minutes: 30, hard_mode: true })] };
  }

  if (intent === "allowOnly") {
    return { ...base, title: "Allow Only", response_text: "This is about reducing decisions: keep essentials available and remove the rest.", bullets: ["Move: allow only essential apps while protected.", "Use it when you need your phone but not the feed.", "Choose essentials like WhatsApp, Maps or calendar."], primary_label: "Enable Allow Only", secondary_label: "Choose apps", actions: [action("enable_allow_only"), action("open_app_picker")], requires_selected_apps: false };
  }

  if (intent === "vacation") {
    const active = context.vacation_mode_active === true;
    return { ...base, title: active ? "Resume Rules" : "Pause Rules", response_text: active ? "Your rules are paused; I can bring the structure back." : "Pausing is fine when the context changes, as long as it has an end.", bullets: active ? ["Resume schedules.", "Keep selected apps unchanged."] : ["Pause scheduled protection for 7 days.", "Keep manual blocks available.", "Resume automatically after the break."], primary_label: active ? "Resume rules" : "Pause 7 days", secondary_label: "Advanced", actions: active ? [action("disable_pause")] : [action("pause_rules", { hours: 168 })], requires_selected_apps: false, requires_screen_time_authorization: false };
  }

  if (intent === "weeklyReview") {
    return { ...base, title: "Weekly Read", response_text: "The useful question is whether the current protection is preventing breaks, not whether the plan sounds good.", bullets: [`${cleanNumber(context.weekly_protected_minutes, 0, 0, 10080)} protected minutes this week.`, `${cleanNumber(context.weekly_break_count, 0, 0, 100)} break signals detected.`, `Next risk window: ${riskWindow}.`], primary_label: "Apply adaptive plan", secondary_label: "Open report", actions: [action("apply_ai_plan")] };
  }

  if (intent === "adultContent") {
    return { ...base, title: "Urge Protection", response_text: "This is a cue-control problem: make access harder before the urge peaks.", bullets: ["Enable adult web filtering.", "Keep distracting apps protected.", "Use a 30 minute hard block when the urge is active."], primary_label: "Enable protection", actions: [action("enable_adult_filter")], requires_selected_apps: false };
  }

  if (intent === "social") {
    return { ...base, title: "Scroll Loop", response_text: `This reads like ${cluster}: the app is filling a state, not just spare time.`, bullets: ["Pattern: the trigger matters more than total screen time.", "Move: block before the usual scroll window and cap fallback use.", "Start with a 25 minute daily limit plus an evening shield."], actions: [action("set_daily_limit", { minutes: 25 }), action("apply_schedule", { name: "Scroll Control", start_minute: 1230, end_minute: 1380, weekdays: [1, 2, 3, 4, 5, 6, 7], duration_days: 7 })] };
  }

  return { ...base, primary_label: "Got it", actions: [], requires_selected_apps: false, requires_screen_time_authorization: false };
}

const actionSchema = {
  type: "object",
  additionalProperties: false,
  required: ["type", "minutes", "hard_mode", "name", "start_minute", "end_minute", "weekdays", "duration_days", "hours"],
  properties: {
    type: { type: "string", enum: ["start_protection", "apply_schedule", "enable_allow_only", "enable_adult_filter", "set_daily_limit", "pause_rules", "disable_pause", "open_app_picker", "request_screen_time_permission", "apply_ai_plan"] },
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
  const bullets = Array.isArray(plan.bullets) ? plan.bullets.map((item) => cleanText(item, 140)).filter(Boolean).slice(0, 4) : [];
  const interpretation = cleanText(source.interpretation, 160);
  const behavior = cleanText(source.behavior_pattern, 160);
  const nextMove = cleanText(source.next_move, 160);
  const fallbackBullets = [interpretation, behavior, nextMove].filter(Boolean).concat(fallback.bullets).slice(0, 4);
  return {
    intent: validIntents.has(plan.intent) ? plan.intent : fallback.intent,
    title: cleanText(plan.title, 70) || fallback.title,
    response_text: cleanText(plan.response_text, 180) || interpretation || fallback.response_text,
    bullets: bullets.length >= 2 ? bullets : fallbackBullets,
    primary_label: cleanText(plan.primary_label, 32) || fallback.primary_label,
    secondary_label: cleanText(plan.secondary_label, 32) || fallback.secondary_label,
    actions: modelActions == null ? fallback.actions : modelActions,
    requires_selected_apps: typeof plan.requires_selected_apps === "boolean" ? plan.requires_selected_apps : fallback.requires_selected_apps,
    requires_screen_time_authorization: typeof plan.requires_screen_time_authorization === "boolean" ? plan.requires_screen_time_authorization : fallback.requires_screen_time_authorization,
  };
}

function normalizeAction(candidate) {
  if (!candidate || typeof candidate !== "object") return null;
  const type = cleanText(candidate.type, 60);
  const allowed = new Set(["start_protection", "apply_schedule", "enable_allow_only", "enable_adult_filter", "set_daily_limit", "pause_rules", "disable_pause", "open_app_picker", "request_screen_time_permission", "apply_ai_plan"]);
  if (!allowed.has(type)) return null;
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
  if (type === "start_protection") return action(type, { minutes: normalized.minutes, hard_mode: normalized.hard_mode ?? false });
  if (type === "pause_rules") return action(type, { hours: normalized.hours });
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
            "You are Blanked, a digital wellness AI for changing phone behavior. First interpret the user's real phone habit pattern, then give one useful next move. Do not sound like a generic productivity assistant. Do not always propose a plan. Use actions only when execution is clearly useful. Stay inside phone behavior, app blocking, Screen Time, sleep, attention, urges, relapse prevention, and healthier screen habits. Do not claim medical diagnosis, therapy, or treatment. Do not use the word coach. English only. Keep response_text to 1-2 concrete sentences. Bullets should follow Read, Pattern, Move, Protection when relevant. Action semantics: apply_schedule is the only action for recurring time windows; set_daily_limit is only a whole-day minute cap; start_protection is only an immediate timed block; enable_allow_only has no schedule; enable_adult_filter has no schedule; pause_rules uses hours only. Never describe an action as doing something its type cannot execute. Every action object must include all nullable action fields.",
        },
        {
          role: "user",
          content: JSON.stringify({
            prompt: cleanText(prompt, 600),
            context,
            examples: [
              { user: "I feel bad because I lose 3 hours on TikTok after work.", answer: "Read: decompression loop after work. Pattern: TikTok is being used to exit stress, then it becomes the evening. Move: protect the first 45 minutes after work and choose one offline decompression action." },
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
