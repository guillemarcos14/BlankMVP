const crypto = require("crypto");
const {
  getSupabaseUser,
  json,
  parseJsonBody,
  requireMethod,
  supabaseFetch,
} = require("./_membership");
const {
  cleanText,
  ensureIdentityForAuthUser,
  linkAppInstall,
} = require("./_identity");

function hashToken(token) {
  return crypto.createHash("sha256").update(String(token || "")).digest("hex");
}

function appInstallId(body) {
  return cleanText(body.app_install_id, 160);
}

async function authenticatedUser(event) {
  const user = await getSupabaseUser(event);
  return user?.id ? user : null;
}

async function createHandoff(event) {
  const user = await authenticatedUser(event);
  if (!user) return json(401, { error: "authentication_required" });

  const body = parseJsonBody(event);
  if (body.data_consent !== true) return json(400, { error: "missing_consent" });
  const identity = await ensureIdentityForAuthUser({
    authUserId: user.id,
    phoneE164: user.phone || "",
  });
  const token = crypto.randomBytes(32).toString("base64url");
  const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
  await supabaseFetch("app_handoffs", {
    method: "POST",
    headers: { prefer: "return=minimal" },
    body: JSON.stringify({
      token_hash: hashToken(token),
      auth_user_id: user.id,
      expires_at: expiresAt,
    }),
  });

  const handoffUrl = new URL("https://blankmind.ai/open");
  handoffUrl.searchParams.set("action", "handoff");
  handoffUrl.searchParams.set("token", token);
  return json(200, {
    ok: true,
    handoff_url: handoffUrl.toString(),
    expires_at: expiresAt,
    assistant_connect_code: identity?.assistant_connect_code || "",
  });
}

async function claimHandoff(event) {
  const body = parseJsonBody(event);
  const token = cleanText(body.handoff_token || body.token, 240);
  const installId = appInstallId(body);
  if (!token || !installId || body.data_consent !== true) {
    return json(400, { error: "missing_handoff_input" });
  }

  const now = new Date().toISOString();
  const rows = await supabaseFetch(
    `app_handoffs?token_hash=eq.${encodeURIComponent(hashToken(token))}&consumed_at=is.null&expires_at=gt.${encodeURIComponent(now)}&select=id,auth_user_id&limit=1`,
    { method: "GET" },
  );
  const handoff = rows[0];
  if (!handoff) return json(400, { error: "handoff_invalid_or_expired" });

  const consumed = await supabaseFetch(
    `app_handoffs?id=eq.${encodeURIComponent(handoff.id)}&consumed_at=is.null`,
    {
      method: "PATCH",
      headers: { prefer: "return=representation" },
      body: JSON.stringify({ consumed_at: now }),
    },
  );
  if (!consumed.length) return json(409, { error: "handoff_already_claimed" });

  const identity = await linkAppInstall({
    authUserId: handoff.auth_user_id,
    appInstallId: installId,
  });
  return json(200, {
    ok: true,
    auth_user_id: handoff.auth_user_id,
    phone_e164: identity?.phone_e164 || "",
    assistant_connect_code: identity?.assistant_connect_code || "",
  });
}

async function claimIdentity(event) {
  const user = await authenticatedUser(event);
  if (!user) return json(401, { error: "authentication_required" });
  const body = parseJsonBody(event);
  const installId = appInstallId(body);
  if (!installId || body.data_consent !== true) return json(400, { error: "missing_identity_link_input" });
  const identity = await ensureIdentityForAuthUser({
    authUserId: user.id,
    phoneE164: user.phone || "",
  });
  const linked = await linkAppInstall({ authUserId: user.id, appInstallId: installId });
  return json(200, {
    ok: true,
    auth_user_id: user.id,
    phone_e164: linked?.phone_e164 || identity?.phone_e164 || user.phone || "",
    assistant_connect_code: linked?.assistant_connect_code || identity?.assistant_connect_code || "",
  });
}

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;
  try {
    const action = cleanText(parseJsonBody(event).action, 40).toLowerCase();
    if (action === "create") return await createHandoff(event);
    if (action === "claim") return await claimHandoff(event);
    if (action === "claim_identity") return await claimIdentity(event);
    return json(400, { error: "unsupported_action" });
  } catch (error) {
    const status = /conflict/.test(error.message) ? 409 : 500;
    return json(status, { error: "app_handoff_failed", detail: error.message });
  }
};
