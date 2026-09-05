import AVFoundation
import FamilyControls
import Foundation
import Speech
import SwiftUI
import UserNotifications

enum BlankedRuntimeMode {
    static let softwareOnly = true
    static let legacyAccessEnabled = false
    static let legacyNfcEnabled = false
}

struct ContentView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var showingOnboardingDemo = false

    var body: some View {
        ZStack {
            if showingOnboardingDemo {
                SetupView {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        showingOnboardingDemo = false
                    }
                }
                .transition(.opacity)
            } else {
                HomeView {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        showingOnboardingDemo = true
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showingOnboardingDemo)
    }
}

private struct ConversationalHomeView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var screenTimeBlocker: ScreenTimeBlocker
    @EnvironmentObject private var purchaseStore: StoreKitPurchaseStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @AppStorage("blankOnboardingName", store: BlankSharedState.defaults) private var onboardingName = ""
    @AppStorage("blankWhatsAppConsentGranted", store: BlankSharedState.defaults) private var whatsAppConsentGranted = false

    @State private var input = ""
    @State private var messages: [AgentMessage] = AgentMessage.openingThread
    @State private var activePlan: AgentPlan?
    @State private var activeSection: HomeSection?
    @State private var showingPicker = false
    @State private var now = Date()
    @State private var dictationBaseInput = ""
    @State private var showingWhatsAppConsent = false
    @State private var showingWidgetTimerSelector = false
    @StateObject private var dictation = SpeechDictationController()
    let onOpenOnboardingDemo: () -> Void

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(_ onOpenOnboardingDemo: @escaping () -> Void = {}) {
        self.onOpenOnboardingDemo = onOpenOnboardingDemo
    }

    private var system: DigitalWellnessV3System {
        sessionStore.digitalWellnessV3
    }

    private var statusLine: String {
        if sessionStore.isBlankActive {
            if let until = sessionStore.blankActiveUntil {
                return "Protected until \(agentClockText(until))"
            }
            return "Protection active"
        }
        if let pausedUntil = sessionStore.vacationModeUntil, pausedUntil > now {
            return "Vacation mode until \(agentClockText(pausedUntil))"
        }
        if let window = sessionStore.schedule.activeWindows.first {
            return "Next protection: \(agentMinuteText(window.startMinute))"
        }
        return "Ready to protect"
    }

    private var nextRecommendation: String {
        if !sessionStore.hasSelectedApps {
            return "Choose the apps Blanked can control."
        }
        if screenTimeBlocker.authorizationStatus != .approved {
            return "Screen Time permission is needed."
        }
        return system.forecast.recommendedAction
    }

    var body: some View {
        ZStack {
            AppBackground(isActive: sessionStore.isBlankActive)

            GeometryReader { proxy in
                let viewportWidth = proxy.size.width
                let viewportHeight = proxy.size.height
                let topSafeArea = proxy.safeAreaInsets.top > 0 ? proxy.safeAreaInsets.top : 44
                let bottomSafeArea = proxy.safeAreaInsets.bottom > 0 ? proxy.safeAreaInsets.bottom : 18
                let horizontalPadding = min(max(viewportWidth * 0.075, 28), 36)
                let contentWidth = viewportWidth - horizontalPadding * 2
                let chatWidth = min(contentWidth, 342)
                let topBarCenterY = topSafeArea + 26 + 47 / 2
                let topBarBottom = topSafeArea + 26 + 47
                let contentTopPadding = topSafeArea + 26 + 47 + 34
                let composerWidth = min(contentWidth, 342)
                let composerBottomPadding = max(bottomSafeArea + 18, 34)
                let chatBottomClearance = composerBottomPadding + 150
                let visualCenterCorrection: CGFloat = -24

                ZStack(alignment: .top) {
                    if activeSection == nil {
                        VStack(spacing: 0) {
                            topBar
                                .offset(x: visualCenterCorrection)
                            Spacer(minLength: 0)
                        }
                        .padding(.top, topBarCenterY - 47 / 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .zIndex(2)

                        if messages.isEmpty && activePlan == nil {
                            VStack(spacing: 0) {
                                Spacer(minLength: max(0, viewportHeight * 0.40 - 58))
                                VStack(spacing: 18) {
                                    welcomeHero
                                    demoButtons
                                }
                                .frame(width: min(contentWidth, 350))
                                .offset(x: visualCenterCorrection)
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        }

                        if !messages.isEmpty || activePlan != nil {
                            ScrollViewReader { scrollProxy in
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 12) {
                                        ForEach(messages) { message in
                                            AgentBubble(message: message, maxWidth: chatWidth)
                                                .id(message.id)
                                        }

                                        if let activePlan {
                                            AgentPlanCard(
                                                plan: activePlan,
                                                canApply: canApply(activePlan),
                                                maxWidth: chatWidth,
                                                onPrimary: { apply(activePlan) },
                                                onSecondary: { handleSecondary(activePlan) }
                                            )
                                            .id(activePlan.id)
                                        }
                                    }
                                    .frame(width: chatWidth, alignment: .leading)
                                    .padding(.top, contentTopPadding)
                                    .padding(.bottom, chatBottomClearance)
                                }
                                .frame(maxWidth: .infinity)
                                .offset(x: visualCenterCorrection)
                                .mask(
                                    chatVisibilityMask(
                                        height: viewportHeight,
                                        topFadeStart: topBarBottom - 6,
                                        topFadeEnd: contentTopPadding,
                                        bottomFadeStart: viewportHeight - chatBottomClearance - 18,
                                        bottomFadeEnd: viewportHeight - composerBottomPadding + 8
                                    )
                                )
                                .onChange(of: messages.count) { _ in
                                    scrollToBottom(scrollProxy)
                                }
                                .onChange(of: activePlan?.id) { _ in
                                    scrollToBottom(scrollProxy)
                                }
                            }
                            .scrollIndicators(.hidden)
                            .overlay {
                                chatFadeOverlays(
                                    topHeight: contentTopPadding,
                                    bottomHeight: chatBottomClearance,
                                    bottomPadding: composerBottomPadding
                                )
                            }
                        }

                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            composer
                                .frame(width: composerWidth)
                                .offset(x: visualCenterCorrection)
                        }
                        .padding(.bottom, composerBottomPadding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }

                    if let activeSection {
                        HomeSectionScreen(
                            showingPicker: $showingPicker,
                            section: activeSection,
                            screenWidth: viewportWidth,
                            screenHeight: viewportHeight,
                            horizontalOffset: visualCenterCorrection,
                            intervention: system.relapseIntervention,
                            onEmergencyUnlock: performEmergencyUnlock
                        ) {
                            closeSection()
                        }
                        .frame(width: viewportWidth, height: viewportHeight, alignment: .topLeading)
                        .transition(.opacity)
                        .zIndex(5)
                    }
                }
                .frame(width: viewportWidth, height: viewportHeight, alignment: .top)
                .animation(.easeInOut(duration: 0.35), value: activeSection)
            }
        }
        .ignoresSafeArea()
        .foregroundStyle(sessionStore.isBlankActive ? Color.white : BlankColors.ink)
        .preferredColorScheme(sessionStore.isBlankActive ? .dark : .light)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .familyActivityPicker(isPresented: $showingPicker, selection: $sessionStore.selection)
        .onAppear {
            restoreRuntimeState()
            openWidgetTimerSelectorIfNeeded()
            scheduleDailyInterventionIfNeeded()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            restoreRuntimeState()
            scheduleDailyInterventionIfNeeded()
        }
        .onReceive(timer) { date in
            now = date
            sessionStore.syncFromSharedDefaults(now: date)
            sessionStore.applyScheduleWindow(at: date)
            screenTimeBlocker.updateAdvancedControls(
                allowOnlyModeEnabled: sessionStore.allowOnlyModeEnabled,
                adultContentBlockingEnabled: sessionStore.adultContentBlockingEnabled
            )
            screenTimeBlocker.apply(isBlankActive: sessionStore.isBlankActive)
        }
        .onChange(of: sessionStore.selection) { selection in
            screenTimeBlocker.updateSelection(selection, isBlankActive: sessionStore.isBlankActive)
            sessionStore.refreshDailyLimitMonitoring()
        }
        .onChange(of: sessionStore.allowOnlyModeEnabled) { _ in
            restoreRuntimeState()
            if sessionStore.allowOnlyModeEnabled && !sessionStore.hasSelectedApps {
                showingPicker = true
            }
        }
        .onChange(of: sessionStore.adultContentBlockingEnabled) { _ in
            restoreRuntimeState()
        }
        .onChange(of: sessionStore.shouldShowWidgetTimerSelector) { shouldShow in
            guard shouldShow else { return }
            openWidgetTimerSelectorIfNeeded()
        }
        .onChange(of: dictation.transcript) { transcript in
            updateInputFromDictation(transcript)
        }
        .onChange(of: dictation.errorMessage) { message in
            guard let message else { return }
            messages.append(AgentMessage(role: .blanked, text: message))
        }
        .confirmationDialog("Connect WhatsApp", isPresented: $showingWhatsAppConsent, titleVisibility: .visible) {
            Button("Connect WhatsApp") {
                whatsAppConsentGranted = true
                openWhatsApp()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("WhatsApp messages are handled by WhatsApp/Meta. Blanked uses this channel only for messages you send and replies from Blanked AI.")
        }
        .sheet(isPresented: $showingWidgetTimerSelector) {
            WidgetTimerSelectionSheet(
                selectedMinutes: sessionStore.pendingWidgetTimerMinutes,
                onSelect: { minutes in
                    sessionStore.selectWidgetTimer(minutes: minutes)
                }
            )
            .presentationDetents([.medium])
        }
    }

    private func openWidgetTimerSelectorIfNeeded() {
        guard sessionStore.shouldShowWidgetTimerSelector else { return }
        showingWidgetTimerSelector = true
        sessionStore.shouldShowWidgetTimerSelector = false
    }

    private var welcomeHero: some View {
        VStack(spacing: 7) {
            Text("Hello \(displayName)")
                .font(.blankInter(size: 14, weight: .regular, relativeTo: .subheadline))
                .foregroundStyle(BlankColors.ink.opacity(0.58))
                .tracking(0)

            Text("How can I help\nyou today?")
                .font(.blankInter(size: 33, weight: .semibold, relativeTo: .largeTitle))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .lineSpacing(0)
                .tracking(0)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var displayName: String {
        let trimmed = onboardingName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "there" : trimmed
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
            .accessibilityLabel("Advanced controls")

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
                    BlankGlassCornerHighlight(width: 78, height: 30, xOffset: -79, yOffset: -15)
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

    private func chatVisibilityMask(
        height: CGFloat,
        topFadeStart: CGFloat,
        topFadeEnd: CGFloat,
        bottomFadeStart: CGFloat,
        bottomFadeEnd: CGFloat
    ) -> some View {
        let safeHeight = max(height, 1)
        let topStart = min(max(topFadeStart / safeHeight, 0), 1)
        let topEnd = min(max(topFadeEnd / safeHeight, topStart), 1)
        let bottomStart = min(max(bottomFadeStart / safeHeight, topEnd), 1)
        let bottomEnd = min(max(bottomFadeEnd / safeHeight, bottomStart), 1)

        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: topStart),
                .init(color: .black, location: topEnd),
                .init(color: .black, location: bottomStart),
                .init(color: .clear, location: bottomEnd),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func chatFadeOverlays(topHeight: CGFloat, bottomHeight: CGFloat, bottomPadding: CGFloat) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(height: max(topHeight, 0))
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black.opacity(0.9), location: 0.55),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Spacer(minLength: 0)

            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(height: max(bottomHeight, bottomPadding + 96))
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.9), location: 0.45),
                            .init(color: .black, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .allowsHitTesting(false)
    }

    private var composer: some View {
        HStack(spacing: 12) {
            TextField(dictation.isRecording ? "Listening..." : "Tell Blanked what you need", text: $input, axis: .vertical)
                .font(.blankInter(size: 16, relativeTo: .body))
                .lineLimit(1...2)
                .foregroundStyle(sessionStore.isBlankActive ? Color.white : BlankColors.ink)
                .padding(.leading, 22)

            Button {
                toggleDictation()
            } label: {
                Image(systemName: dictation.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(dictation.isRecording ? Color.red.opacity(0.86) : BlankColors.ink.opacity(0.66)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(dictation.isRecording ? "Stop dictation" : "Start dictation")

            Button {
                submit()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(BlankColors.ink.opacity(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.22 : 0.88)))
            }
            .buttonStyle(.plain)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.trailing, 7)
        }
        .frame(height: 58)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
            Capsule()
                .fill(Color.white.opacity(sessionStore.isBlankActive ? 0.10 : 0.36))
        }
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(sessionStore.isBlankActive ? 0.18 : 0.34), lineWidth: 1)
        }
        .shadow(color: BlankColors.ink.opacity(0.06), radius: 16, x: 0, y: 8)
    }

    @ViewBuilder
    private var demoButtons: some View {
        #if targetEnvironment(simulator)
        HStack(spacing: 10) {
            Button {
                onOpenOnboardingDemo()
            } label: {
                demoButtonLabel("Onboarding", systemImage: "rectangle.stack")
            }
            .buttonStyle(.plain)

            Button {
                purchaseStore.enableDemoProAccess()
            } label: {
                demoButtonLabel(purchaseStore.hasPremiumAccess ? "Pro active" : "Pro demo", systemImage: "crown")
            }
            .buttonStyle(.plain)
        }
        #endif
    }

    private func demoButtonLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.blankInter(size: 12, weight: .semibold, relativeTo: .caption))
            .foregroundStyle(Color.white.opacity(0.92))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background {
                Capsule().fill(Color.white.opacity(0.18))
            }
            .overlay {
                Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1)
            }
    }

    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                AgentQuickAction(title: "Sleep", systemImage: "moon.fill") {
                    runPrompt("I want to stop scrolling at night.")
                }
                AgentQuickAction(title: "Focus", systemImage: "timer") {
                    runPrompt("I need to focus now.")
                }
                AgentQuickAction(title: "Emergency", systemImage: "bolt.fill") {
                    runPrompt("I'm losing control.")
                }
                AgentQuickAction(title: "Allow Only", systemImage: "checkmark.shield.fill") {
                    runPrompt("Leave me only WhatsApp and Maps.")
                }
                AgentQuickAction(title: "Vacation", systemImage: "pause.fill") {
                    runPrompt("I'm on vacation.")
                }
                AgentQuickAction(title: "Week", systemImage: "chart.xyaxis.line") {
                    runPrompt("Analyze my week.")
                }
                AgentQuickAction(title: "WhatsApp", systemImage: "message.fill") {
                    connectWhatsApp()
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var currentSecondaryColor: Color {
        sessionStore.isBlankActive ? Color.white.opacity(0.70) : BlankColors.mutedInk
    }

    private func openSection(_ section: HomeSection) {
        withAnimation(.easeInOut(duration: 0.35)) {
            activeSection = section
        }
    }

    private func closeSection() {
        withAnimation(.easeInOut(duration: 0.35)) {
            activeSection = nil
        }
    }

    private func restoreRuntimeState() {
        sessionStore.syncFromSharedDefaults()
        sessionStore.applyScheduleWindow()
        screenTimeBlocker.refreshAuthorizationStatus()
        screenTimeBlocker.updateAdvancedControls(
            allowOnlyModeEnabled: sessionStore.allowOnlyModeEnabled,
            adultContentBlockingEnabled: sessionStore.adultContentBlockingEnabled
        )
        screenTimeBlocker.apply(isBlankActive: sessionStore.isBlankActive)
    }

    private func scheduleDailyInterventionIfNeeded() {
        guard !sessionStore.isBlankActive,
              purchaseStore.hasPremiumAccess,
              system.forecast.minutesUntilRisk > 15,
              system.forecast.minutesUntilRisk <= 180 else {
            return
        }

        let defaults = BlankSharedState.defaults
        let dayKey = Calendar.current.ordinality(of: .day, in: .era, for: now) ?? 0
        let scheduledKey = "blankLastAIInterventionNotificationDay"
        guard defaults.integer(forKey: scheduledKey) != dayKey else { return }
        let forecastSystem = system

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "Blanked"
            content.body = DigitalWellnessAI.interventionNotificationText(system: forecastSystem)
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: TimeInterval(max(60, (forecastSystem.forecast.minutesUntilRisk - 15) * 60)),
                repeats: false
            )
            let request = UNNotificationRequest(identifier: "blank-agent-daily-intervention", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request) { error in
                guard error == nil else { return }
                defaults.set(dayKey, forKey: scheduledKey)
            }
        }
    }

    private func submit() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        dictation.stop()
        input = ""
        runPrompt(text)
    }

    private func toggleDictation() {
        if dictation.isRecording {
            dictation.stop()
            return
        }
        dictationBaseInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        dictation.start()
    }

    private func updateInputFromDictation(_ transcript: String) {
        guard dictation.isRecording else { return }
        let spokenText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spokenText.isEmpty else { return }
        input = dictationBaseInput.isEmpty ? spokenText : "\(dictationBaseInput) \(spokenText)"
    }

    private func connectWhatsApp() {
        guard whatsAppConsentGranted else {
            showingWhatsAppConsent = true
            return
        }
        openWhatsApp()
    }

    private func openWhatsApp() {
        guard let number = configuredWhatsAppNumber(), let url = URL(string: "https://wa.me/\(number)?text=Help%20me%20protect%20my%20phone") else {
            messages.append(AgentMessage(role: .blanked, text: "WhatsApp is ready in the app, but the official Blanked number is not configured yet."))
            return
        }
        openURL(url)
    }

    private func configuredWhatsAppNumber() -> String? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "BlankWhatsAppPhoneNumber") as? String else { return nil }
        let digits = rawValue.filter(\.isNumber)
        return digits.isEmpty ? nil : digits
    }

    private func runPrompt(_ text: String) {
        messages.append(AgentMessage(role: .user, text: text))
        let fallbackPlan = BlankedAgentPlanner.plan(
            for: text,
            context: AgentContext(
                isBlankActive: sessionStore.isBlankActive,
                hasSelectedApps: sessionStore.hasSelectedApps,
                selectionCount: sessionStore.selectionCount,
                screenTimeAuthorized: screenTimeBlocker.authorizationStatus == .approved,
                system: system,
                emergencyUnlocksRemaining: sessionStore.emergencyUnlocksRemaining,
                vacationModeActive: sessionStore.isVacationModeActive,
                modeName: sessionStore.currentMode.name,
                availableModes: sessionStore.focusModes.map(\.name)
            )
        )
        BlankedAgentMemory.recordUserPrompt(text, inferredIntent: fallbackPlan.intent)
        activePlan = nil
        let thinkingMessage = AgentMessage(role: .blanked, text: "Reading the pattern...")
        messages.append(thinkingMessage)

        let context = currentAgentContext()
        Task {
            let resolvedPlan: AgentPlan
            do {
                resolvedPlan = try await BlankedAgentClient().plan(prompt: text, context: context)
            } catch {
                #if targetEnvironment(simulator)
                var debugPlan = fallbackPlan
                debugPlan.source = "local_fallback"
                debugPlan.modelError = error.localizedDescription
                resolvedPlan = debugPlan
                #else
                resolvedPlan = fallbackPlan
                #endif
            }
            await MainActor.run {
                activePlan = resolvedPlan.hasExecutableActions ? resolvedPlan : nil
                if let index = messages.firstIndex(where: { $0.id == thinkingMessage.id }) {
                    messages[index].text = resolvedPlan.responseText
                }
            }
        }
    }

    private func currentAgentContext() -> AgentContext {
        AgentContext(
            isBlankActive: sessionStore.isBlankActive,
            hasSelectedApps: sessionStore.hasSelectedApps,
            selectionCount: sessionStore.selectionCount,
            screenTimeAuthorized: screenTimeBlocker.authorizationStatus == .approved,
            system: system,
            emergencyUnlocksRemaining: sessionStore.emergencyUnlocksRemaining,
            vacationModeActive: sessionStore.isVacationModeActive,
            modeName: sessionStore.currentMode.name,
            availableModes: sessionStore.focusModes.map(\.name)
        )
    }

    private func canApply(_ plan: AgentPlan) -> Bool {
        if !plan.hasExecutableActions {
            return false
        }
        if plan.requiresSelectedApps && !sessionStore.hasSelectedApps {
            return false
        }
        if plan.requiresScreenTimeAuthorization && screenTimeBlocker.authorizationStatus != .approved {
            return false
        }
        return true
    }

    private func apply(_ plan: AgentPlan) {
        guard canApply(plan) else {
            handleSecondary(plan)
            return
        }

        var appliedLabels: [String] = []

        for action in plan.actions {
            switch action {
            case .startProtection(let minutes, let hardMode):
                let result = sessionStore.activateBlank(durationMinutes: minutes, hardMode: hardMode)
                screenTimeBlocker.apply(isBlankActive: sessionStore.isBlankActive)
                appliedLabels.append(agentResultText(result))
            case .applySchedule(let name, let startMinute, let endMinute, let weekdays, let durationDays):
                sessionStore.applyAdaptivePlan(startMinute: startMinute, endMinute: endMinute, durationDays: durationDays)
                if var window = sessionStore.schedule.windows.first {
                    window.name = name
                    window.weekdays = weekdays
                    sessionStore.schedule.windows = [window]
                }
                appliedLabels.append("Plan scheduled")
            case .enableAllowOnly:
                sessionStore.allowOnlyModeEnabled = true
                showingPicker = true
                appliedLabels.append("Allow Only enabled")
            case .enableAdultFilter:
                sessionStore.adultContentBlockingEnabled = true
                appliedLabels.append("Adult filter enabled")
            case .setDailyLimit(let minutes):
                sessionStore.dailyLimitMinutes = minutes
                sessionStore.dailyLimitEnabled = true
                appliedLabels.append("Daily limit set")
            case .pauseRules(let hours):
                sessionStore.enableVacationMode(hours: hours)
                appliedLabels.append("Rules paused")
            case .disablePause:
                sessionStore.disableVacationMode()
                appliedLabels.append("Rules resumed")
            case .switchMode(let name):
                if sessionStore.selectMode(named: name) {
                    appliedLabels.append("\(name) mode selected")
                } else {
                    showingPicker = true
                    appliedLabels.append("Choose apps for \(name)")
                }
            case .openAppPicker:
                showingPicker = true
                appliedLabels.append("App picker opened")
            case .requestScreenTimePermission:
                Task {
                    _ = await screenTimeBlocker.requestAuthorization()
                    restoreRuntimeState()
                }
                appliedLabels.append("Permission requested")
            case .applyAIPlan:
                sessionStore.applyAIPlan()
                appliedLabels.append("Adaptive plan applied")
            case .none:
                break
            }
        }

        Task {
            await BlankFunnelAnalytics.track(
                "agent_plan_applied",
                properties: [
                    "intent": plan.intent.rawValue,
                    "action_count": plan.executableActionCount,
                    "selection_count": sessionStore.selectionCount
                ]
            )
        }
        BlankedAgentMemory.recordAppliedPlan(plan, context: currentAgentContext())

        let confirmation = appliedLabels.isEmpty ? "Done." : "Done. \(appliedLabels.joined(separator: ". "))."
        messages.append(AgentMessage(role: .blanked, text: confirmation))
        activePlan = nil
    }

    private func handleSecondary(_ plan: AgentPlan) {
        if !sessionStore.hasSelectedApps && plan.requiresSelectedApps {
            showingPicker = true
            messages.append(AgentMessage(role: .blanked, text: "Choose the apps or categories first. Then I can apply this plan."))
            return
        }
        if screenTimeBlocker.authorizationStatus != .approved && plan.requiresScreenTimeAuthorization {
            Task {
                _ = await screenTimeBlocker.requestAuthorization()
                restoreRuntimeState()
            }
            messages.append(AgentMessage(role: .blanked, text: "I need Screen Time permission before I can protect your phone."))
            return
        }
        activeSection = .schedule
    }

    private func performEmergencyUnlock() -> Bool {
        guard sessionStore.emergencyUnlocksRemaining > 0 else {
            messages.append(AgentMessage(role: .blanked, text: "No emergency unlocks left today."))
            return false
        }
        let unlocked = withAnimation(.easeInOut(duration: 0.65)) {
            sessionStore.deactivateForEmergency()
        }
        if unlocked {
            screenTimeBlocker.clear()
            activeSection = nil
            messages.append(AgentMessage(role: .blanked, text: "Emergency unlock used. Apps are available now."))
        }
        return unlocked
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            if let activePlan {
                proxy.scrollTo(activePlan.id, anchor: .bottom)
            } else if let last = messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func agentResultText(_ result: SessionStore.NfcResult) -> String {
        switch result {
        case .blanked:
            return "Protection started"
        case .noAppsSelected:
            return "Choose apps first"
        case .hardBlankLocked:
            return "Hard Blanked is locked"
        case .schedulePaused:
            return "Schedule paused"
        case .tagRegistered:
            return "Blank linked"
        case .unblanked:
            return "Protection is off"
        case .wrongTag:
            return "Wrong Blank"
        }
    }
}

