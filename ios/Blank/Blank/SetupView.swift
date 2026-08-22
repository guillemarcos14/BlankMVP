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
    case diagnosis
    case recovery
    case commitment
    case personalization
    case trial
    case permission
    case notifications
    case apps

    var bottomGlowPalette: BottomGlowPalette {
        let palettes: [BottomGlowPalette] = [
            .init(id: 0, primary: Color(red: 0.48, green: 0.66, blue: 0.84), secondary: Color(red: 0.62, green: 0.76, blue: 0.90), accent: Color(red: 0.34, green: 0.52, blue: 0.72)),
            .init(id: 1, primary: Color(red: 0.42, green: 0.61, blue: 0.82), secondary: Color(red: 0.55, green: 0.72, blue: 0.88), accent: Color(red: 0.30, green: 0.48, blue: 0.68)),
            .init(id: 2, primary: Color(red: 0.38, green: 0.58, blue: 0.80), secondary: Color(red: 0.58, green: 0.74, blue: 0.90), accent: Color(red: 0.28, green: 0.46, blue: 0.66)),
            .init(id: 3, primary: Color(red: 0.36, green: 0.56, blue: 0.78), secondary: Color(red: 0.52, green: 0.70, blue: 0.88), accent: Color(red: 0.32, green: 0.50, blue: 0.70)),
            .init(id: 4, primary: Color(red: 0.44, green: 0.64, blue: 0.84), secondary: Color(red: 0.60, green: 0.76, blue: 0.91), accent: Color(red: 0.31, green: 0.50, blue: 0.71))
        ]
        return palettes[rawValue % palettes.count]
    }
}

private struct BottomGlowPalette {
    let id: Int
    let primary: Color
    let secondary: Color
    let accent: Color
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

private struct OnboardingResponsePayload: Encodable {
    let anonymous_user_id: String
    let name: String
    let age_range: String
    let goal: String
    let profile: String
    let daily_hours: Double
    let ai_goal: String
    let weak_moment: String
    let selected_plan: String
    let locale: String
    let app_version: String
    let build_number: String
    let data_consent: Bool
    let consent_text: String
}

private struct OnboardingResponsesClient {
    private let baseURL: URL?
    private let session: URLSession

