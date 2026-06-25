import Foundation
import FamilyControls

@MainActor
final class SessionStore: ObservableObject {
    @Published var isBlankActive: Bool {
        didSet {
            defaults.set(isBlankActive, forKey: Keys.isBlankActive)
        }
    }

    @Published var blankActiveSince: Date? {
        didSet {
            defaults.set(blankActiveSince?.timeIntervalSince1970, forKey: Keys.blankActiveSince)
        }
    }

    @Published var nfcTagUid: String? {
        didSet {
            defaults.set(nfcTagUid, forKey: Keys.nfcTagUid)
        }
    }

    @Published var setupComplete: Bool {
        didSet {
            defaults.set(setupComplete, forKey: Keys.setupComplete)
        }
    }

    @Published var selection: FamilyActivitySelection {
        didSet {
            saveSelection(selection)
        }
    }

    @Published var sessions: [BlankSession] {
        didSet {
            saveSessions(sessions)
        }
    }

    private let defaults = UserDefaults.standard
    private let defaultProfileId = UUID(uuidString: "A1E43B14-22E6-4B55-8E89-5E2A3C100001")!

    init() {
        isBlankActive = defaults.bool(forKey: Keys.isBlankActive)
        if let timestamp = defaults.object(forKey: Keys.blankActiveSince) as? TimeInterval, timestamp > 0 {
            blankActiveSince = Date(timeIntervalSince1970: timestamp)
        } else {
            blankActiveSince = nil
        }
        nfcTagUid = defaults.string(forKey: Keys.nfcTagUid)
        setupComplete = defaults.bool(forKey: Keys.setupComplete)
        selection = Self.loadSelection(from: defaults)
        sessions = Self.loadSessions(from: defaults)
    }

    var hasSelectedApps: Bool {
        !selection.applicationTokens.isEmpty ||
        !selection.categoryTokens.isEmpty ||
        !selection.webDomainTokens.isEmpty
    }

    var activeSession: BlankSession? {
        sessions.last { $0.isActive }
    }

    var currentWeekReport: BlankWeeklyReport {
        let weekStart = BlankWeeklySessionAggregator.startOfWeek(for: Date())
        return BlankWeeklySessionAggregator.aggregate(sessions: sessions, weekStart: weekStart)
    }

    func handleNfcTag(uid: String) -> NfcResult {
        guard let savedUid = nfcTagUid else {
            nfcTagUid = uid
            return .tagRegistered
        }

        guard savedUid == uid else {
            return .wrongTag
        }

        guard isBlankActive || hasSelectedApps else {
            return .noAppsSelected
        }

        isBlankActive.toggle()
        blankActiveSince = isBlankActive ? Date() : nil
        if isBlankActive {
            startSession(tag: uid)
        } else {
            endActiveSession()
        }
        return isBlankActive ? .bricked : .unbricked
    }

    func forgetNfcTag() {
        endActiveSession()
        nfcTagUid = nil
        isBlankActive = false
        blankActiveSince = nil
        setupComplete = false
    }

    func finishSetup() {
        setupComplete = true
    }

    private func saveSelection(_ selection: FamilyActivitySelection) {
        if let data = try? JSONEncoder().encode(selection) {
            defaults.set(data, forKey: Keys.selection)
        }
    }

    private func startSession(tag: String) {
        if activeSession != nil {
            endActiveSession()
        }

        let session = BlankSession(
            profileId: defaultProfileId,
            strategy: .nfc,
            startTag: tag
        )
        sessions.append(session)
    }

    private func endActiveSession() {
        guard let index = sessions.lastIndex(where: { $0.isActive }) else {
            return
        }

        sessions[index].end()
    }

    private func saveSessions(_ sessions: [BlankSession]) {
        if let data = try? JSONEncoder().encode(sessions) {
            defaults.set(data, forKey: Keys.sessions)
        }
    }

    private static func loadSelection(from defaults: UserDefaults) -> FamilyActivitySelection {
        guard let data = defaults.data(forKey: Keys.selection),
              let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return FamilyActivitySelection()
        }
        return decoded
    }

    private static func loadSessions(from defaults: UserDefaults) -> [BlankSession] {
        guard let data = defaults.data(forKey: Keys.sessions),
              let decoded = try? JSONDecoder().decode([BlankSession].self, from: data) else {
            return []
        }
        return decoded
    }

    enum NfcResult {
        case tagRegistered
        case bricked
        case unbricked
        case wrongTag
        case noAppsSelected
    }

    private enum Keys {
        static let isBlankActive = "isBlankActive"
        static let blankActiveSince = "blankActiveSince"
        static let nfcTagUid = "nfcTagUid"
        static let setupComplete = "setupComplete"
        static let selection = "familyActivitySelection"
        static let sessions = "blankSessions"
    }
}
