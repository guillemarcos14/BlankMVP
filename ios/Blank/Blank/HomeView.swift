import FamilyControls
import LocalAuthentication
import SwiftUI
import UIKit

enum HomeSection: Hashable {
    case modes
    case schedule
    case report
    case emergency
    case timer
    case settings
}

struct HomeView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var screenTimeBlocker: ScreenTimeBlocker
    @EnvironmentObject private var purchaseStore: StoreKitPurchaseStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @AppStorage("blankAssistantConnectCode", store: BlankSharedState.defaults) private var assistantConnectCode = ""
    @AppStorage("blankAssistantPreferredChannel", store: BlankSharedState.defaults) private var assistantPreferredChannel = ""
    @AppStorage("blankAssistantPhoneNumber", store: BlankSharedState.defaults) private var assistantPhoneNumber = ""

    @State private var now = Date()
    @State private var message: String?
    @State private var messageAction: HomeMessageAction?
    @State private var showingPicker = false
    @State private var activeSection: HomeSection?
    @State private var showingAssistantConnect = false
    @State private var showingContextualAppPicker = false
    @State private var contextualPlanSelection = FamilyActivitySelection()
    @State private var showingRelink = false
    @State private var showingForgetConfirm = false
    @State private var nfcReader = NFCReader()
    @StateObject private var healthKitStore = HealthKitStore()
    @State private var unblankHoldProgress = 0.0
    @State private var isAnimatingUnblankHold = false
    @State private var delayedManualUnlockAt: Date?
    @State private var delayedManualUnlockTask: Task<Void, Never>?
    @State private var showingRelapseReview = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let homeTagline = "Your plan adapts\nbefore the scroll\npulls you back."
    let onOpenOnboardingDemo: () -> Void

    init(_ onOpenOnboardingDemo: @escaping () -> Void = {}) {
        self.onOpenOnboardingDemo = onOpenOnboardingDemo
    }

    private var aiSystem: DigitalWellnessV3System {
        sessionStore.digitalWellnessV3
    }

    var body: some View {
        GeometryReader { proxy in
            let viewportWidth = proxy.size.width
            let viewportHeight = proxy.size.height
            let layout = HomeLayoutMetrics(size: CGSize(width: viewportWidth, height: viewportHeight), safeAreaInsets: proxy.safeAreaInsets)

            ZStack(alignment: .topLeading) {
                if activeSection == nil {
                    (sessionStore.isBlankActive ? BlankColors.newLookDarkBackground : BlankColors.minimalBackground)
                        .frame(width: viewportWidth, height: viewportHeight)
                        .ignoresSafeArea()
                } else {
                    AppBackground(isActive: sessionStore.isBlankActive)
                        .frame(width: viewportWidth, height: viewportHeight)
                        .clipped()
                }

                if activeSection == nil {
                    minimalHome(layout: layout)
                        .frame(width: viewportWidth, height: viewportHeight, alignment: .topLeading)
                }

                homeSectionScreen(viewportWidth: viewportWidth, viewportHeight: viewportHeight)
            }
            .frame(width: viewportWidth, height: viewportHeight, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .foregroundStyle(activeSection == nil ? BlankColors.minimalInk : (sessionStore.isBlankActive ? Color.white : BlankColors.ink))
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(sessionStore.isBlankActive ? .dark : .light)
        .environment(\.blankMinimalAppearance, true)
        .animation(.easeInOut(duration: 0.65), value: sessionStore.isBlankActive)
        .animation(.easeInOut(duration: 0.35), value: activeSection)
        .navigationBarBackButtonHidden()
        .onReceive(timer) { date in
            now = date
            sessionStore.syncFromSharedDefaults(now: date)
            sessionStore.applyScheduleWindow(at: date)
            screenTimeBlocker.apply(isBlankActive: sessionStore.isBlankActive)
            updateDelayedUnlockMessage(now: date)
        }
        .onAppear {
            sessionStore.syncFromSharedDefaults(now: now)
            applyScreenTimeControls()
            screenTimeBlocker.refreshAuthorizationStatus()
            healthKitStore.refresh()
            processPendingBlockConfigurationIfNeeded()
            openWidgetScanIfNeeded()
            showPendingBAIProactiveAlertIfNeeded()
            evaluateBAIProactiveSignals()
            syncAssistantContext()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            sessionStore.syncFromSharedDefaults()
            applyScreenTimeControls()
            screenTimeBlocker.refreshAuthorizationStatus()
            healthKitStore.refresh()
            processPendingBlockConfigurationIfNeeded()
            openWidgetScanIfNeeded()
            showPendingBAIProactiveAlertIfNeeded()
            evaluateBAIProactiveSignals()
            syncAssistantContext()
        }
        .familyActivityPicker(isPresented: $showingPicker, selection: $sessionStore.selection)
        .onChange(of: sessionStore.selection) { newSelection in
            screenTimeBlocker.updateSelection(newSelection, isBlankActive: sessionStore.isBlankActive)
            sessionStore.refreshDailyLimitMonitoring()
            syncAssistantContext()
        }
        .onChange(of: sessionStore.focusModes) { _ in syncAssistantContext() }
        .onChange(of: sessionStore.schedule) { _ in syncAssistantContext() }
        .onChange(of: sessionStore.isBlankActive) { _ in syncAssistantContext() }
        .onChange(of: sessionStore.dailyLimitMinutes) { _ in syncAssistantContext() }
        .onChange(of: sessionStore.dailyLimitEnabled) { _ in syncAssistantContext() }
        .onChange(of: sessionStore.allowOnlyModeEnabled) { _ in
            applyScreenTimeControls()
            syncAssistantContext()
            if sessionStore.allowOnlyModeEnabled && !sessionStore.hasSelectedApps {
                showingPicker = true
            }
        }
        .onChange(of: sessionStore.adultContentBlockingEnabled) { _ in
            applyScreenTimeControls()
            syncAssistantContext()
        }
        .onChange(of: sessionStore.shouldOpenBlockConfiguration) { shouldOpen in
            guard shouldOpen else { return }
            processPendingBlockConfigurationIfNeeded()
        }
        .familyActivityPicker(
            headerText: contextualPickerHeaderText,
            footerText: contextualPickerFooterText,
            isPresented: $showingContextualAppPicker,
            selection: $contextualPlanSelection
        )
        .onChange(of: showingContextualAppPicker) { isPresented in
            if !isPresented {
                if !sessionStore.pendingPlanStartsFreshSelection || contextualPlanSelection.blankedSelectionCount > 0 {
                    if let modeName = sessionStore.pendingPlanModeName,
                       contextualPlanSelection.blankedSelectionCount > 0 {
                        sessionStore.createOrUpdateMode(
                            named: modeName,
                            selection: contextualPlanSelection,
                            appNames: sessionStore.pendingPlanAppNames
                        )
                        if sessionStore.pendingPlanShouldActivate {
                            let result = withAnimation(.easeInOut(duration: 0.65)) {
                                sessionStore.activateBlank(
                                    durationMinutes: sessionStore.pendingPlanDurationMinutes,
                                    hardMode: sessionStore.pendingPlanHardMode
                                )
                            }
                            screenTimeBlocker.updateSelection(sessionStore.selection, isBlankActive: sessionStore.isBlankActive)
                            setMessage(for: result)
                            activeSection = nil
                        } else {
                            message = "\(modeName) mode saved."
                            messageAction = nil
                        }
                    } else if sessionStore.pendingPlanShouldActivate,
                              contextualPlanSelection.blankedSelectionCount > 0 {
                        sessionStore.selection = contextualPlanSelection
                        let result = withAnimation(.easeInOut(duration: 0.65)) {
                            sessionStore.activateBlank(
                                durationMinutes: sessionStore.pendingPlanDurationMinutes,
                                hardMode: sessionStore.pendingPlanHardMode
                            )
                        }
                        applyScreenTimeControls()
                        setMessage(for: result)
                        activeSection = nil
                    } else if let dailyLimitMinutes = sessionStore.pendingPlanDailyLimitMinutes,
                              contextualPlanSelection.blankedSelectionCount > 0 {
                        sessionStore.selection = contextualPlanSelection
                        sessionStore.dailyLimitMinutes = dailyLimitMinutes
                        sessionStore.dailyLimitEnabled = true
                        sessionStore.refreshDailyLimitMonitoring()
                        applyScreenTimeControls()
                        message = "Daily limit set to \(dailyLimitMinutes) minutes."
                        messageAction = nil
                    } else if let schedule = sessionStore.pendingPlanSchedule,
                              contextualPlanSelection.blankedSelectionCount > 0 {
                        sessionStore.selection = contextualPlanSelection
                        sessionStore.applyAdaptivePlan(
                            startMinute: schedule.startMinute,
                            endMinute: schedule.endMinute,
                            durationDays: schedule.durationDays,
                            activateCurrentWindow: false,
                            name: schedule.name,
                            weekdays: schedule.weekdays
                        )
                        applyScreenTimeControls()
                        message = "Added \(schedule.name) without replacing your existing protection windows."
                        messageAction = nil
                    } else {
                        sessionStore.selection = contextualPlanSelection
                    }
                }
                sessionStore.clearPendingPlanAppNames()
                contextualPlanSelection = FamilyActivitySelection()
            }
        }
        .onChange(of: sessionStore.shouldScanBlankFromWidget) { shouldScan in
            guard shouldScan else { return }
            openWidgetScanIfNeeded()
        }
        .fullScreenCover(isPresented: $showingAssistantConnect) {
            AssistantConnectSheet(
                whatsAppNumber: configuredWhatsAppNumber(),
                smsNumber: configuredSMSNumber(),
                openURL: openURL,
                initialContext: assistantContextPayload()
            )
        }
        .sheet(isPresented: $showingRelink) {
            RelinkSheet(message: $message, messageAction: $messageAction)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingForgetConfirm) {
            ForgetBlankConfirmSheet {
                sessionStore.forgetNfcTag()
                screenTimeBlocker.clear()
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog(
            "Review and confirm",
            isPresented: Binding(
                get: { sessionStore.pendingAssistantAction != nil },
                set: { isPresented in
                    if !isPresented { sessionStore.clearAssistantActionConfirmation() }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Confirm") {
                confirmPendingAssistantAction()
            }
            Button("Cancel", role: .cancel) {
                sessionStore.clearAssistantActionConfirmation()
            }
        } message: {
            Text(assistantActionConfirmationMessage)
        }
        .fullScreenCover(isPresented: $showingRelapseReview) {
            RelapseReviewSheet(
                intervention: relapseIntervention,
                onSelect: { reason in
                    sessionStore.recordRelapseReview(reason)
                    sessionStore.requestAssistantActionConfirmation(.applyAIPlan)
                    Task {
                        await BlankFunnelAnalytics.track(
                            "ai_plan_applied",
                            properties: ["source": "relapse_review", "reason": reason.rawValue]
                        )
                    }
                }
            )
            .preferredColorScheme(.light)
        }
    }

    @ViewBuilder
    private func homeSectionScreen(viewportWidth: CGFloat, viewportHeight: CGFloat) -> some View {
        if let activeSection {
            HomeSectionScreen(
                showingPicker: $showingPicker,
                section: activeSection,
                screenWidth: viewportWidth,
                screenHeight: viewportHeight,
                intervention: relapseIntervention,
                onEmergencyUnlock: performEmergencyUnlock,
                onTimedBlank: startTimedBlank,
                onOpenSection: openSection,
                onOpenAssistant: { showingAssistantConnect = true },
                onRequestScreenTimePermission: requestScreenTimePermission,
                onRequestHealthAccess: { healthKitStore.requestAccess() },
                onRelinkBlank: { showingRelink = true },
                onForgetBlank: { showingForgetConfirm = true },
                screenTimeStatus: screenTimePermissionLabel,
                healthStatus: healthPermissionLabel
            ) {
                closeSection()
            }
            .frame(width: viewportWidth, height: viewportHeight, alignment: .topLeading)
            .transition(.opacity)
            .zIndex(5)
        }
    }

    private var topBar: some View {
        let glassTint = Color(red: 149 / 255.0, green: 169 / 255.0, blue: 192 / 255.0).opacity(0.42)
        let logoReflection = RadialGradient(
            colors: [
                Color.white.opacity(0.22),
                Color.white.opacity(0.07),
                Color.white.opacity(0.00)
            ],
            center: .topLeading,
            startRadius: 0,
            endRadius: 52
        )
        let topNavBorder = LinearGradient(
            colors: [
                Color.white.opacity(0.42),
                Color.white.opacity(0.16),
                Color.white.opacity(0.04),
                Color.white.opacity(0.00)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        return HStack(alignment: .center, spacing: 8) {
            Button {
                openSection(.emergency)
            } label: {
                Image(systemName: "sparkle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white)
                    .foregroundColor(Color.white)
                    .frame(width: 47, height: 47)
                    .background {
                        ZStack {
                            Circle().fill(.ultraThinMaterial)
                            Circle().fill(glassTint)
                            Circle().fill(logoReflection)
                            Circle().stroke(topNavBorder, lineWidth: 1)
                        }
                        .allowsHitTesting(false)
                    }
                    .shadow(color: Color.black.opacity(0.05), radius: 5, y: 3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Emergency")

            HStack(spacing: 0) {
                topNavButton("Stats") {
                    openSection(.report)
                }
                topNavButton("Plan") {
                    openSection(.modes)
                }
                topNavButton("Timer") {
                    openSection(.timer)
                }
            }
            .padding(.horizontal, 22)
            .frame(width: 236, height: 47)
            .background {
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(glassTint)
                    GlassCornerHighlight(width: 78, height: 30, xOffset: -79, yOffset: -15)
                        .clipShape(Capsule())
                    Capsule().stroke(topNavBorder, lineWidth: 1)
                }
                .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(0.05), radius: 5, y: 3)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(width: 291, height: 47)
    }

    private func topNavButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.blankInter(size: 15, weight: .regular, relativeTo: .subheadline))
                .foregroundStyle(Color.white)
                .foregroundColor(Color.white)
                .frame(width: 64, height: 47)
                .contentShape(Rectangle())
        }
        .frame(width: 64, height: 47)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
    }

    private func openSection(_ section: HomeSection) {
        if section == .modes, sessionStore.pinProtectionEnabled {
            unlockAdvancedSettings {
                withAnimation(.easeInOut(duration: 0.35)) {
                    activeSection = section
                }
            }
            return
        }
        withAnimation(.easeInOut(duration: 0.35)) {
            activeSection = section
        }
    }

    private func unlockAdvancedSettings(onSuccess: @escaping () -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            message = "Device passcode is required for PIN protection."
            messageAction = nil
            return
        }
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock Blanked advanced settings."
        ) { success, _ in
            Task { @MainActor in
                if success {
                    onSuccess()
                } else {
                    message = "Advanced settings stayed locked."
                    messageAction = nil
                }
            }
        }
    }

    private func closeSection() {
        withAnimation(.easeInOut(duration: 0.35)) {
            activeSection = nil
        }
    }

    @ViewBuilder
    private func topHomePanel(width: CGFloat) -> some View {
        EmptyView()
    }

    @ViewBuilder
    private func minimalHome(layout: HomeLayoutMetrics) -> some View {
        if sessionStore.isBlankActive {
            activeMinimalHome(layout: layout)
        } else {
            idleMinimalHome(layout: layout)
        }
    }

    private func idleMinimalHome(layout: HomeLayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
                minimalStartRow

                minimalHomeRow("stats", color: BlankColors.minimalSecondary) {
                    openSection(.report)
                }

                minimalHomeRow("plan", color: BlankColors.minimalSecondary) {
                    openSection(.modes)
                }

                minimalHomeRow("timer", color: BlankColors.minimalSecondary) {
                    openSection(.timer)
                }

                minimalHomeRow("settings", color: BlankColors.minimalSecondary) {
                    openSection(.settings)
                }

                minimalStatus

                HStack(spacing: 18) {
                    minimalUtilityRow("assistant") {
                        showingAssistantConnect = true
                    }

                    #if targetEnvironment(simulator)
                    minimalUtilityRow("onboarding") {
                        openOnboardingDemo()
                    }

                    minimalUtilityRow("pro") {
                        enableDemoPro()
                    }
                    #endif
                }
                .padding(.top, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.bottom, layout.bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private func activeMinimalHome(layout: HomeLayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            Text("blank is active.")
                .font(.blankInter(size: 42, weight: .bold, relativeTo: .largeTitle))
                .tracking(-1.1)
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 0)

            HStack(alignment: .bottom, spacing: 18) {
                Button("again") {
                    openSection(.timer)
                }
                .font(.blankInter(size: 40, weight: .bold, relativeTo: .title))
                .tracking(-0.8)
                .foregroundStyle(Color.white)
                .frame(minWidth: 44, minHeight: 52, alignment: .leading)
                .buttonStyle(.plain)

                minimalStartRow
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.bottom, layout.bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func minimalHomeRow(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.blankInter(size: 40, weight: .bold, relativeTo: .title))
                .foregroundStyle(color)
                .tracking(-0.6)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var minimalStartRow: some View {
        let isActive = sessionStore.isBlankActive
        let title = isActive
            ? (sessionStore.hardBlankActive ? "blank active" : "quit")
            : "blank"
        let titleColor = isActive ? BlankColors.newLookDarkSecondary : BlankColors.minimalInk

        return Button {
            guard !isActive else { return }
            let result = withAnimation(.easeInOut(duration: 0.65)) {
                sessionStore.activateBlank()
            }
            screenTimeBlocker.apply(isBlankActive: sessionStore.isBlankActive)
            setMessage(for: result)
        } label: {
            Text(title)
                .font(.blankInter(size: 40, weight: .bold, relativeTo: .title))
                .foregroundStyle(titleColor)
                .tracking(-0.6)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomLeading) {
            if isActive, !sessionStore.hardBlankActive {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: proxy.size.width * unblankHoldProgress, height: 2)
                        .frame(maxHeight: .infinity, alignment: .bottomLeading)
                }
                .allowsHitTesting(false)
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 20, maximumDistance: .infinity)
                .onEnded { _ in
                    guard isActive, !sessionStore.hardBlankActive else { return }
                    scheduleDelayedManualUnlock()
                    unblankHoldProgress = 0
                    isAnimatingUnblankHold = false
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard isActive, !sessionStore.hardBlankActive, !isAnimatingUnblankHold else { return }
                    isAnimatingUnblankHold = true
                    unblankHoldProgress = 0
                    withAnimation(.linear(duration: 20)) {
                        unblankHoldProgress = 1
                    }
                }
                .onEnded { _ in
                    isAnimatingUnblankHold = false
                    withAnimation(.easeOut(duration: 0.18)) {
                        unblankHoldProgress = 0
                    }
                }
        )
    }

    @ViewBuilder
    private var minimalStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            if sessionStore.isBlankActive,
               sessionStore.blankActiveUntil == nil,
               let blankActiveSince = sessionStore.blankActiveSince {
                Text(elapsedText(since: blankActiveSince))
                    .font(.blankInter(size: 14, weight: .semibold, relativeTo: .footnote))
                    .monospacedDigit()
            }

            if let schedulePausedUntil = sessionStore.schedulePausedUntil, now < schedulePausedUntil {
                Text("Schedule paused \(remainingText(until: schedulePausedUntil))")
                    .font(.blankInter(size: 13, relativeTo: .footnote))
            }

            if let message {
                if let messageAction {
                    Button {
                        resolve(messageAction)
                    } label: {
                        Text(message)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(message)
                        .multilineTextAlignment(.leading)
                }
            }

            if let cooldownText {
                Text(cooldownText)
                    .monospacedDigit()
            } else if let timerCountdownText {
                Text(timerCountdownText)
                    .monospacedDigit()
            }
        }
        .font(.blankInter(size: 13, relativeTo: .footnote))
        .foregroundStyle(BlankColors.minimalSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 12)
    }

    private func minimalUtilityRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.blankInter(size: 13, weight: .semibold, relativeTo: .footnote))
            .foregroundStyle(BlankColors.minimalSecondary)
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .buttonStyle(.plain)
    }

    private func centerContent(maxWidth: CGFloat, actionWidth: CGFloat) -> some View {
        VStack(spacing: 28) {
            Text(homeTagline)
                .font(.blankInter(size: 34, weight: .medium, relativeTo: .largeTitle))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.82)

            bottomAction(width: actionWidth)
        }
        .frame(maxWidth: maxWidth)
    }

    @ViewBuilder
    private var centerStatus: some View {
        VStack(spacing: 8) {
            if sessionStore.isBlankActive,
               sessionStore.blankActiveUntil == nil,
               let blankActiveSince = sessionStore.blankActiveSince {
                Text(elapsedText(since: blankActiveSince))
                    .font(.blankInter(size: 16, weight: .semibold, relativeTo: .headline))
                    .foregroundStyle(Color.white.opacity(0.86))
                    .monospacedDigit()
                if let schedulePausedUntil = sessionStore.schedulePausedUntil, now < schedulePausedUntil {
                    Text("Schedule paused \(remainingText(until: schedulePausedUntil))")
                        .font(.blankInter(size: 13, relativeTo: .footnote))
                        .foregroundStyle(Color.white.opacity(0.58))
                }
            }

            if let message {
                if let messageAction {
                    Button {
                        resolve(messageAction)
                    } label: {
                        Text(message)
                            .font(.blankInter(size: 13, weight: .semibold, relativeTo: .footnote))
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(sessionStore.isBlankActive ? Color.white.opacity(0.72) : BlankColors.mutedInk)
                } else {
                    Text(message)
                        .font(.blankInter(size: 13, relativeTo: .footnote))
                        .foregroundStyle(sessionStore.isBlankActive ? Color.white.opacity(0.72) : BlankColors.mutedInk)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
            }

        }
    }

    private func bottomAction(width: CGFloat) -> some View {
        VStack(spacing: 12) {
            let buttonWidth = sessionStore.isBlankActive ? min(width, 244) : min(width, 184)
            Button(sessionStore.isBlankActive ? (sessionStore.hardBlankActive ? "Hard Blanked" : "Hold to Unblank") : "Start Blanked") {
                if sessionStore.isBlankActive {
                    return
                } else {
                    let result = withAnimation(.easeInOut(duration: 0.65)) {
                        sessionStore.activateBlank()
                    }
                    screenTimeBlocker.apply(isBlankActive: sessionStore.isBlankActive)
                    setMessage(for: result)
                }
            }
            .buttonStyle(HomeBlankButtonStyle())
            .frame(width: buttonWidth)
            .opacity(sessionStore.hardBlankActive ? 0.86 : 1)
            .overlay(alignment: .leading) {
                if sessionStore.isBlankActive, !sessionStore.hardBlankActive {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: proxy.size.width * unblankHoldProgress)
                            .frame(maxHeight: .infinity, alignment: .leading)
                    }
                    .clipShape(Capsule())
                    .allowsHitTesting(false)
                }
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 20, maximumDistance: .infinity)
                    .onEnded { _ in
                        guard sessionStore.isBlankActive, !sessionStore.hardBlankActive else { return }
                        scheduleDelayedManualUnlock()
                        unblankHoldProgress = 0
                        isAnimatingUnblankHold = false
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard sessionStore.isBlankActive, !sessionStore.hardBlankActive, !isAnimatingUnblankHold else { return }
                        isAnimatingUnblankHold = true
                        unblankHoldProgress = 0
                        withAnimation(.linear(duration: 20)) {
                            unblankHoldProgress = 1
                        }
                    }
                    .onEnded { _ in
                        isAnimatingUnblankHold = false
                        withAnimation(.easeOut(duration: 0.18)) {
                            unblankHoldProgress = 0
                        }
                    }
            )

            if sessionStore.hardBlankActive {
                Button {
                    openSection(.emergency)
                } label: {
                    Text("Emergency unlock only")
                        .font(.blankInter(size: 13, weight: .semibold, relativeTo: .footnote))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                .buttonStyle(.plain)
            }

            if let cooldownText {
                Text(cooldownText)
                    .font(.blankInter(size: 12, weight: .semibold, relativeTo: .caption))
                    .monospacedDigit()
                    .foregroundStyle(sessionStore.isBlankActive ? Color.white.opacity(0.62) : BlankColors.mutedInk)
            } else if let timerCountdownText {
                Text(timerCountdownText)
                    .font(.blankInter(size: 12, weight: .semibold, relativeTo: .caption))
                    .monospacedDigit()
                    .foregroundStyle(sessionStore.isBlankActive ? Color.white.opacity(0.62) : BlankColors.mutedInk)
            }
        }
    }

    private func bottomShortcutBar(width: CGFloat) -> some View {
        HStack {
            #if targetEnvironment(simulator)
            footerShortcut(title: "Onboarding", icon: "rectangle.on.rectangle") {
                openOnboardingDemo()
            }

            footerShortcut(title: "Pro", icon: "sparkles") {
                enableDemoPro()
            }
            #endif

            footerShortcut(title: "Assistant", icon: "message") {
                showingAssistantConnect = true
            }
        }
        .frame(width: min(width, isSimulatorBuild ? 318 : 150), height: 44)
    }

    private func footerShortcut(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.blankInter(size: 12, weight: .semibold, relativeTo: .caption))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(Color.white.opacity(0.72))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func applyScreenTimeControls() {
        screenTimeBlocker.updateAdvancedControls(
            allowOnlyModeEnabled: sessionStore.allowOnlyModeEnabled,
            adultContentBlockingEnabled: sessionStore.adultContentBlockingEnabled
        )
        screenTimeBlocker.apply(isBlankActive: sessionStore.isBlankActive)
        sessionStore.refreshDailyLimitMonitoring()
    }

    private func evaluateBAIProactiveSignals() {
        let system = aiSystem
        let summaries = healthKitStore.summaries
        let selectionCount = sessionStore.selectionCount
        let screenTimeAuthorized = screenTimeBlocker.authorizationStatus == .approved
        let isBlankActive = sessionStore.isBlankActive

        Task {
            await BAIProactiveSignalEngine.evaluate(
                system: system,
                healthSummaries: summaries,
                selectionCount: selectionCount,
                screenTimeAuthorized: screenTimeAuthorized,
                isBlankActive: isBlankActive
            )
        }
    }

    private var isSimulatorBuild: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private var screenTimePermissionLabel: String {
        switch screenTimeBlocker.authorizationStatus {
        case .approved:
            return "connected"
        case .denied:
            return "denied"
        case .notDetermined:
            return "not connected"
        @unknown default:
            return "unknown"
        }
    }

    private var healthPermissionLabel: String {
        switch healthKitStore.state {
        case .connected:
            return "connected"
        case .requesting:
            return "requesting"
        case .notRequested:
            return "not connected"
        case .unavailable:
            return "not available"
        case .failed:
            return "denied"
        }
    }

    private func requestScreenTimePermission() {
        Task { @MainActor in
            _ = await screenTimeBlocker.requestAuthorization()
            applyScreenTimeControls()
        }
    }

    private func openOnboardingDemo() {
        withAnimation(.easeInOut(duration: 0.45)) {
            _ = sessionStore.deactivateBlank(entryMode: .app, endedReason: .manual)
            sessionStore.setupComplete = false
        }
        screenTimeBlocker.clear()
        message = nil
        messageAction = nil
        onOpenOnboardingDemo()
    }

    private func enableDemoPro() {
        purchaseStore.enableDemoProAccess()
        message = "Demo Pro enabled."
        messageAction = nil
    }

    private func performEmergencyUnlock() -> Bool {
        cancelDelayedManualUnlock()
        let unlocked = withAnimation(.easeInOut(duration: 0.65)) {
            sessionStore.deactivateForEmergency()
        }
        if unlocked {
            screenTimeBlocker.clear()
            Task {
                await BlankFunnelAnalytics.track(
                    "relapse_attempt",
                    properties: [
                        "source": "emergency",
                        "remaining_after": sessionStore.emergencyUnlocksRemaining
                    ]
                )
            }
            message = nil
            messageAction = nil
            closeSection()
            showingRelapseReview = true
        }
        return unlocked
    }

    private func scheduleDelayedManualUnlock() {
        guard delayedManualUnlockTask == nil else { return }
        let cooldownSeconds = sessionStore.manualUnblankCooldownSeconds
        let unlockAt = Date().addingTimeInterval(TimeInterval(cooldownSeconds))
        delayedManualUnlockAt = unlockAt
        updateDelayedUnlockMessage(now: Date())
        Task {
            await BlankFunnelAnalytics.track(
                "relapse_attempt",
                properties: ["source": "hold_to_unblank", "delay_seconds": cooldownSeconds]
            )
        }
        delayedManualUnlockTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0, cooldownSeconds)) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            let result = withAnimation(.easeInOut(duration: 0.65)) {
                sessionStore.deactivateBlank(entryMode: .app, endedReason: .manual)
            }
            screenTimeBlocker.clear()
            delayedManualUnlockAt = nil
            delayedManualUnlockTask = nil
            setMessage(for: result)
            showingRelapseReview = true
        }
    }

    private func cancelDelayedManualUnlock() {
        delayedManualUnlockTask?.cancel()
        delayedManualUnlockTask = nil
        delayedManualUnlockAt = nil
    }

    private func updateDelayedUnlockMessage(now: Date) {
        guard let delayedManualUnlockAt else { return }
        let seconds = max(0, Int(ceil(delayedManualUnlockAt.timeIntervalSince(now))))
        message = seconds > 0 ? "Cooldown active" : "Unlocking..."
        messageAction = nil
    }

    private var cooldownText: String? {
        guard let delayedManualUnlockAt else { return nil }
        let seconds = max(0, Int(ceil(delayedManualUnlockAt.timeIntervalSince(now))))
        return "Cooldown: \(formatCooldown(seconds))"
    }

    private var timerCountdownText: String? {
        guard sessionStore.isBlankActive, let blankActiveUntil = sessionStore.blankActiveUntil else { return nil }
        let seconds = max(0, Int(ceil(blankActiveUntil.timeIntervalSince(now))))
        return "Timer: \(formatCooldown(seconds))"
    }

    private func formatCooldown(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return "\(String(format: "%02d", minutes)):\(String(format: "%02d", remainingSeconds))"
    }

    private func startTimedBlank(minutes: Int, hardMode: Bool) {
        let result = withAnimation(.easeInOut(duration: 0.65)) {
            sessionStore.activateBlank(durationMinutes: minutes, hardMode: hardMode)
        }
        screenTimeBlocker.apply(isBlankActive: sessionStore.isBlankActive)
        setMessage(for: result)
        closeSection()
    }

    private func processPendingBlockConfigurationIfNeeded() {
        guard sessionStore.shouldOpenBlockConfiguration else { return }
        if sessionStore.pendingPlanAppNames.isEmpty && sessionStore.pendingPlanModeName == nil {
            openSection(.modes)
        } else {
            contextualPlanSelection = sessionStore.pendingPlanStartsFreshSelection ? FamilyActivitySelection() : sessionStore.selection
            showingContextualAppPicker = true
        }
        sessionStore.shouldOpenBlockConfiguration = false
    }

    private var assistantActionConfirmationMessage: String {
        guard let action = sessionStore.pendingAssistantAction else {
            return "No action is waiting for confirmation."
        }
        switch action {
        case .startProtection(let minutes, _, let appNames):
            let target = appNames.isEmpty ? "the current app selection" : appNames.joined(separator: ", ")
            return minutes.map { "Start protection now for \($0) minutes using \(target)?" } ?? "Start protection now using \(target), with no duration added?"
        case .activateMode(let name, let minutes, _, _):
            return minutes.map { "Start \(name) mode for \($0) minutes?" } ?? "Start \(name) mode now, without adding a duration?"
        case .switchMode(let name):
            return "Switch to \(name) mode?"
        case .applySchedule(let name, let start, let end, _, let days, _):
            return "Add \(name) as a new protection window from \(formatMinute(start)) to \(formatMinute(end)) for \(days) days?"
        case .setDailyLimit(let minutes, _):
            return minutes.map { "Set a daily limit of \($0) minutes?" } ?? "Set a daily limit after you choose its duration?"
        case .allowOnly:
            return "Enable Allow Only?"
        case .adultFilter:
            return "Enable adult web protection?"
        case .pauseRules(let hours):
            return "Pause protection rules for \(hours) hours?"
        case .disablePause:
            return "Resume protection rules?"
        case .applyAIPlan:
            return "Apply the recommended adaptive plan?"
        case .openAppPicker:
            return "Open the app picker to choose what Blanked can protect?"
        case .configureAndOpenAppPicker(let appNames, let durationMinutes, _, let schedule):
            if let schedule {
                return "Choose the apps for \(schedule.name) from \(formatMinute(schedule.startMinute)) to \(formatMinute(schedule.endMinute))?"
            }
            let target = appNames.isEmpty ? "the requested apps" : appNames.joined(separator: ", ")
            return durationMinutes.map { "Choose \(target) and start protection for \($0) minutes?" } ?? "Choose \(target) and start protection now?"
        case .configureAndOpenDailyLimitPicker(let appNames, let minutes):
            let target = appNames.isEmpty ? "the requested apps" : appNames.joined(separator: ", ")
            return "Choose \(target) and set a daily limit of \(minutes) minutes?"
        case .requestScreenTimePermission:
            return "Request Screen Time permission?"
        }
    }

    private func confirmPendingAssistantAction() {
        guard let pendingAction = sessionStore.pendingAssistantAction else { return }
        sessionStore.clearAssistantActionConfirmation()

        switch pendingAction {
        case .startProtection(let minutes, let hardMode, let appNames):
            guard sessionStore.restoreSavedSelectionForAssistant(appNames: appNames) else {
                sessionStore.requestBlockConfiguration(
                    appNames: appNames,
                    startsFreshSelection: !appNames.isEmpty,
                    shouldActivate: true,
                    durationMinutes: minutes,
                    hardMode: hardMode
                )
                return
            }
            let result = sessionStore.activateBlank(
                durationMinutes: minutes,
                hardMode: hardMode,
                usePendingWidgetTimer: false
            )
            applyScreenTimeControls()
            setMessage(for: result)
        case .activateMode(let name, let minutes, let hardMode, let appNames):
            if !sessionStore.selectBestMode(matching: name) {
                guard sessionStore.restoreSavedSelectionForAssistant(appNames: appNames) else {
                    sessionStore.requestBlockConfiguration(
                        appNames: appNames,
                        startsFreshSelection: !appNames.isEmpty,
                        modeName: name,
                        shouldActivate: true,
                        durationMinutes: minutes,
                        hardMode: hardMode
                    )
                    return
                }
                sessionStore.createOrUpdateMode(named: name, selection: sessionStore.selection, appNames: appNames)
            }
            let result = sessionStore.activateBlank(
                durationMinutes: minutes,
                hardMode: hardMode,
                usePendingWidgetTimer: false
            )
            applyScreenTimeControls()
            setMessage(for: result)
        case .switchMode(let name):
            if sessionStore.selectBestMode(matching: name) {
                message = "\(name) mode selected."
                messageAction = nil
            } else if sessionStore.hasSelectedApps {
                sessionStore.createOrUpdateMode(named: name, selection: sessionStore.selection)
                message = "\(name) mode saved."
                messageAction = nil
            } else {
                sessionStore.requestBlockConfiguration(startsFreshSelection: true, modeName: name)
            }
        case .applySchedule(let name, let start, let end, let weekdays, let days, let appNames):
            guard sessionStore.restoreSavedSelectionForAssistant(appNames: appNames) else {
                sessionStore.requestBlockConfiguration(
                    appNames: appNames,
                    startsFreshSelection: !appNames.isEmpty,
                    schedule: PendingPlanSchedule(
                        name: name,
                        startMinute: start,
                        endMinute: end,
                        weekdays: weekdays,
                        durationDays: days
                    )
                )
                return
            }
            sessionStore.applyAdaptivePlan(
                startMinute: start,
                endMinute: end,
                durationDays: days,
                activateCurrentWindow: false,
                name: name,
                weekdays: weekdays
            )
            applyScreenTimeControls()
            message = "Added \(name) without replacing your existing protection windows."
            messageAction = nil
        case .setDailyLimit(let minutes, let appNames):
            guard let minutes else {
                message = "Tell BM how many minutes per day you want to allow before activating this limit."
                messageAction = nil
                return
            }
            guard sessionStore.restoreSavedSelectionForAssistant(appNames: appNames) else {
                sessionStore.requestBlockConfiguration(appNames: appNames, startsFreshSelection: !appNames.isEmpty)
                return
            }
            sessionStore.dailyLimitMinutes = minutes
            sessionStore.dailyLimitEnabled = true
            sessionStore.refreshDailyLimitMonitoring()
            applyScreenTimeControls()
            message = "Daily limit set to \(minutes) minutes."
            messageAction = nil
        case .allowOnly:
            sessionStore.allowOnlyModeEnabled = true
            applyScreenTimeControls()
        case .adultFilter:
            sessionStore.adultContentBlockingEnabled = true
            applyScreenTimeControls()
        case .pauseRules(let hours):
            sessionStore.enableVacationMode(hours: hours)
            applyScreenTimeControls()
        case .disablePause:
            sessionStore.disableVacationMode()
            applyScreenTimeControls()
        case .applyAIPlan:
            sessionStore.applyAIPlan()
            applyScreenTimeControls()
        case .openAppPicker(let appNames):
            sessionStore.requestBlockConfiguration(appNames: appNames, startsFreshSelection: true)
        case .configureAndOpenAppPicker(let appNames, let durationMinutes, let hardMode, let schedule):
            sessionStore.requestBlockConfiguration(
                appNames: appNames,
                startsFreshSelection: true,
                shouldActivate: schedule == nil,
                durationMinutes: durationMinutes,
                hardMode: hardMode,
                schedule: schedule
            )
        case .configureAndOpenDailyLimitPicker(let appNames, let minutes):
            sessionStore.requestBlockConfiguration(
                appNames: appNames,
                startsFreshSelection: true,
                dailyLimitMinutes: minutes
            )
        case .requestScreenTimePermission:
            Task {
                _ = await screenTimeBlocker.requestAuthorization()
                applyScreenTimeControls()
            }
        }
    }

    private var contextualPickerHeaderText: String {
        if let modeName = sessionStore.pendingPlanModeName {
            return "Create \(modeName) mode"
        }
        return "Select \(formattedPendingPlanAppNames) to apply this plan."
    }

    private var contextualPickerFooterText: String {
        guard let modeName = sessionStore.pendingPlanModeName else {
            return "Blanked will use this selection for the plan."
        }
        if sessionStore.pendingPlanShouldActivate {
            return "Choose apps once. Blanked will save \(modeName) and start it now. Next time, the WhatsApp button starts this mode directly."
        }
        return "Choose apps once. Blanked will save \(modeName) so WhatsApp can start it directly next time."
    }

    private var formattedPendingPlanAppNames: String {
        let cleaned = sessionStore.pendingPlanAppNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "the recommended apps" }
        guard cleaned.count > 1 else { return cleaned[0] }
        return "\(cleaned.dropLast().joined(separator: ", ")) and \(cleaned.last ?? "")"
    }

    private var riskWindowText: String {
        aiSystem.forecast.riskWindow
    }

    private func configuredWhatsAppNumber() -> String? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "BlankWhatsAppPhoneNumber") as? String else { return nil }
        let digits = rawValue.filter(\.isNumber)
        return digits.isEmpty ? nil : digits
    }

    private func configuredSMSNumber() -> String? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "BlankSMSPhoneNumber") as? String else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.contains("$(") ? nil : trimmed
    }

    private func assistantContextPayload() -> [String: Any] {
        let system = aiSystem
        var payload: [String: Any] = [
            "is_blank_active": sessionStore.isBlankActive,
            "has_selected_apps": sessionStore.hasSelectedApps,
            "selection_count": sessionStore.selectionCount,
            "screen_time_authorized": screenTimeBlocker.authorizationStatus == .approved,
            "emergency_unlocks_remaining": sessionStore.emergencyUnlocksRemaining,
            "vacation_mode_active": sessionStore.isVacationModeActive,
            "adherence_score": system.profile.adherenceScore,
            "weekly_protected_minutes": system.profile.weeklyProtectedMinutes,
            "weekly_break_count": system.profile.weeklyBreakCount,
            "risk_window": system.forecast.riskWindow,
            "recommended_duration_minutes": system.plan.recommendedDurationMinutes,
            "weekly_goal": system.plan.weeklyGoal,
            "mode_name": sessionStore.currentMode.name,
            "available_modes": sessionStore.focusModes.map(\.name),
            "available_mode_catalog": sessionStore.assistantModeCatalog(),
            "app_presence": BlankmindAppPresence.payload(
                appReady: sessionStore.hasSelectedApps && screenTimeBlocker.authorizationStatus == .approved
            ),
            "schedule": sessionStore.assistantScheduleContext(),
            "allow_only_mode_enabled": sessionStore.allowOnlyModeEnabled,
            "adult_content_blocking_enabled": sessionStore.adultContentBlockingEnabled,
            "daily_limit_enabled": sessionStore.dailyLimitEnabled,
            "daily_limit_minutes": sessionStore.dailyLimitMinutes,
            "memory": BlankedAgentMemory.snapshot(system: system),
        ]
        if let strongestWindow = system.profile.strongestWindow {
            payload["strongest_hour"] = strongestWindow
        }
        return payload
    }

    private func syncAssistantContext() {
        let code = assistantConnectCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let channel = assistantPreferredChannel == "whatsApp" ? "whatsapp" : assistantPreferredChannel.lowercased()
        guard !code.isEmpty, channel == "whatsapp" || channel == "sms" else { return }
        let payload = assistantContextPayload()
        Task {
            await AssistantContextSyncClient().sync(
                connectCode: code,
                channel: channel,
                phoneNumber: assistantPhoneNumber,
                payload: payload
            )
        }
    }

    private var relapseIntervention: RelapseIntervention {
        guard let recoveryScore = homeRecoveryScore(), recoveryScore < 45 else {
            return aiSystem.relapseIntervention
        }
        return RelapseIntervention(
            headline: "Make this easier, not broken.",
            cost: "Low recovery days are when automatic scrolling wins faster.",
            alternative: "Hold 5 more minutes, then do a shorter next block."
        )
    }

    private func homeRecoveryScore() -> Int? {
        let recent = Array(healthKitStore.summaries.suffix(7))
        var scoreParts: [Int] = []
        let sleepValues = recent.compactMap(\.sleepMinutes)
        let stepValues = recent.compactMap(\.steps)
        let workoutValues = recent.compactMap(\.workoutMinutes)

        if let averageSleep = average(sleepValues) {
            scoreParts.append(min(100, max(0, Int(Double(averageSleep) / (8 * 60) * 100))))
        }
        if let averageSteps = average(stepValues) {
            scoreParts.append(min(100, max(0, Int(Double(averageSteps) / 8000 * 100))))
        }
        if let averageWorkout = average(workoutValues) {
            scoreParts.append(min(100, max(0, Int(Double(averageWorkout) / 30 * 100))))
        }
        return average(scoreParts)
    }

    private func average(_ values: [Int]) -> Int? {
        values.isEmpty ? nil : values.reduce(0, +) / values.count
    }

    private func resolve(_ action: HomeMessageAction) {
        switch action {
        case .screenTime:
            Task { @MainActor in
                let approved = await screenTimeBlocker.requestAuthorization()
                message = approved ? nil : "Screen Time is still pending."
                messageAction = approved ? nil : .screenTime
            }
        case .relinkNfc:
            showingRelink = true
        case .selectApps:
            showingPicker = true
        }
    }

    private func scanTag() {
        nfcReader.scan { result in
            Task { @MainActor in
                switch result {
                case .success(let uid):
                    let nfcResult = withAnimation(.easeInOut(duration: 0.65)) {
                        sessionStore.handleNfcTag(uid: uid)
                    }
                    screenTimeBlocker.apply(isBlankActive: sessionStore.isBlankActive)
                    setMessage(for: nfcResult)
                case .failure(let error):
                    message = error.localizedDescription
                    messageAction = nil
                }
            }
        }
    }

    private func openWidgetScanIfNeeded() {
        guard scenePhase == .active, sessionStore.shouldScanBlankFromWidget else { return }
        guard sessionStore.isBlankActive else {
            sessionStore.shouldScanBlankFromWidget = false
            return
        }
        sessionStore.shouldScanBlankFromWidget = false
        DispatchQueue.main.async {
            scanTag()
        }
    }

    private func showPendingBAIProactiveAlertIfNeeded() {
        let defaults = BlankSharedState.defaults
        guard let id = defaults.string(forKey: "blankBAIProactiveAlertId"),
              id != defaults.string(forKey: "blankBAIProactiveAlertConsumedId"),
              let body = defaults.string(forKey: "blankBAIProactiveAlertBody"),
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        let createdAt = defaults.double(forKey: "blankBAIProactiveAlertCreatedAt")
        guard createdAt <= 0 || Date().timeIntervalSince1970 - createdAt < 24 * 60 * 60 else {
            defaults.set(id, forKey: "blankBAIProactiveAlertConsumedId")
            return
        }
        message = body
        messageAction = nil
        defaults.set(id, forKey: "blankBAIProactiveAlertConsumedId")
    }

    private func setMessage(for result: SessionStore.NfcResult) {
        switch result {
        case .tagRegistered:
            message = "NFC registered."
            messageAction = nil
        case .blanked, .unblanked:
            message = nil
            messageAction = nil
        case .schedulePaused:
            message = "Apps unlocked for 5 minutes."
            messageAction = nil
        case .wrongTag:
            message = "That NFC is not your Blank tag."
            messageAction = nil
        case .noAppsSelected:
            message = "No apps selected"
            messageAction = .selectApps
        case .hardBlankLocked:
            message = "Hard Blanked: use Emergency to unlock early."
            messageAction = nil
        }
    }

    private func elapsedText(since date: Date) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(date)))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func remainingText(until date: Date) -> String {
        let remaining = max(0, Int(date.timeIntervalSince(now)))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

private struct HomeLayoutMetrics {
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let configTopPadding: CGFloat
    let bottomPadding: CGFloat
    let messageMaxWidth: CGFloat
    let actionWidth: CGFloat
    let centerX: CGFloat
    let topBarCenterY: CGFloat
    let messageCenterY: CGFloat
    let bottomShortcutCenterY: CGFloat

    init(size: CGSize, safeAreaInsets: EdgeInsets) {
        let width = max(size.width, 320)
        let height = max(size.height, 600)
        let topSafeArea = safeAreaInsets.top > 0 ? safeAreaInsets.top : 44
        horizontalPadding = min(max(width * 0.075, 28), 36)
        topPadding = topSafeArea + 26
        configTopPadding = topPadding + 47 + 14
        bottomPadding = max(safeAreaInsets.bottom + 18, 34)
        messageMaxWidth = min(max(width - horizontalPadding * 2, 280), 350)
        actionWidth = min(max(width - horizontalPadding * 2, 260), 342)
        centerX = width / 2
        topBarCenterY = topPadding + 47 / 2
        messageCenterY = height * 0.52
        bottomShortcutCenterY = height - bottomPadding - 22
    }
}

private struct HomeBlankButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let glassTint = Color(red: 186 / 255.0, green: 186 / 255.0, blue: 188 / 255.0).opacity(configuration.isPressed ? 0.58 : 0.48)
        let capsuleBorder = LinearGradient(
            colors: [
                Color.white.opacity(0.42),
                Color.white.opacity(0.16),
                Color.white.opacity(0.04),
                Color.white.opacity(0.00)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        configuration.label
            .font(.blankInter(size: 16, weight: .regular, relativeTo: .headline))
            .foregroundStyle(Color.white)
            .foregroundColor(Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background {
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(glassTint)
                    GlassCornerHighlight(width: 78, height: 30, xOffset: -64, yOffset: -16)
                        .clipShape(Capsule())
                    Capsule().stroke(capsuleBorder, lineWidth: 1)
                }
                .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.02 : 0.05), radius: 5, y: 3)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

private struct GlassCornerHighlight: View {
    let width: CGFloat
    let height: CGFloat
    let xOffset: CGFloat
    let yOffset: CGFloat

    var body: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.24),
                        Color.white.opacity(0.08),
                        Color.white.opacity(0.00)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: max(width, height) / 2
                )
            )
            .frame(width: width, height: height)
            .offset(x: xOffset, y: yOffset)
    }
}

