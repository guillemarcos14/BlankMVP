# Blank iOS App Store Prep

Use this file to keep the App Store Connect values, privacy answers, review notes, asset status, and first Xcode build checklist in one place.

## Current Apple Developer State

As of 2026-07-09, the Apple Developer Program membership is active.

Team:

```text
GUILLEM ARCOS GONZALEZ - GS54UV79RG
```

Created in Certificates, Identifiers & Profiles:

- `com.blanknfc.app.ios` (`Blank iOS`)
- `com.blanknfc.app.ios.deviceactivity` (`Blank Device Activity Monitor`)

Enabled or requested:

- NFC Tag Reading enabled on the main App ID.
- Family Controls (Development) enabled on the app IDs.
- Family Controls App and Website Usage enabled on the app IDs.
- Family Controls (Distribution) request submitted to Apple on 2026-07-09. Apple showed: `Thank you for your submission. We'll review your request and contact you soon with a status update.`

Still blocked until Apple approves Family Controls distribution:

- TestFlight/App Store distribution with the production Family Controls entitlement.

Still needs macOS/Xcode:

- Code signing validation with Team ID `GS54UV79RG`.
- Archive and upload to App Store Connect.
- Physical iPhone validation for NFC and ManagedSettings shielding.

## App Identity

App name:

```text
Blank
```

Primary bundle ID:

```text
com.blanknfc.app.ios
```

Device Activity Monitor extension bundle ID:

```text
com.blanknfc.app.ios.deviceactivity
```

SKU:

```text
blank-ios-001
```

Apple platforms:

```text
iPhone only for first release
```

Version:

```text
1.0
```

Build:

```text
1
```

Category:

```text
Productivity
```

Secondary category:

```text
Lifestyle
```

Age rating baseline:

```text
4+
```

## Store Listing Copy

Subtitle:

```text
Focus with a physical NFC tag
```

Promotional text:

```text
Blank helps you block distracting apps with a physical NFC tag, so the way out is not just another button on your phone.
```

Description:

```text
Blank is a physical commitment tool for digital focus.

Choose the apps, categories, or web domains you want to protect, pair a small NFC tag, and start Blank when you want a real focus session. While Blank is active, iPhone shields the selected distractions with Apple's Screen Time APIs. Scan the paired tag again to exit.

Blank is built for studying, deep work, late-night scrolling limits, and any moment when you want friction between you and the apps you usually open automatically.

Privacy-first:
- Your paired NFC tag and Screen Time selections stay on your device.
- Blank does not read messages, passwords, screen contents, contacts, notifications, or browsing history.
- Blank does not require an account.
- Blank uses FamilyControls and ManagedSettings on iPhone, not screen scraping.
```

Keywords:

```text
focus, app blocker, nfc, screen time, productivity, digital wellbeing, study, deep work
```

Support URL:

```text
https://getblank.netlify.app/
```

Marketing URL:

```text
https://getblank.netlify.app/
```

Privacy Policy URL:

```text
https://getblank.netlify.app/privacy.html
```

Copyright:

```text
2026 Guillem Arcos Gonzalez
```

## App Review Notes

Use this in App Review notes after uploading the first build:

```text
Blank is a digital wellbeing app controlled by a physical NFC tag.

To test:
1. Install Blank on a physical iPhone with NFC.
2. Open the app and authorize Screen Time access when prompted.
3. Use the Apple Family Activity picker to select one or more apps, categories, or web domains.
4. Scan a physical NFC tag to pair it.
5. Finish setup and start Blank mode.
6. Confirm the selected apps/categories/domains are shielded while Blank is active.
7. Scan the same NFC tag again to deactivate Blank and clear the shields.

Blank stores setup state locally on the device. It does not collect screen contents, messages, passwords, contacts, notifications, browsing history, or selected Screen Time tokens on a server.

If NFC testing is not possible during review, the app also includes an emergency unlock phrase so reviewers can clear shields and continue testing.
```

## Privacy Answers

Data collection:

```text
No user data is collected by this MVP because Blank does not transmit user data off the device.
```

Data stored locally:

```text
Blank stores the paired NFC tag identifier, setup completion state, active Blank mode state, session history, selected Screen Time tokens, focus modes, theme choice, and schedule settings locally on the device.
```