@MainActor
private final class SpeechDictationController: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var transcript = ""
    @Published var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func start() {
        guard !isRecording else { return }
        transcript = ""
        errorMessage = nil

        SFSpeechRecognizer.requestAuthorization { [weak self] speechStatus in
            AVAudioSession.sharedInstance().requestRecordPermission { micGranted in
                Task { @MainActor in
                    guard let self else { return }
                    guard speechStatus == .authorized, micGranted else {
                        self.errorMessage = "Enable microphone and speech recognition to dictate messages."
                        return
                    }
                    self.beginRecording()
                }
            }
        }
    }

    func stop() {
        guard isRecording || audioEngine.isRunning else { return }
        audioEngine.stop()
        recognitionRequest?.endAudio()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func beginRecording() {
        guard speechRecognizer?.isAvailable == true else {
            errorMessage = "Dictation is not available right now."
            return
        }

        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak request] buffer, _ in
                request?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        if result.isFinal {
                            self.stop()
                        }
                    } else if error != nil, self.isRecording {
                        self.errorMessage = "Dictation stopped. Try again."
                        self.stop()
                    }
                }
            }
        } catch {
            errorMessage = "Dictation could not start."
            stop()
        }
    }
}

private struct AgentContext {
    var isBlankActive: Bool
    var hasSelectedApps: Bool
    var selectionCount: Int
    var screenTimeAuthorized: Bool
    var system: DigitalWellnessV3System
    var emergencyUnlocksRemaining: Int
    var vacationModeActive: Bool
    var modeName: String = "Routine"
    var availableModes: [String] = []
    var memory: [String: Any] {
        BlankedAgentMemory.snapshot(system: system)
    }
}

