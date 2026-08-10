import FamilyControls
import SwiftUI

private enum OnboardingStep: Int, CaseIterable {
    case promise
    case goal
    case weakMoment
    case permission
    case apps
    case firstBlock
}

private struct OnboardingOption: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
}

struct SetupView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var screenTimeBlocker: ScreenTimeBlocker
    @Environment(\.scenePhase) private var scenePhase

    @State private var currentStep: OnboardingStep = .promise
    @State private var showingPicker = false
    @State private var message: String?
    @AppStorage("blankWeeklyAIGoal", store: BlankSharedState.defaults) private var onboardingGoal = ""
    @AppStorage("blankOnboardingWeakMoment", store: BlankSharedState.defaults) private var weakMoment = ""

    private let goalOptions = [
        OnboardingOption(id: "focus", title: "Focus deeply", subtitle: "Protect work, study, or creative time.", icon: "target"),
        OnboardingOption(id: "scroll", title: "Stop scrolling", subtitle: "Block the apps that pull you back in.", icon: "iphone.slash"),
        OnboardingOption(id: "sleep", title: "Sleep earlier", subtitle: "Keep nights away from feeds and shorts.", icon: "moon")
    ]

    private let weakMomentOptions = [
        OnboardingOption(id: "morning", title: "Morning", subtitle: "Before the day has started.", icon: "sunrise"),
        OnboardingOption(id: "afternoon", title: "Afternoon", subtitle: "When energy drops.", icon: "sun.max"),
        OnboardingOption(id: "night", title: "Night", subtitle: "When one minute becomes an hour.", icon: "moon.zzz")
    ]

    var body: some View {
        ZStack {
            BlankAtmosphericBackground()

            VStack(spacing: 0) {
                Spacer(minLength: 28)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        content

                        if let message {
                            Text(message)
                                .font(.blankInter(size: 13, relativeTo: .footnote))
                                .foregroundStyle(BlankColors.secondaryText)
                                .multilineTextAlignment(.center)
                                .lineSpacing(2)
                                .frame(maxWidth: 330)
                        }

                        #if DEBUG
                        #if targetEnvironment(simulator)
                        Button("Enter Home in simulator") {
                            enterSimulatorHome()
                        }
                        .buttonStyle(BlankSecondaryButtonStyle())
                        .frame(width: onboardingButtonWidth(for: "Enter Home in simulator"))
                        #endif
                        #endif
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 44)
                    .padding(.bottom, 28)
                }

                stepIndicator
                    .padding(.top, 10)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 26)
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
                message = "\(sessionStore.selectionCount) selections protected."
            }
        }
        .animation(.easeInOut(duration: 0.28), value: currentStep.rawValue)
    }

    @ViewBuilder
    private var content: some View {
        switch currentStep {
        case .promise:
            introStep
        case .goal:
            optionStep(
                title: "What do you want back?",
                body: "Blanked adapts your first block around the habit you want to change.",
                options: goalOptions,
                selection: onboardingGoal,
                onSelect: selectGoal
            )
        case .weakMoment:
            optionStep(
                title: "When is it hardest?",
                body: "This helps Blanked frame your first plan and later AI reports.",
                options: weakMomentOptions,
                selection: weakMoment,
                onSelect: selectWeakMoment
            )
        case .permission:
            stepContent(
                eyebrow: "Required by iOS",
                title: "Allow Screen Time.",
                body: screenTimeDescription,
                statusText: screenTimeBlocker.authorizationStatus == .approved ? "Screen Time ready" : nil,
                primaryTitle: screenTimeBlocker.authorizationStatus == .approved ? "Continue" : "Allow Screen Time",
                secondaryTitle: "Back",
                primaryAction: authorizeScreenTime,
                secondaryAction: { goBack() }
            )
        case .apps:
            stepContent(
                eyebrow: "Your blocklist",
                title: sessionStore.hasSelectedApps ? "Your apps are protected." : "Choose what to block.",
                body: sessionStore.hasSelectedApps
                    ? "\(sessionStore.selectionCount) apps, categories, or websites are ready in \(sessionStore.currentMode.name)."
                    : "Pick the apps, categories, or websites that usually steal your time.",
                statusText: sessionStore.hasSelectedApps ? "\(sessionStore.selectionCount) selected" : nil,
                primaryTitle: sessionStore.hasSelectedApps ? "Continue" : "Select apps",
                secondaryTitle: sessionStore.hasSelectedApps ? "Edit selection" : "Back",
                primaryAction: selectAppsOrContinue,
                secondaryAction: {
                    if sessionStore.hasSelectedApps {
                        showingPicker = true
                    } else {
                        goBack()
                    }
                }
            )
        case .firstBlock:
            stepContent(
                eyebrow: "First block",
                title: "Start with 30 minutes.",
                body: "Blanked will shield your selected apps now. If you need to stop early, use Emergency Unlock.",
                statusText: onboardingGoal.isEmpty ? nil : onboardingGoal,
                primaryTitle: "Start first block",
                secondaryTitle: "Go to Home",
                primaryAction: startFirstBlock,
                secondaryAction: finishWithoutStarting
            )
        }
    }

    private var introStep: some View {
        VStack(spacing: 20) {
            OnboardingMark()
                .padding(.bottom, 8)

            Text("Reclaim your time.")
                .font(.blankInter(size: 38, weight: .medium, relativeTo: .largeTitle))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            Text("Blanked blocks distracting apps when you need distance, then shows you where your attention slips.")
                .font(.blankInter(size: 16, relativeTo: .body))
                .foregroundStyle(BlankColors.mutedInk)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 342)

            VStack(spacing: 10) {
                OnboardingBenefit(icon: "lock.shield", title: "Block apps with Screen Time")
                OnboardingBenefit(icon: "bolt.heart", title: "Use emergency unlock only when needed")
                OnboardingBenefit(icon: "chart.line.uptrend.xyaxis", title: "Learn your weak moments")
            }
            .padding(.top, 8)

            Button("Get started") {
                goForward()
            }
            .buttonStyle(BlankPrimaryButtonStyle())
            .frame(width: onboardingButtonWidth(for: "Get started"))
            .padding(.top, 10)
        }
    }

    private func optionStep(
        title: String,
        body: String,
        options: [OnboardingOption],
        selection: String,
        onSelect: @escaping (OnboardingOption) -> Void
    ) -> some View {
        VStack(spacing: 16) {
            OnboardingHeader(eyebrow: "Personalize", title: title, body: body)

            VStack(spacing: 10) {
                ForEach(options) { option in
                    OnboardingOptionRow(
                        option: option,
                        isSelected: selection == option.title
                    ) {
                        onSelect(option)
                    }
                }
            }
            .frame(maxWidth: 354)
            .padding(.top, 4)

            Button(selection.isEmpty ? "Continue" : "Next") {
                if selection.isEmpty {
                    onSelect(options[0])
                } else {
                    goForward()
                }
            }
            .buttonStyle(BlankPrimaryButtonStyle())
            .frame(width: onboardingButtonWidth(for: selection.isEmpty ? "Continue" : "Next"))
            .padding(.top, 8)

            Button("Back") {
                goBack()
            }
            .buttonStyle(BlankSecondaryButtonStyle())
            .frame(width: onboardingButtonWidth(for: "Back"))
        }
    }

    private func stepContent(
        eyebrow: String,
        title: String,
        body: String,
        statusText: String? = nil,
        primaryTitle: String,
        secondaryTitle: String?,
        primaryAction: @escaping () -> Void,
        secondaryAction: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 15) {
            OnboardingHeader(eyebrow: eyebrow, title: title, body: body)

            if let statusText {
                StatusPill(text: statusText)
                    .padding(.top, 8)
            }

            Button(primaryTitle, action: primaryAction)
                .buttonStyle(BlankPrimaryButtonStyle())
                .frame(width: onboardingButtonWidth(for: primaryTitle))
                .padding(.top, 12)

            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(BlankSecondaryButtonStyle())
                    .frame(width: onboardingButtonWidth(for: secondaryTitle))
            }
        }
    }

    private var screenTimeDescription: String {
        if screenTimeBlocker.authorizationStatus == .approved {
            return "Screen Time is enabled. Blanked can now apply shields to the apps you choose."
        }
        return "Apple requires this permission before Blanked can block apps. You choose the apps; Blanked cannot see private usage details."
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

    private func StatusPill(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.blankInter(size: 13, weight: .semibold, relativeTo: .caption))
            Text(text)
                .font(.blankInter(size: 15, weight: .semibold, relativeTo: .subheadline))
        }
        .foregroundStyle(BlankColors.ink)
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background {
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(Color.white.opacity(0.34))
                Capsule().stroke(BlankColors.glassBorder, lineWidth: 1)
            }
        }
    }

    private func selectGoal(_ option: OnboardingOption) {
        onboardingGoal = option.title
        goForward()
    }

    private func selectWeakMoment(_ option: OnboardingOption) {
        weakMoment = option.title
        goForward()
    }

    private func authorizeScreenTime() {
        if screenTimeBlocker.authorizationStatus == .approved {
            goForward()
            message = nil
            return
        }

        Task {
            if await screenTimeBlocker.requestAuthorization() {
                goForward()
                message = nil
            } else {
                let status = "iOS status: \(screenTimeBlocker.authorizationStatusLabel)."
                if let lastErrorMessage = screenTimeBlocker.lastErrorMessage {
                    message = "\(lastErrorMessage) \(status)"
                } else {
                    message = "Screen Time is still pending. \(status)"
                }
            }
        }
    }

    private func refreshScreenTimeAndContinueIfApproved() async {
        await screenTimeBlocker.refreshAuthorizationStatusUntilSettled()
        if screenTimeBlocker.authorizationStatus == .approved, currentStep == .permission {
            currentStep = .apps
            message = nil
        }
    }

    private func selectAppsOrContinue() {
        if sessionStore.hasSelectedApps {
            goForward()
        } else {
            showingPicker = true
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
            message = "Choose at least one app, category, or website first."
        default:
            sessionStore.finishSetup()
        }
    }

    private func finishWithoutStarting() {
        screenTimeBlocker.updateSelection(sessionStore.selection, isBlankActive: sessionStore.isBlankActive)
        sessionStore.finishSetup()
    }

    private func goForward() {
        guard let next = OnboardingStep(rawValue: min(currentStep.rawValue + 1, OnboardingStep.allCases.count - 1)) else { return }
        currentStep = next
        message = nil
    }

    private func goBack() {
        guard let previous = OnboardingStep(rawValue: max(currentStep.rawValue - 1, 0)) else { return }
        currentStep = previous
        message = nil
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

private struct OnboardingHeader: View {
    let eyebrow: String
    let title: String
    let bodyText: String

    init(eyebrow: String, title: String, body: String) {
        self.eyebrow = eyebrow
        self.title = title
        self.bodyText = body
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(eyebrow.uppercased())
                .font(.blankInter(size: 12, weight: .semibold, relativeTo: .caption))
                .foregroundStyle(BlankColors.mutedInk)

            Text(title)
                .font(.blankInter(size: 34, weight: .medium, relativeTo: .largeTitle))
                .multilineTextAlignment(.center)
                .lineSpacing(1)
                .lineLimit(3)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: 354)

            Text(bodyText)
                .font(.blankInter(size: 16, relativeTo: .body))
                .foregroundStyle(BlankColors.mutedInk)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 342)
                .padding(.top, 2)
        }
    }
}