private enum HomeMessageAction {
    case screenTime
    case relinkNfc
    case selectApps
}

struct AppBackground: View {
    let isActive: Bool

    var body: some View {
        ZStack {
            Image(isActive ? "blank_home_background_active" : "blank_home_background_idle")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.75), value: isActive)
    }
}

private struct ModesList: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.blankMinimalAppearance) private var minimalAppearance
    @Binding var showingPicker: Bool
    let onFinish: () -> Void
    @State private var newModeName = ""
    @State private var showsManualPlanCreator = false
    @State private var windows: [BlankHabitWindow] = [BlankHabitWindow(name: "Routine 1", enabled: false)]
    private var textColor: Color { sessionStore.isBlankActive ? Color.white : BlankColors.ink }
    private var secondaryColor: Color { sessionStore.isBlankActive ? Color.white.opacity(0.70) : BlankColors.mutedInk }

    var body: some View {
        if minimalAppearance {
            newLookPlan
        } else {
            List {
            TopSheetHeader(
                title: "Plan",
                subtitle: "Protection, routines, safeguards.",
                titleColor: textColor,
                subtitleColor: secondaryColor
            )
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            baiPlanSummary
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            protectedAppsCapsule
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 8)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            planRoutineEditor
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            planAdvancedControls
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .padding(.bottom, 34)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .tint(textColor)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .background(Color.clear)
        }
        .preferredColorScheme(sessionStore.isBlankActive ? .dark : .light)
        .onAppear {
            windows = sessionStore.schedule.windows.isEmpty
                ? [BlankHabitWindow(name: "Routine 1", enabled: false)]
                : sessionStore.schedule.windows
        }
    }

    private var newLookPlan: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                TopSheetHeader(
                    title: "Plan",
                    subtitle: "",
                    titleColor: textColor,
                    subtitleColor: secondaryColor
                )
                .padding(.bottom, 34)

                Text(sessionStore.currentMode.name.lowercased())
                    .font(.blankInter(size: 32, weight: .bold, relativeTo: .title2))
                    .tracking(-0.8)
                    .foregroundStyle(textColor)

                Text(blockedAppsText)
                    .font(.blankInter(size: 16, weight: .medium, relativeTo: .body))
                    .foregroundStyle(secondaryColor)
                    .padding(.top, 4)

                newLookRule

                newLookPlanRow(title: "protected apps", detail: blockedAppsText) {
                    showingPicker = true
                    onFinish()
                }

                newLookPlanRow(title: "routines", detail: routineSummaryText) {}

                planRoutineEditor
                    .padding(.top, 20)

                planAdvancedControls
                    .padding(.top, 24)
                    .padding(.bottom, 34)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
    }

    private var newLookRule: some View {
        Rectangle()
            .fill(sessionStore.isBlankActive ? Color.white.opacity(0.16) : BlankColors.newLookRule)
            .frame(height: 1)
            .padding(.top, 26)
            .padding(.bottom, 8)
    }

    private func newLookPlanRow(title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(title)
                    .font(.blankInter(size: 24, weight: .bold, relativeTo: .title3))
                    .tracking(-0.45)
                    .foregroundStyle(textColor)
                Spacer(minLength: 8)
                Text(detail)
                    .font(.blankInter(size: 13, weight: .medium, relativeTo: .caption))
                    .foregroundStyle(secondaryColor)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func modeButton(_ mode: BlankFocusMode) -> some View {
        let isSelected = mode.id == sessionStore.currentModeId

        return Button {
            sessionStore.selectMode(mode.id)
            onFinish()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.name)
                        .font(.blankInter(size: 17, weight: .medium, relativeTo: .body))

                    Text(isSelected ? blockedAppsText : "Tap to activate this plan")
                        .font(.caption)
                        .foregroundStyle(isSelected ? secondaryColor.opacity(0.82) : secondaryColor)
                        .lineLimit(1)
                }

                Spacer()
            }
            .foregroundStyle(isSelected ? textColor.opacity(0.84) : textColor)
            .padding(.horizontal, 18)
            .frame(height: 68)
            .blankGlassCard(cornerRadius: 20, tintOpacity: isSelected ? 0.18 : 0.28)
        }
        .buttonStyle(.plain)
    }

    private var baiPlanSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Current protection")
                        .font(.blankInter(size: 23, weight: .semibold, relativeTo: .title3))
                    Text(sessionStore.currentMode.name)
                        .font(.blankInter(size: 15, weight: .medium, relativeTo: .body))
                        .foregroundStyle(secondaryColor)
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.semibold))
                    Text("Automatic")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(textColor)
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background { Capsule().fill(textColor.opacity(0.10)) }
            }

            HStack(spacing: 10) {
                planVisualTile(title: "Apps", value: "\(sessionStore.selectionCount)", symbol: "square.grid.2x2.fill")
                planVisualTile(title: "Rule", value: sessionStore.allowOnlyModeEnabled ? "Allow" : "Block", symbol: "shield.fill")
                planVisualTile(title: "Exit", value: sessionStore.hardBlankActive ? "Emergency" : "Hold", symbol: "hand.raised.fill")
            }
        }
        .foregroundStyle(textColor)
        .padding(18)
        .blankControlSurface(cornerRadius: 20, tintOpacity: 0.14, emphasized: true)
    }

    private var protectedAppsCapsule: some View {
        Button {
            showingPicker = true
            onFinish()
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "app.badge.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(textColor.opacity(0.10)))

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Protected apps")
                            .font(.blankInter(size: 18, weight: .semibold, relativeTo: .headline))
                        Text(blockedAppsText)
                            .font(.blankInter(size: 15, weight: .medium, relativeTo: .body))
                            .foregroundStyle(secondaryColor)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryColor)
                }

                HStack(spacing: 5) {
                    ForEach(0..<12, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(index < min(12, max(1, sessionStore.selectionCount)) ? textColor.opacity(0.42) : textColor.opacity(0.10))
                            .frame(height: 12)
                    }
                }
                .accessibilityHidden(true)
            }
            .foregroundStyle(textColor)
            .padding(18)
            .blankControlSurface(cornerRadius: 20, tintOpacity: 0.10)
        }
        .buttonStyle(.plain)
    }

    private func planVisualTile(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(textColor.opacity(0.84))
            Text(title)
                .font(.caption2)
                .foregroundStyle(secondaryColor)
            Text(value)
                .font(.blankInter(size: 15, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(textColor.opacity(0.075))
        }
    }

    private var planRoutineEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(textColor.opacity(0.10)))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recurring routines")
                            .font(.blankInter(size: 18, weight: .semibold, relativeTo: .headline))
                        Text(routineSummaryText)
                            .font(.blankInter(size: 15, weight: .medium, relativeTo: .body))
                            .foregroundStyle(secondaryColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }

                routineTimeline
            }
            .foregroundStyle(textColor)
            .padding(18)
            .blankControlSurface(cornerRadius: 20, tintOpacity: 0.10)

            VStack(spacing: 12) {
                ForEach($windows) { $window in
                    HabitWindowCard(
                        window: $window,
                        canDelete: windows.count > 1,
                        textColor: textColor,
                        secondaryColor: secondaryColor
                    ) {
                        deleteWindow(window.id)
                    }
                }
            }

            Button {
                addWindow()
            } label: {
                Label("Add manual routine", systemImage: "plus")
                    .font(.blankInter(size: 15, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(textColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .blankGlassCard(cornerRadius: 18, tintOpacity: 0.22)
            }
            .buttonStyle(.plain)

            VacationModeCard(
                textColor: textColor,
                secondaryColor: secondaryColor
            )

            Button {
                saveSchedule()
            } label: {
                TopSheetPrimaryButtonLabel(title: "Save plan")
            }
            .padding(.top, 2)
        }
    }

    private var routineTimeline: some View {
        HStack(spacing: 5) {
            ForEach(0..<7, id: \.self) { index in
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(enabledWindows.isEmpty ? textColor.opacity(0.10) : textColor.opacity(index < enabledWindows.count ? 0.46 : 0.18))
                        .frame(height: index < enabledWindows.count ? 28 : 15)
                    Text(shortWeekday(index))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(secondaryColor.opacity(0.84))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 50)
        .accessibilityLabel(routineSummaryText)
    }

    private var planAdvancedControls: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Manual plans")
                        .font(.blankInter(size: 13, weight: .semibold, relativeTo: .caption))
                        .foregroundStyle(secondaryColor)
                        .textCase(.uppercase)

                    ForEach(sessionStore.focusModes) { mode in
                        modeButton(mode)
                            .swipeActions {
                                Button(role: .destructive) {
                                    sessionStore.deleteMode(mode.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .disabled(sessionStore.focusModes.count <= 1)
                            }
                    }
                }

                manualPlanCreator

                AdvancedModeControls(
                    showingPicker: $showingPicker,
                    onFinish: onFinish,
                    textColor: textColor,
                    secondaryColor: secondaryColor
                )
            }
            .padding(.top, 10)
        } label: {
            HStack {
                Label("Safeguards", systemImage: "ellipsis.circle")
                    .font(.blankInter(size: 16, weight: .medium, relativeTo: .headline))
                Spacer()
                Text("Advanced")
                    .font(.caption)
                    .foregroundStyle(secondaryColor)
            }
        }
        .foregroundStyle(textColor)
        .padding(18)
        .blankControlSurface(cornerRadius: 20, tintOpacity: 0.08)
    }

    private var enabledWindows: [BlankHabitWindow] {
        windows.filter { $0.enabled }
    }

    private var routineSummaryText: String {
        let count = enabledWindows.count
        guard count > 0 else {
            return "No routine approved yet."
        }
        if count == 1, let first = enabledWindows.first {
            return "\(first.name): \(formatMinute(first.startMinute)) to \(formatMinute(first.endMinute))"
        }
        return "\(count) active routines. Configure each one below."
    }

    private func shortWeekday(_ index: Int) -> String {
        ["M", "T", "W", "T", "F", "S", "S"][index]
    }

    private func saveSchedule() {
        let normalized = windows.enumerated().map { index, window in
            BlankHabitWindow(
                id: window.id,
                name: window.name.isEmpty ? "Routine \(index + 1)" : window.name,
                enabled: window.enabled,
                startMinute: window.startMinute,
                endMinute: window.endMinute,
                weekdays: window.weekdays
            )
        }
        let first = normalized.first ?? BlankHabitWindow(enabled: false)
        sessionStore.schedule = BlankFocusSchedule(
            enabled: normalized.contains { $0.enabled },
            startMinute: first.startMinute,
            endMinute: first.endMinute,
            windows: normalized
        )
        onFinish()
    }

    private func addWindow() {
        let number = windows.count + 1
        windows.append(BlankHabitWindow(name: "Routine \(number)", enabled: true, startMinute: 9 * 60, endMinute: 10 * 60))
    }

    private func deleteWindow(_ id: UUID) {
        guard windows.count > 1 else { return }
        windows.removeAll { $0.id == id }
    }

    private var manualPlanCreator: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showsManualPlanCreator.toggle()
                }
            } label: {
                HStack {
                    Text("Add manual plan")
                        .font(.blankInter(size: 15, weight: .semibold, relativeTo: .subheadline))
                    Spacer()
                    Image(systemName: showsManualPlanCreator ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(secondaryColor)
                .padding(.horizontal, 18)
                .frame(height: 50)
                .blankGlassCard(cornerRadius: 18, tintOpacity: 0.16)
            }
            .buttonStyle(.plain)

            if showsManualPlanCreator {
                TextField("Plan name", text: $newModeName)
                    .font(.blankInter(size: 16, weight: .medium, relativeTo: .body))
                    .foregroundStyle(textColor)
                    .padding(.horizontal, 18)
                    .frame(height: 54)
                    .blankGlassCard(cornerRadius: 18, tintOpacity: 0.20)

                Button {
                    sessionStore.createMode(named: newModeName)
                    newModeName = ""
                    showsManualPlanCreator = false
                } label: {
                    TopSheetPrimaryButtonLabel(title: "Save manual plan")
                }
                .disabled(newModeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(newModeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            }
        }
    }

    private var blockedAppsText: String {
        let count = sessionStore.selectionCount
        return "\(count) \(count == 1 ? "app" : "apps") blocked"
    }
}

private struct AdvancedModeControls: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Binding var showingPicker: Bool
    let onFinish: () -> Void
    let textColor: Color
    let secondaryColor: Color

    private static func cooldownSettingText(for seconds: Int) -> String {
        if seconds == 0 { return "Off" }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes == 0 { return "\(remainingSeconds)s" }
        return remainingSeconds == 0 ? "\(minutes)m" : "\(minutes)m \(remainingSeconds)s"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Advanced")
                .font(.blankInter(size: 15, weight: .semibold, relativeTo: .headline))
                .foregroundStyle(secondaryColor)

            Toggle("Allow Only", isOn: $sessionStore.allowOnlyModeEnabled)
                .advancedControlStyle(textColor: textColor)

            Toggle("Adult website filter", isOn: $sessionStore.adultContentBlockingEnabled)
                .advancedControlStyle(textColor: textColor)

            Toggle("PIN protection", isOn: $sessionStore.pinProtectionEnabled)
                .advancedControlStyle(textColor: textColor)

            Stepper(value: $sessionStore.manualUnblankCooldownSeconds, in: 0...300, step: 15) {
                HStack {
                    Text("Unblank cooldown")
                    Spacer()
                    Text(Self.cooldownSettingText(for: sessionStore.manualUnblankCooldownSeconds))
                        .monospacedDigit()
                        .foregroundStyle(secondaryColor)
                }
            }
            .font(.blankInter(size: 15, weight: .medium, relativeTo: .body))
            .foregroundStyle(textColor)
            .padding(.horizontal, 18)
            .frame(height: 52)
            .blankGlassCard(cornerRadius: 18, tintOpacity: 0.16)

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Daily time limit", isOn: $sessionStore.dailyLimitEnabled)
                    .advancedControlStyle(textColor: textColor)

                if sessionStore.dailyLimitEnabled {
                    Stepper(value: $sessionStore.dailyLimitMinutes, in: 5...240, step: 5) {
                        HStack {
                            Text("Limit")
                            Spacer()
                            Text("\(sessionStore.dailyLimitMinutes) min")
                                .monospacedDigit()
                        }
                    }
                    .font(.blankInter(size: 15, weight: .medium, relativeTo: .body))
                    .foregroundStyle(textColor)
                    .padding(.horizontal, 18)
                    .frame(height: 52)
                    .blankGlassCard(cornerRadius: 18, tintOpacity: 0.20)
                }
            }

            if sessionStore.allowOnlyModeEnabled && sessionStore.selection.applicationTokens.isEmpty && sessionStore.selection.webDomainTokens.isEmpty {
                Button {
                    showingPicker = true
                    onFinish()
                } label: {
                    Text("Choose allowed apps")
                        .font(.blankInter(size: 14, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(textColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .blankGlassCard(cornerRadius: 18, tintOpacity: 0.30)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private extension View {
    func advancedControlStyle(textColor: Color) -> some View {
        self
            .font(.blankInter(size: 15, weight: .medium, relativeTo: .body))
            .foregroundStyle(textColor)
            .padding(.horizontal, 18)
            .frame(height: 52)
            .blankGlassCard(cornerRadius: 18, tintOpacity: 0.24)
    }
}

struct HomeSectionScreen: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Binding var showingPicker: Bool
    let section: HomeSection
    let screenWidth: CGFloat
    let screenHeight: CGFloat
    var horizontalOffset: CGFloat = 0
    let intervention: RelapseIntervention
    let onEmergencyUnlock: () -> Bool
    let onTimedBlank: (Int, Bool) -> Void
    let onOpenSection: (HomeSection) -> Void
    let onOpenAssistant: () -> Void
    let onRequestScreenTimePermission: () -> Void
    let onRequestHealthAccess: () -> Void
    let onRelinkBlank: () -> Void
    let onForgetBlank: () -> Void
    let screenTimeStatus: String
    let healthStatus: String
    let onClose: () -> Void
    private var textColor: Color { sessionStore.isBlankActive ? Color.white : BlankColors.ink }

    var body: some View {
        let contentTop: CGFloat = 94
        let contentHeight = max(0, screenHeight - contentTop)
        let contentWidth = min(max(0, screenWidth - 32), 360)
        let minimalAppearance = true

        ZStack(alignment: .topLeading) {
            if minimalAppearance {
                (sessionStore.isBlankActive ? BlankColors.newLookDarkBackground : BlankColors.minimalBackground)
                    .ignoresSafeArea()
            } else {
                AppBackground(isActive: true)
                    .ignoresSafeArea()
            }

            routeContent
                .environment(\.blankMinimalAppearance, minimalAppearance)
                .frame(width: contentWidth, height: contentHeight, alignment: .top)
                .frame(width: screenWidth, height: contentHeight, alignment: .top)
                .offset(x: horizontalOffset, y: contentTop)

            Button {
                onClose()
            } label: {
                Group {
                    if minimalAppearance {
                        Text("back")
                            .font(.blankInter(size: 20, weight: .bold, relativeTo: .headline))
                            .tracking(-0.3)
                    } else {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 22, weight: .regular))
                    }
                }
                .foregroundStyle(sessionStore.isBlankActive ? Color.white.opacity(0.72) : BlankColors.premiumBlue)
                .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .position(x: 46, y: screenHeight - 48)
        }
        .frame(width: screenWidth, height: screenHeight, alignment: .topLeading)
        .preferredColorScheme(sessionStore.isBlankActive ? .dark : .light)
    }

    @ViewBuilder
    private var routeContent: some View {
        switch section {
        case .modes:
            ModesList(showingPicker: $showingPicker) {
                onClose()
            }
        case .schedule:
            ScheduleEditorContent {
                onClose()
            }
        case .report:
            ReportView(usesMainBackground: true)
        case .emergency:
            EmergencyScreen(
                emergencyUnlocksRemaining: sessionStore.emergencyUnlocksRemaining,
                intervention: intervention,
                onUnlock: onEmergencyUnlock
            )
        case .timer:
            TimerScreen(onStart: onTimedBlank)
        case .settings:
            SettingsScreen(
                onOpenEmergency: { onOpenSection(.emergency) },
                onOpenAssistant: onOpenAssistant,
                onRequestScreenTimePermission: onRequestScreenTimePermission,
                onRequestHealthAccess: onRequestHealthAccess,
                onRelinkBlank: onRelinkBlank,
                onForgetBlank: onForgetBlank,
                screenTimeStatus: screenTimeStatus,
                healthStatus: healthStatus
            )
        }
    }
}

private struct SettingsScreen: View {
    @EnvironmentObject private var sessionStore: SessionStore

    let onOpenEmergency: () -> Void
    let onOpenAssistant: () -> Void
    let onRequestScreenTimePermission: () -> Void
    let onRequestHealthAccess: () -> Void
    let onRelinkBlank: () -> Void
    let onForgetBlank: () -> Void
    let screenTimeStatus: String
    let healthStatus: String

    private var textColor: Color { sessionStore.isBlankActive ? Color.white : BlankColors.ink }
    private var secondaryColor: Color { sessionStore.isBlankActive ? Color.white.opacity(0.70) : BlankColors.mutedInk }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text("settings")
                    .font(.blankInter(size: 40, weight: .bold, relativeTo: .title))
                    .tracking(-0.6)
                    .foregroundStyle(textColor)
                    .padding(.bottom, 18)

                settingsRow(
                    title: "emergency",
                    detail: "unlock access while blanked",
                    action: onOpenEmergency
                )

                settingsRow(
                    title: "screen time",
                    detail: "screen time \(screenTimeStatus)",
                    action: onRequestScreenTimePermission
                )

                settingsRow(
                    title: "health",
                    detail: "apple health \(healthStatus)",
                    action: onRequestHealthAccess
                )

                settingsRow(
                    title: "assistant",
                    detail: "whatsapp · sms · connection code",
                    action: onOpenAssistant
                )

                settingsRow(
                    title: "relink blank",
                    detail: "change the linked nfc tag",
                    action: onRelinkBlank
                )

                settingsRow(
                    title: "forget blank",
                    detail: "return to setup",
                    color: secondaryColor,
                    action: onForgetBlank
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func settingsRow(
        title: String,
        detail: String,
        color: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.blankInter(size: 28, weight: .bold, relativeTo: .title3))
                    .tracking(-0.4)

                Text(detail)
                    .font(.blankInter(size: 12, weight: .medium, relativeTo: .caption))
                    .foregroundStyle(secondaryColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(color ?? textColor)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct ScheduleEditorContent: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss
    let onSave: () -> Void
    @State private var windows: [BlankHabitWindow] = [BlankHabitWindow(name: "Routine 1", enabled: false)]
    private var textColor: Color { sessionStore.isBlankActive ? Color.white : BlankColors.ink }
    private var secondaryColor: Color { sessionStore.isBlankActive ? Color.white.opacity(0.70) : BlankColors.mutedInk }

    var body: some View {
        List {
            VStack(alignment: .center, spacing: 16) {
                TopSheetHeader(
                    title: "Routines",
                    subtitle: "BM schedules routines.\nYou review and override them here.",
                    titleColor: textColor,
                    subtitleColor: secondaryColor
                )

                baiHabitsSummary

                Text("Manual overrides")
                    .font(.blankInter(size: 13, weight: .semibold, relativeTo: .caption))
                    .foregroundStyle(secondaryColor)
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)

                VStack(spacing: 12) {
                    ForEach($windows) { $window in
                        HabitWindowCard(
                            window: $window,
                            canDelete: windows.count > 1,
                            textColor: textColor,
                            secondaryColor: secondaryColor
                        ) {
                            deleteWindow(window.id)
                        }
                    }
                }

                Button {
                    addWindow()
                } label: {
                    Label("Add manually", systemImage: "plus")
                        .font(.blankInter(size: 15, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(textColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .blankGlassCard(cornerRadius: 18, tintOpacity: 0.22)
                }
                .buttonStyle(.plain)

                VacationModeCard(
                    textColor: textColor,
                    secondaryColor: secondaryColor
                )

                Text("Manual exits pause only the current habit window.")
                    .font(.footnote)
                    .foregroundStyle(secondaryColor)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .padding(.top, 2)

                Button {
                    saveSchedule()
                } label: {
                    TopSheetPrimaryButtonLabel(title: "Save habits")
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 34)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .background(Color.clear)
        .preferredColorScheme(sessionStore.isBlankActive ? .dark : .light)
        .onAppear {
            windows = sessionStore.schedule.windows.isEmpty
                ? [BlankHabitWindow(name: "Routine 1", enabled: false)]
                : sessionStore.schedule.windows
        }
    }

    private func saveSchedule() {
        let normalized = windows.enumerated().map { index, window in
            BlankHabitWindow(
                id: window.id,
                name: window.name.isEmpty ? "Routine \(index + 1)" : window.name,
                enabled: window.enabled,
                startMinute: window.startMinute,
                endMinute: window.endMinute,
                weekdays: window.weekdays
            )
        }
        let first = normalized.first ?? BlankHabitWindow(enabled: false)
        sessionStore.schedule = BlankFocusSchedule(
            enabled: normalized.contains { $0.enabled },
            startMinute: first.startMinute,
            endMinute: first.endMinute,
            windows: normalized
        )
        onSave()
        dismiss()
    }

    private func addWindow() {
        let number = windows.count + 1
        windows.append(BlankHabitWindow(name: "Routine \(number)", enabled: true, startMinute: 9 * 60, endMinute: 10 * 60))
    }

    private func deleteWindow(_ id: UUID) {
        guard windows.count > 1 else { return }
        windows.removeAll { $0.id == id }
    }

    private var baiHabitsSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(textColor.opacity(0.10)))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Recurring BM routines")
                        .font(.blankInter(size: 18, weight: .semibold, relativeTo: .headline))
                    Text(habitSummaryText)
                        .font(.blankInter(size: 15, weight: .medium, relativeTo: .body))
                        .foregroundStyle(secondaryColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            Divider()
                .overlay(secondaryColor.opacity(0.20))

            HStack(spacing: 10) {
                habitMetric(title: "Active", value: "\(enabledWindows.count)")
                habitMetric(title: "Total", value: "\(windows.count)")
                habitMetric(title: "Pause", value: sessionStore.isVacationModeActive ? "On" : "Off")
            }
        }
        .foregroundStyle(textColor)
        .padding(18)
        .blankGlassCard(cornerRadius: 20, tintOpacity: 0.30)
    }

    private var enabledWindows: [BlankHabitWindow] {
        windows.filter { $0.enabled }
    }

    private var habitSummaryText: String {
        guard let first = enabledWindows.first else {
            return "No active routine yet. Ask BM to create one, then approve it here."
        }
        return "\(first.name): \(formatMinute(first.startMinute)) to \(formatMinute(first.endMinute))"
    }

    private func habitMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(secondaryColor)
            Text(value)
                .font(.blankInter(size: 15, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct VacationModeCard: View {
    @EnvironmentObject private var sessionStore: SessionStore
    let textColor: Color
    let secondaryColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Vacation Mode")
                        .font(.blankInter(size: 16, weight: .semibold, relativeTo: .headline))
                        .foregroundStyle(textColor)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(secondaryColor)
                }
                Spacer()
                if sessionStore.isVacationModeActive {
                    Button("Off") {
                        sessionStore.disableVacationMode()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(textColor)
                    .buttonStyle(.plain)
                }
            }

            if !sessionStore.isVacationModeActive {
                HStack(spacing: 10) {
                    vacationButton("Today", hours: 24)
                    vacationButton("Weekend", hours: 72)
                    vacationButton("Week", hours: 168)
                }
            }
        }
        .padding(16)
        .blankGlassCard(cornerRadius: 18, tintOpacity: sessionStore.isVacationModeActive ? 0.32 : 0.20)
    }

    private var statusText: String {
        guard let until = sessionStore.vacationModeUntil, until > Date() else {
            return "Pause routines and daily limits temporarily."
        }
        return "Paused until \(formatMinute(minuteOfDay(from: until)))."
    }

    private func vacationButton(_ title: String, hours: Int) -> some View {
        Button {
            sessionStore.enableVacationMode(hours: hours)
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .blankGlassCard(cornerRadius: 14, tintOpacity: 0.20)
        }
        .buttonStyle(.plain)
    }
}

private struct HabitWindowCard: View {
    @Binding var window: BlankHabitWindow
    let canDelete: Bool
    let textColor: Color
    let secondaryColor: Color
    let onDelete: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(textColor.opacity(0.86))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(textColor.opacity(0.10)))

                TextField("Routine", text: $window.name)
                    .font(.blankInter(size: 17, weight: .semibold, relativeTo: .headline))
                    .foregroundStyle(textColor)
                    .submitLabel(.done)

                Toggle("", isOn: $window.enabled)
                    .labelsHidden()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(secondaryColor)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                routineMetric(title: "Start", value: formatMinute(window.startMinute))
                routineMetric(title: "End", value: formatMinute(window.endMinute))
                routineMetric(title: "Days", value: daysSummary)
            }

            if isExpanded {
                VStack(spacing: 12) {
                    VStack(spacing: 10) {
                        WheelTimePicker(minute: $window.startMinute)
                        WheelTimePicker(minute: $window.endMinute)
                    }
                    .padding(.top, 2)

                    HabitDaysPicker(
                        selectedWeekdays: $window.weekdays,
                        textColor: textColor,
                        secondaryColor: secondaryColor
                    )

                    if canDelete {
                        Button(action: onDelete) {
                            Label("Delete routine", systemImage: "trash")
                                .font(.blankInter(size: 14, weight: .semibold, relativeTo: .subheadline))
                                .foregroundStyle(secondaryColor)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .blankGlassCard(cornerRadius: 16, tintOpacity: 0.12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .foregroundStyle(textColor)
        .blankControlSurface(cornerRadius: 20, tintOpacity: window.enabled ? 0.10 : 0.06)
        .opacity(window.enabled ? 1 : 0.72)
    }

    private func routineMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(secondaryColor)
            Text(value)
                .font(.blankInter(size: 13, weight: .semibold, relativeTo: .caption))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(textColor.opacity(0.075))
        }
    }

    private var daysSummary: String {
        if window.runsEveryDay {
            return "Everyday"
        }
        return "\(window.weekdays.count)d"
    }
}

private struct HabitDaysPicker: View {
    @Binding var selectedWeekdays: [Int]
    let textColor: Color
    let secondaryColor: Color

    private let days: [(id: Int, label: String)] = [
        (2, "M"),
        (3, "T"),
        (4, "W"),
        (5, "T"),
        (6, "F"),
        (7, "S"),
        (1, "S")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Days")
                    .font(.blankInter(size: 12, weight: .semibold, relativeTo: .caption))
                    .foregroundStyle(secondaryColor)
                Spacer()
                Text(summary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(textColor.opacity(0.86))
            }

            HStack(spacing: 7) {
                ForEach(days, id: \.id) { day in
                    Button {
                        toggle(day.id)
                    } label: {
                        Text(day.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isSelected(day.id) ? BlankColors.ink : textColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background {
                                Capsule()
                                    .fill(isSelected(day.id) ? Color.white.opacity(0.82) : Color.white.opacity(0.12))
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                presetButton("Every day", weekdays: Array(1...7))
                presetButton("Weekdays", weekdays: [2, 3, 4, 5, 6])
                presetButton("Weekend", weekdays: [1, 7])
            }
        }
    }

    private var summary: String {
        let set = Set(selectedWeekdays)
        if set == Set(1...7) { return "Every day" }
        if set == Set([2, 3, 4, 5, 6]) { return "Weekdays" }
        if set == Set([1, 7]) { return "Weekend" }
        return "\(selectedWeekdays.count) days"
    }

    private func presetButton(_ title: String, weekdays: [Int]) -> some View {
        Button {
            selectedWeekdays = weekdays
        } label: {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background {
                    Capsule().fill(Color.white.opacity(Set(selectedWeekdays) == Set(weekdays) ? 0.20 : 0.10))
                }
        }
        .buttonStyle(.plain)
    }

    private func isSelected(_ weekday: Int) -> Bool {
        selectedWeekdays.contains(weekday)
    }

    private func toggle(_ weekday: Int) {
        var set = Set(selectedWeekdays)
        if set.contains(weekday), set.count > 1 {
            set.remove(weekday)
        } else {
            set.insert(weekday)
        }
        selectedWeekdays = set.sorted()
    }
}

private struct WheelTimePicker: View {
    @Binding var minute: Int

    var body: some View {
        DatePicker("", selection: dateBinding, displayedComponents: .hourAndMinute)
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(height: 96)
            .clipped()
            .colorScheme(.dark)
        .frame(maxWidth: .infinity)
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { dateForMinute(minute) },
            set: { minute = minuteOfDay(from: $0) }
        )
    }
}

private struct StaticScheduleRow: View {
    let title: String
    let value: String
    let textColor: Color

    var body: some View {
        HStack {
            Text(title)
                .font(.blankInter(size: 16, weight: .medium, relativeTo: .body))
            Spacer()
            Text(value)
                .font(.blankInter(size: 20, weight: .semibold, relativeTo: .title3))
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, 18)
        .frame(height: 56)
        .blankGlassCard(cornerRadius: 18, tintOpacity: 0.30)
    }
}

private struct TimeMenuRow: View {
    let title: String
    @Binding var minute: Int
    let textColor: Color

    private let options = stride(from: 0, through: 23 * 60 + 30, by: 30).map { $0 }

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(formatMinute(option)) {
                    minute = option
                }
            }
        } label: {
            HStack {
                Text(title)
                    .font(.blankInter(size: 16, weight: .medium, relativeTo: .body))
                Spacer()
                Text(formatMinute(minute))
                    .font(.blankInter(size: 20, weight: .semibold, relativeTo: .title3))
                    .monospacedDigit()
            }
            .foregroundStyle(textColor)
            .padding(.horizontal, 18)
            .frame(height: 56)
            .blankGlassCard(cornerRadius: 18, tintOpacity: 0.30)
        }
    }
}

private struct ForgetBlankConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onConfirm: () -> Void

    var body: some View {
        TechnicalSettingsSheetLayout {
            TechnicalSheetTitle("I forgot my Blank")
            TechnicalSheetDescription("This turns Blank off, removes the linked item, and returns to onboarding so you can register a new one.")
            TechnicalSheetDescription("Your modes and selected apps stay saved.", emphasized: true)
            TechnicalSheetActions {
                Button("I forgot my Blank") {
                    onConfirm()
                    dismiss()
                }
                .buttonStyle(BlankPrimaryButtonStyle())

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

}

private struct RelapseReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let intervention: RelapseIntervention
    let onSelect: (RelapseReviewReason) -> Void

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = min(max(proxy.size.width - 48, 0), 360)

            ZStack {
                AppBackground(isActive: false)
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.14),
                            BlankColors.background.opacity(0.20),
                            Color.white.opacity(0.06)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                }

                HStack(spacing: 0) {
                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(BlankColors.ink.opacity(0.78))
                            .frame(width: 38, height: 38)
                            .background {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay { Circle().fill(Color.white.opacity(0.28)) }
                            }
                            .overlay {
                                Circle().stroke(BlankColors.glassBorder, lineWidth: 1)
                            }
                            .shadow(color: BlankColors.ink.opacity(0.08), radius: 14, x: 0, y: 8)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Why now?")
                                .font(.blankInter(size: 32, weight: .medium, relativeTo: .largeTitle))
                                .foregroundStyle(BlankColors.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.86)

                            Text(intervention.alternative)
                                .font(.blankInter(size: 15, weight: .medium, relativeTo: .subheadline))
                                .foregroundStyle(BlankColors.mutedInk)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 6)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(RelapseReviewReason.allCases) { reason in
                            Button {
                                onSelect(reason)
                                dismiss()
                            } label: {
                                RelapseReasonTile(reason: reason)
                            }
                            .buttonStyle(RelapseReasonButtonStyle())
                        }
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text("Skip")
                            .font(.blankInter(size: 14, weight: .semibold, relativeTo: .subheadline))
                            .foregroundStyle(BlankColors.ink.opacity(0.58))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)

                    Spacer(minLength: 0)
                    }
                    .frame(width: contentWidth, alignment: .leading)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 92)
                .padding(.bottom, 28)
            }
        }
        .preferredColorScheme(.light)
    }
}

private struct RelapseReasonTile: View {
    let reason: RelapseReviewReason

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BlankColors.ink.opacity(0.74))
                .frame(width: 28, height: 28)
                .background {
                    Circle().fill(BlankColors.ink.opacity(0.055))
                }

            Text(reason.title)
                .font(.blankInter(size: 14, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(BlankColors.ink.opacity(0.94))
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var symbol: String {
        switch reason {
        case .bored: return "sparkles"
        case .anxious: return "waveform.path.ecg"
        case .tired: return "moon.fill"
        case .neededApp: return "app.fill"
        case .procrastinating: return "clock.fill"
        case .other: return "ellipsis"
        }
    }
}

private struct RelapseReasonButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(configuration.isPressed ? 0.24 : 0.38))
                    BlankGlassCornerHighlight(width: 76, height: 28, xOffset: -68, yOffset: -20)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(BlankColors.glassBorder, lineWidth: 1)
            }
            .shadow(color: BlankColors.ink.opacity(configuration.isPressed ? 0.025 : 0.065), radius: configuration.isPressed ? 8 : 16, x: 0, y: configuration.isPressed ? 4 : 10)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private struct EmergencyScreen: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.blankMinimalAppearance) private var minimalAppearance
    let emergencyUnlocksRemaining: Int
    let intervention: RelapseIntervention
    let onUnlock: () -> Bool
    @State private var isConfirming = false
    private var textColor: Color { sessionStore.isBlankActive ? Color.white : BlankColors.ink }
    private var secondaryColor: Color { sessionStore.isBlankActive ? Color.white.opacity(0.70) : BlankColors.mutedInk }

    var body: some View {
        VStack(alignment: minimalAppearance ? .leading : .center, spacing: minimalAppearance ? 18 : 22) {
            Spacer(minLength: 0)

            VStack(alignment: minimalAppearance ? .leading : .center, spacing: 10) {
                if !minimalAppearance {
                    Image(systemName: isConfirming ? "lock.open.fill" : "shield.lefthalf.filled")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(textColor)
                        .frame(width: 52, height: 52)
                        .background {
                            Circle().fill(textColor.opacity(0.08))
                        }
                }

                Text(isConfirming ? "spend emergency?" : "emergency")
                    .font(.blankInter(
                        size: minimalAppearance ? 40 : 34,
                        weight: minimalAppearance ? .bold : .medium,
                        relativeTo: .largeTitle
                    ))
                    .tracking(minimalAppearance ? -0.6 : 0)
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(minimalAppearance ? .leading : .center)

                Text(bodyText)
                    .font(.blankInter(size: minimalAppearance ? 14 : 16, weight: .regular, relativeTo: .body))
                    .foregroundStyle(secondaryColor)
                    .multilineTextAlignment(minimalAppearance ? .leading : .center)
                    .lineSpacing(minimalAppearance ? 0 : 3)
                    .frame(maxWidth: 300)
            }
            .frame(maxWidth: .infinity, alignment: minimalAppearance ? .leading : .center)

            emergencyAllowance

            VStack(spacing: 12) {
                if isConfirming {
                    Button("Keep blocking") {
                        isConfirming = false
                    }
                    .buttonStyle(BlankPrimaryButtonStyle())

                    Button("Confirm unlock") {
                        _ = onUnlock()
                    }
                    .font(.blankInter(size: 15, weight: .semibold, relativeTo: .subheadline))
                    .buttonStyle(.plain)
                    .foregroundStyle(secondaryColor)
                    .disabled(emergencyUnlocksRemaining <= 0)
                } else {
                    Button("Spend emergency") {
                        isConfirming = true
                    }
                    .buttonStyle(BlankPrimaryButtonStyle())
                    .disabled(emergencyUnlocksRemaining <= 0 || !sessionStore.isBlankActive)
                }
            }
            .frame(maxWidth: 300)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .preferredColorScheme(sessionStore.isBlankActive ? .dark : .light)
    }

    private var bodyText: String {
        if isConfirming {
            return "This unlocks Blanked now. You will have \(max(0, emergencyUnlocksRemaining - 1)) left this week."
        }
        guard sessionStore.isBlankActive else {
            return "No active block right now."
        }
        guard emergencyUnlocksRemaining > 0 else {
            return "No emergency unlocks left."
        }
        return "Use one unlock only if access is necessary now."
    }

    private var emergencyAllowance: some View {
        VStack(spacing: 8) {
            Text("\(emergencyUnlocksRemaining)/3 left this week")
                .font(.blankInter(size: 14, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(textColor)
                .monospacedDigit()

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index < emergencyUnlocksRemaining ? textColor.opacity(0.82) : secondaryColor.opacity(0.20))
                        .frame(maxWidth: .infinity)
                        .frame(height: 7)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 260)
        .blankControlSurface(cornerRadius: 18, tintOpacity: 0.08)
    }
}

private struct RelinkSheet: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss
    @Binding var message: String?
    @Binding var messageAction: HomeMessageAction?
    @State private var nfcReader = NFCReader()

    var body: some View {
        TechnicalSettingsSheetLayout {
            TechnicalSheetTitle("New Blank")
            TechnicalSheetDescription("Scan the new Blank to replace the one you linked. Your modes and protected apps stay saved.")
            TechnicalSheetActions {
                Button("Scan new Blank") {
                    nfcReader.scan { result in
                        Task { @MainActor in
                            switch result {
                            case .success(let uid):
                                sessionStore.nfcTagUid = uid
                                message = "New Blank linked."
                                messageAction = nil
                                dismiss()
                            case .failure(let error):
                                message = error.localizedDescription
                                messageAction = nil
                            }
                        }
                    }
                }
                .buttonStyle(BlankPrimaryButtonStyle())

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct TechnicalSettingsSheetLayout<Content: View>: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @ViewBuilder var content: Content
    private var textColor: Color { sessionStore.isBlankActive ? Color.white : BlankColors.ink }

    var body: some View {
        VStack(spacing: 18) {
            content
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(textColor)
        .background(BlankAtmosphericBackground(dimmed: sessionStore.isBlankActive))
        .preferredColorScheme(sessionStore.isBlankActive ? .dark : .light)
    }
}

private struct TechnicalSheetTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.blankInter(size: 34, weight: .medium, relativeTo: .largeTitle))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.86)
            .frame(maxWidth: 320)
    }
}