private enum AgentIntent: String, Codable {
    case sleep
    case focus
    case study
    case emergency
    case allowOnly
    case vacation
    case weeklyReview
    case adultContent
    case social
    case general
}

private enum AgentAction: Equatable {
    case startProtection(minutes: Int, hardMode: Bool)
    case applySchedule(name: String, startMinute: Int, endMinute: Int, weekdays: [Int], durationDays: Int)
    case enableAllowOnly
    case enableAdultFilter
    case setDailyLimit(minutes: Int)
    case pauseRules(hours: Int)
    case disablePause
    case switchMode(name: String)
    case openAppPicker
    case requestScreenTimePermission
    case applyAIPlan
    case none
}

private struct AgentPlan: Identifiable, Equatable {
    var id = UUID()
    var intent: AgentIntent
    var title: String
    var responseText: String
    var bullets: [String]
    var primaryLabel: String
    var secondaryLabel: String
    var actions: [AgentAction]
    var requiresSelectedApps: Bool
    var requiresScreenTimeAuthorization: Bool
    var source: String? = nil
    var modelError: String? = nil

    var executableActionCount: Int {
        actions.filter { $0 != .none }.count
    }

    var hasExecutableActions: Bool {
        executableActionCount > 0
    }
}

private struct AgentMessage: Identifiable, Equatable {
    enum Role {
        case user
        case blanked
    }

    var id = UUID()
    var role: Role
    var text: String

    static let openingThread: [AgentMessage] = []
}

