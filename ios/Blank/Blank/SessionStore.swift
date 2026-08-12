import FamilyControls
import Foundation
import WidgetKit

@MainActor
final class SessionStore: ObservableObject {
    static let defaultModeId = UUID(uuidString: "A1E43B14-22E6-4B55-8E89-5E2A3C100001")!

    @Published var isBlankActive: Bool {
        didSet {
            defaults.set(isBlankActive, forKey: Keys.isBlankActive)
            reloadBlankWidget()
        }
    }

    @Published var blankActiveSince: Date? {
        didSet {
            defaults.set(blankActiveSince?.timeIntervalSince1970, forKey: Keys.blankActiveSince)
            reloadBlankWidget()
        }
    }

    @Published var blankActiveUntil: Date? {
        didSet {
            defaults.set(blankActiveUntil?.timeIntervalSince1970, forKey: Keys.blankActiveUntil)
            reloadBlankWidget()
        }
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
            reloadBlankWidget()
        }
    }

    @Published var sessions: [BlankSession] {
        didSet { saveSessions(sessions) }
    }

    @Published private(set) var usageEvents: [BlankUsageEvent] {
        didSet { saveUsageEvents(usageEvents) }
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

    @Published private(set) var emergencyUnlocksThisWeek: Int {
        didSet { defaults.set(emergencyUnlocksThisWeek, forKey: Keys.emergencyUnlocksThisWeek) }
    }

    @Published private(set) var deviceActivityTimerScheduled: Bool {
        didSet { defaults.set(deviceActivityTimerScheduled, forKey: Keys.deviceActivityTimerScheduled) }
    }

    @Published var shouldOpenBlockConfiguration = false
    @Published var shouldScanBlankFromWidget = false

    #if DEBUG
    private var previewSelectionCount: Int?
    #endif

    private let defaults: UserDefaults

    init(defaults: UserDefaults = BlankSharedState.defaults) {
        self.defaults = defaults
        Self.migrateLegacyDefaultsIfNeeded(to: defaults)
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
        usageEvents = Self.loadUsageEvents(from: defaults)
        focusModes = loadedFocusModes
        currentModeId = loadedModeId
        schedule = Self.loadSchedule(from: defaults)
        deviceActivityTimerScheduled = defaults.bool(forKey: Keys.deviceActivityTimerScheduled)
        let currentWeekKey = Self.currentWeekKey()
        if defaults.string(forKey: Keys.emergencyUnlockWeekKey) == currentWeekKey {
            emergencyUnlocksThisWeek = defaults.integer(forKey: Keys.emergencyUnlocksThisWeek)
        } else {
            emergencyUnlocksThisWeek = 0
            defaults.set(currentWeekKey, forKey: Keys.emergencyUnlockWeekKey)
            defaults.set(0, forKey: Keys.emergencyUnlocksThisWeek)
        }
        if let timestamp = defaults.object(forKey: Keys.schedulePausedUntil) as? TimeInterval, timestamp > 0 {
            schedulePausedUntil = Date(timeIntervalSince1970: timestamp)
        } else {
            schedulePausedUntil = nil
        }

        let currentMode = loadedFocusModes.first { $0.id == loadedModeId }
            ?? loadedFocusModes.first
            ?? BlankFocusMode(id: Self.defaultModeId, name: "Routine")

        if let currentSelection = Self.selection(from: currentMode.selectionData) {
            selection = currentSelection
        }
    }

    var currentMode: BlankFocusMode {
        focusModes.first { $0.id == currentModeId }
            ?? focusModes.first
            ?? BlankFocusMode(id: Self.defaultModeId, name: "Routine")
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

    private var activeSessionStartedBySchedule: Bool {
        activeSession?.forceStarted == true
    }

    var currentWeekReport: BlankWeeklyReport {
        let weekStart = BlankWeeklySessionAggregator.startOfWeek(for: Date())
        return BlankWeeklySessionAggregator.aggregate(sessions: sessions, weekStart: weekStart)
    }

    var emergencyUnlocksRemaining: Int {
        if defaults.string(forKey: Keys.emergencyUnlockWeekKey) != Self.currentWeekKey() {
            return Self.maxEmergencyUnlocksPerWeek
        }
        return max(0, Self.maxEmergencyUnlocksPerWeek - emergencyUnlocksThisWeek)
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
            return deactivateBlank(entryMode: .nfc, endedReason: .nfc)
        }

        return activateBlank(entryMode: .nfc)
    }

    func activateBlank(
        forceStarted: Bool = false,
        durationMinutes: Int? = nil,
        entryMode: BlankEntryMode = .app
    ) -> NfcResult {
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
        startSession(tag: nfcTagUid, forceStarted: forceStarted, entryMode: entryMode, plannedDurationMinutes: durationMinutes)
        return .blanked
    }

    func pauseScheduleWithNfc(minutes: Int = 5) -> NfcResult {
        schedulePausedUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        _ = deactivateBlank(entryMode: .nfc, endedReason: .nfc)
        return .schedulePaused
    }

    func deactivateBlank(
        entryMode: BlankEntryMode = .app,
        endedReason: BlankEndedReason = .unknown,
        broken: Bool = false
    ) -> NfcResult {
        guard isBlankActive else {
            return .unblanked
        }

        isBlankActive = false
        blankActiveSince = nil
        blankActiveUntil = nil
        DeviceActivityTimerScheduler.stop(modeId: currentModeId)
        deviceActivityTimerScheduled = false
        endActiveSession(entryMode: entryMode, endedReason: endedReason, broken: broken)
        return .unblanked
    }

    func deactivateForEmergency() -> Bool {
        resetEmergencyUnlocksIfNeeded()
        if isBlankActive {
            guard emergencyUnlocksThisWeek < Self.maxEmergencyUnlocksPerWeek else {
                return false
            }
            emergencyUnlocksThisWeek += 1
        }
        _ = deactivateBlank(entryMode: .app, endedReason: .emergency, broken: true)
        return true
    }

    func applyScheduleWindow(at date: Date = Date()) {
        resetEmergencyUnlocksIfNeeded(for: date)
        BlankSharedState.finishExpiredBlock(defaults: defaults, now: date)

        if let blankActiveUntil, isBlankActive, date >= blankActiveUntil {
            let reason: BlankEndedReason = activeSession?.plannedDurationMinutes == nil ? .expired : .timer
            _ = deactivateBlank(entryMode: activeSession?.entryMode ?? .app, endedReason: reason)
            return
        }

        guard schedule.enabled else {
            schedulePausedUntil = nil
            return
        }

        if let schedulePausedUntil {
            if date < schedulePausedUntil {
                if isBlankActive, activeSessionStartedBySchedule {
                    _ = deactivateBlank(entryMode: .schedule, endedReason: .schedule)
                }
                return
            }
            self.schedulePausedUntil = nil
        }

        if schedule.contains(date) {
            _ = activateBlank(
                forceStarted: true,
                durationMinutes: schedulePlannedDurationMinutes,
                entryMode: .schedule
            )
        } else if isBlankActive, activeSessionStartedBySchedule {
            _ = deactivateBlank(entryMode: .schedule, endedReason: .schedule)
        }
    }

    func forgetNfcTag() {
        endActiveSession(entryMode: .app, endedReason: .unknown, broken: true)
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

    func requestBlockConfiguration() {
        shouldOpenBlockConfiguration = true
    }

    func requestBlankScanFromWidget() {
        syncFromSharedDefaults()
        shouldScanBlankFromWidget = true
    }

    func syncFromSharedDefaults(now: Date = Date()) {
        let activeState = BlankSharedState.loadActiveState(now: now, defaults: defaults)
        if isBlankActive != activeState.isActive {
            isBlankActive = activeState.isActive
        }
        if blankActiveSince != activeState.startedAt {
            blankActiveSince = activeState.startedAt
        }
        if blankActiveUntil != activeState.endsAt {
            blankActiveUntil = activeState.endsAt
        }

        let sharedSessions = Self.loadSessions(from: defaults)
        if sessions != sharedSessions {
            sessions = sharedSessions
        }

        let sharedUsageEvents = Self.loadUsageEvents(from: defaults)
        if usageEvents != sharedUsageEvents {
            usageEvents = sharedUsageEvents
        }
    }

    func selectMode(_ modeId: UUID) {
        guard let mode = focusModes.first(where: { $0.id == modeId }) else { return }
        currentModeId = mode.id
        selection = Self.selection(from: mode.selectionData) ?? FamilyActivitySelection()
    }

    func createMode(named name: String) {
        let mode = BlankFocusMode(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New mode" : name,
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

    private func startSession(
        tag: String?,
        forceStarted: Bool = false,
        entryMode: BlankEntryMode,
        plannedDurationMinutes: Int? = nil
    ) {
        if activeSession != nil {
            endActiveSession(entryMode: entryMode, endedReason: .unknown)
        }

        let snapshot = currentSelectionSnapshot
        let session = BlankSession(
            profileId: currentModeId,
            strategy: .nfc,
            startTag: tag,
            forceStarted: forceStarted,
            entryMode: entryMode,
            selectionSnapshot: snapshot,
            modeName: currentMode.name,
            plannedDurationMinutes: plannedDurationMinutes
        )
        sessions.append(session)
        appendUsageEvent(
            kind: .blockStarted,
            sessionId: session.id,
            entryMode: entryMode,
            selectionSnapshot: snapshot,
            modeName: session.modeName,
            plannedDurationMinutes: plannedDurationMinutes
        )
    }

    private func endActiveSession(
        entryMode: BlankEntryMode,
        endedReason: BlankEndedReason,
        broken: Bool = false
    ) {
        guard let index = sessions.lastIndex(where: { $0.isActive }) else {
            return
        }

        let endedAt = Date()
        sessions[index].end(at: endedAt, endedReason: endedReason)
        let session = sessions[index]
        appendUsageEvent(
            kind: broken ? .blockBroken : .blockEnded,
            sessionId: session.id,
            entryMode: entryMode,
            endedReason: endedReason,
            duration: session.duration,
            selectionSnapshot: session.selectionSnapshot ?? currentSelectionSnapshot,
            modeName: session.modeName,
            plannedDurationMinutes: session.plannedDurationMinutes
        )
    }

    private var schedulePlannedDurationMinutes: Int {
        let minutes: Int
        if schedule.startMinute < schedule.endMinute {
            minutes = schedule.endMinute - schedule.startMinute
        } else {
            minutes = (24 * 60 - schedule.startMinute) + schedule.endMinute
        }
        return max(1, minutes)
    }

    private var currentSelectionSnapshot: BlankSelectionSnapshot {
        BlankSelectionSnapshot(
            applicationCount: selection.applicationTokens.count,
            categoryCount: selection.categoryTokens.count,
            webDomainCount: selection.webDomainTokens.count
        )
    }

    private func appendUsageEvent(
        kind: BlankUsageEventKind,
        sessionId: UUID?,
        entryMode: BlankEntryMode,
        endedReason: BlankEndedReason? = nil,
        duration: TimeInterval? = nil,
        selectionSnapshot: BlankSelectionSnapshot,
        modeName: String? = nil,
        plannedDurationMinutes: Int? = nil
    ) {
        usageEvents.append(BlankUsageEvent(
            kind: kind,
            sessionId: sessionId,
            entryMode: entryMode,
            endedReason: endedReason,
            duration: duration,
            selectionSnapshot: selectionSnapshot,
            modeName: modeName,
            plannedDurationMinutes: plannedDurationMinutes
        ))
        if usageEvents.count > Self.maxUsageEvents {
            usageEvents.removeFirst(usageEvents.count - Self.maxUsageEvents)
        }
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

    private func saveUsageEvents(_ events: [BlankUsageEvent]) {
        if let data = try? JSONEncoder().encode(events) {
            defaults.set(data, forKey: Keys.usageEvents)
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

    private static func loadUsageEvents(from defaults: UserDefaults) -> [BlankUsageEvent] {
        guard let data = defaults.data(forKey: Keys.usageEvents),
              let decoded = try? JSONDecoder().decode([BlankUsageEvent].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func loadFocusModes(from defaults: UserDefaults, fallbackSelection: FamilyActivitySelection) -> [BlankFocusMode] {
        if let data = defaults.data(forKey: Keys.focusModes),
           let decoded = try? JSONDecoder().decode([BlankFocusMode].self, from: data),
           !decoded.isEmpty {
            return decoded.map { mode in
                var updated = mode
                switch mode.name {
                case "Rutina diaria":
                    updated.name = "Routine"
                case "Estudio":
                    updated.name = "Focus"
                case "Dormir":
                    updated.name = "Sleep"
                default:
                    break
                }
                return updated
            }
        }

        return [
            BlankFocusMode(id: Self.defaultModeId, name: "Routine", selectionData: encodedSelection(fallbackSelection)),
            BlankFocusMode(name: "Focus"),
            BlankFocusMode(name: "Sleep")
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

    private func resetEmergencyUnlocksIfNeeded(for date: Date = Date()) {
        let currentWeekKey = Self.currentWeekKey(for: date)
        guard defaults.string(forKey: Keys.emergencyUnlockWeekKey) != currentWeekKey else {
            return
        }
        emergencyUnlocksThisWeek = 0
        defaults.set(currentWeekKey, forKey: Keys.emergencyUnlockWeekKey)
        defaults.set(0, forKey: Keys.emergencyUnlocksThisWeek)
    }

    private static func currentWeekKey(for date: Date = Date()) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(components.yearForWeekOfYear ?? 0)-\(components.weekOfYear ?? 0)"
    }

    private static func migrateLegacyDefaultsIfNeeded(to defaults: UserDefaults) {
        guard defaults !== UserDefaults.standard,
              defaults.object(forKey: Keys.selection) == nil,
              defaults.object(forKey: Keys.setupComplete) == nil,
              (
                UserDefaults.standard.object(forKey: Keys.selection) != nil ||
                UserDefaults.standard.object(forKey: Keys.setupComplete) != nil
              ) else {
            return
        }

        [
            Keys.isBlankActive,
            Keys.blankActiveSince,
            Keys.blankActiveUntil,
            Keys.nfcTagUid,
            Keys.setupComplete,
            Keys.selection,
            Keys.sessions,
            Keys.usageEvents,
            Keys.focusModes,
            Keys.currentModeId,
            Keys.schedule,
            Keys.deviceActivityTimerScheduled,
            Keys.schedulePausedUntil,
            Keys.emergencyUnlockWeekKey,
            Keys.emergencyUnlocksThisWeek
        ].forEach { key in
            if let value = UserDefaults.standard.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
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
        static let isBlankActive = BlankSharedState.Keys.isBlankActive
        static let blankActiveSince = BlankSharedState.Keys.blankActiveSince
        static let blankActiveUntil = BlankSharedState.Keys.blankActiveUntil
        static let nfcTagUid = "nfcTagUid"
        static let setupComplete = "setupComplete"
        static let selection = BlankSharedState.Keys.selection
        static let sessions = BlankSharedState.Keys.sessions
        static let usageEvents = BlankSharedState.Keys.usageEvents
        static let focusModes = "blankFocusModes"
        static let currentModeId = BlankSharedState.Keys.currentModeId
        static let schedule = "blankFocusSchedule"
        static let deviceActivityTimerScheduled = "blankDeviceActivityTimerScheduled"
        static let schedulePausedUntil = "blankSchedulePausedUntil"
        static let emergencyUnlockWeekKey = "blankEmergencyUnlockWeekKey"
        static let emergencyUnlocksThisWeek = "blankEmergencyUnlocksThisWeek"
    }

    private static let maxEmergencyUnlocksPerWeek = 3
    private static let maxUsageEvents = 500

    private func reloadBlankWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: "BlankQuickBlockWidget")
    }
}

#if DEBUG
extension SessionStore {
    func loadAIDemoData(now: Date = Date()) {
        let calendar = Calendar.current
        let weekStart = BlankWeeklySessionAggregator.startOfWeek(for: now, calendar: calendar)
        let modeName = "Focus"
        let snapshot = BlankSelectionSnapshot(applicationCount: 3, categoryCount: 1, webDomainCount: 0)
        let weakHour = calendar.component(.hour, from: now.addingTimeInterval(20 * 60))
        let currentWeekday = calendar.component(.weekday, from: now)

        if let studyMode = focusModes.first(where: { $0.name == modeName }) {
            currentModeId = studyMode.id
        } else {
            let studyMode = BlankFocusMode(name: modeName, selectionData: Self.encodedSelection(selection))
            focusModes.append(studyMode)
            currentModeId = studyMode.id
        }

        previewSelectionCount = snapshot.totalCount
        isBlankActive = false
        blankActiveSince = nil
        blankActiveUntil = nil
        deviceActivityTimerScheduled = false
        schedulePausedUntil = nil
        setupComplete = true

        let demoSessions: [BlankSession] = [
            demoSession(hoursAgo: 130, durationMinutes: 70, modeName: modeName, snapshot: snapshot, now: now),
            demoSession(hoursAgo: 104, durationMinutes: 35, modeName: modeName, snapshot: snapshot, now: now),
            demoSession(hoursAgo: 80, durationMinutes: 50, modeName: modeName, snapshot: snapshot, now: now),
            demoSession(hoursAgo: 55, durationMinutes: 40, modeName: modeName, snapshot: snapshot, now: now),
            demoSession(hoursAgo: 31, durationMinutes: 25, modeName: modeName, snapshot: snapshot, now: now),
            demoSession(hoursAgo: 26, durationMinutes: 18, endedReason: .emergency, localHour: weakHour, weekday: currentWeekday, modeName: modeName, snapshot: snapshot, now: now),
            demoSession(hoursAgo: 5, durationMinutes: 55, modeName: modeName, snapshot: snapshot, now: now),
            demoSession(hoursAgo: 2, durationMinutes: 35, modeName: modeName, snapshot: snapshot, now: now),
            demoSession(hoursAgo: 1, durationMinutes: 12, endedReason: .emergency, localHour: weakHour, weekday: currentWeekday, modeName: modeName, snapshot: snapshot, now: now)
        ].filter { $0.startedAt >= weekStart && $0.startedAt <= now }

        let sessionEvents = demoSessions.flatMap { session -> [BlankUsageEvent] in
            let endDate = session.endedAt ?? session.startedAt
            return [
                BlankUsageEvent(
                    kind: .blockStarted,
                    sessionId: session.id,
                    occurredAt: session.startedAt,
                    entryMode: session.entryMode ?? .app,
                    selectionSnapshot: snapshot,
                    modeName: session.modeName,
                    localHour: session.localStartHour,
                    weekday: session.startWeekday,
                    plannedDurationMinutes: session.plannedDurationMinutes
                ),
                BlankUsageEvent(
                    kind: session.endedReason == .emergency ? .blockBroken : .blockEnded,
                    sessionId: session.id,
                    occurredAt: endDate,
                    entryMode: session.entryMode ?? .app,
                    endedReason: session.endedReason,
                    duration: session.duration,
                    selectionSnapshot: snapshot,
                    modeName: session.modeName,
                    localHour: session.localStartHour,
                    weekday: session.startWeekday,
                    plannedDurationMinutes: session.plannedDurationMinutes
                )
            ]
        }

        sessions = demoSessions
        usageEvents = sessionEvents
        emergencyUnlocksThisWeek = min(demoSessions.filter { $0.endedReason == .emergency }.count, Self.maxEmergencyUnlocksPerWeek)
    }

    static func preview(
        isBlankActive: Bool = false,
        protectedSelectionCount: Int = 3,
        nfcLinked: Bool = true,
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
        store.schedule = schedule
        store.schedulePausedUntil = schedulePausedUntil
        store.isBlankActive = isBlankActive
        store.blankActiveSince = isBlankActive ? Date().addingTimeInterval(-24 * 60) : nil
        store.blankActiveUntil = timedUntil
        store.deviceActivityTimerScheduled = timedUntil != nil
        store.setupComplete = true
        return store
    }

    private func demoSession(
        hoursAgo: Int,
        durationMinutes: Int,
        endedReason: BlankEndedReason = .timer,
        localHour: Int? = nil,
        weekday: Int? = nil,
        modeName: String,
        snapshot: BlankSelectionSnapshot,
        now: Date
    ) -> BlankSession {
        let calendar = Calendar.current
        let startedAt = now.addingTimeInterval(TimeInterval(-hoursAgo * 60 * 60))
        let endedAt = startedAt.addingTimeInterval(TimeInterval(durationMinutes * 60))
        return BlankSession(
            profileId: currentModeId,
            strategy: .nfc,
            startTag: nfcTagUid,
            startedAt: startedAt,
            endedAt: min(endedAt, now.addingTimeInterval(-60)),
            forceStarted: false,
            entryMode: .app,
            endedReason: endedReason,
            selectionSnapshot: snapshot,
            modeName: modeName,
            localStartHour: localHour ?? calendar.component(.hour, from: startedAt),
            startWeekday: weekday ?? calendar.component(.weekday, from: startedAt),
            plannedDurationMinutes: durationMinutes,
            calendar: calendar
        )
    }
}
#endif