private struct TechnicalSheetDescription: View {
    let text: String
    var emphasized = false

    init(_ text: String, emphasized: Bool = false) {
        self.text = text
        self.emphasized = emphasized
    }

    var body: some View {
        Text(text)
            .font(emphasized ? .footnote.weight(.medium) : .body)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .lineSpacing(2)
            .frame(maxWidth: 330)
    }
}

private struct TechnicalSheetActions<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 12) {
            content
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

private struct TimerScreen: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.blankMinimalAppearance) private var minimalAppearance
    @State private var hardMode = false
    @State private var selectedMinutes = 30
    let onStart: (Int, Bool) -> Void
    private let options = [15, 30, 45, 60, 90, 120]
    private var textColor: Color { sessionStore.isBlankActive ? Color.white : BlankColors.ink }
    private var secondaryColor: Color { sessionStore.isBlankActive ? Color.white.opacity(0.70) : BlankColors.mutedInk }
    private var recommendedMinutes: Int { sessionStore.digitalWellnessV3.plan.recommendedDurationMinutes }

    var body: some View {
        Group {
            if minimalAppearance {
                newLookTimer
            } else {
                VStack(spacing: 22) {
            Spacer(minLength: 0)

            TopSheetHeader(
                title: "Timer",
                subtitle: "Choose a focused block.",
                titleColor: textColor,
                subtitleColor: secondaryColor
            )

            VStack(spacing: 18) {
                timerDurationRing

                Button {
                    selectedMinutes = recommendedMinutes
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.caption.weight(.semibold))
                        Text("Recommended: \(formatDuration(recommendedMinutes)) now")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .foregroundStyle(textColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background {
                        RoundedRectangle(cornerRadius: minimalAppearance ? 0 : 20, style: .continuous)
                            .fill(textColor.opacity(0.10))
                    }
                }
                .buttonStyle(.plain)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                    ForEach(options, id: \.self) { minutes in
                        timerOptionButton(minutes)
                    }
                }

                Toggle(isOn: $hardMode) {
                    HStack(spacing: 10) {
                        Image(systemName: hardMode ? "lock.shield.fill" : "shield")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(textColor.opacity(0.86))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Hard mode")
                                .font(.blankInter(size: 15, weight: .semibold, relativeTo: .subheadline))
                            Text("Early exit uses Emergency")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(secondaryColor)
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(textColor.opacity(0.72))
                .foregroundStyle(textColor)
                .padding(.horizontal, 16)
                .frame(height: 58)
                .blankControlSurface(cornerRadius: 18, tintOpacity: hardMode ? 0.16 : 0.08)

                Button {
                    if !sessionStore.isBlankActive {
                        onStart(selectedMinutes, hardMode)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: sessionStore.isBlankActive ? "shield.fill" : "timer")
                        Text(sessionStore.isBlankActive ? "Blanked is active" : "Start block")
                    }
                }
                .buttonStyle(BlankPrimaryButtonStyle())
                .disabled(sessionStore.isBlankActive)
                .opacity(sessionStore.isBlankActive ? 0.62 : 1)
            }
            .padding(18)
            .blankControlSurface(cornerRadius: 24, tintOpacity: 0.08, emphasized: true)

                    Spacer(minLength: 0)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .preferredColorScheme(sessionStore.isBlankActive ? .dark : .light)
    }

    private var newLookTimer: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopSheetHeader(
                title: "Timer",
                subtitle: "",
                titleColor: textColor,
                subtitleColor: secondaryColor
            )

            Spacer(minLength: 38)

            Text(durationNumber(selectedMinutes))
                .font(.blankInter(size: 92, weight: .bold, relativeTo: .largeTitle))
                .tracking(-3)
                .foregroundStyle(textColor)
                .monospacedDigit()
                .lineLimit(1)

            Text(durationUnit(selectedMinutes))
                .font(.blankInter(size: 20, weight: .bold, relativeTo: .title3))
                .foregroundStyle(secondaryColor)

            Rectangle()
                .fill(sessionStore.isBlankActive ? Color.white.opacity(0.16) : BlankColors.newLookRule)
                .frame(height: 1)
                .padding(.top, 28)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(options, id: \.self) { minutes in
                    Button {
                        selectedMinutes = minutes
                    } label: {
                        HStack {
                            Text(formatDuration(minutes))
                                .font(.blankInter(size: 24, weight: .bold, relativeTo: .title3))
                                .tracking(-0.4)
                            Spacer()
                            if selectedMinutes == minutes {
                                Text("selected")
                                    .font(.blankInter(size: 12, weight: .semibold, relativeTo: .caption))
                                    .foregroundStyle(secondaryColor)
                            }
                        }
                        .foregroundStyle(selectedMinutes == minutes ? textColor : secondaryColor)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Toggle("hard mode", isOn: $hardMode)
                .font(.blankInter(size: 18, weight: .bold, relativeTo: .headline))
                .foregroundStyle(textColor)
                .tint(textColor.opacity(0.75))
                .padding(.top, 16)

            Spacer(minLength: 26)

            Button {
                if !sessionStore.isBlankActive {
                    onStart(selectedMinutes, hardMode)
                }
            } label: {
                Text(sessionStore.isBlankActive ? "blank is active" : "start blank")
                    .font(.blankInter(size: 28, weight: .bold, relativeTo: .title2))
                    .tracking(-0.6)
                    .foregroundStyle(textColor)
                    .frame(minWidth: 44, minHeight: 52, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(sessionStore.isBlankActive)
            .opacity(sessionStore.isBlankActive ? 0.52 : 1)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var timerDurationRing: some View {
        ZStack {
            Circle()
                .stroke(textColor.opacity(0.08), lineWidth: 10)
            Circle()
                .trim(from: 0, to: CGFloat(min(selectedMinutes, 120)) / 120)
                .stroke(
                    AngularGradient(
                        colors: [
                            BlankColors.premiumBlue.opacity(0.34),
                            textColor.opacity(0.92),
                            BlankColors.premiumBlue.opacity(0.62)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text(durationNumber(selectedMinutes))
                    .font(.blankInter(size: 56, weight: .semibold, relativeTo: .largeTitle))
                    .foregroundStyle(textColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(durationUnit(selectedMinutes))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryColor)
            }
        }
        .frame(width: 188, height: 188)
        .accessibilityLabel("Timer \(formatDuration(selectedMinutes))")
    }

    private func timerOptionButton(_ minutes: Int) -> some View {
        Button {
            selectedMinutes = minutes
        } label: {
            Text(formatDuration(minutes))
                .font(.blankInter(size: 14, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background {
                    RoundedRectangle(cornerRadius: minimalAppearance ? 0 : 21, style: .continuous)
                        .fill(selectedMinutes == minutes ? BlankColors.premiumBlue.opacity(0.24) : textColor.opacity(0.08))
                }
                .overlay {
                    if minimalAppearance {
                        Rectangle()
                            .stroke(BlankColors.line, lineWidth: 0.8)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func durationNumber(_ minutes: Int) -> String {
        if minutes == 60 { return "1" }
        if minutes == 120 { return "2" }
        return "\(minutes)"
    }

    private func durationUnit(_ minutes: Int) -> String {
        if minutes == 60 { return "hour" }
        if minutes == 120 { return "hours" }
        return "minutes"
    }

    private func formatDuration(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}

private struct AssistantConnectSheet: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.blankMinimalAppearance) private var minimalAppearance
    @Environment(\.dismiss) private var dismiss
    @AppStorage("blankAssistantPhoneNumber", store: BlankSharedState.defaults) private var phoneNumber = ""
    @AppStorage("blankAssistantConnectCode", store: BlankSharedState.defaults) private var connectCode = ""
    @AppStorage("blankAssistantPreferredChannel", store: BlankSharedState.defaults) private var preferredChannel = ""
    @AppStorage("blankAssistantConnectedAt", store: BlankSharedState.defaults) private var connectedAt = ""
    @State private var copiedCode = false
    @State private var showingPhoneSignIn = false

    let whatsAppNumber: String?
    let smsNumber: String?
    let openURL: OpenURLAction
    let initialContext: [String: Any]

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = min(max(0, proxy.size.width - 48), 360)

            ZStack {
                if minimalAppearance {
                    BlankColors.minimalBackground
                        .ignoresSafeArea()
                } else {
                    AppBackground(isActive: sessionStore.isBlankActive)
                        .ignoresSafeArea()
                }

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(minimalAppearance ? "assistant" : "Assistant")
                                    .font(.blankInter(
                                        size: minimalAppearance ? 40 : 34,
                                        weight: minimalAppearance ? .bold : .medium,
                                        relativeTo: .largeTitle
                                    ))
                                    .tracking(minimalAppearance ? -0.6 : 0)
                                    .lineLimit(1)

                                Text(minimalAppearance ? "use blanked from whatsapp or sms." : "Use Blanked from WhatsApp or SMS.")
                                    .font(.blankInter(size: minimalAppearance ? 13 : 15, weight: .medium, relativeTo: .subheadline))
                                    .foregroundStyle(secondaryColor)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 16)

                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(width: 44, height: 44)
                                    .background { Circle().fill(textColor.opacity(0.10)) }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close Assistant")
                        }

                        VStack(alignment: .leading, spacing: 9) {
                            Text("Your phone")
                                .font(.blankInter(size: 13, weight: .semibold, relativeTo: .caption))
                                .foregroundStyle(secondaryColor)
                            TextField("+1 555 000 0000", text: $phoneNumber)
                                .keyboardType(.phonePad)
                                .textContentType(.telephoneNumber)
                                .font(.blankInter(size: 16, weight: .medium, relativeTo: .body))
                                .padding(.horizontal, 16)
                                .frame(height: 52)
                                .blankGlassCard(cornerRadius: 16, tintOpacity: 0.28)
                            Text("Used to match your CONNECT message.")
                                .font(.blankInter(size: 12, weight: .medium, relativeTo: .caption))
                                .foregroundStyle(secondaryColor.opacity(0.82))

                            Button("Sign in with your phone") {
                                showingPhoneSignIn = true
                            }
                            .font(.blankInter(size: 13, weight: .semibold, relativeTo: .footnote))
                            .foregroundStyle(textColor)
                            .buttonStyle(.plain)
                        }

                        VStack(spacing: 10) {
                            AssistantChannelButton(
                                title: "Connect WhatsApp",
                                subtitle: "Recommended",
                                systemImage: "message.fill",
                                usesWhatsAppLogo: true,
                                enabled: whatsAppNumber != nil,
                                textColor: textColor,
                                secondaryColor: secondaryColor
                            ) {
                                openAssistantChannel(.whatsApp)
                            }

                            AssistantChannelButton(
                                title: "Connect SMS",
                                subtitle: "Same code, same assistant",
                                systemImage: "message",
                                usesWhatsAppLogo: false,
                                enabled: smsNumber != nil,
                                textColor: textColor,
                                secondaryColor: secondaryColor
                            ) {
                                openAssistantChannel(.sms)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Code")
                                    .font(.blankInter(size: 12, weight: .semibold, relativeTo: .caption2))
                                    .foregroundStyle(secondaryColor)
                                Spacer()
                                Button(copiedCode ? "Copied" : "Copy") {
                                    UIPasteboard.general.string = connectMessage
                                    copiedCode = true
                                }
                                .font(.blankInter(size: 12, weight: .semibold, relativeTo: .caption2))
                                .foregroundStyle(secondaryColor)
                                .buttonStyle(.plain)
                            }

                            Text(connectMessage)
                                .font(.blankInter(size: 17, weight: .semibold, relativeTo: .body))
                                .monospacedDigit()
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .frame(height: 54)
                                .blankGlassCard(cornerRadius: 18, tintOpacity: 0.22)

                            Text(statusText)
                                .font(.blankInter(size: 13, weight: .medium, relativeTo: .footnote))
                                .foregroundStyle(secondaryColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.top, 36)
                    .padding(.bottom, 24)
                    .frame(width: contentWidth, alignment: .topLeading)
                    .frame(minHeight: proxy.size.height, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .foregroundStyle(textColor)
        .environment(\.blankMinimalAppearance, !sessionStore.isBlankActive)
        .preferredColorScheme(sessionStore.isBlankActive ? .dark : .light)
        .onAppear {
            ensureConnectCode()
        }
        .sheet(isPresented: $showingPhoneSignIn) {
            AppPhoneSignInSheet(initialPhone: phoneNumber)
                .environmentObject(sessionStore)
        }
    }

    private var textColor: Color { sessionStore.isBlankActive ? Color.white : BlankColors.ink }
    private var secondaryColor: Color { sessionStore.isBlankActive ? Color.white.opacity(0.70) : BlankColors.mutedInk }

    private var statusText: String {
        guard !connectedAt.isEmpty else {
            return "Send this code once to verify Assistant."
        }
        return "Finish in \(preferredChannelName) by sending the CONNECT code."
    }

    private var preferredChannelName: String {
        preferredChannel == AssistantChannel.whatsApp.rawValue ? "WhatsApp" : "SMS"
    }

    private var connectMessage: String {
        "CONNECT \(connectCode.isEmpty ? "BLANKED" : connectCode)"
    }

    private func ensureConnectCode() {
        guard connectCode.isEmpty else { return }
        connectCode = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).uppercased()
    }

    private func openAssistantChannel(_ channel: AssistantChannel) {
        ensureConnectCode()
        preferredChannel = channel.rawValue
        connectedAt = Date.now.formatted(date: .abbreviated, time: .shortened)
        let cleanedUserPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)

        let message = connectMessage
        let encodedMessage = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? message

        switch channel {
        case .whatsApp:
            guard let whatsAppNumber, let url = URL(string: "https://wa.me/\(whatsAppNumber)?text=\(encodedMessage)") else { return }
            openURL(url)
        case .sms:
            guard let smsNumber, let url = URL(string: "sms:\(smsNumber)&body=\(encodedMessage)") else { return }
            openURL(url)
        }
        Task {
            await registerAssistantPreference(
                channel: channel,
                connectCode: connectCode,
                userPhone: cleanedUserPhone,
                context: initialContext
            )
            await BlankFunnelAnalytics.track(
                "assistant_channel_connect_started",
                properties: [
                    "channel": channel.rawValue,
                    "has_user_phone": !cleanedUserPhone.isEmpty,
                    "connect_code": connectCode
                ]
            )
        }
        dismiss()
    }

    private func registerAssistantPreference(
        channel: AssistantChannel,
        connectCode: String,
        userPhone: String,
        context: [String: Any]
    ) async {
        guard let baseURL = configuredBaseURL() else { return }
        var request = URLRequest(url: baseURL.appendingPathComponent("assistant-channel"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8
        let payload: [String: Any] = [
            "action": "register_preference",
            "connect_code": connectCode,
            "preferred_channel": channel == .whatsApp ? "whatsapp" : "sms",
            "user_phone": userPhone,
            "context": context
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        _ = try? await URLSession.shared.data(for: request)
    }

    private func configuredBaseURL() -> URL? {
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

private struct AppPhoneSignInSheet: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("blankAssistantPhoneNumber", store: BlankSharedState.defaults) private var phoneNumber = ""
    @AppStorage("blankAssistantConnectCode", store: BlankSharedState.defaults) private var connectCode = ""
    @AppStorage("blankAssistantPreferredChannel", store: BlankSharedState.defaults) private var preferredChannel = ""
    @AppStorage("blankAssistantConnectedAt", store: BlankSharedState.defaults) private var connectedAt = ""
    @State private var code = ""
    @State private var channel = "whatsapp"
    @State private var verificationStarted = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    let initialPhone: String

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Use the same phone number you verified on the web. Blankmind will link this app install to that account and its WhatsApp or SMS thread.")
                        .font(.blankInter(size: 15, weight: .medium, relativeTo: .body))
                        .foregroundStyle(.secondary)
                }

                Section("Phone") {
                    TextField("+1 555 000 0000", text: $phoneNumber)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    Picker("Send code by", selection: $channel) {
                        Text("WhatsApp").tag("whatsapp")
                        Text("SMS").tag("sms")
                    }
                    .pickerStyle(.segmented)
                }

                if verificationStarted {
                    Section("Verification code") {
                        TextField("123456", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                        Button(isWorking ? "Verifying…" : "Verify and connect") {
                            Task { await verifyCode() }
                        }
                        .disabled(isWorking || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } else {
                    Section {
                        Button(isWorking ? "Sending…" : "Send verification code") {
                            Task { await requestCode() }
                        }
                        .disabled(isWorking || phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Connect Blankmind")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if phoneNumber.isEmpty { phoneNumber = initialPhone }
            }
        }
        .preferredColorScheme(sessionStore.isBlankActive ? .dark : .light)
    }

    private func requestCode() async {
        await performRequest(action: "request_otp", payload: [
            "phone": phoneNumber,
            "channel": channel,
        ])
        if errorMessage == nil { verificationStarted = true }
    }

    private func verifyCode() async {
        do {
            isWorking = true
            errorMessage = nil
            let auth = try await postJSON(path: "app-auth", payload: [
                "action": "verify_otp",
                "phone": phoneNumber,
                "token": code,
            ])
            guard let accessToken = auth["access_token"] as? String, !accessToken.isEmpty else {
                throw AppPhoneSignInError.message("Blankmind did not return a session.")
            }
            let linked = try await postJSON(
                path: "app-handoff",
                payload: [
                    "action": "claim_identity",
                    "app_install_id": BlankSharedState.appInstallId,
                    "data_consent": true,
                ],
                bearerToken: accessToken
            )
            guard let linkedCode = linked["assistant_connect_code"] as? String, !linkedCode.isEmpty else {
                throw AppPhoneSignInError.message("The account was verified but the assistant link was not created.")
            }
            connectCode = linkedCode
            preferredChannel = channel
            if let linkedPhone = linked["phone_e164"] as? String, !linkedPhone.isEmpty {
                phoneNumber = linkedPhone
            }
            connectedAt = Date.now.formatted(date: .abbreviated, time: .shortened)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func performRequest(action: String, payload: [String: Any]) async {
        do {
            isWorking = true
            errorMessage = nil
            var body = payload
            body["action"] = action
            _ = try await postJSON(path: "app-auth", payload: body)
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func postJSON(path: String, payload: [String: Any], bearerToken: String? = nil) async throws -> [String: Any] {
        guard let baseURL = configuredBaseURL() else {
            throw AppPhoneSignInError.message("Blankmind connection is not configured in this build.")
        }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearerToken { request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization") }
        request.timeoutInterval = 12
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        let result = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let detail = result["detail"] as? String ?? result["error"] as? String ?? "Request failed."
            throw AppPhoneSignInError.message(detail.replacingOccurrences(of: "_", with: " "))
        }
        return result
    }

    private func configuredBaseURL() -> URL? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "BlankMembershipAPIBaseURL") as? String else {
            return nil
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return URL(string: trimmed)
    }
}

private enum AppPhoneSignInError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        if case let .message(value) = self { return value }
        return nil
    }
}

private struct AssistantChannelButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let usesWhatsAppLogo: Bool
    let enabled: Bool
    let textColor: Color
    let secondaryColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(textColor.opacity(0.10))
                    if usesWhatsAppLogo {
                        WhatsAppMark()
                            .stroke(textColor, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                            .frame(width: 17, height: 17)
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.blankInter(size: 15, weight: .semibold, relativeTo: .subheadline))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(subtitle)
                        .font(.blankInter(size: 12, weight: .medium, relativeTo: .caption))
                        .foregroundStyle(secondaryColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(secondaryColor)
            }
            .foregroundStyle(textColor)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .blankControlSurface(cornerRadius: 18, tintOpacity: enabled ? 0.12 : 0.06)
            .opacity(enabled ? 1 : 0.46)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct WhatsAppMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bubble = CGRect(
            x: rect.minX + rect.width * 0.05,
            y: rect.minY + rect.height * 0.05,
            width: rect.width * 0.90,
            height: rect.height * 0.82
        )
        path.addEllipse(in: bubble)
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.30, y: rect.minY + rect.height * 0.78))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.96))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.84))

        path.move(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.minY + rect.height * 0.32))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.68, y: rect.minY + rect.height * 0.62),
            control1: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.52),
            control2: CGPoint(x: rect.minX + rect.width * 0.54, y: rect.minY + rect.height * 0.62)
        )
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY + rect.height * 0.32))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.42))
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.68, y: rect.minY + rect.height * 0.62))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.57, y: rect.minY + rect.height * 0.54))
        return path
    }
}

