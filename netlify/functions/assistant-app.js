const { getSupabaseUser, json, parseJsonBody, requireMethod, supabaseFetch } = require("./_membership");
const { identityForAuthUser } = require("./_identity");
const { getAssistantMemory, recordAssistantConversationTurn, recordAssistantMemory } = require("./_assistant_channel");
const { semanticPersistenceRequired } = require("./_bm_semantic_store");
const { callBlankedAgent, queuePendingAssistantAction } = require("./whatsapp-agent");

const TABLE = "assistant_app_turns";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

async function authenticatedIdentity(event, body) {
  const user = await getSupabaseUser(event);
  if (!user?.id) return { error: "authentication_required", status: 401 };
  const identity = await identityForAuthUser(user.id);
  if (!identity?.app_install_id || identity.app_install_id !== body.app_install_id
      || !identity.assistant_connect_code || !identity.phone_e164) {
    return { error: "installation_not_verified", status: 403 };
  }
  return { user, identity, connection: {
    channel: "whatsapp",
    channelUser: identity.phone_e164,
    connectCode: identity.assistant_connect_code,
  } };
}

async function readTurn(userId, turnId) {
  const rows = await supabaseFetch(
    `${TABLE}?id=eq.${encodeURIComponent(turnId)}&auth_user_id=eq.${encodeURIComponent(userId)}&select=*`,
    { method: "GET" },
  );
  return rows[0] || null;
}

function actionStatus(actionId, memory) {
  if (!actionId) return "";
  if (memory.pending_assistant_action?.id === actionId) {
    const expiry = Date.parse(memory.pending_assistant_action.expires_at || "");
    if (Number.isFinite(expiry) && expiry <= Date.now()) return "expired";
    return memory.pending_assistant_action.status || "queued";
  }
  if (memory.last_assistant_action_outcome?.id === actionId) {
    return memory.last_assistant_action_outcome.status || "failed";
  }
  return "superseded";
}

function presentTurn(row, memory) {
  return {
    id: row.id,
    user_text: row.user_text,
    assistant_text: row.assistant_text || "",
    status: row.status,
    action_id: row.action_id || "",
    action_label: row.action_label || "",
    action_status: actionStatus(row.action_id, memory),
    created_at: row.created_at,
  };
}

async function history(auth, body) {
  const before = String(body.before || "").trim();
  if (before && !Number.isFinite(Date.parse(before))) return json(400, { error: "invalid_history_cursor" });
  const rows = await supabaseFetch(
    `${TABLE}?auth_user_id=eq.${encodeURIComponent(auth.user.id)}`
      + (before ? `&created_at=lt.${encodeURIComponent(before)}` : "")
      + "&select=*&order=created_at.desc&limit=61",
    { method: "GET" },
  );
  const memory = await getAssistantMemory("whatsapp", auth.identity.phone_e164);
  const page = rows.slice(0, 60);
  return json(200, {
    ok: true,
    turns: page.reverse().map((row) => presentTurn(row, memory)),
    next_before: rows.length > 60 ? rows[59].created_at : null,
  });
}