private enum BlankedAgentPlanner {
    static func plan(for prompt: String, context: AgentContext) -> AgentPlan {
        let intent = classify(prompt)
        if appCorrection(in: prompt) {
            return correctionPlan()
        }
        if let missingContextPlan = missingContextPlan(for: prompt, intent: intent, context: context) {
            return missingContextPlan
        }
        if let window = explicitTimeWindow(in: prompt),
           [.sleep, .focus, .social, .general].contains(intent) {
            return explicitWindowPlan(intent: intent == .general ? .social : intent, window: window, context: context)
        }
        if intent == .sleep, let bedtime = explicitSingleTime(in: prompt) {
            return bedtimeBoundaryPlan(bedtime: bedtime, context: context)
        }

        switch intent {
        case .sleep:
            return sleepPlan(context: context)
        case .focus:
            return focusPlan(context: context)
        case .study:
            return studyPlan(context: context)
        case .emergency:
            return emergencyPlan(context: context)
        case .allowOnly:
            return allowOnlyPlan(context: context)
        case .vacation:
            return vacationPlan(context: context)
        case .weeklyReview:
            return weeklyReviewPlan(context: context)
        case .adultContent:
            return adultContentPlan(context: context)
        case .social:
            return socialPlan(prompt: prompt, context: context)
        case .general:
            return generalPlan(prompt: prompt, context: context)
        }
    }

    private static func explicitWindowPlan(intent: AgentIntent, window: AgentTimeWindow, context: AgentContext) -> AgentPlan {
        let start = agentMinuteText(window.startMinute)
        let end = agentMinuteText(window.endMinute)
        return AgentPlan(
            intent: intent,
            title: intent == .sleep ? "Sleep Protection Plan" : "Scroll Control Plan",
            responseText: "I read this as a specific protection window: \(start) to \(end).",
            bullets: [
                "Pattern: the risky moment is already clear, so guessing is unnecessary.",
                "Move: shield distracting apps from \(start) to \(end).",
                context.hasSelectedApps ? "Use your current app selection." : "Choose the apps Blanked should control first."
            ],
            primaryLabel: "Apply plan",
            secondaryLabel: "Choose apps",
            actions: [
                .applySchedule(name: intent == .sleep ? "Sleep Protection" : "Scroll Control", startMinute: window.startMinute, endMinute: window.endMinute, weekdays: Array(1...7), durationDays: 7)
            ],
            requiresSelectedApps: true,
            requiresScreenTimeAuthorization: true
        )
    }

    private static func classify(_ prompt: String) -> AgentIntent {
        let text = prompt.lowercased()
        if asksWhereToStart(text) { return .general }
        if contains(text, ["porn", "porno", "adult", "xxx"]) { return .adultContent }
        if contains(text, ["losing control", "perdiendo el control", "reca", "relapse", "urge", "emergency", "can't stop", "no puedo parar"]) { return .emergency }
        if contains(text, ["sleep", "night", "bed", "dormir", "noche", "scroll por la noche", "tired", "cansado"]) { return .sleep }
        if contains(text, ["exam", "study", "estudio", "estudiar", "examen", "opos"]) { return .study }
        if contains(text, ["allow only", "whatsapp", "maps", "solo", "only"]) { return .allowOnly }
        if contains(text, ["vacation", "holiday", "vacaciones", "pause", "pausa"]) { return .vacation }
        if contains(text, ["week", "semana", "analy", "diagn"]) { return .weeklyReview }
        if contains(text, ["social", "tiktok", "instagram", "youtube", "gaming", "game", "dopamine", "scroll", "doomscroll", "reels", "shorts", "feed", "anxious", "anxiety", "ansiedad", "bored", "aburr", "guilt", "culpa"]) { return .social }
        if contains(text, ["focus", "work", "productiv", "foco", "trabaj"]) { return .focus }
        return .general
    }

    private static func missingContextPlan(for prompt: String, intent: AgentIntent, context: AgentContext) -> AgentPlan? {
        let text = prompt.lowercased()
        if intent == .social,
           explicitTimeWindow(in: prompt) == nil,
           BlankedAgentMemory.rememberedWeakHours(system: context.system).isEmpty,
           let momentPlan = relativeMomentPlan(for: prompt) {
            return momentPlan
        }

        if intent == .sleep,
           explicitTimeWindow(in: prompt) == nil,
           explicitSingleTime(in: prompt) == nil,
           BlankedAgentMemory.rememberedBedtimeMinute() == nil,
           !hasExplicitBlockRequest(text) {
            return AgentPlan(
                intent: .sleep,
                title: "Bedtime Scroll Read",
                responseText: "This sounds like a bedtime scroll loop. Before I block anything, I need your sleep target.",
                bullets: [
                    "Read: you want nights to feel less automatic.",
                    "Pattern: the risky window depends on when you actually go to sleep.",
                    "Move: tell me your usual bedtime, then I can suggest the right boundary."
                ],
                primaryLabel: "Got it",
                secondaryLabel: "Open report",
                actions: [],
                requiresSelectedApps: false,
                requiresScreenTimeAuthorization: false
            )
        }

        if intent == .social,
           contains(text, ["scroll", "doomscroll"]),
           explicitTimeWindow(in: prompt) == nil,
           BlankedAgentMemory.rememberedMainApps().isEmpty,
           !contains(text, ["tiktok", "instagram", "youtube", "app"]) {
            return AgentPlan(
                intent: .social,
                title: "Scroll Pattern",
                responseText: "I can help with that, but first I need to know where the loop happens.",
                bullets: [
                    "Read: this is a scroll habit, not a generic focus issue.",
                    "Pattern: the useful protection depends on the app and time window.",
                    "Move: tell me the main app or the time of day it usually starts."
                ],
                primaryLabel: "Got it",
                secondaryLabel: "Open report",
                actions: [],
                requiresSelectedApps: false,
                requiresScreenTimeAuthorization: false
            )
        }

        return nil
    }

    private static func hasExplicitBlockRequest(_ text: String) -> Bool {
        contains(text, ["block", "bloquea", "bloquear", "shield", "protect", "schedule", "limit", "from"])
    }

    private static func asksForPlan(_ text: String) -> Bool {
        contains(text.lowercased(), [
            " plan",
            "plan ",
            "make me a plan",
            "create a plan",
            "build a plan",
            "give me a plan",
            "focus plan",
            "protection plan",
            "quiero un plan",
            "hazme un plan"
        ])
    }

    private static func asksWhereToStart(_ text: String) -> Bool {
        contains(text.lowercased(), [
            "where to start",
            "where should i start",
            "how to start",
            "don't know where to start",
            "do not know where to start",
            "no se por donde empezar",
            "no sé por dónde empezar"
        ])
    }

    private static func asksForAdvice(_ text: String) -> Bool {
        contains(text.lowercased(), [
            "how can i",
            "what should i",
            "help me understand",
            "help me improve",
            "recommend",
            "advice",
            "advise",
            "tips",
            "why do i",
            "review",
            "diagnose",
            "analyze",
            "analyse",
            "como puedo",
            "qué debería",
            "que deberia",
            "aconseja",
            "consejo",
            "ayudame",
            "ayúdame"
        ])
    }

    private static func appCorrection(in prompt: String) -> Bool {
        let text = prompt.lowercased()
        let negatesUse = contains(text, [
            "i don't use",
            "i dont use",
            "i do not use",
            "i never use",
            "dont use",
            "don't use",
            "do not use",
            "no uso",
            "yo no uso"
        ])
        return negatesUse && contains(text, ["tiktok", "tik tok", "instagram", "ig", "youtube", "reddit", "twitter", "facebook", "snapchat"])
    }

    private static func correctionPlan() -> AgentPlan {
        AgentPlan(
            intent: .general,
            title: "Context Corrected",
            responseText: "Got it. I will not use that app as context. Which app, moment or habit should we focus on instead?",
            bullets: [
                "Read: the previous app context was wrong.",
                "Pattern: a useful plan needs your real trigger, not a guessed app.",
                "Move: tell me the app, moment or habit you actually want to improve."
            ],
            primaryLabel: "Tell pattern",
            secondaryLabel: "Not now",
            actions: [],
            requiresSelectedApps: false,
            requiresScreenTimeAuthorization: false
        )
    }

    private static func relativeMomentPlan(for prompt: String) -> AgentPlan? {
        let text = prompt.lowercased()
        let values: (label: String, question: String, move: String)?
        if contains(text, ["after lunch", "despues de comer", "después de comer"]) {
            values = ("after lunch", "Most people do best starting 10-15 minutes after lunch. What time do you usually finish eating?", "tell me when you usually finish lunch, then I can place the boundary without guessing.")
        } else if contains(text, ["after dinner", "despues de cenar", "después de cenar"]) {
            values = ("after dinner", "What time do you usually finish dinner?", "tell me when dinner usually ends, then I can set the boundary around the real risk moment.")
        } else if contains(text, ["when i wake up", "after waking", "wake up", "al despertar", "cuando me despierto"]) {
            values = ("after waking up", "What time do you usually wake up?", "tell me your usual wake-up time, then I can protect the first phone check.")
        } else if contains(text, ["after work", "despues de trabajar", "después de trabajar"]) {
            values = ("after work", "What time do you usually finish work?", "tell me when work usually ends, then I can protect the decompression window.")
        } else {
            values = nil
        }
        guard let values else { return nil }
        return AgentPlan(
            intent: .social,
            title: "Contextual Boundary",
            responseText: values.question,
            bullets: [
                "Read: you want protection \(values.label).",
                "Pattern: the useful boundary should match your real routine, not a generic clock time.",
                "Move: \(values.move)"
            ],
            primaryLabel: "Tell time",
            secondaryLabel: "Not now",
            actions: [],
            requiresSelectedApps: false,
            requiresScreenTimeAuthorization: false
        )
    }

