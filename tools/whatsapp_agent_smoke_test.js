const assert = require("assert");

process.env.OPENAI_API_KEY = "";
process.env.WHATSAPP_VERIFY_TOKEN = "test-token";
delete process.env.WHATSAPP_ACCESS_TOKEN;
delete process.env.WHATSAPP_PHONE_NUMBER_ID;

const { handler } = require("../netlify/functions/whatsapp-agent");

async function verifyWebhook() {
  const response = await handler({
    httpMethod: "GET",
    queryStringParameters: {
      "hub.mode": "subscribe",
      "hub.verify_token": "test-token",
      "hub.challenge": "challenge-ok",
    },
  });
  assert.strictEqual(response.statusCode, 200, response.body);
  assert.strictEqual(response.body, "challenge-ok");
}

async function receiveMessage() {
  const response = await handler({
    httpMethod: "POST",
    headers: {},
    body: JSON.stringify({
      entry: [
        {
          changes: [
            {
              value: {
                messages: [
                  {
                    from: "34600000000",
                    id: "wamid.test",
                    text: { body: "Block Instagram from 10 to 7" },
                  },
                ],
              },
            },
          ],
        },
      ],
    }),
  });
  assert.strictEqual(response.statusCode, 200, response.body);
  const body = JSON.parse(response.body);
  assert.strictEqual(body.ok, true);
  assert.strictEqual(body.received, 1);
  assert.strictEqual(body.results[0].skipped, true);
  assert.strictEqual(body.results[0].reason, "missing_whatsapp_credentials");
}

async function connectMessage() {
  const response = await handler({
    httpMethod: "POST",
    headers: {},
    body: JSON.stringify({
      entry: [
        {
          changes: [
            {
              value: {
                messages: [
                  {
                    from: "34600000000",
                    id: "wamid.connect",
                    text: { body: "CONNECT ABC123" },
                  },
                ],
              },
            },
          ],
        },
      ],
    }),
  });
  assert.strictEqual(response.statusCode, 200, response.body);
  const body = JSON.parse(response.body);
  assert.strictEqual(body.ok, true);
  assert.strictEqual(body.received, 1);
  assert.strictEqual(body.results[0].skipped, true);
  assert.strictEqual(body.results[0].reason, "missing_whatsapp_credentials");
}

async function linkIncludesRequestedApps() {
  process.env.WHATSAPP_ACCESS_TOKEN = "test-access-token";
  process.env.WHATSAPP_PHONE_NUMBER_ID = "test-phone-number-id";
  let outboundText = "";
  const originalFetch = global.fetch;
  global.fetch = async (_url, options) => {
    outboundText = JSON.parse(options.body).text.body;
    return {
      ok: true,
      json: async () => ({ ok: true }),
    };
  };

  try {
    const response = await handler({
      httpMethod: "POST",
      headers: {},
      body: JSON.stringify({
        entry: [
          {
            changes: [
              {
                value: {
                  messages: [
                    {
                      from: "34600000000",
                      id: "wamid.plan",
                      text: { body: "Block Instagram TikTok and X from 10 to 7" },
                    },
                  ],
                },
              },
            ],
          },
        ],
      }),
    });
    assert.strictEqual(response.statusCode, 200, response.body);
    assert.match(outboundText, /blank:\/\/setup-plan\?/);
    assert.match(outboundText, /apps=Instagram%2CTikTok%2CX/);
  } finally {
    global.fetch = originalFetch;
    delete process.env.WHATSAPP_ACCESS_TOKEN;
    delete process.env.WHATSAPP_PHONE_NUMBER_ID;
  }
}

(async () => {
  await verifyWebhook();
  await receiveMessage();
  await connectMessage();
  await linkIncludesRequestedApps();
  console.log("whatsapp-agent smoke tests passed");
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
