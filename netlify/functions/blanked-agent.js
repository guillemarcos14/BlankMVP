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
  if (contains(text, ["sleep", "night", "bed", "dormir", "noche"])) return "sleep";
  if (contains(text, ["exam", "study", "estudio", "estudiar", "examen", "opos"])) return "study";
  if (contains(text, ["losing control", "perdiendo el control", "urge", "emergency", "reca"])) return "emergency";
  if (contains(text, ["allow only", "whatsapp", "maps", "solo", "only"])) return "allowOnly";
  if (contains(text, ["vacation", "holiday", "vacaciones", "pause", "pausa"])) return "vacation";
  if (contains(text, ["week", "semana", "analy", "diagn"])) return "weeklyReview";
  if (contains(text, ["porn", "porno", "adult", "xxx"])) return "adultContent";
  if (contains(text, ["social", "tiktok", "instagram", "youtube", "gaming", "game", "dopamine", "scroll"])) return "social";
  if (contains(text, ["focus", "work", "productiv", "foco", "trabaj", "now"])) return "focus";
  return "general";
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

function fallbackPlan(prompt, context = {}) {
  const intent = classify(prompt);
  const selected = context.has_selected_apps === true;
  const authorized = context.screen_time_authorized === true;
  const duration = cleanNumber(context.recommended_duration_minutes, 30, 5, 240);
  const riskWindow = cleanText(context.risk_window, 60) || "your next risk window";
  const timeWindow = explicitTimeWindow(prompt);

  const base = {
    intent,
    title: "Adaptive Protection Plan",
    response_text: "I can turn that into a protection plan and apply it.",
    bullets: [
      cleanText(context.weekly_goal, 140) || "Protect the next high-risk window.",
      `Current risk window: ${riskWindow}.`,
      selected && authorized ? "Ready to apply." : "Setup is needed before execution.",
    ],
    primary_label: "Apply plan",
    secondary_label: "Choose apps",
    actions: [{ type: "apply_ai_plan" }],
    requires_selected_apps: true,
    requires_screen_time_authorization: true,
  };

  if (timeWindow && ["sleep", "focus", "social", "general"].includes(intent)) {
    const start = minuteText(timeWindow.start);
    const end = minuteText(timeWindow.end);
    const planIntent = intent === "general" ? "social" : intent;
    return {
      ...base,
      intent: planIntent,
      title: planIntent === "sleep" ? "Sleep Protection Plan" : "Scroll Control Plan",
      response_text: `I can protect that window from ${start} to ${end}.`,
      bullets: [
        `Block selected distracting apps from ${start} to ${end}.`,
        "Keep the same window for 7 days so Blanked can learn.",
        selected ? "Use your current app selection." : "Choose the apps Blanked should control first.",
      ],
      actions: [{ type: "apply_schedule", name: planIntent === "sleep" ? "Sleep Protection" : "Scroll Control", start_minute: timeWindow.start, end_minute: timeWindow.end, weekdays: [1, 2, 3, 4, 5, 6, 7], duration_days: 7 }],
    };
  }

  if (intent === "sleep") {
    return {
      ...base,
      title: "Night Protection Plan",
      response_text: "I can protect your nights before the scroll starts.",
      bullets: [
        "Block distracting apps from 10:30 PM to 7:30 AM.",
        "Use medium difficulty for the first 7 days.",
        "Keep the final hour before sleep protected.",
      ],
      actions: [{ type: "apply_schedule", name: "Night Protection", start_minute: 1350, end_minute: 450, weekdays: [1, 2, 3, 4, 5, 6, 7], duration_days: 7 }],
    };
  }

  if (intent === "focus") {
    return {
      ...base,
      title: "Focus Block",
      response_text: "I can start a protected focus block now.",
      bullets: [`Start ${duration} minutes now.`, "Keep your current protected apps.", `Risk signal: ${riskWindow}.`],
      primary_label: "Start now",
      actions: [{ type: "start_protection", minutes: duration, hard_mode: false }],
    };
  }

  if (intent === "study") {
    return {
      ...base,
      title: "24h Study Protection",
      response_text: "I can set an intensive study plan for the next 24 hours.",
      bullets: ["Protect 9:00 AM to 12:00 PM.", "Add a 30 minute daily limit.", "Keep the same apps until the exam window ends."],
      primary_label: "Apply study plan",
      actions: [
        { type: "apply_schedule", name: "Study Protection", start_minute: 540, end_minute: 720, weekdays: [1, 2, 3, 4, 5, 6, 7], duration_days: 1 },
        { type: "set_daily_limit", minutes: 30 },
      ],
    };
  }

  if (intent === "emergency") {
    return {
      ...base,
      title: "Immediate Protection",
      response_text: context.is_blank_active ? "You are already protected. Stay inside the block." : "I can protect you immediately.",
      bullets: [`${cleanNumber(context.emergency_unlocks_remaining, 0, 0, 3)} emergency unlocks left this week.`, "Start a 30 minute hard block.", "Review the trigger after the block."],
      primary_label: context.is_blank_active ? "Keep blocking" : "Start hard block",
      actions: context.is_blank_active ? [] : [{ type: "start_protection", minutes: 30, hard_mode: true }],
    };
  }

  if (intent === "allowOnly") {
    return {
      ...base,
      title: "Allow Only Mode",
      response_text: "I can switch Blanked into Allow Only mode.",
      bullets: ["Selected essentials stay available.", "Everything else is shielded while Blanked is active.", "Choose WhatsApp, Maps or other essentials in the picker."],
      primary_label: "Enable Allow Only",
      secondary_label: "Choose allowed apps",
      actions: [{ type: "enable_allow_only" }, { type: "open_app_picker" }],
      requires_selected_apps: false,
    };
  }

  if (intent === "vacation") {
    const active = context.vacation_mode_active === true;
    return {
      ...base,
      title: active ? "Resume Rules" : "Vacation Mode",
      response_text: active ? "Your rules are paused. I can resume them now." : "I can pause scheduled protection while you are away.",
      bullets: active ? ["Resume schedules.", "Keep selected apps unchanged."] : ["Pause schedules for 7 days.", "Keep manual protection available.", "Resume anytime."],
      primary_label: active ? "Resume rules" : "Pause 7 days",
      secondary_label: "Advanced",
      actions: active ? [{ type: "disable_pause" }] : [{ type: "pause_rules", hours: 168 }],
      requires_selected_apps: false,
      requires_screen_time_authorization: false,
    };
  }

  if (intent === "weeklyReview") {
    return {
      ...base,
      title: "Weekly Diagnosis",
      response_text: "Here is the current read. I can apply the adaptive plan from this.",
      bullets: [
        `${cleanNumber(context.weekly_protected_minutes, 0, 0, 10080)} protected minutes this week.`,
        `${cleanNumber(context.weekly_break_count, 0, 0, 100)} break signals detected.`,
        `Next risk window: ${riskWindow}.`,
      ],
      primary_label: "Apply adaptive plan",
      secondary_label: "Open report",
      actions: [{ type: "apply_ai_plan" }],
    };
  }

  if (intent === "adultContent") {
    return {
      ...base,
      title: "Adult Content Protection",
      response_text: "I can add adult content filtering to your phone protection.",
      bullets: ["Enable Apple's adult web content filter.", "Keep app protection available.", "Use hard blocks when urges spike."],
      primary_label: "Enable protection",
      actions: [{ type: "enable_adult_filter" }],
      requires_selected_apps: false,
    };
  }

  if (intent === "social") {
    return {
      ...base,
      title: "Scroll Control Plan",
      response_text: "I can reduce social scrolling with a daily limit and one preventive window.",
      bullets: ["Daily limit: 25 minutes.", "Preventive block: 8:30 PM to 11:00 PM.", "Keep the same apps for 7 days."],
      actions: [
        { type: "set_daily_limit", minutes: 25 },
        { type: "apply_schedule", name: "Scroll Control", start_minute: 1230, end_minute: 1380, weekdays: [1, 2, 3, 4, 5, 6, 7], duration_days: 7 },
      ],
    };
  }

  return base;
}

