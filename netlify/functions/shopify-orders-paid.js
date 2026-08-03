const {
  buildMembershipRecord,
  createMembership,
  entitlementFromRecord,
  findMembershipByOrder,
  generateActivationCode,
  json,
  parseJsonBody,
  planFromOrder,
  sendActivationEmail,
  verifyShopifyWebhook,
} = require("./_membership");

exports.handler = async (event) => {
  if (event.httpMethod !== "POST") {
    return json(405, { error: "method_not_allowed" });
  }

  try {
    verifyShopifyWebhook(event);
    const order = parseJsonBody(event);
    const orderId = String(order.id || order.admin_graphql_api_id || order.name);
    const existing = await findMembershipByOrder(orderId);

    if (existing) {
      return json(200, {
        ok: true,
        existing: true,
        code: existing.activation_code,
        entitlement: entitlementFromRecord(existing),
      });
    }

    const plan = planFromOrder(order);
    if (!plan) {
      return json(200, {
        ok: true,
        ignored: true,
        reason: "no_membership_plan_detected",
      });
    }

    let membership = null;
    let attempts = 0;

    while (!membership && attempts < 5) {
      attempts += 1;
      const code = generateActivationCode();
      const record = buildMembershipRecord({ order, plan, code });
      try {
        membership = await createMembership(record);
      } catch (error) {
        if (!String(error.message).includes("duplicate")) {
          throw error;
        }
      }
    }

    if (!membership) {
      throw new Error("Could not generate a unique activation code");
    }

    const email = await sendActivationEmail({
      to: membership.customer_email,
      code: membership.activation_code,
      plan: membership.plan,
    });

    return json(200, {
      ok: true,
      code: membership.activation_code,
      entitlement: entitlementFromRecord(membership),
      email,
    });
  } catch (error) {
    return json(500, { error: "shopify_order_paid_failed", detail: error.message });
  }
};
