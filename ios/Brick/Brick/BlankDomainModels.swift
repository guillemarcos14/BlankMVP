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

    init(
        id: UUID = UUID(),
        profileId: UUID,
        strategy: BlankStrategyKind,
        startTag: String? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        pauseStartedAt: Date? = nil,
        pauseEndedAt: Date? = nil,
        forceStarted: Bool = false
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
    }

    var isActive: Bool {
        endedAt == nil
    }

    var duration: TimeInterval {
        (endedAt ?? Date()).timeIntervalSince(startedAt)
    }

    mutating func end(at date: Date = Date()) {
        endedAt = date
    }
}

struct BlankWeeklyReport: Equatable {
    var dailyDurations: [TimeInterval]
    var dailySessionCounts: [Int]
    var totalFocusTime: TimeInterval
    var completedSessionCount: Int
    var estimatedTimeSaved: TimeInterval
}

enum BlankWeeklySessionAggregator {
    static func startOfWeek(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    static func aggregate(
        sessions: [BlankSession],
        weekStart: Date,
        estimatedMinutesSavedPerSession: Int = 15,
        calendar: Calendar = .current
    ) -> BlankWeeklyReport {
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let completedSessions = sessions.compactMap { session -> (start: Date, end: Date)? in
            guard let endedAt = session.endedAt,
                  session.startedAt < weekEnd,
                  endedAt > weekStart else {
                return nil
            }
            return (session.startedAt, endedAt)
        }

        var dailyDurations = Array(repeating: TimeInterval.zero, count: 7)
        var dailySessionCounts = Array(repeating: 0, count: 7)

        for dayOffset in 0..<7 {
            guard let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: weekStart),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
                continue
            }

            for session in completedSessions {
                let overlapStart = max(session.start, dayStart)
                let overlapEnd = min(session.end, dayEnd)

                guard overlapStart < overlapEnd else { continue }

                dailyDurations[dayOffset] += overlapEnd.timeIntervalSince(overlapStart)
                dailySessionCounts[dayOffset] += 1
            }
        }

        return BlankWeeklyReport(
            dailyDurations: dailyDurations,
            dailySessionCounts: dailySessionCounts,
            totalFocusTime: dailyDurations.reduce(0, +),
            completedSessionCount: completedSessions.count,
            estimatedTimeSaved: TimeInterval(completedSessions.count * estimatedMinutesSavedPerSession * 60)
        )
    }
}
