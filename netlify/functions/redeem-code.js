const {
  entitlementFromRecord,
  findMembershipByCode,
  json,
  listDevices,
  parseJsonBody,
  patchMembership,
  recordGrantsAccess,
  requireMethod,
  touchDevice,
} = require("./_membership");

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;

  try {
    const body = parseJsonBody(event);
    const code = body.code;
    const appInstallId = body.app_install_id;
    const platform = body.platform || "ios";

    if (!code || !appInstallId) {
      return json(400, { error: "missing_code_or_app_install_id" });
    }

    const membership = await findMembershipByCode(code);
    if (!membership) {
      return json(404, { error: "invalid_code" });
    }

    if (!recordGrantsAccess(membership)) {
      return json(403, { error: "membership_not_active", ...entitlementFromRecord(membership) });
    }

    const devices = await listDevices(membership.id);
    const alreadyLinked = devices.some((device) => device.app_install_id === appInstallId);
    if (!alreadyLinked && devices.length >= membership.max_devices) {
      return json(403, { error: "device_limit_reached", ...entitlementFromRecord(membership) });
    }

    await touchDevice(membership.id, appInstallId, platform);
    const updated = await patchMembership(membership.id, { updated_at: new Date().toISOString() });
    return json(200, entitlementFromRecord(updated || membership));
  } catch (error) {
    return json(500, { error: "redeem_failed", detail: error.message });
  }
};
