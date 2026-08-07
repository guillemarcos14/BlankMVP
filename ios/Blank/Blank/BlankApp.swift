import SwiftUI

@main
struct BlankApp: App {
    @StateObject private var sessionStore = SessionStore()
    @StateObject private var membershipStore = MembershipStore()
    @StateObject private var screenTimeBlocker = ScreenTimeBlocker()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionStore)
                .environmentObject(membershipStore)
                .environmentObject(screenTimeBlocker)
                .environment(\.font, .blankBody)
                .task {
                    await membershipStore.refreshIfNeeded()
                    await screenTimeBlocker.restore(selection: sessionStore.selection)
                    screenTimeBlocker.apply(isBlankActive: sessionStore.isBlankActive)
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        Task {
                            await membershipStore.refreshIfNeeded(force: true)
                        }
                        screenTimeBlocker.refreshAuthorizationStatus()
                    }
                }
                .onOpenURL { url in
                    guard url.scheme == "blank" else { return }
                    if url.host == "scan-blank" {
                        sessionStore.requestBlankScanFromWidget()
                    } else if url.host == "configure-block" {
                        sessionStore.requestBlockConfiguration()
                    }
                }
        }
    }
}
