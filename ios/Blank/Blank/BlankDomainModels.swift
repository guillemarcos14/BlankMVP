import Foundation

enum BlankStrategyKind: String, Codable, CaseIterable, Identifiable {
    case manual
    case nfc
    case manualStartNfcStop
    case nfcTimer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual:
            return "Manual"
        case .nfc:
            return "NFC"
        case .manualStartNfcStop:
            return "Manual + NFC"
        case .nfcTimer:
            return "NFC + Timer"
        }
    }

    var usesNFC: Bool {
        switch self {
        case .nfc, .manualStartNfcStop, .nfcTimer:
            return true
        case .manual:
            return false
        }
    }

    var hasTimer: Bool {
        switch self {
        case .nfcTimer:
            return true
        case .manual, .nfc, .manualStartNfcStop:
            return false
        }
    }
}

enum BlankEntryMode: String, Codable {
    case app
    case widget
    case nfc
    case schedule
}

enum BlankUsageEventKind: String, Codable {
    case blockStarted
    case blockEnded
    case blockBroken
}

enum BlankEndedReason: String, Codable {
    case nfc
    case manual
    case timer
    case schedule
    case emergency
    case expired
    case unknown
}

struct BlankSelectionSnapshot: Codable, Equatable {
    var applicationCount: Int
    var categoryCount: Int
    var webDomainCount: Int

    var totalCount: Int {
        applicationCount + categoryCount + webDomainCount
    }

    init(applicationCount: Int = 0, categoryCount: Int = 0, webDomainCount: Int = 0) {
        self.applicationCount = applicationCount
        self.categoryCount = categoryCount
        self.webDomainCount = webDomainCount
    }
}

struct BlankUsageEvent: Codable, Identifiable, Equatable {
    var id: UUID
    var kind: BlankUsageEventKind
    var sessionId: UUID?
    var occurredAt: Date
    var entryMode: BlankEntryMode
    var endedReason: BlankEndedReason?
    var duration: TimeInterval?
    var selectionSnapshot: BlankSelectionSnapshot
    var modeName: String?
    var localHour: Int
    var weekday: Int
    var plannedDurationMinutes: Int?

    init(
        id: UUID = UUID(),
        kind: BlankUsageEventKind,
        sessionId: UUID?,
        occurredAt: Date = Date(),
        entryMode: BlankEntryMode,
        endedReason: BlankEndedReason? = nil,
        duration: TimeInterval? = nil,
        selectionSnapshot: BlankSelectionSnapshot = BlankSelectionSnapshot(),
        modeName: String? = nil,
        localHour: Int? = nil,
        weekday: Int? = nil,
        plannedDurationMinutes: Int? = nil,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.kind = kind
        self.sessionId = sessionId
        self.occurredAt = occurredAt
        self.entryMode = entryMode
        self.endedReason = endedReason
        self.duration = duration
        self.selectionSnapshot = selectionSnapshot
        self.modeName = modeName
        self.localHour = localHour ?? calendar.component(.hour, from: occurredAt)
        self.weekday = weekday ?? calendar.component(.weekday, from: occurredAt)
        self.plannedDurationMinutes = plannedDurationMinutes
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case sessionId
        case occurredAt
        case entryMode
        case endedReason
        case duration
        case selectionSnapshot
        case modeName
        case localHour
        case weekday
        case plannedDurationMinutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decode(BlankUsageEventKind.self, forKey: .kind)
        sessionId = try container.decodeIfPresent(UUID.self, forKey: .sessionId)
        occurredAt = try container.decodeIfPresent(Date.self, forKey: .occurredAt) ?? Date()
        entryMode = try container.decodeIfPresent(BlankEntryMode.self, forKey: .entryMode) ?? .app
        endedReason = try container.decodeIfPresent(BlankEndedReason.self, forKey: .endedReason)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        selectionSnapshot = try container.decodeIfPresent(BlankSelectionSnapshot.self, forKey: .selectionSnapshot) ?? BlankSelectionSnapshot()
        modeName = try container.decodeIfPresent(String.self, forKey: .modeName)
        localHour = try container.decodeIfPresent(Int.self, forKey: .localHour) ?? Calendar.current.component(.hour, from: occurredAt)
        weekday = try container.decodeIfPresent(Int.self, forKey: .weekday) ?? Calendar.current.component(.weekday, from: occurredAt)
        plannedDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .plannedDurationMinutes)
    }
}

