import Foundation
import Combine
import HealthKit

struct HealthDaySummary: Identifiable, Equatable {
    var id: Date { date }
    var date: Date
    var sleepMinutes: Int?
    var steps: Int?
    var activeEnergyKcal: Int?
    var basalEnergyKcal: Int?
    var averageHeartRate: Int?
    var restingHeartRate: Int?
    var hrvSDNN: Int?

    var hasSignals: Bool {
        sleepMinutes != nil ||
        steps != nil ||
        activeEnergyKcal != nil ||
        basalEnergyKcal != nil ||
        averageHeartRate != nil ||
        restingHeartRate != nil ||
        hrvSDNN != nil
    }
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
        var sleepByDay: [Date: Int] = [:]
        var stepsByDay: [Date: Int] = [:]
        var activeEnergyByDay: [Date: Int] = [:]
        var basalEnergyByDay: [Date: Int] = [:]
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
                    sleepMinutes: sleepByDay[day],
                    steps: stepsByDay[day],
                    activeEnergyKcal: activeEnergyByDay[day],
                    basalEnergyKcal: basalEnergyByDay[day],
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
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
            HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned),
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
        completion: @escaping ([Date: Int]) -> Void
    ) {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            completion([:])
            return
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            var totals: [Date: TimeInterval] = [:]
            for sample in samples as? [HKCategorySample] ?? [] {
                guard Self.isAsleepValue(sample.value) else { continue }
                let day = calendar.startOfDay(for: sample.startDate)
                totals[day, default: 0] += sample.endDate.timeIntervalSince(sample.startDate)
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
}