    init(baseURL: URL? = Self.configuredBaseURL(), session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func submit(_ payload: OnboardingResponsePayload) async throws {
        #if DEBUG
        if baseURL == nil {
            return
        }
        #endif

        guard let baseURL else {
            throw URLError(.badURL)
        }

        let url = baseURL.appendingPathComponent("onboarding-responses")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private static func configuredBaseURL() -> URL? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "BlankMembershipAPIBaseURL") as? String else {
            return nil
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else {
            return nil
        }
        return URL(string: trimmed)
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
    @State private var isSubmittingOnboardingResponse = false
    @State private var presentedLegalDocument: BlankLegalDocument?
    @State private var recoveryRevealStep = 0
    @State private var personalizationShowsDetail = false

    @AppStorage("blankOnboardingName", store: BlankSharedState.defaults) private var name = ""
    @AppStorage("blankOnboardingAnonymousUserId", store: BlankSharedState.defaults) private var onboardingAnonymousUserId = ""
    @AppStorage("blankWeeklyAIGoal", store: BlankSharedState.defaults) private var onboardingGoal = ""
    @AppStorage("blankOnboardingWeakMoment", store: BlankSharedState.defaults) private var weakMoment = ""
    @AppStorage("blankOnboardingGoal", store: BlankSharedState.defaults) private var selectedOnboardingGoal = ""
    @AppStorage("blankOnboardingAgeRange", store: BlankSharedState.defaults) private var selectedAgeRange = ""
    @AppStorage("blankOnboardingProfile", store: BlankSharedState.defaults) private var selectedProfile = ""
    @AppStorage("blankOnboardingDailyHours", store: BlankSharedState.defaults) private var storedDailyHours = 4.5
    @AppStorage("blankOnboardingTrialStarted", store: BlankSharedState.defaults) private var trialStarted = false

    var body: some View {
        ZStack {
            BlankOnboardingBackground(palette: currentStep.bottomGlowPalette)

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
                                .frame(height: usesAnchoredPrimaryAction ? max(0, proxy.size.height - 64) : nil)

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
            .padding(.horizontal, 32)
            .padding(.bottom, 0)

            OnboardingTopBreathingLight(palette: currentStep.bottomGlowPalette)
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
            if step == .recovery {
                recoveryRevealStep = 0
            }
            if step == .commitment {
                resetCommitmentHold()
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
        case .diagnosis:
            diagnosisStep
        case .recovery:
            recoveryStep
        case .commitment:
            commitmentStep
        case .personalization:
            personalizationStep
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
        referenceScene(
            lines: [
                .text("Your phone is taking"),
                .text("more of your life"),
                .text("than you think", icon: "iphone")
            ],
            body: "Let's calculate it",
            primaryTitle: button,
            primaryAction: goForward
        )
    }

    private var nameStep: some View {
        referenceScene(
            lines: [
                .text("First, what should"),
                .text("we call you?", icon: "person.fill")
            ],
            primaryTitle: "Continue",
            primaryAction: {
                goForward()
            },
            centerContent: true,
            accessory: AnyView(
                TextField("You", text: $name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .font(.blankInter(size: 18, weight: .medium, relativeTo: .body))
                    .foregroundStyle(BlankColors.ink)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 18)
                    .frame(height: 54)
                    .blankGlassCard(cornerRadius: 18, tintOpacity: 0.34)
                    .frame(maxWidth: 280, alignment: .leading)
            )
        )
    }

    private var lifetimeStep: some View {
        referenceScene(
            lines: [
                .text("The average person loses"),
                .accent("\(lifetimeYears) years", icon: "hourglass"),
                .text("to their phone screen"),
                .text("over a lifetime")
            ],
            primaryTitle: "Continue",
            primaryAction: goForward
        )
        .onAppear {
            startLifetimeAnimation()
        }
    }

    private var dopamineStep: some View {
        referenceScene(
            lines: [
                .text("Algorithms are built"),
                .text("to pull you back", icon: "sparkles"),
                .text("before you notice")
            ],
            body: "Blanked is built to interrupt that loop before it wins",
            primaryTitle: "Continue",
            primaryAction: goForward
        )
    }

    private var dailyUseStep: some View {
        referenceScene(
            lines: [
                .text("What's your average"),
                .text("daily screen time?", icon: "iphone"),
                .accent("\(formattedHours(dailyHours)) / day")
            ],
            primaryTitle: "Calculate time lost",
            primaryAction: {
                storedDailyHours = dailyHours
                goForward()
            },
            accessory: AnyView(
                Slider(value: $dailyHours, in: 1...9, step: 0.5)
                    .tint(Color.white)
                    .frame(maxWidth: 330)
                    .onChange(of: dailyHours) { value in
                        storedDailyHours = value
                    }
            )
        )
    }

    private var resultStep: some View {
        referenceScene(
            lines: [
                .text("At this pace, your phone costs you"),
                .accent("\(animatedLostDays) days", icon: "calendar"),
                .text("this year"),
                .accent("\(animatedLostYears) years", icon: "clock.arrow.circlepath"),
                .text("over a lifetime")
            ],
            body: "That's too much time",
            primaryTitle: "See how I can recover",
            primaryAction: {
                onboardingGoal = firstTargetText
                weakMoment = weakMomentPreview
                goForward()
            }
        )
        .onAppear {
            startResultCountAnimation()
        }
    }

    private var recoveryStep: some View {
        referenceScene(
            lines: recoverySceneLines,
            primaryTitle: "Start my first block",
            primaryAction: {
                if recoveryRevealStep < 1 {
                    withAnimation(.spring(response: 0.48, dampingFraction: 0.88)) {
                        recoveryRevealStep += 1
                    }
                } else {
                    sessionStore.applyOnboardingPlan(modeName: onboardingNameText, startHour: recommendedHourPreview)
                    goForward()
                }
            }
        )
    }

    private var goalStep: some View {
        choiceStep(
            title: "What matters most to you?",
            options: [
                ("moon.fill", "Sleep better"),
                ("target", "Deep work"),
                ("person.2.fill", "More presence"),
                ("app.badge.fill", "Less social media"),
                ("lock.shield.fill", "Control back")
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
            title: "When do you usually lose control?",
            options: [
                ("moon.stars.fill", "Night scrolling"),
                ("laptopcomputer", "Work distractions"),
                ("graduationcap.fill", "Study focus"),
                ("sparkles", "Boredom loop"),
                ("person.2.fill", "Social relapse"),
                ("sun.max.fill", "Morning checking")
            ],
            selection: selectedProfile
        ) { selectedProfile = $0 }
    }

    private var diagnosisStep: some View {
        referenceScene(
            lines: [
                .text("Your first win is"),
                .text("blocking your", icon: diagnosisIconName),
                .text("weakest hour")
            ],
            body: "You can recover\n\(recoveredWeeklyHoursNumberText) hours a week\n\(recoveredYearlyDaysText) days a year",
            primaryTitle: "Build my plan",
            primaryAction: {
                onboardingGoal = firstTargetText
                weakMoment = weakMomentPreview
                sessionStore.applyOnboardingPlan(modeName: onboardingNameText, startHour: recommendedHourPreview)
                goForward()
            }
        )
    }

    private var notificationsStep: some View {
        referenceScene(
            lines: [
                .text("Let us warn you"),
                .text("before your weakest moment", icon: "bell.badge.fill")
            ],
            primaryTitle: "Enable reminders",
            primaryAction: requestNotifications,
            secondaryTitle: "Not now",
            secondaryAction: goForward,
            accessory: AnyView(notificationPreview),
            accessoryAboveText: true
        )
    }

    private var commitmentStep: some View {
        referenceScene(
            lines: [
                .text("Hold to commit"),
                .text("to protecting", icon: "hand.raised.fill"),
                .text(commitmentFocusText)
            ],
            body: commitmentComplete ? "Done." : "Hold for \(max(0, 3 - commitmentSeconds)) seconds.",
            accessory: AnyView(commitmentHoldControl)
        )
    }

    private var personalizationStep: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 14) {
                    ReferenceOnboardingText(
                        eyebrow: nil,
                        lines: [
                            .text("Let's personalize"),
                            .text("the plan", icon: "sparkles")
                        ],
                        body: personalizationShowsDetail ? "Use the answers to personalize my plan\nand improve the recommendations." : nil,
                        detailStartIndex: 2,
                        titleOpacity: personalizationShowsDetail ? 0.38 : 1
                    )
                }
                .frame(maxWidth: 318, alignment: .leading)
                .position(x: proxy.size.width / 2, y: proxy.size.height * 0.46)

                VStack(spacing: 9) {
                    Button {
                        handlePersonalizationTap()
                    } label: {
                        if isSubmittingOnboardingResponse {
                            ProgressView()
                                .tint(Color.white)
                        } else {
                            Text("Personalize my plan")
                        }
                    }
                    .buttonStyle(ReferenceOnboardingButtonStyle())
                    .frame(maxWidth: 318)
                    .disabled(isSubmittingOnboardingResponse)

                    Text("We do not share the app list or screen time data.")
                        .font(.blankInter(size: 12, weight: .medium, relativeTo: .caption))
                        .foregroundStyle(Color.white.opacity(0.52))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .frame(maxWidth: 318)
                }
                .frame(maxWidth: 318)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var trialStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            ReferenceOnboardingText(
                eyebrow: nil,
                lines: [
                    .text("Don't lose \(lostLifetimeYears) years."),
                    .text("Start with 3 days free.")
                ],
                body: nil
            )

            Text("Blanked blocks your biggest distractions,\nturns weak moments into protected time,\nand helps you feel in control again.")
                .font(.blankInter(size: 13, weight: .medium, relativeTo: .footnote))
                .foregroundStyle(Color.white.opacity(0.50))
                .multilineTextAlignment(.leading)
                .lineSpacing(3)
                .frame(maxWidth: 318, alignment: .leading)
                .padding(.top, 15)

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
            .frame(maxWidth: 318)
            .padding(.top, 25)

            Button {
                purchaseSelectedPlan()
            } label: {
                if purchaseStore.isPurchasing || purchaseStore.isLoading {
                    ProgressView()
                        .tint(Color.black)
                } else {
                    Text("Start Free")
                }
            }
            .buttonStyle(PaywallPrimaryButtonStyle())
            .frame(maxWidth: 318)
            .padding(.top, 22)

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
            .foregroundStyle(Color.white.opacity(0.70))
            .buttonStyle(.plain)
            .padding(.top, 13)

            if isReviewDemoAccessAvailable {
                Button("Continue in demo mode") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    continueWithReviewDemoAccess()
                }
                .font(.blankInter(size: 13, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(Color.white.opacity(0.82))
                .buttonStyle(.plain)
                .padding(.top, 13)
            }

            if let purchaseMessage = purchaseStore.message {
                Text(purchaseMessage)
                    .font(.blankInter(size: 12, relativeTo: .caption))
                    .foregroundStyle(Color.white.opacity(0.74))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 318)
                    .padding(.top, 10)
            }

            Spacer(minLength: 16)

            legalDisclosure
        }
        .frame(maxWidth: 318, maxHeight: .infinity, alignment: .center)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    private var permissionStep: some View {
        referenceScene(
            lines: [
                .text(screenTimeBlocker.authorizationStatus == .approved ? "Screen Time is ready" : "Allow Screen Time"),
                .text("so Blanked can", icon: "lock.shield.fill"),
                .text("block distractions")
            ],
            body: screenTimeDescription,
            primaryTitle: screenTimeBlocker.authorizationStatus == .approved ? "Continue" : "Allow Screen Time",
            primaryAction: authorizeScreenTime,
            accessory: screenTimeBlocker.authorizationStatus == .approved ? AnyView(StatusPill(text: "Screen Time ready")) : AnyView(EmptyView())
        )
    }

    private var appsStep: some View {
        referenceScene(
            lines: [
                .text(sessionStore.hasSelectedApps ? "Your first block" : "Choose what"),
                .text(sessionStore.hasSelectedApps ? "is ready with" : "to block", icon: "app.badge.fill"),
                .text(sessionStore.hasSelectedApps ? "\(sessionStore.selectionCount) selections" : onboardingNameText)
            ],
            body: sessionStore.hasSelectedApps
                ? weakMomentPreview
                : "Pick the apps, categories or websites that trigger this pattern.",
            primaryTitle: sessionStore.hasSelectedApps ? "Continue" : "Select apps",
            primaryAction: selectAppsOrContinue,
            secondaryTitle: sessionStore.hasSelectedApps ? "Edit selection" : nil,
            secondaryAction: sessionStore.hasSelectedApps ? { showingPicker = true } : nil
        )
    }

    private func choiceStep(
        title: String,
        options: [(icon: String, title: String)],
        selection: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(spacing: 22) {
            ReferenceOnboardingText(
                eyebrow: nil,
                lines: choiceSceneLines(for: title),
                body: nil
            )

            VStack(spacing: 11) {
                ForEach(options, id: \.title) { option in
                    OnboardingChoiceButton(
                        systemName: option.icon,
                        title: option.title,
                        selected: false
                    ) {
                        onSelect(option.title)
                        goForward()
                    }
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: 318)
        }
        .frame(maxWidth: 318, maxHeight: .infinity, alignment: .center)
    }

    private func referenceScene(
        eyebrow: String? = nil,
        lines: [ReferenceTextLine],
        body: String? = nil,
        primaryTitle: String? = nil,
        primaryAction: (() -> Void)? = nil,
        secondaryTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil,
        centerContent: Bool = false,
        accessory: AnyView = AnyView(EmptyView()),
        accessoryAboveText: Bool = false
    ) -> some View {
        ReferenceOnboardingScene(
            eyebrow: eyebrow,
            lines: lines,
            body: body,
            primaryTitle: primaryTitle,
            primaryAction: primaryAction,
            secondaryTitle: secondaryTitle,
            secondaryAction: secondaryAction,
            centerContent: centerContent,
            accessory: accessory,
            accessoryAboveText: accessoryAboveText
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

    private var notificationPreview: some View {
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

    private var commitmentHoldControl: some View {
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
        VStack(spacing: 3) {
            Text("Full access today. \(selectedPlanRenewalDisclosure)")
                .multilineTextAlignment(.center)

            HStack(spacing: 3) {
                legalButton("Terms of Use", document: .termsOfUse)
                Text("and")
                legalButton("Privacy Policy", document: .privacyPolicy)
                Text("apply")
            }
        }
        .font(.blankInter(size: 11, relativeTo: .caption2))
        .foregroundStyle(Color.white.opacity(0.40))
        .lineSpacing(2)
        .frame(maxWidth: 318)
    }

    private func legalButton(_ title: String, document: BlankLegalDocument) -> some View {
        Button(title) {
            presentedLegalDocument = document
        }
        .font(.blankInter(size: 11, weight: .semibold, relativeTo: .caption2))
        .foregroundStyle(Color.white.opacity(0.72))
        .buttonStyle(.plain)
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
        case .awareness, .lifetime, .dopamine, .name, .dailyUse, .result, .diagnosis, .recovery, .goal, .age, .profile, .commitment, .personalization, .trial, .notifications, .permission, .apps:
            return true
        }
    }

    private var diagnosisIconName: String {
        switch onboardingArchetype {
        case "Night Scroller":
            return "moon.stars.fill"
        case "Dopamine Loop":
            return "sparkles"
        case "Presence Drifter":
            return "person.2.fill"
        case "Focus Breaker":
            return "target"
        default:
            return "arrow.triangle.2.circlepath"
        }
    }

    private func choiceSceneLines(for title: String) -> [ReferenceTextLine] {
        switch title {
        case "What matters most to you?":
            return [
                .text("What do you want"),
                .text("to protect first?", icon: "shield.fill")
            ]
        case "How old are you?":
            return [
                .text("Where are you"),
                .text("in life right now?", icon: "person.fill")
            ]
        case "When do you usually lose control?":
            return [
                .text("Where do you"),
                .text("lose control?", icon: "clock.fill")
            ]
        default:
            return [.text(title)]
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

    private var recoveredWeeklyHours: Double {
        max(0.5, dailyHours * 7.0 * 0.30)
    }

    private var recoveredWeeklyHoursText: String {
        if recoveredWeeklyHours.rounded() == recoveredWeeklyHours {
            return "\(Int(recoveredWeeklyHours))h"
        }
        return String(format: "%.1fh", recoveredWeeklyHours)
    }

    private var recoveredWeeklyHoursNumberText: String {
        if recoveredWeeklyHours.rounded() == recoveredWeeklyHours {
            return "\(Int(recoveredWeeklyHours))"
        }
        return String(format: "%.1f", recoveredWeeklyHours)
    }

    private var recoveredYearlyDaysText: String {
        let days = max(1, Int(((recoveredWeeklyHours * 52.0) / 24.0).rounded()))
        return "\(days)"
    }

    private var recoverySceneLines: [ReferenceTextLine] {
        let openingOpacity = recoveryRevealStep == 0 ? 1.0 : 0.34
        var lines = onboardingTextLines(from: riskBodyPreview, opacity: openingOpacity)

        guard recoveryRevealStep >= 1 else { return lines }

        lines.append(.text("Let's protect", icon: "shield.fill"))
        lines.append(.text(weakMomentPreview))
        return lines
    }

    private func onboardingTextLines(from text: String, opacity: Double = 1) -> [ReferenceTextLine] {
        var lines: [ReferenceTextLine] = []
        var current = ""

        for word in text.split(separator: " ").map(String.init) {
            let candidate = current.isEmpty ? word : "\(current) \(word)"
            if candidate.count > 24, !current.isEmpty {
                lines.append(.text(current, opacity: opacity))
                current = word
            } else {
                current = candidate
            }
        }

        if !current.isEmpty {
            lines.append(.text(current, opacity: opacity))
        }

        return lines
    }

    private var onboardingArchetype: String {
        let goal = selectedOnboardingGoal.lowercased()
        let profile = selectedProfile.lowercased()

        if goal.contains("sleep") || profile.contains("night") {
            return "Night Scroller"
        }
        if goal.contains("social") || profile.contains("social") || profile.contains("boredom") {
            return "Dopamine Loop"
        }
        if goal.contains("presence") {
            return "Presence Drifter"
        }
        if goal.contains("work") || profile.contains("work") || profile.contains("study") {
            return "Focus Breaker"
        }
        return "Habit Rebuilder"
    }

    private var recommendedHourPreview: Int {
        switch onboardingArchetype {
        case "Night Scroller":
            return 22
        case "Dopamine Loop":
            return 20
        case "Presence Drifter":
            return 18
        case "Focus Breaker":
            return selectedProfile.lowercased().contains("study") ? 16 : 9
        default:
            return selectedProfile.lowercased().contains("morning") ? 8 : Calendar.current.component(.hour, from: Date())
        }
    }

    private var weakMomentPreview: String {
        DigitalWellnessAI.hourRangeText(recommendedHourPreview)
    }

    private var initialBlockMinutesPreview: Int {
        switch onboardingArchetype {
        case "Night Scroller":
            return 45
        case "Focus Breaker":
            return 45
        case "Presence Drifter":
            return 25
        default:
            return dailyHours >= 6.5 ? 35 : 30
        }
    }

    private var riskTitlePreview: String {
        switch onboardingArchetype {
        case "Night Scroller":
            return "Late-night scroll risk"
        case "Dopamine Loop":
            return "High stimulation risk"
        case "Presence Drifter":
            return "Attention leak risk"
        case "Focus Breaker":
            return "Deep-work interruption risk"
        default:
            return "Automatic checking risk"
        }
    }

    private var riskBodyPreview: String {
        switch onboardingArchetype {
        case "Night Scroller":
            return "Your highest leverage habit is protecting the final hour before sleep."
        case "Dopamine Loop":
            return "You usually scroll when your energy is lowest"
        case "Presence Drifter":
            return "The first win is protecting short windows where you want to be present."
        case "Focus Breaker":
            return "Your biggest gain is starting a block before the first distraction."
        default:
            return "Your plan should make the first block easy and repeatable."
        }
    }

    private var firstTargetText: String {
        switch onboardingArchetype {
        case "Night Scroller":
            return "Reduce late scrolling by 30%"
        case "Dopamine Loop":
            return "Break the boredom scroll loop"
        case "Presence Drifter":
            return "Protect one present window daily"
        case "Focus Breaker":
            return "Protect your first deep-work block"
        default:
            return "Build one repeatable block"
        }
    }

    private var commitmentFocusText: String {
        switch onboardingArchetype {
        case "Night Scroller":
            return "my sleep"
        case "Dopamine Loop":
            return "my attention"
        case "Presence Drifter":
            return "my presence"
        case "Focus Breaker":
            return "my focus"
        default:
            return "my time"
        }
    }

    private var onboardingNameText: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Your plan" : trimmedName
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

    private func submitOnboardingPersonalization() {
        guard !isSubmittingOnboardingResponse else { return }
        isSubmittingOnboardingResponse = true
        message = nil
        let payload = OnboardingResponsePayload(
            anonymous_user_id: currentOnboardingAnonymousUserId(),
            name: onboardingNameText,
            age_range: selectedAgeRange,
            goal: selectedOnboardingGoal,
            profile: selectedProfile,
            daily_hours: storedDailyHours,
            ai_goal: firstTargetText,
            weak_moment: weakMomentPreview,
            selected_plan: selectedPlan.rawValue,
            locale: Locale.current.identifier,
            app_version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            build_number: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            data_consent: true,
            consent_text: "Personalize my plan"
        )

        Task {
            do {
                try await OnboardingResponsesClient().submit(payload)
                await MainActor.run {
                    isSubmittingOnboardingResponse = false
                    goForward()
                }
            } catch {
                await MainActor.run {
                    isSubmittingOnboardingResponse = false
                    message = "We could not personalize your plan. Please try again."
                }
            }
        }
    }

    private func handlePersonalizationTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        guard personalizationShowsDetail else {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.88)) {
                personalizationShowsDetail = true
            }
            return
        }

        submitOnboardingPersonalization()
    }

    private func currentOnboardingAnonymousUserId() -> String {
        if !onboardingAnonymousUserId.isEmpty {
            return onboardingAnonymousUserId
        }
        let created = UUID().uuidString
        onboardingAnonymousUserId = created
        return created
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

    private func resetCommitmentHold() {
        cancelCommitmentHold()
        commitmentComplete = false
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
            DigitalWellnessAI.saveInitialDiagnosis(
                goal: selectedOnboardingGoal,
                profile: selectedProfile,
                dailyHours: storedDailyHours,
                selectionCount: sessionStore.selectionCount
            )
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
        if currentStep == .commitment {
            resetCommitmentHold()
        }
        if currentStep == .personalization || previous == .personalization {
            personalizationShowsDetail = false
        }
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

private struct ReferenceTextLine: Identifiable {
    let id = UUID()
    let text: String
    let icon: String?
    let isAccent: Bool
    let opacity: Double

    static func text(_ text: String, icon: String? = nil, opacity: Double = 1) -> ReferenceTextLine {
        ReferenceTextLine(text: text, icon: icon, isAccent: false, opacity: opacity)
    }

    static func accent(_ text: String, icon: String? = nil, opacity: Double = 1) -> ReferenceTextLine {
        ReferenceTextLine(text: text, icon: icon, isAccent: true, opacity: opacity)
    }
}

private struct ReferenceOnboardingScene: View {
    let eyebrow: String?
    let lines: [ReferenceTextLine]
    let bodyText: String?
    let primaryTitle: String?
    let primaryAction: (() -> Void)?
    let secondaryTitle: String?
    let secondaryAction: (() -> Void)?
    let centerContent: Bool
    let accessory: AnyView
    let accessoryAboveText: Bool
    @State private var showsDetail = false

    init(
        eyebrow: String?,
        lines: [ReferenceTextLine],
        body: String?,
        primaryTitle: String?,
        primaryAction: (() -> Void)?,
        secondaryTitle: String?,
        secondaryAction: (() -> Void)?,
        centerContent: Bool,
        accessory: AnyView,
        accessoryAboveText: Bool
    ) {
        self.eyebrow = eyebrow
        self.lines = lines
        self.bodyText = body
        self.primaryTitle = primaryTitle
        self.primaryAction = primaryAction
        self.secondaryTitle = secondaryTitle
        self.secondaryAction = secondaryAction
        self.centerContent = centerContent
        self.accessory = accessory
        self.accessoryAboveText = accessoryAboveText
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 14) {
                    if accessoryAboveText {
                        accessory
                            .padding(.bottom, 8)
                    }

                    ReferenceOnboardingText(
                        eyebrow: eyebrow,
                        lines: lines,
                        body: showsDetail ? bodyText : nil,
                        detailStartIndex: lines.count,
                        titleOpacity: showsDetail ? 0.38 : 1
                    )

                    if !accessoryAboveText {
                        accessory
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: 318, alignment: .leading)
                .position(x: proxy.size.width / 2, y: proxy.size.height * 0.46)

                if primaryTitle != nil || secondaryTitle != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        if let primaryTitle {
                            Button(primaryTitle) {
                                handlePrimaryTap()
                            }
                            .buttonStyle(ReferenceOnboardingButtonStyle())
                            .frame(maxWidth: .infinity)
                        }

                        if let secondaryTitle, let secondaryAction {
                            Button(secondaryTitle, action: secondaryAction)
                                .font(.blankInter(size: 13, weight: .semibold, relativeTo: .footnote))
                                .foregroundStyle(Color.white.opacity(0.70))
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .frame(maxWidth: 318, alignment: .leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hasDetail: Bool {
        guard let bodyText else { return false }
        return !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func handlePrimaryTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if hasDetail && !showsDetail {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.88)) {
                showsDetail = true
            }
            return
        }

        primaryAction?()
    }
}

private struct ReferenceOnboardingText: View {
    let eyebrow: String?
    let lines: [ReferenceTextLine]
    let bodyText: String?
    let detailStartIndex: Int
    let titleOpacity: Double

    init(eyebrow: String?, lines: [ReferenceTextLine], body: String?, detailStartIndex: Int = 0, titleOpacity: Double = 1) {
        self.eyebrow = eyebrow
        self.lines = lines
        self.bodyText = body
        self.detailStartIndex = detailStartIndex
        self.titleOpacity = titleOpacity
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let eyebrow, !eyebrow.isEmpty {
                Text(eyebrow.uppercased())
                    .font(.blankInter(size: 12, weight: .semibold, relativeTo: .caption))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .padding(.bottom, 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(lines.indices, id: \.self) { index in
                    ReferenceAnimatedLine(line: lines[index], delay: Double(index) * 0.075, iconAfterText: index.isMultiple(of: 2))
                }
            }
            .opacity(titleOpacity)
            .animation(.easeInOut(duration: 0.26), value: titleOpacity)

            if let bodyText, !bodyText.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(detailLines(from: bodyText).indices, id: \.self) { index in
                        let lineIndex = detailStartIndex + index
                        ReferenceAnimatedLine(
                            line: .text(detailLines(from: bodyText)[index]),
                            delay: Double(lineIndex) * 0.075,
                            iconAfterText: lineIndex.isMultiple(of: 2)
                        )
                    }
                }
                .padding(.top, 2)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func detailLines(from text: String) -> [String] {
        var lines: [String] = []

        for paragraph in text.components(separatedBy: .newlines) {
            let words = paragraph.split(separator: " ").map(String.init)
            var current = ""

            for word in words {
                let candidate = current.isEmpty ? word : "\(current) \(word)"
                if candidate.count > 24, !current.isEmpty {
                    lines.append(current)
                    current = word
                } else {
                    current = candidate
                }
            }

            if !current.isEmpty {
                lines.append(current)
            }
        }

        return lines
    }
}

private struct ReferenceAnimatedLine: View {
    let line: ReferenceTextLine
    let delay: Double
    let iconAfterText: Bool
    @State private var visible = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if !iconAfterText {
                iconView
            }

            Text(line.text)
                .font(.blankInter(size: 32, weight: .semibold, relativeTo: .largeTitle))
                .foregroundStyle(line.isAccent ? Color.white : Color.white.opacity(0.96))
                .lineLimit(line.icon == nil ? 2 : 1)
                .minimumScaleFactor(line.icon == nil ? 0.68 : 0.46)
                .multilineTextAlignment(.leading)
                .lineSpacing(0)
                .tracking(0)
                .shadow(color: line.isAccent ? Color.white.opacity(0.68) : .clear, radius: 10, x: 0, y: 0)
                .shadow(color: line.isAccent ? BlankColors.airMist.opacity(0.52) : .clear, radius: 22, x: 0, y: 0)
                .shadow(color: line.isAccent ? BlankColors.airBlue.opacity(0.34) : .clear, radius: 34, x: 0, y: 0)

            if iconAfterText {
                iconView
            }
        }
        .frame(maxWidth: 318, alignment: .leading)
        .opacity(visible ? line.opacity : 0)
        .animation(.easeInOut(duration: 0.26), value: line.opacity)
        .offset(y: visible ? 0 : 28)
        .blur(radius: visible ? 0 : 5)
        .onAppear {
            visible = false
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86).delay(delay)) {
                visible = true
            }
        }
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon = line.icon {
            Image(systemName: icon)
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(line.isAccent ? Color.white : Color.white.opacity(0.96))
                .frame(width: 28, height: 28)
                .shadow(color: line.isAccent ? Color.white.opacity(0.62) : .clear, radius: 10, x: 0, y: 0)
                .shadow(color: line.isAccent ? BlankColors.airMist.opacity(0.38) : .clear, radius: 18, x: 0, y: 0)
        }
    }
}

private struct ReferenceOnboardingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.blankInter(size: 15, weight: .semibold, relativeTo: .callout))
            .foregroundStyle(Color.white.opacity(configuration.isPressed ? 0.78 : 0.92))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.black.opacity(configuration.isPressed ? 0.54 : 0.42))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.035), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private struct PaywallPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.blankInter(size: 15, weight: .semibold, relativeTo: .callout))
            .foregroundStyle(Color.black.opacity(configuration.isPressed ? 0.68 : 0.92))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.78 : 0.94))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: Color.white.opacity(configuration.isPressed ? 0.10 : 0.20), radius: 18, x: 0, y: 0)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
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
                    .frame(maxWidth: 318)
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
            .shadow(color: Color.white.opacity(0.46), radius: 10, x: 0, y: 0)
            .shadow(color: BlankColors.airMist.opacity(0.38), radius: 24, x: 0, y: 0)

            Text(caption)
                .font(.blankInter(size: 15, relativeTo: .subheadline))
                .foregroundStyle(Color.white.opacity(0.66))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
    }
}

