import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var membershipStore: MembershipStore

    var body: some View {
        Group {
            if !membershipStore.hasAccess {
                MembershipActivationView()
            } else if sessionStore.setupComplete {
                HomeView()
            } else {
                SetupView()
            }
        }
    }
}
