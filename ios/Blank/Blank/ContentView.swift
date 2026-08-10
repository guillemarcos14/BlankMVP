import SwiftUI

enum BlankedRuntimeMode {
    static let softwareOnly = true
    static let legacyAccessEnabled = false
    static let legacyNfcEnabled = false
}

struct ContentView: View {
    @EnvironmentObject private var sessionStore: SessionStore

    var body: some View {
        Group {
            if sessionStore.setupComplete {
                HomeView()
            } else {
                SetupView()
            }
        }
    }
}
