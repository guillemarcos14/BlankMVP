const { json, parseJsonBody, requireMethod } = require("./_membership");
const {
  cleanChannel,
  cleanText,
  findAssistantConnection,
  attachAssistantUserContext,
  recordAssistantMemory,
  getAssistantMemory,
  normalizeConnectCode,
  recordAssistantUserContext,
  recordAssistantChannel,
  proactiveGate,
  sendAssistantMessage,
} = require("./_assistant_channel");
const { identityForAppInstall, identityForPhone } = require("./_identity");
const { normalizeDevicePush } = require("./_assistant_push");

async function registerPreference(body) {
  const connectCode = normalizeConnectCode(body.connect_code);
  const preferredChannel = cleanChannel(body.preferred_channel || body.channel);
  if (!connectCode || !preferredChannel) {
    return json(400, { error: "missing_connect_code_or_channel" });
  }

  await recordAssistantChannel({
    event: "assistant_channel_preference_set",
    channel: preferredChannel,
    preferredChannel,
    connectCode,
    userPhone: body.user_phone || body.phone_number || "",
  });

  if (body.context && typeof body.context === "object" && !Array.isArray(body.context)) {
    const normalizedContext = await recordAssistantUserContext({
      connectCode,
      context: body.context,
      channel: preferredChannel,
      userPhone: body.user_phone || body.phone_number || "",
    });
    const connection = await findAssistantConnection(connectCode, preferredChannel);
    if (connection && normalizedContext) {
      await attachAssistantUserContext({
        connectCode,
        channel: connection.channel,
        channelUser: connection.channelUser,
      });
    }
  }

  return json(200, { ok: true, connect_code: connectCode, preferred_channel: preferredChannel });
}

async function sendProactive(body) {
  const connectCode = normalizeConnectCode(body.connect_code);
  const preferredChannel = cleanChannel(body.preferred_channel || body.channel);
  const message = cleanText(body.message || body.body || body.text, 900);
  if (!connectCode || !message) {
    return json(400, { error: "missing_connect_code_or_message" });
  }

  const connection = await findAssistantConnection(connectCode, preferredChannel);
  const gate = await proactiveGate(connectCode, message, connection?.channel || preferredChannel, body.update_key || body.signal_id || "", connection?.channelUser || "");
  if (!gate.allowed) {
    await recordAssistantChannel({
      event: "assistant_proactive_delivery_skipped",
      channel: connection?.channel || preferredChannel,
      preferredChannel,
      connectCode,
      channelUser: connection?.channelUser || "",
      metadata: { reason: gate.reason },
    });
    return json(200, { ok: true, delivered: false, channel: connection?.channel || preferredChannel || "", reason: gate.reason });
  }
  if (connection?.channel === "whatsapp" && !gate.contentSid) {
    return json(200, { ok: true, delivered: false, channel: "whatsapp", reason: "missing_proactive_template" });
  }
  const result = await sendAssistantMessage(connection, message, gate.contentSid ? { contentSid: gate.contentSid } : {});
  await recordAssistantChannel({
    event: result.skipped ? "assistant_proactive_delivery_skipped" : "assistant_proactive_delivered",
    channel: connection?.channel || preferredChannel,
    preferredChannel,
    connectCode,
    channelUser: connection?.channelUser || "",
    metadata: {
      proactive_fingerprint: gate.proactiveFingerprint,
      update_key: cleanText(body.update_key || body.signal_id, 120),
      template_index: gate.templateIndex,
      content_sid: gate.contentSid,
    },
  });

  if (!result.skipped && connection?.channel === "whatsapp") {
    await require("./_assistant_channel").recordAssistantMemory({
      channel: "whatsapp",
      channelUser: connection.channelUser,
      memory: {
        pending_proactive_message: message,
        pending_proactive_update_key: cleanText(body.update_key || body.signal_id, 120),
        pending_proactive_sent_at: new Date().toISOString(),
      },
      source: "assistant_proactive_template",
    });
  }

  return json(200, {
    ok: true,
    delivered: !result.skipped,
    channel: connection?.channel || preferredChannel || "",
    reason: result.reason || "",
  });
}

