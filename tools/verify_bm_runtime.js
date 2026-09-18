"use strict";

function valueAfter(flag) {
  const index = process.argv.indexOf(flag);
  return index >= 0 ? String(process.argv[index + 1] || "") : "";
}

async function main() {
  const endpoint = valueAfter("--url");
  const expected = valueAfter("--expected");
  if (!endpoint || !expected) throw new Error("--url and --expected are required");

  for (let attempt = 1; attempt <= 5; attempt += 1) {
    const url = new URL(endpoint);
    url.searchParams.set("bm_runtime", "1");
    url.searchParams.set("nonce", `${Date.now()}-${attempt}`);
    const response = await fetch(url, { headers: { "cache-control": "no-store" } });
    const runtime = response.headers.get("x-bm-runtime-contract") || "";
    if (!response.ok || runtime !== expected) {
      throw new Error(`runtime probe ${attempt} failed: status=${response.status} expected=${expected} actual=${runtime || "missing"}`);
    }
  }
  console.log(`BM runtime verified: ${expected} (5/5)`);
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
