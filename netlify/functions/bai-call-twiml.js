const { xml } = require("./_twilio_voice");

exports.handler = async (event) => {
  if (event.httpMethod !== "POST") {
    return xml(405, "<Response><Reject/></Response>");
  }

  return xml(410, "<Response><Hangup/></Response>");
};
