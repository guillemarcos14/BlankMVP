import FamilyControls
import Foundation
import WidgetKit

enum AssistantPendingAction: Equatable {
    case startProtection(minutes: Int?, hardMode: Bool, appNames: [String])
    case applySchedule(name: String, startMinute: Int, endMinute: Int, weekdays: [Int], durationDays: Int, appNames: [String])
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

struct AssistantProtectionExecution: Equatable {
    let status: String
    let detail: String
    let requestedAt: Date
    let startedAt: Date
    let requestedDurationMinutes: Int
    let effectiveUntil: Date?
    let startDelaySeconds: Int
    let mergedWithExisting: Bool
    let result: String
}

@MainActor
final class SessionStore: ObservableObject {
    static let canonicalProtectionId = BlankSharedState.canonicalProtectionId
    static let canonicalProtectionName = BlankSharedState.canonicalProtectionName

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
        let legacyFocusModes = Self.loadLegacyFocusModes(from: defaults)
        let storedModeId = defaults.string(forKey: Keys.legacyCurrentModeId).flatMap(UUID.init(uuidString:))
        let legacyCurrentMode = storedModeId.flatMap { id in legacyFocusModes.first(where: { $0.id == id }) }
            ?? legacyFocusModes.first
        let canonicalSelection = Self.hasSelection(loadedSelection)
            ? loadedSelection
            : (Self.selection(from: legacyCurrentMode?.selectionData) ?? loadedSelection)
        selection = canonicalSelection
        sessions = Self.loadSessions(from: defaults)
        usageEvents = Self.loadUsageEvents(from: defaults)
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

        defaults.removeObject(forKey: Keys.legacyFocusModes)
        defaults.removeObject(forKey: Keys.legacyCurrentModeId)
        syncRecurringSchedule()
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
            modeName: Self.canonicalProtectionName,
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
        let now = Date()
        let pendingDuration = usePendingWidgetTimer ? pendingWidgetTimerMinutes : nil
        let selectedDuration = (durationMinutes ?? pendingDuration).map { min(max($0, 5), 240) }
        if isBlankActive {
            hardBlankActive = hardBlankActive || hardMode
            if let selectedDuration, blankActiveUntil != nil {
                let proposedEnd = now.addingTimeInterval(TimeInterval(selectedDuration * 60))
                let mergedEnd = max(blankActiveUntil ?? proposedEnd, proposedEnd)
                blankActiveUntil = mergedEnd
                let remainingMinutes = max(1, Int(ceil(mergedEnd.timeIntervalSince(now) / 60)))
                deviceActivityTimerScheduled = DeviceActivityTimerScheduler.start(
                    protectionId: Self.canonicalProtectionId,
                    durationMinutes: remainingMinutes
                )
            }
            pendingWidgetTimerMinutes = nil
            return .blanked
        }
        if let lastManualUnblankedAt,
           Date().timeIntervalSince(lastManualUnblankedAt) < TimeInterval(manualUnblankCooldownSeconds) {
            return .unblanked
        }