async function send(auth, body) {
  const turnId = String(body.turn_id || "").trim();
  const prompt = String(body.text || "").trim().slice(0, 4000);
  if (!UUID.test(turnId) || !prompt) return json(400, { error: "invalid_turn" });
  const existing = await readTurn(auth.user.id, turnId);
  if (existing) {
    if (existing.status !== "completed") return json(409, { error: "turn_in_progress_or_failed" });
    const memory = await getAssistantMemory("whatsapp", auth.identity.phone_e164);
    return json(200, { ok: true, turn: presentTurn(existing, memory), idempotent: true });
  }
  try {
    await supabaseFetch(TABLE, {
      method: "POST",
      headers: { prefer: "return=minimal" },
      body: JSON.stringify({ id: turnId, auth_user_id: auth.user.id, user_text: prompt, status: "processing" }),
    });
  } catch (error) {
    const raced = await readTurn(auth.user.id, turnId);
    if (!raced) throw error;
    if (raced.status !== "completed") return json(409, { error: "turn_in_progress_or_failed" });
    const memory = await getAssistantMemory("whatsapp", auth.identity.phone_e164);
    return json(200, { ok: true, turn: presentTurn(raced, memory), idempotent: true });
  }
  try {
    const { plan, context } = await callBlankedAgent(prompt, auth.identity.phone_e164, auth.connection);
    const answer = String(plan.message_text || plan.response_text || "").trim().slice(0, 4000);
    if (!answer) throw new Error("assistant_empty_reply");
    await recordAssistantConversationTurn({
      channel: "whatsapp",
      channelUser: auth.identity.phone_e164,
      previousState: context.memory?.conversation_state,
      expectedVersion: context.memory?.semantic_store_version,
      userMessage: prompt,
      assistantMessage: answer,
      semanticState: plan.semantic_state,
      topic: context.memory?.last_topic || "",
    });
    if (plan.blocking_user_request === true) {
      try {
        await recordAssistantMemory({
          channel: "whatsapp", channelUser: auth.identity.phone_e164,
          memory: { pending_blocking: plan.blocking_ready === false
            ? { ...(plan.blocking_data || {}), updated_at: new Date().toISOString() }
            : null },
          source: plan.blocking_ready === false ? "blocking_details_requested" : "blocking_contract_completed",
        });
      } catch (error) { if (semanticPersistenceRequired()) throw error; }
    }
    let queued = null;
    let queueFailed = false;
    try { queued = await queuePendingAssistantAction(auth.connection, plan, prompt, "app"); }
    catch (_) { queueFailed = true; }
    const invalidates = plan.semantic_state?.intent === "cancelled"
      || (plan.semantic_state?.intent === "block" && ["collecting", "awaiting_confirmation"].includes(plan.semantic_state?.status));
    if (!queued && invalidates && !queueFailed) {
      await recordAssistantMemory({
        channel: "whatsapp", channelUser: auth.identity.phone_e164,
        memory: { pending_assistant_action: null }, source: "assistant_app_action_invalidated",
      }).catch(() => null);
    }
    const action = queued?.action;
    const spanish = String(plan.response_language || context.language || "").startsWith("es");
    const actionLabel = action?.type === "start_protection" && Number.isInteger(action.minutes)
      ? (spanish ? `Bloquear ${action.minutes} min` : `Block ${action.minutes} min`)
      : action ? (spanish ? "Aplicar ahora" : "Apply now") : null;
    const proposedAction = Array.isArray(plan.actions) && plan.actions.length > 0;
    const claimsExecution = /\b(?:already blocked|blocked your|already applied|activated your|he bloqueado|he aplicado|ya est[aá]n bloquead[ao]s|ya est[aá] aplicado)\b/i.test(answer);
    let visibleAnswer = answer;
    if (queueFailed || (proposedAction && !action)) {
      visibleAnswer = spanish
        ? "No he podido preparar esta acción. No se ha aplicado ningún cambio. Puedes volver a pedírmela."
        : "I couldn't prepare this action. No change was applied. You can ask me to try again.";
    } else if (action && claimsExecution) {
      visibleAnswer = spanish
        ? "La acción está preparada para tus distracciones seleccionadas. Pulsa el botón para aplicarla; te diré si el iPhone la verifica."
        : "The action is ready for your selected distractions. Tap the button to apply it; I'll show whether your iPhone verifies it.";
    }
    const rows = await supabaseFetch(`${TABLE}?id=eq.${encodeURIComponent(turnId)}&auth_user_id=eq.${encodeURIComponent(auth.user.id)}`, {
      method: "PATCH", headers: { prefer: "return=representation" },
      body: JSON.stringify({ assistant_text: visibleAnswer, action_id: action?.id || null, action_label: actionLabel,
        status: "completed", completed_at: new Date().toISOString() }),
    });
    const memory = await getAssistantMemory("whatsapp", auth.identity.phone_e164);
    return json(200, { ok: true, turn: presentTurn(rows[0], memory) });
  } catch (error) {
    await supabaseFetch(`${TABLE}?id=eq.${encodeURIComponent(turnId)}&status=eq.processing`, {
      method: "PATCH", headers: { prefer: "return=minimal" },
      body: JSON.stringify({ status: "failed" }),
    }).catch(() => null);
    throw error;
  }
}

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;
  try {
    const body = parseJsonBody(event);
    const auth = await authenticatedIdentity(event, body);
    if (auth.error) return json(auth.status, { error: auth.error });
    if (body.action === "history") return await history(auth, body);
    if (body.action === "send") return await send(auth, body);
    return json(400, { error: "unsupported_action" });
  } catch (error) {
    return json(500, { error: "assistant_app_failed", detail: error.message });
  }
};

exports.authenticatedIdentity = authenticatedIdentity;
exports.actionStatus = actionStatus;
