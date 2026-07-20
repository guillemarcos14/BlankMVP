import SwiftUI

@main
struct BlankApp: App {
    @StateObject private var sessionStore = SessionStore()
    @StateObject private var screenTimeBlocker = ScreenTimeBlocker()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionStore)
                .environmentObject(screenTimeBlocker)
                .task {
                    await screenTimeBlocker.restore(selection: sessionStore.selection)
                    screenTimeBlocker.apply(isBlankActive: sessionStore.isBlankActive)
                }
        }
    }
}
