const { json, requireMethod } = require("./_membership");
const { handler: blankedAgentHandler } = require("./blanked-agent");
const {
  connectCodeFromText,
  recordAssistantChannel,
} = require("./_assistant_channel");

function text(statusCode, body, contentType = "text/plain; charset=utf-8") {
  return {
    statusCode,
    headers: {
      "content-type": contentType,
      "cache-control": "no-store",
    },
    body,
  };
}

function rawBody(event) {
  if (!event.body) return "";
  return event.isBase64Encoded
    ? Buffer.from(event.body, "base64").toString("utf8")
    : event.body;
}

function parseSmsBody(event) {
  const contentType = event.headers["content-type"] || event.headers["Content-Type"] || "";
  const raw = rawBody(event);
  if (contentType.includes("application/json")) {
    try {
      const parsed = JSON.parse(raw || "{}");
      return {
        from: cleanText(parsed.from || parsed.From, 80),
        body: cleanText(parsed.body || parsed.Body || parsed.text, 800),
      };
    } catch {
      return { from: "", body: "" };
    }
  }

  const params = new URLSearchParams(raw);
  return {
    from: cleanText(params.get("From") || params.get("from"), 80),
    body: cleanText(params.get("Body") || params.get("body"), 800),
  };
}

function channelFromSender(from) {
  return cleanText(from, 90).toLowerCase().startsWith("whatsapp:") ? "whatsapp" : "sms";
}

function cleanText(value, maxLength = 240) {
  return String(value || "").trim().slice(0, maxLength);
}

function twiml(message) {
  return `<?xml version="1.0" encoding="UTF-8"?><Response><Message>${escapeXml(message)}</Message></Response>`;
}

function escapeXml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

function connectReply(from, channel) {
  const label = channel === "whatsapp" ? "WhatsApp" : "SMS";
  return `Connected. BAI will use ${label} for this number${from ? ` (${from})` : ""}.`;
}

function actionIntro(actions) {
  const first = primaryAction(actions);
  if (!first) return "";
  if (first.type === "set_daily_limit") return "Open Blanked to apply the daily limit:";
  if (first.type === "apply_schedule") return "Open Blanked to apply the protection window:";
  if (first.type === "start_protection") return "Open Blanked to start it:";
  if (first.type === "open_app_picker" || first.type === "request_screen_time_permission") return "Open Blanked to finish setup:";
  return "Open Blanked to apply it:";
}

function chatMessage(message, hasAction) {
  const text = cleanText(message, 1400);
  if (!hasAction || /^[\u{1F300}-\u{1FAFF}]/u.test(text)) return text;
  return `👍 ${text}`;
}

async function recordMessageConnection(connectCode, from, channel) {
  try {
    await recordAssistantChannel({
      event: "assistant_channel_connected",
      channel,
      preferredChannel: channel,
      connectCode,
      channelUser: from,
    });
  } catch (_) {
    return;
  }
}

async function askBAI(prompt, from, channel) {
  const response = await blankedAgentHandler({
    httpMethod: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      prompt,
      locale: "en-US",
      context: {
        channel,
        assistant_channel: channel,
        has_selected_apps: true,
        screen_time_authorized: true,
        memory: {
          phone_number_hash_hint: from ? "sms-linked" : "",
        },
      },
    }),
  });

  if (response.statusCode < 200 || response.statusCode >= 300) {
    return "BAI could not read that yet. Try again in a moment.";
  }
  const parsed = JSON.parse(response.body || "{}");
  const plan = parsed.plan || {};
  const message = cleanText(plan.message_text || plan.response_text, 1400);
  const actionLink = actionDeepLink(plan.actions || []);
  const reply = chatMessage(message, Boolean(actionLink));
  return actionLink ? `${reply}\n\n${actionIntro(plan.actions || [])}\n${actionLink}` : reply;
}

function actionDeepLink(actions) {
  const first = primaryAction(actions);
  if (!first) return "";

  if (first.type === "start_protection") {
    return `blank://start-focus?minutes=${clamp(first.minutes || 25, 5, 240)}${first.hard_mode ? "&hard=true" : ""}`;
  }
  if (first.type === "apply_schedule") {
    return `blank://apply-plan?start=${clamp(first.start_minute || 1260, 0, 1439)}&end=${clamp(first.end_minute || 1380, 0, 1439)}&days=${clamp(first.duration_days || 7, 1, 14)}`;
  }
  if (first.type === "set_daily_limit") {
    return `blank://daily-limit?minutes=${clamp(first.minutes || 25, 5, 240)}`;
  }
  if (first.type === "open_app_picker") {
    return "blank://open-picker";
  }
  if (first.type === "request_screen_time_permission") {
    return "blank://choose-apps";
  }
  if (first.type === "enable_allow_only") {
    return "blank://allow-only";
  }
  if (first.type === "enable_adult_filter") {
    return "blank://adult-filter";
  }
  if (first.type === "pause_rules") {
    return `blank://pause-rules?hours=${clamp(first.hours || 24, 1, 168)}`;
  }
  if (first.type === "disable_pause") {
    return "blank://resume-rules";
  }
  return "";
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

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;

  const { from, body } = parseSmsBody(event);
  if (!body) {
    return json(400, { error: "missing_sms_body" });
  }

  const connectCode = connectCodeFromText(body);
  const channel = channelFromSender(from);
  const reply = connectCode
    ? (await recordMessageConnection(connectCode, from, channel), connectReply(from, channel))
    : await askBAI(body, from, channel);

  return text(200, twiml(reply), "application/xml; charset=utf-8");
};
