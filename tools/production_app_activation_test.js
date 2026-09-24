const assert = require("assert");
const { isFinalAppLinkedWhatsApp } = require("../netlify/functions/_bm_final_qa_access");

const phone = "+34658991584";
const code = "ABCDEFGH23";
const originalFetch = global.fetch;
const originalFlag = process.env.BM_FINAL_APP_LINKED_ROUTING_ENABLED;
const originalUrl = process.env.SUPABASE_URL;
const originalKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

async function main() {
  let installed = true;
  let connected = false;
  let fetchCount = 0;
  process.env.SUPABASE_URL = "https://supabase.test";
  process.env.SUPABASE_SERVICE_ROLE_KEY = "test-key";
  global.fetch = async (url) => {
    fetchCount += 1;
    const rows = String(url).includes("blankmind_identity_links")
      ? [{ phone_e164: phone, app_install_id: installed ? "installation-1" : null, assistant_connect_code: code }]
      : connected ? [{ payload: { properties: { channel: "whatsapp", channel_user: phone, connect_code: code } } }] : [];
    return { ok: true, status: 200, text: async () => JSON.stringify(rows), json: async () => rows };
  };

  delete process.env.BM_FINAL_APP_LINKED_ROUTING_ENABLED;
  assert.strictEqual(await isFinalAppLinkedWhatsApp("whatsapp", phone, `CONNECT ${code}`), false);
  assert.strictEqual(fetchCount, 0, "public routing stays disabled by default");

  process.env.BM_FINAL_APP_LINKED_ROUTING_ENABLED = "true";
  assert.strictEqual(await isFinalAppLinkedWhatsApp("sms", phone, `CONNECT ${code}`), false);
  assert.strictEqual(await isFinalAppLinkedWhatsApp("whatsapp", phone, "Hola"), false);
  assert.strictEqual(await isFinalAppLinkedWhatsApp("whatsapp", phone, "CONNECT WRONGCODE"), false);
  installed = false;
  assert.strictEqual(await isFinalAppLinkedWhatsApp("whatsapp", phone, `CONNECT ${code}`), false);
  installed = true;
  assert.strictEqual(await isFinalAppLinkedWhatsApp("whatsapp", phone, `CONNECT ${code}`), true);
  connected = true;
  assert.strictEqual(await isFinalAppLinkedWhatsApp("whatsapp", phone, "Hola"), true);
  console.log("production app activation routing: ok");
}

main().catch((error) => { console.error(error); process.exitCode = 1; }).finally(() => {
  global.fetch = originalFetch;
  if (originalFlag === undefined) delete process.env.BM_FINAL_APP_LINKED_ROUTING_ENABLED;
  else process.env.BM_FINAL_APP_LINKED_ROUTING_ENABLED = originalFlag;
  if (originalUrl === undefined) delete process.env.SUPABASE_URL;
  else process.env.SUPABASE_URL = originalUrl;
  if (originalKey === undefined) delete process.env.SUPABASE_SERVICE_ROLE_KEY;
  else process.env.SUPABASE_SERVICE_ROLE_KEY = originalKey;
});