struct BlankProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var strategy: BlankStrategyKind
    var createdAt: Date
    var updatedAt: Date
    var physicalUnlockItems: [PhysicalUnlockItem]
    var estimatedMinutesSavedPerBlock: Int

    init(
        id: UUID = UUID(),
        name: String,
        strategy: BlankStrategyKind = .nfc,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        physicalUnlockItems: [PhysicalUnlockItem] = [],
        estimatedMinutesSavedPerBlock: Int = 15
    ) {
        self.id = id
        self.name = name
        self.strategy = strategy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.physicalUnlockItems = physicalUnlockItems
        self.estimatedMinutesSavedPerBlock = estimatedMinutesSavedPerBlock
    }
}

struct BlankFocusMode: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var selectionData: Data?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        selectionData: Data? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Mode"
            : name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.selectionData = selectionData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct BlankFocusSchedule: Codable, Equatable {
    var enabled: Bool
    var startMinute: Int
    var endMinute: Int

    init(enabled: Bool = false, startMinute: Int = 23 * 60 + 30, endMinute: Int = 8 * 60) {
        self.enabled = enabled
        self.startMinute = min(max(startMinute, 0), 1439)
        self.endMinute = min(max(endMinute, 0), 1439)
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        if startMinute < endMinute {
            return minute >= startMinute && minute < endMinute
        }
        return minute >= startMinute || minute < endMinute
    }
}

struct PhysicalUnlockItem: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case nfc
    }

    var id: UUID
    var name: String
    var kind: Kind
    var codeValue: String

    init(id: UUID = UUID(), name: String, kind: Kind, codeValue: String) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kind = kind
        self.codeValue = Self.normalized(codeValue, kind: kind)
    }

    static func normalized(_ value: String, kind: Kind) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmed
    }
}

struct BlankSession: Codable, Identifiable, Equatable {
    var id: UUID
    var profileId: UUID
    var strategy: BlankStrategyKind
    var startTag: String?
    var startedAt: Date
    var endedAt: Date?
    var pauseStartedAt: Date?
    var pauseEndedAt: Date?
    var forceStarted: Bool
    var entryMode: BlankEntryMode?
    var endedReason: BlankEndedReason?
    var selectionSnapshot: BlankSelectionSnapshot?
    var modeName: String?
    var localStartHour: Int?
    var startWeekday: Int?
    var plannedDurationMinutes: Int?

    init(
        id: UUID = UUID(),
        profileId: UUID,
        strategy: BlankStrategyKind,
        startTag: String? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        pauseStartedAt: Date? = nil,
        pauseEndedAt: Date? = nil,
        forceStarted: Bool = false,
        entryMode: BlankEntryMode? = nil,
        endedReason: BlankEndedReason? = nil,
        selectionSnapshot: BlankSelectionSnapshot? = nil,
        modeName: String? = nil,
        localStartHour: Int? = nil,
        startWeekday: Int? = nil,
        plannedDurationMinutes: Int? = nil,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.profileId = profileId
        self.strategy = strategy
        self.startTag = startTag
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.pauseStartedAt = pauseStartedAt
        self.pauseEndedAt = pauseEndedAt
        self.forceStarted = forceStarted
        self.entryMode = entryMode
        self.endedReason = endedReason
        self.selectionSnapshot = selectionSnapshot
        self.modeName = modeName
        self.localStartHour = localStartHour ?? calendar.component(.hour, from: startedAt)
        self.startWeekday = startWeekday ?? calendar.component(.weekday, from: startedAt)
        self.plannedDurationMinutes = plannedDurationMinutes
    }

    var isActive: Bool {
        endedAt == nil
    }

    var duration: TimeInterval {
        (endedAt ?? Date()).timeIntervalSince(startedAt)
    }