async function syncContext(body) {
  const connectCode = normalizeConnectCode(body.connect_code);
  const preferredChannel = cleanChannel(body.preferred_channel || body.channel);
  const context = body.context && typeof body.context === "object" && !Array.isArray(body.context)
    ? body.context
    : null;
  if (!connectCode || !context) return json(400, { error: "missing_connect_code_or_context" });

  const normalizedContext = await recordAssistantUserContext({
    connectCode,
    context,
    channel: preferredChannel,
    userPhone: body.user_phone || body.phone_number || "",
  });
  const connection = await findAssistantConnection(connectCode, preferredChannel);
  if (connection && normalizedContext) {
    await recordAssistantMemory({
      channel: connection.channel,
      channelUser: connection.channelUser,
      memory: { user_context: normalizedContext },
      source: "assistant_user_context_sync",
    });
  }
  return json(200, {
    ok: true,
    synced: Boolean(normalizedContext),
    available_mode_count: Array.isArray(normalizedContext?.available_mode_catalog)
      ? normalizedContext.available_mode_catalog.length
      : 0,
    attached_channel: connection?.channel || "",
  });
}

async function registerDevicePush(body) {
  const result = await connectedChannel(body);
  if (result.error) return json(400, { error: result.error });
  if (!result.connection) return json(200, { ok: true, registered: false, reason: "not_linked" });
  const devicePush = normalizeDevicePush({
    token: body.device_token,
    environment: body.environment,
    app_install_id: body.app_install_id,
    updated_at: new Date().toISOString(),
  });
  if (!devicePush) return json(400, { error: "invalid_device_token" });
  await recordAssistantMemory({
    channel: result.connection.channel,
    channelUser: result.connection.channelUser,
    memory: { assistant_device_push: devicePush },
    source: "assistant_device_push_registered",
  });
  return json(200, { ok: true, registered: true, environment: devicePush.environment });
}

const PENDING_ACTION_TYPES = new Set([
  "start_protection", "activate_mode", "switch_mode", "apply_schedule", "set_daily_limit",
  "enable_allow_only", "enable_adult_filter", "pause_rules", "disable_pause", "apply_ai_plan",
  "open_app_picker", "request_screen_time_permission",
]);

function normalizePendingAction(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const id = cleanText(value.id, 80);
  const type = cleanText(value.type, 60);
  const expiresAt = Date.parse(value.expires_at || "");
  if (!id || !PENDING_ACTION_TYPES.has(type) || !Number.isFinite(expiresAt) || expiresAt <= Date.now()) return null;
  const action = {
    id,
    type,
    name: cleanText(value.name, 80) || null,
    source_mode_name: cleanText(value.source_mode_name, 80) || null,
    copy_mode: value.copy_mode === true,
    minutes: Number.isInteger(value.minutes) ? Math.min(Math.max(value.minutes, 5), 240) : null,
    hard_mode: value.hard_mode === true,
    start_minute: Number.isInteger(value.start_minute) ? Math.min(Math.max(value.start_minute, 0), 1439) : null,
    end_minute: Number.isInteger(value.end_minute) ? Math.min(Math.max(value.end_minute, 0), 1439) : null,
    weekdays: Array.isArray(value.weekdays)
      ? value.weekdays.filter((day) => Number.isInteger(day) && day >= 1 && day <= 7).slice(0, 7)
      : [],
    duration_days: Number.isInteger(value.duration_days) ? Math.min(Math.max(value.duration_days, 1), 14) : null,
    hours: Number.isInteger(value.hours) ? Math.min(Math.max(value.hours, 1), 168) : null,
    app_names: Array.isArray(value.app_names)
      ? value.app_names.map((name) => cleanText(name, 40)).filter(Boolean).slice(0, 12)
      : [],
    summary: cleanText(value.summary, 320),
    created_at: cleanText(value.created_at, 40),
    expires_at: new Date(expiresAt).toISOString(),
    status: cleanText(value.status, 24) || "queued",
    delivered_at: cleanText(value.delivered_at, 40),
    confirmed_at: cleanText(value.confirmed_at, 40),
    execution_started_at: cleanText(value.execution_started_at, 40),
  };
  if (type === "apply_schedule" && (
    !Number.isInteger(action.start_minute)
    || !Number.isInteger(action.end_minute)
    || action.start_minute === action.end_minute
  )) return null;
  return action;
}

async function connectedChannel(body) {
  const preferredChannel = cleanChannel(body.preferred_channel || body.channel);
  if (!preferredChannel) return { error: "missing_channel" };
  let connectCode = normalizeConnectCode(body.connect_code);
  if (!connectCode) {
    const identity = await identityForAppInstall(body.app_install_id)
      || await identityForPhone(body.user_phone || body.phone_number);
    connectCode = normalizeConnectCode(identity?.assistant_connect_code);
  }
  if (!connectCode) return { error: "installation_not_linked" };
  const connection = await findAssistantConnection(connectCode, preferredChannel);
  return { connectCode, preferredChannel, connection };
}

