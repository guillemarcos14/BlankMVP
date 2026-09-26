# Production app activation

The public production entry point is the iOS app. The website can continue to run Early Access independently. A person who joined the waitlist uses the same app flow when installing from the App Store; the SMS OTP can recover the existing phone identity.

1. First launch opens the three-step `SetupView`. Its first screen embeds `AppPhoneSignInSheet`: the user consents, requests a phone OTP by SMS, verifies it and calls `app-handoff?action=claim_identity` for this installation. Phone verification does not claim that WhatsApp is connected.
2. The second screen requests Screen Time authorization, a nonempty canonical distraction selection and notification permission. All three must be ready before advancing.
3. The third screen registers the WhatsApp preference and current selection context before opening a prepared `CONNECT <code>` message. Only an inbound WhatsApp message from the verified E.164 phone may attach the channel. The connection replies with a short status, not a new welcome sequence.
4. Returning to the app checks the channel connection, notification authorization, Screen Time authorization, nonempty selection and the server's actual APNs registration response. `complete_onboarding` checks the same server state and sends the ready message once. The onboarding then enters Home without automatically starting a block.
5. A later blocking request still follows the existing durable pending-action and iOS confirmation lifecycle. The app reports verified execution only after native application succeeds.

`BM_FINAL_APP_LINKED_ROUTING_ENABLED=true` enables Final routing for WhatsApp senders with an app installation and either a matching inbound CONNECT code or an already verified channel connection. With the flag unset, the existing exact QA phone continues to use Final and all other WhatsApp/SMS senders continue through Early Access. Set the flag only in the Backend Cloud release after the iOS build and a physical activation/block test. The 50/50 repository harness and iOS simulator CI build do not prove APNs delivery on a device.