private struct OnboardingInsightCard: View {
    let systemName: String
    let title: String
    let value: String
    let caption: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(BlankColors.airMist)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.10)))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.blankInter(size: 12, weight: .semibold, relativeTo: .caption))
                    .foregroundStyle(Color.white.opacity(0.56))

                Text(value)
                    .font(.blankInter(size: 18, weight: .semibold, relativeTo: .headline))
                    .foregroundStyle(Color.white.opacity(0.94))
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                Text(caption)
                    .font(.blankInter(size: 12, relativeTo: .caption))
                    .foregroundStyle(Color.white.opacity(0.56))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(Color.white.opacity(0.09))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct OnboardingPlanPreviewRow: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.blankInter(size: 14, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(BlankColors.ink)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.86)))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.blankInter(size: 17, weight: .semibold, relativeTo: .headline))
                    .foregroundStyle(Color.white.opacity(0.94))

                Text(detail)
                    .font(.blankInter(size: 13, relativeTo: .footnote))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .lineSpacing(2)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(Color.white.opacity(0.09))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct PaywallValueRow: View {
    let systemName: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.86))
                .frame(width: 20)

            Text(text)
                .font(.blankInter(size: 13, weight: .medium, relativeTo: .footnote))
                .foregroundStyle(Color.white.opacity(0.82))
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 34)
        .background {
            Capsule().fill(Color.white.opacity(0.075))
        }
    }
}

