import SwiftUI

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
