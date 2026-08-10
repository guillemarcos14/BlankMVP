import FamilyControls
import SwiftUI
import UserNotifications

private enum OnboardingStep: Int, CaseIterable {
    case awareness
    case lifetime
    case dopamine
    case name
    case dailyUse
    case result
    case recovery
    case account
    case notifications
    case commitment
    case trial
    case permission
    case apps
    case firstBlock
}

private enum OnboardingPlan: String {
    case annual
    case monthly
}

struct SetupView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var screenTimeBlocker: ScreenTimeBlocker
    @EnvironmentObject private var purchaseStore: StoreKitPurchaseStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var currentStep: OnboardingStep = .awareness
    @State private var showingPicker = false
    @State private var message: String?
    @State private var dailyHours = 4.5
    @State private var selectedPlan: OnboardingPlan = .annual
    @State private var commitmentComplete = false
    @State private var notificationStatus = "Off"

    @AppStorage("blankOnboardingName", store: BlankSharedState.defaults) private var name = ""
    @AppStorage("blankWeeklyAIGoal", store: BlankSharedState.defaults) private var onboardingGoal = ""
    @AppStorage("blankOnboardingWeakMoment", store: BlankSharedState.defaults) private var weakMoment = ""
    @AppStorage("blankOnboardingDailyHours", store: BlankSharedState.defaults) private var storedDailyHours = 4.5
    @AppStorage("blankOnboardingTrialStarted", store: BlankSharedState.defaults) private var trialStarted = false

    var body: some View {
        ZStack {
            BlankOnboardingBackground()

            VStack(spacing: 0) {
                HStack {
                    if currentStep != .awareness {
                        Button {
                            goBack()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.86))
                                .frame(width: 42, height: 42)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back")
                    } else {
                        Color.clear.frame(width: 42, height: 42)
                    }

                    Spacer()
                }
                .padding(.top, 2)

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
                    .padding(.top, 34)
                    .padding(.bottom, 28)
                }

                stepIndicator
                    .padding(.top, 10)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Color.white)
        .familyActivityPicker(isPresented: $showingPicker, selection: $sessionStore.selection)
        .task {
            dailyHours = storedDailyHours
            await purchaseStore.loadProducts()
            await refreshScreenTimeAndContinueIfApproved()
            await refreshNotificationStatus()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            Task {
                await refreshScreenTimeAndContinueIfApproved()
                await refreshNotificationStatus()
            }
        }
        .onChange(of: sessionStore.selection) { newSelection in
            screenTimeBlocker.updateSelection(newSelection, isBlankActive: sessionStore.isBlankActive)
            if currentStep == .apps, sessionStore.hasSelectedApps {
                message = "\(sessionStore.selectionCount) selections protected."
            }
        }
        .animation(.easeInOut(duration: 0.26), value: currentStep.rawValue)
    }

    @ViewBuilder
    private var content: some View {
        switch currentStep {
        case .awareness:
            simpleStatement(
                icon: "iphone.slash",
                title: "You are losing more time than you think.",
                body: nil,
                button: "Continue"
            )
        case .lifetime:
            simpleStatement(
                icon: "hourglass",
                title: "The average person loses",
                body: "13 years",
                bodyColor: BlankColors.red,
                button: "Continue"
            )
        case .dopamine:
            simpleStatement(
                icon: "brain.head.profile",
                title: "Apps are not neutral.",
                body: "They are training your attention.",
                bodyColor: BlankColors.red,
                button: "Continue"
            )
        case .name:
            nameStep
        case .dailyUse:
            dailyUseStep
        case .result:
            resultStep
        case .recovery:
            simpleStatement(
                icon: "target",
                title: "Blanked can help you recover",
                body: "+\(recoveredYears) years",
                bodyColor: Color(red: 0.278, green: 0.780, blue: 0.506),
                button: "I want those years back"
            )
        case .account:
            accountStep
        case .notifications:
            notificationsStep
        case .commitment:
            commitmentStep
        case .trial:
            trialStep
        case .permission:
            permissionStep
        case .apps:
            appsStep
        case .firstBlock:
            firstBlockStep
        }
    }

    private func simpleStatement(
        icon: String,
        title: String,
        body: String?,
        bodyColor: Color = BlankColors.ink,
        button: String
    ) -> some View {
        VStack(spacing: 22) {
            Spacer(minLength: 100)

            Image(systemName: icon)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.66))

            Text(title)
                .font(.blankInter(size: 25, weight: .semibold, relativeTo: .title))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 342)

            if let body {
                Text(body)
                    .font(.blankInter(size: 42, weight: .semibold, relativeTo: .largeTitle))
                    .foregroundStyle(bodyColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.74)
                    .frame(maxWidth: 342)
            }

            Spacer(minLength: 88)

            Button(button) {
                goForward()
            }
            .buttonStyle(BlankPrimaryButtonStyle(light: true))
            .frame(width: onboardingButtonWidth(for: button))
        }
    }

    private var nameStep: some View {
        VStack(spacing: 20) {
            OnboardingHeader(
                eyebrow: "Your result",
                title: "Let's calculate how much life your phone is taking.",
                body: "What should Blanked call you?"
            )

            TextField("Your name", text: $name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .font(.blankInter(size: 18, weight: .medium, relativeTo: .body))
                .foregroundStyle(BlankColors.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .frame(height: 54)
                .blankGlassCard(cornerRadius: 18, tintOpacity: 0.34)
                .frame(maxWidth: 314)
                .padding(.top, 8)

            Button(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Continue" : "Calculate") {
                if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    name = "You"
                }
                goForward()
            }
            .buttonStyle(BlankPrimaryButtonStyle(light: true))
            .frame(width: onboardingButtonWidth(for: "Calculate"))
        }
    }

    private var dailyUseStep: some View {
        VStack(spacing: 22) {
            OnboardingHeader(
                eyebrow: "Daily use",
                title: "How much time do you spend on your phone daily?",
                body: "Use your real average. This only takes a few seconds."
            )

            VStack(spacing: 18) {
                Slider(value: $dailyHours, in: 1...9, step: 0.5)
                    .tint(BlankColors.ink)
                    .onChange(of: dailyHours) { value in
                        storedDailyHours = value
                    }

                Text("\(formattedHours(dailyHours)) / day")
                    .font(.blankInter(size: 38, weight: .semibold, relativeTo: .largeTitle))
                    .foregroundStyle(BlankColors.red)
            }
            .frame(maxWidth: 342)
            .padding(.top, 12)

            Button("Calculate time lost") {
                storedDailyHours = dailyHours
                goForward()
            }
            .buttonStyle(BlankPrimaryButtonStyle(light: true))
            .frame(width: onboardingButtonWidth(for: "Calculate time lost"))
        }
    }

    private var resultStep: some View {
        VStack(spacing: 22) {
            OnboardingHeader(
                eyebrow: "Your result",
                title: "This is your lost time projection.",
                body: ""
            )

            VStack(spacing: 14) {
                Text("Careful")
                    .font(.blankInter(size: 15, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(Capsule().fill(BlankColors.red))

                Text("\(displayName), if nothing changes, you could lose")
                    .font(.blankInter(size: 15, relativeTo: .subheadline))
                    .foregroundStyle(BlankColors.mutedInk)
                    .multilineTextAlignment(.center)

                Text("\(lostDaysThisYear) days")
                    .font(.blankInter(size: 38, weight: .semibold, relativeTo: .largeTitle))
                    .foregroundStyle(BlankColors.red)

                Text("in the rest of 2026")
                    .font(.blankInter(size: 14, relativeTo: .footnote))
                    .foregroundStyle(BlankColors.mutedInk)

                Divider().opacity(0.28)

                Text("\(lostLifetimeYears) years")
                    .font(.blankInter(size: 34, weight: .semibold, relativeTo: .title))
                    .foregroundStyle(BlankColors.red)

                Text("over a lifetime")
                    .font(.blankInter(size: 14, relativeTo: .footnote))
                    .foregroundStyle(BlankColors.mutedInk)
            }
            .padding(20)
            .frame(maxWidth: 342)
            .blankGlassCard(cornerRadius: 20, tintOpacity: 0.30)

            Button("Continue") {
                onboardingGoal = "Recover control from distracting apps"
                weakMoment = "When scrolling takes over"
                goForward()
            }
            .buttonStyle(BlankPrimaryButtonStyle(light: true))
            .frame(width: onboardingButtonWidth(for: "Continue"))
        }
    }

    private var accountStep: some View {
        VStack(spacing: 16) {
            OnboardingHeader(
                eyebrow: "Start",
                title: "Create your Blanked account.",
                body: "Keep your progress and trial tied to you. You can continue without sync for now."
            )

            VStack(spacing: 10) {
                SocialLoginButton(systemName: "apple.logo", title: "Continue with Apple") {
                    goForward()
                }

                SocialLoginButton(systemName: "g.circle.fill", title: "Continue with Google") {
                    goForward()
                }
            }
            .frame(maxWidth: 342)

            Button("Continue without account") {
                goForward()
            }
            .font(.blankInter(size: 14, weight: .medium, relativeTo: .footnote))
            .foregroundStyle(Color.white.opacity(0.72))
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    private var notificationsStep: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.black.opacity(0.18))
                    .frame(width: 250, height: 178)
                    .overlay(alignment: .top) {
                        HStack(spacing: 10) {
                            Image(systemName: "target")
                                .font(.system(size: 20, weight: .semibold))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Blanked")
                                    .font(.blankInter(size: 13, weight: .semibold, relativeTo: .caption))
                                Text("You are entering your weak hour. Start a block.")
                                    .font(.blankInter(size: 12, relativeTo: .caption))
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Text("now")
                                .font(.blankInter(size: 11, relativeTo: .caption2))
                                .foregroundStyle(BlankColors.mutedInk)
                        }
                        .foregroundStyle(BlankColors.ink)
                        .padding(12)
                        .frame(width: 292)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.84))
                        }
                        .offset(y: 26)
                    }
            }

            OnboardingHeader(
                eyebrow: "Notifications",
                title: "Can we help you catch the moment before you scroll?",
                body: "Blanked can remind you before weak hours, trial renewal, and block prompts."
            )

            StatusPill(text: "Notifications: \(notificationStatus)")

            Button("Allow notifications") {
                requestNotifications()
            }
            .buttonStyle(BlankPrimaryButtonStyle(light: true))
            .frame(width: onboardingButtonWidth(for: "Allow notifications"))

            Button("Not now") {
                goForward()
            }
            .buttonStyle(BlankSecondaryButtonStyle())
            .frame(width: 184)
        }
    }

    private var commitmentStep: some View {
        VStack(spacing: 24) {
            OnboardingHeader(
                eyebrow: "Commitment",
                title: "I want to take control of my life.",
                body: "Hold the button to continue."
            )

            Button {
                if commitmentComplete {
                    goForward()
                }
            } label: {
                Image(systemName: commitmentComplete ? "checkmark" : "arrow.right")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(BlankColors.ink)
                    .frame(width: 74, height: 74)
                    .background(Circle().fill(Color.white.opacity(0.82)))
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 1.2).onEnded { _ in
                    commitmentComplete = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        goForward()
                    }
                }
            )

            Text(commitmentComplete ? "Done" : "Keep holding")
                .font(.blankInter(size: 13, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(BlankColors.mutedInk)
        }
    }

    private var trialStep: some View {
        VStack(spacing: 18) {
            OnboardingHeader(
                eyebrow: "Free trial",
                title: "Start your free trial.",
                body: "Full access today. Cancel any time before the trial ends."
            )

            HStack(spacing: 10) {
                TrialComparisonCard(title: "Without Blanked", main: formattedHours(dailyHours), caption: "daily screen time", tallBars: true)
                TrialComparisonCard(title: "With Blanked", main: formattedHours(max(1.0, dailyHours * 0.38)), caption: "target daily use", tallBars: false)
            }
            .frame(maxWidth: 342)

            VStack(spacing: 12) {
                TrialTimelineRow(icon: "lock.open", title: "Today", detail: "Unlock Blanked and set your first block.")
                TrialTimelineRow(icon: "bell", title: "In 2 days", detail: "We remind you before the trial ends.")
            }
            .frame(maxWidth: 342)

            HStack(spacing: 10) {
                PlanButton(
                    title: "Monthly",
                    price: purchaseStore.priceText(for: StoreKitPurchaseStore.monthlyProductId, fallback: "2.99 EUR"),
                    detail: "35.88 EUR/year",
                    selected: selectedPlan == .monthly
                ) {
                    selectedPlan = .monthly
                }
                PlanButton(
                    title: "Annual",
                    price: purchaseStore.priceText(for: StoreKitPurchaseStore.annualProductId, fallback: "19.99 EUR"),
                    detail: "per year",
                    selected: selectedPlan == .annual
                ) {
                    selectedPlan = .annual
                }
            }
            .frame(maxWidth: 342)

            Button {
                purchaseSelectedPlan()
            } label: {
                if purchaseStore.isPurchasing || purchaseStore.isLoading {
                    ProgressView()
                        .tint(BlankColors.ink)
                } else {
                    Text("Start my 3-day FREE trial")
                }
            }
            .buttonStyle(BlankPrimaryButtonStyle(light: true))
            .frame(width: onboardingButtonWidth(for: "Start my 3-day FREE trial"))

            Button("Restore purchases") {
                Task {
                    await purchaseStore.restorePurchases()
                    if purchaseStore.hasEntitlement {
                        trialStarted = true
                        goForward()
                    }
                }
            }
            .buttonStyle(BlankSecondaryButtonStyle())
            .frame(width: 224)

            Text("3 days free. Then \(selectedPlan == .annual ? "19.99 EUR/year" : "2.99 EUR/month"). Auto-renewable. Cancel any time in App Store settings. Terms and Privacy apply.")
                .font(.blankInter(size: 11, relativeTo: .caption2))
                .foregroundStyle(BlankColors.mutedInk)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 320)

            if let purchaseMessage = purchaseStore.message {
                Text(purchaseMessage)
                    .font(.blankInter(size: 12, relativeTo: .caption))
                    .foregroundStyle(BlankColors.mutedInk)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
    }

    private var permissionStep: some View {
        stepContent(
            eyebrow: "Required by iOS",
            title: "Allow Screen Time.",
            body: screenTimeDescription,
            statusText: screenTimeBlocker.authorizationStatus == .approved ? "Screen Time ready" : nil,
            primaryTitle: screenTimeBlocker.authorizationStatus == .approved ? "Continue" : "Allow Screen Time",
            secondaryTitle: nil,
            primaryAction: authorizeScreenTime,
            secondaryAction: nil
        )
    }

    private var appsStep: some View {
        stepContent(
            eyebrow: "Your blocklist",
            title: sessionStore.hasSelectedApps ? "Your apps are protected." : "Choose what to block.",
            body: sessionStore.hasSelectedApps
                ? "\(sessionStore.selectionCount) apps, categories, or websites are ready in \(sessionStore.currentMode.name)."
                : "Pick the apps, categories, or websites that usually steal your time.",
            statusText: sessionStore.hasSelectedApps ? "\(sessionStore.selectionCount) selected" : nil,
            primaryTitle: sessionStore.hasSelectedApps ? "Continue" : "Select apps",
            secondaryTitle: sessionStore.hasSelectedApps ? "Edit selection" : nil,
            primaryAction: selectAppsOrContinue,
            secondaryAction: {
                if sessionStore.hasSelectedApps {
                    showingPicker = true
                }
            }
        )
    }

    private var firstBlockStep: some View {
        stepContent(
            eyebrow: "First block",
            title: "Start with 30 minutes.",
            body: "Blanked will shield your selected apps now. If you need to stop early, use Emergency Unlock.",
            statusText: trialStarted ? "Trial started" : nil,
            primaryTitle: "Start first block",
            secondaryTitle: "Go to Home",
            primaryAction: startFirstBlock,
            secondaryAction: finishWithoutStarting
        )
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
                .buttonStyle(BlankPrimaryButtonStyle(light: true))
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
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(step.rawValue <= currentStep.rawValue ? BlankColors.ink : BlankColors.line)
                    .frame(width: step == currentStep ? 18 : 6, height: 6)
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

    private var displayName: String {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanName.isEmpty ? "You" : cleanName
    }

    private var lostDaysThisYear: Int {
        let calendar = Calendar.current
        let now = Date()
        let end = calendar.date(from: DateComponents(year: 2027, month: 1, day: 1)) ?? now
        let days = max(1, calendar.dateComponents([.day], from: now, to: end).day ?? 1)
        return max(1, Int((Double(days) * dailyHours / 24.0).rounded()))
    }

    private var lostLifetimeYears: Int {
        max(1, Int((dailyHours * 75.0 / 24.0).rounded()))
    }

    private var recoveredYears: Int {
        max(1, Int((Double(lostLifetimeYears) * 0.38).rounded()))
    }

    private func formattedHours(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))h"
        }
        return String(format: "%.1fh", value)
    }

    private func requestNotifications() {
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
                notificationStatus = granted ? "On" : "Off"
                goForward()
            } catch {
                notificationStatus = "Off"
                message = "Notifications were not enabled. You can turn them on later."
            }
        }
    }

    private func purchaseSelectedPlan() {
        let productId = selectedPlan == .annual
            ? StoreKitPurchaseStore.annualProductId
            : StoreKitPurchaseStore.monthlyProductId

        Task {
            if await purchaseStore.purchase(productId: productId) {
                trialStarted = true
                goForward()
            }
        }
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationStatus = "On"
        case .denied:
            notificationStatus = "Off"
        case .notDetermined:
            notificationStatus = "Off"
        @unknown default:
            notificationStatus = "Off"
        }
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
        let estimated = CGFloat(title.count) * 8.2 + 66
        return min(max(estimated, 184), 316)
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
                .foregroundStyle(Color.white.opacity(0.58))

            Text(title)
                .font(.blankInter(size: 31, weight: .medium, relativeTo: .largeTitle))
                .multilineTextAlignment(.center)
                .lineSpacing(1)
                .lineLimit(4)
                .minimumScaleFactor(0.76)
                .frame(maxWidth: 354)

            if !bodyText.isEmpty {
                Text(bodyText)
                    .font(.blankInter(size: 16, relativeTo: .body))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 342)
                    .padding(.top, 2)
            }
        }
    }
}