    private static func behaviorPattern(_ prompt: String) -> String {
        let text = prompt.lowercased()
        if contains(text, ["anxious", "anxiety", "ansiedad", "stress"]) { return "an anxiety scroll loop" }
        if contains(text, ["bored", "aburr"]) { return "a boredom scroll loop" }
        if contains(text, ["sleep", "night", "bed", "dormir", "noche", "tired"]) { return "a bedtime scroll loop" }
        if contains(text, ["whatsapp", "check", "notification", "notif"]) { return "a compulsive checking loop" }
        if contains(text, ["avoid", "procrast", "work", "study", "exam"]) { return "an avoidance loop" }
        if contains(text, ["relapse", "reca", "broke", "failed"]) { return "a relapse pattern" }
        return "a screen habit loop"
    }

    private static func namedApp(in prompt: String) -> String? {
        let text = " \(prompt.lowercased()) "
        let apps = [
            ("TikTok", ["tiktok", "tik tok"]),
            ("Instagram", ["instagram", "insta", " ig "]),
            ("YouTube", ["youtube", "yt"]),
            ("Reddit", ["reddit"]),
            ("Twitter", ["twitter", " x "]),
            ("Facebook", ["facebook"]),
            ("Snapchat", ["snapchat"])
        ]
        return apps.first { _, aliases in
            aliases.contains { text.contains($0) }
        }?.0
    }

    private static func requestedAppCategory(in prompt: String) -> String? {
        let text = prompt.lowercased()
        if contains(text, ["social media", "social apps", "social networks", "redes sociales"]) {
            return "social apps"
        }
        return nil
    }

    private static func sleepPlan(context: AgentContext) -> AgentPlan {
        if let bedtime = BlankedAgentMemory.rememberedBedtimeMinute() {
            return bedtimeBoundaryPlan(bedtime: bedtime, context: context)
        }
        return AgentPlan(
            intent: .sleep,
            title: "Bedtime Scroll Loop",
            responseText: "This sounds like bedtime scrolling spilling into recovery, not a generic productivity issue.",
            bullets: [
                "Read: nights are the risky context.",
                "Pattern: the phone extends the day when your body needs shutdown.",
                "Move: tell me your usual bedtime before I suggest a block."
            ],
            primaryLabel: "Got it",
            secondaryLabel: "Open report",
            actions: [],
            requiresSelectedApps: false,
            requiresScreenTimeAuthorization: false
        )
    }

    private static func bedtimeBoundaryPlan(bedtime: Int, context: AgentContext) -> AgentPlan {
        let start = (bedtime + 24 * 60 - 30) % (24 * 60)
        return AgentPlan(
            intent: .sleep,
            title: "Bedtime Boundary",
            responseText: "That sleep target gives us the missing boundary.",
            bullets: [
                "Read: your target bedtime is \(agentMinuteText(bedtime)).",
                "Pattern: the phone needs to become less available before the final scroll starts.",
                "Move: protect distracting apps from \(agentMinuteText(start)) to \(agentMinuteText(bedtime)) first."
            ],
            primaryLabel: "Apply boundary",
            secondaryLabel: "Choose apps",
            actions: [
                .applySchedule(name: "Sleep Boundary", startMinute: start, endMinute: bedtime, weekdays: Array(1...7), durationDays: 7)
            ],
            requiresSelectedApps: true,
            requiresScreenTimeAuthorization: true
        )
    }

    private static func focusPlan(context: AgentContext) -> AgentPlan {
        let minutes = context.system.plan.recommendedDurationMinutes
        return AgentPlan(
            intent: .focus,
            title: "Focus Block",
            responseText: "This is an execution moment, so the useful move is immediate friction.",
            bullets: [
                "Move: start \(minutes) minutes now.",
                "Keep your current protected apps.",
                context.system.forecast.reason
            ],
            primaryLabel: "Start now",
            secondaryLabel: "Change apps",
            actions: [.startProtection(minutes: minutes, hardMode: false)],
            requiresSelectedApps: true,
            requiresScreenTimeAuthorization: true
        )
    }

    private static func studyPlan(context: AgentContext) -> AgentPlan {
        AgentPlan(
            intent: .study,
            title: "24h Study Protection",
            responseText: "I can set an intensive study plan for the next 24 hours.",
            bullets: [
                "Block distractions during the next key study window.",
                "Add a daily limit to reduce fallback scrolling.",
                "Use a stricter block when you start manually."
            ],
            primaryLabel: "Apply study plan",
            secondaryLabel: "Choose apps",
            actions: [
                .applySchedule(name: "Study Protection", startMinute: 9 * 60, endMinute: 12 * 60, weekdays: Array(1...7), durationDays: 1),
                .setDailyLimit(minutes: 30)
            ],
            requiresSelectedApps: true,
            requiresScreenTimeAuthorization: true
        )
    }

    private static func emergencyPlan(context: AgentContext) -> AgentPlan {
        AgentPlan(
            intent: .emergency,
            title: "Loss Of Control",
            responseText: context.isBlankActive ? "You are already protected; changing settings now would weaken the boundary." : "This is a high-risk moment. Reduce choice immediately.",
            bullets: [
                context.emergencyUnlocksRemaining > 0 ? "\(context.emergencyUnlocksRemaining) emergency unlocks left this week." : "No emergency unlocks left this week.",
                "Move: use a short hard block, then review what triggered it.",
                "Do not redesign the whole plan while the urge is active."
            ],
            primaryLabel: context.isBlankActive ? "Keep blocking" : "Start hard block",
            secondaryLabel: "Change apps",
            actions: context.isBlankActive ? [.none] : [.startProtection(minutes: 30, hardMode: true)],
            requiresSelectedApps: true,
            requiresScreenTimeAuthorization: true
        )
    }

    private static func allowOnlyPlan(context: AgentContext) -> AgentPlan {
        AgentPlan(
            intent: .allowOnly,
            title: "Allow Only Mode",
            responseText: "I can switch from blocking selected apps to allowing only selected essentials.",
            bullets: [
                "Only selected apps and web domains stay available.",
                "Everything else is shielded while Blanked is active.",
                "Choose WhatsApp, Maps or any essentials in the picker."
            ],
            primaryLabel: "Enable Allow Only",
            secondaryLabel: "Choose allowed apps",
            actions: [.enableAllowOnly, .openAppPicker],
            requiresSelectedApps: false,
            requiresScreenTimeAuthorization: true
        )
    }

    private static func vacationPlan(context: AgentContext) -> AgentPlan {
        let isActive = context.vacationModeActive
        return AgentPlan(
            intent: .vacation,
            title: isActive ? "Resume Rules" : "Vacation Mode",
            responseText: isActive ? "Your rules are paused. I can resume them now." : "I can pause scheduled protection while you are away.",
            bullets: isActive
                ? ["Resume schedules.", "Keep selected apps and modes unchanged."]
                : ["Pause schedules for 7 days.", "Keep manual protection available.", "Resume anytime from chat."],
            primaryLabel: isActive ? "Resume rules" : "Pause 7 days",
            secondaryLabel: "Advanced",
            actions: isActive ? [.disablePause] : [.pauseRules(hours: 168)],
            requiresSelectedApps: false,
            requiresScreenTimeAuthorization: false
        )
    }

    private static func weeklyReviewPlan(context: AgentContext) -> AgentPlan {
        let profile = context.system.profile
        return AgentPlan(
            intent: .weeklyReview,
            title: "Weekly Diagnosis",
            responseText: "Here is the current read. I can apply the adaptive plan from this.",
            bullets: [
                "\(profile.weeklyProtectedMinutes) protected minutes this week.",
                "\(profile.weeklyBreakCount) break signals detected.",
                "Next risk window: \(context.system.forecast.riskWindow)."
            ],
            primaryLabel: "Apply adaptive plan",
            secondaryLabel: "Open report",
            actions: [.applyAIPlan],
            requiresSelectedApps: true,
            requiresScreenTimeAuthorization: true
        )
    }

    private static func adultContentPlan(context: AgentContext) -> AgentPlan {
        AgentPlan(
            intent: .adultContent,
            title: "Adult Content Protection",
            responseText: "I can add adult content filtering to your phone protection.",
            bullets: [
                "Enable Apple's automatic adult web content filter.",
                "Keep your selected apps protected.",
                "Use a hard 30 minute block when urges spike."
            ],
            primaryLabel: "Enable protection",
            secondaryLabel: "Choose apps",
            actions: [.enableAdultFilter],
            requiresSelectedApps: false,
            requiresScreenTimeAuthorization: true
        )
    }