private struct OnboardingMark: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
            Circle()
                .fill(Color.white.opacity(0.32))
            Circle()
                .stroke(BlankColors.glassBorder, lineWidth: 1)
            Image(systemName: "hourglass")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(BlankColors.ink)
        }
        .frame(width: 68, height: 68)
        .shadow(color: BlankColors.ink.opacity(0.06), radius: 14, y: 8)
    }
}

private struct OnboardingBenefit: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(BlankColors.ink)
            Text(title)
                .font(.blankInter(size: 15, weight: .medium, relativeTo: .subheadline))
                .foregroundStyle(BlankColors.ink)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: 342)
        .frame(height: 52)
        .blankGlassCard(cornerRadius: 18, tintOpacity: 0.28)
    }
}

private struct OnboardingOptionRow: View {
    let option: OnboardingOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: option.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(BlankColors.ink)
                    .frame(width: 34, height: 34)
                    .background {
                        Circle()
                            .fill(Color.white.opacity(isSelected ? 0.58 : 0.30))
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(option.title)
                        .font(.blankInter(size: 16, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(BlankColors.ink)
                    Text(option.subtitle)
                        .font(.blankInter(size: 13, relativeTo: .footnote))
                        .foregroundStyle(BlankColors.mutedInk)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? BlankColors.ink : BlankColors.mutedInk)
            }
            .padding(.horizontal, 15)
            .frame(height: 72)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .blankGlassCard(cornerRadius: 20, tintOpacity: isSelected ? 0.42 : 0.28)
    }
}
