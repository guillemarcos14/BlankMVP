import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import OSLog

private let log = Logger(
    subsystem: "com.blanknfc.app.ios.device-activity",
    category: "DeviceActivity"
)

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let strategyActivityPrefix = "BlankStrategyTimer"
    private let dailyLimitActivity = "BlankDailyLimit"
    private let dailyLimitEvent = "BlankDailyLimitReached"
    private let store = ManagedSettingsStore()

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        log.info("DeviceActivity interval started: \(activity.rawValue)")
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        log.info("DeviceActivity interval ended: \(activity.rawValue)")

        if activity.rawValue.hasPrefix(strategyActivityPrefix) || activity.rawValue == dailyLimitActivity {
            store.clearAllSettings()
        }
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        log.info("DeviceActivity event reached: \(event.rawValue), activity: \(activity.rawValue)")

        guard activity.rawValue == dailyLimitActivity,
              event.rawValue == dailyLimitEvent,
              let selection = Self.loadSelection() else {
            return
        }

        store.shield.applications = selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens
        store.webContent.blockedByFilter = Self.adultContentBlockingEnabled ? .auto() : nil
    }

    private static func loadSelection() -> FamilyActivitySelection? {
        let defaults = UserDefaults(suiteName: "group.com.blanknfc.app.ios") ?? .standard
        guard let data = defaults.data(forKey: "familyActivitySelection") else { return nil }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    private static var adultContentBlockingEnabled: Bool {
        let defaults = UserDefaults(suiteName: "group.com.blanknfc.app.ios") ?? .standard
        return defaults.bool(forKey: "blankAdultContentBlockingEnabled")
    }
}
