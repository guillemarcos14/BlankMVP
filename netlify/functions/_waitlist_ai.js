const { cleanText } = require("./_identity");

const FACT_KEYS = [
  "preferred_name",
  "email",
  "age",
  "occupation",
  "work_context",
  "daily_routine",
  "scroll_moments",
  "scroll_contexts",
  "apps",
  "content_types",
  "triggers",
  "frequency_duration",
  "impact",
  "feelings",
  "attempted_solutions",
  "desired_change",
  "goals",
  "motivation",
  "device_platform",
  "communication_preference",
  "other_personal_context",
];

const MULTI_VALUE_KEYS = new Set([
  "scroll_moments",
  "scroll_contexts",
  "apps",
  "content_types",
  "triggers",
  "feelings",
  "attempted_solutions",
  "goals",
]);

const EVENTUAL_GOALS = [
  "preferred_name",
  "email",
  "age_band",
  "occupation",
  "scroll_moments",
  "scroll_contexts",
  "apps",
  "impact",
  "desired_change",
];

const RESTRICTED_TOPIC_PATTERNS = [
  /\b(abortion|anti[- ]?abortion|pro[- ]?life|pro[- ]?choice)\b/i,
  /\b(war|warfare|armed conflict|invasion|genocide|ceasefire)\b/i,
  /\b(election|political party|left[- ]?wing|right[- ]?wing|democrat|republican|conservative|socialist|communist)\b/i,
  /\b(guerra|aborto|elecciones?|partido pol[ií]tico|izquierda|derecha|conflicto armado)\b/i,
  /\b(religious superiority|religious conflict|holy war)\b/i,
];

const SENSITIVE_INFERENCE_PATTERNS = [
  /\b(diagnos|disorder|addict|adhd|depress|anxi|therapy|medication)\b/i,
  /\b(religion|muslim|christian|jewish|hindu|atheist)\b/i,
  /\b(politic|political|party preference|voting preference)\b/i,
  /\b(gay|lesbian|bisexual|transgender|sexual orientation)\b/i,
  /\b(race|ethnicity|racial|ethnic)\b/i,
  /\b(income|salary|bank|debt|credit card)\b/i,
];

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/i;

const EXTRACTION_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["facts"],
  properties: {
    facts: {
      type: "array",
      maxItems: 16,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["key", "value_text", "value_items", "evidence", "confidence", "explicit", "operation"],
        properties: {
          key: { type: "string", enum: FACT_KEYS },
          value_text: { type: "string", maxLength: 500 },
          value_items: { type: "array", maxItems: 12, items: { type: "string", maxLength: 120 } },
          evidence: { type: "string", maxLength: 280 },
          confidence: { type: "string", enum: ["high", "medium", "low"] },
          explicit: { type: "boolean" },
          operation: { type: "string", enum: ["set", "add", "correct", "remove"] },
        },
      },
    },
  },
};

const REPLY_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["reply", "focus", "profile_useful"],
  properties: {
    reply: { type: "string", minLength: 1, maxLength: 700 },
    focus: {
      type: "string",
      enum: [
        "story",
        "work_and_daily_life",
        "scroll_context",
        "apps_and_content",
        "impact",
        "desired_change",
        "identity",
        "contact",
        "natural_followup",
        "safe_redirect",
        "complete",
      ],
    },
    profile_useful: { type: "boolean" },
  },
};

function responseOutputText(payload) {
  if (typeof payload?.output_text === "string") return payload.output_text;
  for (const item of Array.isArray(payload?.output) ? payload.output : []) {
    for (const content of Array.isArray(item?.content) ? item.content : []) {
      if (typeof content?.text === "string") return content.text;
    }
  }
  return "";
}

async function structuredResponse({ model, schemaName, schema, system, input, fetchImpl = fetch }) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) throw new Error("OPENAI_API_KEY is not configured");
  const response = await fetchImpl("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      authorization: `Bearer ${apiKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model,
      input: [
        { role: "system", content: [{ type: "input_text", text: system }] },
        { role: "user", content: [{ type: "input_text", text: input }] },
      ],
      text: { format: { type: "json_schema", name: schemaName, strict: true, schema } },
    }),
  });
  const raw = await response.text();
  let payload = {};
  try { payload = raw ? JSON.parse(raw) : {}; } catch (_) { payload = {}; }
  if (!response.ok) {
    throw new Error(`waitlist_openai_${response.status}:${cleanText(payload.error?.message || raw, 200)}`);
  }
  const output = responseOutputText(payload);
  if (!output) throw new Error("waitlist_openai_empty_output");
  return JSON.parse(output);
}

function normalizedComparable(value) {
  return cleanText(value, 1000).toLowerCase().replace(/[’‘]/g, "'").replace(/\s+/g, " ");
}

