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
  return audio(410, "audio_replies_disabled", { "content-type": "text/plain; charset=utf-8" });
};
