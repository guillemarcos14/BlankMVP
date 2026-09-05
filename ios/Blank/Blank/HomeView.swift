import FamilyControls
import LocalAuthentication
import SwiftUI
import UIKit
import UserNotifications

enum HomeSection: Hashable {
    case modes
    case schedule
    case report
    case emergency
}

struct HomeView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var screenTimeBlocker: ScreenTimeBlocker
    @EnvironmentObject private var purchaseStore: StoreKitPurchaseStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @State private var now = Date()
    @State private var message: String?
    @State private var messageAction: ConfigIssue.Action?
    @State private var showingPicker = false
    @State private var activeSection: HomeSection?
    @State private var showingTimer = false
    @State private var showingAssistantConnect = false
    @State private var showingContextualAppPicker = false
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
    private let riskBlankMinutes = 30
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
                AppBackground(isActive: sessionStore.isBlankActive)
                    .frame(width: viewportWidth, height: viewportHeight)
                    .clipped()

                if activeSection == nil {
                    topBar
                        .position(x: layout.centerX, y: layout.topBarCenterY)
                        .zIndex(2)

                    topHomePanel(width: layout.actionWidth)
                        .padding(.horizontal, layout.horizontalPadding)
                        .padding(.top, layout.configTopPadding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    centerContent(maxWidth: layout.messageMaxWidth, actionWidth: layout.actionWidth)
                        .position(x: layout.centerX, y: layout.messageCenterY)

                    bottomShortcutBar(width: layout.actionWidth)
                        .position(x: layout.centerX, y: layout.bottomShortcutCenterY)
                }

                if let activeSection {
                    HomeSectionScreen(
                        showingPicker: $showingPicker,
                        section: activeSection,
                        screenWidth: viewportWidth,
                        screenHeight: viewportHeight,
                        intervention: relapseIntervention,
                        onEmergencyUnlock: performEmergencyUnlock
                    ) {
                        closeSection()
                    }
                    .frame(width: viewportWidth, height: viewportHeight, alignment: .topLeading)
                    .transition(.opacity)
                    .zIndex(5)
                }
            }
            .frame(width: viewportWidth, height: viewportHeight, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .foregroundStyle(sessionStore.isBlankActive ? Color.white : BlankColors.ink)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(sessionStore.isBlankActive ? .dark : .light)
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
            openWidgetScanIfNeeded()
            scheduleDailyInterventionIfNeeded()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            sessionStore.syncFromSharedDefaults()
            applyScreenTimeControls()
            screenTimeBlocker.refreshAuthorizationStatus()
            healthKitStore.refresh()
            openWidgetScanIfNeeded()
            scheduleDailyInterventionIfNeeded()
        }
        .familyActivityPicker(isPresented: $showingPicker, selection: $sessionStore.selection)
        .onChange(of: sessionStore.selection) { newSelection in
            screenTimeBlocker.updateSelection(newSelection, isBlankActive: sessionStore.isBlankActive)
            sessionStore.refreshDailyLimitMonitoring()
        }
        .onChange(of: sessionStore.allowOnlyModeEnabled) { _ in
            applyScreenTimeControls()
            if sessionStore.allowOnlyModeEnabled && !sessionStore.hasSelectedApps {
                showingPicker = true
            }
        }
        .onChange(of: sessionStore.adultContentBlockingEnabled) { _ in
            applyScreenTimeControls()
        }
        .onChange(of: sessionStore.shouldOpenBlockConfiguration) { shouldOpen in
            guard shouldOpen else { return }
            if sessionStore.pendingPlanAppNames.isEmpty {
                openSection(.modes)
            } else {
                showingContextualAppPicker = true
            }
            sessionStore.shouldOpenBlockConfiguration = false
        }
        .familyActivityPicker(
            headerText: contextualPickerHeaderText,
            footerText: "",
            isPresented: $showingContextualAppPicker,
            selection: $sessionStore.selection
        )
        .onChange(of: showingContextualAppPicker) { isPresented in
            if !isPresented {
                sessionStore.clearPendingPlanAppNames()
            }
        }
        .onChange(of: sessionStore.shouldScanBlankFromWidget) { shouldScan in
            guard shouldScan else { return }
            openWidgetScanIfNeeded()
        }
        .sheet(isPresented: $showingTimer) {
            TimerStartSheet { minutes, hardMode in
                let result = withAnimation(.easeInOut(duration: 0.65)) {
                    sessionStore.activateBlank(durationMinutes: minutes, hardMode: hardMode)
                }
                screenTimeBlocker.apply(isBlankActive: sessionStore.isBlankActive)
                setMessage(for: result)
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingAssistantConnect) {
            AssistantConnectSheet(
                whatsAppNumber: configuredWhatsAppNumber(),
                smsNumber: configuredSMSNumber(),
                openURL: openURL
            )
            .presentationDetents([.medium])
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
        .sheet(isPresented: $showingRelapseReview) {
            RelapseReviewSheet(
                intervention: relapseIntervention,
                onSelect: { reason in
                    sessionStore.recordRelapseReview(reason)
                    sessionStore.applyAIPlan()
                    Task {
                        await BlankFunnelAnalytics.track(
                            "ai_plan_applied",
                            properties: ["source": "relapse_review", "reason": reason.rawValue]
                        )
                    }
                }
            )
            .presentationDetents([.medium])
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

            HStack(spacing: 0) {
                topNavButton("Stats") {
                    openSection(.report)
                }
                topNavButton("Mode") {
                    openSection(.modes)
                }
                topNavButton("Habits") {
                    openSection(.schedule)
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
        let issues = configIssues
        if !issues.isEmpty {
            configCard(issues)
        } else if !sessionStore.isBlankActive, purchaseStore.hasPremiumAccess {
            aiPlanHomeCard(width: width)
        }
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

    private func aiPlanHomeCard(width: CGFloat) -> some View {
        let system = aiSystem

        return HStack(alignment: .center, spacing: 10) {
            notificationIcon

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Blanked AI")
                        .font(.blankInter(size: 12, weight: .semibold, relativeTo: .caption))
                    Text("now")
                        .font(.blankInter(size: 11, relativeTo: .caption2))
                        .foregroundStyle(BlankColors.mutedInk.opacity(0.78))
                    Spacer(minLength: 0)
                }

                Text("\(system.plan.recommendedDurationMinutes) min before \(system.forecast.riskWindow)")
                    .font(.blankInter(size: 13, weight: .semibold, relativeTo: .caption))
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)
            }
            .layoutPriority(1)

            Button {
                let result = withAnimation(.easeInOut(duration: 0.65)) {
                    sessionStore.activateBlank(durationMinutes: system.plan.recommendedDurationMinutes)
                }
                screenTimeBlocker.apply(isBlankActive: sessionStore.isBlankActive)
                setMessage(for: result)
            } label: {
                Text("Start")
                    .font(.blankInter(size: 11, weight: .semibold, relativeTo: .caption2))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background { Capsule().fill(BlankColors.ink.opacity(0.92)) }
            }
            .buttonStyle(.plain)

            Menu {
                Button("Apply to Habits") {
                    sessionStore.applyAIPlan()
                    Task {
                        await BlankFunnelAnalytics.track(
                            "ai_plan_applied",
                            properties: ["source": "home_ai_plan"]
                        )
                    }
                    message = "Blanked AI applied to Habits."
                    messageAction = nil
                }
                Button("Edit in Habits") {
                    openSection(.schedule)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BlankColors.ink.opacity(0.72))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
        }
        .foregroundStyle(BlankColors.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: min(width, 330), alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.66))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.54), lineWidth: 1)
        }
        .shadow(color: BlankColors.ink.opacity(0.10), radius: 16, x: 0, y: 8)
    }

    private func configCard(_ issues: [ConfigIssue]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(issues) { issue in
                Button {
                    resolve(issue.action)
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(BlankColors.ink.opacity(0.92))
                            Image(systemName: "exclamationmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.white)
                        }
                        .frame(width: 30, height: 30)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("Blanked")
                                    .font(.blankInter(size: 12, weight: .semibold, relativeTo: .caption))
                                Text("now")
                                    .font(.blankInter(size: 11, relativeTo: .caption2))
                                    .foregroundStyle(BlankColors.mutedInk.opacity(0.78))
                            }
                            Text(issue.title)
                                .font(.blankInter(size: 13, weight: .semibold, relativeTo: .caption))
                                .lineLimit(1)
                                .minimumScaleFactor(0.84)
                        }
                        .layoutPriority(1)

                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BlankColors.mutedInk)
                    }
                    .foregroundStyle(BlankColors.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.74))
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.54), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 330, alignment: .leading)
        .shadow(color: BlankColors.ink.opacity(0.10), radius: 16, x: 0, y: 8)
    }

    @ViewBuilder
    private var centerStatus: some View {
        VStack(spacing: 8) {
            if sessionStore.isBlankActive, let blankActiveSince = sessionStore.blankActiveSince {
                Text(activeTimerText(since: blankActiveSince, until: sessionStore.blankActiveUntil))
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

            #if DEBUG
            #if targetEnvironment(simulator)
            Button("Onboarding") {
                withAnimation(.easeInOut(duration: 0.45)) {
                    _ = sessionStore.deactivateBlank(entryMode: .app, endedReason: .manual)
                    sessionStore.setupComplete = false
                }
                screenTimeBlocker.clear()
                message = nil
                messageAction = nil
                onOpenOnboardingDemo()
            }
            .font(.blankInter(size: 13, weight: .semibold, relativeTo: .footnote))
            .foregroundStyle(sessionStore.isBlankActive ? Color.white.opacity(0.64) : BlankColors.mutedInk)
            .padding(.top, 8)
            .buttonStyle(.plain)
            #endif
            #endif
        }
    }

    private func bottomAction(width: CGFloat) -> some View {
        VStack(spacing: 12) {
            let buttonWidth = sessionStore.isBlankActive ? min(width, 244) : min(width, 184)
            Button(sessionStore.isBlankActive ? (sessionStore.hardBlankActive ? "Hard Blanked" : "Hold to Unblank") : "Iniciar Blank") {
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
                LongPressGesture(minimumDuration: 20)
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
        }
    }

    private func bottomShortcutBar(width: CGFloat) -> some View {
        HStack(spacing: 10) {
            footerShortcut(title: "Timer", icon: "timer") {
                showingTimer = true
            }
            footerShortcut(title: "Assistant", icon: "message") {
                showingAssistantConnect = true
            }
        }
        .frame(width: min(width, 238), height: 44)
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
        let unlockAt = Date().addingTimeInterval(60)
        delayedManualUnlockAt = unlockAt
        updateDelayedUnlockMessage(now: Date())
        Task {
            await BlankFunnelAnalytics.track(
                "relapse_attempt",
                properties: ["source": "hold_to_unblank", "delay_seconds": 60]
            )
        }
        delayedManualUnlockTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
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
        message = seconds > 0 ? "Unlocking in \(seconds)s" : "Unlocking..."
        messageAction = nil
    }

    private var aiRiskNotification: some View {
        Button {
            let result = withAnimation(.easeInOut(duration: 0.65)) {
                sessionStore.activateBlank(durationMinutes: riskBlankMinutes)
            }
            screenTimeBlocker.apply(isBlankActive: sessionStore.isBlankActive)
            setMessage(for: result)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                notificationIcon

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("BLANKED")
                            .font(.blankInter(size: 11, weight: .semibold, relativeTo: .caption2))
                            .foregroundStyle(BlankColors.ink.opacity(0.76))
                        Text("now")
                            .font(.blankInter(size: 11, relativeTo: .caption2))
                            .foregroundStyle(BlankColors.mutedInk.opacity(0.78))
                        Spacer(minLength: 0)
                    }

                    Text("High risk near \(riskWindowText). Start a \(riskBlankMinutes) min blank?")
                        .font(.blankInter(size: 13, weight: .semibold, relativeTo: .caption))
                        .foregroundStyle(BlankColors.ink.opacity(0.94))
                        .lineLimit(2)
                        .minimumScaleFactor(0.84)
                }
                .layoutPriority(1)

                Text("Start \(riskBlankMinutes) min")
                    .font(.blankInter(size: 11, weight: .semibold, relativeTo: .caption2))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background {
                        Capsule().fill(BlankColors.ink.opacity(0.92))
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: 330)
            .background {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .fill(Color.white.opacity(0.64))
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(Color.white.opacity(0.54), lineWidth: 1)
            }
            .shadow(color: BlankColors.ink.opacity(0.12), radius: 18, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("High risk near \(riskWindowText). Start a \(riskBlankMinutes) minute blank.")
    }

    private var notificationIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(BlankColors.ink.opacity(0.92))
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
        }
        .frame(width: 30, height: 30)
    }

    private var shouldShowRiskNotification: Bool {
        guard !sessionStore.isBlankActive,
              purchaseStore.hasPremiumAccess,
              message == nil,
              configIssues.isEmpty else {
            return false
        }

        return aiSystem.forecast.riskScore >= 70 &&
            aiSystem.forecast.minutesUntilRisk <= 90
    }

    private var contextualPickerHeaderText: String {
        "Vamos a implementar el plan. Selecciona \(formattedPendingPlanAppNames) en la lista."
    }

    private var formattedPendingPlanAppNames: String {
        let cleaned = sessionStore.pendingPlanAppNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "las apps recomendadas" }
        guard cleaned.count > 1 else { return cleaned[0] }
        return "\(cleaned.dropLast().joined(separator: ", ")) y \(cleaned.last ?? "")"
    }

    private var riskWindowText: String {
        aiSystem.forecast.riskWindow
    }

    private func scheduleDailyInterventionIfNeeded() {
        guard !sessionStore.isBlankActive,
              purchaseStore.hasPremiumAccess,
              aiSystem.forecast.minutesUntilRisk > 15,
              aiSystem.forecast.minutesUntilRisk <= 180 else {
            return
        }

        let defaults = BlankSharedState.defaults
        let dayKey = Calendar.current.ordinality(of: .day, in: .era, for: now) ?? 0
        let scheduledKey = "blankLastAIInterventionNotificationDay"
        guard defaults.integer(forKey: scheduledKey) != dayKey else { return }
        let system = aiSystem

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "Blanked"
            content.body = DigitalWellnessAI.interventionNotificationText(system: system)
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: TimeInterval(max(60, (system.forecast.minutesUntilRisk - 15) * 60)),
                repeats: false
            )
            let request = UNNotificationRequest(identifier: "blank-ai-daily-intervention", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request) { error in
                guard error == nil else { return }
                defaults.set(dayKey, forKey: scheduledKey)
            }
        }
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

    private var configIssues: [ConfigIssue] {
        var issues: [ConfigIssue] = []
        if screenTimeBlocker.authorizationStatus != .approved {
            issues.append(ConfigIssue(
                title: "Screen Time pending",
                body: "Authorize Screen Time so iOS can apply shields.",
                action: .screenTime
            ))
        }
        if !sessionStore.hasSelectedApps {
            issues.append(ConfigIssue(
                title: "No apps selected",
                body: "Choose apps, categories, or domains before starting.",
                action: .selectApps
            ))
        }
        return issues
    }

    private func resolve(_ action: ConfigIssue.Action) {
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

    private func activeTimerText(since startDate: Date, until endDate: Date?) -> String {
        guard let endDate else {
            return elapsedText(since: startDate)
        }
        return countdownText(until: endDate)
    }

    private func countdownText(until date: Date) -> String {
        let remaining = max(0, Int(date.timeIntervalSince(now)))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let seconds = remaining % 60
        if hours > 0 {
            return String(format: "%01d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
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

private struct ConfigIssue: Identifiable {
    enum Action {
        case screenTime
        case relinkNfc
        case selectApps
    }

    let title: String
    let body: String
    let action: Action

    var id: String { title }
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
    @Binding var showingPicker: Bool
    let onFinish: () -> Void
    @State private var newModeName = ""
    private var textColor: Color { sessionStore.isBlankActive ? Color.white : BlankColors.ink }
    private var secondaryColor: Color { sessionStore.isBlankActive ? Color.white.opacity(0.70) : BlankColors.mutedInk }

    var body: some View {
        List {
            TopSheetHeader(
                title: "Mode",
                subtitle: "Choose the active block mode\nand edit the apps it protects.",
                titleColor: textColor,
                subtitleColor: secondaryColor
            )
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            ForEach(sessionStore.focusModes) { mode in
                modeButton(mode)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 5)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions {
                        Button(role: .destructive) {
                            sessionStore.deleteMode(mode.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(sessionStore.focusModes.count <= 1)
                    }
            }

            VStack(spacing: 10) {
                TextField("Create a custom mode", text: $newModeName)
                    .font(.blankInter(size: 16, weight: .medium, relativeTo: .body))
                    .foregroundStyle(textColor)
                    .padding(.horizontal, 18)
                    .frame(height: 56)
                    .blankGlassCard(cornerRadius: 18, tintOpacity: 0.20)

                Button {
                    sessionStore.createMode(named: newModeName)
                    newModeName = ""
                } label: {
                    TopSheetPrimaryButtonLabel(title: "Create mode")
                }
                .disabled(newModeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(newModeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                .padding(.top, 2)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Button {
                showingPicker = true
                onFinish()
            } label: {
                HStack {
                    Text("Edit current mode apps")
                        .font(.blankInter(size: 16, weight: .medium, relativeTo: .body))
                    Spacer()
                }
                .foregroundStyle(textColor)
                .padding(.horizontal, 18)
                .frame(height: 56)
                .blankGlassCard(cornerRadius: 18, tintOpacity: 0.30)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            AdvancedModeControls(
                showingPicker: $showingPicker,
                onFinish: onFinish,
                textColor: textColor,
                secondaryColor: secondaryColor
            )
            .padding(.horizontal, 24)
            .padding(.top, 8)
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
        .preferredColorScheme(sessionStore.isBlankActive ? .dark : .light)
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

                    Text(isSelected ? blockedAppsText : "Tap to activate this mode")
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

            VStack(alignment: .leading, spacing: 8) {
                Text(shortcutsText)
                    .font(.caption)
                    .foregroundStyle(secondaryColor)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    shortcutPill("Start URL", value: "blank://start")
                    shortcutPill("Stop URL", value: "blank://stop")
                }
            }
            .padding(.top, 2)

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

    private var shortcutsText: String {
        "iOS Shortcuts can open these links automatically. Use Start to turn Blanked on and Stop to turn it off from time, location, Focus, or app automations."
    }

    private func shortcutPill(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(secondaryColor)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .frame(height: 52)
        .blankGlassCard(cornerRadius: 16, tintOpacity: 0.18)
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
    let onClose: () -> Void
    private var textColor: Color { sessionStore.isBlankActive ? Color.white : BlankColors.ink }

    var body: some View {
        let contentTop: CGFloat = 94
        let contentHeight = max(0, screenHeight - contentTop)
        let contentWidth = min(max(0, screenWidth - 32), 360)

        ZStack(alignment: .topLeading) {
            routeContent
                .frame(width: contentWidth, height: contentHeight, alignment: .top)
                .frame(width: screenWidth, height: contentHeight, alignment: .top)
                .offset(x: horizontalOffset, y: contentTop)

            Button {
                onClose()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(textColor)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .position(x: 34, y: 64)
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
        }
    }
}

private struct ScheduleEditorContent: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss
    let onSave: () -> Void
    @State private var windows: [BlankHabitWindow] = [BlankHabitWindow(name: "Habit 1", enabled: false)]
    private var textColor: Color { sessionStore.isBlankActive ? Color.white : BlankColors.ink }
    private var secondaryColor: Color { sessionStore.isBlankActive ? Color.white.opacity(0.70) : BlankColors.mutedInk }

    var body: some View {
        List {
            VStack(alignment: .center, spacing: 16) {
                TopSheetHeader(
                    title: "Habits",
                    subtitle: "Run more than one automatic block\nduring your day.",
                    titleColor: textColor,
                    subtitleColor: secondaryColor
                )

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
                    Label("Add habit", systemImage: "plus")
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

                Text("Scheduled blocks end automatically. Manual exits pause only the current habit window.")
                    .font(.footnote)
                    .foregroundStyle(secondaryColor)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .padding(.top, 2)

                Button {
                    saveSchedule()
                } label: {
                    TopSheetPrimaryButtonLabel(title: "Save")
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
                ? [BlankHabitWindow(name: "Habit 1", enabled: false)]
                : sessionStore.schedule.windows
        }
    }

    private func saveSchedule() {
        let normalized = windows.enumerated().map { index, window in
            BlankHabitWindow(
                id: window.id,
                name: window.name.isEmpty ? "Habit \(index + 1)" : window.name,
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
        windows.append(BlankHabitWindow(name: "Habit \(number)", enabled: true, startMinute: 9 * 60, endMinute: 10 * 60))
    }

    private func deleteWindow(_ id: UUID) {
        guard windows.count > 1 else { return }
        windows.removeAll { $0.id == id }
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
            return "Pause Habits and daily limits temporarily."
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

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                TextField("Habit", text: $window.name)
                    .font(.blankInter(size: 17, weight: .semibold, relativeTo: .headline))
                    .foregroundStyle(textColor)

                Toggle("", isOn: $window.enabled)
                    .labelsHidden()

                if canDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(secondaryColor)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(spacing: 12) {
                WheelTimePicker(minute: $window.startMinute)
                WheelTimePicker(minute: $window.endMinute)
            }

            HabitDaysPicker(
                selectedWeekdays: $window.weekdays,
                textColor: textColor,
                secondaryColor: secondaryColor
            )
        }
        .padding(16)
        .blankGlassCard(cornerRadius: 18, tintOpacity: window.enabled ? 0.30 : 0.18)
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
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Relapse review", systemImage: "sparkles")
                    .font(.blankInter(size: 15, weight: .semibold, relativeTo: .headline))
                    .foregroundStyle(BlankColors.mutedInk)

                Text("Why now?")
                    .font(.blankInter(size: 30, weight: .semibold, relativeTo: .largeTitle))
                    .foregroundStyle(BlankColors.ink)

                Text(intervention.alternative)
                    .font(.blankInter(size: 14, relativeTo: .subheadline))
                    .foregroundStyle(BlankColors.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(RelapseReviewReason.allCases) { reason in
                    Button {
                        onSelect(reason)
                        dismiss()
                    } label: {
                        Text(reason.title)
                            .font(.blankInter(size: 14, weight: .semibold, relativeTo: .subheadline))
                            .foregroundStyle(BlankColors.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(0.78))
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            Button("Skip") {
                dismiss()
            }
            .font(.blankInter(size: 14, weight: .semibold, relativeTo: .subheadline))
            .foregroundStyle(BlankColors.mutedInk)
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(BlankColors.background.ignoresSafeArea())
    }
}

private struct EmergencyScreen: View {
    @EnvironmentObject private var sessionStore: SessionStore
    let emergencyUnlocksRemaining: Int
    let intervention: RelapseIntervention
    let onUnlock: () -> Bool
    @State private var isConfirming = false
    private var textColor: Color { sessionStore.isBlankActive ? Color.white : BlankColors.ink }
    private var secondaryColor: Color { sessionStore.isBlankActive ? Color.white.opacity(0.70) : BlankColors.mutedInk }

    var body: some View {
        List {
            VStack(alignment: .center, spacing: 18) {
                TopSheetHeader(
                    title: isConfirming ? "Are you sure?" : "Emergency",
                    subtitle: isConfirming
                        ? "This will use 1 emergency unlock."
                        : "Use only when you need access now.",
                    titleColor: textColor,
                    subtitleColor: secondaryColor
                )

                if isConfirming {
                    VStack(spacing: 10) {
                        emergencyMetric(title: "Remaining after unlock", value: "\(max(0, emergencyUnlocksRemaining - 1))")
                        emergencyMetric(title: "This week", value: "\(3 - emergencyUnlocksRemaining)/3 used")
                    }
                    .padding(.top, 4)

                    Button("Use emergency") {
                        _ = onUnlock()
                    }
                    .buttonStyle(BlankPrimaryButtonStyle())
                    .disabled(emergencyUnlocksRemaining <= 0)

                    Button("Keep blocking") {
                        isConfirming = false
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(secondaryColor)
                } else {
                    VStack(spacing: 10) {
                        emergencyMetric(title: "Unlocks left", value: "\(emergencyUnlocksRemaining)")
                        emergencyMetric(title: "AI read", value: intervention.headline)
                        emergencyMetric(title: "Better next step", value: intervention.alternative)
                    }

                    Button("Spend emergency") {
                        isConfirming = true
                    }
                    .buttonStyle(BlankPrimaryButtonStyle())
                    .disabled(emergencyUnlocksRemaining <= 0 || !sessionStore.isBlankActive)

                    Text(sessionStore.isBlankActive ? intervention.cost : "Emergency unlocks are available while a block is active.")
                        .font(.footnote)
                        .foregroundStyle(secondaryColor)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
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
        .background(Color.clear)
        .preferredColorScheme(sessionStore.isBlankActive ? .dark : .light)
    }

    private func emergencyMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.blankInter(size: 12, weight: .semibold, relativeTo: .caption))
                .foregroundStyle(secondaryColor)
            Text(value)
                .font(.blankInter(size: 18, weight: .semibold, relativeTo: .headline))
                .foregroundStyle(textColor)
                .lineLimit(2)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .frame(minHeight: 62)
        .blankGlassCard(cornerRadius: 18, tintOpacity: 0.28)
    }
}

private struct RelinkSheet: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss
    @Binding var message: String?
    @Binding var messageAction: ConfigIssue.Action?
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

private struct TimerStartSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hardMode = false
    let onStart: (Int, Bool) -> Void
    private let options = [15, 30, 45, 60, 90, 120]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Timer")
                .font(.blankInter(size: 38, weight: .medium, relativeTo: .largeTitle))
            Text(hardMode ? "Hard Blanked ends when the timer finishes. Early exit spends an emergency." : "Blank turns off automatically when the timer ends.")
                .foregroundStyle(.secondary)

            Toggle("Hard Blanked", isOn: $hardMode)
                .font(.blankInter(size: 16, weight: .semibold, relativeTo: .body))
                .padding(.horizontal, 18)
                .frame(height: 56)
                .blankGlassCard(cornerRadius: 18, tintOpacity: 0.28)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(options, id: \.self) { minutes in
                    Button(formatDuration(minutes)) {
                        onStart(minutes, hardMode)
                        dismiss()
                    }
                    .buttonStyle(BlankSecondaryButtonStyle())
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BlankAtmosphericBackground())
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
    @Environment(\.dismiss) private var dismiss
    @AppStorage("blankAssistantPhoneNumber", store: BlankSharedState.defaults) private var phoneNumber = ""
    @AppStorage("blankAssistantConnectCode", store: BlankSharedState.defaults) private var connectCode = ""
    @AppStorage("blankAssistantPreferredChannel", store: BlankSharedState.defaults) private var preferredChannel = ""
    @AppStorage("blankAssistantConnectedAt", store: BlankSharedState.defaults) private var connectedAt = ""

    let whatsAppNumber: String?
    let smsNumber: String?
    let openURL: OpenURLAction

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Assistant")
                .font(.blankInter(size: 38, weight: .medium, relativeTo: .largeTitle))

            Text("Connect WhatsApp or SMS to use Blanked outside the app. The app stays as your control center for blocks, Health, reports and settings.")
                .foregroundStyle(.secondary)
                .lineSpacing(2)

            VStack(alignment: .leading, spacing: 8) {
                Text("Phone")
                    .font(.blankInter(size: 13, weight: .semibold, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                TextField("+1 555 000 0000", text: $phoneNumber)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .font(.blankInter(size: 16, weight: .medium, relativeTo: .body))
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .blankGlassCard(cornerRadius: 16, tintOpacity: 0.28)
            }

            VStack(spacing: 10) {
                Button {
                    openAssistantChannel(.whatsApp)
                } label: {
                    Label("Connect WhatsApp", systemImage: "message.fill")
                }
                .buttonStyle(BlankPrimaryButtonStyle())
                .disabled(whatsAppNumber == nil)

                Button {
                    openAssistantChannel(.sms)
                } label: {
                    Label("Connect SMS", systemImage: "message")
                }
                .buttonStyle(BlankSecondaryButtonStyle())
                .disabled(smsNumber == nil)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Code")
                    .font(.blankInter(size: 12, weight: .semibold, relativeTo: .caption2))
                    .foregroundStyle(.secondary)
                Text(connectMessage)
                    .font(.blankInter(size: 14, weight: .semibold, relativeTo: .footnote))
                    .textSelection(.enabled)
            }
            .padding(.top, 2)

            if !connectedAt.isEmpty {
                Text("\(preferredChannel.capitalized) connection started \(connectedAt).")
                    .font(.blankInter(size: 13, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BlankAtmosphericBackground())
        .onAppear {
            ensureConnectCode()
        }
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