function hasEvidence(message, evidence) {
  const source = normalizedComparable(message);
  const excerpt = normalizedComparable(evidence);
  return Boolean(excerpt && source.includes(excerpt));
}

function ageBand(value) {
  const age = Number(String(value || "").match(/\b(\d{1,3})\b/)?.[1]);
  if (!Number.isFinite(age) || age < 13 || age > 120) return "";
  if (age < 18) return "under_18";
  if (age <= 24) return "18_24";
  if (age <= 34) return "25_34";
  if (age <= 44) return "35_44";
  if (age <= 54) return "45_54";
  if (age <= 64) return "55_64";
  return "65_plus";
}

function normalizedName(value) {
  const name = cleanText(value, 80).replace(/[^\p{L}\p{M}' -]/gu, "").replace(/\s+/g, " ").trim();
  if (!name || name.split(" ").length > 5 || name.length < 2) return "";
  return name;
}

function uniqueValues(values) {
  const seen = new Set();
  return values.map((item) => cleanText(item, 120)).filter((item) => {
    const key = item.toLowerCase();
    if (!key || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function containsSensitiveInference(text) {
  return SENSITIVE_INFERENCE_PATTERNS.some((pattern) => pattern.test(text));
}

function validateExtractedFacts(message, extracted) {
  const facts = [];
  for (const candidate of Array.isArray(extracted?.facts) ? extracted.facts : []) {
    if (!FACT_KEYS.includes(candidate?.key) || candidate.explicit !== true) continue;
    const evidence = cleanText(candidate.evidence, 280);
    const evidenceExact = hasEvidence(message, evidence);
    if (!evidenceExact && candidate.confidence !== "low") continue;

    const operation = ["set", "add", "correct", "remove"].includes(candidate.operation)
      ? candidate.operation
      : "set";
    let key = candidate.key;
    let value = MULTI_VALUE_KEYS.has(key)
      ? uniqueValues(candidate.value_items || [])
      : cleanText(candidate.value_text, 500);
    if (MULTI_VALUE_KEYS.has(key) && !value.length && candidate.value_text) {
      value = uniqueValues(String(candidate.value_text).split(/,|\band\b/i));
    }

    if (key === "email") {
      const email = cleanText(candidate.value_text, 254).toLowerCase();
      if (!EMAIL_PATTERN.test(email)) continue;
      value = email;
    }
    if (key === "preferred_name") {
      value = normalizedName(candidate.value_text);
      if (!value) continue;
    }
    if (key === "age") {
      value = ageBand(candidate.value_text || evidence);
      if (!value) continue;
      key = "age_band";
    }
    const candidateContent = `${candidate.value_text || ""} ${(candidate.value_items || []).join(" ")} ${evidence}`;
    if (key === "other_personal_context" && (containsSensitiveInference(candidateContent) || isRestrictedTopic(candidateContent))) {
      continue;
    }
    if ((Array.isArray(value) && !value.length) || (!Array.isArray(value) && !value)) continue;

    const confidence = candidate.confidence === "high" ? 0.95 : candidate.confidence === "medium" ? 0.72 : 0.4;
    facts.push({
      key,
      value,
      normalizedText: Array.isArray(value) ? value.join(", ") : String(value),
      evidence,
      confidence,
      status: confidence >= 0.7 && evidenceExact ? "confirmed" : "uncertain",
      operation,
    });
  }
  return facts;
}

function deterministicFacts(message) {
  const facts = [];
  const email = String(message || "").match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i)?.[0];
  if (email) {
    facts.push({
      key: "email",
      value: email.toLowerCase(),
      normalizedText: email.toLowerCase(),
      evidence: email,
      confidence: 1,
      status: "confirmed",
      operation: "set",
    });
  }
  return facts;
}

async function extractFacts({ message, history, profile, fetchImpl = fetch }) {
  const deterministic = deterministicFacts(message);
  const system = [
    "Extract only personal facts the person explicitly states in the latest message.",
    "Return verbatim evidence copied from that message. Never infer, diagnose, or invent.",
    "Use occupation and work_context broadly when the person explains what they do or how their day works.",
    "Do not extract political opinions, views on wars, abortion, elections, religion, race, sexuality, medical diagnoses, legal matters, financial details, passwords, addresses, or other sensitive categories.",
    "Age may be extracted only when explicitly stated. Email and preferred name must be exact.",
    "Use correct when the person explicitly replaces an earlier fact, add for additional list items, remove when they withdraw a fact, and set otherwise.",
    "Do not turn interpretation into fact. An emotional impact is valid only if the person says it.",
  ].join(" ");
  const input = JSON.stringify({ latest_message: message, recent_history: history.slice(-10), known_profile: profile });
  const model = process.env.WAITLIST_EXTRACTION_MODEL || "gpt-5.6-luna";
  try {
    const extracted = await structuredResponse({
      model,
      schemaName: "waitlist_fact_extraction",
      schema: EXTRACTION_SCHEMA,
      system,
      input,
      fetchImpl,
    });
    const validated = validateExtractedFacts(message, extracted);
    const byKey = new Map(deterministic.map((fact) => [fact.key, fact]));
    for (const fact of validated) if (!byKey.has(fact.key)) byKey.set(fact.key, fact);
    return Array.from(byKey.values());
  } catch (error) {
    if (deterministic.length) return deterministic;
    throw error;
  }
}

function isRestrictedTopic(message) {
  return RESTRICTED_TOPIC_PATTERNS.some((pattern) => pattern.test(String(message || "")));
}

function coverage(profile) {
  return Object.fromEntries(EVENTUAL_GOALS.map((key) => [key, profile[key] !== undefined && profile[key] !== null]));
}

function safeReply(reply) {
  const text = cleanText(reply, 700)
    .replace(/```[\s\S]*?```/g, "")
    .replace(/^[-*#]+\s*/gm, "")
    .replace(/[*_`#]/g, "")
    .replace(/https?:\/\/\S+/gi, "")
    .replace(/[—–]/g, ",")
    .replace(/\s+/g, " ")
    .trim();
  if (!text) throw new Error("waitlist_reply_empty");
  return text;
}

function replyQualityIssues(reply) {
  const issues = [];
  const firstSentence = String(reply || "").split(/[.!?]/)[0] || "";
  const sentenceCount = String(reply || "")
    .split(/[.!?]+/)
    .map((sentence) => sentence.trim())
    .filter(Boolean).length;
  const wordCount = String(reply || "").split(/\s+/).filter(Boolean).length;
  if (!/\bI\b|\bI['’](?:m|d|ve|ll)\b|\bI can\b|\bI get\b|\bI want\b/i.test(firstSentence)) {
    issues.push("first_sentence_not_first_person");
  }
  if ((String(reply || "").match(/\?/g) || []).length > 1) issues.push("more_than_one_question");
  if (sentenceCount > 2) issues.push("too_many_sentences");
  if (wordCount > 35 || String(reply || "").length > 220) issues.push("too_long");
  if (/\b(pattern|assessment|intake|prescribe|just yet|should stop|handoff point|underlying)\b|stay with your experience|what do you notice|what is it like for you|tell me how that lands|jump into advice|help understand|what happens for you|more interested in|what would you want(?: it| this| things)? to be different/i.test(reply)) {
    issues.push("clinical_or_scripted_language");
  }
  if (/https?:\/\/|[*#`]|[;—–]/i.test(reply)) issues.push("formatting_or_link");
  return issues;
}

async function generateReply({ message, history, profile, newlySavedFacts, fetchImpl = fetch }) {
  const restricted = isRestrictedTopic(message);
  const knownCoverage = coverage(profile);
  const system = [
    "You are Blankmind speaking in first person as a thoughtful personal assistant during Early Access.",
    "Your only purpose is to get to know this person through a genuinely natural conversation before product access.",
    "Naturalness is the highest priority. Respond to what they actually said before asking anything. Sound warm, attentive, curious, and grounded. Never sound like a form, survey, funnel, support bot, interview script, or data collector.",
    "The first sentence of every reply must contain a natural first-person phrase. Vary it freely and do not rely on scripted I get that or I can see openings. It can be as simple as an honest I'm curious followed by the question.",
    "Reflect only details and feelings the person explicitly expressed. Never add a likely motive, emotion, energy level, benefit, or consequence just to sound insightful.",
    "Do not recap or paraphrase the person's whole message. Use no more than one contextual detail in the acknowledgment or question. Specific does not mean repeating facts back to them.",
    "You may explore a wide personal context when it fits naturally, including their work, studies, routines, environment, interests, responsibilities, energy, relationships with their phone, apps, scrolling moments, impact, and what they would like to change.",
    "There is no fixed order. Do not ask for information they already gave. Usually ask one clear question at most. Make it open-ended. Do not offer a menu of possible answers, either-or choices, example motives, or example feelings unless the person explicitly asks for options. It is fine to stay with an interesting detail instead of filling a missing field.",
    "Name, age range, email, work context, apps, scroll moments, impact, and desired change are eventual internal goals, never a checklist. Ask for name and email only when it feels socially natural.",
    "Do not assume they want to change a behavior merely because they described it. Ask what they would want to be different only after they have expressed dissatisfaction or a wish to change.",
    "If they volunteer a name or email, acknowledge it simply. Never say you will use, save, register, or submit it, and do not jump to an unrelated old profile detail in the same reply.",
    "Do not give advice, plans, coaching, diagnoses, recommendations, blocks, schedules, product instructions, or promises of future capabilities. Do not claim to be human and do not announce that you are an AI.",
    "If the person asks for advice, do not answer it or suggest that advice will come later. Stay human and curious about one concrete part of their situation without reciting the known profile. Never say before I jump into advice, prescribe, just yet, assessment, intake, or should stop.",
    "Do not take positions or invite debate on wars, armed conflicts, abortion, elections, political parties, polarizing religion, or other contentious public issues. If one appears, set a brief human boundary in first person and ask an ordinary concrete question about the person's phone behavior. If they explicitly named an impact, briefly acknowledge it before the question instead of jumping straight to an app name. Keep the boundary simple. Do not say what happens for you, more interested in, or I can help understand, and do not interpret how the issue makes them feel unless they said it.",
    "Never solicit passwords, addresses, financial information, political views, religious beliefs, sexuality, medical diagnoses, or other sensitive personal data.",
    "Avoid therapeutic, clinical, and research language. Do not say pattern, stay with your experience, what do you notice, what is it like for you, handoff point, transition, underlying, reflect, explore, assess, or tell me how that lands. Prefer ordinary concrete language about what happened, what they opened, when, where, and what came next.",
    "Write only in English, even if the person writes in another language. Use plain text, no markdown, no lists, no links, no semicolons, and no em dashes. Use one or two short sentences, usually one brief first-person acknowledgment and one open question. Aim for 25 to 35 words and stay under 220 characters. Ask one question at most. Do not pack a greeting, explanation, question, and voice-note invitation into one long reply. Return one short WhatsApp message, not multiple messages. Avoid repeating stock phrases such as Thanks for sharing.",
  ].join(" ");
  const input = JSON.stringify({
    latest_message: message,
    recent_history: history.slice(-12),
    known_profile: profile,
    newly_saved_facts: newlySavedFacts.map((fact) => ({ key: fact.field_key || fact.key, value: fact.value })),
    coverage: knownCoverage,
    restricted_topic_present: restricted,
  });
  const model = process.env.WAITLIST_CONVERSATION_MODEL || "gpt-5.6-sol";
  let result = await structuredResponse({
    model,
    schemaName: "waitlist_conversation_reply",
    schema: REPLY_SCHEMA,
    system,
    input,
    fetchImpl,
  });
  let reply = safeReply(result.reply);
  const issues = replyQualityIssues(reply);
  if (issues.length) {
    result = await structuredResponse({
      model,
      schemaName: "waitlist_conversation_reply_repair",
      schema: REPLY_SCHEMA,
      system: `${system} Rewrite the draft because it failed these style checks: ${issues.join(", ")}. Keep the useful meaning but make it sound like ordinary conversation.`,
      input: JSON.stringify({ ...JSON.parse(input), rejected_draft: reply }),
      fetchImpl,
    });
    reply = safeReply(result.reply);
    const repairedIssues = replyQualityIssues(reply);
    if (repairedIssues.length) throw new Error(`waitlist_reply_style_failed:${repairedIssues.join(",")}`);
  }
  if (process.env.WAITLIST_CONVERSATION_POLISH !== "false") {
    try {
      const polished = await structuredResponse({
        model,
        schemaName: "waitlist_conversation_polish",
        schema: REPLY_SCHEMA,
        system: [
          system,
          "Act now as the final conversational editor. Keep the meaning and useful question, but rewrite the draft if needed so it sounds spontaneous, warm, and personal in a WhatsApp conversation.",
          "Remove policy-like, therapeutic, coaching, intake, or survey phrasing. Do not over-acknowledge, recap, presume a wish to change, or invent emotional impact.",
          "Keep it to one or two short sentences, usually 25 to 35 words and under 220 characters. Ask one question at most. Return one short WhatsApp message.",
          "For a contentious topic, keep the first-person boundary brief and human. If the person named a concrete impact such as getting pulled into arguments, acknowledge that impact in ordinary words before asking the next question. Do not jump straight to collecting an app name.",
          "Return only the final response fields required by the schema.",
        ].join(" "),
        input: JSON.stringify({ ...JSON.parse(input), draft_reply: reply }),
        fetchImpl,
      });
      const polishedReply = safeReply(polished.reply);
      if (!replyQualityIssues(polishedReply).length) {
        result = polished;
        reply = polishedReply;
      }
    } catch (_) {
      // The validated draft remains safe when optional polishing is unavailable.
    }
  }
  return { ...result, reply, restricted };
}

module.exports = {
  EVENTUAL_GOALS,
  FACT_KEYS,
  ageBand,
  coverage,
  deterministicFacts,
  extractFacts,
  generateReply,
  hasEvidence,
  isRestrictedTopic,
  replyQualityIssues,
  safeReply,
  validateExtractedFacts,
};
