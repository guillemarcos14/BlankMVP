# Blank Play Console Setup Values

Use these values to complete the first Google Play Console setup for Blank.

## Main Store Listing

App name:

```text
Blank
```

Short description:

```text
Block distracting apps with a physical NFC tag.
```

Full description:

```text
Blank is a physical commitment tool for digital focus.

Choose the apps you want to block, pair a small NFC tag, and tap the tag when you want to enter Blank mode. While Blank mode is active, selected apps are blocked until you tap the paired tag again.

Blank is built for focus sessions, studying, deep work, and reducing late-night scrolling.

Privacy-first beta:
- Your paired tag and selected apps stay on your device.
- Blank does not read messages, passwords, screen contents, or notifications.
- Android Accessibility is used only to detect foreground app changes and show the block screen for apps you selected.
```

Category:

```text
Productivity
```

Tags:

```text
Productivity, Focus, Digital wellbeing
```

Contact email:

```text
TODO: add the public support email before submitting app setup.
```

Website:

```text
TODO: add landing page URL if available.
```

Privacy policy URL:

```text
TODO: publish PRIVACY_POLICY_DRAFT.md at a stable public URL and paste it here.
```

## App Content

Ads:

```text
No, my app does not contain ads.
```

App access:

```text
All functionality is available without an account. Reviewers need a physical Android device with NFC and a writable NFC tag.
```

Target audience:

```text
18 and over
```

News app:

```text
No
```

Health app:

```text
No
```

Government app:

```text
No
```

Financial features:

```text
No financial features
```

## Data Safety

Current beta behavior:

```text
Blank does not transmit user data off the device in this MVP. The app stores the paired NFC tag ID, selected blocked app package names, setup state, active Blank mode state, and activation time locally on the device.
```

Collection:

```text
No user data is collected, because "collection" means transmitting data off the user's device. This beta does not send Blank data to a server or third party.
```

Sharing:

```text
No user data is shared.
```

Security practices:

```text
Data is stored locally on the user's device. Users can reset the paired NFC tag from the app.
```

Note: if Firebase, Sentry, analytics, crash reporting, backend sync, or support logs are added later, update this section before the next release.

## Accessibility API Declaration

Is the app an accessibility tool?

```text
No
```

Why does Blank use AccessibilityService?

```text
Blank uses Android Accessibility events only to detect when the foreground app changes. If Blank mode is active and the foreground package is in the user's selected blocked list, Blank opens its blocking screen.

Blank does not read screen text, typed text, passwords, messages, notifications, contacts, browsing history, media, or form contents. Blank stores selected package names, paired NFC tag ID, setup state, and current Blank mode state locally on the device.
```

Reviewer instructions:

```text
Use a physical Android phone with NFC and a writable NFC tag.

1. Install and open Blank.
2. Select one or more distracting apps to block.
3. Pair an NFC tag during setup.
4. Enable the Blank Accessibility Service when prompted.
5. Activate Blank mode.
6. Open a selected blocked app and confirm that Blank shows the block screen.
7. Tap the paired NFC tag again to deactivate Blank mode.

Blank does not require an account, login credentials, or server access.
```

## Internal Test Release Notes

```xml
<es-ES>
Primera beta interna de Blank para pruebas cerradas. Incluye el flujo inicial de configuración, selección de apps bloqueadas y activación mediante NFC.
</es-ES>
```

