const {
  entitlementFromRecord,
  findMembershipByCode,
  findMembershipByOrder,
  json,
  parseJsonBody,
  patchMembership,
  requireMethod,
  timingSafeEqual,
} = require("./_membership");

const ALLOWED_STATUSES = new Set(["trial_active", "active", "past_due", "cancelled", "expired"]);

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;

  try {
    const secret = process.env.MEMBERSHIP_ADMIN_SECRET;
    const header = event.headers.authorization || event.headers.Authorization || "";
    const token = header.replace(/^Bearer\s+/i, "");
    if (!secret || !timingSafeEqual(secret, token)) {
      return json(401, { error: "unauthorized" });
    }

    const body = parseJsonBody(event);
    const membership = body.code
      ? await findMembershipByCode(body.code)
      : body.order_id
        ? await findMembershipByOrder(String(body.order_id))
        : null;

    if (!membership) {
      return json(404, { error: "membership_not_found" });
    }

    const updates = { updated_at: new Date().toISOString() };
    if (body.status) {
      if (!ALLOWED_STATUSES.has(body.status)) {
        return json(400, { error: "invalid_status" });
      }
      updates.status = body.status;
    }
    if ("trial_ends_at" in body) updates.trial_ends_at = body.trial_ends_at;
    if ("current_period_ends_at" in body) updates.current_period_ends_at = body.current_period_ends_at;
    if ("shopify_subscription_id" in body) updates.shopify_subscription_id = body.shopify_subscription_id;

    const updated = await patchMembership(membership.id, updates);
    return json(200, entitlementFromRecord(updated));
  } catch (error) {
    return json(500, { error: "membership_update_failed", detail: error.message });
  }
};
