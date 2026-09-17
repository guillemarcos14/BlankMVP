import FamilyControls
import Foundation
import WidgetKit

enum AssistantPendingAction: Equatable {
    case startProtection(minutes: Int?, hardMode: Bool, appNames: [String])
    case activateMode(name: String, minutes: Int?, hardMode: Bool, appNames: [String])
    case duplicateAndActivateMode(sourceName: String, minutes: Int?, hardMode: Bool, appNames: [String])
    case switchMode(name: String)
    case applySchedule(name: String, startMinute: Int, endMinute: Int, weekdays: [Int], durationDays: Int, appNames: [String])
    case duplicateModeAndApplySchedule(sourceName: String, name: String, startMinute: Int, endMinute: Int, weekdays: [Int], durationDays: Int, appNames: [String])
    case setDailyLimit(minutes: Int?, appNames: [String])
    case allowOnly
    case adultFilter
    case pauseRules(hours: Int)
    case disablePause
    case applyAIPlan
    case openAppPicker(appNames: [String])
    case configureAndOpenAppPicker(appNames: [String], durationMinutes: Int?, hardMode: Bool, schedule: PendingPlanSchedule?)
    case configureAndOpenDailyLimitPicker(appNames: [String], minutes: Int)
    case requestScreenTimePermission
}

