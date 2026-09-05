import SwiftUI
import UIKit

@main
struct BlankApp: App {
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
                    await purchaseStore.loadProducts()
                    if BlankedRuntimeMode.legacyAccessEnabled {
                        await membershipStore.refreshIfNeeded()
                    }
                    await screenTimeBlocker.restore(selection: sessionStore.selection)
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
        guard url.scheme == "blank" else { return }
        let action = url.host ?? ""
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        if action == "referral" {
            purchaseStore.captureReferral(from: url)
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
            if let name = components?.stringQueryItem("name"), !sessionStore.selectMode(named: name) {
                sessionStore.requestBlockConfiguration()
            }
            applyScreenTimeState()
        }
    }

    private func openBlockConfiguration(from components: URLComponents?) {
        let appNames = components?.listQueryItem("apps") ?? []
        sessionStore.requestBlockConfiguration(appNames: appNames)
    }

    private func setupPlan(from components: URLComponents?) {
        applyPlan(from: components, shouldOpenPickerIfIncomplete: false)
        openBlockConfiguration(from: components)
    }

    private func applyPlan(from components: URLComponents?, shouldOpenPickerIfIncomplete: Bool = true) {
        let startMinute = components?.minuteQueryItem("start") ?? components?.intQueryItem("start_minute")
        let endMinute = components?.minuteQueryItem("end") ?? components?.intQueryItem("end_minute")
        let durationDays = components?.intQueryItem("days") ?? 7

        if let startMinute, let endMinute {
            sessionStore.applyAdaptivePlan(
                startMinute: min(max(startMinute, 0), 1439),
                endMinute: min(max(endMinute, 0), 1439),
                durationDays: min(max(durationDays, 1), 14)
            )
            applyScreenTimeState()
        } else if shouldOpenPickerIfIncomplete {
            sessionStore.requestBlockConfiguration()
        }
    }

    private func applyScreenTimeState() {
        screenTimeBlocker.updateAdvancedControls(
            allowOnlyModeEnabled: sessionStore.allowOnlyModeEnabled,
            adultContentBlockingEnabled: sessionStore.adultContentBlockingEnabled
        )
        screenTimeBlocker.apply(isBlankActive: sessionStore.isBlankActive)
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
        return value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { String($0.prefix(30)) }
            .prefix(8)
            .map(String.init)
    }

    func minuteQueryItem(_ name: String) -> Int? {
        guard let value = stringQueryItem(name) else { return nil }
        if let minutes = Int(value) { return minutes }
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return min(max(hour, 0), 23) * 60 + min(max(minute, 0), 59)
    }
}
