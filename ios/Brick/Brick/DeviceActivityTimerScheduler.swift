import Foundation

#if canImport(DeviceActivity)
import DeviceActivity
#endif

enum DeviceActivityTimerScheduler {
    static let strategyActivityPrefix = "BlankStrategyTimer"

    static func start(modeId: UUID, durationMinutes: Int) -> Bool {
        guard durationMinutes > 0 else { return false }

        #if canImport(DeviceActivity)
        let center = DeviceActivityCenter()
        let activityName = DeviceActivityName(rawValue: "\(strategyActivityPrefix):\(modeId.uuidString)")
        let endComponents = endDateComponents(durationMinutes: durationMinutes)
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: endComponents,
            repeats: false
        )

        do {
            center.stopMonitoring([activityName])
            try center.startMonitoring(activityName, during: schedule)
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    static func stop(modeId: UUID) {
        #if canImport(DeviceActivity)
        let center = DeviceActivityCenter()
        center.stopMonitoring([DeviceActivityName(rawValue: "\(strategyActivityPrefix):\(modeId.uuidString)")])
        #endif
    }

    private static func endDateComponents(durationMinutes: Int) -> DateComponents {
        let endDate = Date().addingTimeInterval(TimeInterval(durationMinutes * 60))
        let components = Calendar.current.dateComponents([.hour, .minute], from: endDate)
        return DateComponents(hour: components.hour, minute: components.minute)
    }
}
