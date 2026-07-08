import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var screenTimeBlocker: ScreenTimeBlocker

    @State private var now = Date()
    @State private var message: String?
    @State private var showingPicker = false
    @State private var nfcReader = NFCReader()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Text(sessionStore.isBlankActive ? "BLANKED" : "UNBLANKED")
                .font(.system(size: 46, weight: .bold))
                .multilineTextAlignment(.center)

            Text(sessionStore.isBlankActive ? "Scan your NFC tag to deactivate Blank mode" : "Scan your NFC tag to activate Blank mode")
                .font(.body)
                .foregroundStyle(BrickColors.secondaryText)
                .multilineTextAlignment(.center)

            if sessionStore.isBlankActive, let blankActiveSince = sessionStore.blankActiveSince {
                Text(elapsedText(since: blankActiveSince))
                    .font(.system(size: 34, weight: .semibold, design: .monospaced))
                    .padding(.top, 16)

                Text("Blanked since \(blankActiveSince.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(BrickColors.secondaryText.opacity(0.7))
            }

            if sessionStore.hasSelectedApps {
                Text("\(selectionCount) selected")
                    .font(.body)
                    .foregroundStyle(BrickColors.secondaryText)
                    .padding(.top, 24)
            }

            NavigationLink {
                ReportView()
            } label: {
                Text("View weekly report")
                    .font(.footnote.weight(.semibold))
                    .underline()
            }
            .foregroundStyle(BrickColors.secondaryText)

            Button(action: scanTag) {
                Text("Scan NFC Tag")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(sessionStore.isBlankActive ? BrickColors.red : BrickColors.green)
            .padding(.top, 16)

            if !sessionStore.isBlankActive {
                Button("Edit Apps") {
                    showingPicker = true
                }
                .buttonStyle(.bordered)
                .tint(BrickColors.text)

                Button("Forget NFC Tag") {
                    sessionStore.forgetNfcTag()
                    screenTimeBlocker.clear()
                }
                .foregroundStyle(BrickColors.secondaryText)
            }

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(BrickColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(sessionStore.isBlankActive ? BrickColors.redDark : BrickColors.background)
        .foregroundStyle(BrickColors.text)
        .onReceive(timer) { date in
            now = date
        }
        .familyActivityPicker(isPresented: $showingPicker, selection: $sessionStore.selection)
        .onChange(of: sessionStore.selection) { newSelection in
            screenTimeBlocker.updateSelection(newSelection, isBlankActive: sessionStore.isBlankActive)
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
