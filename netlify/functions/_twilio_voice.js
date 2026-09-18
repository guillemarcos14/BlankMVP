function xml(statusCode, body) {
  return {
    statusCode,
    headers: { "content-type": "application/xml; charset=utf-8" },
    body,
  };
}

function json(statusCode, body) {
  return {
    statusCode,
    headers: { "content-type": "application/json; charset=utf-8" },
    body: JSON.stringify(body),
  };
}

module.exports = {
  json,
  xml,
};
