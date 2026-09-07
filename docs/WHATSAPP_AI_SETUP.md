# Blanked AI WhatsApp Setup

## Netlify function

Webhook URL:

```txt
https://getblank.netlify.app/.netlify/functions/whatsapp-agent
```

## Netlify environment variables

```txt
WHATSAPP_VERIFY_TOKEN=choose-a-long-random-token
WHATSAPP_ACCESS_TOKEN=meta-permanent-or-system-user-token
WHATSAPP_PHONE_NUMBER_ID=meta-phone-number-id
WHATSAPP_APP_SECRET=meta-app-secret
WHATSAPP_GRAPH_API_VERSION=v26.0
BLANKED_APP_DEEP_LINK_SCHEME=blank

TWILIO_ACCOUNT_SID=replace-me
TWILIO_AUTH_TOKEN=replace-me
TWILIO_FROM_NUMBER=+15550000000
# Optional instead of TWILIO_FROM_NUMBER:
TWILIO_MESSAGING_SERVICE_SID=MGxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

## iOS build settings

Set the official WhatsApp number without `+`, spaces, or dashes:

```txt
BLANK_WHATSAPP_PHONE_NUMBER=34600000000
```

Set the official SMS number in dialable format:

```txt
BLANK_SMS_PHONE_NUMBER=+34600000000
```

## Product contract

- WhatsApp receives user messages and sends them to `blanked-agent`.
- WhatsApp replies with guidance and, when there is an executable action, a `blank://...` link.
- iOS is still the authority for Screen Time actions.
- `/.netlify/functions/assistant-channel` stores the user's preferred BAI interface (`whatsapp` or `sms`) by `CONNECT <code>` and sends proactive BAI alerts through the selected channel after the external thread has sent `CONNECT`.
- SMS uses `/.netlify/functions/sms-agent` as an inbound SMS webhook. It accepts Twilio-style form posts, sends the message to `blanked-agent`, replies with TwiML plus a `blank://...` action link when needed, and supports outbound via Twilio credentials.
- Users can send `stop` or `disconnect` in WhatsApp to pause this channel.

## Autonomous checks

Run before connecting the real Meta number:

```powershell
node --check netlify/functions/whatsapp-agent.js
node --check netlify/functions/sms-agent.js
node --check netlify/functions/assistant-channel.js
node --check netlify/functions/_assistant_channel.js
node --check netlify/functions/funnel-event.js
node tools/whatsapp_agent_smoke_test.js
```

Expected result: syntax checks return no output and the smoke test prints `whatsapp-agent smoke tests passed`.

## Manual E2E checklist

- Before the SIM arrives, use Meta's test WhatsApp number to validate webhook verification and outbound replies against `whatsapp-agent`.
- The real company number cannot be attached to WhatsApp Business until the verification SMS/call can be received.
- Configure the Netlify WhatsApp variables above.
- In Meta Developers, set the webhook callback URL to `https://getblank.netlify.app/.netlify/functions/whatsapp-agent`.
- Use the same `WHATSAPP_VERIFY_TOKEN` in Meta and Netlify.
- Configure Xcode build settings with `BLANK_WHATSAPP_PHONE_NUMBER` and `BLANK_SMS_PHONE_NUMBER`.
- Configure Twilio credentials in Netlify if SMS outbound should be active.
- On iPhone, open Blanked, tap `Assistant`, then `Connect WhatsApp`.
- Confirm WhatsApp opens with `CONNECT <code>`.
- Send the message and confirm Blanked replies `Connected`.
- For SMS, configure the SMS provider inbound webhook to `https://getblank.netlify.app/.netlify/functions/sms-agent`, then tap `Connect SMS` in Blanked and send `CONNECT <code>`.
- Send `Block Instagram TikTok and X from 10 to 7`.
- Confirm the reply includes a `blank://setup-plan?...apps=Instagram%2CTikTok%2CX` link.
- Trigger a BAI proactive alert and confirm `assistant-channel` attempts delivery through the selected channel.
- Tap the link, confirm Blanked opens the native app picker, and select the apps.
