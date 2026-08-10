import FamilyControls
import SwiftUI

private enum OnboardingStep: Int, CaseIterable {
    case apps
    case permission
    case start
}

struct SetupView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var screenTimeBlocker: ScreenTimeBlocker
    @Environment(\.scenePhase) private var scenePhase

    @State private var currentStep: OnboardingStep = .apps
    @State private var showingPicker = false
    @State private var message: String?

    var body: some View {
        ZStack {
            BlankAtmosphericBackground()

            VStack(spacing: 0) {
                Spacer()
                content
                Spacer()
                stepIndicator
                    .padding(.bottom, 10)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(BlankColors.ink)
        .familyActivityPicker(isPresented: $showingPicker, selection: $sessionStore.selection)
        .task {
            await refreshScreenTimeAndContinueIfApproved()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            Task {
                await refreshScreenTimeAndContinueIfApproved()
            }
        }
        .onChange(of: sessionStore.selection) { newSelection in
            screenTimeBlocker.updateSelection(newSelection, isBlankActive: sessionStore.isBlankActive)
            if currentStep == .apps, sessionStore.hasSelectedApps {
                currentStep = .permission
                message = nil
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch currentStep {
        case .apps:
            onboardingScreen(
                title: "Choose apps.",
                subtitle: "Select what Blanked should block.",
                primaryTitle: sessionStore.hasSelectedApps ? "Continue" : "Select apps",
                secondaryTitle: nil,
                primaryAction: {
                    if sessionStore.hasSelectedApps {
                        currentStep = .permission
                    } else {
                        showingPicker = true
                    }
                }
            )
        case .permission:
            onboardingScreen(
                title: "Allow Screen Time.",
                subtitle: "iOS needs this permission to block apps.",
                primaryTitle: screenTimeBlocker.authorizationStatus == .approved ? "Continue" : "Allow",
                secondaryTitle: "Back",
                primaryAction: authorizeScreenTime,
                secondaryAction: { currentStep = .apps }
            )
        case .start:
            onboardingScreen(
                title: "Ready.",
                subtitle: "Start your first 30 minute block.",
                primaryTitle: "Start",
                secondaryTitle: "Later",
                primaryAction: startFirstBlock,
                secondaryAction: finishWithoutStarting
            )
        }
    }

    private func onboardingScreen(
        title: String,
        subtitle: String,
        primaryTitle: String,
        secondaryTitle: String?,
        primaryAction: @escaping () -> Void,
        secondaryAction: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 18) {
            Text(title)
                .font(.blankInter(size: 38, weight: .medium, relativeTo: .largeTitle))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            Text(subtitle)
                .font(.blankInter(size: 16, relativeTo: .body))
                .foregroundStyle(BlankColors.mutedInk)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 280)

            if let message {
                Text(message)
                    .font(.blankInter(size: 13, relativeTo: .footnote))
                    .foregroundStyle(BlankColors.mutedInk)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            Button(primaryTitle, action: primaryAction)
                .buttonStyle(BlankPrimaryButtonStyle())
                .frame(width: onboardingButtonWidth(for: primaryTitle))
                .padding(.top, 8)

            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(BlankSecondaryButtonStyle())
                    .frame(width: onboardingButtonWidth(for: secondaryTitle))
            }

            #if DEBUG
            #if targetEnvironment(simulator)
            Button("Enter Home in simulator") {
                enterSimulatorHome()
            }
            .buttonStyle(BlankSecondaryButtonStyle())
            .frame(width: onboardingButtonWidth(for: "Enter Home in simulator"))
            .padding(.top, 4)
            #endif
            #endif
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(step.rawValue <= currentStep.rawValue ? BlankColors.ink : BlankColors.line)
                    .frame(width: step == currentStep ? 22 : 8, height: 8)
            }
        }
    }

    private func authorizeScreenTime() {
        if screenTimeBlocker.authorizationStatus == .approved {
            currentStep = .start
            message = nil
            return
        }

        Task {
            if await screenTimeBlocker.requestAuthorization() {
                currentStep = .start
                message = nil
            } else {
                message = "Permission pending."
            }
        }
    }

    private func refreshScreenTimeAndContinueIfApproved() async {
        await screenTimeBlocker.refreshAuthorizationStatusUntilSettled()
        if screenTimeBlocker.authorizationStatus == .approved, currentStep == .permission {
            currentStep = .start
            message = nil
        }
    }

    private func startFirstBlock() {
        screenTimeBlocker.updateSelection(sessionStore.selection, isBlankActive: sessionStore.isBlankActive)
        let result = sessionStore.activateBlank(durationMinutes: 30, entryMode: .app)
        switch result {
        case .blanked:
            screenTimeBlocker.apply(isBlankActive: true)
            sessionStore.finishSetup()
        case .noAppsSelected:
            currentStep = .apps
            message = "Select at least one app."
        default:
            sessionStore.finishSetup()
        }
    }

    private func finishWithoutStarting() {
        screenTimeBlocker.updateSelection(sessionStore.selection, isBlankActive: sessionStore.isBlankActive)
        sessionStore.finishSetup()
    }

    #if DEBUG
    #if targetEnvironment(simulator)
    private func enterSimulatorHome() {
        screenTimeBlocker.updateSelection(sessionStore.selection, isBlankActive: sessionStore.isBlankActive)
        sessionStore.finishSetup()
    }
    #endif
    #endif

    private func onboardingButtonWidth(for title: String) -> CGFloat {
        let estimated = CGFloat(title.count) * 8.6 + 64
        return min(max(estimated, 184), 276)
    }
}
