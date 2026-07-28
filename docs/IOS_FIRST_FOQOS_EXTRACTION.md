# Blank iOS-first plan from Foqos

Blank will start as an iOS-first product. Android remains useful later, but the first production-quality build should focus on iPhone because Foqos proves the strongest blocking model on iOS: Screen Time APIs plus physical controls.

## Source reference

Foqos repository: `https://github.com/awaseem/foqos`

License: MIT. Any copied or substantially derived source must preserve the Foqos copyright and MIT license notice.

Do not copy Foqos brand assets, name, icons, screenshots, App Store copy, or visual identity. Use it as a functional and architectural reference for Blank.

## Usage in Blank

Current usage:

- Foqos has been used as a technical reference for Screen Time architecture, NFC physical unlock strategies, timers, schedules, and extensions.
- Blank has not imported Foqos assets, visual identity, App Store copy, or bundled source files.
- QR/barcode support was intentionally removed from Blank after product review; NFC remains the only physical unlock path.
- Blank's first timer flow stores the end date locally and now attempts to schedule a DeviceActivity timer from the app target. A DeviceActivityMonitor extension target is wired into the Xcode project and still needs to be built and validated on a physical iPhone. Foqos remains the reference for the complete runtime behavior.
- App Store Connect prep values, Family Controls request text, and first iOS asset status are tracked in `docs/IOS_APP_STORE_PREP.md`.

If future work copies or substantially adapts Foqos source, add the MIT notice to the relevant file header or a dedicated third-party notices file before shipping.

## Why iOS first

- Foqos is primarily an iOS app built with SwiftUI, SwiftData, FamilyControls, ManagedSettings, DeviceActivity, CoreNFC, WidgetKit, Live Activities, and App Intents.
- Blank already has an iOS MVP under `ios/Blank` with Core NFC, FamilyControls selection, and ManagedSettings shielding.
- iOS app blocking cannot use Android Accessibility. It must use Apple's Screen Time stack.
- The main external dependency is Apple approval for the Family Controls entitlement.

## Current Blank iOS baseline

Implemented:

- NFC tag reading with Core NFC.
- Paired-tag activation/deactivation.
- Timer-based sessions with local automatic end, an initial DeviceActivity scheduling helper, and a DeviceActivityMonitor scaffold.
- Screen Time authorization request.
- FamilyActivityPicker app/category/web-domain selection.
- ManagedSettings shields while Blank is active.
- Local setup state in UserDefaults.
- Session history and weekly report.
- Multiple focus modes with separate Screen Time selections.
- Daily schedule persistence and activation window.
- Timer end persistence.
- Emergency unlock phrase.
- NFC relink/reset flows.
- Background theme selection.

Missing:

- Strategy picker.
- Background timer completion validation on device.
- Pause strategies.
- Polished report charts.
- Emergency unlock limits.
- Data export.
- Widget/Live Activity equivalents.

## Foqos features to extract

### Phase 1: iOS MVP worth shipping

Goal: a polished Blank iPhone app with one default profile, physical NFC control, and an honest report.

- Done: `HomeView` uses the Blank visual structure and exposes the main Android-equivalent controls.
- Done: records `BlankSession` on activation/deactivation.
- Done: report screen shows total protected time, estimated time saved, completed sessions, and best day.
- Done: app/category/web-domain selection via FamilyActivityPicker.
- Done: paired NFC tag is the normal unlock path.
- Done: Family Controls entitlement and TestFlight checklist documented.

### Phase 2: Foqos-style profiles

Goal: make Blank useful for different contexts.

- Add `BlankProfile` persistence.
- Profile list: Work, Study, Night, Custom.
- Each profile stores:
  - name
  - Screen Time selection
  - strategy
  - physical unlock items
  - estimated minutes saved per block
- Active session belongs to a profile.

### Phase 3: strategies

Goal: mirror Foqos strategy power without copying its UI.

Implement in this order:

1. Manual.
2. NFC.
3. Manual start + NFC stop.
4. NFC + timer.

Strategy model is seeded as `BlankStrategyKind`.

### Phase 4: physical unlock items

Goal: go beyond one NFC tag.

- Multiple NFC tags per profile.
- Rename/revoke unlock items.

Model is seeded as `PhysicalUnlockItem`.

### Phase 5: schedules and breaks

Goal: advanced focus controls.

- Weekly schedules similar to Foqos `BlockedProfileSchedule`.
- Smart breaks.
- Pause timers.
- Optional reminders when a session ends.

### Phase 6: platform extensions

Goal: native iOS polish after core product works.

- Widgets for active profile/session.
- Live Activity if it fits the product.
- Shortcuts/App Intents for start/stop profile.
- Export/import local data.

## iOS-specific constraints

- Real blocking requires Family Controls entitlement approval.
- NFC requires a physical iPhone; it cannot be validated in Simulator.
- Screen Time tokens are not normal bundle IDs; they are opaque Apple tokens.
- ManagedSettings can shield apps/categories/web domains, but not inspect content.
- Blank should keep selected apps/tokens local unless a later privacy-reviewed sync feature is added.

## Implementation rule

Treat Foqos as the reference for behavior and edge cases. Treat Blank as its own product for naming, UI, copy, analytics, and user experience.
