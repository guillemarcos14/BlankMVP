import FamilyControls
import Foundation

enum BlankSharedState {
    static let appGroupIdentifier = "group.com.blanknfc.app.ios"
    static let defaultModeId = UUID(uuidString: "A1E43B14-22E6-4B55-8E89-5E2A3C100001")!

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    static func hasConfiguredBlock(in defaults: UserDefaults = Self.defaults) -> Bool {
        selectionCount(in: defaults) > 0
    }

    static func selectionCount(in defaults: UserDefaults = Self.defaults) -> Int {
        selectionSnapshot(in: defaults).totalCount
    }

    static func selectionSnapshot(in defaults: UserDefaults = Self.defaults) -> BlankSelectionSnapshot {
        guard let selection = loadSelection(from: defaults) else {
            return BlankSelectionSnapshot()
        }
        return BlankSelectionSnapshot(
            applicationCount: selection.applicationTokens.count,
            categoryCount: selection.categoryTokens.count,
            webDomainCount: selection.webDomainTokens.count
        )
    }

    static func loadSelection(from defaults: UserDefaults = Self.defaults) -> FamilyActivitySelection? {
        guard let data = defaults.data(forKey: Keys.selection) else { return nil }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    static func loadActiveState(now: Date = Date(), defaults: UserDefaults = Self.defaults) -> ActiveState {
        let isActive = defaults.bool(forKey: Keys.isBlankActive)
        let startedAt = date(forKey: Keys.blankActiveSince, defaults: defaults)
        let endsAt = date(forKey: Keys.blankActiveUntil, defaults: defaults)

        if isActive, let endsAt, now >= endsAt {
            return ActiveState(isActive: false, startedAt: startedAt, endsAt: endsAt)
        }

        return ActiveState(isActive: isActive, startedAt: startedAt, endsAt: endsAt)
    }

    static func startQuickBlock(defaults: UserDefaults = Self.defaults, now: Date = Date()) -> Bool {
        guard hasConfiguredBlock(in: defaults) else { return false }
        defaults.set(true, forKey: Keys.isBlankActive)
        defaults.set(now.timeIntervalSince1970, forKey: Keys.blankActiveSince)
        defaults.removeObject(forKey: Keys.blankActiveUntil)
        defaults.removeObject(forKey: "blankQuickBlockDurationMinutes")
        appendSession(defaults: defaults, now: now, entryMode: .widget)
        return true
    }

    @discardableResult
    static func finishExpiredBlock(defaults: UserDefaults = Self.defaults, now: Date = Date()) -> Bool {
        guard defaults.bool(forKey: Keys.isBlankActive),
              let endsAt = date(forKey: Keys.blankActiveUntil, defaults: defaults),
              now >= endsAt else {
            return false
        }

        defaults.set(false, forKey: Keys.isBlankActive)
        defaults.removeObject(forKey: Keys.blankActiveSince)
        defaults.removeObject(forKey: Keys.blankActiveUntil)
        endActiveSession(defaults: defaults, now: now, endedReason: activeExpiredReason(defaults: defaults))
        return true
    }

    private static func activeExpiredReason(defaults: UserDefaults) -> BlankEndedReason {
        let activeSession = loadSessions(defaults: defaults).last { $0.isActive }
        return activeSession?.plannedDurationMinutes == nil ? .expired : .timer
    }

    private static func appendSession(defaults: UserDefaults, now: Date, entryMode: BlankEntryMode) {
        let modeId = defaults.string(forKey: Keys.currentModeId).flatMap(UUID.init(uuidString:)) ?? defaultModeId
        let modeName = currentModeName(defaults: defaults, modeId: modeId)
        let snapshot = selectionSnapshot(in: defaults)
        let session = BlankSession(
            profileId: modeId,
            strategy: .manual,
            startedAt: now,
            entryMode: entryMode,
            selectionSnapshot: snapshot,
            modeName: modeName
        )
        var sessions = loadSessions(defaults: defaults)
        if let index = sessions.lastIndex(where: { $0.isActive }) {
            sessions[index].end(at: now, endedReason: .unknown)
            appendUsageEvent(
                defaults: defaults,
                kind: .blockEnded,
                session: sessions[index],
                entryMode: entryMode,
                endedReason: .unknown,
                now: now
            )
        }
        sessions.append(session)
        saveSessions(sessions, defaults: defaults)
        appendUsageEvent(
            defaults: defaults,
            kind: .blockStarted,
            session: session,
            entryMode: entryMode,
            now: now,
            selectionSnapshot: snapshot,
            modeName: modeName
        )
    }

    private static func endActiveSession(defaults: UserDefaults, now: Date, endedReason: BlankEndedReason) {
        var sessions = loadSessions(defaults: defaults)
        guard let index = sessions.lastIndex(where: { $0.isActive }) else { return }
        sessions[index].end(at: now, endedReason: endedReason)
        saveSessions(sessions, defaults: defaults)
        appendUsageEvent(
            defaults: defaults,
            kind: .blockEnded,
            session: sessions[index],
            entryMode: sessions[index].entryMode ?? .widget,
            endedReason: endedReason,
            now: now
        )
    }

    private static func loadSessions(defaults: UserDefaults) -> [BlankSession] {
        guard let data = defaults.data(forKey: Keys.sessions),
              let sessions = try? JSONDecoder().decode([BlankSession].self, from: data) else {
            return []
        }
        return sessions
    }

    private static func saveSessions(_ sessions: [BlankSession], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        defaults.set(data, forKey: Keys.sessions)
    }

    private static func appendUsageEvent(
        defaults: UserDefaults,
        kind: BlankUsageEventKind,
        session: BlankSession,
        entryMode: BlankEntryMode,
        endedReason: BlankEndedReason? = nil,
        now: Date,
        selectionSnapshot: BlankSelectionSnapshot? = nil,
        modeName: String? = nil
    ) {
        var events = loadUsageEvents(defaults: defaults)
        events.append(BlankUsageEvent(
            kind: kind,
            sessionId: session.id,
            occurredAt: now,
            entryMode: entryMode,
            endedReason: endedReason,
            duration: kind == .blockStarted ? nil : session.duration,
            selectionSnapshot: selectionSnapshot ?? session.selectionSnapshot ?? Self.selectionSnapshot(in: defaults),
            modeName: modeName ?? session.modeName,
            plannedDurationMinutes: session.plannedDurationMinutes
        ))
        if events.count > 500 {
            events.removeFirst(events.count - 500)
        }
        saveUsageEvents(events, defaults: defaults)
    }

    private static func loadUsageEvents(defaults: UserDefaults) -> [BlankUsageEvent] {
        guard let data = defaults.data(forKey: Keys.usageEvents),
              let events = try? JSONDecoder().decode([BlankUsageEvent].self, from: data) else {
            return []
        }
        return events
    }

    private static func saveUsageEvents(_ events: [BlankUsageEvent], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        defaults.set(data, forKey: Keys.usageEvents)
    }

    private static func currentModeName(defaults: UserDefaults, modeId: UUID) -> String? {
        guard let data = defaults.data(forKey: Keys.focusModes),
              let modes = try? JSONDecoder().decode([BlankFocusMode].self, from: data) else {
            return nil
        }
        return modes.first { $0.id == modeId }?.name
    }

    private static func date(forKey key: String, defaults: UserDefaults) -> Date? {
        guard let timestamp = defaults.object(forKey: key) as? TimeInterval, timestamp > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    struct ActiveState {
        var isActive: Bool
        var startedAt: Date?
        var endsAt: Date?

        func elapsedSeconds(now: Date = Date()) -> Int {
            guard isActive, let startedAt else { return 0 }
            return max(0, Int(now.timeIntervalSince(startedAt)))
        }
    }

    enum Keys {
        static let isBlankActive = "isBlankActive"
        static let blankActiveSince = "blankActiveSince"
        static let blankActiveUntil = "blankActiveUntil"
        static let selection = "familyActivitySelection"
        static let sessions = "blankSessions"
        static let usageEvents = "blankUsageEvents"
        static let currentModeId = "blankCurrentModeId"
        static let focusModes = "blankFocusModes"
    }
}