    mutating func end(at date: Date = Date(), endedReason: BlankEndedReason? = nil) {
        endedAt = date
        self.endedReason = endedReason
    }

    enum CodingKeys: String, CodingKey {
        case id
        case profileId
        case strategy
        case startTag
        case startedAt
        case endedAt
        case pauseStartedAt
        case pauseEndedAt
        case forceStarted
        case entryMode
        case endedReason
        case selectionSnapshot
        case modeName
        case localStartHour
        case startWeekday
        case plannedDurationMinutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        profileId = try container.decode(UUID.self, forKey: .profileId)
        strategy = try container.decode(BlankStrategyKind.self, forKey: .strategy)
        startTag = try container.decodeIfPresent(String.self, forKey: .startTag)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        pauseStartedAt = try container.decodeIfPresent(Date.self, forKey: .pauseStartedAt)
        pauseEndedAt = try container.decodeIfPresent(Date.self, forKey: .pauseEndedAt)
        forceStarted = try container.decodeIfPresent(Bool.self, forKey: .forceStarted) ?? false
        entryMode = try container.decodeIfPresent(BlankEntryMode.self, forKey: .entryMode)
        endedReason = try container.decodeIfPresent(BlankEndedReason.self, forKey: .endedReason)
        selectionSnapshot = try container.decodeIfPresent(BlankSelectionSnapshot.self, forKey: .selectionSnapshot)
        modeName = try container.decodeIfPresent(String.self, forKey: .modeName)
        localStartHour = try container.decodeIfPresent(Int.self, forKey: .localStartHour) ?? Calendar.current.component(.hour, from: startedAt)
        startWeekday = try container.decodeIfPresent(Int.self, forKey: .startWeekday) ?? Calendar.current.component(.weekday, from: startedAt)
        plannedDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .plannedDurationMinutes)
    }
}

struct BlankWeeklyReport: Equatable {
    var dailyDurations: [TimeInterval]
    var dailySessionCounts: [Int]
    var totalFocusTime: TimeInterval
    var completedSessionCount: Int
    var estimatedTimeSaved: TimeInterval
    var averageSessionDuration: TimeInterval {
        completedSessionCount > 0 ? totalFocusTime / Double(completedSessionCount) : 0
    }
}

enum BlankWeeklySessionAggregator {
    static func startOfWeek(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    static func aggregate(
        sessions: [BlankSession],
        weekStart: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> BlankWeeklyReport {
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let trackedSessions = sessions.compactMap { session -> (start: Date, end: Date, completed: Bool)? in
            let sessionEnd = session.endedAt ?? now
            guard session.startedAt < weekEnd,
                  sessionEnd > weekStart,
                  sessionEnd > session.startedAt else {
                return nil
            }
            return (session.startedAt, sessionEnd, session.endedAt != nil)
        }

        var dailyDurations = Array(repeating: TimeInterval.zero, count: 7)
        var dailySessionCounts = Array(repeating: 0, count: 7)

        for dayOffset in 0..<7 {
            guard let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: weekStart),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
                continue
            }

            for session in trackedSessions {
                let overlapStart = max(session.start, dayStart)
                let overlapEnd = min(session.end, dayEnd)

                guard overlapStart < overlapEnd else { continue }

                dailyDurations[dayOffset] += overlapEnd.timeIntervalSince(overlapStart)
                dailySessionCounts[dayOffset] += 1
            }
        }

        let totalFocusTime = dailyDurations.reduce(0, +)
        let completedSessionCount = trackedSessions.filter { $0.completed }.count
        let trackedSessionCount = max(completedSessionCount, trackedSessions.count)
        let sessionBaseSavedTime = TimeInterval(trackedSessionCount * 7 * 60)
        let protectedTimeSavedShare = totalFocusTime * 0.10
        let estimatedTimeSaved = min(
            totalFocusTime,
            sessionBaseSavedTime + protectedTimeSavedShare
        )

        return BlankWeeklyReport(
            dailyDurations: dailyDurations,
            dailySessionCounts: dailySessionCounts,
            totalFocusTime: totalFocusTime,
            completedSessionCount: trackedSessionCount,
            estimatedTimeSaved: estimatedTimeSaved
        )
    }
}

