import FamilyControls
import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var screenTimeBlocker: ScreenTimeBlocker

    @State private var currentStep = 0
    @State private var showingPicker = false
    @State private var message: String?
    @State private var nfcReader = NFCReader()

    var body: some View {
        VStack(spacing: 32) {
            Text("Setup Blank")
                .font(.largeTitle.weight(.bold))

            Spacer()

            switch currentStep {
            case 0:
                setupStep(
                    title: "Authorize Screen Time",
                    description: screenTimeDescription,
                    buttonTitle: "Authorize",
                    action: authorizeScreenTime
                )
            case 1:
                setupStep(
                    title: "Pair NFC Tag",
                    description: sessionStore.nfcTagUid == nil
                        ? "Scan your physical Blank NFC tag to pair it with this iPhone."
                        : "NFC tag registered. Continue to app selection.",
                    buttonTitle: sessionStore.nfcTagUid == nil ? "Scan Tag" : "Continue",
                    action: scanOrContinue
                )
            case 2:
                setupStep(
                    title: "Select Apps",
                    description: sessionStore.hasSelectedApps
                        ? "\(selectionCount) selected"
                        : "Choose the apps, categories, or web domains to shield when Blank mode is active.",
                    buttonTitle: sessionStore.hasSelectedApps ? "Continue" : "Select Apps",
                    action: selectAppsOrContinue
                )
            default:
                setupStep(
                    title: "Setup Complete",
                    description: "Blank is ready on this iPhone.",
                    buttonTitle: "Finish Setup",
                    action: {
                        screenTimeBlocker.updateSelection(sessionStore.selection, isBlankActive: sessionStore.isBlankActive)
                        sessionStore.finishSetup()
                    }
                )
            }

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(BrickColors.secondaryText)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            stepIndicator
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrickColors.background)
        .foregroundStyle(BrickColors.text)
        .familyActivityPicker(isPresented: $showingPicker, selection: $sessionStore.selection)
        .onChange(of: sessionStore.selection) { _, newSelection in
            screenTimeBlocker.updateSelection(newSelection, isBlankActive: sessionStore.isBlankActive)
        }
    }

    private var screenTimeDescription: String {
        if screenTimeBlocker.authorizationStatus == .approved {
            return "Screen Time authorization is approved."
        }
        return "Blank needs Screen Time access to shield the apps you choose. This replaces Android Accessibility on iOS."
    }

    private var selectionCount: Int {
        sessionStore.selection.applicationTokens.count +
        sessionStore.selection.categoryTokens.count +
        sessionStore.selection.webDomainTokens.count
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(index <= currentStep ? BrickColors.green : BrickColors.surface)
                    .frame(width: 8, height: 8)
            }
        }
    }

    private func setupStep(
        title: String,
        description: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 18) {
            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(description)
                .font(.body)
                .foregroundStyle(BrickColors.secondaryText)
                .multilineTextAlignment(.center)

            Button(action: action) {
                Text(buttonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(BrickColors.green)
        }
    }

    private func authorizeScreenTime() {
        Task {
            if await screenTimeBlocker.requestAuthorization() {
                currentStep = 1
                message = nil
            } else {
                message = screenTimeBlocker.lastErrorMessage ?? "Screen Time authorization was not approved."
            }
        }
    }

    private func scanOrContinue() {
        if sessionStore.nfcTagUid != nil {
            currentStep = 2
            return
        }

        nfcReader.scan { result in
            Task { @MainActor in
                switch result {
                case .success(let uid):
                    _ = sessionStore.handleNfcTag(uid: uid)
                    currentStep = 2
                    message = "NFC tag registered."
                case .failure(let error):
                    message = error.localizedDescription
                }
            }
        }
    }

    private func selectAppsOrContinue() {
        if sessionStore.hasSelectedApps {
            currentStep = 3
        } else {
            showingPicker = true
        }
    }
}
