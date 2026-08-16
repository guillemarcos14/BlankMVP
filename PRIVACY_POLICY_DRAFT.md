# Blank Privacy Policy Draft

Last updated: June 14, 2026

Blank is an app blocker controlled by a paired NFC tag.

## Data Blank stores

Blank stores the following data locally on your device:

- The NFC tag ID paired with Blank.
- The package names of apps you choose to block.
- Whether Blank mode is active.
- The time Blank mode was activated.
- Whether setup has been completed.

Blank may also collect the answers you provide during onboarding, such as your name, age range, goals, profile, estimated daily phone use, selected plan, locale, app version, and an anonymous user identifier. Blank uses this information to understand onboarding performance, improve the product, and make the experience more relevant. Blank does not collect the exact apps you choose to block.

On iPhone, Blank may optionally read Apple Health data that you explicitly allow, such as sleep, time in bed, steps, walking/running distance, active energy, resting energy, workouts, mindful minutes, heart rate, resting heart rate, and heart rate variability. Blank uses this data locally to generate digital wellness insights about screen habits. Blank does not use Apple Health data for medical diagnosis and does not send Apple Health data to its backend in the current implementation.

## Accessibility Use

Blank uses Android Accessibility events to detect when the foreground app changes. If Blank mode is active and the foreground app is in your blocked list, Blank opens its blocking screen.

Blank does not use Accessibility to read screen text, passwords, messages, notifications, form contents, contacts, browsing history, or media.

## Analytics And Crash Reporting

The current MVP does not include a production third-party analytics or crash reporting SDK. During local beta builds, Blank may write technical events to device logs to help debug setup and blocking behavior.

If Firebase, Sentry, or another analytics/crash provider is added later, this policy and the app store privacy disclosures must be updated before release.

## Sharing

Blank may send onboarding responses to its backend for product analytics and improvement. Blank does not sell this data and does not share it with third-party advertisers.

## Permissions

Blank requires NFC to pair and read your physical tag. Blank requires Accessibility access to detect blocked apps. Blank may request battery optimization exclusion so Android does not stop the app while Blank mode is active.

On iPhone, Apple Health access is optional and can be declined without blocking the app. You can stop Blank from using Apple Health inside the app, and you can revoke Health permissions in iOS Settings or Apple Health.

## iPhone Version

On iPhone, Blank cannot use Android Accessibility. The iPhone version uses Apple's Screen Time APIs, such as FamilyControls and ManagedSettings, so users can select apps/categories and Blank can shield them while Blank mode is active. Apple may require entitlement approval before this works in distributed builds.

## Contact

TODO: Add support email before public release.
