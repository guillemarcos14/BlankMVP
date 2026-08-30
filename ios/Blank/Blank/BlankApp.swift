import SwiftUI

@main
struct BlankApp: App {
    @StateObject private var sessionStore = SessionStore()
    @StateObject private var membershipStore = MembershipStore()
    @StateObject private var purchaseStore = StoreKitPurchaseStore()
    @StateObject private var screenTimeBlocker = ScreenTimeBlocker()
    @Environment(\.scenePhase) private var scenePhase

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
                    guard url.scheme == "blank" else { return }
                    if url.host == "referral" {
                        purchaseStore.captureReferral(from: url)
                    } else if url.host == "scan-blank", BlankedRuntimeMode.legacyNfcEnabled {
                        sessionStore.requestBlankScanFromWidget()
                    } else if url.host == "configure-block" {
                        sessionStore.requestBlockConfiguration()
                    } else if url.host == "start" || url.host == "start-blank" {
                        _ = sessionStore.activateBlank(entryMode: .app)
                        screenTimeBlocker.updateAdvancedControls(
                            allowOnlyModeEnabled: sessionStore.allowOnlyModeEnabled,
                            adultContentBlockingEnabled: sessionStore.adultContentBlockingEnabled
                        )
                        screenTimeBlocker.apply(isBlankActive: sessionStore.isBlankActive)
                    } else if url.host == "stop" || url.host == "stop-blank" {
                        _ = sessionStore.deactivateBlank(entryMode: .app, endedReason: .manual, broken: true)
                        screenTimeBlocker.clear()
                    }
                }
        }
    }
}