private enum AssistantChannel: String {
    case whatsApp
    case sms
}

private func formatMinute(_ minuteOfDay: Int) -> String {
    let hour = max(0, min(23, minuteOfDay / 60))
    let minute = max(0, min(59, minuteOfDay % 60))
    let displayHour = hour % 12 == 0 ? 12 : hour % 12
    let meridiem = hour < 12 ? "AM" : "PM"
    return "\(displayHour):\(String(format: "%02d", minute)) \(meridiem)"
}

private func parseMinute(_ value: String) -> Int? {
    let parts = value.split(separator: ":")
    guard parts.count == 2,
          let hour = Int(parts[0]),
          let minute = Int(parts[1]),
          (0...23).contains(hour),
          (0...59).contains(minute) else {
        return nil
    }
    return hour * 60 + minute
}

private func dateForMinute(_ minuteOfDay: Int) -> Date {
    let calendar = Calendar.current
    let hour = max(0, min(23, minuteOfDay / 60))
    let minute = max(0, min(59, minuteOfDay % 60))
    return calendar.date(
        bySettingHour: hour,
        minute: minute,
        second: 0,
        of: Date()
    ) ?? Date()
}

private func minuteOfDay(from date: Date) -> Int {
    let components = Calendar.current.dateComponents([.hour, .minute], from: date)
    return (components.hour ?? 0) * 60 + (components.minute ?? 0)
}

