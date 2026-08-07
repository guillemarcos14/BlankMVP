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
        guard let selection = loadSelection(from: defaults) else { return 0 }
        return selection.applicationTokens.count +
            selection.categoryTokens.count +
            selection.webDomainTokens.count
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
        appendSession(defaults: defaults, now: now)
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
        endActiveSession(defaults: defaults, now: now)
        return true
    }

    private static func appendSession(defaults: UserDefaults, now: Date) {
        let modeId = defaults.string(forKey: Keys.currentModeId).flatMap(UUID.init(uuidString:)) ?? defaultModeId
        let session = BlankSession(
            profileId: modeId,
            strategy: .manualStartNfcStop,
            startedAt: now
        )
        var sessions = loadSessions(defaults: defaults)
        if let index = sessions.lastIndex(where: { $0.isActive }) {
            sessions[index].end(at: now)
        }
        sessions.append(session)
        saveSessions(sessions, defaults: defaults)
    }

    private static func endActiveSession(defaults: UserDefaults, now: Date) {
        var sessions = loadSessions(defaults: defaults)
        guard let index = sessions.lastIndex(where: { $0.isActive }) else { return }
        sessions[index].end(at: now)
        saveSessions(sessions, defaults: defaults)
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
        static let currentModeId = "blankCurrentModeId"
    }
}