const agentSchema = {
  type: "object",
  additionalProperties: false,
  required: ["plan"],
  properties: {
    plan: {
      type: "object",
      additionalProperties: false,
      required: ["intent", "title", "response_text", "bullets", "primary_label", "secondary_label", "actions", "requires_selected_apps", "requires_screen_time_authorization"],
      properties: {
        intent: { type: "string", enum: ["sleep", "focus", "study", "emergency", "allowOnly", "vacation", "weeklyReview", "adultContent", "social", "general"] },
        title: { type: "string", maxLength: 70 },
        response_text: { type: "string", maxLength: 160 },
        bullets: { type: "array", minItems: 2, maxItems: 4, items: { type: "string", maxLength: 130 } },
        primary_label: { type: "string", maxLength: 32 },
        secondary_label: { type: "string", maxLength: 32 },
        requires_selected_apps: { type: "boolean" },
        requires_screen_time_authorization: { type: "boolean" },
        actions: {
          type: "array",
          maxItems: 4,
          items: {
            type: "object",
            additionalProperties: false,
            required: ["type", "minutes", "hard_mode", "name", "start_minute", "end_minute", "weekdays", "duration_days", "hours"],
            properties: {
              type: {
                type: "string",
                enum: [
                  "start_protection",
                  "apply_schedule",
                  "enable_allow_only",
                  "enable_adult_filter",
                  "set_daily_limit",
                  "pause_rules",
                  "disable_pause",
                  "open_app_picker",
                  "request_screen_time_permission",
                  "apply_ai_plan",
                ],
              },
              minutes: { type: ["integer", "null"], minimum: 5, maximum: 240 },
              hard_mode: { type: ["boolean", "null"] },
              name: { type: ["string", "null"], maxLength: 40 },
              start_minute: { type: ["integer", "null"], minimum: 0, maximum: 1439 },
              end_minute: { type: ["integer", "null"], minimum: 0, maximum: 1439 },
              weekdays: { type: ["array", "null"], items: { type: "integer", minimum: 1, maximum: 7 }, maxItems: 7 },
              duration_days: { type: ["integer", "null"], minimum: 1, maximum: 14 },
              hours: { type: ["integer", "null"], minimum: 1, maximum: 168 },
            },
          },
        },
      },
    },
  },
};