struct PendingPlanSchedule: Equatable {
    let name: String
    let startMinute: Int
    let endMinute: Int
    let weekdays: [Int]
    let durationDays: Int
}

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

    @Published var hardBlankActive: Bool {
        didSet { defaults.set(hardBlankActive, forKey: Keys.hardBlankActive) }
    }

    @Published var allowOnlyModeEnabled: Bool {
        didSet { defaults.set(allowOnlyModeEnabled, forKey: Keys.allowOnlyModeEnabled) }
    }

    @Published var adultContentBlockingEnabled: Bool {
        didSet { defaults.set(adultContentBlockingEnabled, forKey: Keys.adultContentBlockingEnabled) }
    }

    @Published var dailyLimitEnabled: Bool {
        didSet {
            defaults.set(dailyLimitEnabled, forKey: Keys.dailyLimitEnabled)
            refreshDailyLimitMonitoring()
        }
    }

    @Published var dailyLimitMinutes: Int {
        didSet {
            let clamped = min(max(dailyLimitMinutes, 5), 240)
            if dailyLimitMinutes != clamped {
                dailyLimitMinutes = clamped
                return
            }
            defaults.set(dailyLimitMinutes, forKey: Keys.dailyLimitMinutes)
            refreshDailyLimitMonitoring()
        }
    }

    @Published var vacationModeUntil: Date? {
        didSet {
            defaults.set(vacationModeUntil?.timeIntervalSince1970, forKey: Keys.vacationModeUntil)
            refreshDailyLimitMonitoring()
        }
    }

    @Published var pinProtectionEnabled: Bool {
        didSet { defaults.set(pinProtectionEnabled, forKey: Keys.pinProtectionEnabled) }
    }

    @Published var focusSoundscapeEnabled: Bool {
        didSet { defaults.set(focusSoundscapeEnabled, forKey: Keys.focusSoundscapeEnabled) }
    }

    @Published var manualUnblankCooldownSeconds: Int {
        didSet {
            let clamped = min(max(manualUnblankCooldownSeconds, 0), 300)
            if manualUnblankCooldownSeconds != clamped {
                manualUnblankCooldownSeconds = clamped
                return
            }
            defaults.set(manualUnblankCooldownSeconds, forKey: Keys.manualUnblankCooldownSeconds)
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
            syncRecurringSchedule()
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
        didSet {
            saveSchedule(schedule)
            syncRecurringSchedule()
        }
    }

    @Published var schedulePausedUntil: Date? {
        didSet { defaults.set(schedulePausedUntil?.timeIntervalSince1970, forKey: Keys.schedulePausedUntil) }
    }

    @Published private(set) var adaptiveScheduleExpiresAt: Date? = nil {
        didSet { defaults.set(adaptiveScheduleExpiresAt?.timeIntervalSince1970, forKey: Keys.adaptiveScheduleExpiresAt) }
    }

    @Published private(set) var emergencyUnlocksThisWeek: Int {
        didSet { defaults.set(emergencyUnlocksThisWeek, forKey: Keys.emergencyUnlocksThisWeek) }
    }

    @Published private(set) var deviceActivityTimerScheduled: Bool {
        didSet { defaults.set(deviceActivityTimerScheduled, forKey: Keys.deviceActivityTimerScheduled) }
    }

    @Published var pendingWidgetTimerMinutes: Int? {
        didSet {
            BlankSharedState.setPendingWidgetTimerMinutes(pendingWidgetTimerMinutes, defaults: defaults)
            reloadBlankWidget()
        }
    }

    @Published var shouldOpenBlockConfiguration = false
    @Published var shouldScanBlankFromWidget = false
    @Published var shouldShowWidgetTimerSelector = false
    @Published var pendingPlanAppNames: [String] = []
    @Published var pendingPlanStartsFreshSelection = false
    @Published var pendingPlanModeName: String?
    @Published var pendingPlanShouldActivate = false
    @Published var pendingPlanDurationMinutes: Int?
    @Published var pendingPlanHardMode = false
    @Published var pendingPlanSchedule: PendingPlanSchedule? = nil
    @Published var pendingPlanDailyLimitMinutes: Int? = nil
    @Published var pendingAssistantAction: AssistantPendingAction?

    #if DEBUG
    private var previewSelectionCount: Int?
    #endif

    private let defaults: UserDefaults
    private var lastManualUnblankedAt: Date?

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
        hardBlankActive = defaults.bool(forKey: Keys.hardBlankActive)
        allowOnlyModeEnabled = defaults.bool(forKey: Keys.allowOnlyModeEnabled)
        adultContentBlockingEnabled = defaults.bool(forKey: Keys.adultContentBlockingEnabled)
        dailyLimitEnabled = defaults.bool(forKey: Keys.dailyLimitEnabled)
        let storedDailyLimit = defaults.integer(forKey: Keys.dailyLimitMinutes)
        dailyLimitMinutes = storedDailyLimit > 0 ? min(max(storedDailyLimit, 5), 240) : 30
        if let timestamp = defaults.object(forKey: Keys.vacationModeUntil) as? TimeInterval, timestamp > 0 {
            vacationModeUntil = Date(timeIntervalSince1970: timestamp)
        } else {
            vacationModeUntil = nil
        }
        pinProtectionEnabled = defaults.bool(forKey: Keys.pinProtectionEnabled)
        focusSoundscapeEnabled = defaults.bool(forKey: Keys.focusSoundscapeEnabled)
        let storedManualCooldown = defaults.object(forKey: Keys.manualUnblankCooldownSeconds) as? Int
        manualUnblankCooldownSeconds = min(max(storedManualCooldown ?? 60, 0), 300)
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
        pendingWidgetTimerMinutes = BlankSharedState.pendingWidgetTimerMinutes(defaults: defaults)
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
        if let timestamp = defaults.object(forKey: Keys.adaptiveScheduleExpiresAt) as? TimeInterval, timestamp > 0 {
            adaptiveScheduleExpiresAt = Date(timeIntervalSince1970: timestamp)
        } else {
            adaptiveScheduleExpiresAt = nil
        }

        let currentMode = loadedFocusModes.first { $0.id == loadedModeId }
            ?? loadedFocusModes.first
            ?? BlankFocusMode(id: Self.defaultModeId, name: "Routine")

        if let currentSelection = Self.selection(from: currentMode.selectionData) {
            selection = currentSelection
        }

        syncRecurringSchedule()
    }

    var currentMode: BlankFocusMode {
        focusModes.first { $0.id == currentModeId }
            ?? focusModes.first
            ?? BlankFocusMode(id: Self.defaultModeId, name: "Routine")
    }

    var hasSelectedApps: Bool {
        selectionCount > 0
    }

    var isVacationModeActive: Bool {
        guard let vacationModeUntil else { return false }
        return vacationModeUntil > Date()
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

    var digitalWellnessV3: DigitalWellnessV3System {
        DigitalWellnessAI.v3System(
            events: usageEvents,
            sessions: sessions,
            selectionCount: selectionCount,
            modeName: currentMode.name,
            emergencyUnlocksRemaining: emergencyUnlocksRemaining
        )
    }

    func digitalWellnessFeaturePayload(
        healthSummaries: [HealthDaySummary],
        now: Date = Date()
    ) -> DigitalWellnessFeaturePayload {
        DigitalWellnessFeatureBuilder.makePayload(
            defaults: defaults,
            healthSummaries: healthSummaries,
            sessions: sessions,
            events: usageEvents,
            selectionCount: selectionCount,
            selectionSnapshot: currentSelectionSnapshot,
            now: now
        )
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
            if hardBlankActive {
                return .hardBlankLocked
            }
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
        hardMode: Bool = false,
        entryMode: BlankEntryMode = .app,
        usePendingWidgetTimer: Bool = true
    ) -> NfcResult {
        guard hasSelectedApps else {
            return .noAppsSelected
        }
        guard !isBlankActive else {
            return .blanked
        }
        if let lastManualUnblankedAt,
           Date().timeIntervalSince(lastManualUnblankedAt) < TimeInterval(manualUnblankCooldownSeconds) {
            return .unblanked
        }

        isBlankActive = true
        hardBlankActive = hardMode
        blankActiveSince = Date()
        let pendingDuration = usePendingWidgetTimer ? pendingWidgetTimerMinutes : nil
        let selectedDuration = (durationMinutes ?? pendingDuration).map { min(max($0, 5), 240) }
        if let selectedDuration, selectedDuration > 0 {
            blankActiveUntil = Date().addingTimeInterval(TimeInterval(selectedDuration * 60))
            deviceActivityTimerScheduled = DeviceActivityTimerScheduler.start(
                modeId: currentModeId,
                durationMinutes: selectedDuration
            )
        } else {
            blankActiveUntil = nil
            deviceActivityTimerScheduled = false
        }
        pendingWidgetTimerMinutes = nil
        startSession(tag: nfcTagUid, forceStarted: forceStarted, entryMode: entryMode, plannedDurationMinutes: selectedDuration)
        return .blanked
    }

    func pauseScheduleWithNfc(minutes: Int = 5) -> NfcResult {
        let now = Date()
        schedulePausedUntil = scheduleEndDate(containing: now) ?? now.addingTimeInterval(TimeInterval(minutes * 60))
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

        let endedAt = Date()
        if hardBlankActive, endedReason != .emergency, endedReason != .timer, endedReason != .expired, endedReason != .schedule {
            return .hardBlankLocked
        }
        if endedReason == .manual || endedReason == .emergency || endedReason == .nfc {
            pauseScheduleForUserUnlock(at: endedAt)
        }

        isBlankActive = false
        hardBlankActive = false
        blankActiveSince = nil
        blankActiveUntil = nil
        pendingWidgetTimerMinutes = nil
        if endedReason == .manual {
            lastManualUnblankedAt = endedAt
        }
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

        if let vacationModeUntil {
            if date < vacationModeUntil {
                if isBlankActive, activeSessionStartedBySchedule {
                    _ = deactivateBlank(entryMode: .schedule, endedReason: .schedule)
                }
                return
            }
            self.vacationModeUntil = nil
        }

        if let blankActiveUntil, isBlankActive, date >= blankActiveUntil {
            let reason: BlankEndedReason = activeSession?.plannedDurationMinutes == nil ? .expired : .timer
            _ = deactivateBlank(entryMode: activeSession?.entryMode ?? .app, endedReason: reason)
            return
        }

        guard schedule.enabled, !schedule.activeWindows.isEmpty else {
            schedulePausedUntil = nil
            adaptiveScheduleExpiresAt = nil
            return
        }

        if let adaptiveScheduleExpiresAt, date >= adaptiveScheduleExpiresAt {
            schedule = BlankFocusSchedule()
            schedulePausedUntil = nil
            self.adaptiveScheduleExpiresAt = nil
            if isBlankActive, activeSessionStartedBySchedule {
                _ = deactivateBlank(entryMode: .schedule, endedReason: .schedule)
            }
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

        if let activeWindow = schedule.window(containing: date) {
            _ = activateBlank(
                forceStarted: true,
                durationMinutes: activeWindow.remainingMinutes(from: date),
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
        hardBlankActive = false
        blankActiveSince = nil
        blankActiveUntil = nil
        pendingWidgetTimerMinutes = nil
        DeviceActivityTimerScheduler.stop(modeId: currentModeId)
        deviceActivityTimerScheduled = false
        schedulePausedUntil = nil
        setupComplete = false
    }

    func finishSetup() {
        setupComplete = true
    }

    func requestBlockConfiguration(
        appNames: [String] = [],
        startsFreshSelection: Bool = false,
        modeName: String? = nil,
        shouldActivate: Bool = false,
        durationMinutes: Int? = nil,
        hardMode: Bool = false,
        schedule: PendingPlanSchedule? = nil,
        dailyLimitMinutes: Int? = nil
    ) {
        pendingPlanAppNames = appNames
        pendingPlanStartsFreshSelection = startsFreshSelection
        let cleanModeName = modeName?.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingPlanModeName = cleanModeName?.isEmpty == false ? cleanModeName : nil
        pendingPlanShouldActivate = shouldActivate
        pendingPlanDurationMinutes = durationMinutes.map { min(max($0, 5), 240) }
        pendingPlanHardMode = hardMode
        pendingPlanSchedule = schedule
        pendingPlanDailyLimitMinutes = dailyLimitMinutes.map { min(max($0, 5), 240) }
        shouldOpenBlockConfiguration = true
    }

    func clearPendingPlanAppNames() {
        pendingPlanAppNames = []
        pendingPlanStartsFreshSelection = false
        pendingPlanModeName = nil
        pendingPlanShouldActivate = false
        pendingPlanDurationMinutes = nil
        pendingPlanHardMode = false
        pendingPlanSchedule = nil
        pendingPlanDailyLimitMinutes = nil
    }

    func requestWidgetTimerSelector() {
        shouldShowWidgetTimerSelector = true
    }

    func requestAssistantActionConfirmation(_ action: AssistantPendingAction) {
        pendingAssistantAction = action
    }

    func clearAssistantActionConfirmation() {
        pendingAssistantAction = nil
    }

    func selectWidgetTimer(minutes: Int?) {
        pendingWidgetTimerMinutes = minutes
    }

    func requestBlankScanFromWidget() {
        syncFromSharedDefaults()
        shouldScanBlankFromWidget = true
    }

    func syncFromSharedDefaults(now: Date = Date()) {
        BlankSharedState.finishExpiredBlock(defaults: defaults, now: now)
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
        let sharedPendingTimer = BlankSharedState.pendingWidgetTimerMinutes(defaults: defaults)
        if pendingWidgetTimerMinutes != sharedPendingTimer {
            pendingWidgetTimerMinutes = sharedPendingTimer
        }
        if !activeState.isActive, hardBlankActive {
            hardBlankActive = false
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

    @discardableResult
    func selectMode(named name: String) -> Bool {
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let mode = focusModes.first(where: { $0.name.lowercased() == target }) else { return false }
        selectMode(mode.id)
        return true
    }

    @discardableResult
    func selectBestMode(matching rawName: String) -> Bool {
        let target = Self.normalizedModeName(rawName)
        guard !target.isEmpty else { return false }
        if let exact = focusModes.first(where: { Self.normalizedModeName($0.name) == target }) {
            selectMode(exact.id)
            return true
        }
        if let fuzzy = focusModes.first(where: { mode in
            let normalized = Self.normalizedModeName(mode.name)
            return normalized.contains(target) || target.contains(normalized)
        }) {
            selectMode(fuzzy.id)
            return true
        }
        let aliases: [(keys: [String], modes: [String])] = [
            (["social", "redes", "instagram", "tiktok", "tik tok", "reels", "shorts"], ["social", "social media", "redes sociales"]),
            (["deep focus", "focus", "foco", "work", "trabajo"], ["deep focus", "focus", "work"]),
            (["study", "estudio", "exam", "examen"], ["study", "study mode"]),
            (["sleep", "night", "bedtime", "dormir", "noche"], ["sleep", "night", "bedtime"])
        ]
        for alias in aliases where alias.keys.contains(where: { target.contains($0) }) {
            if let match = focusModes.first(where: { mode in
                let normalized = Self.normalizedModeName(mode.name)
                return alias.modes.contains(where: { normalized.contains($0) || $0.contains(normalized) })
            }) {
                selectMode(match.id)
                return true
            }
        }
        return false
    }

    @discardableResult
    func duplicateMode(named sourceName: String) -> BlankFocusMode? {
        let target = Self.normalizedModeName(sourceName)
        guard !target.isEmpty,
              let source = focusModes.first(where: { Self.normalizedModeName($0.name) == target }),
              let selectionData = source.selectionData,
              let copiedSelection = Self.selection(from: selectionData),
              (!copiedSelection.applicationTokens.isEmpty
                || !copiedSelection.categoryTokens.isEmpty
                || !copiedSelection.webDomainTokens.isEmpty) else { return nil }
        let baseName = "\(source.name) copy"
        var copyName = baseName
        var suffix = 2
        let existingNames = Set(focusModes.map { Self.normalizedModeName($0.name) })
        while existingNames.contains(Self.normalizedModeName(copyName)) {
            copyName = "\(baseName) \(suffix)"
            suffix += 1
        }
        let copy = BlankFocusMode(name: copyName, selectionData: selectionData, appNames: source.appNames)
        focusModes.append(copy)
        currentModeId = copy.id
        selection = copiedSelection
        return copy
    }

    @discardableResult
    func restoreSavedSelectionForAssistant(appNames: [String] = []) -> Bool {
        let targets = appNames
            .map(Self.normalizedAssistantAppName)
            .filter { !$0.isEmpty }
        if !targets.isEmpty {
            let targetSet = Set(targets)
            if let exact = focusModes.first(where: { mode in
                Set(Self.assistantAppNames(for: mode)) == targetSet
            }) {
                selectMode(exact.id)
                return hasSelectedApps
            }
            return false
        }
        if hasSelectedApps { return true }

        let candidates = focusModes.filter { mode in
            guard let data = mode.selectionData,
                  let savedSelection = Self.selection(from: data) else { return false }
            return savedSelection.applicationTokens.count > 0
                || savedSelection.categoryTokens.count > 0
                || savedSelection.webDomainTokens.count > 0
        }
        let preferred = candidates.first
        guard let preferred else { return false }
        selectMode(preferred.id)
        return hasSelectedApps
    }

    func assistantModeCatalog() -> [[String: Any]] {
        focusModes.map { mode in
            let selection = Self.selection(from: mode.selectionData)
            let appNames = Self.assistantAppNames(for: mode)
            return [
                "id": mode.id.uuidString,
                "name": mode.name,
                "app_names": appNames,
                "selection_count": selection.map {
                    $0.applicationTokens.count + $0.categoryTokens.count + $0.webDomainTokens.count
                } ?? 0,
                "has_selection": selection.map {
                    !$0.applicationTokens.isEmpty || !$0.categoryTokens.isEmpty || !$0.webDomainTokens.isEmpty
                } ?? false
            ]
        }
    }

    func assistantScheduleContext() -> [String: Any] {
        var context: [String: Any] = [
            "enabled": schedule.enabled,
            "start_minute": schedule.startMinute,
            "end_minute": schedule.endMinute,
            "windows": schedule.windows.map { window in
                [
                    "id": window.id.uuidString,
                    "name": window.name,
                    "enabled": window.enabled,
                    "start_minute": window.startMinute,
                    "end_minute": window.endMinute,
                    "weekdays": window.weekdays
                ] as [String: Any]
            }
        ]
        if let pausedUntil = schedulePausedUntil {
            context["paused_until"] = pausedUntil.timeIntervalSince1970
        }
        if let expiresAt = adaptiveScheduleExpiresAt {
            context["expires_at"] = expiresAt.timeIntervalSince1970
        }
        return context
    }

    func createMode(named name: String) {
        let mode = BlankFocusMode(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New mode" : name,
            selectionData: Self.encodedSelection(selection),
            appNames: Self.inferredAssistantApps(from: name)
        )
        focusModes.append(mode)
        selectMode(mode.id)
    }

    func createOrUpdateMode(named name: String, selection: FamilyActivitySelection, appNames: [String] = []) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let knownAppNames = appNames.isEmpty
            ? Self.inferredAssistantApps(from: cleanName)
            : Self.normalizedAssistantDisplayAppNames(appNames)
        let requestedAppsName = knownAppNames.joined(separator: " + ")
        let modeName = requestedAppsName.isEmpty
            ? (cleanName.isEmpty ? "New mode" : cleanName)
            : requestedAppsName
        if let existing = focusModes.first(where: { Self.normalizedModeName($0.name) == Self.normalizedModeName(modeName) }) {
            currentModeId = existing.id
            self.selection = selection
            updateCurrentModeSelection(selection)
            if !knownAppNames.isEmpty {
                focusModes = focusModes.map { mode in
                    guard mode.id == existing.id else { return mode }
                    var updated = mode
                    updated.appNames = knownAppNames
                    updated.updatedAt = Date()
                    return updated
                }
            }
            return
        }
        let mode = BlankFocusMode(name: modeName, selectionData: Self.encodedSelection(selection), appNames: knownAppNames)
        focusModes.append(mode)
        currentModeId = mode.id
        self.selection = selection
    }

    func saveManualMode(
        named name: String,
        selection: FamilyActivitySelection,
        startMinute: Int,
        endMinute: Int,
        weekdays: [Int],
        repeatsWeekly: Bool
    ) {
        createOrUpdateMode(named: name, selection: selection)

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedName = cleanName.isEmpty ? currentMode.name : cleanName
        var windows = schedule.windows.filter {
            $0.name.caseInsensitiveCompare(savedName) != .orderedSame
        }

        if repeatsWeekly {
            windows.append(
                BlankHabitWindow(
                    name: savedName,
                    enabled: true,
                    startMinute: startMinute,
                    endMinute: endMinute,
                    weekdays: weekdays
                )
            )
        }

        let first = windows.first ?? BlankHabitWindow(
            name: savedName,
            enabled: false,
            startMinute: startMinute,
            endMinute: endMinute,
            weekdays: weekdays
        )
        schedule = BlankFocusSchedule(
            enabled: windows.contains(where: \.enabled),
            startMinute: first.startMinute,
            endMinute: first.endMinute,
            windows: windows
        )
        adaptiveScheduleExpiresAt = nil
        schedulePausedUntil = nil
    }

    func deleteScheduleWindow(_ windowId: UUID) {
        let wasActiveSchedule = isBlankActive && activeSessionStartedBySchedule
        let remainingWindows = schedule.windows.filter { $0.id != windowId }
        let first = remainingWindows.first

        schedule = BlankFocusSchedule(
            enabled: remainingWindows.contains(where: \.enabled),
            startMinute: first?.startMinute ?? schedule.startMinute,
            endMinute: first?.endMinute ?? schedule.endMinute,
            windows: remainingWindows
        )

        if remainingWindows.isEmpty {
            schedulePausedUntil = nil
            adaptiveScheduleExpiresAt = nil
        }

        if wasActiveSchedule {
            applyScheduleWindow()
        }
    }

    func applyOnboardingPlan(modeName: String, startHour: Int) {
        let cleanName = modeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let planModeName = cleanName.isEmpty ? "My Plan" : cleanName

        if let existingMode = focusModes.first(where: { $0.name == planModeName }) {
            currentModeId = existingMode.id
        } else {
            let mode = BlankFocusMode(name: planModeName, selectionData: Self.encodedSelection(selection))
            focusModes.append(mode)
            currentModeId = mode.id
        }

        let startMinute = min(max(startHour, 0), 23) * 60
        schedule = BlankFocusSchedule(
            enabled: true,
            startMinute: startMinute,
            endMinute: (startMinute + 60) % (24 * 60),
            windows: [
                BlankHabitWindow(name: "AI Plan", enabled: true, startMinute: startMinute, endMinute: (startMinute + 60) % (24 * 60))
            ]
        )
        schedulePausedUntil = nil
    }

    func applyAdaptivePlan(
        startMinute: Int,
        endMinute: Int,
        durationDays: Int,
        activateCurrentWindow: Bool = true,
        name: String = "AI Plan",
        weekdays: [Int] = Array(1...7)
    ) {
        adaptiveScheduleExpiresAt = Calendar.current.date(
            byAdding: .day,
            value: max(1, min(14, durationDays)),
            to: Date()
        )
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "AI Plan" : name
        let normalizedWeekdays = Array(Set(weekdays.filter { (1...7).contains($0) })).sorted()
        let window = BlankHabitWindow(
            name: cleanName,
            enabled: true,
            startMinute: startMinute,
            endMinute: endMinute,
            weekdays: normalizedWeekdays.isEmpty ? Array(1...7) : normalizedWeekdays
        )
        var windows = schedule.windows
        if let existingIndex = windows.firstIndex(where: {
            $0.name.caseInsensitiveCompare(cleanName) == .orderedSame
                && $0.startMinute == window.startMinute
                && $0.endMinute == window.endMinute
        }) {
            windows[existingIndex] = BlankHabitWindow(
                id: windows[existingIndex].id,
                name: cleanName,
                enabled: true,
                startMinute: startMinute,
                endMinute: endMinute,
                weekdays: window.weekdays
            )
        } else {
            windows.append(window)
        }
        schedule = BlankFocusSchedule(
            enabled: true,
            startMinute: schedule.startMinute,
            endMinute: schedule.endMinute,
            windows: windows
        )
        schedulePausedUntil = nil
        syncRecurringSchedule()
        if activateCurrentWindow {
            applyScheduleWindow()
        }
    }

    func applyAIPlan(durationMinutes: Int? = nil) {
        let system = digitalWellnessV3
        let startMinute = (system.plan.recommendedStartHour * 60 + (24 * 60 - 10)) % (24 * 60)
        let duration = durationMinutes ?? system.plan.recommendedDurationMinutes
        let endMinute = (startMinute + max(15, min(120, duration))) % (24 * 60)
        applyAdaptivePlan(startMinute: startMinute, endMinute: endMinute, durationDays: 7)
    }

    func enableVacationMode(hours: Int) {
        vacationModeUntil = Date().addingTimeInterval(TimeInterval(max(1, min(168, hours)) * 60 * 60))
        if isBlankActive, activeSessionStartedBySchedule {
            _ = deactivateBlank(entryMode: .schedule, endedReason: .schedule)
        }
    }

    func disableVacationMode() {
        vacationModeUntil = nil
        applyScheduleWindow()
    }

    func refreshDailyLimitMonitoring() {
        guard dailyLimitEnabled, !isVacationModeActive, hasSelectedApps else {
            DeviceActivityTimerScheduler.stopDailyLimit()
            return
        }
        _ = DeviceActivityTimerScheduler.startDailyLimit(selection: selection, thresholdMinutes: dailyLimitMinutes)
    }

    func syncRecurringSchedule() {
        _ = DeviceActivityTimerScheduler.syncRecurringSchedule(schedule, until: adaptiveScheduleExpiresAt)
    }

    func recordRelapseReview(_ reason: RelapseReviewReason) {
        defaults.set(reason.rawValue, forKey: "blankLastRelapseReviewReason")
        defaults.set(Date().timeIntervalSince1970, forKey: "blankLastRelapseReviewAt")
        Task {
            await BlankFunnelAnalytics.track(
                "relapse_review_submitted",
                properties: [
                    "reason": reason.rawValue,
                    "adjustment": reason.planAdjustment
                ]
            )
        }
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
            strategy: .manual,
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

    private func pauseScheduleForUserUnlock(at date: Date) {
        guard let windowEnd = scheduleEndDate(containing: date) else { return }
        if schedulePausedUntil == nil || schedulePausedUntil! < windowEnd {
            schedulePausedUntil = windowEnd
        }
    }

    private func scheduleEndDate(containing date: Date, calendar: Calendar = .current) -> Date? {
        guard schedule.enabled, let window = schedule.window(containing: date, calendar: calendar) else { return nil }

        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let dayStart = calendar.startOfDay(for: date)
        let endDay: Date

        if window.startMinute >= window.endMinute, minute >= window.startMinute {
            endDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        } else {
            endDay = dayStart
        }

        return calendar.date(byAdding: .minute, value: window.endMinute, to: endDay)
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
        trackUsageEvent(
            kind: kind,
            entryMode: entryMode,
            endedReason: endedReason,
            duration: duration,
            selectionSnapshot: selectionSnapshot,
            modeName: modeName,
            plannedDurationMinutes: plannedDurationMinutes
        )
    }

    private func trackUsageEvent(
        kind: BlankUsageEventKind,
        entryMode: BlankEntryMode,
        endedReason: BlankEndedReason?,
        duration: TimeInterval?,
        selectionSnapshot: BlankSelectionSnapshot,
        modeName: String?,
        plannedDurationMinutes: Int?
    ) {
        let eventName: String
        switch kind {
        case .blockStarted:
            eventName = "block_started"
        case .blockEnded:
            eventName = "block_ended"
        case .blockBroken:
            eventName = "relapse_attempt"
        }

        var properties: [String: Any] = [
            "entry_mode": entryMode.rawValue,
            "selection_count": selectionSnapshot.totalCount,
            "application_count": selectionSnapshot.applicationCount,
            "category_count": selectionSnapshot.categoryCount,
            "web_domain_count": selectionSnapshot.webDomainCount
        ]
        if let endedReason {
            properties["ended_reason"] = endedReason.rawValue
        }
        if let duration {
            properties["duration_seconds"] = Int(duration.rounded())
        }
        if let modeName {
            properties["mode_name"] = modeName
        }
        if let plannedDurationMinutes {
            properties["planned_duration_minutes"] = plannedDurationMinutes
        }

        Task {
            await BlankFunnelAnalytics.track(eventName, properties: properties)
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
            let migrated = decoded.compactMap { mode -> BlankFocusMode? in
                switch mode.name {
                case "Rutina diaria":
                    return BlankFocusMode(id: mode.id, name: "Routine", selectionData: mode.selectionData, createdAt: mode.createdAt, updatedAt: mode.updatedAt)
                case "Estudio":
                    return nil
                case "Dormir":
                    return nil
                case "Focus", "Work":
                    return mode.selectionData == nil ? nil : mode
                default:
                    guard mode.appNames.isEmpty else { return mode }
                    var inferred = mode
                    inferred.appNames = Self.inferredAssistantApps(from: mode.name)
                    return inferred
                }
            }
            if !migrated.isEmpty {
                return migrated
            }
        }

        return [
            BlankFocusMode(id: Self.defaultModeId, name: "Routine", selectionData: encodedSelection(fallbackSelection))
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

    private static func normalizedModeName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: " mode", with: "")
            .replacingOccurrences(of: " profile", with: "")
            .split(separator: " ")
            .joined(separator: " ")
    }

    private static func normalizedAssistantAppName(_ value: String) -> String {
        let normalized = normalizedModeName(value)
        switch normalized {
        case "insta": return "instagram"
        case "tik tok": return "tiktok"
        case "yt": return "youtube"
        case "x": return "twitter"
        default: return normalized
        }
    }

    private static func inferredAssistantApps(from value: String) -> [String] {
        let normalized = " \(normalizedModeName(value)) "
        let aliases: [(String, String)] = [
            ("instagram", "Instagram"),
            ("insta", "Instagram"),
            ("tiktok", "TikTok"),
            ("tik tok", "TikTok"),
            ("youtube", "YouTube"),
            ("yt", "YouTube"),
            ("reddit", "Reddit"),
            ("twitter", "Twitter"),
            ("facebook", "Facebook"),
            ("snapchat", "Snapchat"),
            ("whatsapp", "WhatsApp")
        ]
        var seen = Set<String>()
        return aliases.compactMap { alias, app in
            guard normalized.contains(" \(alias) "), !seen.contains(app) else { return nil }
            seen.insert(app)
            return app
        }
    }

    private static func normalizedAssistantDisplayAppNames(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = normalizedAssistantAppName(trimmed)
            guard !trimmed.isEmpty, !normalized.isEmpty, !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return trimmed
        }
    }

    private static func assistantAppNames(for mode: BlankFocusMode) -> [String] {
        let names = mode.appNames.isEmpty ? inferredAssistantApps(from: mode.name) : mode.appNames
        return names.map(normalizedAssistantAppName).sorted()
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
            BlankSharedState.Keys.pendingWidgetTimerMinutes,
            Keys.hardBlankActive,
            Keys.allowOnlyModeEnabled,
            Keys.adultContentBlockingEnabled,
            Keys.dailyLimitEnabled,
            Keys.dailyLimitMinutes,
            Keys.vacationModeUntil,
            Keys.pinProtectionEnabled,
            Keys.focusSoundscapeEnabled,
            Keys.manualUnblankCooldownSeconds,
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
            Keys.adaptiveScheduleExpiresAt,
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
        case hardBlankLocked
    }

    private enum Keys {
        static let isBlankActive = BlankSharedState.Keys.isBlankActive
        static let blankActiveSince = BlankSharedState.Keys.blankActiveSince
        static let blankActiveUntil = BlankSharedState.Keys.blankActiveUntil
        static let hardBlankActive = "blankHardBlankActive"
        static let allowOnlyModeEnabled = "blankAllowOnlyModeEnabled"
        static let adultContentBlockingEnabled = "blankAdultContentBlockingEnabled"
        static let dailyLimitEnabled = "blankDailyLimitEnabled"
        static let dailyLimitMinutes = "blankDailyLimitMinutes"
        static let vacationModeUntil = "blankVacationModeUntil"
        static let pinProtectionEnabled = "blankPinProtectionEnabled"
        static let focusSoundscapeEnabled = "blankFocusSoundscapeEnabled"
        static let manualUnblankCooldownSeconds = "blankManualUnblankCooldownSeconds"
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
        static let adaptiveScheduleExpiresAt = "blankAdaptiveScheduleExpiresAt"
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
        store.hardBlankActive = false
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
            strategy: .manual,
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