struct BlankActivityDay: Identifiable, Equatable {
    var id: Date { date }
    var date: Date
    var totalFocusTime: TimeInterval
    var sessionCount: Int
}

struct BlankModeActivity: Identifiable, Equatable {
    var id: UUID { modeId }
    var modeId: UUID
    var name: String
    var totalFocusTime: TimeInterval
    var sessionCount: Int
}

struct BlankProgressReport: Equatable {
    var weeklyReport: BlankWeeklyReport
    var recentActivity: [BlankActivityDay]
    var modeActivity: [BlankModeActivity]
    var currentStreakDays: Int
    var longestStreakDays: Int
}

struct DigitalWellnessPlanItem: Codable, Equatable, Identifiable {
    var id: Int
    var title: String
    var action: String
}

struct DigitalWellnessDiagnosis: Codable, Equatable {
    var archetype: String
    var riskTitle: String
    var riskBody: String
    var primaryGoal: String
    var weakMoment: String
    var dailyHours: Double
    var initialBlockMinutes: Int
    var recommendedHour: Int
    var plan: [DigitalWellnessPlanItem]
    var createdAt: Date
}

struct SmartBlockRecommendation: Equatable {
    var title: String
    var detail: String
    var durationMinutes: Int
}

struct RelapseIntervention: Equatable {
    var headline: String
    var cost: String
    var alternative: String
}

enum DigitalWellnessAI {
    private static let diagnosisKey = "blankDigitalWellnessDiagnosis"

    static func saveInitialDiagnosis(
        defaults: UserDefaults = BlankSharedState.defaults,
        goal: String,
        profile: String,
        dailyHours: Double,
        selectionCount: Int,
        now: Date = Date()
    ) {
        let diagnosis = initialDiagnosis(
            goal: goal,
            profile: profile,
            dailyHours: dailyHours,
            selectionCount: selectionCount,
            now: now
        )
        guard let data = try? JSONEncoder().encode(diagnosis) else { return }
        defaults.set(data, forKey: diagnosisKey)
    }

    static func loadDiagnosis(defaults: UserDefaults = BlankSharedState.defaults) -> DigitalWellnessDiagnosis? {
        guard let data = defaults.data(forKey: diagnosisKey) else { return nil }
        return try? JSONDecoder().decode(DigitalWellnessDiagnosis.self, from: data)
    }

    static func currentDiagnosis(
        defaults: UserDefaults = BlankSharedState.defaults,
        events: [BlankUsageEvent],
        sessions: [BlankSession],
        selectionCount: Int,
        now: Date = Date()
    ) -> DigitalWellnessDiagnosis {
        let stored = loadDiagnosis(defaults: defaults)
        let goal = defaults.string(forKey: "blankOnboardingGoal") ?? stored?.primaryGoal ?? ""
        let profile = defaults.string(forKey: "blankOnboardingProfile") ?? ""
        let dailyHours = defaults.object(forKey: "blankOnboardingDailyHours") == nil
            ? stored?.dailyHours ?? 4.5
            : defaults.double(forKey: "blankOnboardingDailyHours")
        var diagnosis = stored ?? initialDiagnosis(
            goal: goal,
            profile: profile,
            dailyHours: dailyHours,
            selectionCount: selectionCount,
            now: now
        )

        if let weakHour = weakHour(events: events, sessions: sessions, now: now) {
            diagnosis.recommendedHour = weakHour
            diagnosis.weakMoment = hourRangeText(weakHour)
        }
        return diagnosis
    }

