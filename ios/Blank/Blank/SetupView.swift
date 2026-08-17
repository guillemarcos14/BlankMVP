import FamilyControls
import Foundation
import SwiftUI
import UIKit
import UserNotifications

private enum OnboardingStep: Int, CaseIterable {
    case awareness
    case lifetime
    case dopamine
    case name
    case goal
    case age
    case profile
    case dailyUse
    case result
    case recovery
    case commitment
    case trial
    case permission
    case notifications
    case apps
}

private enum OnboardingPlan: String {
    case annual
    case monthly
}

private enum BlankLegalDocument: Identifiable {
    case termsOfUse
    case privacyPolicy

    var id: String {
        title
    }

    var title: String {
        switch self {
        case .termsOfUse:
            return "Terms of Use"
        case .privacyPolicy:
            return "Privacy Policy"
        }
    }

    var updatedAt: String {
        "Last updated: August 17, 2026"
    }
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
    @State private var commitmentSeconds = 0
    @State private var commitmentTimer: Timer?
    @State private var isCommitmentPressing = false
    @State private var notificationStatus = "Off"
    @State private var lifetimeRingProgress = 0.0
    @State private var lifetimeYears = 0
    @State private var animatedLostDays = 0
    @State private var animatedLostYears = 0
    @State private var animatedRecoveredYears = 0
    @State private var onboardingDataConsent = false
    @State private var presentedLegalDocument: BlankLegalDocument?

    @AppStorage("blankOnboardingName", store: BlankSharedState.defaults) private var name = ""
    @AppStorage("blankWeeklyAIGoal", store: BlankSharedState.defaults) private var onboardingGoal = ""
    @AppStorage("blankOnboardingWeakMoment", store: BlankSharedState.defaults) private var weakMoment = ""
    @AppStorage("blankOnboardingGoal", store: BlankSharedState.defaults) private var selectedOnboardingGoal = ""
    @AppStorage("blankOnboardingAgeRange", store: BlankSharedState.defaults) private var selectedAgeRange = ""
    @AppStorage("blankOnboardingProfile", store: BlankSharedState.defaults) private var selectedProfile = ""
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

                GeometryReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 22) {
                            content
                                .id(currentStep.rawValue)
                                .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .center)))
                                .frame(height: usesAnchoredPrimaryAction ? max(0, proxy.size.height - 96) : nil)

                            if let message {
                                Text(message)
                                    .font(.blankInter(size: 13, relativeTo: .footnote))
                                    .foregroundStyle(BlankColors.secondaryText)
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(2)
                                    .frame(maxWidth: 330)
                            }

                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 34)
                        .padding(.bottom, 28)
                    }
                }

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
        .onChange(of: currentStep) { step in
            if step == .lifetime {
                startLifetimeAnimation()
            }
        }
        .onChange(of: sessionStore.selection) { newSelection in
            screenTimeBlocker.updateSelection(newSelection, isBlankActive: sessionStore.isBlankActive)
            if currentStep == .apps, sessionStore.hasSelectedApps {
                message = "\(sessionStore.selectionCount) selections protected"
            }
        }
        .sheet(item: $presentedLegalDocument) { document in
            LegalDocumentView(document: document)
        }
        .animation(.easeInOut(duration: 0.26), value: currentStep.rawValue)
    }

    @ViewBuilder
    private var content: some View {
        switch currentStep {
        case .awareness:
            simpleStatement(
                title: "Your phone is taking more of your life than you think",
                body: "Let's see how much",
                bodySize: 18,
                bodyColor: Color.white.opacity(0.68),
                button: "Continue"
            )
        case .lifetime:
            lifetimeStep
        case .dopamine:
            dopamineStep
        case .name:
            nameStep
        case .goal:
            goalStep
        case .age:
            ageStep
        case .profile:
            profileStep
        case .dailyUse:
            dailyUseStep
        case .result:
            resultStep
        case .recovery:
            recoveryStep
        case .commitment:
            commitmentStep
        case .trial:
            trialStep
        case .permission:
            permissionStep
        case .notifications:
            notificationsStep
        case .apps:
            appsStep
        }
    }

    private func simpleStatement(
        title: String,
        body: String?,
        bodySize: CGFloat = 44,
        bodyColor: Color = BlankColors.ink,
        button: String
    ) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 96)

            Text(title)
                .font(.blankInter(size: 27, weight: .semibold, relativeTo: .title))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 342)

            if let body {
                Text(body)
                    .font(.blankInter(size: bodySize, weight: .semibold, relativeTo: .largeTitle))
                    .foregroundStyle(bodyColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.74)
                    .frame(maxWidth: 342)
            }

            Spacer(minLength: 28)

            Button(button) {
                goForward()
            }
            .buttonStyle(BlankPrimaryButtonStyle(light: true))
            .frame(width: onboardingButtonWidth(for: button))
        }
    }

    private var nameStep: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 116)

            Text("What should we call you?")
                .font(.blankInter(size: 31, weight: .medium, relativeTo: .largeTitle))
                .multilineTextAlignment(.center)
                .lineSpacing(1)
                .lineLimit(3)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: 342)

            TextField("Your name", text: $name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .font(.blankInter(size: 18, weight: .medium, relativeTo: .body))
                .foregroundStyle(BlankColors.ink)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 18)
                .frame(height: 54)
                .blankGlassCard(cornerRadius: 18, tintOpacity: 0.34)
                .frame(maxWidth: 314)
                .padding(.top, 2)

            Spacer(minLength: 28)

            Button("Continue") {
                if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    name = "You"
                }
                goForward()
            }
            .buttonStyle(BlankPrimaryButtonStyle(light: true))
            .frame(width: onboardingButtonWidth(for: "Continue"))
        }
        .frame(maxHeight: .infinity)
    }

    private var lifetimeStep: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 92)

            Text("The average person loses\nto their phone screen")
                .font(.blankInter(size: 27, weight: .semibold, relativeTo: .title))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 342)

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: 7)

                Circle()
                    .trim(from: 0, to: lifetimeRingProgress)
                    .stroke(
                        Color.white.opacity(0.72),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 5) {
                    Text("\(lifetimeYears) years")
                        .font(.blankInter(size: 35, weight: .semibold, relativeTo: .largeTitle))
                        .foregroundStyle(Color.white)

                    Text("Over a lifetime")
                        .font(.blankInter(size: 13, weight: .medium, relativeTo: .footnote))
                        .foregroundStyle(Color.white.opacity(0.54))
                }
            }
            .frame(width: 176, height: 176)
            .padding(.top, 6)
            .onAppear {
                startLifetimeAnimation()
            }

            Spacer(minLength: 28)

            Button("Continue") {
                goForward()
            }
            .buttonStyle(BlankPrimaryButtonStyle(light: true))
            .frame(width: onboardingButtonWidth(for: "Continue"))
        }
        .frame(maxHeight: .infinity)
    }

    private var dopamineStep: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 92)

            Text("Your feed is engineered")
                .font(.blankInter(size: 27, weight: .semibold, relativeTo: .title))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 342)

            Text("Studies compare its reward loop to c**aine. You've been drugged by algorithms")
                .font(.blankInter(size: 19, weight: .semibold, relativeTo: .title3))
                .foregroundStyle(Color.white.opacity(0.76))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 310)

            Spacer(minLength: 28)

            Button("Continue") {
                goForward()
            }
            .buttonStyle(BlankPrimaryButtonStyle(light: true))
            .frame(width: onboardingButtonWidth(for: "Continue"))
        }
        .frame(maxHeight: .infinity)
    }

    private var dailyUseStep: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 54)

            OnboardingHeader(
                eyebrow: "",
                title: "How much time do you spend on your phone daily?",
                body: "Use your real daily average"
            )

            VStack(spacing: 18) {
                Slider(value: $dailyHours, in: 1...9, step: 0.5)
                    .tint(BlankColors.ink)
                    .onChange(of: dailyHours) { value in
                        storedDailyHours = value
                    }

                Text("\(formattedHours(dailyHours)) / day")
                    .font(.blankInter(size: 38, weight: .semibold, relativeTo: .largeTitle))
                    .foregroundStyle(Color.white)
            }
            .frame(maxWidth: 342)
            .padding(.top, 12)

            Spacer(minLength: 28)

            Button("Calculate time lost") {
                storedDailyHours = dailyHours
                goForward()
            }
            .buttonStyle(BlankPrimaryButtonStyle(light: true))
            .frame(width: onboardingButtonWidth(for: "Calculate time lost"))
        }
        .frame(maxHeight: .infinity)
    }

    private var resultStep: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 54)

            OnboardingHeader(
                eyebrow: "",
                title: "This is what your phone could cost you",
                body: ""
            )

            VStack(spacing: 26) {
                ResultMetricView(
                    value: "\(animatedLostDays)",
                    unit: "days",
                    caption: "you won't get back this year"
                )

                ResultMetricView(
                    value: "\(animatedLostYears)",
                    unit: "years",
                    caption: "over a lifetime"
                )
            }
            .frame(maxWidth: 342)
            .padding(.top, 10)
            .onAppear {
                startResultCountAnimation()
            }

            Spacer(minLength: 28)

            Button("See what I can recover") {
                onboardingGoal = "Recover control from distracting apps"
                weakMoment = "When scrolling takes over"
                goForward()
            }
            .buttonStyle(BlankPrimaryButtonStyle(light: true))
            .frame(width: onboardingButtonWidth(for: "See what I can recover"))
        }
        .frame(maxHeight: .infinity)
    }

    private var recoveryStep: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 82)

            Text("Blanked can help you get that time back")
                .font(.blankInter(size: 27, weight: .semibold, relativeTo: .title))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 342)

            VStack(spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("+\(animatedRecoveredYears)")
                        .font(.blankInter(size: 50, weight: .semibold, relativeTo: .largeTitle))
                        .monospacedDigit()

                    Text("years")
                        .font(.blankInter(size: 24, weight: .semibold, relativeTo: .title3))
                        .foregroundStyle(BlankColors.airMist.opacity(0.86))
                }
                .foregroundStyle(BlankColors.airMist)
                .lineLimit(1)
                .minimumScaleFactor(0.74)

                Text("recovered over a lifetime")
                    .font(.blankInter(size: 15, relativeTo: .subheadline))
                    .foregroundStyle(Color.white.opacity(0.66))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 342)
            .onAppear {
                startRecoveryCountAnimation()
            }

            Spacer(minLength: 28)

            Button("Start recovering") {
                goForward()
            }
            .buttonStyle(BlankPrimaryButtonStyle(light: true))
            .frame(width: onboardingButtonWidth(for: "Start recovering"))
        }
        .frame(maxHeight: .infinity)
    }

    private var goalStep: some View {
        choiceStep(
            title: "What matters most to you?",
            options: [
                ("target", "Better focus"),
                ("moon.fill", "Better sleep"),
                ("person.2.fill", "Be more present"),
                ("brain.head.profile", "Improve mental health"),
                ("ellipsis", "Other")
            ],
            selection: selectedOnboardingGoal
        ) { selectedOnboardingGoal = $0 }
    }

    private var ageStep: some View {
        choiceStep(
            title: "How old are you?",
            options: [
                ("person.fill", "Under 18"),
                ("person.fill", "18-24"),
                ("person.fill", "25-34"),
                ("person.fill", "35-44"),
                ("person.fill", "45+")
            ],
            selection: selectedAgeRange
        ) { selectedAgeRange = $0 }
    }

    private var profileStep: some View {
        choiceStep(
            title: "What describes you best?",
            options: [
                ("laptopcomputer", "Technology"),
                ("lightbulb.fill", "Entrepreneur"),
                ("house.fill", "Remote"),
                ("chart.bar.fill", "Finance"),
                ("paintbrush.pointed.fill", "Creative"),
                ("graduationcap.fill", "Student"),
                ("heart.fill", "Caregiver")
            ],
            selection: selectedProfile
        ) { selectedProfile = $0 }
    }

    private var notificationsStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Blanked")
                            .font(.blankInter(size: 13, weight: .semibold, relativeTo: .caption))
                        Spacer()
                        Text("now")
                            .font(.blankInter(size: 11, relativeTo: .caption2))
                            .foregroundStyle(BlankColors.mutedInk)
                    }
                    Text("Your scroll risk is rising")
                        .font(.blankInter(size: 12, relativeTo: .caption))
                        .lineLimit(2)
                }
                .foregroundStyle(BlankColors.ink)
                .padding(13)
                .frame(width: 276, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.86))
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 22) {
                OnboardingHeader(
                    eyebrow: "",
                    title: "Stay ahead of the scroll",
                    body: "Blanked can remind you before your weakest moments"
                )

                VStack(spacing: 15) {
                    Button("Enable reminders") {
                        requestNotifications()
                    }
                    .buttonStyle(BlankPrimaryButtonStyle(light: true))
                    .frame(width: onboardingButtonWidth(for: "Enable reminders"))

                    Button("Not now") {
                        goForward()
                    }
                    .font(.blankInter(size: 13, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(Color.white.opacity(0.56))
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    private var commitmentStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 24) {
                OnboardingHeader(
                    eyebrow: "",
                    title: "I'm ready to take back control",
                    body: commitmentComplete ? "Done" : "Hold for \(max(0, 3 - commitmentSeconds))s"
                )

                Image(systemName: commitmentComplete ? "checkmark" : "arrow.right")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(BlankColors.ink)
                    .frame(width: 74, height: 74)
                    .background(Circle().fill(Color.white.opacity(isCommitmentPressing ? 0.62 : 0.82)))
                    .scaleEffect(isCommitmentPressing ? 0.985 : 1)
                    .onLongPressGesture(
                        minimumDuration: 3,
                        maximumDistance: 48,
                        pressing: { isPressing in
                            isCommitmentPressing = isPressing
                            if isPressing {
                                startCommitmentHold()
                            } else if !commitmentComplete {
                                cancelCommitmentHold()
                            }
                        },
                        perform: {
                            completeCommitmentHold()
                        }
                    )

            }

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    private var trialStep: some View {
        VStack(spacing: 15) {
            OnboardingHeader(
                eyebrow: "",
                title: "Start taking back your time",
                body: "Block the apps that steal your focus. Try Blanked free for 3 days"
            )

            VStack(spacing: 9) {
                PlanButton(
                    title: "Annual",
                    price: purchaseStore.priceText(for: StoreKitPurchaseStore.annualProductId, fallback: "€19.99"),
                    detail: "3 days free, then billed yearly",
                    badge: "Best value",
                    selected: selectedPlan == .annual
                ) {
                    selectedPlan = .annual
                }

                PlanButton(
                    title: "Monthly",
                    price: purchaseStore.priceText(for: StoreKitPurchaseStore.monthlyProductId, fallback: "€2.99"),
                    detail: "3 days free, then billed monthly",
                    badge: nil,
                    selected: selectedPlan == .monthly
                ) {
                    selectedPlan = .monthly
                }
            }
            .frame(maxWidth: 342)

            Button {
                onboardingDataConsent.toggle()
                if onboardingDataConsent {
                    message = nil
                }
            } label: {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: onboardingDataConsent ? "checkmark.square.fill" : "square")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(onboardingDataConsent ? 0.88 : 0.52))
                        .frame(width: 18, height: 18)

                    Text(onboardingConsentText)
                        .font(.blankInter(size: 11, weight: .medium, relativeTo: .caption2))
                        .foregroundStyle(Color.white.opacity(0.58))
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)
                }
                .frame(maxWidth: 318, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Required onboarding data consent")

            Button {
                purchaseSelectedPlan()
            } label: {
                if purchaseStore.isPurchasing || purchaseStore.isLoading {
                    ProgressView()
                        .tint(BlankColors.ink)
                } else {
                    Text("Start free trial")
                }
            }
            .buttonStyle(BlankPrimaryButtonStyle(light: true))
            .frame(width: 222)

            Button("Restore purchases") {
                Task {
                    await purchaseStore.restorePurchases()
                    if purchaseStore.hasEntitlement {
                        trialStarted = true
                        goForward()
                    }
                }
            }
            .font(.blankInter(size: 13, weight: .semibold, relativeTo: .footnote))
            .foregroundStyle(Color.white.opacity(0.56))
            .buttonStyle(.plain)

            if isReviewDemoAccessAvailable {
                Button("Continue in demo mode") {
                    continueWithReviewDemoAccess()
                }
                .buttonStyle(BlankSecondaryButtonStyle())
                .frame(width: 236)
            }

            legalDisclosure

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
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 20) {
                OnboardingHeader(
                    eyebrow: "",
                    title: screenTimeBlocker.authorizationStatus == .approved ? "Screen Time is ready" : "Allow Screen Time",
                    body: screenTimeDescription
                )

                if screenTimeBlocker.authorizationStatus == .approved {
                    StatusPill(text: "Screen Time ready")
                }
            }

            Button(screenTimeBlocker.authorizationStatus == .approved ? "Continue" : "Allow Screen Time", action: authorizeScreenTime)
                .buttonStyle(BlankPrimaryButtonStyle(light: true))
                .frame(width: onboardingButtonWidth(for: screenTimeBlocker.authorizationStatus == .approved ? "Continue" : "Allow Screen Time"))
                .padding(.top, 42)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 22)
    }

    private var appsStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 20) {
                OnboardingHeader(
                    eyebrow: "",
                    title: sessionStore.hasSelectedApps ? "Your apps are protected" : "Choose what to block",
                    body: sessionStore.hasSelectedApps
                        ? "\(sessionStore.selectionCount) apps, categories, or websites are ready in \(sessionStore.currentMode.name)"
                        : "Pick the apps, categories, or websites that usually steal your time"
                )

                if sessionStore.hasSelectedApps {
                    StatusPill(text: "\(sessionStore.selectionCount) selected")
                }
            }

            VStack(spacing: 15) {
                Button(sessionStore.hasSelectedApps ? "Continue" : "Select apps", action: selectAppsOrContinue)
                    .buttonStyle(BlankPrimaryButtonStyle(light: true))
                    .frame(width: onboardingButtonWidth(for: sessionStore.hasSelectedApps ? "Continue" : "Select apps"))

                if sessionStore.hasSelectedApps {
                    Button("Edit selection") {
                        showingPicker = true
                    }
                    .font(.blankInter(size: 13, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(Color.white.opacity(0.56))
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 42)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 22)
    }

    private func choiceStep(
        title: String,
        options: [(icon: String, title: String)],
        selection: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(spacing: 22) {
            Spacer(minLength: 74)

            Text(title)
                .font(.blankInter(size: 30, weight: .medium, relativeTo: .largeTitle))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .lineLimit(3)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: 342)

            VStack(spacing: 11) {
                ForEach(options, id: \.title) { option in
                    OnboardingChoiceButton(
                        systemName: option.icon,
                        title: option.title,
                        selected: selection == option.title
                    ) {
                        onSelect(option.title)
                        goForward()
                    }
                }
            }
            .frame(maxWidth: 342)

            Spacer(minLength: 28)
        }
        .frame(maxHeight: .infinity)
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

            Spacer(minLength: 28)

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
        .frame(maxHeight: .infinity)
    }

    private var screenTimeDescription: String {
        if screenTimeBlocker.authorizationStatus == .approved {
            return "Blanked can now shield the apps you choose"
        }
        return "Apple requires this permission before Blanked can block distracting apps"
    }

    private var selectedPlanRenewalDisclosure: String {
        let productId = selectedPlan == .annual
            ? StoreKitPurchaseStore.annualProductId
            : StoreKitPurchaseStore.monthlyProductId
        let period = selectedPlan == .annual ? "year" : "month"
        let price = purchaseStore.priceText(for: productId, fallback: selectedPlan == .annual ? "€19.99" : "€2.99")
        return "3 days free. Then \(price)/\(period). Cancel anytime in App Store settings"
    }

    private var legalDisclosure: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                legalButton("Terms of Use", document: .termsOfUse)
                legalButton("Privacy Policy", document: .privacyPolicy)
            }

            Text("Full access today. \(selectedPlanRenewalDisclosure)")
                .multilineTextAlignment(.center)
                .font(.blankInter(size: 10, relativeTo: .caption2))
                .foregroundStyle(Color.white.opacity(0.42))
        }
        .lineSpacing(2)
        .frame(maxWidth: 320)
    }

    private func legalButton(_ title: String, document: BlankLegalDocument) -> some View {
        Button(title) {
            presentedLegalDocument = document
        }
        .font(.blankInter(size: 13, weight: .semibold, relativeTo: .caption))
        .foregroundStyle(Color.white.opacity(0.96))
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Capsule().fill(Color.white.opacity(0.10)))
        .overlay {
            Capsule().stroke(Color.white.opacity(0.28), lineWidth: 1)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens \(title) in the app")
    }

    private var onboardingConsentText: String {
        "I agree to the Privacy Policy and Terms"
    }

    private var isReviewDemoAccessAvailable: Bool {
        #if DEBUG
        #if targetEnvironment(simulator)
        return true
        #endif
        #endif

        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    private var usesAnchoredPrimaryAction: Bool {
        switch currentStep {
        case .awareness, .lifetime, .dopamine, .name, .dailyUse, .result, .recovery, .goal, .age, .profile, .commitment, .notifications, .permission, .apps:
            return true
        case .trial:
            return false
        }
    }

    private func StatusPill(text: String) -> some View {
        HStack {
            Text(text)
                .font(.blankInter(size: 14, weight: .semibold, relativeTo: .subheadline))
        }
        .foregroundStyle(Color.white.opacity(0.76))
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background {
            Capsule().fill(Color.white.opacity(0.10))
        }
    }

    private var lostDaysThisYear: Int {
        max(1, Int((365.0 * dailyHours / 24.0).rounded()))
    }

    private var lostLifetimeYears: Int {
        max(1, Int((dailyHours * 84.1 / 24.0).rounded()))
    }

    private var recoveredYears: Int {
        max(1, Int((dailyHours * 0.30 * 84.1 / 24.0).rounded()))
    }

    private func formattedHours(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))h"
        }
        return String(format: "%.1fh", value)
    }

    private func startResultCountAnimation() {
        let targetDays = lostDaysThisYear
        let targetYears = lostLifetimeYears
        animatedLostDays = 0
        animatedLostYears = 0

        Task { @MainActor in
            for frame in 1...42 {
                try? await Task.sleep(nanoseconds: 18_000_000)
                let progress = Double(frame) / 42.0
                let easedProgress = 1.0 - pow(1.0 - progress, 3.0)
                animatedLostDays = Int((Double(targetDays) * easedProgress).rounded())
                animatedLostYears = Int((Double(targetYears) * easedProgress).rounded())
            }
            animatedLostDays = targetDays
            animatedLostYears = targetYears
        }
    }

    private func startRecoveryCountAnimation() {
        let targetYears = recoveredYears
        animatedRecoveredYears = 0

        Task { @MainActor in
            for frame in 1...34 {
                try? await Task.sleep(nanoseconds: 20_000_000)
                let progress = Double(frame) / 34.0
                let easedProgress = 1.0 - pow(1.0 - progress, 3.0)
                animatedRecoveredYears = Int((Double(targetYears) * easedProgress).rounded())
            }
            animatedRecoveredYears = targetYears
        }
    }


    private func requestNotifications() {
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
                notificationStatus = granted ? "On" : "Off"
                goForward()
            } catch {
                notificationStatus = "Off"
                message = "Notifications were not enabled. You can turn them on later"
            }
        }
    }

    private func purchaseSelectedPlan() {
        guard onboardingDataConsent else {
            message = "Please agree to the Privacy Policy and Terms to continue"
            return
        }

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

    private func continueWithReviewDemoAccess() {
        message = nil
        goForward()
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

    private func startLifetimeAnimation() {
        lifetimeRingProgress = 0
        lifetimeYears = 0

        withAnimation(.easeOut(duration: 0.9)) {
            lifetimeRingProgress = 0.78
        }

        Task { @MainActor in
            for year in 1...13 {
                try? await Task.sleep(nanoseconds: 42_000_000)
                lifetimeYears = year
            }
        }
    }

    private func startCommitmentHold() {
        guard commitmentTimer == nil, !commitmentComplete else { return }
        commitmentSeconds = 0
        commitmentTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            commitmentSeconds += 1
            playCommitmentHaptic()
            if commitmentSeconds >= 3 {
                timer.invalidate()
                commitmentTimer = nil
            }
        }
    }

    private func cancelCommitmentHold() {
        isCommitmentPressing = false
        commitmentTimer?.invalidate()
        commitmentTimer = nil
        commitmentSeconds = 0
    }

    private func completeCommitmentHold() {
        isCommitmentPressing = false
        commitmentTimer?.invalidate()
        commitmentTimer = nil
        commitmentSeconds = 3
        commitmentComplete = true
        goForward()
    }

    private func playCommitmentHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
                let status = "iOS status: \(screenTimeBlocker.authorizationStatusLabel)"
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
            currentStep = .notifications
            message = nil
        }
    }

    private func selectAppsOrContinue() {
        if sessionStore.hasSelectedApps {
            screenTimeBlocker.updateSelection(sessionStore.selection, isBlankActive: sessionStore.isBlankActive)
            sessionStore.finishSetup()
        } else {
            showingPicker = true
        }
    }

    private func goForward() {
        guard let next = OnboardingStep(rawValue: min(currentStep.rawValue + 1, OnboardingStep.allCases.count - 1)) else { return }
        withAnimation(.easeInOut(duration: 0.38)) {
            currentStep = next
        }
        message = nil
    }

    private func goBack() {
        guard let previous = OnboardingStep(rawValue: max(currentStep.rawValue - 1, 0)) else { return }
        withAnimation(.easeInOut(duration: 0.38)) {
            currentStep = previous
        }
        message = nil
    }

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
            if !eyebrow.isEmpty {
                Text(eyebrow.uppercased())
                    .font(.blankInter(size: 12, weight: .semibold, relativeTo: .caption))
                    .foregroundStyle(Color.white.opacity(0.58))
            }

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

