const { generateSpeech, verifySignedAudioRequest } = require("./_elevenlabs_voice");

function audio(statusCode, body, headers = {}) {
  return {
    statusCode,
    headers: {
      "cache-control": "private, max-age=300",
      ...headers,
    },
    body,
    isBase64Encoded: statusCode >= 200 && statusCode < 300,
  };
}

exports.handler = async (event) => {
  if (event.httpMethod !== "GET") {
    return audio(405, "method_not_allowed", { "content-type": "text/plain; charset=utf-8" });
  }

  const verified = verifySignedAudioRequest(event);
  if (!verified.ok) {
    return audio(403, verified.error, { "content-type": "text/plain; charset=utf-8" });
  }

  try {
    const mp3 = await generateSpeech(verified.text);
    return audio(200, mp3.toString("base64"), {
      "content-type": "audio/mpeg",
      "content-length": String(mp3.length),
    });
  } catch (error) {
    return audio(502, error.message || "audio_generation_failed", { "content-type": "text/plain; charset=utf-8" });
  }
};