function normalizePlan(plan, fallback) {
  const source = plan && typeof plan === "object" ? plan : {};
  const validIntents = new Set(["sleep", "focus", "study", "emergency", "allowOnly", "vacation", "weeklyReview", "adultContent", "social", "general"]);
  const actions = Array.isArray(source.actions) ? source.actions.slice(0, 4).map(normalizeAction).filter(Boolean) : [];
  const bullets = Array.isArray(source.bullets) ? source.bullets.map((item) => cleanText(item, 130)).filter(Boolean).slice(0, 4) : [];

  return {
    intent: validIntents.has(source.intent) ? source.intent : fallback.intent,
    title: cleanText(source.title, 70) || fallback.title,
    response_text: cleanText(source.response_text, 160) || fallback.response_text,
    bullets: bullets.length >= 2 ? bullets : fallback.bullets,
    primary_label: cleanText(source.primary_label, 32) || fallback.primary_label,
    secondary_label: cleanText(source.secondary_label, 32) || fallback.secondary_label,
    actions: actions.length || fallback.actions.length === 0 ? actions : fallback.actions,
    requires_selected_apps: typeof source.requires_selected_apps === "boolean" ? source.requires_selected_apps : fallback.requires_selected_apps,
    requires_screen_time_authorization: typeof source.requires_screen_time_authorization === "boolean" ? source.requires_screen_time_authorization : fallback.requires_screen_time_authorization,
  };
}

function normalizeAction(action) {
  if (!action || typeof action !== "object") return null;
  const type = cleanText(action.type, 60);
  const allowed = new Set([
    "start_protection",
    "apply_schedule",
    "enable_allow_only",
    "enable_adult_filter",
    "set_daily_limit",
    "pause_rules",
    "disable_pause",
    "open_app_picker",
    "request_screen_time_permission",
    "apply_ai_plan",
  ]);
  if (!allowed.has(type)) return null;
  return {
    type,
    minutes: action.minutes == null ? null : cleanNumber(action.minutes, 30, 5, 240),
    hard_mode: action.hard_mode === true ? true : action.hard_mode === false ? false : null,
    name: action.name == null ? null : cleanText(action.name, 40),
    start_minute: action.start_minute == null ? null : cleanNumber(action.start_minute, 1320, 0, 1439),
    end_minute: action.end_minute == null ? null : cleanNumber(action.end_minute, 420, 0, 1439),
    weekdays: Array.isArray(action.weekdays) ? Array.from(new Set(action.weekdays.map((day) => cleanNumber(day, 1, 1, 7)))).slice(0, 7) : null,
    duration_days: action.duration_days == null ? null : cleanNumber(action.duration_days, 7, 1, 14),
    hours: action.hours == null ? null : cleanNumber(action.hours, 168, 1, 168),
  };
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
    headers: {
      authorization: `Bearer ${apiKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model,
      input: [
        {
          role: "system",
          content:
            "You are Blanked, an action-first digital wellness agent. Do not use the word coach. Return a concise executable plan for controlling phone behavior. You may only use the provided action types. Never claim medical diagnosis, therapy, or treatment. If setup is missing, the plan should request the needed permission or app picker. English only.",
        },
        {
          role: "user",
          content: JSON.stringify({
            prompt: cleanText(prompt, 600),
            context,
            output_contract: agentSchema,
          }),
        },
      ],
      text: {
        format: {
          type: "json_schema",
          name: "blanked_agent_plan",
          strict: true,
          schema: agentSchema,
        },
      },
      max_output_tokens: 700,
    }),
  });

  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`openai_failed_${response.status}:${detail.slice(0, 240)}`);
  }

  const body = await response.json();
  const parsed = JSON.parse(extractResponseText(body));
  return { plan: normalizePlan(parsed.plan, fallback), source: `openai:${model}` };
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
    if (explicitTimeWindow(prompt)) {
      result.plan = fallback;
    }

    return json(200, {
      ok: true,
      plan: result.plan,
      source: result.source,
      model_error: result.error || null,
    });
  } catch (error) {
    return json(500, { error: "blanked_agent_failed", detail: error.message });
  }
};
