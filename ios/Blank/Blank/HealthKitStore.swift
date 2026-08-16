import Foundation
import Combine
import HealthKit

struct HealthDaySummary: Identifiable, Equatable {
    var id: Date { date }
    var date: Date
    var inBedMinutes: Int?
    var sleepMinutes: Int?
    var bedtimeMinute: Int?
    var wakeMinute: Int?
    var steps: Int?
    var distanceMeters: Int?
    var activeEnergyKcal: Int?
    var basalEnergyKcal: Int?
    var workoutMinutes: Int?
    var mindfulMinutes: Int?
    var averageHeartRate: Int?
    var restingHeartRate: Int?
    var hrvSDNN: Int?

    var hasSignals: Bool {
        inBedMinutes != nil ||
        sleepMinutes != nil ||
        bedtimeMinute != nil ||
        wakeMinute != nil ||
        steps != nil ||
        distanceMeters != nil ||
        activeEnergyKcal != nil ||
        basalEnergyKcal != nil ||
        workoutMinutes != nil ||
        mindfulMinutes != nil ||
        averageHeartRate != nil ||
        restingHeartRate != nil ||
        hrvSDNN != nil
    }
}

private struct HealthSleepSummary {
    var inBedMinutes: Int?
    var sleepMinutes: Int?
    var bedtimeMinute: Int?
    var wakeMinute: Int?
}

enum HealthKitConnectionState: Equatable {
    case unavailable
    case notRequested
    case requesting
    case connected
    case failed(String)
}

final class HealthKitStore: ObservableObject {
    @Published private(set) var state: HealthKitConnectionState
    @Published private(set) var summaries: [HealthDaySummary] = []

    private let healthStore = HKHealthStore()
    private let defaults: UserDefaults
    private let requestedKey = "blankHealthKitRequested"

    init(defaults: UserDefaults = BlankSharedState.defaults) {
        self.defaults = defaults
        if !HKHealthStore.isHealthDataAvailable() {
            state = .unavailable
        } else if defaults.bool(forKey: requestedKey) {
            state = .connected
        } else {
            state = .notRequested
        }
    }

