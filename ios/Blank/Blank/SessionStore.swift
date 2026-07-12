import FamilyControls
import Foundation

@MainActor
final class SessionStore: ObservableObject {
    static let defaultModeId = UUID(uuidString: "A1E43B14-22E6-4B55-8E89-5E2A3C100001")!

    @Published var isBlankActive: Bool {
        didSet { defaults.set(isBlankActive, forKey: Keys.isBlankActive) }
    }

    @Published var blankActiveSince: Date? {
        didSet { defaults.set(blankActiveSince?.timeIntervalSince1970, forKey: Keys.blankActiveSince) }
    }

    @Published var blankActiveUntil: Date? {
        didSet { defaults.set(blankActiveUntil?.timeIntervalSince1970, forKey: Keys.blankActiveUntil) }
    }

    @Published var nfcTagUid: String? {
        didSet { defaults.set(nfcTagUid, forKey: Keys.nfcTagUid) }
    }

    @Published var setupComplete: Bool {
        didSet { defaults.set(setupComplete, forKey: Keys.setupComplete) }
    }

    @Published var selection: FamilyActivitySelection {
        didSet {
            saveSelection(selection)
            updateCurrentModeSelection(selection)
        }
    }

    @Published var sessions: [BlankSession] {
        didSet { saveSessions(sessions) }
    }

    @Published var focusModes: [BlankFocusMode] {
        didSet { saveFocusModes(focusModes) }
    }

    @Published var currentModeId: UUID {
        didSet { defaults.set(currentModeId.uuidString, forKey: Keys.currentModeId) }
    }

    @Published var schedule: BlankFocusSchedule {
        didSet { saveSchedule(schedule) }
    }

    @Published var schedulePausedUntil: Date? {
        didSet { defaults.set(schedulePausedUntil?.timeIntervalSince1970, forKey: Keys.schedulePausedUntil) }
    }

    @Published var backgroundThemeId: String {
        didSet { defaults.set(backgroundThemeId, forKey: Keys.backgroundThemeId) }
    }

    @Published private(set) var deviceActivityTimerScheduled: Bool {
        didSet { defaults.set(deviceActivityTimerScheduled, forKey: Keys.deviceActivityTimerScheduled) }
    }

    #if DEBUG
    private var previewSelectionCount: Int?
    #endif

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isBlankActive = defaults.bool(forKey: Keys.isBlankActive)
        if let timestamp = defaults.object(forKey: Keys.blankActiveSince) as? TimeInterval, timestamp > 0 {
            blankActiveSince = Date(timeIntervalSince1970: timestamp)
        } else {
            blankActiveSince = nil
        }
        if let timestamp = defaults.object(forKey: Keys.blankActiveUntil) as? TimeInterval, timestamp > 0 {
            blankActiveUntil = Date(timeIntervalSince1970: timestamp)
        } else {
            blankActiveUntil = nil
        }
        nfcTagUid = defaults.string(forKey: Keys.nfcTagUid)
        setupComplete = defaults.bool(forKey: Keys.setupComplete)
        let loadedSelection = Self.loadSelection(from: defaults)
        let loadedFocusModes = Self.loadFocusModes(from: defaults, fallbackSelection: loadedSelection)
        let storedModeId = defaults.string(forKey: Keys.currentModeId).flatMap(UUID.init(uuidString:))
        let loadedModeId = storedModeId.flatMap { id in loadedFocusModes.first(where: { $0.id == id })?.id }
            ?? loadedFocusModes.first?.id
            ?? Self.defaultModeId

        selection = loadedSelection
        sessions = Self.loadSessions(from: defaults)
        focusModes = loadedFocusModes
        currentModeId = loadedModeId
        schedule = Self.loadSchedule(from: defaults)
        backgroundThemeId = defaults.string(forKey: Keys.backgroundThemeId) ?? "grey"
        deviceActivityTimerScheduled = defaults.bool(forKey: Keys.deviceActivityTimerScheduled)
        if let timestamp = defaults.object(forKey: Keys.schedulePausedUntil) as? TimeInterval, timestamp > 0 {
            schedulePausedUntil = Date(timeIntervalSince1970: timestamp)
        } else {
            schedulePausedUntil = nil
        }

        let currentMode = loadedFocusModes.first { $0.id == loadedModeId }
            ?? loadedFocusModes.first
            ?? BlankFocusMode(id: Self.defaultModeId, name: "Rutina diaria")

