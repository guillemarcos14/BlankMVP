const crypto = require("crypto");
const { getAssistantMemory, recordAssistantMemory } = require("./_assistant_channel");
const { sendAssistantActionPush } = require("./_assistant_push");
const { reviewActionLink } = require("./_bm_action_link");

const ONBOARDING_VERSION = "natural-v1";
const ONBOARDING_ACTION_TYPE = "open_app_picker";

function cleanText(value, maxLength = 600) {
  return String(value || "").trim().replace(/\s+/g, " ").slice(0, maxLength);
}

function hasSelectedDistractions(context = {}) {
  return context.has_selected_apps === true
    || Number(context.selection_count) > 0
    || (Array.isArray(context.selected_app_names) && context.selected_app_names.length > 0);
}

function onboardingMessages(context = {}) {
  return {
    welcome: "Welcome to Blankmind. I'm here to help you build a better relationship with your phone, one small change at a time. You can tell me what's pulling you in, ask for a digital detox plan, or say when you need a little help staying off an app.",
    setup: "To get started, choose the apps you consider distractions. That becomes your one distraction list, and every block or plan will work from it. Tap the button below to choose them in Blankmind, then come back here and talk to me normally.",
    ready: "Blankmind is already set up. From here, just talk to me normally: tell me what's been pulling you in, when you keep reaching for your phone, or what you'd like to change.",
  };
}

function onboardingAction(messages, now = Date.now()) {
  const createdAt = new Date(now).toISOString();
  const payload = {
    type: ONBOARDING_ACTION_TYPE,
    // A pure onboarding tap opens the picker; it must not imply a block or activate anything.
    name: null,
    minutes: null,
    hard_mode: false,
    start_minute: null,
    end_minute: null,
    weekdays: [],
    duration_days: null,
    hours: null,
    app_names: [],
  };
  const fingerprint = crypto.createHash("sha256")
    .update(`onboarding:${ONBOARDING_VERSION}:${JSON.stringify(payload)}`)
    .digest("hex")
    .slice(0, 32);
  return {
    id: `onboarding_${now.toString(36)}_${crypto.randomBytes(6).toString("hex")}`,
    fingerprint,
    ...payload,
    status: "queued",
    summary: cleanText(messages.setup, 320),
    source: "onboarding",
    created_at: createdAt,
    requested_at: createdAt,
    expires_at: new Date(now + 24 * 60 * 60 * 1000).toISOString(),
  };
}

function whatsappButtonVariables(link) {
  let linkPath = link;
  try {
    const parsed = new URL(link);
    linkPath = `${parsed.pathname.replace(/^\//, "")}${parsed.search}`;
  } catch (_) {
    linkPath = link.replace(/^https?:\/\/[^/]+\//i, "");
  }
  const configured = cleanText(process.env.TWILIO_WHATSAPP_ACTION_CONTENT_VARIABLES, 1000);
  if (configured) {
    try {
      const parsed = JSON.parse(configured);
      return Object.fromEntries(Object.entries(parsed).map(([key, value]) => [
        key,
        String(value).replace(/\{\{link\}\}/g, link).replace(/\{\{link_path\}\}/g, linkPath),
      ]));
    } catch (_) {
      return { "1": linkPath };
    }
  }
  return { "1": linkPath };
}

function onboardingButton(action) {
  const contentSid = cleanText(
    process.env.TWILIO_WHATSAPP_ONBOARDING_CONTENT_SID || process.env.TWILIO_WHATSAPP_ACTION_CONTENT_SID,
    80,
  );
  const link = reviewActionLink(action, []);
  if (!contentSid || !link) return null;
  return { contentSid, contentVariables: whatsappButtonVariables(link) };
}

async function queueOnboardingPicker({ channel, channelUser, messages }) {
  const memory = await getAssistantMemory(channel, channelUser);
  const existing = memory.pending_assistant_action;
  if (existing?.source === "onboarding" && Date.parse(existing.expires_at || "") > Date.now()) {
    let push = { sent: false, reason: "push_not_attempted" };
    try { push = await sendAssistantActionPush(memory.assistant_device_push, existing); } catch (error) { push = { sent: false, reason: `push_exception:${error.message}` }; }
    return { action: existing, push, button: onboardingButton(existing) };
  }

  const action = onboardingAction(messages);
  await recordAssistantMemory({
    channel,
    channelUser,
    memory: { pending_assistant_action: action },
    source: "assistant_onboarding_picker_pending",
  });
  let push = { sent: false, reason: "push_not_attempted" };
  try { push = await sendAssistantActionPush(memory.assistant_device_push, action); }
  catch (error) { push = { sent: false, reason: `push_exception:${error.message}` }; }
  try {
    await recordAssistantMemory({
      channel,
      channelUser,
      memory: {
        last_assistant_push_attempt: {
          action_id: action.id,
          action_type: action.type,
          sent: push.sent === true,
          reason: cleanText(push.reason, 200),
          status: Number(push.status || 0),
          apns_id: cleanText(push.apns_id, 80),
          attempted_at: push.accepted_at || push.attempted_at || new Date().toISOString(),
        },
      },
      source: push.sent === true ? "assistant_onboarding_push_accepted" : "assistant_onboarding_push_failed",
    });
  } catch (_) {
    // The pending action is already durable; push-attempt telemetry is best effort.
  }
  return { action, push, button: onboardingButton(action) };
}

async function markOnboardingSent(channel, channelUser) {
  try {
    await recordAssistantMemory({
      channel,
      channelUser,
      memory: {
        assistant_onboarding_version: ONBOARDING_VERSION,
        assistant_onboarding_sent_at: new Date().toISOString(),
      },
      source: "assistant_onboarding_sent",
    });
  } catch (_) {
    // A copy-delivery acknowledgement must never turn into a failed connection.
  }
}

module.exports = {
  ONBOARDING_VERSION,
  hasSelectedDistractions,
  onboardingMessages,
  onboardingAction,
  onboardingButton,
  queueOnboardingPicker,
  markOnboardingSent,
};
