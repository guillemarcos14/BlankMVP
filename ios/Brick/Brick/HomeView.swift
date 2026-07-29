import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var screenTimeBlocker: ScreenTimeBlocker

    @State private var now = Date()
    @State private var message: String?
    @State private var showingPicker = false
    @State private var nfcReader = NFCReader()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let homeTagline = "¿Lo ves? Al final\nno era urgente,\nera costumbre."

    var body: some View {
        ZStack {
            homeBackground

            VStack(spacing: 16) {
                Spacer()

                VStack(spacing: 24) {
                    Text(homeTagline)
                        .font(.system(size: 37, weight: .semibold))
                        .lineSpacing(1)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.78)
                        .foregroundStyle(.white)

                    Button(action: scanTag) {
                        Text(sessionStore.isBlankActive ? "Escanear Blank para salir" : "Blankear")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: sessionStore.isBlankActive ? 320 : 178)
                            .frame(height: 48)
                            .background(Color(red: 0.694, green: 0.702, blue: 0.722).opacity(0.82))
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 8)
                    }
                    .buttonStyle(.plain)

                    statusBlock
                }
                .frame(maxWidth: 340)

                Spacer()

                bottomLinks
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 42)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .onReceive(timer) { date in
            now = date
        }
        .familyActivityPicker(isPresented: $showingPicker, selection: $sessionStore.selection)
        .onChange(of: sessionStore.selection) { newSelection in
            screenTimeBlocker.updateSelection(newSelection, isBlankActive: sessionStore.isBlankActive)
        }
    }

    private var homeBackground: some View {
        ZStack {
            LinearGradient(
                colors: sessionStore.isBlankActive
                    ? [Color(red: 0.13, green: 0.14, blue: 0.15), Color(red: 0.42, green: 0.45, blue: 0.50)]
                    : [Color(red: 0.58, green: 0.61, blue: 0.68), Color(red: 0.80, green: 0.80, blue: 0.76)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.white.opacity(sessionStore.isBlankActive ? 0.12 : 0.22), .clear],
                center: .center,
                startRadius: 40,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var statusBlock: some View {
        VStack(spacing: 8) {
            if sessionStore.isBlankActive, let blankActiveSince = sessionStore.blankActiveSince {
                Text(elapsedText(since: blankActiveSince))
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.86))

                Text("Activo desde \(blankActiveSince.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.70))
            }

            if sessionStore.hasSelectedApps {
                Text("\(selectionCount) apps protegidas")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.74))
            }

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.74))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
    }

    private var bottomLinks: some View {
        VStack(spacing: 10) {
            NavigationLink {
                ReportView()
            } label: {
                Text("Progreso")
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(.white.opacity(0.74))

            if !sessionStore.isBlankActive {
                Button("Editar apps") {
                    showingPicker = true
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.74))

                Button("Olvidar NFC") {
                    sessionStore.forgetNfcTag()
                    screenTimeBlocker.clear()
                }
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.58))
            }
        }
    }

    private var selectionCount: Int {
        sessionStore.selection.applicationTokens.count +
        sessionStore.selection.categoryTokens.count +
        sessionStore.selection.webDomainTokens.count
    }

    private func scanTag() {
        nfcReader.scan { result in
            Task { @MainActor in
                switch result {
                case .success(let uid):
                    let nfcResult = sessionStore.handleNfcTag(uid: uid)
                    screenTimeBlocker.apply(isBlankActive: sessionStore.isBlankActive)
                    message = messageText(for: nfcResult)
                case .failure(let error):
                    message = error.localizedDescription
                }
            }
        }
    }

    private func messageText(for result: SessionStore.NfcResult) -> String {
        switch result {
        case .tagRegistered:
            return "NFC tag registered."
        case .bricked:
            return "Blank mode activated."
        case .unbricked:
            return "Blank mode deactivated."
        case .wrongTag:
            return "Tag not recognized. Use your paired Blank."
        case .noAppsSelected:
            return "Select at least one app to block first."
        }
    }

    private func elapsedText(since date: Date) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(date)))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
