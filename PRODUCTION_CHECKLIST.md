# Blank Production Checklist

## Build Readiness

- Install JDK 17 and set `JAVA_HOME`.
- Install Android SDK Platform 35.
- Run `.\gradlew.bat testDebugUnitTest`.
- Run `.\gradlew.bat assembleDebug`.
- Configure a release keystore outside the repository using `docs/ANDROID_BETA_RELEASE.md`.
- Run `.\gradlew.bat bundleRelease`.
- Keep `keystore.properties`, `.jks`, and `.keystore` files out of git.
- Before adding Firebase/Sentry, update privacy copy and store Data Safety answers.

## Device Validation

- Test on a real NFC-capable Android device.
- Register a physical NFC tag.
- Enable Blank's Accessibility Service from Android settings.
- Disable battery optimization for Blank.
- Select at least one app to block.
- Activate Blank mode with the paired NFC tag.
- Confirm selected apps open the fullscreen blocking screen.
- Confirm the paired NFC tag exits Blank mode.
- Confirm unpaired NFC tags do not exit Blank mode.
- Reboot the device and confirm the state is preserved.
- Test recent apps, notifications, split screen, quick settings, and OEM battery managers.

## Google Play Policy

- Keep `targetSdk` at API 35 or higher.
- Do not add `QUERY_ALL_PACKAGES` unless Play Console approval is explicitly required and granted.
- Keep app visibility limited to launcher apps through manifest `<queries>`.
- Provide in-app Accessibility disclosure before sending the user to system settings.
- In Play Console, declare Accessibility API usage accurately.
- State that Blank uses Accessibility events to detect foreground app package changes.
- State that Blank does not read text, credentials, messages, or screen contents.
- Prepare a short review video showing setup, Accessibility usage, app blocking, and NFC unblock.
- Publish the privacy policy from `PRIVACY_POLICY_DRAFT.md` at a stable public URL.
- Complete Play Console Data Safety based on local-only storage unless analytics or backend sync are added later.
- Follow `docs/ANDROID_BETA_RELEASE.md` for Accessibility declaration copy and internal testing flow.

## iOS Production Path

- Open `ios/Brick/Brick.xcodeproj` in Xcode on macOS.
- Set Team and bundle identifier.
- Request Apple's Family Controls entitlement before relying on real iPhone app shielding.
- Add/confirm Near Field Communication Tag Reading and Family Controls capabilities.
- Test only on physical iPhone for NFC.
- Use `docs/IOS_TESTFLIGHT_AND_ENTITLEMENT.md` for entitlement request copy, TestFlight steps, and review notes.

## Analytics And Crashes

- Current Android implementation logs beta events through `LogcatAnalyticsTracker`.
- Decide Firebase or Sentry before public testing beyond close friends.
- If using Firebase, add `google-services.json` locally and implement a production `AnalyticsTracker`.
- Track setup completion, NFC registration, Blank activation/deactivation, selected app count, block screens, permission failures, NFC failures, and crashes.
- Use `docs/ANALYTICS_AND_CRASHES.md` as the instrumentation checklist.

## Market Test

- Publish `web/landing/` or port it to your site builder.
- Connect the beta form to Tally, Typeform, Airtable, ConvertKit, or a backend.
- Recruit 20-50 testers and give each one a physical NFC tag.
- Run the 7-day test described in `docs/MARKET_TEST_PLAN.md`.
- Use the success criteria before spending on larger inventory.

## Store Listing

- Create production launcher icon assets.
- Prepare phone screenshots for setup, home, app selector, privacy, and block screen.
- Write short description, full description, and release notes.
- Decide support email and privacy policy URL.
- Run closed testing before production submission.
- Use `docs/STORE_LISTING_COPY.md` as the first copy draft.