private struct ResultMetricView: View {
    let value: String
    let unit: String
    let caption: String

    var body: some View {
        VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value)
                    .font(.blankInter(size: 48, weight: .semibold, relativeTo: .largeTitle))
                    .monospacedDigit()

                Text(unit)
                    .font(.blankInter(size: 24, weight: .semibold, relativeTo: .title3))
                    .foregroundStyle(Color.white.opacity(0.82))
            }
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.74)

            Text(caption)
                .font(.blankInter(size: 15, relativeTo: .subheadline))
                .foregroundStyle(Color.white.opacity(0.66))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
    }
}

private struct OnboardingChoiceButton: View {
    let systemName: String
    let title: String
    let selected: Bool
    let action: () -> Void

    private let accent = BlankColors.airMist

    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 22)

                Text(title)
                    .font(.blankInter(size: 17, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(Color.white.opacity(0.92))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.14 : 0.075))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(selected ? BlankColors.airBlue.opacity(0.30) : Color.white.opacity(0.08), lineWidth: selected ? 1.2 : 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct BlankOnboardingBackground: View {
    var body: some View {
        ZStack {
            BlankAtmosphericBackground(dimmed: true)
            Color.black.opacity(0.38).ignoresSafeArea()
            LinearGradient(
                colors: [
                    Color.black.opacity(0.06),
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.46)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

private struct PlanButton: View {
    let title: String
    let price: String
    let detail: String
    let badge: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.blankInter(size: 13, weight: .semibold, relativeTo: .caption))
                        if let badge {
                            Text(badge)
                                .font(.blankInter(size: 10, weight: .semibold, relativeTo: .caption2))
                                .foregroundStyle(BlankColors.ink.opacity(0.72))
                                .padding(.horizontal, 7)
                                .frame(height: 20)
                                .background(Capsule().fill(BlankColors.airMist.opacity(0.58)))
                        }
                    }

                    Text(price)
                        .font(.blankInter(size: 19, weight: .semibold, relativeTo: .headline))

                    Text(detail)
                        .font(.blankInter(size: 11, relativeTo: .caption2))
                        .foregroundStyle(selected ? BlankColors.ink.opacity(0.58) : Color.white.opacity(0.46))
                }

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .stroke(selected ? BlankColors.ink.opacity(0.38) : Color.white.opacity(0.26), lineWidth: 1)
                    if selected {
                        Circle()
                            .fill(BlankColors.ink)
                            .padding(4)
                    }
                }
                .frame(width: 18, height: 18)
            }
            .foregroundStyle(selected ? BlankColors.ink : Color.white.opacity(0.88))
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.92) : Color.white.opacity(0.095))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? Color.white.opacity(0.72) : Color.white.opacity(0.12), lineWidth: selected ? 1.2 : 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct LegalDocumentView: View {
    let document: BlankLegalDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(document.updatedAt)
                        .font(.blankInter(size: 13, relativeTo: .footnote))
                        .foregroundStyle(.secondary)

                    ForEach(sections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(section.title)
                                .font(.blankInter(size: 18, weight: .semibold, relativeTo: .headline))

                            Text(section.body)
                                .font(.blankInter(size: 14, relativeTo: .body))
                                .foregroundStyle(.secondary)
                                .lineSpacing(3)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var sections: [(title: String, body: String)] {
        switch document {
        case .termsOfUse:
            return [
                (
                    "Agreement",
                    "By using Blanked, you agree to these Terms of Use and Apple's Standard End User License Agreement. If these terms conflict with Apple's Standard EULA, Apple's Standard EULA applies where required by Apple."
                ),
                (
                    "Subscription",
                    "Blanked offers auto-renewable subscriptions through the App Store. If you start a free trial, it lasts 3 days. After the trial, Apple charges the price shown on the App Store purchase sheet for the selected plan unless you cancel before the trial ends."
                ),
                (
                    "Renewal And Cancellation",
                    "Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period. You can manage or cancel your subscription in App Store account settings. Apple handles billing, renewals, refunds, and payment method changes."
                ),
                (
                    "Use Of The App",
                    "Blanked helps you block distracting apps and websites using Apple's Screen Time frameworks. You are responsible for choosing what to block and for keeping access to essential apps, contacts, and services available when needed."
                ),
                (
                    "No Medical Advice",
                    "Blanked may provide digital wellness insights, but it is not a medical device and does not provide diagnosis, treatment, or medical advice."
                ),
                (
                    "Contact",
                    "For support or legal questions, contact hola@blankeate.com."
                )
            ]
        case .privacyPolicy:
            return [
                (
                    "Overview",
                    "Blanked is a digital wellness app that helps you block distracting apps and websites. In this version, Blanked does not collect personal data through its own backend."
                ),
                (
                    "Data Stored On Device",
                    "Blanked stores setup state, blocking status, selected Screen Time categories, session timing, onboarding progress, and app settings on your device. Your exact Screen Time app and website selections stay on your device."
                ),
                (
                    "Onboarding Data",
                    "Your onboarding answers are used inside the app to personalize the experience and are stored locally on your device. Blanked does not send onboarding answers to its own backend in this version."
                ),
                (
                    "Purchases",
                    "Subscriptions are processed by Apple through the App Store. Blanked can check whether you have an active entitlement, but Apple handles payment details and billing."
                ),
                (
                    "Sharing",
                    "Blanked does not sell your personal data and does not share it with third-party advertisers."
                ),
                (
                    "Your Choices",
                    "You can revoke Screen Time permissions in iOS Settings, cancel your subscription in App Store settings, or contact hola@blankeate.com for privacy requests."
                )
            ]
        }
    }
}
