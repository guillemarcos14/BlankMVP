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

function connectReply(from) {
  return `Connected. BAI will use SMS for this number${from ? ` (${from})` : ""}.`;
}

async function recordSmsConnection(connectCode, from) {
  try {
    await recordAssistantChannel({
      event: "assistant_channel_connected",
      channel: "sms",
      preferredChannel: "sms",
      connectCode,
      channelUser: from,
    });
  } catch (_) {
    return;
  }
}

async function askBAI(prompt, from) {
  const response = await blankedAgentHandler({
    httpMethod: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      prompt,
      locale: "en-US",
      context: {
        channel: "sms",
        assistant_channel: "sms",
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
  return actionLink ? `${message}\n${actionLink}` : message;
}

function actionDeepLink(actions) {
  const first = Array.isArray(actions) ? actions.find((item) => item && item.type && item.type !== "none") : null;
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
  const reply = connectCode
    ? (await recordSmsConnection(connectCode, from), connectReply(from))
    : await askBAI(body, from);

  return text(200, twiml(reply), "application/xml; charset=utf-8");
};
