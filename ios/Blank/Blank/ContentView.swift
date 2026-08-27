import SwiftUI

enum BlankedRuntimeMode {
    static let softwareOnly = true
    static let legacyAccessEnabled = false
    static let legacyNfcEnabled = false
}

struct ContentView: View {
    @EnvironmentObject private var sessionStore: SessionStore

    var body: some View {
        ZStack {
            if sessionStore.setupComplete {
                HomeView()
                    .transition(.opacity.combined(with: .scale(scale: 1.01, anchor: .center)))
            } else {
                SetupView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.85), value: sessionStore.setupComplete)
    }
}