    static func smartBlockRecommendation(
        defaults: UserDefaults = BlankSharedState.defaults,
        events: [BlankUsageEvent],
        sessions: [BlankSession],
        selectionCount: Int,
        now: Date = Date()
    ) -> SmartBlockRecommendation {
        let diagnosis = currentDiagnosis(
            defaults: defaults,
            events: events,
            sessions: sessions,
            selectionCount: selectionCount,
            now: now
        )

        if let weakHour = weakHour(events: events, sessions: sessions, now: now) {
            let minutes = minutesUntilNextHour(weakHour, now: now)
            if minutes <= 90 {
                return SmartBlockRecommendation(
                    title: "Protect your weak window",
                    detail: "\(hourRangeText(weakHour)) is your highest-risk window. Start a \(diagnosis.initialBlockMinutes)-min block.",
                    durationMinutes: diagnosis.initialBlockMinutes
                )
            }
        }

        return SmartBlockRecommendation(
            title: "Start your \(diagnosis.archetype) plan",
            detail: "Day 1: protect \(hourRangeText(diagnosis.recommendedHour)) with a \(diagnosis.initialBlockMinutes)-min block.",
            durationMinutes: diagnosis.initialBlockMinutes
        )
    }

    static func relapseIntervention(
        defaults: UserDefaults = BlankSharedState.defaults,
        events: [BlankUsageEvent],
        sessions: [BlankSession],
        selectionCount: Int,
        now: Date = Date()
    ) -> RelapseIntervention {
        let diagnosis = currentDiagnosis(
            defaults: defaults,
            events: events,
            sessions: sessions,
            selectionCount: selectionCount,
            now: now
        )
        let weakHour = weakHour(events: events, sessions: sessions, now: now) ?? diagnosis.recommendedHour
        let isWeakWindow = Calendar.current.component(.hour, from: now) == weakHour
        return RelapseIntervention(
            headline: isWeakWindow ? "This is your risk window." : "This break trains the loop.",
            cost: "Breaking now weakens your \(diagnosis.archetype.lowercased()) plan.",
            alternative: "Try 5 more minutes, then decide again."
        )
    }

    static func weakHour(events: [BlankUsageEvent], sessions: [BlankSession], now: Date = Date()) -> Int? {
        let calendar = Calendar.current
        let weekStart = BlankWeeklySessionAggregator.startOfWeek(for: now, calendar: calendar)
        let brokenEventHours = events
            .filter { event in
                event.occurredAt >= weekStart &&
                event.occurredAt <= now &&
                (event.kind == .blockBroken || event.endedReason == .emergency || event.endedReason == .manual)
            }
            .map(\.localHour)
        let emergencySessionHours = sessions
            .filter { session in
                let sessionEnd = session.endedAt ?? now
                return session.startedAt <= now &&
                sessionEnd >= weekStart &&
                (session.endedReason == .emergency || session.endedReason == .manual)
            }
            .compactMap(\.localStartHour)

        return mostCommonValue(brokenEventHours + emergencySessionHours)
    }

    static func hourRangeText(_ hour: Int) -> String {
        "\(String(format: "%02d:00", hour))-\(String(format: "%02d:00", (hour + 1) % 24))"
    }

