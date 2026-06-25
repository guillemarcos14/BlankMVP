# Blank MVP

Blank is a physical NFC-controlled app blocker.

## Project Structure

- `app/` - Android Kotlin/Jetpack Compose MVP.
- `ios/Brick/` - iPhone SwiftUI MVP using Core NFC and Screen Time APIs.
- `docs/` - production, beta, analytics, market test, and store copy documents.
- `web/landing/` - static landing page for waitlist/preorder testing.

## Android Beta

```powershell
.\gradlew.bat testDebugUnitTest
.\gradlew.bat assembleDebug
.\gradlew.bat bundleRelease
```

Release signing is configured through secrets outside the repo. See `docs/ANDROID_BETA_RELEASE.md`.

## iPhone Beta

Open `ios/Brick/Brick.xcodeproj` on macOS with Xcode and run on a physical iPhone. NFC does not work in Simulator. Real app shielding requires Apple's Family Controls entitlement. See `docs/IOS_TESTFLIGHT_AND_ENTITLEMENT.md`.

## Market Test

Open `web/landing/index.html` in a browser to preview the static landing page. Before sending traffic, connect the email form to a real backend or form tool.

Use `docs/MARKET_TEST_PLAN.md` to run a 20-50 user beta.
