const { json, requireCallAdmin, twilioConfig, twilioRequest, twilioVoiceUrl } = require("./_twilio_voice");
const { parseJsonBody, requireMethod } = require("./_membership");
const { cleanText } = require("./_assistant_channel");

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;

  const admin = requireCallAdmin(event);
  if (!admin.ok) return admin.response;

  try {
    const body = parseJsonBody(event);
    const to = cleanText(body.to || body.to_number, 80);
    if (!to || !/^\+\d{8,15}$/.test(to)) return json(400, { error: "invalid_to_number" });

    const config = twilioConfig();
    if (!config.from) return json(503, { error: "missing_twilio_voice_from_number" });

    const params = new URLSearchParams();
    params.set("To", to);
    params.set("From", config.from);
    params.set("Url", twilioVoiceUrl(event, "outbound"));
    params.set("Method", "POST");

    const call = await twilioRequest("/Calls.json", params);
    return json(200, {
      ok: true,
      sid: call.sid,
      status: call.status,
      to,
      from: config.from,
    });
  } catch (error) {
    return json(500, { error: "bai_call_failed", detail: error.message });
  }
};