    private static func initialDiagnosis(
        goal: String,
        profile: String,
        dailyHours: Double,
        selectionCount: Int,
        now: Date
    ) -> DigitalWellnessDiagnosis {
        let goalText = goal.isEmpty ? "Build healthier screen habits" : goal
        let normalizedGoal = goal.lowercased()
        let normalizedProfile = profile.lowercased()

        let archetype: String
        let riskTitle: String
        let riskBody: String
        let recommendedHour: Int
        let blockMinutes: Int

        if normalizedGoal.contains("sleep") || normalizedProfile.contains("night") {
            archetype = "Night Scroller"
            riskTitle = "Late-night scroll risk"
            riskBody = "Your highest leverage habit is protecting the final hour before sleep."
            recommendedHour = 22
            blockMinutes = 45
        } else if normalizedGoal.contains("social") || normalizedProfile.contains("social") || normalizedProfile.contains("boredom") || dailyHours >= 6.5 {
            archetype = "Dopamine Loop"
            riskTitle = "High stimulation risk"
            riskBody = "Your phone is likely filling low-energy moments before you notice."
            recommendedHour = 20
            blockMinutes = 30
        } else if normalizedGoal.contains("present") || normalizedProfile.contains("caregiver") {
            archetype = "Presence Drifter"
            riskTitle = "Attention leak risk"
            riskBody = "The main win is protecting short windows where you want to be more present."
            recommendedHour = 18
            blockMinutes = 25
        } else if normalizedProfile.contains("study") || normalizedProfile.contains("work") || normalizedGoal.contains("work") || normalizedGoal.contains("focus") || normalizedProfile.contains("technology") {
            archetype = "Focus Breaker"
            riskTitle = "Deep-work interruption risk"
            riskBody = "Your biggest gain is starting blocks before the first distraction."
            recommendedHour = normalizedProfile.contains("study") ? 16 : 9
            blockMinutes = 45
        } else {
            archetype = "Habit Rebuilder"
            riskTitle = "Automatic checking risk"
            riskBody = "Your plan should make the first block easy and repeatable."
            recommendedHour = normalizedProfile.contains("morning") ? 8 : Calendar.current.component(.hour, from: now)
            blockMinutes = selectionCount < 3 ? 25 : 35
        }

        let weakMoment = hourRangeText(recommendedHour)
        return DigitalWellnessDiagnosis(
            archetype: archetype,
            riskTitle: riskTitle,
            riskBody: riskBody,
            primaryGoal: goalText,
            weakMoment: weakMoment,
            dailyHours: dailyHours,
            initialBlockMinutes: blockMinutes,
            recommendedHour: recommendedHour,
            plan: sevenDayPlan(archetype: archetype, weakMoment: weakMoment, blockMinutes: blockMinutes),
            createdAt: now
        )
    }

    private static func sevenDayPlan(archetype: String, weakMoment: String, blockMinutes: Int) -> [DigitalWellnessPlanItem] {
        [
            DigitalWellnessPlanItem(id: 1, title: "Day 1", action: "\(blockMinutes) min during \(weakMoment)."),
            DigitalWellnessPlanItem(id: 2, title: "Day 2", action: "Repeat the same window with the same apps."),
            DigitalWellnessPlanItem(id: 3, title: "Day 3", action: "Add 10 min if there was no emergency."),
            DigitalWellnessPlanItem(id: 4, title: "Day 4", action: "Start 10 min before the urge usually appears."),
            DigitalWellnessPlanItem(id: 5, title: "Day 5", action: "Keep one strict block and one short reset."),
            DigitalWellnessPlanItem(id: 6, title: "Day 6", action: "Review which app pulled hardest."),
            DigitalWellnessPlanItem(id: 7, title: "Day 7", action: "Repeat your best \(archetype.lowercased()) block.")
        ]
    }

    private static func minutesUntilNextHour(_ hour: Int, now: Date) -> Int {
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        if currentHour == hour {
            return 0
        }
        let hoursUntil = (hour - currentHour + 24) % 24
        return max(0, hoursUntil * 60 - currentMinute)
    }

    private static func mostCommonValue<T: Hashable>(_ values: [T]) -> T? {
        let counts = values.reduce(into: [T: Int]()) { counts, value in
            counts[value, default: 0] += 1
        }
        return counts.max { lhs, rhs in lhs.value < rhs.value }?.key
    }
}