private extension FamilyActivitySelection {
    var blankedSelectionCount: Int {
        applicationTokens.count + categoryTokens.count + webDomainTokens.count
    }
}

#if DEBUG
@MainActor
private struct HomePreviewScene: View {
    let name: String
    let sessionStore: SessionStore
    let screenTimeBlocker: ScreenTimeBlocker

    init(
        _ name: String,
        isBlankActive: Bool = false,
        protectedSelectionCount: Int = 3,
        nfcLinked: Bool = true,
        authorizationApproved: Bool = true,
        schedule: BlankFocusSchedule = BlankFocusSchedule(),
        schedulePausedUntil: Date? = nil,
        timedUntil: Date? = nil
    ) {
        self.name = name
        self.sessionStore = SessionStore.preview(
            isBlankActive: isBlankActive,
            protectedSelectionCount: protectedSelectionCount,
            nfcLinked: nfcLinked,
            schedule: schedule,
            schedulePausedUntil: schedulePausedUntil,
            timedUntil: timedUntil
        )
        self.screenTimeBlocker = ScreenTimeBlocker.preview(authorizationApproved: authorizationApproved)
    }

    var body: some View {
        HomeView()
            .environmentObject(sessionStore)
            .environmentObject(screenTimeBlocker)
            .environmentObject(StoreKitPurchaseStore())
            .environment(\.font, .blankBody)
            .previewDisplayName(name)
    }
}

#Preview("Home - Idle") {
    HomePreviewScene("Home - Idle")
}

#Preview("Home - No apps") {
    HomePreviewScene("Home - No apps", protectedSelectionCount: 0)
}

#Preview("Home - NFC pending") {
    HomePreviewScene("Home - NFC pending", nfcLinked: false)
}

#Preview("Blank active") {
    HomePreviewScene("Blank active", isBlankActive: true)
}

#Preview("Blank active - Timer") {
    HomePreviewScene(
        "Blank active - Timer",
        isBlankActive: true,
        timedUntil: Date().addingTimeInterval(38 * 60)
    )
}

#Preview("Schedule paused") {
    HomePreviewScene(
        "Schedule paused",
        isBlankActive: false,
        schedule: BlankFocusSchedule(enabled: true, startMinute: 0, endMinute: 24 * 60 - 1),
        schedulePausedUntil: Date().addingTimeInterval(5 * 60)
    )
}

#Preview("Permission pending") {
    HomePreviewScene("Permission pending", authorizationApproved: false)
}
#endif
