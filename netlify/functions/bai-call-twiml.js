const { parseFormBody, registerElevenLabsCall, xml } = require("./_twilio_voice");

exports.handler = async (event) => {
  if (event.httpMethod !== "POST") {
    return xml(405, "<Response><Reject/></Response>");
  }

  const form = parseFormBody(event);
  const direction = event.queryStringParameters?.direction || form.Direction || "inbound";
  const fromNumber = form.From || form.Caller || "";
  const toNumber = form.To || form.Called || "";

  try {
    const twiml = await registerElevenLabsCall({ fromNumber, toNumber, direction });
    return xml(200, twiml);
  } catch (error) {
    return xml(
      200,
      `<Response><Say>BAI voice is not available right now.</Say><Hangup/></Response><!-- ${String(error.message || "call_failed").replace(/--/g, "")} -->`
    );
  }
};