    private static func socialPlan(prompt: String, context: AgentContext) -> AgentPlan {
        let promptApp = namedApp(in: prompt)
        let appCategory = requestedAppCategory(in: prompt)
        let mainApp = promptApp ?? BlankedAgentMemory.rememberedMainApps().first ?? "the app"
        let outcome = BlankedAgentMemory.lastPlanOutcome(system: context.system)
        if appCategory != nil && hasExplicitBlockRequest(prompt.lowercased()) && (!context.hasSelectedApps || !context.screenTimeAuthorized) {
            return AgentPlan(
                intent: .social,
                title: "Choose Apps",
                responseText: "Choose the social apps in Screen Time first, then I can apply the block.",
                bullets: [
                    "Read: this is a category of apps, not one exact app.",
                    "Pattern: iOS needs you to choose the apps before Blanked can shield them.",
                    "Move: choose the social apps now, then apply the boundary."
                ],
                primaryLabel: context.hasSelectedApps ? "Allow Screen Time" : "Choose apps",
                secondaryLabel: "Not now",
                actions: [context.hasSelectedApps ? .requestScreenTimePermission : .openAppPicker],
                requiresSelectedApps: false,
                requiresScreenTimeAuthorization: false
            )
        }
        if promptApp != nil && hasExplicitBlockRequest(prompt.lowercased()) && (!context.hasSelectedApps || !context.screenTimeAuthorized) {
            return AgentPlan(
                intent: .social,
                title: "Choose App",
                responseText: "Choose \(mainApp) in Screen Time first, then I can apply the block.",
                bullets: [
                    "Read: \(mainApp) is the app you want to control.",
                    "Pattern: iOS needs that app inside your authorized selection before Blanked can shield it.",
                    "Move: choose the app now, then apply the boundary."
                ],
                primaryLabel: context.hasSelectedApps ? "Allow Screen Time" : "Choose app",
                secondaryLabel: "Not now",
                actions: [context.hasSelectedApps ? .requestScreenTimePermission : .openAppPicker],
                requiresSelectedApps: false,
                requiresScreenTimeAuthorization: false
            )
        }
        if promptApp == nil,
           appCategory == nil,
           explicitTimeWindow(in: prompt) == nil,
           outcome != "broke",
           outcome != "held",
           contains(prompt.lowercased(), ["scroll", "doomscroll", "scrolling", "checking my phone", "check my phone"]) {
            return AgentPlan(
                intent: .social,
                title: "Scroll Context",
                responseText: "I can help, but I need the real loop before creating a block. Which app or moment does the scrolling usually start with?",
                bullets: [
                    "Read: you want to stop scrolling, but the target is still broad.",
                    "Pattern: useful protection needs the app, trigger or time window.",
                    "Move: tell me the app or moment, then I can set the right boundary."
                ],
                primaryLabel: "Tell pattern",
                secondaryLabel: "Not now",
                actions: [],
                requiresSelectedApps: false,
                requiresScreenTimeAuthorization: false
            )
        }
        let weakWindow = BlankedAgentMemory.rememberedWeakHours(system: context.system).first.map(DigitalWellnessAI.hourRangeText) ?? "the usual scroll window"
        let feedbackLine: String
        if outcome == "broke" {
            feedbackLine = "Feedback: the last plan broke, so start easier and earlier."
        } else if outcome == "held" {
            feedbackLine = "Feedback: the last plan held, so repeat it before increasing difficulty."
        } else {
            feedbackLine = "Start with a 25 minute daily limit plus an evening shield."
        }
        return AgentPlan(
            intent: .social,
            title: "Scroll Loop",
            responseText: "This reads like \(behaviorPattern(context.system.profile.dominantModeName ?? "")): \(mainApp) is filling a state, not just spare time.",
            bullets: [
                "Pattern: the trigger matters more than total screen time.",
                "Move: block before \(weakWindow) and cap fallback use.",
                feedbackLine
            ],
            primaryLabel: "Apply plan",
            secondaryLabel: "Choose apps",
            actions: [
                .setDailyLimit(minutes: 25),
                .applySchedule(name: "Scroll Control", startMinute: 20 * 60 + 30, endMinute: 23 * 60, weekdays: Array(1...7), durationDays: 7)
            ],
            requiresSelectedApps: true,
            requiresScreenTimeAuthorization: true
        )
    }

    private static func generalPlan(prompt: String, context: AgentContext) -> AgentPlan {
        if (asksForAdvice(prompt) || asksForPlan(prompt) || asksWhereToStart(prompt)) && !hasExplicitBlockRequest(prompt.lowercased()) {
            if asksForPlan(prompt) {
                return AgentPlan(
                    intent: .general,
                    title: "Plan Context",
                    responseText: "I can build a plan, but first I need the real loop. Which app, moment or habit should we focus on?",
                    bullets: [
                        "Read: you want a plan, but the target is still too broad.",
                        "Pattern: useful protection starts from one repeated trigger.",
                        "Move: tell me the app, moment or habit that takes over most often."
                    ],
                    primaryLabel: "Tell pattern",
                    secondaryLabel: "Open report",
                    actions: [],
                    requiresSelectedApps: false,
                    requiresScreenTimeAuthorization: false
                )
            }
            return AgentPlan(
                intent: .general,
                title: "Digital Wellness Read",
                responseText: "Start by identifying the moment when the phone becomes automatic. Then make that moment slightly harder before adding strict blocks.",
                bullets: [
                    "Read: you are asking for guidance, not a blocking plan yet.",
                    "Pattern: the trigger usually matters more than total screen time.",
                    "Move: name the app and the moment it usually takes over."
                ],
                primaryLabel: "Tell pattern",
                secondaryLabel: "Open report",
                actions: [],
                requiresSelectedApps: false,
                requiresScreenTimeAuthorization: false
            )
        }
        return AgentPlan(
            intent: .general,
            title: "Noted",
            responseText: "I can help with screen-habit advice, a diagnosis or a protection plan if you want to go further.",
            bullets: [
                "Read: there is no clear action request yet.",
                "Pattern: Blanked should not turn every message into a blocking plan.",
                "Move: tell me whether you want advice or a plan."
            ],
            primaryLabel: "Tell goal",
            secondaryLabel: "Open report",
            actions: [],
            requiresSelectedApps: false,
            requiresScreenTimeAuthorization: false
        )
    }

    private static func contains(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private static func explicitTimeWindow(in prompt: String) -> AgentTimeWindow? {
        let text = prompt.lowercased()
        let pattern = #"(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(?:-|to|until|a)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: fullRange) else { return nil }

        func value(_ index: Int) -> String? {
            let range = match.range(at: index)
            guard range.location != NSNotFound else { return nil }
            return nsText.substring(with: range)
        }

        guard let startHour = Int(value(1) ?? ""),
              let endHour = Int(value(4) ?? "") else {
            return nil
        }

        let startMinutePart = Int(value(2) ?? "") ?? 0
        let endMinutePart = Int(value(5) ?? "") ?? 0
        guard (0...59).contains(startMinutePart), (0...59).contains(endMinutePart) else { return nil }

        let looksNightly = contains(text, ["night", "sleep", "bed", "dormir", "noche"]) ||
            (contains(text, ["block", "bloquea", "bloquear", "instagram", "tiktok", "youtube", "scroll"]) &&
             (7...11).contains(startHour) &&
             (1...9).contains(endHour))
        let explicitEndMeridiem = value(6)
        let explicitStartMeridiem = value(3)
        let endMeridiem = explicitEndMeridiem ?? (looksNightly && explicitStartMeridiem == nil ? "am" : nil)
        let startMeridiem = explicitStartMeridiem ?? (looksNightly ? "pm" : endMeridiem)
        let start = minuteOfDay(hour: startHour, minute: startMinutePart, meridiem: startMeridiem)
        let end = minuteOfDay(hour: endHour, minute: endMinutePart, meridiem: endMeridiem)
        guard let start, let end, start != end else { return nil }
        return AgentTimeWindow(startMinute: start, endMinute: end)
    }

    private static func explicitSingleTime(in prompt: String) -> Int? {
        let text = prompt.lowercased()
        if scrollUntilSleepTime(prompt) { return nil }
        if contains(text, ["sleep", "bed", "dormir", "duermo", "acuesto", "bedtime"]) && text.contains("midnight") {
            return 0
        }
        let pattern = #"(?:sleep|bed|dormir|duermo|acuesto|bedtime)[^\d]*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: fullRange) else { return nil }

        func value(_ index: Int) -> String? {
            let range = match.range(at: index)
            guard range.location != NSNotFound else { return nil }
            return nsText.substring(with: range)
        }

        guard let hour = Int(value(1) ?? "") else { return nil }
        let minute = Int(value(2) ?? "") ?? 0
        let meridiem = value(3) ?? ((6...11).contains(hour) ? "pm" : nil)
        return minuteOfDay(hour: hour, minute: minute, meridiem: meridiem)
    }

    private static func scrollUntilSleepTime(_ prompt: String) -> Bool {
        let text = prompt.lowercased()
        guard contains(text, ["scroll", "doomscroll", "reels", "shorts", "feed"]),
              contains(text, ["bed", "night", "noche"]) else {
            return false
        }
        return text.range(of: #"\buntil\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)?\b"#, options: .regularExpression) != nil
    }

    private static func minuteOfDay(hour: Int, minute: Int, meridiem: String?) -> Int? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        var resolvedHour = hour
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            if meridiem == "am" {
                resolvedHour = hour == 12 ? 0 : hour
            } else if meridiem == "pm" {
                resolvedHour = hour == 12 ? 12 : hour + 12
            }
        }
        return resolvedHour * 60 + minute
    }
}

private struct AgentTimeWindow {
    var startMinute: Int
    var endMinute: Int
}

private struct BlankedAgentClient {
    func plan(prompt: String, context: AgentContext) async throws -> AgentPlan {
        guard let baseURL = configuredBaseURL() else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("blanked-agent"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload(prompt: prompt, context: context))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(RemoteAgentResponse.self, from: data)
        var plan = decoded.plan.toAgentPlan(fallback: BlankedAgentPlanner.plan(for: prompt, context: context))
        plan.source = decoded.source
        plan.modelError = decoded.model_error
        return plan
    }

