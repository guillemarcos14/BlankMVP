// Tests execute production window models, extension predicate, interval generation
// and selection observer. Only Apple-only persistence/monitor effects are fixtures.
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

@main
struct ProtectionTests {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
        }
        let work = BlankHabitWindow(name: "Work", startMinute: 9 * 60, endMinute: 17 * 60, weekdays: [2, 3, 4, 5, 6])
        expect(work.contains(date(25, 10), calendar: calendar), "Friday work window missing")
        expect(!work.contains(date(26, 10), calendar: calendar), "Weekday window incorrectly blocks Saturday")
        expect(!work.contains(date(25, 17), calendar: calendar), "Window end must be exclusive")
        expect(DeviceActivityTimerScheduler.recurringIntervals(for: work).count == 1, "Weekday windows need a native interval")

        let night = BlankHabitWindow(name: "Friday night", startMinute: 23 * 60, endMinute: 7 * 60, weekdays: [6])
        expect(night.contains(date(25, 23, 30), calendar: calendar), "Friday night start missing")
        expect(night.contains(date(26, 6), calendar: calendar), "Overnight window must use its start weekday")
        expect(!night.contains(date(26, 23, 30), calendar: calendar), "Saturday must not start Friday's window")
        expect(!night.contains(date(26, 7), calendar: calendar), "Overnight end must be exclusive")
        expect(DeviceActivityTimerScheduler.recurringIntervals(for: night).count == 2, "Overnight monitor needs both sides of midnight")

        var expiring = work
        expiring.expiresAt = date(25, 12)
        expect(expiring.contains(date(25, 11), calendar: calendar), "Expiry shortened a live window")
        expect(!expiring.contains(date(25, 12), calendar: calendar), "Expired window remains active")
        let overlap = BlankFocusSchedule(enabled: true, windows: [expiring, work])
        expect(overlap.contains(date(25, 13), calendar: calendar), "One expired window unlocked an overlapping live window")

        // The independently compiled extension must agree with app calendar rules.
        for window in [work, night, expiring] {
            let data = try JSONEncoder().encode(window)
            let extensionWindow = try JSONDecoder().decode(StoredWindow.self, from: data)
            for day in 20...28 {
                for hour in 0...23 {
                    let instant = date(day, hour)
                    expect(window.contains(instant, calendar: calendar) == extensionWindow.contains(instant, calendar: calendar), "App and extension disagree at \(instant)")
                }
            }
        }
        let legacy = Data(#"{"name":"Legacy","enabled":true,"startMinute":540,"endMinute":1020,"weekdays":[2,3,4,5,6]}"#.utf8)
        let restored = try JSONDecoder().decode(BlankHabitWindow.self, from: legacy)
        expect(restored.expiresAt == nil && restored.weekdays == work.weekdays, "Installed schedule lost backwards compatibility")
        let roundTrip = try JSONDecoder().decode(BlankHabitWindow.self, from: JSONEncoder().encode(expiring))
        expect(roundTrip.expiresAt == expiring.expiresAt && roundTrip.id == expiring.id, "Window expiry or identity lost during persistence")

        let state = SelectionFixture()
        state.isBlankActive = true
        state.selection = 2
        expect(state.selection == 1 && state.saved == 0, "Open picker changed active protection")
        state.isBlankActive = false
        BlankSharedState.sharedActive = true
        state.selection = 2
        expect(state.selection == 1, "Widget protection bypassed selection lock")
        BlankSharedState.sharedActive = false
        DeviceActivityTimerScheduler.hasIndependentProtection = true
        state.selection = 2
        expect(state.selection == 1 && state.limits == 0, "Scheduled or daily-limit shield bypassed selection lock")
        DeviceActivityTimerScheduler.hasIndependentProtection = false
        state.selection = 2
        expect(state.selection == 2 && state.saved == 1 && state.schedules == 1 && state.limits == 1, "Legal selection must update every monitor")
        state.selection = 2
        expect(state.saved == 1, "Equivalent selection update should be inert")
        print("iOS protection: weekday/overnight/expiry/overlap, 648 app-extension comparisons, legacy persistence and canonical selection locking passed")
    }
}
