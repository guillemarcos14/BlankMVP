const assert = require("assert");
const membership = require("../netlify/functions/_membership");

const codes = new Set(Array.from({ length: 1000 }, () => membership.generateActivationCode()));
assert.equal(codes.size, 1000);

const sample = Array.from(codes)[0];
assert.match(sample, /^BLANK-[A-Z2-9]{4}-[A-Z2-9]{4}$/);

const active = membership.entitlementFromRecord({
  status: "active",
  plan: "family",
  max_devices: 5,
  trial_ends_at: null,
  current_period_ends_at: "2099-01-01T00:00:00.000Z",
});
assert.deepEqual(active, {
  status: "active",
  plan: "family",
  max_devices: 5,
  trial_ends_at: null,
  current_period_ends_at: "2099-01-01T00:00:00.000Z",
});

const expiredRecord = {
  status: "active",
  plan: "annual",
  max_devices: 1,
  trial_ends_at: null,
  current_period_ends_at: "2000-01-01T00:00:00.000Z",
};
const expired = membership.entitlementFromRecord(expiredRecord);
assert.equal(expired.status, "expired");
assert.equal(membership.recordGrantsAccess(expiredRecord), false);

process.env.SHOPIFY_TRIAL_SELLING_PLAN_IDS = "gid://shopify/SellingPlan/691965231447,691965231447";
process.env.SHOPIFY_MONTHLY_SELLING_PLAN_IDS = "gid://shopify/SellingPlan/691965264215,691965264215";
process.env.SHOPIFY_ANNUAL_SELLING_PLAN_IDS = "gid://shopify/SellingPlan/691965690199,691965690199";
process.env.SHOPIFY_FAMILY_SELLING_PLAN_IDS = "gid://shopify/SellingPlan/691965722967,691965722967";
process.env.SHOPIFY_ANNUAL_VARIANT_IDS = "gid://shopify/ProductVariant/54026066788695,54026066788695";

assert.equal(
  membership.planFromOrder({
    line_items: [{
      variant_id: 54026066788695,
      selling_plan_allocation: {
        selling_plan: { id: "gid://shopify/SellingPlan/691965231447", name: "30 dias gratis, luego 29€/año" },
      },
    }],
  }),
  "trial"
);

assert.equal(
  membership.planFromOrder({
    line_items: [{
      variant_id: 54026066788695,
      selling_plan_allocation: {
        selling_plan: { id: "gid://shopify/SellingPlan/691965722967", name: "Plan familiar - 39€/año" },
      },
    }],
  }),
  "family"
);

assert.equal(
  membership.planFromOrder({
    line_items: [{
      variant_id: 54026066788695,
      selling_plan_name: "Plan mensual - 3,99€/mes",
    }],
  }),
  "monthly"
);

console.log(`membership smoke test ok: ${sample}`);