private struct OnboardingChoiceButton: View {
    let systemName: String
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .frame(width: 22)

                Text(title)
                    .font(.blankInter(size: 17, weight: .medium, relativeTo: .body))
                    .foregroundStyle(Color.white.opacity(0.94))

                Spacer(minLength: 0)

                if selected {
                    EmptyView()
                }
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 58)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(selected ? 0.36 : 0.22))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? Color.white.opacity(0.42) : Color.white.opacity(0.12), lineWidth: selected ? 1.4 : 1)
            }
            .shadow(color: selected ? Color.white.opacity(0.08) : .clear, radius: 12, y: 7)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct BlankOnboardingBackground: View {
    let palette: BottomGlowPalette

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image("blank_home_background_active")
                .resizable()
                .scaledToFill()
                .opacity(0.14)
                .blur(radius: 3)
                .overlay(Color.black.opacity(0.74))
                .ignoresSafeArea()

            ReferenceBottomGlow(palette: palette)
            LinearGradient(
                colors: [
                    Color.black.opacity(0.08),
                    Color.black.opacity(0.22),
                    Color.black.opacity(0.36)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.42), value: palette.id)
    }
}

private struct OnboardingTopBreathingLight: View {
    let palette: BottomGlowPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let duration = 7.4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            GeometryReader { proxy in
                let progress = reduceMotion ? 0.52 : breathingProgress(from: context.date)
                let scale = CGFloat(progress)
                let width = proxy.size.width * (0.82 + scale * 0.18)
                let height: CGFloat = 138 + scale * 46
                let topY = -38 + proxy.safeAreaInsets.top * 0.14

                ZStack {
                    Ellipse()
                        .fill(palette.secondary.opacity(0.12 + progress * 0.06))
                        .frame(width: width, height: height)
                        .blur(radius: 46)
                        .position(x: proxy.size.width / 2, y: topY)

                    Ellipse()
                        .fill(palette.primary.opacity(0.10 + progress * 0.05))
                        .frame(width: width * 0.66, height: height * 0.58)
                        .blur(radius: 34)
                        .position(x: proxy.size.width / 2, y: topY + 5)

                    LinearGradient(
                        colors: [
                            palette.secondary.opacity(0.08 + progress * 0.04),
                            palette.primary.opacity(0.04 + progress * 0.02),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 150 + scale * 28)
                    .position(x: proxy.size.width / 2, y: 58)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .allowsHitTesting(false)
                .blendMode(.screen)
            }
        }
        .ignoresSafeArea()
    }

