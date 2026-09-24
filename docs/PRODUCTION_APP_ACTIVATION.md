# Production app activation

The public production entry point is the iOS app. The website can continue to run Early Access independently. A person who joined the waitlist uses the same app flow when installing from the App Store; the SMS OTP can recover the existing phone identity.

1. First launch opens `SetupView`. Screen Time authorization and a nonempty canonical distraction selection are required. Notification permission can be deferred at its prompt but must be granted before assistant activation.
2. `AppPhoneSignInSheet` requests a phone OTP by SMS, verifies it and calls `app-handoff?action=claim_identity` for this installation. Phone verification does not claim that WhatsApp is connected.
3. The app registers the WhatsApp preference and current selection context before opening a prepared `CONNECT <code>` message. Only an inbound WhatsApp message from the verified E.164 phone may attach the channel. The connection replies with a short status, not a new welcome sequence.
4. Returning to the app checks the channel connection, notification authorization, Screen Time authorization, nonempty selection and the server's actual APNs registration response. `complete_onboarding` checks the same server state and sends the ready message once. The onboarding then enters Home without automatically starting a block.
5. A later blocking request still follows the existing durable pending-action and iOS confirmation lifecycle. The app reports verified execution only after native application succeeds.

`BM_FINAL_APP_LINKED_ROUTING_ENABLED=true` enables Final routing for WhatsApp senders with an app installation and either a matching inbound CONNECT code or an already verified channel connection. With the flag unset, the existing exact QA phone continues to use Final and all other WhatsApp/SMS senders continue through Early Access. Set the flag only in the Backend Cloud release after the iOS build and a physical activation/block test. Do not infer public readiness from the 50/50 repository harness; it cannot compile iOS or prove APNs delivery on a device.
