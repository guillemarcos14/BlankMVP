import SwiftUI

enum BlankedRuntimeMode {
    static let softwareOnly = true
    static let legacyAccessEnabled = false
    static let legacyNfcEnabled = false
}

struct ContentView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var membershipStore: MembershipStore

    var body: some View {
        Group {
            if !BlankedRuntimeMode.softwareOnly && BlankedRuntimeMode.legacyAccessEnabled && !membershipStore.hasAccess {
                MembershipActivationView()
            } else if sessionStore.setupComplete {
                HomeView()
            } else {
                SetupView()
            }
        }
    }
}