    private func payload(prompt: String, context: AgentContext) -> [String: Any] {
        var contextPayload: [String: Any] = [
            "is_blank_active": context.isBlankActive,
            "has_selected_apps": context.hasSelectedApps,
            "selection_count": context.selectionCount,
            "screen_time_authorized": context.screenTimeAuthorized,
            "emergency_unlocks_remaining": context.emergencyUnlocksRemaining,
            "vacation_mode_active": context.vacationModeActive,
            "adherence_score": context.system.profile.adherenceScore,
            "weekly_protected_minutes": context.system.profile.weeklyProtectedMinutes,
            "weekly_break_count": context.system.profile.weeklyBreakCount,
            "risk_window": context.system.forecast.riskWindow,
            "recommended_duration_minutes": context.system.plan.recommendedDurationMinutes,
            "weekly_goal": context.system.plan.weeklyGoal,
            "mode_name": context.modeName,
            "available_modes": context.availableModes,
            "weak_hours": BlankedAgentMemory.rememberedWeakHours(system: context.system),
            "pattern_cluster": BlankedAgentMemory.rememberedPatternCluster(),
            "last_plan_outcome": BlankedAgentMemory.lastPlanOutcome(system: context.system),
            "memory": context.memory
        ]
        if let strongestWindow = context.system.profile.strongestWindow {
            contextPayload["strongest_hour"] = strongestWindow
        }
        return [
            "prompt": String(prompt.prefix(500)),
            "locale": Locale.current.identifier,
            "context": contextPayload
        ]
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

private struct RemoteAgentResponse: Decodable {
    var plan: RemoteAgentPlan
    var source: String?
    var model_error: String?
}

private struct RemoteAgentPlan: Decodable {
    var intent: String
    var title: String
    var response_text: String
    var bullets: [String]
    var primary_label: String
    var secondary_label: String
    var actions: [RemoteAgentAction]
    var requires_selected_apps: Bool
    var requires_screen_time_authorization: Bool

    func toAgentPlan(fallback: AgentPlan) -> AgentPlan {
        let mappedActions = actions.compactMap(\.agentAction)
        let cleanedBullets = bullets.map { clean($0, "") }.filter { !$0.isEmpty }
        return AgentPlan(
            intent: AgentIntent(rawValue: intent) ?? fallback.intent,
            title: clean(title, fallback.title),
            responseText: clean(response_text, fallback.responseText),
            bullets: cleanedBullets.isEmpty ? fallback.bullets : Array(cleanedBullets.prefix(4)),
            primaryLabel: clean(primary_label, fallback.primaryLabel),
            secondaryLabel: clean(secondary_label, fallback.secondaryLabel),
            actions: mappedActions,
            requiresSelectedApps: requires_selected_apps,
            requiresScreenTimeAuthorization: requires_screen_time_authorization
        )
    }

    private func clean(_ value: String, _ fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : String(trimmed.prefix(180))
    }
}

private struct RemoteAgentAction: Decodable {
    var type: String
    var minutes: Int?
    var hard_mode: Bool?
    var name: String?
    var start_minute: Int?
    var end_minute: Int?
    var weekdays: [Int]?
    var duration_days: Int?
    var hours: Int?

    var agentAction: AgentAction? {
        switch type {
        case "none":
            return AgentAction.none
        case "start_protection":
            return .startProtection(minutes: clamp(minutes ?? 30, 5, 240), hardMode: hard_mode ?? false)
        case "apply_schedule":
            return .applySchedule(
                name: String((name ?? "AI Plan").prefix(40)),
                startMinute: clamp(start_minute ?? 22 * 60, 0, 1439),
                endMinute: clamp(end_minute ?? 7 * 60, 0, 1439),
                weekdays: normalizedWeekdays(weekdays),
                durationDays: clamp(duration_days ?? 7, 1, 14)
            )
        case "enable_allow_only":
            return .enableAllowOnly
        case "enable_adult_filter":
            return .enableAdultFilter
        case "set_daily_limit":
            return .setDailyLimit(minutes: clamp(minutes ?? 30, 5, 240))
        case "pause_rules":
            return .pauseRules(hours: clamp(hours ?? 168, 1, 168))
        case "disable_pause":
            return .disablePause
        case "switch_mode":
            return .switchMode(name: String((name ?? "Routine").prefix(40)))
        case "open_app_picker":
            return .openAppPicker
        case "request_screen_time_permission":
            return .requestScreenTimePermission
        case "apply_ai_plan":
            return .applyAIPlan
        default:
            return nil
        }
    }

    private func clamp(_ value: Int, _ lower: Int, _ upper: Int) -> Int {
        min(max(value, lower), upper)
    }

    private func normalizedWeekdays(_ values: [Int]?) -> [Int] {
        let valid = Array(Set((values ?? Array(1...7)).filter { (1...7).contains($0) })).sorted()
        return valid.isEmpty ? Array(1...7) : valid
    }
}

private enum BlankedAgentMemory {
    private static let defaults = BlankSharedState.defaults
    private static let lastPromptKey = "blankedAgentLastPrompt"
    private static let lastIntentKey = "blankedAgentLastIntent"
    private static let lastPlanTitleKey = "blankedAgentLastPlanTitle"
    private static let lastPlanAppliedAtKey = "blankedAgentLastPlanAppliedAt"
    private static let lastPlanProtectedMinutesKey = "blankedAgentLastPlanProtectedMinutes"
    private static let lastPlanBreakCountKey = "blankedAgentLastPlanBreakCount"
    private static let mainAppsKey = "blankedAgentMainApps"
    private static let bedtimeMinuteKey = "blankedAgentBedtimeMinute"
    private static let patternClusterKey = "blankedAgentPatternCluster"

    static func recordUserPrompt(_ prompt: String, inferredIntent: AgentIntent) {
        defaults.removeObject(forKey: lastPromptKey)
        defaults.set(inferredIntent.rawValue, forKey: lastIntentKey)
        if let bedtime = explicitBedtimeMinute(in: prompt) {
            defaults.set(bedtime, forKey: bedtimeMinuteKey)
        }
        let rejectedApps = negatedMainApps(from: prompt)
        removeMainApps(rejectedApps)
        mergeMainApps(extractMainApps(from: prompt).filter { !rejectedApps.contains($0) })
        defaults.set(patternCluster(for: prompt, intent: inferredIntent), forKey: patternClusterKey)
    }

    static func recordAppliedPlan(_ plan: AgentPlan, context: AgentContext) {
        defaults.set(plan.title, forKey: lastPlanTitleKey)
        defaults.set(Date().timeIntervalSince1970, forKey: lastPlanAppliedAtKey)
        defaults.set(plan.intent.rawValue, forKey: lastIntentKey)
        defaults.set(context.system.profile.weeklyProtectedMinutes, forKey: lastPlanProtectedMinutesKey)
        defaults.set(context.system.profile.weeklyBreakCount, forKey: lastPlanBreakCountKey)
    }

    static func snapshot(system: DigitalWellnessV3System) -> [String: Any] {
        var payload: [String: Any] = [
            "last_prompt": "",
            "last_intent": defaults.string(forKey: lastIntentKey) ?? "",
            "last_plan_title": defaults.string(forKey: lastPlanTitleKey) ?? "",
            "last_plan_applied_at": defaults.double(forKey: lastPlanAppliedAtKey),
            "last_plan_outcome": lastPlanOutcome(system: system),
            "main_apps": rememberedMainApps(),
            "weak_hours": rememberedWeakHours(system: system),
            "pattern_cluster": rememberedPatternCluster(),
            "protected_minutes_since_plan": max(0, system.profile.weeklyProtectedMinutes - defaults.integer(forKey: lastPlanProtectedMinutesKey)),
            "breaks_since_plan": max(0, system.profile.weeklyBreakCount - defaults.integer(forKey: lastPlanBreakCountKey))
        ]
        if let bedtime = rememberedBedtimeMinute() {
            payload["bedtime_minute"] = bedtime
        }
        return payload
    }

    static func rememberedMainApps() -> [String] {
        (defaults.string(forKey: mainAppsKey) ?? "")
            .split(separator: "|")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    static func rememberedBedtimeMinute() -> Int? {
        guard defaults.object(forKey: bedtimeMinuteKey) != nil else { return nil }
        let value = defaults.integer(forKey: bedtimeMinuteKey)
        return (0...(24 * 60 - 1)).contains(value) ? value : nil
    }

    static func rememberedPatternCluster() -> String {
        defaults.string(forKey: patternClusterKey) ?? ""
    }

    static func rememberedWeakHours(system: DigitalWellnessV3System) -> [Int] {
        let candidates = ([system.profile.weakestWindow] + system.weakWindows.map(\.hour))
            .compactMap { $0 }
            .filter { (0...23).contains($0) }
        var seen = Set<Int>()
        var hours: [Int] = []
        for candidate in candidates where !seen.contains(candidate) {
            seen.insert(candidate)
            hours.append(candidate)
            if hours.count == 3 { break }
        }
        return hours
    }

    static func lastPlanOutcome(system: DigitalWellnessV3System) -> String {
        guard defaults.object(forKey: lastPlanAppliedAtKey) != nil else { return "none" }
        let breaksSincePlan = system.profile.weeklyBreakCount - defaults.integer(forKey: lastPlanBreakCountKey)
        let protectedSincePlan = system.profile.weeklyProtectedMinutes - defaults.integer(forKey: lastPlanProtectedMinutesKey)
        if breaksSincePlan > 0 { return "broke" }
        if protectedSincePlan >= 15 { return "held" }
        return "pending"
    }

    private static func mergeMainApps(_ apps: [String]) {
        guard !apps.isEmpty else { return }
        var seen = Set<String>()
        var merged: [String] = []
        for app in rememberedMainApps() + apps where !seen.contains(app) {
            seen.insert(app)
            merged.append(app)
            if merged.count == 5 { break }
        }
        defaults.set(merged.joined(separator: "|"), forKey: mainAppsKey)
    }

    private static func removeMainApps(_ apps: [String]) {
        guard !apps.isEmpty else { return }
        let rejected = Set(apps)
        let kept = rememberedMainApps().filter { !rejected.contains($0) }
        defaults.set(kept.joined(separator: "|"), forKey: mainAppsKey)
    }

    private static func extractMainApps(from prompt: String) -> [String] {
        let knownApps = [
            "TikTok": ["tiktok", "tik tok"],
            "Instagram": ["instagram", "insta", " ig "],
            "YouTube": ["youtube", "yt"],
            "WhatsApp": ["whatsapp"],
            "X": ["twitter", " x "],
            "Reddit": ["reddit"],
            "Safari": ["safari"],
            "Chrome": ["chrome"],
            "Netflix": ["netflix"],
            "Snapchat": ["snapchat"],
            "Discord": ["discord"]
        ]
        let text = " \(prompt.lowercased()) "
        return knownApps.compactMap { name, aliases in
            aliases.contains { text.contains($0) } ? name : nil
        }
    }

    private static func negatedMainApps(from prompt: String) -> [String] {
        let text = prompt.lowercased()
        let negatesUse = text.contains("i don't use") ||
            text.contains("i dont use") ||
            text.contains("i do not use") ||
            text.contains("i never use") ||
            text.contains("dont use") ||
            text.contains("don't use") ||
            text.contains("do not use") ||
            text.contains("no uso") ||
            text.contains("yo no uso")
        return negatesUse ? extractMainApps(from: prompt) : []
    }

    private static func patternCluster(for prompt: String, intent: AgentIntent) -> String {
        let text = prompt.lowercased()
        if text.contains("night") || text.contains("sleep") || text.contains("bed") || text.contains("noche") { return "bedtime_scroll" }
        if text.contains("anxious") || text.contains("stress") || text.contains("ansiedad") { return "anxiety_scroll" }
        if text.contains("bored") || text.contains("aburr") { return "boredom_scroll" }
        if text.contains("whatsapp") || text.contains("notification") || text.contains("check") { return "compulsive_checking" }
        if text.contains("study") || text.contains("work") || text.contains("procrast") { return "avoidance_loop" }
        return intent.rawValue
    }

    private static func explicitBedtimeMinute(in prompt: String) -> Int? {
        let text = prompt.lowercased()
        let pattern = #"(?:sleep|bed|dormir|duermo|acuesto|bedtime)[^\d]*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        func value(_ index: Int) -> String? {
            let range = match.range(at: index)
            guard range.location != NSNotFound else { return nil }
            return nsText.substring(with: range)
        }
        guard let hour = Int(value(1) ?? "") else { return nil }
        let minute = Int(value(2) ?? "") ?? 0
        let meridiem = value(3) ?? ((6...11).contains(hour) ? "pm" : nil)
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        var resolvedHour = hour
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            if meridiem == "am" {
                resolvedHour = hour == 12 ? 0 : hour
            } else if meridiem == "pm" {
                resolvedHour = hour == 12 ? 12 : hour + 12
            }
        }
        return resolvedHour * 60 + minute
    }
}

private struct WidgetTimerSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var customMinutes: Int
    let selectedMinutes: Int?
    let onSelect: (Int?) -> Void

