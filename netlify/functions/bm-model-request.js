"use strict";

const ERROR_NAMES = new Set(["Error", "TimeoutError", "AbortError", "TypeError", "SyntaxError", "RangeError"]);
const CAUSE_CODES = new Set([
  "UND_ERR_CONNECT_TIMEOUT", "UND_ERR_HEADERS_TIMEOUT", "UND_ERR_BODY_TIMEOUT",
  "UND_ERR_SOCKET", "UND_ERR_ABORTED", "UND_ERR_RESPONSE_STATUS_CODE",
  "ECONNRESET", "ECONNREFUSED", "ETIMEDOUT", "ENOTFOUND", "EAI_AGAIN", "EPIPE",
]);

function nonnegativeNumber(value) {
  if (value == null || value === "") return null;
  const result = Number(value);
  return Number.isFinite(result) && result >= 0 ? result : null;
}

function usageCounts(usage) {
  const values = {
    input_tokens: usage?.input_tokens,
    output_tokens: usage?.output_tokens,
    total_tokens: usage?.total_tokens,
    cached_input_tokens: usage?.input_tokens_details?.cached_tokens,
    reasoning_tokens: usage?.output_tokens_details?.reasoning_tokens,
  };
  return Object.fromEntries(Object.entries(values).filter(([, value]) => Number.isSafeInteger(value) && value >= 0));
}

// Metrics contain only allowlisted transport facts. Never retain request bodies,
// generated text, credentials, provider error bodies or arbitrary error messages.
async function readModelJson({ request, timeoutMs, fetchImpl = fetch, errorPrefix }) {
  const started = Date.now();
  let headersAt = null;
  const metrics = { phase: "headers", budget_ms: timeoutMs, elapsed_ms: 0 };
  try {
    const response = await fetchImpl("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: { authorization: `Bearer ${process.env.OPENAI_API_KEY}`, "content-type": "application/json" },
      body: JSON.stringify(request),
      // Native fetch retains this signal while consuming the response body.
      signal: AbortSignal.timeout(timeoutMs),
    });
    headersAt = Date.now();
    metrics.headers_ms = Math.max(0, headersAt - started);
    if (Number.isInteger(response.status) && response.status >= 100 && response.status <= 599) metrics.http_status = response.status;
    const requestId = response.headers?.get?.("x-request-id");
    if (typeof requestId === "string" && /^[A-Za-z0-9_-]{1,159}$/.test(requestId)) metrics.request_id = requestId;
    const processingMs = nonnegativeNumber(response.headers?.get?.("openai-processing-ms"));
    if (processingMs != null) metrics.processing_ms = processingMs;
    if (!response.ok) {
      // Release the connection without consuming or copying the error payload.
      // A cancellation error must not hide the original HTTP failure.
      try { Promise.resolve(response.body?.cancel()).catch(() => {}); } catch (_) {}
      throw new Error(`${errorPrefix}_http_${response.status}`);
    }
    metrics.phase = "body";
    const body = await response.json();
    metrics.body_ms = Math.max(0, Date.now() - headersAt);
    metrics.phase = "complete";
    metrics.elapsed_ms = Math.max(0, Date.now() - started);
    const usage = usageCounts(body?.usage);
    if (Object.keys(usage).length) metrics.usage = usage;
    return { body, metrics };
  } catch (caught) {
    const error = caught && typeof caught === "object" ? caught : new Error("model_request_failed");
    metrics.elapsed_ms = Math.max(0, Date.now() - started);
    if (headersAt != null && metrics.phase === "body") metrics.body_ms = Math.max(0, Date.now() - headersAt);
    metrics.error_name = ERROR_NAMES.has(error.name) ? error.name : "Error";
    const causeCode = error.cause?.code || error.code;
    if (CAUSE_CODES.has(causeCode)) metrics.cause_code = causeCode;
    error.model_request_metrics = { ...metrics };
    throw error;
  }
}

module.exports = { readModelJson };
