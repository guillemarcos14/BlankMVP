# iOS TestFlight and Family Controls

## Reality Check

iOS cannot use the Android Accessibility blocking model. Production app blocking must use Apple's Screen Time stack:

- `FamilyControls` for authorization and app/category selection.
- `ManagedSettings` for shielding selected apps and domains.
- `DeviceActivity` later if scheduled monitoring windows are needed.

The app in `ios/Brick` uses this architecture. Real shielding requires the Family Controls entitlement on the app identifier.

## Apple Entitlement Request

Submit the Family Controls entitlement request from the Apple Developer account holder.

Suggested explanation:

```text
Blank is a digital wellbeing app that lets users voluntarily block their own distracting apps using a physical NFC tag as the activation/deactivation control.

The app uses FamilyControls so users can select the apps, app categories, and web domains they want to shield. It uses ManagedSettings to apply those shields only while the user has activated Blank mode with their paired NFC tag.

Blank does not monitor children, sell parental-control services, collect app usage content, read messages, read screen contents, or transmit selected apps to a server in this MVP. Selected tokens, paired tag state, and Blank mode state are stored locally on the device.

The user can deactivate Blank mode with the paired NFC tag and can reset the paired tag from inside the app when Blank mode is inactive.
```

## TestFlight Setup

1. Open `ios/Brick/Brick.xcodeproj` in Xcode.
2. Select the `Brick` target.
3. Set Team and bundle identifier.
4. Add capabilities:
   - Family Controls.
   - Near Field Communication Tag Reading.
5. Confirm `Brick.entitlements` is attached to Debug and Release.
6. Archive from Xcode.
7. Upload to App Store Connect.
8. Add internal testers first.
9. Test on physical iPhone; NFC does not work in Simulator.

## App Review Notes

Use this review note:

```text
Blank is controlled by a physical NFC tag. During setup, the reviewer should authorize Screen Time access, scan an NFC tag, choose one or more apps/categories using the Apple Family Activity picker, then finish setup.

When Blank mode is activated with the paired tag, the app applies ManagedSettings shields to the selected apps/categories. Scanning the same tag again deactivates Blank mode and clears the shields.

Blank stores setup state locally and does not collect screen contents, messages, passwords, contacts, or browsing history.
```

## iOS QA Pass

- App launches and setup starts.
- Screen Time authorization succeeds or shows a clear error.
- NFC scan registers a physical tag.
- Selected apps/categories persist after app restart.
- Matching tag toggles Blank mode.
- Wrong tag is rejected.
- Shielded apps are blocked while Blank mode is active.
- Shields clear after deactivation.
- Forget tag resets setup when not bricked.