private struct BlankOnboardingBackground: View {
    var body: some View {
        ZStack {
            BlankAtmosphericBackground(dimmed: true)
            Color.black.opacity(0.58).ignoresSafeArea()
            LinearGradient(
                colors: [
                    Color.white.opacity(0.05),
                    BlankColors.airBlue.opacity(0.08),
                    Color.black.opacity(0.32)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

private struct SocialLoginButton: View {
    let systemName: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemName)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.blankInter(size: 15, weight: .semibold, relativeTo: .subheadline))
            }
            .foregroundStyle(BlankColors.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.88))
            }
        }
        .buttonStyle(.plain)
    }
}

private struct TrialComparisonCard: View {
    let title: String
    let main: String
    let caption: String
    let tallBars: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.blankInter(size: 13, weight: .semibold, relativeTo: .caption))
            VStack(alignment: .leading, spacing: 2) {
                Text(main)
                    .font(.blankInter(size: 22, weight: .semibold, relativeTo: .title3))
                Text(caption)
                    .font(.blankInter(size: 11, relativeTo: .caption2))
                    .foregroundStyle(BlankColors.mutedInk)
            }
            HStack(alignment: .bottom, spacing: 7) {
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(index == 2 ? BlankColors.airBlue : BlankColors.ink.opacity(0.28))
                        .frame(width: 18, height: tallBars ? CGFloat(34 + index * 6) : CGFloat(10 + index * 2))
                }
            }
        }
        .foregroundStyle(BlankColors.ink)
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
        .blankGlassCard(cornerRadius: 16, tintOpacity: 0.30)
    }
}

private struct TrialTimelineRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 30, height: 30)
                .foregroundStyle(BlankColors.ink)
                .background(Circle().fill(Color.white.opacity(0.64)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.blankInter(size: 15, weight: .semibold, relativeTo: .subheadline))
                Text(detail)
                    .font(.blankInter(size: 12, relativeTo: .caption))
                    .foregroundStyle(BlankColors.mutedInk)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .frame(height: 58)
        .blankGlassCard(cornerRadius: 16, tintOpacity: 0.26)
    }
}

private struct PlanButton: View {
    let title: String
    let price: String
    let detail: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title)
                        .font(.blankInter(size: 13, weight: .semibold, relativeTo: .caption))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(price)
                    .font(.blankInter(size: 17, weight: .semibold, relativeTo: .headline))
                Text(detail)
                    .font(.blankInter(size: 11, relativeTo: .caption2))
                    .foregroundStyle(BlankColors.mutedInk)
            }
            .foregroundStyle(BlankColors.ink)
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .blankGlassCard(cornerRadius: 16, tintOpacity: selected ? 0.48 : 0.26)
        }
        .buttonStyle(.plain)
    }
}
