# Android Beta Release

## Release Build

Blank reads release signing credentials from either `keystore.properties` in the project root or environment variables.

Do not commit signing secrets.

Example `keystore.properties`:

```properties
storeFile=C:\\Users\\Guillem\\keys\\blank-release.jks
storePassword=replace_me
keyAlias=blank
keyPassword=replace_me
```

Equivalent environment variables:

```powershell
$env:BLANK_RELEASE_STOREFILE="C:\\Users\\Guillem\\keys\\blank-release.jks"
$env:BLANK_RELEASE_STOREPASSWORD="replace_me"
$env:BLANK_RELEASE_keyAlias="blank"
$env:BLANK_RELEASE_KEYPASSWORD="replace_me"
```

Commands:

```powershell
.\gradlew.bat testDebugUnitTest
.\gradlew.bat assembleDebug
.\gradlew.bat bundleRelease
```

Current signed internal-testing bundle:

```text
C:\Users\Guillem\Desktop\Blank-internal-testing-1.0.aab
SHA256: 622FA84504AB734DA74341F9CF5558DCE286A5685A20E7BD700EE38B18C0D008
```

Upload `C:\Users\Guillem\Desktop\Blank-internal-testing-1.0.aab` to Google Play Console internal testing.

Keep both files below backed up. Losing them blocks future updates with the same upload key:

```text
C:\Users\Guillem\Desktop\BlankMVP\release-keys\blank-upload.jks
C:\Users\Guillem\Desktop\BlankMVP\keystore.properties
```

## Play Console Internal Testing

1. Create app in Play Console.
2. Enable Play App Signing when prompted.
3. Complete App content:
   - Privacy Policy URL.
   - Data Safety.
   - Accessibility API declaration.
   - Content rating.
   - Target audience.
4. Create internal testing track.
5. Add tester emails or Google Group.
6. Upload signed AAB.
7. Add release notes:
   - NFC tag pairing.
   - App selection.
   - Blank mode app blocking.
   - Privacy/local storage beta.
8. Submit internal track for review.
9. Share the opt-in link with testers after Google Play processes the release.

## Accessibility Declaration Copy

Blank uses Android Accessibility events only to detect when the foreground app changes. If Blank mode is active and the foreground package is in the user's selected blocked list, Blank opens its blocking screen.

Blank does not read screen text, typed text, passwords, messages, notifications, contacts, browsing history, media, or form contents. Blank stores selected package names, paired NFC tag ID, setup state, and current Blank mode state locally on the device.

For the Accessibility API declaration, state that Blank is not an accessibility tool for disability support and that the API is used only for user-requested focus blocking. Keep `android:isAccessibilityTool="false"` unless the product purpose changes.

## Store / Review Notes

- App category: Productivity.
- Ads: No.
- Data sharing: No server sharing in this beta.
- Sensitive app data: selected app package names, paired NFC tag ID, setup state, and current Blank mode state are stored locally.
- Restricted access instructions: reviewers need a physical Android device with NFC and an NFC tag. The onboarding asks them to select apps, pair NFC, and enable the Blank accessibility service.

## Manual QA Pass

- Fresh install starts setup.
- NFC unsupported devices show a clear blocker.
- First valid NFC tag registers.
- Wrong NFC tag cannot activate or deactivate an existing session.
- Matching NFC tag refuses to start without selected apps.
- Accessibility disclosure appears before system settings.
- Accessibility service can be enabled.
- Battery optimization prompt works on supported Android versions.
- Launcher app list excludes Blank and critical phone/settings packages.
- Blank mode blocks selected apps.
- Blank mode does not block unselected apps.
- Block screen exits after matching NFC tag deactivates Blank mode.
- Reboot preserves selected apps, NFC tag, and Blank mode state.
- Forget tag resets setup and clears Blank mode.
