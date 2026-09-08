# Android Release

## Current Build

Signed AAB:

```text
C:\Users\Guillem\Desktop\Blanked\Extra\Codigo\app\build\outputs\bundle\release\Blank-1.8-release.aab
```

SHA256:

```text
FB8548BEA7A950CF550351134020EBB9BBCF64AE77272728929636AEED8D4A87
```

Validation:

```powershell
.\gradlew.bat testDebugUnitTest assembleDebug bundleRelease
```

Result:

```text
BUILD SUCCESSFUL
```

Last autonomous validation on 2026-09-04:

```text
BUILD SUCCESSFUL
SHA256 FB8548BEA7A950CF550351134020EBB9BBCF64AE77272728929636AEED8D4A87
Netlify production deploy 6a9aaa19672d40819a330a2a
blanked-agent remote eval 65/65
```

## Signing

Blank reads release signing credentials from `keystore.properties` in the project root or from environment variables.

Do not commit signing secrets.

Current local signing file:

```text
C:\Users\Guillem\Desktop\Blanked\Extra\Codigo\release-keys\blank-upload.jks
```

## Manual Play Console Steps

Done on 2026-09-03:

- Uploaded `Blank-1.8-release.aab` to Google Play Console > `Prueba interna`.
- Google Play Console accepted bundle `22 (1.8)`.
- Release `3` was published to internal testers.
- Track is active and shows latest version `22 (1.8)`.
- Publication time shown by Play Console: `3 sept 19:43`.
- Tester list: `Beta testers v.0`, 22 testers.
- Internal test join link: `https://play.google.com/apps/internaltest/4701665978038551921`.
- Blocking errors: none.
- Warning: no deobfuscation file is associated with this App Bundle.
- Emulator QA found and fixed residual onboarding text before this upload: `Blank`, `Paso 3 de 3`, and `Permite que Blank bloquee.`.

Remaining:

1. Complete store listing and app-content declarations using `docs/PLAY_CONSOLE_ANDROID_1_8_VALUES.md`.
2. Configure Google Payments merchant profile if Play Console requires it.
3. Create subscriptions:
   - `blanked_monthly_299`
   - `blanked_annual_19`
4. Add 3-day free trial to both subscription offers.
5. Confirm Google Play availability with a real tester account once propagation completes.

## Manual QA Pass

- Fresh install starts onboarding.
- User can continue app-only without NFC.
- App selection works.
- Accessibility permission can be enabled.
- Battery optimization prompt works.
- Start Blanked blocks selected apps.
- Unselected apps are not blocked.
- Emergency unlock requires exact phrase.
- Stats, Habits, AI Focus Plan, Digital Wellness Report and Health Connect screens render correctly.
- Health Connect permission flow works on a real Android device.
- Google Play Billing shows monthly and annual products with the 3-day trial.
- Analytics/onboarding/AI/referrals reach Netlify/Supabase.
