import DeviceActivity
import ManagedSettings
import OSLog

private let log = Logger(
    subsystem: "com.blanknfc.app.ios.device-activity",
    category: "DeviceActivity"
)

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let strategyActivityPrefix = "BlankStrategyTimer"
    private let store = ManagedSettingsStore()

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        log.info("DeviceActivity interval started: \(activity.rawValue)")
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        log.info("DeviceActivity interval ended: \(activity.rawValue)")

        guard activity.rawValue.hasPrefix(strategyActivityPrefix) else {
            return
        }

        store.clearAllSettings()
    }
}