        if let currentSelection = Self.selection(from: currentMode.selectionData) {
            selection = currentSelection
        }
    }

    var currentMode: BlankFocusMode {
        focusModes.first { $0.id == currentModeId }
            ?? focusModes.first
            ?? BlankFocusMode(id: Self.defaultModeId, name: "Rutina diaria")
    }

    var hasSelectedApps: Bool {
        selectionCount > 0
    }

    var selectionCount: Int {
        #if DEBUG
        if let previewSelectionCount {
            return previewSelectionCount
        }
        #endif
        return (
            selection.applicationTokens.count +
            selection.categoryTokens.count +
            selection.webDomainTokens.count
        )
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

        if isBlankActive {
            if schedule.enabled, schedule.contains(Date()) {
                return pauseScheduleWithNfc()
            }
            return deactivateBlank()
        }

        return activateBlank()
    }

    func activateBlank(forceStarted: Bool = false, durationMinutes: Int? = nil) -> NfcResult {
        guard hasSelectedApps else {
            return .noAppsSelected
        }
        guard !isBlankActive else {
            return .blanked
        }

        isBlankActive = true
        blankActiveSince = Date()
        if let durationMinutes, durationMinutes > 0 {
            blankActiveUntil = Date().addingTimeInterval(TimeInterval(durationMinutes * 60))
            deviceActivityTimerScheduled = DeviceActivityTimerScheduler.start(
                modeId: currentModeId,
                durationMinutes: durationMinutes
            )
        } else {
            blankActiveUntil = nil
            deviceActivityTimerScheduled = false
        }
        startSession(tag: nfcTagUid, forceStarted: forceStarted)
        return .blanked
    }

    func pauseScheduleWithNfc(minutes: Int = 5) -> NfcResult {
        schedulePausedUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        _ = deactivateBlank()
        return .schedulePaused
    }

    func deactivateBlank() -> NfcResult {
        guard isBlankActive else {
            return .unblanked
        }

        isBlankActive = false
        blankActiveSince = nil
        blankActiveUntil = nil
        DeviceActivityTimerScheduler.stop(modeId: currentModeId)
        deviceActivityTimerScheduled = false
        endActiveSession()
        return .unblanked
    }

    func applyScheduleWindow(at date: Date = Date()) {
        if let blankActiveUntil, isBlankActive, date >= blankActiveUntil {
            _ = deactivateBlank()
            return
        }

        guard schedule.enabled else {
            schedulePausedUntil = nil
            return
        }

        if let schedulePausedUntil {
            if date < schedulePausedUntil {
                if isBlankActive {
                    _ = deactivateBlank()
                }
                return
            }
            self.schedulePausedUntil = nil
        }

        if schedule.contains(date) {
            _ = activateBlank(forceStarted: true)
        } else if isBlankActive {
            _ = deactivateBlank()
        }
    }

    func forgetNfcTag() {
        endActiveSession()
        nfcTagUid = nil
        isBlankActive = false
        blankActiveSince = nil
        blankActiveUntil = nil
        DeviceActivityTimerScheduler.stop(modeId: currentModeId)
        deviceActivityTimerScheduled = false
        schedulePausedUntil = nil
        setupComplete = false
    }

    func finishSetup() {
        setupComplete = true
    }

    func selectMode(_ modeId: UUID) {
        guard let mode = focusModes.first(where: { $0.id == modeId }) else { return }
        currentModeId = mode.id
        selection = Self.selection(from: mode.selectionData) ?? FamilyActivitySelection()
    }

    func createMode(named name: String) {
        let mode = BlankFocusMode(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Nuevo modo" : name,
            selectionData: Self.encodedSelection(selection)
        )
        focusModes.append(mode)
        selectMode(mode.id)
    }

    func renameMode(_ modeId: UUID, name: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        focusModes = focusModes.map { mode in
            guard mode.id == modeId else { return mode }
            var updated = mode
            updated.name = cleanName
            updated.updatedAt = Date()
            return updated
        }
    }

    func deleteMode(_ modeId: UUID) {
        guard focusModes.count > 1 else { return }
        focusModes.removeAll { $0.id == modeId }
        if currentModeId == modeId, let firstMode = focusModes.first {
            selectMode(firstMode.id)
        }
    }

    private func saveSelection(_ selection: FamilyActivitySelection) {
        if let data = Self.encodedSelection(selection) {
            defaults.set(data, forKey: Keys.selection)
        }
    }

    private func startSession(tag: String?, forceStarted: Bool = false) {
        if activeSession != nil {
            endActiveSession()
        }

        let session = BlankSession(
            profileId: currentModeId,
            strategy: .nfc,
            startTag: tag,
            forceStarted: forceStarted
        )
        sessions.append(session)
    }

    private func endActiveSession() {
        guard let index = sessions.lastIndex(where: { $0.isActive }) else {
            return
        }

        sessions[index].end()
    }

    private func updateCurrentModeSelection(_ selection: FamilyActivitySelection) {
        guard !focusModes.isEmpty else { return }
        let encodedSelection = Self.encodedSelection(selection)
        focusModes = focusModes.map { mode in
            guard mode.id == currentModeId else { return mode }
            var updated = mode
            updated.selectionData = encodedSelection
            updated.updatedAt = Date()
            return updated
        }
    }

    private func saveSessions(_ sessions: [BlankSession]) {
        if let data = try? JSONEncoder().encode(sessions) {
            defaults.set(data, forKey: Keys.sessions)
        }
    }

    private func saveFocusModes(_ modes: [BlankFocusMode]) {
        if let data = try? JSONEncoder().encode(modes) {
            defaults.set(data, forKey: Keys.focusModes)
        }
    }

    private func saveSchedule(_ schedule: BlankFocusSchedule) {
        if let data = try? JSONEncoder().encode(schedule) {
            defaults.set(data, forKey: Keys.schedule)
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

    private static func loadFocusModes(from defaults: UserDefaults, fallbackSelection: FamilyActivitySelection) -> [BlankFocusMode] {
        if let data = defaults.data(forKey: Keys.focusModes),
           let decoded = try? JSONDecoder().decode([BlankFocusMode].self, from: data),
           !decoded.isEmpty {
            return decoded
        }

        return [
            BlankFocusMode(id: Self.defaultModeId, name: "Rutina diaria", selectionData: encodedSelection(fallbackSelection)),
            BlankFocusMode(name: "Estudio"),
            BlankFocusMode(name: "Dormir")
        ]
    }

    private static func loadSchedule(from defaults: UserDefaults) -> BlankFocusSchedule {
        guard let data = defaults.data(forKey: Keys.schedule),
              let decoded = try? JSONDecoder().decode(BlankFocusSchedule.self, from: data) else {
            return BlankFocusSchedule()
        }
        return decoded
    }

    private static func encodedSelection(_ selection: FamilyActivitySelection) -> Data? {
        try? JSONEncoder().encode(selection)
    }

    private static func selection(from data: Data?) -> FamilyActivitySelection? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    enum NfcResult {
        case tagRegistered
        case blanked
        case unblanked
        case schedulePaused
        case wrongTag
        case noAppsSelected
    }

    private enum Keys {
        static let isBlankActive = "isBlankActive"
        static let blankActiveSince = "blankActiveSince"
        static let blankActiveUntil = "blankActiveUntil"
        static let nfcTagUid = "nfcTagUid"
        static let setupComplete = "setupComplete"
        static let selection = "familyActivitySelection"
        static let sessions = "blankSessions"
        static let focusModes = "blankFocusModes"
        static let currentModeId = "blankCurrentModeId"
        static let schedule = "blankFocusSchedule"
        static let backgroundThemeId = "blankBackgroundThemeId"
        static let deviceActivityTimerScheduled = "blankDeviceActivityTimerScheduled"
        static let schedulePausedUntil = "blankSchedulePausedUntil"
    }
}

#if DEBUG
extension SessionStore {
    static func preview(
        isBlankActive: Bool = false,
        protectedSelectionCount: Int = 3,
        nfcLinked: Bool = true,
        backgroundThemeId: String = "grey",
        schedule: BlankFocusSchedule = BlankFocusSchedule(),
        schedulePausedUntil: Date? = nil,
        timedUntil: Date? = nil
    ) -> SessionStore {
        let suiteName = "BlankPreview-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)

        let store = SessionStore(defaults: defaults)
        store.previewSelectionCount = protectedSelectionCount
        store.nfcTagUid = nfcLinked ? "preview-nfc-tag" : nil
        store.backgroundThemeId = backgroundThemeId
        store.schedule = schedule
        store.schedulePausedUntil = schedulePausedUntil
        store.isBlankActive = isBlankActive
        store.blankActiveSince = isBlankActive ? Date().addingTimeInterval(-24 * 60) : nil
        store.blankActiveUntil = timedUntil
        store.deviceActivityTimerScheduled = timedUntil != nil
        store.setupComplete = true
        return store
    }
}
#endif
