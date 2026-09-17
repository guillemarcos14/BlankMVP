import SwiftUI
import UIKit
import UserNotifications

@main
struct BlankApp: App {
    @UIApplicationDelegateAdaptor(BlankAppDelegate.self) private var appDelegate
    @StateObject private var sessionStore = SessionStore()
    @StateObject private var membershipStore = MembershipStore()
    @StateObject private var purchaseStore = StoreKitPurchaseStore()
    @StateObject private var screenTimeBlocker = ScreenTimeBlocker()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UIScrollView.appearance().showsVerticalScrollIndicator = false
        UIScrollView.appearance().showsHorizontalScrollIndicator = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionStore)
                .environmentObject(membershipStore)
                .environmentObject(purchaseStore)
                .environmentObject(screenTimeBlocker)
                .environment(\.font, .blankBody)
                .task {
                    appDelegate.registerForRemoteActions()
                    await purchaseStore.loadProducts()
                    if BlankedRuntimeMode.legacyAccessEnabled {
                        await membershipStore.refreshIfNeeded()
                    }
                    await screenTimeBlocker.restore(selection: sessionStore.selection)
                    sessionStore.syncRecurringSchedule()
                    screenTimeBlocker.updateAdvancedControls(
                        allowOnlyModeEnabled: sessionStore.allowOnlyModeEnabled,
                        adultContentBlockingEnabled: sessionStore.adultContentBlockingEnabled
                    )
                    screenTimeBlocker.apply(isBlankActive: sessionStore.isBlankActive)
                    sessionStore.refreshDailyLimitMonitoring()
                }
                .task {
                    await purchaseStore.observeTransactionUpdates()
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        if BlankedRuntimeMode.legacyAccessEnabled {
                            Task {
                                await membershipStore.refreshIfNeeded(force: true)
                            }
                        }
                        screenTimeBlocker.refreshAuthorizationStatus()
                        sessionStore.syncRecurringSchedule()
                        screenTimeBlocker.updateAdvancedControls(
                            allowOnlyModeEnabled: sessionStore.allowOnlyModeEnabled,
                            adultContentBlockingEnabled: sessionStore.adultContentBlockingEnabled
                        )
                        sessionStore.refreshDailyLimitMonitoring()
                    }
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let action: String
        if url.scheme == "blank" {
            action = url.host ?? ""
        } else if isBlankedUniversalLink(url) {
            action = components?.stringQueryItem("action") ?? ""
        } else {
            return
        }

        if action == "referral" {
            purchaseStore.captureReferral(from: url)
            return
        }
        if action == "handoff" {
            let token = components?.stringQueryItem("token") ?? ""
            Task { await claimAppHandoff(token) }
            return
        }
        if action == "scan-blank", BlankedRuntimeMode.legacyNfcEnabled {
            sessionStore.requestBlankScanFromWidget()
            return
        }

        if action == "timer" || action == "schedule-timer" {
            sessionStore.requestWidgetTimerSelector()
            return
        }

        if action == "configure-block" || action == "open-picker" || action == "choose-apps" {
            openBlockConfiguration(from: components)
            return
        }

        if action == "setup-plan" {
            setupPlan(from: components)
            return
        }

        if action == "review-action" {
            if ["open_app_picker", "request_screen_time_permission"].contains(components?.stringQueryItem("type") ?? "") {
                BlankSharedState.defaults.set(true, forKey: "blankAssistantPollAfterOpen")
                return
            }
            requestAssistantActionConfirmation(from: components)
            return
        }

        if action == "start" || action == "start-blank" || action == "start-focus" {
            let minutes = components?.intQueryItem("minutes").map { min(max($0, 5), 240) }
            let hardMode = components?.boolQueryItem("hard") ?? false
            _ = sessionStore.activateBlank(durationMinutes: minutes, hardMode: hardMode, entryMode: .app)
            applyScreenTimeState()
            return
        }

        if action == "stop" || action == "stop-blank" {
            _ = sessionStore.deactivateBlank(entryMode: .app, endedReason: .manual, broken: true)
            screenTimeBlocker.clear()
            return
        }

        if action == "apply-plan" {
            applyPlan(from: components)
            return
        }

        if action == "allow-only" {
            sessionStore.allowOnlyModeEnabled = true
            sessionStore.requestBlockConfiguration()
            applyScreenTimeState()
            return
        }

        if action == "adult-filter" {
            sessionStore.adultContentBlockingEnabled = true
            applyScreenTimeState()
            return
        }

        if action == "daily-limit" {
            if let minutes = components?.intQueryItem("minutes") {
                sessionStore.dailyLimitMinutes = min(max(minutes, 5), 240)
                sessionStore.dailyLimitEnabled = true
                sessionStore.refreshDailyLimitMonitoring()
                applyScreenTimeState()
            }
            return
        }

        if action == "pause-rules" || action == "vacation" {
            let hours = min(max(components?.intQueryItem("hours") ?? 24, 1), 168)
            sessionStore.enableVacationMode(hours: hours)
            applyScreenTimeState()
            return
        }

        if action == "resume-rules" {
            sessionStore.disableVacationMode()
            applyScreenTimeState()
            return
        }

        if action == "mode" {
            let shouldActivate = components?.boolQueryItem("activate") ?? false
            let minutes = components?.intQueryItem("minutes").map { min(max($0, 5), 240) }
            let hardMode = components?.boolQueryItem("hard") ?? false
            if sessionStore.hasSelectedApps {
                if shouldActivate {
                    _ = sessionStore.activateBlank(durationMinutes: minutes, hardMode: hardMode, entryMode: .app)
                }
            } else {
                openBlockConfiguration(
                    from: components,
                    shouldActivate: shouldActivate,
                    durationMinutes: minutes,
                    hardMode: hardMode
                )
            }
            applyScreenTimeState()
        }
    }

    private func openBlockConfiguration(
        from components: URLComponents?,
        shouldActivate: Bool = false,
        durationMinutes: Int? = nil,
        hardMode: Bool = false
    ) {
        let appNames = components?.listQueryItem("apps") ?? []
        sessionStore.requestBlockConfiguration(
            appNames: appNames,
            shouldActivate: shouldActivate,
            durationMinutes: durationMinutes,
            hardMode: hardMode
        )
    }

    private func setupPlan(from components: URLComponents?) {
        applyPlan(from: components, shouldOpenPickerIfIncomplete: false)
        if !sessionStore.hasSelectedApps {
            openBlockConfiguration(from: components)
        }
    }

    private func applyPlan(from components: URLComponents?, shouldOpenPickerIfIncomplete: Bool = true) {
        let startMinute = components?.minuteQueryItem("start") ?? components?.intQueryItem("start_minute")
        let endMinute = components?.minuteQueryItem("end") ?? components?.intQueryItem("end_minute")
        let durationDays = components?.intQueryItem("days") ?? 7
        let weekdays = components?.listQueryItem("weekdays").compactMap(Int.init) ?? Array(1...7)

        if let startMinute, let endMinute {
            sessionStore.applyAdaptivePlan(
                startMinute: min(max(startMinute, 0), 1439),
                endMinute: min(max(endMinute, 0), 1439),
                durationDays: min(max(durationDays, 1), 14),
                activateCurrentWindow: false,
                name: "Protection",
                weekdays: weekdays
            )
            applyScreenTimeState()
        } else if shouldOpenPickerIfIncomplete {
            sessionStore.requestBlockConfiguration()
        }
    }

    private func requestAssistantActionConfirmation(from components: URLComponents?) {
        let type = components?.stringQueryItem("type") ?? ""
        let appNames = components?.listQueryItem("apps") ?? []
        let minutes = components?.intQueryItem("minutes").map { min(max($0, 5), 240) }
        let hardMode = components?.boolQueryItem("hard") ?? false
        switch type {
        case "start_protection", "activate_mode":
            sessionStore.requestAssistantActionConfirmation(.startProtection(minutes: minutes, hardMode: hardMode, appNames: appNames))
        case "switch_mode":
            sessionStore.requestAssistantActionConfirmation(.openAppPicker(appNames: appNames))
        case "apply_schedule":
            guard let start = components?.minuteQueryItem("start") ?? components?.intQueryItem("start_minute"),
                  let end = components?.minuteQueryItem("end") ?? components?.intQueryItem("end_minute") else { return }
            let weekdays = components?.listQueryItem("weekdays").compactMap(Int.init) ?? Array(1...7)
            sessionStore.requestAssistantActionConfirmation(.applySchedule(
                name: components?.stringQueryItem("name") ?? "AI Plan",
                startMinute: min(max(start, 0), 1439),
                endMinute: min(max(end, 0), 1439),
                weekdays: weekdays,
                durationDays: min(max(components?.intQueryItem("days") ?? 7, 1), 14),
                appNames: appNames
            ))
        case "set_daily_limit":
            sessionStore.requestAssistantActionConfirmation(.setDailyLimit(minutes: minutes, appNames: appNames))
        case "enable_allow_only":
            sessionStore.requestAssistantActionConfirmation(.allowOnly)
        case "enable_adult_filter":
            sessionStore.requestAssistantActionConfirmation(.adultFilter)
        case "pause_rules":
            sessionStore.requestAssistantActionConfirmation(.pauseRules(hours: min(max(components?.intQueryItem("hours") ?? 168, 1), 168)))
        case "disable_pause":
            sessionStore.requestAssistantActionConfirmation(.disablePause)
        case "apply_ai_plan":
            sessionStore.requestAssistantActionConfirmation(.applyAIPlan)
        case "open_app_picker":
            let pickerStart = components?.minuteQueryItem("start") ?? components?.intQueryItem("start_minute")
            let pickerEnd = components?.minuteQueryItem("end") ?? components?.intQueryItem("end_minute")
            let pickerName = components?.stringQueryItem("name") ?? ""
            let pickerSchedule: PendingPlanSchedule?
            if let pickerStart, let pickerEnd {
                pickerSchedule = PendingPlanSchedule(
                    name: components?.stringQueryItem("name") ?? "AI Plan",
                    startMinute: min(max(pickerStart, 0), 1439),
                    endMinute: min(max(pickerEnd, 0), 1439),
                    weekdays: components?.listQueryItem("weekdays").compactMap(Int.init) ?? Array(1...7),
                    durationDays: min(max(components?.intQueryItem("days") ?? 7, 1), 14)
                )
            } else {
                pickerSchedule = nil
            }
            if pickerName == "Daily Limit", let minutes {
                sessionStore.requestAssistantActionConfirmation(.configureAndOpenDailyLimitPicker(appNames: appNames, minutes: minutes))
            } else if pickerSchedule != nil || minutes != nil || hardMode || !pickerName.isEmpty {
                sessionStore.requestAssistantActionConfirmation(.configureAndOpenAppPicker(
                    appNames: appNames,
                    durationMinutes: minutes,
                    hardMode: hardMode,
                    schedule: pickerSchedule
                ))
            } else {
                sessionStore.requestAssistantActionConfirmation(.openAppPicker(appNames: appNames))
            }
        case "request_screen_time_permission":
            sessionStore.requestAssistantActionConfirmation(.requestScreenTimePermission)
        default:
            break
        }
    }

    private func applyScreenTimeState() {
        screenTimeBlocker.updateAdvancedControls(
            allowOnlyModeEnabled: sessionStore.allowOnlyModeEnabled,
            adultContentBlockingEnabled: sessionStore.adultContentBlockingEnabled
        )
        screenTimeBlocker.updateSelection(sessionStore.selection, isBlankActive: sessionStore.isBlankActive)
    }

    private func isBlankedUniversalLink(_ url: URL) -> Bool {
        guard url.scheme == "https", ["blankmind.ai", "blanked.app", "getblank.netlify.app"].contains(url.host ?? "") else { return false }
        return url.path == "/open" || url.path == "/open.html"
    }

    private func claimAppHandoff(_ token: String) async {
        guard !token.isEmpty,
              let baseURL = configuredMembershipBaseURL() else { return }
        var request = URLRequest(url: baseURL.appendingPathComponent("app-handoff"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8
        let payload: [String: Any] = [
            "action": "claim",
            "handoff_token": token,
            "app_install_id": BlankSharedState.appInstallId,
            "data_consent": true,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let defaults = BlankSharedState.defaults
        if let connectCode = result["assistant_connect_code"] as? String, !connectCode.isEmpty {
            defaults.set(connectCode, forKey: "blankAssistantConnectCode")
        }
        if let phone = result["phone_e164"] as? String, !phone.isEmpty {
            defaults.set(phone, forKey: "blankAssistantPhoneNumber")
        }
        defaults.set(Date.now.formatted(date: .abbreviated, time: .shortened), forKey: "blankAssistantConnectedAt")
    }

    private func configuredMembershipBaseURL() -> URL? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "BlankMembershipAPIBaseURL") as? String else {
            return nil
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return URL(string: trimmed)
    }
}

@MainActor
final class BlankAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        registerForRemoteActions()
        return true
    }

    func registerForRemoteActions() {
        UIApplication.shared.registerForRemoteNotifications()
        registerStoredTokenIfPossible()
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        BlankSharedState.defaults.set(token, forKey: "blankAssistantPushToken")
        registerStoredTokenIfPossible()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        BlankSharedState.defaults.removeObject(forKey: "blankAssistantPushToken")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard userInfo["bm_action_id"] != nil else {
            completionHandler(.noData)
            return
        }
        Task { @MainActor in
            let outcome = await AssistantBackgroundActionRunner().run()
            completionHandler(outcome)
        }
    }

    private func registerStoredTokenIfPossible() {
        let defaults = BlankSharedState.defaults
        let token = defaults.string(forKey: "blankAssistantPushToken") ?? ""
        let code = defaults.string(forKey: "blankAssistantConnectCode") ?? ""
        let rawChannel = defaults.string(forKey: "blankAssistantPreferredChannel") ?? ""
        let channel = rawChannel == "whatsApp" ? "whatsapp" : rawChannel.lowercased()
        guard !token.isEmpty, !code.isEmpty, ["whatsapp", "sms"].contains(channel) else { return }
        let phone = defaults.string(forKey: "blankAssistantPhoneNumber") ?? ""
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        Task {
            _ = await AssistantActionInboxClient().registerDevicePush(
                token: token,
                environment: environment,
                connectCode: code,
                channel: channel,
                phoneNumber: phone
            )
        }
    }
}

