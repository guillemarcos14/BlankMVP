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
            ? "Modo"
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
                name: namesById[modeId] ?? "Modo",
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
