const { json } = require("./_twilio_voice");
const { requireMethod } = require("./_membership");

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;

  return json(410, { error: "voice_replies_disabled" });
};