        isBlankActive = true
        hardBlankActive = hardMode
        blankActiveSince = now
        if let selectedDuration, selectedDuration > 0 {
            blankActiveUntil = now.addingTimeInterval(TimeInterval(selectedDuration * 60))
            deviceActivityTimerScheduled = DeviceActivityTimerScheduler.start(
                protectionId: Self.canonicalProtectionId,
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

    func applyAssistantProtection(
        actionId: String,
        requestedAt: Date,
        durationMinutes: Int,
        hardMode: Bool,
        now: Date = Date()
    ) -> AssistantProtectionExecution {
        let duration = min(max(durationMinutes, 5), 240)
        let requestedEnd = requestedAt.addingTimeInterval(TimeInterval(duration * 60))
        let delay = max(0, Int(now.timeIntervalSince(requestedAt).rounded()))
        guard now < requestedEnd else {
            return AssistantProtectionExecution(
                status: "failed",
                detail: "immediate_action_expired_before_execution",
                requestedAt: requestedAt,
                startedAt: now,
                requestedDurationMinutes: duration,
                effectiveUntil: blankActiveUntil,
                startDelaySeconds: delay,
                mergedWithExisting: isBlankActive,
                result: "expired_without_attribution"
            )
        }

        let mergedWithExisting = isBlankActive
        let existingEnd = blankActiveUntil
        let remainingMinutes = max(1, Int(ceil(requestedEnd.timeIntervalSince(now) / 60)))
        _ = activateBlank(
            durationMinutes: remainingMinutes,
            hardMode: hardMode,
            entryMode: .app,
            usePendingWidgetTimer: false
        )
        if !mergedWithExisting || existingEnd != nil {
            let mergedEnd = max(existingEnd ?? requestedEnd, requestedEnd)
            blankActiveUntil = mergedEnd
            deviceActivityTimerScheduled = DeviceActivityTimerScheduler.start(
                protectionId: Self.canonicalProtectionId,
                durationMinutes: max(1, Int(ceil(mergedEnd.timeIntervalSince(now) / 60)))
            )
        }
        let effectiveEnd = blankActiveUntil ?? requestedEnd
        let exactActionApplied = isBlankActive
            && effectiveEnd >= requestedEnd.addingTimeInterval(-1)
        let delayed = delay > 60
        let status = exactActionApplied ? (delayed ? "delayed" : "verified") : "failed"
        let result = exactActionApplied
            ? (mergedWithExisting ? "merged_without_shortening_existing_protection" : "started_requested_protection")
            : "requested_interval_not_applied"
        defaults.set(actionId, forKey: "blankLastAssistantExecutionActionId")
        defaults.set(requestedAt.timeIntervalSince1970, forKey: "blankLastAssistantExecutionRequestedAt")
        defaults.set(now.timeIntervalSince1970, forKey: "blankLastAssistantExecutionStartedAt")
        defaults.set(duration, forKey: "blankLastAssistantExecutionDurationMinutes")
        defaults.set(effectiveEnd?.timeIntervalSince1970, forKey: "blankLastAssistantExecutionEffectiveUntil")
        defaults.set("assistant_remote", forKey: "blankLastAssistantExecutionOrigin")
        defaults.set(result, forKey: "blankLastAssistantExecutionResult")
        return AssistantProtectionExecution(
            status: status,
            detail: delayed ? "late_delivery_applied_remaining_requested_window" : "exact_remote_action_applied",
            requestedAt: requestedAt,
            startedAt: now,
            requestedDurationMinutes: duration,
            effectiveUntil: effectiveEnd,
            startDelaySeconds: delay,
            mergedWithExisting: mergedWithExisting,
            result: result
        )
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
        DeviceActivityTimerScheduler.stop(protectionId: Self.canonicalProtectionId)
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
        DeviceActivityTimerScheduler.stop(protectionId: Self.canonicalProtectionId)
        deviceActivityTimerScheduled = false
        schedulePausedUntil = nil
        setupComplete = false
    }

    func finishSetup() {
        setupComplete = true
    }

    func requestBlockConfiguration(
        appNames: [String] = [],
        shouldActivate: Bool = false,
        durationMinutes: Int? = nil,
        hardMode: Bool = false,
        schedule: PendingPlanSchedule? = nil,
        dailyLimitMinutes: Int? = nil
    ) {
        pendingPlanAppNames = appNames
        pendingPlanShouldActivate = shouldActivate
        pendingPlanDurationMinutes = durationMinutes.map { min(max($0, 5), 240) }
        pendingPlanHardMode = hardMode
        pendingPlanSchedule = schedule
        pendingPlanDailyLimitMinutes = dailyLimitMinutes.map { min(max($0, 5), 240) }
        shouldOpenBlockConfiguration = true
    }

    func clearPendingPlanAppNames() {
        pendingPlanAppNames = []
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

    @discardableResult
    func restoreSavedSelectionForAssistant(appNames: [String] = []) -> Bool {
        _ = appNames
        return hasSelectedApps
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

    func saveManualSchedule(
        startMinute: Int,
        endMinute: Int,
        weekdays: [Int],
        repeatsWeekly: Bool
    ) {
        let scheduleName = "Protection \(Self.clockLabel(startMinute))"
        var windows = schedule.windows.filter {
            $0.name.caseInsensitiveCompare(scheduleName) != .orderedSame
        }
        if repeatsWeekly {
            windows.append(
                BlankHabitWindow(
                    name: scheduleName,
                    enabled: true,
                    startMinute: startMinute,
                    endMinute: endMinute,
                    weekdays: weekdays
                )
            )
        }
        let first = windows.first ?? BlankHabitWindow(
            name: scheduleName,
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

    func applyOnboardingPlan(startHour: Int) {

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
            profileId: Self.canonicalProtectionId,
            strategy: .manual,
            startTag: tag,
            forceStarted: forceStarted,
            entryMode: entryMode,
            selectionSnapshot: snapshot,
            modeName: Self.canonicalProtectionName,
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

    private static func loadLegacyFocusModes(from defaults: UserDefaults) -> [LegacyFocusMode] {
        guard let data = defaults.data(forKey: Keys.legacyFocusModes),
              let decoded = try? JSONDecoder().decode([LegacyFocusMode].self, from: data) else {
            return []
        }
        return decoded
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

    private static func hasSelection(_ selection: FamilyActivitySelection) -> Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty
    }

    private static func clockLabel(_ minute: Int) -> String {
        let normalized = ((minute % (24 * 60)) + (24 * 60)) % (24 * 60)
        return String(format: "%02d:%02d", normalized / 60, normalized % 60)
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
            Keys.legacyFocusModes,
            Keys.legacyCurrentModeId,
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
        static let legacyFocusModes = "blankFocusModes"
        static let legacyCurrentModeId = "blankCurrentModeId"
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
        let modeName = Self.canonicalProtectionName
        let snapshot = BlankSelectionSnapshot(applicationCount: 3, categoryCount: 1, webDomainCount: 0)
        let weakHour = calendar.component(.hour, from: now.addingTimeInterval(20 * 60))
        let currentWeekday = calendar.component(.weekday, from: now)

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
            profileId: Self.canonicalProtectionId,
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