    private let options = [5, 15, 30, 60]

    init(selectedMinutes: Int?, onSelect: @escaping (Int?) -> Void) {
        self.selectedMinutes = selectedMinutes
        self.onSelect = onSelect
        _customMinutes = State(initialValue: selectedMinutes ?? 45)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Start timer")
                .font(.blankInter(size: 34, weight: .semibold, relativeTo: .largeTitle))

            Text("Choose a countdown. It will be used when you press Start Blank on the widget.")
                .font(.blankInter(size: 15, relativeTo: .body))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(options, id: \.self) { minutes in
                    Button(formatDuration(minutes)) {
                        onSelect(minutes)
                        dismiss()
                    }
                    .buttonStyle(BlankSecondaryButtonStyle())
                }
            }

            Stepper(value: $customMinutes, in: 5...240, step: 5) {
                Text(formatDuration(customMinutes))
                    .font(.blankInter(size: 17, weight: .semibold, relativeTo: .body))
            }
            .padding(.horizontal, 18)
            .frame(height: 56)
            .blankGlassCard(cornerRadius: 18, tintOpacity: 0.28)

            Button("Use custom timer") {
                onSelect(customMinutes)
                dismiss()
            }
            .buttonStyle(BlankPrimaryButtonStyle())

            if selectedMinutes != nil {
                Button("Clear timer") {
                    onSelect(nil)
                    dismiss()
                }
                .font(.blankInter(size: 14, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .buttonStyle(.plain)
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

private struct AgentBubble: View {
    let message: AgentMessage
    let maxWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            if message.role == .user { Spacer(minLength: 0) }
            Text(message.text)
                .font(.blankInter(size: 16, relativeTo: .body))
                .foregroundStyle(message.role == .user ? Color.white : BlankColors.ink)
                .frame(maxWidth: min(maxWidth * 0.84, 304), alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .background {
                    bubbleBackground
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(bubbleStroke, lineWidth: 1)
                }
                .shadow(color: bubbleShadow, radius: message.role == .user ? 8 : 18, x: 0, y: message.role == .user ? 4 : 10)

            if message.role == .blanked { Spacer(minLength: 0) }
        }
        .frame(width: maxWidth, alignment: message.role == .user ? .trailing : .leading)
    }

    private var bubbleBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(message.role == .user ? AnyShapeStyle(BlankColors.ink.opacity(0.94)) : AnyShapeStyle(.ultraThinMaterial))
            .overlay {
                if message.role == .blanked {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.78),
                                    Color.white.opacity(0.48),
                                    Color(red: 206 / 255.0, green: 224 / 255.0, blue: 246 / 255.0).opacity(0.24)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
    }

    private var bubbleStroke: LinearGradient {
        LinearGradient(
            colors: message.role == .user
                ? [Color.white.opacity(0.10), Color.white.opacity(0.02)]
                : [Color.white.opacity(0.74), Color.white.opacity(0.22), Color.white.opacity(0.04)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var bubbleShadow: Color {
        message.role == .user ? BlankColors.ink.opacity(0.08) : BlankColors.ink.opacity(0.07)
    }
}

private struct AgentPlanCard: View {
    let plan: AgentPlan
    let canApply: Bool
    let maxWidth: CGFloat
    let onPrimary: () -> Void
    let onSecondary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(BlankColors.ink.opacity(0.08)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.title)
                        .font(.blankInter(size: 20, weight: .semibold, relativeTo: .title3))
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                    Text(statusText)
                        .font(.blankInter(size: 12, weight: .semibold, relativeTo: .caption))
                        .foregroundStyle(BlankColors.mutedInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(plan.bullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 9) {
                        Circle()
                            .fill(BlankColors.ink.opacity(0.70))
                            .frame(width: 5, height: 5)
                            .padding(.top, 8)
                        Text(bullet)
                            .font(.blankInter(size: 15, relativeTo: .subheadline))
                            .foregroundStyle(BlankColors.ink.opacity(0.84))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if plan.hasExecutableActions {
                HStack(spacing: 8) {
                    Button(action: onPrimary) {
                        Text(plan.primaryLabel)
                            .font(.blankInter(size: 16, weight: .medium, relativeTo: .headline))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .foregroundStyle(Color.white)
                            .background {
                                Capsule().fill(BlankColors.glassTint.opacity(0.48))
                            }
                    }
                    .buttonStyle(.plain)
                    .opacity(canApply ? 1 : 0.62)

                    Button(plan.secondaryLabel, action: onSecondary)
                        .font(.blankInter(size: 14, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(BlankColors.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .frame(width: 96, height: 50)
                        .background {
                            Capsule().fill(Color.white.opacity(0.46))
                        }
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .frame(width: maxWidth, alignment: .leading)
        .blankGlassCard(cornerRadius: 24, tintOpacity: 0.50)
        .frame(width: maxWidth)
        .clipped()
    }

    private var iconName: String {
        switch plan.intent {
        case .sleep:
            return "moon.fill"
        case .focus, .study:
            return "timer"
        case .emergency:
            return "bolt.fill"
        case .allowOnly:
            return "checkmark.shield.fill"
        case .vacation:
            return "pause.fill"
        case .weeklyReview:
            return "chart.xyaxis.line"
        case .adultContent:
            return "lock.shield.fill"
        case .social:
            return "iphone.slash"
        case .general:
            return "sparkles"
        }
    }

    private var statusText: String {
        if !plan.hasExecutableActions {
            return "Understanding first"
        }
        return canApply ? "Ready to execute" : "Needs setup first"
    }
}

private struct AgentStatusPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.blankInter(size: 10, weight: .semibold, relativeTo: .caption2))
                .foregroundStyle(BlankColors.mutedInk)
            Text(value)
                .font(.blankInter(size: 14, weight: .semibold, relativeTo: .caption))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .frame(height: 54)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.38))
        }
    }
}

private struct AgentQuickAction: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.blankInter(size: 13, weight: .semibold, relativeTo: .caption))
            }
            .foregroundStyle(BlankColors.ink)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background {
                Capsule().fill(Color.white.opacity(0.46))
            }
        }
        .buttonStyle(.plain)
    }
}

private func agentMinuteText(_ minuteOfDay: Int) -> String {
    let hour = max(0, min(23, minuteOfDay / 60))
    let minute = max(0, min(59, minuteOfDay % 60))
    let displayHour = hour % 12 == 0 ? 12 : hour % 12
    let meridiem = hour < 12 ? "AM" : "PM"
    return "\(displayHour):\(String(format: "%02d", minute)) \(meridiem)"
}

private func agentClockText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter.string(from: date)
}
