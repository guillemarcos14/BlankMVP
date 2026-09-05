const { json, parseJsonBody, requireMethod } = require("./_membership");

function cleanText(value, maxLength = 240) {
  return String(value || "").trim().replace(/\s+/g, " ").slice(0, maxLength);
}

function paddedText(value, maxLength = 600) {
  return ` ${cleanText(value, maxLength).toLowerCase()} `;
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
    .replace(/\bI'?ve set\b/gi, "I can set")
    .replace(/\bI have set\b/gi, "I can set")
    .replace(/\bI created\b/gi, "I can create")
    .replace(/\bI'?ll set\b/gi, "I can set")
    .replace(/\bHe preparado\b/gi, "Puedo preparar")
    .replace(/\bHe creado\b/gi, "Puedo crear")
    .replace(/\bConfiguraré\b/gi, "Puedo configurar")
    .replace(/\bVoy a configurar\b/gi, "Puedo configurar")
    .replace(/\bVoy a preparar\b/gi, "Puedo preparar")
    .replace(/\bask the user\b/gi, "tell me")
    .replace(/\bask user\b/gi, "tell me")
    .replace(/\bthe user\b/gi, "you")
    .replace(/\buser's\b/gi, "your")
    .replace(/\buser\b/gi, "you");
}

function responseLanguage(prompt, context = {}) {
  const explicit = cleanText(context.language || context.locale || "", 20).toLowerCase();
  if (explicit.startsWith("es")) return "es";
  if (explicit.startsWith("en")) return "en";
  const text = cleanText(prompt, 600).toLowerCase();
  const spanishScore = [
    "¿", "á", "é", "í", "ó", "ú", "ñ",
    "como puedo", "cómo puedo", "que deberia", "qué debería", "quiero", "bloquear", "bloquea",
    "despues", "después", "comer", "cenar", "despertar", "trabajar", "estudiar",
    "movil", "móvil", "no uso", "lo necesito", "para siempre", "consejo", "ayudame", "ayúdame",
    "bienestar digital", "redes", "redes sociales", "perdiendo mucho tiempo", "por la noche", "estoy", "me quedo", "scrolleando", "dormir", "fatal",
    "concentrarme", "asistente personal", "controlar mi móvil", "controlar mi movil", "hazme",
    "recuérdame", "recuerdame", "esta tarde", "esta noche",
  ].reduce((score, token) => score + (text.includes(token) ? 1 : 0), 0);
  const englishScore = [
    "how can i", "what should i", "block", "after", "phone", "sleep", "work", "study",
    "instagram", "tiktok", "youtube", "scroll", "focus", "advice", "help me",
  ].reduce((score, token) => score + (text.includes(token) ? 1 : 0), 0);
  return spanishScore > englishScore ? "es" : "en";
}

function localizeMinuteText(text, language) {
  if (language !== "es") return text;
  return String(text)
    .replace(/\bAM\b/g, "a. m.")
    .replace(/\bPM\b/g, "p. m.")
    .replace(/\b to \b/g, " a ")
    .replace(/m\.\./g, "m.");
}

function localizeText(value, language) {
  const text = cleanText(value, 220);
  if (language !== "es" || !text) return text;
  const scheduleMatch = text.match(/^I read this as a specific protection window: (.+) to (.+)\.$/i);
  if (scheduleMatch) return localizeMinuteText(`Lo leo como una franja concreta de protección entre ${scheduleMatch[1]} y ${scheduleMatch[2]}.`, language);
  const exact = {
    "Context Corrected": "Contexto corregido",
    "Bounded Protection": "Protección limitada",
    "Bedtime Scroll Read": "Lectura de noche",
    "Scroll Pattern": "Patrón de scroll",
    "Contextual Boundary": "Límite contextual",
    "Work App Conflict": "Conflicto con app de trabajo",
    "Choose Apps": "Elegir apps",
    "Choose App": "Elegir app",
    "App Privacy": "Privacidad de apps",
    "Digital Wellness Read": "Lectura digital",
    "Scheduled Protection": "Protección programada",
    "Focus Protection": "Protección de foco",
    "Strict Focus Protection": "Protección estricta",
    "24h Study Protection": "Protección de estudio",
    "Bedtime Boundary": "Límite de sueño",
    "Bedtime Scroll Loop": "Scroll de noche",
    "Loss Of Control": "Pérdida de control",
    "Allow Only": "Solo esenciales",
    "Resume Rules": "Reactivar reglas",
    "Pause Rules": "Pausar reglas",
    "Weekly Read": "Lectura semanal",
    "Urge Protection": "Protección ante impulso",
    "Scroll Loop": "Bucle de scroll",
    "Plan Context": "Contexto del plan",
    "Noted": "Anotado",
    "Tell pattern": "Contar patrón",
    "Tell target": "Contar objetivo",
    "Tell bedtime": "Contar hora",
    "Tell app": "Contar app",
    "Tell time": "Contar hora",
    "Tell window": "Contar franja",
    "Choose apps": "Elegir apps",
    "Choose app": "Elegir app",
    "Allow Screen Time": "Permitir Screen Time",
    "Got it": "Entendido",
    "Set up": "Configurar",
    "Apply window": "Aplicar franja",
    "Start now": "Empezar ahora",
    "Apply study plan": "Aplicar plan",
    "Stay protected": "Mantener protección",
    "Start hard block": "Bloqueo fuerte",
    "Enable Allow Only": "Activar esenciales",
    "Pause 7 days": "Pausar 7 días",
    "Advanced": "Avanzado",
    "Apply adaptive plan": "Aplicar plan",
    "Open report": "Abrir informe",
    "Enable protection": "Activar protección",
    "Apply protection": "Aplicar protección",
    "Tell goal": "Contar objetivo",
    "Not now": "Ahora no",
    "I can help make access harder, but I will only create bounded rules with a clear target and exit path. Tell me the app or moment to protect first.": "Puedo hacer el acceso más difícil, pero solo crearé reglas limitadas con un objetivo claro y una salida. Dime primero la app o el momento que quieres proteger.",
    "Got it. I will not use that app as context. Which app, moment or habit should we focus on instead?": "Entendido. No usaré esa app como contexto. ¿En qué app, momento o hábito deberíamos centrarnos?",
    "This sounds like a bedtime scroll loop. Before I block anything, I need your sleep target.": "Esto suena a bucle de scroll de noche. Antes de bloquear nada, necesito tu hora objetivo para dormir.",
    "I can help with that, but first I need to know where the loop happens.": "Puedo ayudarte con eso, pero primero necesito saber dónde ocurre el bucle.",
    "Most people do best starting 10-15 minutes after lunch. What time do you usually finish eating?": "Suele funcionar mejor empezar 10-15 minutos después de comer. ¿A qué hora sueles terminar de comer?",
    "What time do you usually finish dinner?": "¿A qué hora sueles terminar de cenar?",
    "What time do you usually wake up?": "¿A qué hora sueles despertarte?",
    "What time do you usually finish work?": "¿A qué hora sueles terminar de trabajar?",
    "Choose the social apps in Screen Time first, then I can apply the block.": "Elige primero las apps sociales en Screen Time y después puedo aplicar el bloqueo.",
    "I can use counts and context you choose to share, but I do not need your exact app list to reason about the pattern.": "Puedo usar conteos y contexto que decidas compartir, pero no necesito tu lista exacta de apps para razonar sobre el patrón.",
    "This is an execution moment, so the useful move is immediate friction.": "Este es un momento de ejecución: lo útil ahora es añadir fricción inmediata.",
    "I read this as a study window, so the useful move is a short plan with friction already in place.": "Lo leo como una franja de estudio: lo útil es un plan corto con fricción ya preparada.",
    "This sounds like bedtime scrolling spilling into recovery, not a generic productivity issue.": "Esto suena a scroll nocturno invadiendo descanso, no a un problema genérico de productividad.",
    "You are already protected; changing settings now would weaken the boundary.": "Ya estás protegido; cambiar ajustes ahora debilitaría el límite.",
    "This is a high-risk moment. Reduce choice immediately.": "Este es un momento de alto riesgo. Reduce opciones de inmediato.",
    "This is about reducing decisions: keep essentials available and remove the rest.": "Esto va de reducir decisiones: deja lo esencial disponible y quita el resto.",
    "Your rules are paused; I can bring the structure back.": "Tus reglas están pausadas; puedo recuperar la estructura.",
    "Pausing is fine when the context changes, as long as it has an end.": "Pausar está bien cuando cambia el contexto, siempre que tenga final.",
    "The useful question is whether the current protection is preventing breaks, not whether the plan sounds good.": "La pregunta útil es si la protección actual evita rupturas, no si el plan suena bien.",
    "This is a cue-control problem: make access harder before the urge peaks.": "Esto es un problema de control de señales: haz el acceso más difícil antes de que el impulso suba.",
    "I can build a plan, but first I need the real loop. Which app, moment or habit should we focus on?": "Puedo crear un plan, pero primero necesito el bucle real. ¿En qué app, momento o hábito nos centramos?",
    "Start by identifying the moment when the phone becomes automatic. Then make that moment slightly harder before adding strict blocks.": "Empieza identificando el momento en que el móvil se vuelve automático. Después haz ese momento un poco más difícil antes de añadir bloqueos estrictos.",
    "I can help with screen-habit advice, a diagnosis or a protection plan if you want to go further.": "Puedo ayudarte con consejo sobre hábitos digitales, una lectura del patrón o un plan de protección si quieres ir más allá.",
    "Read: you are asking for guidance, not a blocking plan yet.": "Lectura: estás pidiendo guía, no un plan de bloqueo todavía.",
    "Pattern: the trigger usually matters more than total screen time.": "Patrón: el disparador suele importar más que el tiempo total de pantalla.",
    "Move: name the app and the moment it usually takes over.": "Movimiento: dime la app y el momento en que suele tomar el control.",
    "Read: there is no clear action request yet.": "Lectura: todavía no hay una petición de acción clara.",
    "Pattern: Blanked should not turn every message into a blocking plan.": "Patrón: Blanked no debe convertir cada mensaje en un plan de bloqueo.",
    "Move: tell me whether you want advice or a plan.": "Movimiento: dime si quieres consejo o un plan.",
    "Personal Assistant": "Asistente personal",
    "Reminder Context": "Contexto de recordatorio",
    "Plan Timing": "Horario del plan",
    "Automation Setup": "Configuración automática",
    "I can read your phone-habit patterns, explain what is changing, and turn that into blocks, schedules, limits, reports or setup steps when it helps.": "Puedo leer tus patrones de uso del móvil, explicar qué está cambiando y convertirlo en bloqueos, horarios, límites, informes o pasos de configuración cuando ayude.",
    "I can help prevent that moment, but this action should become either a notification setup or a block window. What time should I protect?": "Puedo ayudarte a prevenir ese momento, pero esto debe convertirse en una notificación o en una franja de bloqueo. ¿A qué hora debería protegerte?",
    "I can plan this, but I need the time window before I start anything now.": "Puedo planificarlo, pero necesito la franja horaria antes de iniciar nada ahora.",
    "I can help automate protection, but first I need the pattern to optimize: app, weak moment, goal or risk window.": "Puedo ayudarte a automatizar la protección, pero primero necesito el patrón a optimizar: app, momento débil, objetivo o franja de riesgo.",
    "Read: I can respond when you ask and also use signals when your pattern changes.": "Lectura: puedo responder cuando me escribes y también usar señales cuando cambia tu patrón.",
    "Pattern: the useful move depends on your apps, weak hours, plan history and permissions.": "Patrón: el movimiento útil depende de tus apps, franjas débiles, historial del plan y permisos.",
    "Move: tell me the moment you want to improve, or ask me to review your current pattern.": "Movimiento: dime el momento que quieres mejorar o pídeme revisar tu patrón actual.",
    "Read: you want proactive help before the scroll starts.": "Lectura: quieres ayuda proactiva antes de que empiece el scroll.",
    "Pattern: the useful solution needs a clear time or risk window.": "Patrón: la solución útil necesita una hora o franja de riesgo clara.",
    "Move: tell me the time, then I can suggest the right protection.": "Movimiento: dime la hora y podré sugerir la protección adecuada.",
    "Read: this is about future focus, not an immediate block.": "Lectura: esto va de foco futuro, no de un bloqueo inmediato.",
    "Pattern: scheduled protection works better when the start time is clear.": "Patrón: la protección programada funciona mejor con hora de inicio clara.",
    "Move: tell me the time window, then I can set the plan.": "Movimiento: dime la franja horaria y podré preparar el plan.",
    "Read: you want BAi to act with more initiative.": "Lectura: quieres que BAi actúe con más iniciativa.",
    "Pattern: automatic changes need a clear rule and a safe exit.": "Patrón: los cambios automáticos necesitan una regla clara y una salida segura.",
    "Move: tell me what to protect first, then I can recommend the right automation.": "Movimiento: dime qué proteger primero y podré recomendar la automatización adecuada.",
  };
  if (exact[text]) return exact[text];
  let translated = text
    .replace(/^Read:/i, "Lectura:")
    .replace(/^Pattern:/i, "Patrón:")
    .replace(/^Move:/i, "Movimiento:")
    .replace(/^Signal:/i, "Señal:")
    .replace(/^Feedback:/i, "Feedback:")
    .replace(/^Protection:/i, "Protección:")
    .replace(/\bscreen habit loop\b/gi, "bucle de hábito digital")
    .replace(/\banxiety scroll\b/gi, "scroll por ansiedad")
    .replace(/\bboredom scroll\b/gi, "scroll por aburrimiento")
    .replace(/\bbedtime scroll\b/gi, "scroll de noche")
    .replace(/\bsocial comparison\b/gi, "comparación social")
    .replace(/\bavoidance loop\b/gi, "bucle de evitación")
    .replace(/\bcompulsive checking\b/gi, "revisión compulsiva")
    .replace(/\blow-energy scroll\b/gi, "scroll por baja energía")
    .replace(/\bthe app\b/gi, "la app")
    .replace(/\byour phone\b/gi, "tu móvil")
    .replace(/\bphone\b/gi, "móvil")
    .replace(/\bapp\b/gi, "app")
    .replace(/\bapps\b/gi, "apps")
    .replace(/\bhabit\b/gi, "hábito")
    .replace(/\bhabits\b/gi, "hábitos")
    .replace(/\btrigger\b/gi, "disparador")
    .replace(/\btriggers\b/gi, "disparadores")
    .replace(/\bpattern\b/gi, "patrón")
    .replace(/\bpatterns\b/gi, "patrones")
    .replace(/\bprotection\b/gi, "protección")
    .replace(/\bprotect\b/gi, "proteger")
    .replace(/\bblock\b/gi, "bloquear")
    .replace(/\bboundary\b/gi, "límite")
    .replace(/\bboundaries\b/gi, "límites")
    .replace(/\brisk window\b/gi, "franja de riesgo")
    .replace(/\bwillpower\b/gi, "fuerza de voluntad")
    .replace(/\btell me\b/gi, "dime")
    .replace(/\busual\b/gi, "habitual")
    .replace(/\bsleep target\b/gi, "hora objetivo para dormir")
    .replace(/\bbedtime\b/gi, "hora de dormir")
    .replace(/\bwork\b/gi, "trabajo")
    .replace(/\bstudy\b/gi, "estudio")
    .replace(/\bnon-work use\b/gi, "uso no laboral")
    .replace(/\bnot a generic focus issue\b/gi, "no es un problema genérico de foco");
  translated = translated
    .replace(/^Lectura: you want protection after lunch\.$/i, "Lectura: quieres protección después de comer.")
    .replace(/^Lectura: you want protection after dinner\.$/i, "Lectura: quieres protección después de cenar.")
    .replace(/^Lectura: you want protection after waking up\.$/i, "Lectura: quieres proteger la primera revisión del móvil.")
    .replace(/^Lectura: you want protection after work\.$/i, "Lectura: quieres protección después de trabajar.")
    .replace(/^Movimiento: dime when you usually finish lunch, then I can place the límite without guessing\.$/i, "Movimiento: dime cuándo sueles terminar de comer y colocaré el límite sin adivinar.")
    .replace(/^Movimiento: dime when dinner usually ends, then I can set the límite around the real risk moment\.$/i, "Movimiento: dime cuándo suele terminar la cena y ajustaré el límite al momento real de riesgo.")
    .replace(/^Movimiento: dime your habitual wake-up time, then I can proteger the first móvil check\.$/i, "Movimiento: dime tu hora habitual de despertar y protegeré la primera revisión del móvil.")
    .replace(/^Movimiento: dime when trabajo usually ends, then I can proteger the decompression window\.$/i, "Movimiento: dime cuándo sueles terminar de trabajar y protegeré la franja de desconexión.");
  return localizeMinuteText(translated, language);
}

function localizePlan(plan, language) {
  if (language !== "es") return plan;
  return {
    ...plan,
    title: localizeText(plan.title, language).slice(0, 70),
    message_text: localizeText(plan.message_text, language).slice(0, 320),
    response_text: localizeText(plan.response_text, language).slice(0, 180),
    bullets: Array.isArray(plan.bullets) ? plan.bullets.map((item) => localizeText(item, language).slice(0, 140)) : [],
    primary_label: localizeText(plan.primary_label, language).slice(0, 32),
    secondary_label: localizeText(plan.secondary_label, language).slice(0, 32),
  };
}

function hasSpanishLanguageLeak(plan) {
  const text = [
    plan.title,
    plan.response_text,
    plan.primary_label,
    plan.secondary_label,
    ...(Array.isArray(plan.bullets) ? plan.bullets : []),
  ].filter(Boolean).join(" ");
  return /\b(Let me|brief|session|support|right now|distracting|start|block|apps and|focus|help you|you want|depends on|when you|then I can|use, then|the same app|full block|could break|work instead)\b/i.test(text);
}

function stripBulletPrefix(value) {
  return cleanText(value, 180)
    .replace(/^(Read|Pattern|Move|Signal|Feedback|Protection|Lectura|Patrón|Movimiento|Señal|Protección):\s*/i, "")
    .replace(/\.$/, "");
}

function conversationalMessage(plan, language = "en") {
  const response = cleanText(plan.response_text, 220);
  const bullets = Array.isArray(plan.bullets) ? plan.bullets.map(stripBulletPrefix).filter(Boolean) : [];
  const actions = Array.isArray(plan.actions) ? plan.actions.filter((item) => item && item.type && item.type !== "none") : [];
  const hasQuestion = /[?¿]\s*$/.test(response);
  const move = bullets.find((item) => /tell me|what time|which app|dime|qué app|que app|a qué hora|cuando|cuándo/i.test(item));

  if (!actions.length && hasQuestion) return response;
  if (!actions.length && /\bsleep target\b|hora objetivo para dormir/i.test(response)) return response;
  if (!actions.length && move && !response.toLowerCase().includes(move.toLowerCase())) {
    const normalizedMove = move.charAt(0).toUpperCase() + move.slice(1);
    return `${response} ${normalizedMove.endsWith("?") || normalizedMove.endsWith("¿") ? normalizedMove : normalizedMove + "."}`.slice(0, 320);
  }

  if (actions.length) {
    const actionLine = language === "es"
      ? "Puedo prepararlo en Blanked si lo confirmas."
      : "I can prepare it in Blanked if you confirm.";
    return `${response} ${actionLine}`.slice(0, 320);
  }

  return response || (language === "es" ? "Puedo ayudarte con eso en Blanked." : "I can help with that in Blanked.");
}

function hasExplicitBlockRequest(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  return contains(text, ["block", "bloquea", "bloquear", "shield", "protect", "set ", "schedule", "limit", "from"]);
}

function asksForAdvice(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  return contains(text, [
    "how can i",
    "what can i do",
    "what should i",
    "help me understand",
    "help me improve",
    "recommend",
    "advice",
    "advise",
    "tips",
    "why do i",
    "review",
    "diagnose",
    "analyze",
    "analyse",
    "como puedo",
    "qué debería",
    "que deberia",
    "aconseja",
    "consejo",
    "ayudame",
    "ayúdame",
    "mejorar",
    "bienestar digital",
  ]);
}

function asksForPlan(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  return contains(text, [
    " plan",
    "plan ",
    "make me a plan",
    "create a plan",
    "build a plan",
    "give me a plan",
    "set up a plan",
    "focus plan",
    "protection plan",
    "quiero un plan",
    "hazme un plan",
  ]);
}

function asksWhereToStart(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  return contains(text, [
    "where to start",
    "where should i start",
    "how to start",
    "don't know where to start",
    "do not know where to start",
    "no se por donde empezar",
    "no sé por dónde empezar",
  ]);
}

function asksForPermanentLockout(prompt) {
  const text = paddedText(prompt, 600);
  return contains(text, ["forever", "permanently", "para siempre", "ever again", "impossible to use", "delete my distractions"]) &&
    contains(text, ["block", "blok", "bloquea", "bloquear", "everything", "todo", "phone", "distractions"]);
}

function asksAboutAssistantCapabilities(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  return contains(text, [
    "what can you do",
    "how can you help",
    "can you help me with",
    "que puedes hacer",
    "qué puedes hacer",
    "como me puedes ayudar",
    "cómo me puedes ayudar",
    "asistente personal",
  ]);
}

function asksForUnsupportedReminder(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  return contains(text, ["remind me", "reminder", "notify me", "ping me", "recuérdame", "recuerdame", "avísame", "avisame"]) &&
    !contains(text, ["block", "bloquea", "bloquear", "protect", "proteger"]);
}

function asksForBroadAutomation(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  return contains(text, ["automatically", "manage my phone", "control my phone", "auto", "automático", "automatico", "controlar mi móvil", "controlar mi movil"]) &&
    !contains(text, ["from", "at ", "after", "de ", "desde", "a las", "después", "despues", "now", "ahora"]);
}

function relativeMoment(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  if (contains(text, ["after lunch", "right after lunch", "despues de comer", "después de comer", "despues de lunch", "después de lunch"])) {
    return {
      key: "lunch",
      label: "after lunch",
      question: "Most people do best starting 10-15 minutes after lunch. What time do you usually finish eating?",
      move: "tell me when you usually finish lunch, then I can place the boundary without guessing.",
    };
  }
  if (contains(text, ["after dinner", "right after dinner", "despues de cenar", "después de cenar", "despues de dinner", "después de dinner"])) {
    return {
      key: "dinner",
      label: "after dinner",
      question: "What time do you usually finish dinner?",
      move: "tell me when dinner usually ends, then I can set the boundary around the real risk moment.",
    };
  }
  if (contains(text, ["when i wake up", "after waking", "wake up", "al despertar", "cuando me despierto"])) {
    return {
      key: "wake",
      label: "after waking up",
      question: "What time do you usually wake up?",
      move: "tell me your usual wake-up time, then I can protect the first phone check.",
    };
  }
  if (contains(text, ["after work", "right after work", "despues de trabajar", "después de trabajar", "despues de work", "después de work"])) {
    return {
      key: "work_end",
      label: "after work",
      question: "What time do you usually finish work?",
      move: "tell me when work usually ends, then I can protect the decompression window.",
    };
  }
  return null;
}

function promptHasFutureTiming(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  return contains(text, ["tomorrow", "mañana", "later", "tonight", "esta noche", "this evening", "esta tarde"]);
}

function routineAnchorMinute(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  const match = text.match(/(?:at|around|a las|sobre)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?/i);
  if (!match) return null;
  const rawHour = Number(match[1]);
  const meridiem = match[3] || (rawHour >= 1 && rawHour <= 7 ? "pm" : null);
  return minuteOfDay(rawHour, Number(match[2] || 0), meridiem);
}

function hasBedtime(prompt, context = {}) {
  const text = cleanText(prompt, 600).toLowerCase();
  if (scrollUntilSleepTime(prompt)) return false;
  if (explicitSingleTime(prompt) != null) return true;
  const memory = context.memory && typeof context.memory === "object" ? context.memory : {};
  return Boolean(memory.bedtime_minute != null || contains(text, ["my bedtime", "go to sleep at", "me duermo a", "me voy a dormir a"]));
}

function hasKnownMainApp(context = {}) {
  const memory = context.memory && typeof context.memory === "object" ? context.memory : {};
  return Array.isArray(memory.main_apps) && memory.main_apps.length > 0;
}

function hasKnownWeakHour(context = {}) {
  const memory = context.memory && typeof context.memory === "object" ? context.memory : {};
  return Array.isArray(memory.weak_hours) && memory.weak_hours.some((hour) => Number.isFinite(Number(hour)));
}

function namedApp(prompt) {
  const text = paddedText(prompt, 600);
  const apps = [
    ["tiktok", "TikTok"],
    ["tik tok", "TikTok"],
    ["instagram", "Instagram"],
    ["insta", "Instagram"],
    [" ig ", "Instagram"],
    ["youtube", "YouTube"],
    ["yt", "YouTube"],
    ["youtube shorts", "YouTube"],
    ["reddit", "Reddit"],
    ["twitter", "Twitter"],
    [" x ", "Twitter"],
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

function appCorrection(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  const negatesUse = contains(text, [
    "i don't use",
    "i dont use",
    "i do not use",
    "i never use",
    "dont use",
    "don't use",
    "do not use",
    "no uso",
    "yo no uso",
  ]);
  if (!negatesUse) return "";
  const apps = ["tiktok", "tik tok", "instagram", "insta", "ig", "youtube", "yt", "reddit", "twitter", "facebook", "snapchat"];
  return apps.find((app) => text.includes(app)) || "";
}

function requestedUnknownApp(prompt) {
  const text = cleanText(prompt, 600);
  const match = text.match(/\b(?:block|limit|bloquea|bloquear)\s+([a-z][a-z0-9._+-]{1,30})\b/i);
  if (!match) return "";
  const raw = match[1];
  const lowered = raw.toLowerCase();
  const blockedWords = new Set(["everything", "all", "todos", "todas", "adult", "websites", "apps", "app", "social", "media", "networks", "redes", "my", "me", "now", "for", "from", "during", "strict", "hard", "distractions", "distracciones"]);
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
  const text = paddedText(prompt, 600);
  return contains(text, ["but i need", "but need", "need it", "need this app", "except i need", "for work", "for studying", "for study", "work tutorials", "para trabajar", "para estudiar", "lo necesito", "la necesito"]) &&
    contains(text, ["block", "blok", "bloquea", "bloquear", "limit", "distract", "tiktok", "tik tok", "instagram", "insta", " ig ", "youtube", "yt", "reddit", "twitter", " x ", "facebook", "snapchat"]);
}

function asksAboutExactAppList(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  return contains(text, ["exact app list", "my app list", "which apps", "see my apps", "selected apps", "all my apps", "access all my apps", "lista exacta de apps", "mis apps"]) &&
    contains(text, ["see", "know", "access", "visible", "can you", "puedes ver", "sabes", "acceder"]);
}

function needsContextBeforeAction(prompt, intent, context = {}) {
  const text = cleanText(prompt, 600).toLowerCase();
  const moment = relativeMoment(prompt);
  const memory = context.memory && typeof context.memory === "object" ? context.memory : {};
  const rememberedApps = Array.isArray(memory.main_apps) ? memory.main_apps.map((app) => cleanText(app, 40).toLowerCase()) : [];
  const promptApp = namedApp(prompt).toLowerCase();
  const sameRememberedApp = promptApp !== "the app" && rememberedApps.includes(promptApp);
  if (moment && !explicitTimeWindow(prompt) && (!hasKnownWeakHour(context) || !sameRememberedApp) && (hasExplicitBlockRequest(prompt) || intent === "social")) {
    return moment.key;
  }
  if (intent === "sleep" && !explicitTimeWindow(prompt) && !hasBedtime(prompt, context) && !hasExplicitBlockRequest(prompt)) {
    return "bedtime";
  }
  if (intent === "sleep" && scrollUntilSleepTime(prompt) && !hasBedtime(prompt, context)) {
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
  const text = paddedText(prompt, 600);
  if (asksWhereToStart(prompt)) return "general";
  if (asksForPlan(prompt) && !hasExplicitBlockRequest(prompt) && !contains(text, ["after", "when", "from", "at ", "tonight", "now", "ahora"])) return "general";
  if (contains(text, ["screen time is bad", "use my phone too much", "too much with my phone", "demasiado con el movil", "demasiado con el móvil", "phone is killing my focus"])) return "general";
  if (explicitDurationMinutes(prompt) && contains(text, ["hard block", "hard blok", "hard bloquear", "block distractions", "blok everything", "bloquear everything", "bloquea distracciones", "bloquear distractions", "bloquear distracciones"])) return "focus";
  if (contains(text, ["porn", "porno", "adult", "xxx"])) return "adultContent";
  if (contains(text, ["losing control", "perdiendo el control", "urge", "emergency", "reca", "relapse", "broke the block", "break the block", "can't stop", "no puedo parar", "terrible today", "fatal hoy", "no consigo concentrarme"])) return "emergency";
  if (contains(text, ["sleep", "night", "bed", "dormir", "duermo", "acuesto", "noche", "scrolleando hasta", "scrolling until", "tired", "cansado"])) return "sleep";
  if (contains(text, ["exam", "study", "estudio", "estudiar", "examen", "opos"])) return "study";
  if (contains(text, ["allow only", "whatsapp", "maps", "solo", "only"])) return "allowOnly";
  if (contains(text, ["vacation", "holiday", "vacaciones", "pause", "pausa", "resume my rules", "resume rules"])) return "vacation";
  if (contains(text, ["week", "semana", "analy", "diagn", "report", "review"])) return "weeklyReview";
  if (contains(text, ["social media", "social apps", "social networks", "redes sociales", "tiktok", "tik tok", "instagram", "insta", " ig ", "youtube", " yt ", "reddit", "twitter", " x ", "facebook", "snapchat", "gaming", "game", "dopamine", "scroll", "doomscroll", "notification", "notifications", "reels", "shorts", "feed", "for you page"])) return "social";
  if (requestedUnknownApp(prompt)) return "social";
  if (contains(text, ["anxious", "anxiety", "ansiedad", "bored", "boring", "aburr", "lonely", "stress", "guilt", "culpa"])) return "social";
  if (contains(text, ["focus", "productiv", "foco", "deep work", "now"])) return "focus";
  if (contains(text, ["work", "trabaj"]) && contains(text, ["focus", "block", "bloquea", "bloquear", "protect", "proteger"])) return "focus";
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
  const crossesMidnight = looksNightly && !match[3] && !match[6] && endHour <= startHour;
  const endMeridiem = match[6] || (crossesMidnight ? "am" : (looksNightly ? "pm" : null));
  const startMeridiem = match[3] || (looksNightly ? "pm" : endMeridiem);
  const start = minuteOfDay(startHour, Number(match[2] || 0), startMeridiem);
  const end = minuteOfDay(endHour, Number(match[5] || 0), endMeridiem);
  if (start == null || end == null || start === end) return null;
  return { start, end };
}

function anchorWindow(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  if (contains(text, ["sleep", "bed", "bedtime", "dormir", "duermo", "acuesto"])) return null;
  const minute = routineAnchorMinute(prompt);
  if (minute == null) return null;
  const offset = contains(text, ["after", "despues", "después", "termine", "termino", "finish"]) ? 10 : 0;
  const start = (minute + offset) % (24 * 60);
  const duration = contains(text, ["lunch", "comer", "dinner", "cenar", "work", "trabaj"]) ? 60 : 45;
  return { start, end: (start + duration) % (24 * 60) };
}

function explicitSingleTime(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  if (scrollUntilSleepTime(prompt)) return null;
  if (contains(text, ["sleep", "bed", "dormir", "duermo", "acuesto", "bedtime"]) && /\bmidnight\b/i.test(text)) return 0;
  const match = text.match(/(?:sleep|bed|dormir|duermo|acuesto|bedtime)[^\d]*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?/i);
  if (!match) return null;
  const rawHour = Number(match[1]);
  const meridiem = match[3] || (rawHour >= 6 && rawHour <= 11 ? "pm" : rawHour === 12 ? "am" : null);
  return minuteOfDay(rawHour, Number(match[2] || 0), meridiem);
}

function scrollUntilSleepTime(prompt) {
  const text = cleanText(prompt, 600).toLowerCase();
  return contains(text, ["scroll", "doomscroll", "reels", "shorts", "feed"]) &&
    contains(text, ["bed", "night", "noche"]) &&
    /\buntil\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)?\b/i.test(text);
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
  const language = responseLanguage(prompt, context);
  const promptText = cleanText(prompt, 600).toLowerCase();
  const selected = context.has_selected_apps === true;
  const authorized = context.screen_time_authorized === true;
  const duration = cleanNumber(context.recommended_duration_minutes, 30, 5, 240);
  const riskWindow = cleanText(context.risk_window, 60) || "your next risk window";
  const cluster = behaviorCluster(prompt);
  const timeWindow = explicitTimeWindow(prompt) || anchorWindow(prompt);
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

  if (asksAboutAssistantCapabilities(prompt)) {
    return {
      intent: "general",
      title: "Personal Assistant",
      response_text: "I can read your phone-habit patterns, explain what is changing, and turn that into blocks, schedules, limits, reports or setup steps when it helps.",
      bullets: [
        "Read: I can respond when you ask and also use signals when your pattern changes.",
        "Pattern: the useful move depends on your apps, weak hours, plan history and permissions.",
        "Move: tell me the moment you want to improve, or ask me to review your current pattern."
      ],
      primary_label: "Tell pattern",
      secondary_label: "Open report",
      actions: [],
      requires_selected_apps: false,
      requires_screen_time_authorization: false,
    };
  }

  if (asksForBroadAutomation(prompt)) {
    return {
      intent: "general",
      title: "Automation Setup",
      response_text: "I can help automate protection, but first I need the pattern to optimize: app, weak moment, goal or risk window.",
      bullets: [
        "Read: you want BAi to act with more initiative.",
        "Pattern: automatic changes need a clear rule and a safe exit.",
        "Move: tell me what to protect first, then I can recommend the right automation."
      ],
      primary_label: "Tell pattern",
      secondary_label: "Open report",
      actions: [],
      requires_selected_apps: false,
      requires_screen_time_authorization: false,
    };
  }

  if (asksForUnsupportedReminder(prompt)) {
    return {
      intent: "general",
      title: "Reminder Context",
      response_text: "I can help prevent that moment, but this action should become either a notification setup or a block window. What time should I protect?",
      bullets: [
        "Read: you want proactive help before the scroll starts.",
        "Pattern: the useful solution needs a clear time or risk window.",
        "Move: tell me the time, then I can suggest the right protection."
      ],
      primary_label: "Tell time",
      secondary_label: "Not now",
      actions: [],
      requires_selected_apps: false,
      requires_screen_time_authorization: false,
    };
  }

  if (appCorrection(prompt)) {
    return {
      intent: "general",
      title: "Context Corrected",
      response_text: "Got it. I will not use that app as context. Which app, moment or habit should we focus on instead?",
      bullets: [
        "Read: the previous app context was wrong.",
        "Pattern: a useful plan needs your real trigger, not a guessed app.",
        "Move: tell me the app, moment or habit you actually want to improve."
      ],
      primary_label: "Tell pattern",
      secondary_label: "Not now",
      actions: [],
      requires_selected_apps: false,
      requires_screen_time_authorization: false,
    };
  }

  if (asksForPermanentLockout(prompt)) {
    return {
      intent: "general",
      title: "Bounded Protection",
      response_text: "I can help make access harder, but I will only create bounded rules with a clear target and exit path. Tell me the app or moment to protect first.",
      bullets: [
        "Read: you want a very strong boundary.",
        "Pattern: absolute blocks need a clear target and an exit rule.",
        "Move: tell me the app or moment, then I can create a bounded protection plan."
      ],
      primary_label: "Tell target",
      secondary_label: "Not now",
      actions: [],
      requires_selected_apps: false,
      requires_screen_time_authorization: false,
    };
  }

  if (missingContext === "bedtime") {
    if (language === "es") {
      return {
        intent: "sleep",
        title: "Lectura de noche",
        response_text: "Esto suena a bucle de scroll de noche. Antes de bloquear nada, necesito tu hora objetivo para dormir.",
        bullets: [
          "Lectura: quieres que las noches se sientan menos automáticas.",
          "Patrón: la franja de riesgo depende de cuándo quieres dormir realmente.",
          "Movimiento: dime tu hora habitual de dormir y podré sugerir el límite adecuado."
        ],
        primary_label: "Decir hora",
        secondary_label: "Ahora no",
        actions: [],
        requires_selected_apps: false,
        requires_screen_time_authorization: false,
      };
    }
    return {
      intent: "sleep",
      title: "Bedtime Scroll Read",
      response_text: asksForAdvice(prompt)
        ? "The useful move is to make scrolling harder before your usual sleep target, not when you are already in bed. What time do you normally want to be asleep?"
        : "This sounds like a bedtime scroll loop. Before I block anything, I need your sleep target.",
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

  const moment = relativeMoment(prompt);
  if (missingContext && moment && missingContext === moment.key) {
    return {
      intent: "social",
      title: "Contextual Boundary",
      response_text: moment.question,
      bullets: [
        `Read: you want protection ${moment.label}.`,
        "Pattern: the useful boundary should match your real routine, not a generic clock time.",
        `Move: ${moment.move}`
      ],
      primary_label: "Tell time",
      secondary_label: "Not now",
      actions: [],
      requires_selected_apps: false,
      requires_screen_time_authorization: false,
    };
  }

  if ((intent === "social" || intent === "study" || intent === "focus") && hasWorkAppConflict(prompt)) {
    const app = namedApp(prompt);
    if (language === "es") {
      return {
        intent: "social",
        title: "Conflicto con app de trabajo",
        response_text: `Dime cuándo ${app} deja de ser uso de trabajo y puedo preparar ese límite.`,
        bullets: [
          "Lectura: la misma app tiene contextos útiles y contextos de riesgo.",
          "Patrón: un bloqueo completo podría romper tu trabajo en vez de mejorar el control.",
          `Movimiento: dime la franja de uso no laboral de ${app} y podré ajustar el límite.`
        ],
        primary_label: "Decir franja",
        secondary_label: "Ahora no",
        actions: [],
        requires_selected_apps: false,
        requires_screen_time_authorization: false,
      };
    }
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

  if (intent === "social" &&
      promptApp === "the app" &&
      !appCategory &&
      !timeWindow &&
      !["broke", "held"].includes(lastOutcome) &&
      contains(promptText, ["scroll", "doomscroll", "scrolling", "checking my phone", "check my phone"])) {
    return {
      intent: "social",
      title: "Scroll Context",
      response_text: "I can help, but I need the real loop before creating a block. Which app or moment does the scrolling usually start with?",
      bullets: [
        "Read: you want to stop scrolling, but the target is still broad.",
        "Pattern: useful protection needs the app, trigger or time window.",
        "Move: tell me the app or moment, then I can set the right boundary."
      ],
      primary_label: "Tell pattern",
      secondary_label: "Not now",
      actions: [],
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

  if (intent === "general" && memoryApp && weakHours.length > 0 && contains(promptText, ["again", "evening", "worse", "same"])) {
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

  if (intent === "focus" && promptHasFutureTiming(prompt) && !timeWindow) {
    return {
      ...base,
      title: "Plan Timing",
      response_text: "I can plan this, but I need the time window before I start anything now.",
      bullets: [
        "Read: this is about future focus, not an immediate block.",
        "Pattern: scheduled protection works better when the start time is clear.",
        "Move: tell me the time window, then I can set the plan."
      ],
      primary_label: "Tell time",
      actions: [],
      requires_selected_apps: false,
      requires_screen_time_authorization: false,
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

  if (intent === "general" && (asksForAdvice(prompt) || asksForPlan(prompt) || asksWhereToStart(prompt)) && !hasExplicitBlockRequest(prompt)) {
    if (asksForPlan(prompt)) {
      return {
        ...base,
        title: "Plan Context",
        response_text: "I can build a plan, but first I need the real loop. Which app, moment or habit should we focus on?",
        bullets: [
          "Read: you want a plan, but the target is still too broad.",
          "Pattern: useful protection starts from one repeated trigger.",
          "Move: tell me the app, moment or habit that takes over most often."
        ],
        primary_label: "Tell pattern",
        actions: [],
        requires_selected_apps: false,
        requires_screen_time_authorization: false,
      };
    }
    return {
      ...base,
      title: "Digital Wellness Read",
      response_text: "Start by identifying the moment when the phone becomes automatic. Then make that moment slightly harder before adding strict blocks.",
      bullets: [
        "Read: you are asking for guidance, not a blocking plan yet.",
        "Pattern: the trigger usually matters more than total screen time.",
        "Move: name the app and the moment it usually takes over."
      ],
      primary_label: "Tell pattern",
      actions: [],
      requires_selected_apps: false,
      requires_screen_time_authorization: false,
    };
  }

  if (intent === "general" && !asksForAdvice(prompt)) {
    return {
      ...base,
      title: "Noted",
      response_text: "I can help with screen-habit advice, a diagnosis or a protection plan if you want to go further.",
      bullets: [
        "Read: there is no clear action request yet.",
        "Pattern: Blanked should not turn every message into a blocking plan.",
        "Move: tell me whether you want advice or a plan."
      ],
      primary_label: "Tell goal",
      actions: [],
      requires_selected_apps: false,
      requires_screen_time_authorization: false,
    };
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

function appCapabilities(context = {}) {
  return {
    actions: [
      "start_protection",
      "apply_schedule",
      "set_daily_limit",
      "enable_allow_only",
      "enable_adult_filter",
      "pause_rules",
      "disable_pause",
      "switch_mode",
      "open_app_picker",
      "request_screen_time_permission",
      "apply_ai_plan",
    ],
    channels: ["app", "whatsapp", "sms", "push"],
    can_start_now: context.is_blank_active !== true,
    has_selected_apps: context.has_selected_apps === true,
    screen_time_authorized: context.screen_time_authorized === true,
    available_modes: availableModeNames(context),
    limits: {
      max_start_minutes: 240,
      max_schedule_days: 14,
      max_pause_hours: 168,
      proactive_max_per_day: 1,
    },
  };
}

function actionNeedsScreenTime(actionType) {
  return ["start_protection", "apply_schedule", "set_daily_limit", "enable_allow_only", "enable_adult_filter", "switch_mode", "apply_ai_plan"].includes(actionType);
}

function actionNeedsSelection(actionType) {
  return ["start_protection", "apply_schedule", "set_daily_limit", "apply_ai_plan"].includes(actionType);
}

function deterministicNoActionTitle(title) {
  return new Set([
    "Bounded Protection",
    "Bedtime Scroll Read",
    "Lectura de noche",
    "Contextual Boundary",
    "Work App Conflict",
    "Conflicto con app de trabajo",
    "Scroll Pattern",
    "Scroll Context",
    "Context Corrected",
    "App Privacy",
    "Digital Wellness Read",
    "Plan Context",
    "Plan Timing",
    "Personal Assistant",
    "Automation Setup",
    "Reminder Context",
    "Noted",
    "Loss Of Control",
  ]).has(title);
}

function deterministicActionTitle(title) {
  return new Set([
    "Bedtime Boundary",
    "Scheduled Protection",
    "Sleep Protection",
    "Remembered Scroll Pattern",
    "Choose App",
    "Choose Apps",
    "Scroll Loop",
    "24h Study Protection",
    "Loss Of Control",
    "Urge Protection",
    "Allow Only",
    "Focus Protection",
    "Strict Focus Protection",
    "Pause Rules",
    "Resume Rules",
    "Weekly Read",
  ]).has(title);
}

function actionGate(plan, fallback, context = {}, prompt = "") {
  const proposed = Array.isArray(plan.actions) ? plan.actions.slice(0, 4).map(normalizeAction).filter(Boolean) : [];
  const hasClearFutureWindow = Boolean(explicitTimeWindow(prompt) || anchorWindow(prompt));
  const fallbackActions = Array.isArray(fallback.actions) ? fallback.actions.filter((item) => item && item.type !== "none").map(normalizeAction).filter(Boolean) : [];
  const selected = context.has_selected_apps === true;
  const authorized = context.screen_time_authorized === true;
  if (fallbackActions.length === 0 && deterministicNoActionTitle(fallback.title)) return [];
  const fallbackNeedsSetup = fallbackActions.some((item) => (actionNeedsSelection(item.type) && !selected) || (actionNeedsScreenTime(item.type) && !authorized));
  if (fallbackActions.some((item) => item.type === "switch_mode") && !fallbackNeedsSetup) return fallbackActions.slice(0, 4);
  if (fallbackActions.length > 0 && deterministicActionTitle(fallback.title) && !fallbackNeedsSetup) return fallbackActions.slice(0, 4);
  if (hasClearFutureWindow && fallbackActions.some((item) => item.type === "apply_schedule")) return fallbackActions.slice(0, 4);
  if (asksForPermanentLockout(prompt) || asksAboutAssistantCapabilities(prompt) || asksForUnsupportedReminder(prompt) || asksForBroadAutomation(prompt)) return [];
  if (promptHasFutureTiming(prompt) && !hasClearFutureWindow && !contains(cleanText(prompt, 600).toLowerCase(), ["now", "ahora"])) return [];
  if (context.is_blank_active === true && proposed.some((item) => item.type === "start_protection")) return [];

  const setupActions = [];
  const gated = [];

  for (const item of proposed) {
    if (!item || item.type === "none") continue;
    if (actionNeedsSelection(item.type) && !selected) {
      setupActions.push(action("open_app_picker"));
      continue;
    }
    if (actionNeedsScreenTime(item.type) && !authorized) {
      setupActions.push(action("request_screen_time_permission"));
      continue;
    }
    if (item.type === "apply_schedule" && (item.start_minute == null || item.end_minute == null || item.start_minute === item.end_minute)) continue;
    if (item.type === "switch_mode" && item.name && !availableModeNames(context).some((mode) => mode.toLowerCase() === item.name.toLowerCase())) continue;
    if (item.type === "start_protection" && promptHasFutureTiming(prompt) && !contains(cleanText(prompt, 600).toLowerCase(), ["now", "ahora"])) continue;
    gated.push(item);
  }

  const uniqueSetup = setupActions.filter((item, index, items) => items.findIndex((candidate) => candidate.type === item.type) === index);
  if (uniqueSetup.length > 0) return uniqueSetup.slice(0, 2);

  if (gated.length > 0) return gated;

  if (fallbackActions.length > 0 && !promptHasFutureTiming(prompt)) return fallbackActions.slice(0, 4).map(normalizeAction).filter(Boolean);
  return [];
}

function normalizePlan(parsed, fallback, context = {}, prompt = "", language = "en") {
  const source = parsed && typeof parsed === "object" ? parsed : {};
  const plan = source.plan && typeof source.plan === "object" ? source.plan : source;
  const validIntents = new Set(["sleep", "focus", "study", "emergency", "allowOnly", "vacation", "weeklyReview", "adultContent", "social", "general"]);
  const planIntent = validIntents.has(plan.intent) ? plan.intent : fallback.intent;
  const bullets = Array.isArray(plan.bullets) ? plan.bullets.map((item) => userFacingText(item, 140)).filter(Boolean).slice(0, 4) : [];
  const interpretation = userFacingText(source.interpretation, 160);
  const behavior = userFacingText(source.behavior_pattern, 160);
  const nextMove = userFacingText(source.next_move, 160);
  const fallbackBullets = fallback.bullets;
  const actions = actionGate(plan, fallback, context, prompt);
  const hasExecutableActions = actions.some((item) => item && item.type !== "none");
  const modelProposedAction = Array.isArray(plan.actions) && plan.actions.some((item) => item && item.type && item.type !== "none");
  const shouldUseFallbackPresentation =
    deterministicNoActionTitle(fallback.title) ||
    deterministicActionTitle(fallback.title) ||
    (hasExecutableActions && actions.some((item) => item.type === "apply_schedule") && Boolean(explicitTimeWindow(prompt) || anchorWindow(prompt))) ||
    (!hasExecutableActions &&
      modelProposedAction &&
      (asksAboutAssistantCapabilities(prompt) ||
        asksForUnsupportedReminder(prompt) ||
        asksForBroadAutomation(prompt) ||
        asksForPermanentLockout(prompt) ||
        (promptHasFutureTiming(prompt) && !explicitTimeWindow(prompt) && !anchorWindow(prompt))));
  const shouldUseLanguageFallback = language === "es" && hasSpanishLanguageLeak(plan);
  const visibleBullets = hasExecutableActions ? bullets : bullets.filter((item) => !/^protection:/i.test(item));
  const structuredBullets = visibleBullets.filter((item) => /^(Read|Pattern|Move|Signal|Feedback|Protection|Lectura|Patrón|Movimiento|Señal|Protección):/i.test(item)).length >= 2;
  const preserveFallbackText = contains(fallback.response_text, [
    "already protected",
    "Got it. I will not use that app as context",
    "I can help make access harder, but I will only create",
    "I can use counts and context you choose to share",
  ]);
  const title = shouldUseFallbackPresentation || shouldUseLanguageFallback ? fallback.title : userFacingText(plan.title, 70) || fallback.title;
  const responseText = shouldUseFallbackPresentation || shouldUseLanguageFallback || preserveFallbackText ? fallback.response_text : userFacingText(plan.response_text, 180) || interpretation || fallback.response_text;
  const normalizedPlan = {
    intent: shouldUseFallbackPresentation || shouldUseLanguageFallback ? fallback.intent : planIntent,
    title,
    response_text: responseText,
    bullets: shouldUseFallbackPresentation || shouldUseLanguageFallback ? fallbackBullets : visibleBullets.length >= 2 && structuredBullets ? visibleBullets : fallbackBullets,
    primary_label: shouldUseFallbackPresentation || shouldUseLanguageFallback ? fallback.primary_label : cleanText(plan.primary_label, 32) || fallback.primary_label,
    secondary_label: shouldUseFallbackPresentation || shouldUseLanguageFallback ? fallback.secondary_label : cleanText(plan.secondary_label, 32) || fallback.secondary_label,
    actions,
    requires_selected_apps: hasExecutableActions ? fallback.requires_selected_apps : false,
    requires_screen_time_authorization: hasExecutableActions ? fallback.requires_screen_time_authorization : false,
  };
  return {
    ...normalizedPlan,
    message_text: conversationalMessage(normalizedPlan, language),
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

async function modelPlan(prompt, context, fallback, language) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) return { plan: normalizePlan({ plan: fallback }, fallback, context, prompt, language), source: "deterministic_fallback" };
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
            "You are BAI, Blanked's personal assistant for healthier screen habits. Act as one assistant with two internal modes: reactive when the person messages you, proactive when product signals say something important changed. Lead with useful interpretation and context, not with rigid templates. Use the person's context, memory, recent plan outcomes, risk windows, app setup, Health aggregates if present, and app capabilities. You may answer, ask for one missing detail, recommend an app action, or propose no action. Recommend actions when they are useful and executable: start_protection for immediate blocks, apply_schedule for blocking/protection time windows, set_daily_limit for caps, enable_allow_only for essentials-only, enable_adult_filter for adult web protection, pause_rules/disable_pause, switch_mode only for existing modes, open_app_picker/request_screen_time_permission for setup, apply_ai_plan for adaptive plan/report. Do not use apply_schedule as a reminder or notification. Never say you already set, created, scheduled, blocked, or changed something; say you can do it or propose it, because the app executes after confirmation. For proactive mode, explain why you are interrupting and propose one concrete solution; avoid generic motivation. Do not force blocks for vague inputs, but do not be passive when a sensible next step exists. For emotional inputs, respond like a practical assistant: acknowledge the state and offer a small concrete move inside Blanked when relevant. Stay inside digital wellness, phone behavior, focus, sleep, attention, urges, relapse prevention, and app blocking. Do not claim therapy, treatment, medical diagnosis, device surveillance, exact app visibility, or impossible permanent blocking. Do not use the word coach. Respond in response_language: English for en, Spanish for es. Keep JSON keys, intent values and action types in English. Write directly to the person; never say user, the user, ask user, or mention internal implementation/QA/model/source/debug details. Keep response_text to 1-2 concrete sentences. Bullets should use Read/Pattern/Move/Protection in English, or Lectura/Patrón/Movimiento/Protección in Spanish. Every action object must include all nullable action fields.",
        },
        {
          role: "user",
          content: JSON.stringify({
            prompt: cleanText(prompt, 600),
            context,
            response_language: language,
            trigger: cleanText(context.trigger || context.mode || "reactive", 40),
            app_capabilities: appCapabilities(context),
            memory_rules: [
              "Use context.memory.main_apps, bedtime_minute, weak_hours, pattern_cluster, and last_plan_outcome when present.",
              "If last_plan_outcome is broke, reduce intensity or move protection earlier instead of making the plan stricter.",
              "If last_plan_outcome is held, repeat the stable plan before increasing difficulty.",
              "For broad questions, use memory as background but do not invent exact app details."
            ],
            examples: [
              { user: "What can you do for me?", answer: "Read: I can help you understand phone patterns and turn them into blocks, schedules, limits, reports or habits. Move: tell me the moment you most want help with, or ask me to review your current pattern." },
              { user: "I feel terrible today", answer: "Read: this is a low-control moment, not a time for a complex plan. Move: start a short protection block or choose one tiny offline reset." },
              { user: "I feel bad because I lose 3 hours on TikTok after work.", answer: "Read: decompression loop after work. Pattern: TikTok is being used to exit stress, then it becomes the evening. Move: protect the first 45 minutes after work and choose one offline decompression action." },
              { user: "How can I not scroll at nights?", answer: "Read: bedtime scrolling is the habit to understand. Pattern: the right boundary depends on the user's sleep target. Move: ask what time they usually want to be asleep before creating any block." },
              { user: "Block Instagram from 10 to 7.", answer: "Read: explicit schedule request. Pattern: bedtime risk window is clear. Move: apply a nightly shield from 10 PM to 7 AM." },
              { user: "I keep checking WhatsApp while working.", answer: "Read: compulsive checking loop. Pattern: the interruption is frequent and short, so app limits alone may be weak. Move: use Allow Only or a timed focus block." },
              { user: "proactive signal: social use is 42% above baseline after lunch", answer: "Read: I am interrupting because today's social use is above your usual pattern after lunch. Move: apply a short lunch boundary for the next 7 days." },
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
  return { plan: normalizePlan(parsed, fallback, context, prompt, language), source: `openai:${model}` };
}

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;
  try {
    const body = parseJsonBody(event);
    const prompt = cleanText(body.prompt, 600);
    if (!prompt) return json(400, { error: "missing_prompt" });
    const context = body.context && typeof body.context === "object" ? body.context : {};
    const language = responseLanguage(prompt, context);
    const fallback = fallbackPlan(prompt, context);
    let result;
    try {
      result = await modelPlan(prompt, context, fallback, language);
    } catch (error) {
      result = { plan: fallback, source: "deterministic_fallback_after_model_error", error: error.message };
    }
    result.plan = localizePlan(result.plan, language);
    return json(200, { ok: true, plan: result.plan, source: result.source, model_error: result.error || null });
  } catch (error) {
    return json(500, { error: "blanked_agent_failed", detail: error.message });
  }
};
