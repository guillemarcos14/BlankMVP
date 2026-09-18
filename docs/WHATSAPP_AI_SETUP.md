# BM WhatsApp/SMS Setup

## Netlify function

Webhook URL:

```txt
https://getblank.netlify.app/.netlify/functions/whatsapp-agent
```

SMS webhook URL:

```txt
https://getblank.netlify.app/.netlify/functions/sms-agent
```

## Netlify environment variables

```txt
WHATSAPP_VERIFY_TOKEN=choose-a-long-random-token
WHATSAPP_ACCESS_TOKEN=meta-permanent-or-system-user-token
WHATSAPP_PHONE_NUMBER_ID=meta-phone-number-id
WHATSAPP_APP_SECRET=meta-app-secret
WHATSAPP_GRAPH_API_VERSION=v26.0
BLANKED_APP_DEEP_LINK_SCHEME=blank
BLANKED_PUBLIC_APP_LINK_BASE=https://getblank.netlify.app
BLANKMIND_APP_DOWNLOAD_URL=https://apps.apple.com/es/app/id6789519152

TWILIO_ACCOUNT_SID=replace-me
TWILIO_AUTH_TOKEN=replace-me
TWILIO_FROM_NUMBER=+13478366767
TWILIO_WHATSAPP_FROM_NUMBER=+13478366767
# The exact public webhook URL used to calculate Twilio signatures.
TWILIO_WEBHOOK_URL=https://getblank.netlify.app/.netlify/functions/sms-agent
TWILIO_VALIDATE_WEBHOOK_SIGNATURE=true
# Optional approved Twilio WhatsApp review/action templates.
# TWILIO_WHATSAPP_ACTION_CONTENT_SID=HX...
# TWILIO_WHATSAPP_REVIEW_CONTENT_SID=HX...
# TWILIO_WHATSAPP_REVIEW_TEMPLATE_ENABLED=true
# Five approved Utility templates, comma-separated or individually configured.
TWILIO_WHATSAPP_PROACTIVE_CONTENT_SIDS=HX...,HX...,HX...,HX...,HX...
# Optional individual form: TWILIO_WHATSAPP_PROACTIVE_CONTENT_SID_1 through _5
# Optional UTC quiet-hours guard. Defaults to 21:00-08:00 UTC.
ASSISTANT_PROACTIVE_QUIET_START_UTC=21
ASSISTANT_PROACTIVE_QUIET_END_UTC=8
# Optional instead of TWILIO_FROM_NUMBER:
TWILIO_MESSAGING_SERVICE_SID=MGxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# Voice replies and phone calls are disabled. Audio inputs are transcribed and answered with text.
```

## iOS build settings

Set the official WhatsApp number without `+`, spaces, or dashes:

```txt
BLANK_WHATSAPP_PHONE_NUMBER=13478366767
```

Set the official SMS number in dialable format:

```txt
BLANK_SMS_PHONE_NUMBER=+13478366767
```

## Product contract

- WhatsApp receives user messages and sends them to `blanked-agent`.
- Both channels keep the same short conversational shape: up to eight recent turns, with a two-hour expiry for follow-up context. Long-lived facts (selected apps, risk windows and user context) remain separate from that short-term thread.
- Meta `message.id` and Twilio `MessageSid` are claimed before planning so provider retries and concurrent duplicate deliveries cannot both enter the planner. Migration `014_assistant_inbound_idempotency.sql` provides the unique reservation plus a five-minute lease; the older event-store marker remains as a compatibility fallback during rollout.
- WhatsApp replies with guidance and, when there is an executable action, uses a review-and-confirm link. A Twilio CTA template is optional through `TWILIO_WHATSAPP_REVIEW_CONTENT_SID`; set `TWILIO_WHATSAPP_REVIEW_TEMPLATE_ENABLED=true` only after verifying that its button label is exactly `Review and confirm`. Otherwise BM sends the precise text link and never falls back to a stale `Open Blankmind` button.
- The WhatsApp button should point to a Universal Link such as `https://blankmind.ai/open?action=start-focus...`; keep `BLANKED_PUBLIC_APP_LINK_BASE` aligned with the public `blankmind.ai` domain once `/open` and AASA are served there.
- Twilio WhatsApp/SMS can receive audio inputs, transcribe them with OpenAI, and answer with BM text. BM never attaches audio or generates a spoken reply.
- iOS is still the authority for Screen Time actions.
- `/.netlify/functions/assistant-channel` stores the user's preferred BM interface (`whatsapp` or `sms`) by `CONNECT <code>` and sends proactive BM alerts through the selected channel after the external thread has sent `CONNECT`.
- When the iOS app is opened or returns to the foreground, it syncs a minimal `app_presence` heartbeat. BM treats it as `recently_seen` for 24 hours, then `stale`, and never claims that a stale or unseen app is definitely uninstalled. On WhatsApp/SMS, executable actions are withheld until a recent heartbeat exists; the reply then says naturally that Blankmind must be opened and includes `BLANKMIND_APP_DOWNLOAD_URL` as a conditional download link.
- Proactive WhatsApp alerts are only sent when BM supplies a meaningful update. The backend checks that the selected SID is actually `Approved` in Twilio, enforces one delivery per 24 hours, suppresses duplicate updates for the same user, respects quiet hours, rotates the five templates, and sends the full update only after the user taps/replies positively.
- SMS uses `/.netlify/functions/sms-agent` as an inbound SMS webhook. It accepts Twilio-style form posts, sends the message to `blanked-agent`, replies first with commands like `Reply BLOCK` instead of raw URLs, stores the pending action, and sends the Universal Link only after the user replies with `BLOCK`, `START` or `OPEN`.
- Users can send `stop` or `disconnect` in WhatsApp to pause this channel.

