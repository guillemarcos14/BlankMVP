const {
  PLAN_CONFIG,
  codeHash,
  createMembership,
  entitlementFromRecord,
  generateActivationCode,
  json,
  parseJsonBody,
  sendActivationEmail,
  timingSafeEqual,
} = require("./_membership");

function daysFromNow(days) {
  return new Date(Date.now() + days * 24 * 60 * 60 * 1000).toISOString();
}

function randomManualOrderId() {
  return `manual-${require("crypto").randomBytes(10).toString("hex")}`;
}

exports.handler = async (event) => {
  if (event.httpMethod === "OPTIONS") {
    return json(204, {});
  }
  if (event.httpMethod !== "POST") {
    return json(405, { error: "method_not_allowed" });
  }

  try {
    const secret = process.env.MEMBERSHIP_ADMIN_SECRET;
    const header = event.headers.authorization || event.headers.Authorization || "";
    const token = header.replace(/^Bearer\s+/i, "");
    if (!secret || !timingSafeEqual(secret, token)) {
      return json(401, { error: "unauthorized" });
    }

    const body = parseJsonBody(event);
    const plan = body.plan || "annual";
    const config = PLAN_CONFIG[plan];
    if (!config) {
      return json(400, { error: "invalid_plan" });
    }

    const code = generateActivationCode();
    const now = new Date().toISOString();
    const membership = await createMembership({
      activation_code: code,
      code_hash: codeHash(code),
      status: config.status,
      plan,
      max_devices: body.max_devices || config.maxDevices,
      shopify_order_id: body.order_id || randomManualOrderId(),
      shopify_order_name: body.order_name || null,
      shopify_confirmation_number: body.confirmation_number || null,
      shopify_customer_id: body.customer_id || null,
      shopify_subscription_id: body.subscription_id || null,
      customer_email: body.email || null,
      trial_ends_at: config.trialDays ? daysFromNow(config.trialDays) : null,
      current_period_ends_at: config.periodDays ? daysFromNow(config.periodDays) : null,
      created_at: now,
      updated_at: now,
    });

    const email = body.send_email === false
      ? { skipped: true }
      : await sendActivationEmail({ to: membership.customer_email, code, plan });

    return json(200, {
      code,
      entitlement: entitlementFromRecord(membership),
      email,
    });
  } catch (error) {
    return json(500, { error: "membership_create_failed", detail: error.message });
  }
};
