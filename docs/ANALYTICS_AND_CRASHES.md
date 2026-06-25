# Analytics and Crash Reporting

## Current State

Android has a local `AnalyticsTracker` abstraction and a `LogcatAnalyticsTracker`. This avoids adding Firebase/Sentry credentials to the repo while keeping all instrumentation points explicit.

Tracked Android events:

- `app_opened`
- `setup_completed`
- `nfc_tag_registered`
- `nfc_wrong_tag`
- `nfc_no_apps_selected`
- `BLANK_MODE_activated`
- `BLANK_MODE_deactivated`
- `blocked_apps_updated`
- `block_screen_shown`
- `tag_forgotten`

## Recommended Production Stack

Use one of:

- Firebase Analytics + Crashlytics for Android.
- Firebase Analytics + Crashlytics for iOS.
- Sentry if you want one cross-platform crash/error view with simpler product analytics elsewhere.

## Firebase Android Integration Steps

1. Create a Firebase project.
2. Add Android app with package `com.blanknfc.app`.
3. Download `google-services.json` into `app/`.
4. Add Google Services and Crashlytics Gradle plugins.
5. Implement `FirebaseAnalyticsTracker : AnalyticsTracker`.
6. Replace `LogcatAnalyticsTracker` in `AppContainer`.
7. Complete Play Console Data Safety again because analytics changes data collection.

Do not add Firebase until privacy policy, consent copy, and Data Safety answers are updated.

## Beta Metrics

Primary activation metrics:

- Install to setup completion.
- Setup step drop-off.
- NFC registration success rate.
- App selection completion rate.
- First Blank activation rate.

Retention metrics:

- Sessions per active user per day.
- Median Blank session duration.
- Day 1, Day 3, Day 7 active usage.

Quality metrics:

- Accessibility permission failure rate.
- NFC scan failure rate.
- Block screen shown count.
- Wrong tag attempts.
- Crash-free users.
