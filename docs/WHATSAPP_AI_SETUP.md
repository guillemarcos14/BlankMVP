# Blanked AI WhatsApp/SMS Setup

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

TWILIO_ACCOUNT_SID=replace-me
TWILIO_AUTH_TOKEN=replace-me
TWILIO_FROM_NUMBER=+13478366767
TWILIO_WHATSAPP_FROM_NUMBER=+13478366767
# Optional instead of TWILIO_FROM_NUMBER:
TWILIO_MESSAGING_SERVICE_SID=MGxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# Optional ElevenLabs voice layer for premium WhatsApp audio replies.
# Without these variables, WhatsApp/SMS stay text-only.
ELEVENLABS_API_KEY=replace-me
ELEVENLABS_VOICE_ID=replace-me
ELEVENLABS_TTS_MODEL=eleven_multilingual_v2
ELEVENLABS_OUTPUT_FORMAT=mp3_44100_128
ELEVENLABS_TTS_MAX_CHARS=420
ELEVENLABS_AUDIO_URL_TTL_SECONDS=600
ELEVENLABS_AUDIO_SIGNING_SECRET=replace-me-long-random-secret

# Optional ElevenLabs Conversational AI call layer.
ELEVENLABS_CONVAI_API_KEY=replace-me
ELEVENLABS_AGENT_ID=agent_xxxxxxxxxxxxxxxxxxxxxxxxxxxx
BAI_CALL_ADMIN_SECRET=replace-me-long-random-secret
TWILIO_VOICE_FROM_NUMBER=+13478366767
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
- WhatsApp replies with guidance and, when there is an executable action, a `blank://...` link.
- Twilio WhatsApp can receive voice notes, transcribe them with OpenAI, answer with BAI text, and attach an ElevenLabs-generated MP3 when the inbound message was audio or explicitly asks for voice.
- iOS is still the authority for Screen Time actions.
- `/.netlify/functions/assistant-channel` stores the user's preferred BAI interface (`whatsapp` or `sms`) by `CONNECT <code>` and sends proactive BAI alerts through the selected channel after the external thread has sent `CONNECT`.
- SMS uses `/.netlify/functions/sms-agent` as an inbound SMS webhook. It accepts Twilio-style form posts, sends the message to `blanked-agent`, replies with TwiML plus a `blank://...` action link when needed, and supports outbound via Twilio credentials.
- Users can send `stop` or `disconnect` in WhatsApp to pause this channel.

## Autonomous checks

Run before connecting the real Meta number:

```powershell
node --check netlify/functions/whatsapp-agent.js
node --check netlify/functions/sms-agent.js
node --check netlify/functions/assistant-audio.js
node --check netlify/functions/_elevenlabs_voice.js
node --check netlify/functions/_twilio_voice.js
node --check netlify/functions/elevenlabs-bai-tool.js
node --check netlify/functions/bai-call-twiml.js
node --check netlify/functions/bai-call.js
node --check netlify/functions/twilio-voice-configure.js
node --check netlify/functions/assistant-channel.js
node --check netlify/functions/_assistant_channel.js
node --check netlify/functions/funnel-event.js
node tools/whatsapp_agent_smoke_test.js
node tools/sms_agent_voice_smoke_test.js
node tools/bai_call_smoke_test.js
```

Expected result: syntax checks return no output and the smoke test prints `whatsapp-agent smoke tests passed`.

Voice smoke expected result: `sms-agent voice smoke tests passed`.

## Manual E2E checklist

- Before the SIM arrives, use Meta's test WhatsApp number to validate webhook verification and outbound replies against `whatsapp-agent`.
- The real company number cannot be attached to WhatsApp Business until the verification SMS/call can be received.
- In Twilio, buy an SMS-capable phone number.
- In Twilio, configure the number's Messaging webhook: `A message comes in` -> `Webhook` -> `POST` -> `https://getblank.netlify.app/.netlify/functions/sms-agent`.
- In Netlify, add `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN` and either `TWILIO_FROM_NUMBER` or `TWILIO_MESSAGING_SERVICE_SID`.
- For WhatsApp senders registered through Twilio, add `TWILIO_WHATSAPP_FROM_NUMBER`.
- Set `BLANK_SMS_PHONE_NUMBER` in the iOS build settings to the Twilio number in dialable format.
- Send `CONNECT <code>` from a real phone to the Twilio number and confirm Twilio receives TwiML `Connected`.
- Send a proactive test through `assistant-channel`; `delivered` must be `true`. If it returns `missing_sms_credentials`, Netlify has not received the Twilio variables.
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
- Send a WhatsApp voice note or a text asking for a voice note.
- Confirm Twilio receives TwiML with `<Media>` pointing to `/.netlify/functions/assistant-audio`.
- Confirm the WhatsApp reply includes playable audio plus the text/deep link fallback.
- Trigger a BAI proactive alert and confirm `assistant-channel` attempts delivery through the selected channel.
- Tap the link, confirm Blanked opens the native app picker, and select the apps.

## ElevenLabs calls

BAI calls use Twilio for the phone number and ElevenLabs Agents for the spoken conversation.
Blanked remains the authority for reasoning through:

```txt
https://getblank.netlify.app/.netlify/functions/elevenlabs-bai-tool
```

Runtime endpoints:

```txt
POST https://getblank.netlify.app/.netlify/functions/twilio-voice-configure
POST https://getblank.netlify.app/.netlify/functions/bai-call-twiml
POST https://getblank.netlify.app/.netlify/functions/bai-call
```

`twilio-voice-configure` is admin-protected by `BAI_CALL_ADMIN_SECRET` and sets the Twilio number's inbound voice webhook.
`bai-call-twiml` is the Twilio voice webhook and registers each call with ElevenLabs.
`bai-call` is admin-protected and can start outbound calls when explicitly requested.
