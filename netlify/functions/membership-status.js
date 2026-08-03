const {
  entitlementFromRecord,
  findMembershipByCode,
  json,
  listDevices,
  parseJsonBody,
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

    const devices = await listDevices(membership.id);
    const isLinked = devices.some((device) => device.app_install_id === appInstallId);
    if (!isLinked) {
      return json(403, { error: "device_not_authorized", ...entitlementFromRecord(membership) });
    }

    await touchDevice(membership.id, appInstallId, platform);
    return json(200, entitlementFromRecord(membership));
  } catch (error) {
    return json(500, { error: "status_failed", detail: error.message });
  }
};