async function pollPendingAction(body) {
  const result = await connectedChannel(body);
  if (result.error) return json(400, { error: result.error });
  if (!result.connection) return json(200, { ok: true, linked: false, pending_action: null });

  const memory = await getAssistantMemory(result.connection.channel, result.connection.channelUser);
  const pending = normalizePendingAction(memory.pending_assistant_action);
  if (!pending && memory.pending_assistant_action) {
    await recordAssistantMemory({
      channel: result.connection.channel,
      channelUser: result.connection.channelUser,
      memory: { pending_assistant_action: null },
      source: "assistant_action_expired",
    });
  }
  if (pending && pending.status === "queued") {
    const delivered = { ...memory.pending_assistant_action, status: "delivered", delivered_at: new Date().toISOString() };
    await recordAssistantMemory({
      channel: result.connection.channel,
      channelUser: result.connection.channelUser,
      memory: { pending_assistant_action: delivered },
      source: "assistant_action_delivered",
    });
    Object.assign(pending, normalizePendingAction(delivered));
  }
  return json(200, {
    ok: true,
    linked: true,
    pending_action: pending,
  });
}

async function acknowledgePendingAction(body) {
  const result = await connectedChannel(body);
  const actionId = cleanText(body.action_id, 80);
  const status = ["received", "confirmed", "execution_started", "verified", "failed", "dismissed"].includes(cleanText(body.status, 24).toLowerCase())
    ? cleanText(body.status, 20).toLowerCase()
    : "failed";
  if (result.error || !actionId) return json(400, { error: result.error || "missing_action_id" });
  if (!result.connection) return json(200, { ok: true, acknowledged: false, reason: "not_linked" });

  const memory = await getAssistantMemory(result.connection.channel, result.connection.channelUser);
  const pending = normalizePendingAction(memory.pending_assistant_action);
  if (!pending || pending.id !== actionId) {
    return json(200, { ok: true, acknowledged: false, reason: pending ? "action_mismatch" : "no_pending_action" });
  }
  const now = new Date().toISOString();
  const terminal = ["verified", "failed", "dismissed"].includes(status);
  const timestampKey = status === "confirmed" ? "confirmed_at"
    : status === "execution_started" ? "execution_started_at"
      : status === "received" ? "delivered_at" : "resolved_at";
  const updated = { ...memory.pending_assistant_action, status, [timestampKey]: now };
  await recordAssistantMemory({
    channel: result.connection.channel,
    channelUser: result.connection.channelUser,
    memory: terminal
      ? {
          pending_assistant_action: null,
          last_assistant_action_outcome: {
            id: actionId,
            type: pending.type,
            status,
            resolved_at: now,
            detail: cleanText(body.detail, 240),
          },
        }
      : { pending_assistant_action: updated },
    source: `assistant_action_${status}`,
  });
  if (terminal) {
    const spanish = String(memory.language || "").toLowerCase().startsWith("es");
    let message;
    if (status === "verified") {
      const target = pending.app_names.length ? pending.app_names.join(", ") : (pending.source_mode_name || pending.name || "the requested apps");
      if (["start_protection", "activate_mode"].includes(pending.type)) {
        message = spanish
          ? `${target} ${pending.minutes ? `está bloqueado durante ${pending.minutes} minutos` : "está bloqueado"}.`
          : `${target} is blocked${pending.minutes ? ` for ${pending.minutes} minutes` : ""}.`;
      } else if (pending.type === "apply_schedule") {
        message = spanish ? "El nuevo horario de bloqueo ya está aplicado." : "The new blocking schedule is applied.";
      } else {
        message = spanish ? "Hecho. El cambio está aplicado y verificado." : "Done. The change is applied and verified.";
      }
    } else {
      message = spanish
        ? "No he podido aplicar el bloqueo en el iPhone. No se ha marcado como completado."
        : "I couldn't apply the block on the iPhone. It hasn't been marked as completed.";
    }
    try { await sendAssistantMessage(result.connection, message); } catch (_) { /* The verified outcome remains recorded. */ }
  }
  return json(200, { ok: true, acknowledged: true, status });
}

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;

  try {
    const body = parseJsonBody(event);
    const action = cleanText(body.action, 60).toLowerCase();
    if (action === "register_preference") return registerPreference(body);
    if (action === "sync_context") return syncContext(body);
    if (action === "register_device_push") return registerDevicePush(body);
    if (action === "send_proactive") return sendProactive(body);
    if (action === "poll_pending_action") return pollPendingAction(body);
    if (action === "ack_pending_action") return acknowledgePendingAction(body);
    return json(400, { error: "unsupported_action" });
  } catch (error) {
    return json(500, { error: "assistant_channel_failed", detail: error.message });
  }
};

exports.normalizePendingAction = normalizePendingAction;
