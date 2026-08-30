import Foundation

#if canImport(DeviceActivity)
import DeviceActivity
import FamilyControls
#endif

enum DeviceActivityTimerScheduler {
    static let strategyActivityPrefix = "BlankStrategyTimer"
    static let dailyLimitActivity = "BlankDailyLimit"
    static let dailyLimitEvent = "BlankDailyLimitReached"

    static func start(modeId: UUID, durationMinutes: Int) -> Bool {
        guard durationMinutes > 0 else { return false }

        #if canImport(DeviceActivity)
        let center = DeviceActivityCenter()
        let activityName = DeviceActivityName(rawValue: "\(strategyActivityPrefix):\(modeId.uuidString)")
        let timerInterval = makeTimerInterval(durationMinutes: durationMinutes)
        guard timerInterval.start != timerInterval.end else {
            return false
        }

        center.stopMonitoring([activityName])
        let schedule = DeviceActivitySchedule(
            intervalStart: timerInterval.start,
            intervalEnd: timerInterval.end,
            repeats: false
        )

        do {
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

    static func startDailyLimit(selection: FamilyActivitySelection, thresholdMinutes: Int) -> Bool {
        #if canImport(DeviceActivity)
        guard thresholdMinutes > 0 else { return false }
        let center = DeviceActivityCenter()
        let activityName = DeviceActivityName(rawValue: dailyLimitActivity)
        let eventName = DeviceActivityEvent.Name(dailyLimitEvent)
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        let event = DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: DateComponents(minute: thresholdMinutes)
        )

        center.stopMonitoring([activityName])
        do {
            try center.startMonitoring(activityName, during: schedule, events: [eventName: event])
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    static func stopDailyLimit() {
        #if canImport(DeviceActivity)
        DeviceActivityCenter().stopMonitoring([DeviceActivityName(rawValue: dailyLimitActivity)])
        #endif
    }

    private static func makeTimerInterval(durationMinutes: Int) -> (start: DateComponents, end: DateComponents) {
        let startDate = Date().addingTimeInterval(1)
        let endDate = Date().addingTimeInterval(TimeInterval(durationMinutes * 60))
        let components: Set<Calendar.Component> = [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second]
        let calendar = Calendar.current
        return (
            start: calendar.dateComponents(components, from: startDate),
            end: calendar.dateComponents(components, from: endDate)
        )
    }
}
