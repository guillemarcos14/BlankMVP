# Blanked AI WhatsApp Setup

## Netlify function

Webhook URL:

```txt
https://getblank.netlify.app/.netlify/functions/whatsapp-agent
```

## Required environment variables

```txt
WHATSAPP_VERIFY_TOKEN=choose-a-long-random-token
WHATSAPP_ACCESS_TOKEN=meta-permanent-or-system-user-token
WHATSAPP_PHONE_NUMBER_ID=meta-phone-number-id
WHATSAPP_APP_SECRET=meta-app-secret
WHATSAPP_GRAPH_API_VERSION=v26.0
BLANKED_APP_DEEP_LINK_SCHEME=blank
```

## iOS build setting

Set the official WhatsApp number without `+`, spaces, or dashes:

```txt
BLANK_WHATSAPP_PHONE_NUMBER=34600000000
```

## Product contract

- WhatsApp receives user messages and sends them to `blanked-agent`.
- WhatsApp replies with guidance and, when there is an executable action, a `blank://...` link.
- iOS is still the authority for Screen Time actions.
- Users can send `stop` or `disconnect` in WhatsApp to pause this channel.