    private func breathingProgress(from date: Date) -> Double {
        let progress = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration) / duration
        let normalized = progress < 0 ? progress + 1 : progress
        return (1 - cos(normalized * 2 * Double.pi)) / 2
    }
}

private struct ReferenceBottomGlow: View {
    let palette: BottomGlowPalette

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Ellipse()
                    .fill(palette.primary.opacity(0.42))
                    .frame(width: proxy.size.width * 1.55, height: 250)
                    .blur(radius: 50)
                    .position(x: proxy.size.width * 0.50, y: proxy.size.height + 34)

                Ellipse()
                    .fill(palette.secondary.opacity(0.36))
                    .frame(width: proxy.size.width * 1.18, height: 190)
                    .blur(radius: 48)
                    .position(x: proxy.size.width * 0.48, y: proxy.size.height + 18)

                Ellipse()
                    .fill(palette.secondary.opacity(0.42))
                    .frame(width: proxy.size.width * 0.92, height: 360)
                    .blur(radius: 58)
                    .position(x: proxy.size.width * 0.95, y: proxy.size.height - 52)
                    .mask(rightSideRiseMask(proxy: proxy))

                Ellipse()
                    .fill(palette.accent.opacity(0.32))
                    .frame(width: proxy.size.width * 0.70, height: 300)
                    .blur(radius: 64)
                    .position(x: proxy.size.width * 0.86, y: proxy.size.height - 18)
                    .mask(rightSideRiseMask(proxy: proxy))

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.00),
                        palette.secondary.opacity(0.10),
                        palette.primary.opacity(0.18)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 240)
                .position(x: proxy.size.width / 2, y: proxy.size.height - 70)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
    }

    private func rightSideRiseMask(proxy: GeometryProxy) -> some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.00),
                .init(color: .clear, location: 0.44),
                .init(color: .white.opacity(0.20), location: 0.62),
                .init(color: .white, location: 1.00)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: proxy.size.width, height: proxy.size.height)
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
                                .foregroundStyle(Color.white.opacity(0.92))
                                .padding(.horizontal, 7)
                                .frame(minHeight: 20)
                                .background(Capsule().fill(Color.white.opacity(0.12)))
                        }
                    }

                    Text(price)
                        .font(.blankInter(size: 19, weight: .semibold, relativeTo: .headline))

                    Text(detail)
                        .font(.blankInter(size: 12, relativeTo: .caption))
                        .foregroundStyle(Color.white.opacity(0.62))
                }

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .stroke(selected ? Color.white.opacity(0.58) : Color.white.opacity(0.26), lineWidth: 1)
                    if selected {
                        Circle()
                            .fill(Color.white.opacity(0.90))
                            .padding(4)
                    }
                }
                .frame(width: 18, height: 18)
            }
            .foregroundStyle(Color.white.opacity(0.88))
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(selected ? 0.36 : 0.22))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? Color.white.opacity(0.42) : Color.white.opacity(0.12), lineWidth: selected ? 1.4 : 1)
            }
            .shadow(color: selected ? Color.white.opacity(0.08) : .clear, radius: 14, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                    "Blanked is a digital wellness app that helps you block distracting apps and websites. We collect only the data needed to provide the app, process subscriptions, and personalize the onboarding experience on your device."
                ),
                (
                    "Data Stored On Device",
                    "Blanked stores setup state, blocking status, selected Screen Time categories, session timing, onboarding progress, and app settings on your device. Your exact Screen Time app and website selections stay on your device."
                ),
                (
                    "Onboarding Data",
                    "When you tap Personalize my plan, Blanked sends your onboarding answers to its backend to personalize your plan and improve recommendations. Blanked does not share your app list or screen time data."
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
                    "You can revoke permissions in iOS Settings, cancel your subscription in App Store settings, or contact hola@blankeate.com for privacy requests."
                )
            ]
        }
    }
}