enum BlankProgressAggregator {
    static func aggregate(
        sessions: [BlankSession],
        modes: [BlankFocusMode],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> BlankProgressReport {
        let weekStart = BlankWeeklySessionAggregator.startOfWeek(for: now, calendar: calendar)
        let weeklyReport = BlankWeeklySessionAggregator.aggregate(
            sessions: sessions,
            weekStart: weekStart,
            now: now,
            calendar: calendar
        )

        return BlankProgressReport(
            weeklyReport: weeklyReport,
            recentActivity: activityDays(sessions: sessions, days: 28, endingOn: now, calendar: calendar),
            modeActivity: modeActivity(sessions: sessions, modes: modes, weekStart: weekStart, now: now, calendar: calendar),
            currentStreakDays: currentStreakDays(sessions: sessions, now: now, calendar: calendar),
            longestStreakDays: longestStreakDays(sessions: sessions, days: 365, endingOn: now, calendar: calendar)
        )
    }

    static func activityDays(
        sessions: [BlankSession],
        days: Int,
        endingOn endDate: Date,
        calendar: Calendar = .current
    ) -> [BlankActivityDay] {
        let endDay = calendar.startOfDay(for: endDate)
        guard let startDay = calendar.date(byAdding: .day, value: -(days - 1), to: endDay) else {
            return []
        }

        return (0..<days).compactMap { offset in
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: startDay),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
                return nil
            }

            let overlapping = sessions.compactMap { session -> TimeInterval? in
                let sessionEnd = session.endedAt ?? endDate
                let overlapStart = max(session.startedAt, dayStart)
                let overlapEnd = min(sessionEnd, dayEnd)
                guard overlapStart < overlapEnd else { return nil }
                return overlapEnd.timeIntervalSince(overlapStart)
            }

            return BlankActivityDay(
                date: dayStart,
                totalFocusTime: overlapping.reduce(0, +),
                sessionCount: overlapping.count
            )
        }
    }

    private static func modeActivity(
        sessions: [BlankSession],
        modes: [BlankFocusMode],
        weekStart: Date,
        now: Date,
        calendar: Calendar
    ) -> [BlankModeActivity] {
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
            return []
        }

        let namesById = Dictionary(uniqueKeysWithValues: modes.map { ($0.id, $0.name) })
        var totals: [UUID: (duration: TimeInterval, count: Int)] = [:]

        for session in sessions {
            let sessionEnd = session.endedAt ?? now
            guard session.startedAt < weekEnd,
                  sessionEnd > weekStart,
                  sessionEnd > session.startedAt else {
                continue
            }

            let overlapStart = max(session.startedAt, weekStart)
            let overlapEnd = min(sessionEnd, weekEnd)
            guard overlapStart < overlapEnd else { continue }

            let current = totals[session.profileId] ?? (0, 0)
            totals[session.profileId] = (
                current.duration + overlapEnd.timeIntervalSince(overlapStart),
                current.count + 1
            )
        }

        return totals.map { entry in
            let modeId = entry.key
            let value = entry.value
            return BlankModeActivity(
                modeId: modeId,
                name: namesById[modeId] ?? "Mode",
                totalFocusTime: value.duration,
                sessionCount: value.count
            )
        }
        .sorted { lhs, rhs in
            if lhs.totalFocusTime == rhs.totalFocusTime {
                return lhs.sessionCount > rhs.sessionCount
            }
            return lhs.totalFocusTime > rhs.totalFocusTime
        }
    }

    private static func currentStreakDays(
        sessions: [BlankSession],
        now: Date,
        calendar: Calendar
    ) -> Int {
        let activeDays = completedSessionDays(sessions: sessions, calendar: calendar)
        var expectedDay = calendar.startOfDay(for: now)
        var streak = 0

        while activeDays.contains(expectedDay) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: expectedDay) else {
                break
            }
            expectedDay = previousDay
        }

        return streak
    }

    private static func longestStreakDays(
        sessions: [BlankSession],
        days: Int,
        endingOn endDate: Date,
        calendar: Calendar
    ) -> Int {
        let activeDays = completedSessionDays(sessions: sessions, calendar: calendar)
        let endDay = calendar.startOfDay(for: endDate)
        guard let startDay = calendar.date(byAdding: .day, value: -(days - 1), to: endDay) else {
            return 0
        }

        var currentDay = startDay
        var currentStreak = 0
        var longestStreak = 0

        while currentDay <= endDay {
            if activeDays.contains(currentDay) {
                currentStreak += 1
                longestStreak = max(longestStreak, currentStreak)
            } else {
                currentStreak = 0
            }

            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay) else {
                break
            }
            currentDay = nextDay
        }

        return longestStreak
    }

    private static func completedSessionDays(
        sessions: [BlankSession],
        calendar: Calendar
    ) -> Set<Date> {
        Set(
            sessions.compactMap { session in
                guard let endedAt = session.endedAt else { return nil }
                return calendar.startOfDay(for: endedAt)
            }
        )
    }
}
