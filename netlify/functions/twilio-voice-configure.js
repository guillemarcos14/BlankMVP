const { json, requireCallAdmin, twilioConfig, twilioRequest, twilioVoiceUrl } = require("./_twilio_voice");
const { requireMethod } = require("./_membership");

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;

  const admin = requireCallAdmin(event);
  if (!admin.ok) return admin.response;

  try {
    const config = twilioConfig();
    if (!config.sid || !config.token || !config.from) {
      return json(503, { error: "twilio_voice_not_configured" });
    }

    const list = await fetch(
      `https://api.twilio.com/2010-04-01/Accounts/${encodeURIComponent(config.sid)}/IncomingPhoneNumbers.json?PhoneNumber=${encodeURIComponent(config.from)}`,
      {
        headers: {
          authorization: `Basic ${Buffer.from(`${config.sid}:${config.token}`).toString("base64")}`,
        },
      }
    );
    const listBody = await list.json();
    const number = listBody.incoming_phone_numbers?.[0];
    if (!list.ok || !number?.sid) return json(404, { error: "twilio_number_not_found" });

    const params = new URLSearchParams();
    params.set("VoiceUrl", twilioVoiceUrl(event, "inbound"));
    params.set("VoiceMethod", "POST");

    const updated = await twilioRequest(`/IncomingPhoneNumbers/${encodeURIComponent(number.sid)}.json`, params);
    return json(200, {
      ok: true,
      phone_number: updated.phone_number,
      voice_url: updated.voice_url,
      voice_method: updated.voice_method,
    });
  } catch (error) {
    return json(500, { error: "twilio_voice_configure_failed", detail: error.message });
  }
};