    func requestAccess() {
        guard HKHealthStore.isHealthDataAvailable() else {
            state = .unavailable
            return
        }
        let types = readTypes
        guard !types.isEmpty else {
            state = .failed("Health data types are not available on this device.")
            return
        }

        state = .requesting
        healthStore.requestAuthorization(toShare: [], read: types) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.defaults.set(true, forKey: self.requestedKey)
                if success {
                    self.state = .connected
                    self.refresh()
                } else {
                    self.state = .failed(error?.localizedDescription ?? "Health access was not granted.")
                }
            }
        }
    }

    func disconnect() {
        defaults.set(false, forKey: requestedKey)
        summaries = []
        state = HKHealthStore.isHealthDataAvailable() ? .notRequested : .unavailable
    }

    func loadSyntheticAppleWatchData(days: Int = 14) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        summaries = (0..<days).compactMap { offset -> HealthDaySummary? in
            guard let date = calendar.date(byAdding: .day, value: offset - (days - 1), to: today) else {
                return nil
            }

            let dayIndex = offset + 1
            let shortSleepDay = dayIndex == 4 || dayIndex == 9 || dayIndex == 13
            let activeDay = dayIndex == 2 || dayIndex == 6 || dayIndex == 11
            let lateBedtime = shortSleepDay || dayIndex == 8
            let sleepMinutes = shortSleepDay ? 315 + (dayIndex % 2) * 18 : 430 + (dayIndex % 3) * 22
            let steps = activeDay ? 10400 + dayIndex * 110 : 2800 + dayIndex * 360
            let workoutMinutes = activeDay ? 36 + dayIndex % 4 * 6 : (dayIndex % 5 == 0 ? 18 : nil)
            let bedtimeMinute = lateBedtime ? 1 * 60 + 15 + dayIndex * 3 : 22 * 60 + 35 + dayIndex * 4
            let wakeMinute = shortSleepDay ? 6 * 60 + 35 : 7 * 60 + 20 + dayIndex % 4 * 8

            return HealthDaySummary(
                date: date,
                inBedMinutes: sleepMinutes + 34,
                sleepMinutes: sleepMinutes,
                bedtimeMinute: bedtimeMinute % (24 * 60),
                wakeMinute: wakeMinute,
                steps: steps,
                distanceMeters: Int(Double(steps) * 0.78),
                activeEnergyKcal: activeDay ? 680 + dayIndex * 8 : 240 + dayIndex * 13,
                basalEnergyKcal: 1540 + dayIndex * 3,
                workoutMinutes: workoutMinutes,
                mindfulMinutes: dayIndex % 3 == 0 ? 8 + dayIndex % 4 : nil,
                averageHeartRate: 76 - dayIndex % 5,
                restingHeartRate: shortSleepDay ? 68 + dayIndex % 3 : 58 + dayIndex % 4,
                hrvSDNN: shortSleepDay ? 31 + dayIndex % 5 : 54 + dayIndex % 8
            )
        }
        state = .connected
    }

    func refresh(days: Int = 14) {
        guard HKHealthStore.isHealthDataAvailable() else {
            state = .unavailable
            return
        }
        guard defaults.bool(forKey: requestedKey) else { return }

        let calendar = Calendar.current
        let now = Date()
        let end = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) else {
            return
        }

        let group = DispatchGroup()
        var sleepByDay: [Date: HealthSleepSummary] = [:]
        var stepsByDay: [Date: Int] = [:]
        var distanceByDay: [Date: Int] = [:]
        var activeEnergyByDay: [Date: Int] = [:]
        var basalEnergyByDay: [Date: Int] = [:]
        var workoutMinutesByDay: [Date: Int] = [:]
        var mindfulMinutesByDay: [Date: Int] = [:]
        var heartRateByDay: [Date: Int] = [:]
        var restingHeartRateByDay: [Date: Int] = [:]
        var hrvByDay: [Date: Int] = [:]

        group.enter()
        readSleepMinutes(start: start, end: end, calendar: calendar) { values in
            sleepByDay = values
            group.leave()
        }

        if let type = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            group.enter()
            readDailySum(type: type, unit: .count(), start: start, end: end, calendar: calendar) { values in
                stepsByDay = values
                group.leave()
            }
        }

        if let type = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
            group.enter()
            readDailySum(type: type, unit: .meter(), start: start, end: end, calendar: calendar) { values in
                distanceByDay = values
                group.leave()
            }
        }

        if let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            group.enter()
            readDailySum(type: type, unit: .kilocalorie(), start: start, end: end, calendar: calendar) { values in
                activeEnergyByDay = values
                group.leave()
            }
        }

        if let type = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned) {
            group.enter()
            readDailySum(type: type, unit: .kilocalorie(), start: start, end: end, calendar: calendar) { values in
                basalEnergyByDay = values
                group.leave()
            }
        }

        group.enter()
        readWorkoutMinutes(start: start, end: end, calendar: calendar) { values in
            workoutMinutesByDay = values
            group.leave()
        }

        if let type = HKObjectType.categoryType(forIdentifier: .mindfulSession) {
            group.enter()
            readCategoryMinutes(type: type, acceptedValues: nil, start: start, end: end, calendar: calendar) { values in
                mindfulMinutesByDay = values
                group.leave()
            }
        }

        if let type = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            group.enter()
            readDailyAverage(type: type, unit: HKUnit.count().unitDivided(by: .minute()), start: start, end: end, calendar: calendar) { values in
                heartRateByDay = values
                group.leave()
            }
        }

        if let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            group.enter()
            readDailyAverage(type: type, unit: HKUnit.count().unitDivided(by: .minute()), start: start, end: end, calendar: calendar) { values in
                restingHeartRateByDay = values
                group.leave()
            }
        }

        if let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            group.enter()
            readDailyAverage(type: type, unit: .secondUnit(with: .milli), start: start, end: end, calendar: calendar) { values in
                hrvByDay = values
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            let loadedSummaries = (0..<days).compactMap { offset -> HealthDaySummary? in
                guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
                let day = calendar.startOfDay(for: date)
                return HealthDaySummary(
                    date: day,
                    inBedMinutes: sleepByDay[day]?.inBedMinutes,
                    sleepMinutes: sleepByDay[day]?.sleepMinutes,
                    bedtimeMinute: sleepByDay[day]?.bedtimeMinute,
                    wakeMinute: sleepByDay[day]?.wakeMinute,
                    steps: stepsByDay[day],
                    distanceMeters: distanceByDay[day],
                    activeEnergyKcal: activeEnergyByDay[day],
                    basalEnergyKcal: basalEnergyByDay[day],
                    workoutMinutes: workoutMinutesByDay[day],
                    mindfulMinutes: mindfulMinutesByDay[day],
                    averageHeartRate: heartRateByDay[day],
                    restingHeartRate: restingHeartRateByDay[day],
                    hrvSDNN: hrvByDay[day]
                )
            }
            self.summaries = loadedSummaries.filter(\.hasSignals)
            self.state = .connected
        }
    }

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
            HKQuantityType.quantityType(forIdentifier: .stepCount),
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning),
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
            HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned),
            HKObjectType.workoutType(),
            HKObjectType.categoryType(forIdentifier: .mindfulSession),
            HKQuantityType.quantityType(forIdentifier: .heartRate),
            HKQuantityType.quantityType(forIdentifier: .restingHeartRate),
            HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        ].forEach { type in
            if let type {
                types.insert(type)
            }
        }
        return types
    }

    private func readSleepMinutes(
        start: Date,
        end: Date,
        calendar: Calendar,
        completion: @escaping ([Date: HealthSleepSummary]) -> Void
    ) {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            completion([:])
            return
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            var asleepTotals: [Date: TimeInterval] = [:]
            var inBedTotals: [Date: TimeInterval] = [:]
            var bedtimeByDay: [Date: Int] = [:]
            var wakeByDay: [Date: Int] = [:]
            for sample in samples as? [HKCategorySample] ?? [] {
                let day = calendar.startOfDay(for: sample.startDate)
                if sample.value == HKCategoryValueSleepAnalysis.inBed.rawValue {
                    inBedTotals[day, default: 0] += sample.endDate.timeIntervalSince(sample.startDate)
                }
                guard Self.isAsleepValue(sample.value) else { continue }
                asleepTotals[day, default: 0] += sample.endDate.timeIntervalSince(sample.startDate)
                let startMinute = Self.minuteOfDay(sample.startDate, calendar: calendar)
                let endMinute = Self.minuteOfDay(sample.endDate, calendar: calendar)
                bedtimeByDay[day] = Self.earlierSleepStart(current: bedtimeByDay[day], candidate: startMinute)
                wakeByDay[day] = Self.laterWake(current: wakeByDay[day], candidate: endMinute)
            }
            let days = Set(asleepTotals.keys)
                .union(inBedTotals.keys)
                .union(bedtimeByDay.keys)
                .union(wakeByDay.keys)
            let summaries = Dictionary(uniqueKeysWithValues: days.map { day in
                (
                    day,
                    HealthSleepSummary(
                        inBedMinutes: inBedTotals[day].map { Int(($0 / 60).rounded()) },
                        sleepMinutes: asleepTotals[day].map { Int(($0 / 60).rounded()) },
                        bedtimeMinute: bedtimeByDay[day],
                        wakeMinute: wakeByDay[day]
                    )
                )
            })
            completion(summaries)
        }
        healthStore.execute(query)
    }

    private func readCategoryMinutes(
        type: HKCategoryType,
        acceptedValues: Set<Int>?,
        start: Date,
        end: Date,
        calendar: Calendar,
        completion: @escaping ([Date: Int]) -> Void
    ) {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            var totals: [Date: TimeInterval] = [:]
            for sample in samples as? [HKCategorySample] ?? [] {
                if let acceptedValues = acceptedValues, !acceptedValues.contains(sample.value) { continue }
                let day = calendar.startOfDay(for: sample.startDate)
                totals[day, default: 0] += sample.endDate.timeIntervalSince(sample.startDate)
            }
            completion(totals.mapValues { Int(($0 / 60).rounded()) })
        }
        healthStore.execute(query)
    }

    private func readWorkoutMinutes(
        start: Date,
        end: Date,
        calendar: Calendar,
        completion: @escaping ([Date: Int]) -> Void
    ) {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            var totals: [Date: TimeInterval] = [:]
            for workout in samples as? [HKWorkout] ?? [] {
                let day = calendar.startOfDay(for: workout.startDate)
                totals[day, default: 0] += workout.duration
            }
            completion(totals.mapValues { Int(($0 / 60).rounded()) })
        }
        healthStore.execute(query)
    }

    private func readDailySum(
        type: HKQuantityType,
        unit: HKUnit,
        start: Date,
        end: Date,
        calendar: Calendar,
        completion: @escaping ([Date: Int]) -> Void
    ) {
        readQuantitySamples(type: type, start: start, end: end, calendar: calendar) { samples in
            var totals: [Date: Double] = [:]
            for sample in samples {
                let day = calendar.startOfDay(for: sample.startDate)
                totals[day, default: 0] += sample.quantity.doubleValue(for: unit)
            }
            completion(totals.mapValues { Int($0.rounded()) })
        }
    }

    private func readDailyAverage(
        type: HKQuantityType,
        unit: HKUnit,
        start: Date,
        end: Date,
        calendar: Calendar,
        completion: @escaping ([Date: Int]) -> Void
    ) {
        readQuantitySamples(type: type, start: start, end: end, calendar: calendar) { samples in
            var values: [Date: [Double]] = [:]
            for sample in samples {
                let day = calendar.startOfDay(for: sample.startDate)
                values[day, default: []].append(sample.quantity.doubleValue(for: unit))
            }
            completion(values.mapValues { Int(($0.reduce(0, +) / Double(max(1, $0.count))).rounded()) })
        }
    }

    private func readQuantitySamples(
        type: HKQuantityType,
        start: Date,
        end: Date,
        calendar: Calendar,
        completion: @escaping ([HKQuantitySample]) -> Void
    ) {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            completion(samples as? [HKQuantitySample] ?? [])
        }
        healthStore.execute(query)
    }

    private static func isAsleepValue(_ value: Int) -> Bool {
        value != HKCategoryValueSleepAnalysis.inBed.rawValue &&
        value != HKCategoryValueSleepAnalysis.awake.rawValue
    }

    private static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    private static func earlierSleepStart(current: Int?, candidate: Int) -> Int {
        guard let current else { return candidate }
        let currentScore = current < 12 * 60 ? current + 24 * 60 : current
        let candidateScore = candidate < 12 * 60 ? candidate + 24 * 60 : candidate
        return candidateScore < currentScore ? candidate : current
    }

    private static func laterWake(current: Int?, candidate: Int) -> Int {
        guard let current else { return candidate }
        let currentScore = current < 12 * 60 ? current : current - 24 * 60
        let candidateScore = candidate < 12 * 60 ? candidate : candidate - 24 * 60
        return candidateScore > currentScore ? candidate : current
    }
}