Tracking:

```text
No, Blank does not track users across apps or websites owned by other companies.
```

Third-party advertising:

```text
No ads.
```

Account creation:

```text
No account required.
```

Sensitive permissions explanation:

```text
Blank uses NFC to pair and scan the user's physical Blank tag. Blank uses Apple's Screen Time APIs, including FamilyControls and ManagedSettings, so users can choose apps/categories/domains and Blank can shield those selections during active focus sessions. Blank does not inspect app content.
```

## Family Controls Entitlement Request

Submitted to Apple on 2026-07-09. Keep this wording as the project rationale for App Review and any follow-up from Apple:

```text
Blank is a digital wellbeing app that lets users voluntarily block their own distracting apps using a physical NFC tag as the activation and deactivation control.

Blank uses FamilyControls so users can select the apps, app categories, and web domains they want to shield. It uses ManagedSettings to apply those shields only while the user has activated Blank mode.

Blank does not monitor children, sell parental-control services, collect app usage content, read messages, read screen contents, or transmit selected apps to a server in this MVP. Selected tokens, paired tag state, focus modes, session history, and Blank mode state are stored locally on the device.

The user can deactivate Blank mode with the paired NFC tag and can clear shields with an emergency unlock phrase if needed.
```

## Asset Status

Prepared now:

- `ios/Blank/Blank/Assets.xcassets/AppIcon.appiconset`
- App icon generated from `web/landing/assets/blank-star-logo.png`
- iPhone icon slots: 40, 58, 60, 80, 87, 120, 180 px
- App Store marketing icon: 1024 px

Still needed from a real iPhone/TestFlight build:

- 6.7-inch screenshots.
- 6.5-inch screenshots if App Store Connect requests them.
- Optional 5.5-inch screenshots only if required by the submission flow.

Recommended first screenshot set:

1. Setup Screen Time permission context.
2. Pair NFC tag.
3. Select apps/categories.
4. Active Blank mode.
5. Shielded app state.
6. Privacy/local-first screen or report screen.

## Xcode Build Checklist

Run this on macOS:

1. Open `ios/Blank/Blank.xcodeproj`.
2. Select target `Blank`.
3. Set Team to the paid Apple Developer account.
4. Keep bundle ID `com.blanknfc.app.ios`.
5. Confirm Signing & Capabilities:
   - Family Controls.
   - Near Field Communication Tag Reading.
6. Select target `BlankDeviceActivityMonitor`.
7. Set the same Team.
8. Keep bundle ID `com.blanknfc.app.ios.deviceactivity`.
9. Confirm Family Controls is enabled for the extension.
10. Build on a physical iPhone first.
11. Run the QA script from `docs/IOS_TESTFLIGHT_AND_ENTITLEMENT.md`.
12. Archive `Any iOS Device`.
13. Upload to App Store Connect.
14. Add internal testers in TestFlight before external testing.

## Static Readiness Audit

Completed on Windows before Apple account activation:

- `Info.plist` parses and now has explicit `CFBundleDisplayName = Blank`.
- App entitlements parse and include Family Controls plus NFC reader session formats.
- Device Activity Monitor extension plist parses and uses `com.apple.deviceactivity.monitor-extension`.
- Extension entitlements parse and include Family Controls.
- `Assets.xcassets` is linked to the app target and `AppIcon` is selected for Debug and Release.
- No active QR/barcode unlock code remains in `ios/Blank` or `web/app-preview`; NFC remains the only physical unlock path.

Not verifiable on Windows:

- Swift compilation with Xcode.
- Code signing with Team ID `GS54UV79RG`.
- Family Controls distribution entitlement approval.
- Real NFC scanning on iPhone.
- ManagedSettings shielding on selected apps/categories/domains.
- DeviceActivity timer behavior while the app is backgrounded.

## Expected First Build Issues

- If Family Controls distribution is not approved yet, Xcode signing may fail for distribution or Screen Time authorization may not work in distributed builds.
- NFC cannot be tested in the iOS Simulator.
- The Device Activity Monitor extension timer path must be validated on device with the app backgrounded.
- App Store Connect may not let the app record be created until Apple finishes processing the membership.
