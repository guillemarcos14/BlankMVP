const crypto = require("crypto");
const { getAssistantMemory, recordAssistantMemory, sendAssistantMessage } = require("./_assistant_channel");
const { sendAssistantActionPush } = require("./_assistant_push");

const wait = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

function validRequest(body) {
  const channel = String(body?.channel || "").toLowerCase();
  const channelUser = String(body?.channel_user || "").slice(0, 160);
  const actionId = String(body?.action_id || "").slice(0, 80);
  const supplied = String(body?.signature || "");
  const secret = String(process.env.WHATSAPP_APP_SECRET || "");
  if (!secret || !["whatsapp", "sms"].includes(channel) || !channelUser || !actionId || !/^[a-f0-9]{64}$/.test(supplied)) return null;
  const expected = crypto.createHmac("sha256", secret).update(`${channel}:${channelUser}:${actionId}`).digest("hex");
  const valid = crypto.timingSafeEqual(Buffer.from(supplied), Buffer.from(expected));
  return valid ? { channel, channelUser, actionId } : null;
}

async function retryIfPending(target, attempt) {
  const memory = await getAssistantMemory(target.channel, target.channelUser);
  const pending = memory.pending_assistant_action;
  if (!pending || pending.id !== target.actionId || !["queued", "delivered"].includes(pending.status || "queued")) {
    return { pending: false, memory };
  }
  if (Date.parse(pending.expires_at || "") <= Date.now()) return { pending: false, memory, expired: true };
  const push = await sendAssistantActionPush(memory.assistant_device_push, pending);
  await recordAssistantMemory({
    channel: target.channel,
    channelUser: target.channelUser,
    memory: {
      last_assistant_push_attempt: {
        action_id: pending.id,
        action_type: pending.type,
        sent: push.sent === true,
        reason: String(push.reason || "").slice(0, 200),
        status: Number(push.status || 0),
        apns_id: String(push.apns_id || "").slice(0, 80),
        attempt,
        attempted_at: push.accepted_at || push.attempted_at || new Date().toISOString(),
      },
    },
    source: push.sent ? "assistant_push_retry_accepted" : "assistant_push_retry_failed",
  });
  return { pending: true, memory, push };
}

exports.handler = async (event) => {
  let body;
  try { body = JSON.parse(event.body || "{}"); } catch (_) { return { statusCode: 400 }; }
  const target = validRequest(body);
  if (!target) return { statusCode: 403 };

  await wait(20_000);
  let state = await retryIfPending(target, 2);
  if (!state.pending) return { statusCode: 200 };

  await wait(40_000);
  state = await retryIfPending(target, 3);
  if (!state.pending) return { statusCode: 200 };
  const fresh = await getAssistantMemory(target.channel, target.channelUser);
  if (fresh.delivery_notice_sent_action_id !== target.actionId) {
    await recordAssistantMemory({
      channel: target.channel,
      channelUser: target.channelUser,
      memory: {
        delivery_notice_sent_action_id: target.actionId,
        last_assistant_action_delivery_state: {
          action_id: target.actionId,
          status: "delayed_unconfirmed",
          measured_at: new Date().toISOString(),
        },
      },
      source: "assistant_action_delivery_delayed",
    });
    if (!target.actionId.startsWith("app_")) {
      await sendAssistantMessage(
        { channel: target.channel, channelUser: target.channelUser },
        String(fresh.language || "").toLowerCase().startsWith("es")
          ? "El iPhone aún no ha confirmado esta orden. No la cuento como aplicada. iOS puede retrasar o impedir la ejecución en segundo plano; seguiré aceptando únicamente la evidencia de esa acción concreta."
          : "The iPhone has not confirmed this request. It is not counted as applied. iOS may delay background execution; only evidence for this exact action will complete it."
      );
    }
  }
  return { statusCode: 200 };
};

exports.validRequest = validRequest;
