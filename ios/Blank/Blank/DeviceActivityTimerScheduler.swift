import Foundation

#if canImport(DeviceActivity)
import DeviceActivity
import FamilyControls
#endif

enum DeviceActivityTimerScheduler {
    static let strategyActivityPrefix = "BlankStrategyTimer"
    static let recurringSchedulePrefix = "BlankRecurringSchedule"
    static let dailyLimitActivity = "BlankDailyLimit"
    static let dailyLimitEvent = "BlankDailyLimitReached"

    private static let maxRecurringActivities = 8
    static let recurringExpiryActivity = "BlankRecurringScheduleExpiry"

    @discardableResult
    static func syncRecurringSchedule(_ schedule: BlankFocusSchedule, until expiry: Date? = nil) -> Bool {
        #if canImport(DeviceActivity)
        let center = DeviceActivityCenter()
        let activityNames = (0..<maxRecurringActivities).map {
            DeviceActivityName(rawValue: "\(recurringSchedulePrefix):\($0)")
        }
        center.stopMonitoring(activityNames + [DeviceActivityName(rawValue: recurringExpiryActivity)])

        guard schedule.enabled else { return true }
        if let expiry, expiry <= Date() {
            return true
        }

        var registered = 0
        for window in schedule.activeWindows where window.runsEveryDay {
            for interval in recurringIntervals(for: window) {
                guard registered < maxRecurringActivities else { break }
                let name = DeviceActivityName(rawValue: "\(recurringSchedulePrefix):\(registered)")
                let activity = DeviceActivitySchedule(
                    intervalStart: interval.start,
                    intervalEnd: interval.end,
                    repeats: true
                )
                do {
                    try center.startMonitoring(name, during: activity)
                    registered += 1
                } catch {
                    return false
                }
            }
        }
        if let expiry, expiry > Date() {
            let calendar = Calendar.current
            let start = calendar.dateComponents(
                [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second],
                from: expiry
            )
            let end = calendar.dateComponents(
                [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second],
                from: expiry.addingTimeInterval(120)
            )
            do {
                try center.startMonitoring(
                    DeviceActivityName(rawValue: recurringExpiryActivity),
                    during: DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: false)
                )
            } catch {
                return false
            }
        }
        return true
        #else
        return false
        #endif
    }

    static func stopRecurringSchedule() {
        #if canImport(DeviceActivity)
        let names = (0..<maxRecurringActivities).map {
            DeviceActivityName(rawValue: "\(recurringSchedulePrefix):\($0)")
        }
        DeviceActivityCenter().stopMonitoring(names + [DeviceActivityName(rawValue: recurringExpiryActivity)])
        #endif
    }

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

    private static func recurringIntervals(for window: BlankHabitWindow) -> [(start: DateComponents, end: DateComponents)] {
        let start = dateComponents(minute: window.startMinute, second: 0)
        let end = dateComponents(minute: window.endMinute, second: 0)
        if window.startMinute < window.endMinute {
            return [(start, end)]
        }

        return [
            (start, dateComponents(minute: 24 * 60 - 1, second: 59)),
            (dateComponents(minute: 0, second: 0), end)
        ]
    }

    private static func dateComponents(minute: Int, second: Int) -> DateComponents {
        DateComponents(hour: minute / 60, minute: minute % 60, second: second)
    }
}