@MainActor
private struct AssistantBackgroundActionRunner {
    func run() async -> UIBackgroundFetchResult {
        let defaults = BlankSharedState.defaults
        let code = defaults.string(forKey: "blankAssistantConnectCode") ?? ""
        let rawChannel = defaults.string(forKey: "blankAssistantPreferredChannel") ?? ""
        let channel = rawChannel == "whatsApp" ? "whatsapp" : rawChannel.lowercased()
        let phone = defaults.string(forKey: "blankAssistantPhoneNumber") ?? ""
        guard ["whatsapp", "sms"].contains(channel) else { return .noData }
        let client = AssistantActionInboxClient()
        if let receipt = AssistantActionReceiptStore.load(defaults: defaults) {
            let acknowledged = await client.acknowledgeLifecycle(
                receipt: receipt,
                connectCode: code,
                channel: channel,
                phoneNumber: phone
            )
            if acknowledged {
                AssistantActionReceiptStore.clear(actionId: receipt.actionId, defaults: defaults)
                return .newData
            }
            return .failed
        }
        guard let remote = await client.poll(connectCode: code, channel: channel, phoneNumber: phone),
              let action = remote.toPendingAction() else { return .noData }

        if case .openAppPicker = action { return .noData }
        if case .configureAndOpenAppPicker = action { return .noData }
        if case .configureAndOpenDailyLimitPicker = action { return .noData }
        if case .requestScreenTimePermission = action { return .noData }

        guard await client.acknowledge(
            actionId: remote.id,
            status: "confirmed",
            connectCode: code,
            channel: channel,
            phoneNumber: phone
        ) else { return .failed }
        guard await client.acknowledge(
            actionId: remote.id,
            status: "execution_started",
            connectCode: code,
            channel: channel,
            phoneNumber: phone
        ) else { return .failed }

        let store = SessionStore(defaults: defaults)
        let blocker = ScreenTimeBlocker()
        await blocker.restore(selection: store.selection)
        blocker.refreshAuthorizationStatus()
        guard blocker.authorizationStatus == .approved else {
            let receipt = AssistantActionReceipt(
                actionId: remote.id,
                status: "failed",
                detail: "screen_time_permission_required",
                executionStarted: true
            )
            AssistantActionReceiptStore.save(
                actionId: receipt.actionId,
                status: receipt.status,
                detail: receipt.detail,
                executionStarted: receipt.executionStarted,
                defaults: defaults
            )
            if await client.acknowledge(actionId: remote.id, status: receipt.status, connectCode: code, channel: channel, phoneNumber: phone, detail: receipt.detail) {
                AssistantActionReceiptStore.clear(actionId: receipt.actionId, defaults: defaults)
            }
            return .failed
        }

        let outcome = execute(remote: remote, action: action, store: store, blocker: blocker)
        let receipt = AssistantActionReceipt(
            actionId: remote.id,
            status: outcome.status,
            detail: outcome.detail,
            executionStarted: true,
            requestedAt: outcome.execution.map { ISO8601DateFormatter().string(from: $0.requestedAt) } ?? "",
            startedAt: outcome.execution.map { ISO8601DateFormatter().string(from: $0.startedAt) } ?? "",
            requestedDurationMinutes: outcome.execution?.requestedDurationMinutes,
            effectiveUntil: outcome.execution?.effectiveUntil.map { ISO8601DateFormatter().string(from: $0) } ?? "",
            origin: outcome.execution == nil ? "" : "assistant_remote",
            result: outcome.execution?.result ?? "",
            startDelaySeconds: outcome.execution?.startDelaySeconds,
            mergedWithExisting: outcome.execution?.mergedWithExisting ?? false
        )
        AssistantActionReceiptStore.save(
            actionId: receipt.actionId,
            status: receipt.status,
            detail: receipt.detail,
            executionStarted: receipt.executionStarted,
            requestedAt: receipt.requestedAt,
            startedAt: receipt.startedAt,
            requestedDurationMinutes: receipt.requestedDurationMinutes,
            effectiveUntil: receipt.effectiveUntil,
            origin: receipt.origin,
            result: receipt.result,
            startDelaySeconds: receipt.startDelaySeconds,
            mergedWithExisting: receipt.mergedWithExisting,
            defaults: defaults
        )
        if await client.acknowledge(
            actionId: remote.id,
            status: receipt.status,
            connectCode: code,
            channel: channel,
            phoneNumber: phone,
            detail: receipt.detail,
            evidence: receipt
        ) {
            AssistantActionReceiptStore.clear(actionId: receipt.actionId, defaults: defaults)
        }
        return outcome.status == "verified" || outcome.status == "delayed" ? .newData : .failed
    }

