const {
  entitlementFromRecord,
  findMembershipByOrder,
  json,
  parseJsonBody,
  requireMethod,
  timingSafeEqual,
} = require("./_membership");

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;

  try {
    const secret = process.env.MEMBERSHIP_ADMIN_SECRET;
    const header = event.headers.authorization || event.headers.Authorization || "";
    const token = header.replace(/^Bearer\s+/i, "");
    const isAdmin = secret && timingSafeEqual(secret, token);
    const publicLookupEnabled = process.env.PUBLIC_ACTIVATION_LOOKUP_ENABLED === "true";

    const body = parseJsonBody(event);
    const orderId = body.order_id;
    if (!orderId) {
      return json(400, { error: "missing_order_id" });
    }

    if (!isAdmin && !publicLookupEnabled) {
      return json(401, { error: "unauthorized" });
    }

    const membership = await findMembershipByOrder(String(orderId));
    if (!membership) {
      return json(202, { status: "preparing_code" });
    }

    if (!isAdmin) {
      const check = String(body.confirmation_number || body.order_name || "").trim();
      const validChecks = [
        membership.shopify_confirmation_number,
        membership.shopify_order_name,
      ].filter(Boolean).map(String);

      if (!check || !validChecks.includes(check)) {
        return json(403, { error: "order_verification_failed" });
      }
    }

    return json(200, {
      code: membership.activation_code,
      entitlement: entitlementFromRecord(membership),
    });
  } catch (error) {
    return json(500, { error: "activation_code_lookup_failed", detail: error.message });
  }
};