## Autonomous checks

Run before connecting the real Meta number:

```powershell
node --check netlify/functions/whatsapp-agent.js
node --check netlify/functions/sms-agent.js
node --check netlify/functions/_twilio_voice.js
node --check netlify/functions/elevenlabs-bai-tool.js
node --check netlify/functions/assistant-channel.js
node --check netlify/functions/_assistant_channel.js
node --check netlify/functions/funnel-event.js
node tools/whatsapp_agent_smoke_test.js
node tools/sms_agent_voice_smoke_test.js
node tools/bai_call_smoke_test.js
```

Expected result: syntax checks return no output and the smoke test prints `whatsapp-agent smoke tests passed`.

Audio-input smoke expected result: `sms-agent audio input smoke tests passed`.

## Manual E2E checklist

- Before the SIM arrives, use Meta's test WhatsApp number to validate webhook verification and outbound replies against `whatsapp-agent`.
- The real company number cannot be attached to WhatsApp Business until the verification SMS/call can be received.
- In Twilio, buy an SMS-capable phone number.
- In Twilio, configure the number's Messaging webhook: `A message comes in` -> `Webhook` -> `POST` -> `https://getblank.netlify.app/.netlify/functions/sms-agent`.
- Keep `TWILIO_WEBHOOK_URL` byte-for-byte equal to the URL configured in Twilio; production rejects unsigned or incorrectly signed requests.
- In Netlify, add `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN` and either `TWILIO_FROM_NUMBER` or `TWILIO_MESSAGING_SERVICE_SID`.
- Apply `supabase/migrations/014_assistant_inbound_idempotency.sql` before enabling the production webhook claims.
- For WhatsApp senders registered through Twilio, add `TWILIO_WHATSAPP_FROM_NUMBER`.
- Set `BLANK_SMS_PHONE_NUMBER` in the iOS build settings to the Twilio number in dialable format.
- Send `CONNECT <code>` from a real phone to the Twilio number and confirm Twilio receives TwiML `Connected`.
- Send a proactive test through `assistant-channel`; `delivered` must be `true`. If it returns `missing_sms_credentials`, Netlify has not received the Twilio variables.
- Configure the Netlify WhatsApp variables above.
- In Meta Developers, set the webhook callback URL to `https://getblank.netlify.app/.netlify/functions/whatsapp-agent`.
- Use the same `WHATSAPP_VERIFY_TOKEN` in Meta and Netlify.
- Keep `WHATSAPP_APP_SECRET` configured in Netlify; production rejects Meta callbacks without a valid `X-Hub-Signature-256`.
- Configure Xcode build settings with `BLANK_WHATSAPP_PHONE_NUMBER` and `BLANK_SMS_PHONE_NUMBER`.
- Configure Twilio credentials in Netlify if SMS outbound should be active.
- On iPhone, open Blankmind, tap `Assistant`, then `Connect WhatsApp`.
- Confirm WhatsApp opens with `CONNECT <code>`.
- Send the message and confirm Blankmind replies `Connected`.
- For SMS, configure the SMS provider inbound webhook to `https://getblank.netlify.app/.netlify/functions/sms-agent`, then tap `Connect SMS` in Blankmind and send `CONNECT <code>`.
- Send `Block Instagram TikTok and X from 10 to 7`.
- In WhatsApp, confirm the reply says `Review and confirm in Blankmind` and never uses an obsolete action label.
- In SMS, confirm the first reply says `Reply BLOCK` without a raw URL; reply `BLOCK` and confirm the next SMS includes the Universal Link.
- Send a WhatsApp audio note or a text asking for a voice note.
- Confirm the audio is interpreted and the reply is text-only, with no TwiML `<Media>` element.
- Trigger a BM proactive alert and confirm `assistant-channel` attempts delivery through the selected channel.
- Tap the link, confirm Blankmind opens the native app picker, and select the apps.

## Voice status

Voice replies, ElevenLabs TTS, and phone calls are disabled by product decision. The endpoints remain guarded and return `410 voice_replies_disabled`; re-enable them only after an explicit product decision.