    private func execute(
        remote: AssistantInboxAction,
        action: AssistantPendingAction,
        store: SessionStore,
        blocker: ScreenTimeBlocker
    ) -> (status: String, detail: String, execution: AssistantProtectionExecution?) {
        switch action {
        case .startProtection(let minutes, let hardMode, let appNames):
            guard let minutes, let requestedAt = remote.requestedDate else { return ("failed", "missing_exact_action_metadata", nil) }
            guard store.restoreSavedSelectionForAssistant(appNames: appNames) else { return ("failed", "distraction_selection_required", nil) }
            let execution = store.applyAssistantProtection(
                actionId: remote.id,
                requestedAt: requestedAt,
                durationMinutes: minutes,
                hardMode: hardMode
            )
            apply(store: store, blocker: blocker)
            return (execution.status, execution.detail, execution)
        case .applySchedule(_, let start, let end, let weekdays, let days, let appNames):
            guard store.restoreSavedSelectionForAssistant(appNames: appNames) else { return ("failed", "distraction_selection_required", nil) }
            store.applyAdaptivePlan(startMinute: start, endMinute: end, durationDays: days, activateCurrentWindow: true, name: "Protection", weekdays: weekdays)
            apply(store: store, blocker: blocker)
            return ("verified", "canonical_schedule_persisted", nil)
        case .setDailyLimit(let minutes, let appNames):
            guard let minutes, store.restoreSavedSelectionForAssistant(appNames: appNames) else { return ("failed", "distraction_selection_required", nil) }
            store.dailyLimitMinutes = minutes
            store.dailyLimitEnabled = true
            store.refreshDailyLimitMonitoring()
            apply(store: store, blocker: blocker)
            return (store.dailyLimitEnabled && store.dailyLimitMinutes == minutes ? "verified" : "failed", "daily_limit_state_checked", nil)
        case .allowOnly:
            store.allowOnlyModeEnabled = true
            apply(store: store, blocker: blocker)
            return (store.allowOnlyModeEnabled ? "verified" : "failed", "allow_only_state_checked", nil)
        case .adultFilter:
            store.adultContentBlockingEnabled = true
            apply(store: store, blocker: blocker)
            return (store.adultContentBlockingEnabled ? "verified" : "failed", "adult_filter_state_checked", nil)
        case .pauseRules(let hours):
            store.enableVacationMode(hours: hours)
            apply(store: store, blocker: blocker)
            return (store.isVacationModeActive ? "verified" : "failed", "pause_state_checked", nil)
        case .disablePause:
            store.disableVacationMode()
            apply(store: store, blocker: blocker)
            return (!store.isVacationModeActive ? "verified" : "failed", "resume_state_checked", nil)
        case .applyAIPlan:
            store.applyAIPlan()
            apply(store: store, blocker: blocker)
            return ("verified", "ai_plan_persisted", nil)
        case .openAppPicker, .configureAndOpenAppPicker, .configureAndOpenDailyLimitPicker, .requestScreenTimePermission:
            return ("failed", "foreground_setup_required", nil)
        }
    }

    private func apply(store: SessionStore, blocker: ScreenTimeBlocker) {
        blocker.updateAdvancedControls(
            allowOnlyModeEnabled: store.allowOnlyModeEnabled,
            adultContentBlockingEnabled: store.adultContentBlockingEnabled
        )
        blocker.updateSelection(store.selection, isBlankActive: store.isBlankActive)
    }
}

private extension URLComponents {
    func stringQueryItem(_ name: String) -> String? {
        queryItems?.first(where: { $0.name == name })?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func intQueryItem(_ name: String) -> Int? {
        guard let value = stringQueryItem(name) else { return nil }
        return Int(value)
    }

    func boolQueryItem(_ name: String) -> Bool? {
        guard let value = stringQueryItem(name)?.lowercased() else { return nil }
        if ["1", "true", "yes"].contains(value) { return true }
        if ["0", "false", "no"].contains(value) { return false }
        return nil
    }

    func listQueryItem(_ name: String) -> [String] {
        guard let value = stringQueryItem(name) else { return [] }

        var items: [String] = []
        for rawItem in value.split(separator: ",") {
            let item = rawItem.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !item.isEmpty else { continue }
            items.append(String(item.prefix(30)))
            if items.count >= 8 { break }
        }
        return items
    }

    func minuteQueryItem(_ name: String) -> Int? {
        guard let value = stringQueryItem(name) else { return nil }
        if let minutes = Int(value) { return minutes }
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return min(max(hour, 0), 23) * 60 + min(max(minute, 0), 59)
    }
}
