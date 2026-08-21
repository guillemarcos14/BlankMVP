import FamilyControls
import SwiftUI

private enum HomeSheet: Identifiable {
    case modes
    case schedule
    case report
    case emergency

    var id: String {
        switch self {
        case .modes: return "modes"
        case .schedule: return "schedule"
        case .report: return "report"
        case .emergency: return "emergency"
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var screenTimeBlocker: ScreenTimeBlocker
    @Environment(\.scenePhase) private var scenePhase

    @State private var now = Date()
    @State private var message: String?
    @State private var messageAction: ConfigIssue.Action?
    @State private var showingPicker = false
    @State private var activeSheet: HomeSheet?
    @State private var nfcReader = NFCReader()
    @State private var unblankHoldProgress = 0.0
    @State private var isAnimatingUnblankHold = false
    @State private var unblankHoldStartedAt: Date?
    @AppStorage("blankWeeklyAIGoal", store: BlankSharedState.defaults) private var storedWeeklyGoal = ""

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let homeTagline = "Shaping what we\ncreate with the\npower of time."
    private let unblankHoldDuration: TimeInterval = 23

    var body: some View {
        GeometryReader { proxy in
            let layout = HomeLayoutMetrics(size: proxy.size, safeAreaInsets: proxy.safeAreaInsets)

            ZStack {
                AppBackground(isActive: sessionStore.isBlankActive)

                topBar
                    .position(x: layout.centerX, y: layout.topBarCenterY)
                    .zIndex(2)

                configCard
                    .frame(width: layout.configCardWidth)
                    .padding(.top, layout.configTopPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                centerContent(maxWidth: layout.messageMaxWidth, actionWidth: layout.actionWidth)
                    .position(x: layout.centerX, y: layout.messageCenterY)
            }
        }
        .ignoresSafeArea()
        .foregroundStyle(sessionStore.isBlankActive ? Color.white : BlankColors.ink)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(sessionStore.isBlankActive ? .dark : .light)
        .animation(.easeInOut(duration: 0.65), value: sessionStore.isBlankActive)
        .navigationBarBackButtonHidden()
        .onReceive(timer) { date in
            now = date
            sessionStore.syncFromSharedDefaults(now: date)
            sessionStore.applyScheduleWindow(at: date)
            screenTimeBlocker.apply(isBlankActive: sessionStore.isBlankActive)
        }
        .onAppear {
            sessionStore.syncFromSharedDefaults(now: now)
            screenTimeBlocker.apply(isBlankActive: sessionStore.isBlankActive)
            screenTimeBlocker.refreshAuthorizationStatus()
            openWidgetScanIfNeeded()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            sessionStore.syncFromSharedDefaults()
            screenTimeBlocker.apply(isBlankActive: sessionStore.isBlankActive)
            screenTimeBlocker.refreshAuthorizationStatus()
            openWidgetScanIfNeeded()
        }
        .familyActivityPicker(isPresented: $showingPicker, selection: $sessionStore.selection)
        .onChange(of: sessionStore.selection) { newSelection in
            screenTimeBlocker.updateSelection(newSelection, isBlankActive: sessionStore.isBlankActive)
        }
        .onChange(of: sessionStore.shouldOpenBlockConfiguration) { shouldOpen in
            guard shouldOpen else { return }
            activeSheet = .modes
            sessionStore.shouldOpenBlockConfiguration = false
        }
        .onChange(of: sessionStore.shouldScanBlankFromWidget) { shouldScan in
            guard shouldScan else { return }
            openWidgetScanIfNeeded()
        }
        .sheet(item: $activeSheet) { sheet in
            homeSheetContent(sheet)
                .blankTransparentPresentation()
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
                activeSheet = .emergency
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
                    activeSheet = .report
                }
                topNavButton("Mode") {
                    activeSheet = .modes
                }
                topNavButton("Habits") {
                    activeSheet = .schedule
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

    @ViewBuilder
    private var configCard: some View {
        let issues = configIssues
        if !issues.isEmpty {
            VStack(spacing: 8) {
                ForEach(issues) { issue in
                    Button {
                        resolve(issue.action)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(BlankColors.ink.opacity(0.76))
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Color.white.opacity(0.54)))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(issue.title)
                                    .font(.blankInter(size: 15, weight: .semibold, relativeTo: .subheadline))
                                    .foregroundStyle(BlankColors.ink)
                                    .lineLimit(1)

                                Text(issue.body)
                                    .font(.blankInter(size: 13, relativeTo: .footnote))
                                    .foregroundStyle(BlankColors.mutedInk)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .layoutPriority(1)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            ZStack {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color.white.opacity(0.68))
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.white.opacity(0.42), lineWidth: 1)
                            }
                        }
                        .shadow(color: Color.black.opacity(0.05), radius: 12, y: 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func centerContent(maxWidth: CGFloat, actionWidth: CGFloat) -> some View {
        VStack(spacing: 22) {
            Group {
                if sessionStore.isBlankActive, let unblankHoldStartedAt {
                    UnblankBreathingPrompt(startedAt: unblankHoldStartedAt, totalDuration: unblankHoldDuration)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    Text(homeTagline)
                        .font(.blankInter(size: 32.4, weight: .medium, relativeTo: .largeTitle))
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(-2)
                        .lineLimit(3)
                        .minimumScaleFactor(0.78)
                        .transition(.opacity.combined(with: .scale(scale: 1.02)))
                }
            }
            .frame(height: 122)
            .animation(.easeInOut(duration: 0.42), value: unblankHoldStartedAt != nil)

            bottomAction(width: actionWidth)

            centerStatus
        }
        .frame(maxWidth: maxWidth)
    }

    @ViewBuilder
    private var centerStatus: some View {
        VStack(spacing: 8) {
            if sessionStore.isBlankActive, let blankActiveSince = sessionStore.blankActiveSince {
                Text(elapsedText(since: blankActiveSince))
                    .font(.blankInter(size: 16, weight: .semibold, relativeTo: .headline))
                    .foregroundStyle(Color.white.opacity(0.86))
                    .monospacedDigit()
                if let blankActiveUntil = sessionStore.blankActiveUntil {
                    Text("Ends in \(remainingText(until: blankActiveUntil))")
                        .font(.blankBody)
                        .foregroundStyle(Color.white.opacity(0.76))
                    Text(sessionStore.deviceActivityTimerScheduled ? "System timer active" : "Internal timer active")
                        .font(.blankInter(size: 13, relativeTo: .footnote))
                        .foregroundStyle(Color.white.opacity(0.58))
                }
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
            if let preventiveAlertText {
                Text(preventiveAlertText)
                    .font(.blankInter(size: 13, relativeTo: .footnote))
                    .foregroundStyle(Color.white.opacity(0.74))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
                    .frame(maxWidth: 244)
            }

            let buttonWidth = sessionStore.isBlankActive ? min(width, 244) : min(width, 184)
            Button(sessionStore.isBlankActive ? "Hold to Unblank" : "Start Blank") {
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
            .buttonStyle(HomeBlankearButtonStyle())
            .frame(width: buttonWidth)
            .overlay(alignment: .leading) {
                if sessionStore.isBlankActive {
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
                LongPressGesture(minimumDuration: unblankHoldDuration, maximumDistance: 80)
                    .onEnded { _ in
                        guard sessionStore.isBlankActive else { return }
                        let result = withAnimation(.easeInOut(duration: 0.65)) {
                            sessionStore.deactivateBlank(entryMode: .app, endedReason: .manual)
                        }
                        screenTimeBlocker.clear()
                        unblankHoldProgress = 0
                        isAnimatingUnblankHold = false
                        unblankHoldStartedAt = nil
                        setMessage(for: result)
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard sessionStore.isBlankActive, !isAnimatingUnblankHold else { return }
                        isAnimatingUnblankHold = true
                        unblankHoldStartedAt = Date()
                        unblankHoldProgress = 0
                        withAnimation(.linear(duration: unblankHoldDuration)) {
                            unblankHoldProgress = 1
                        }
                    }
                    .onEnded { _ in
                        isAnimatingUnblankHold = false
                        unblankHoldStartedAt = nil
                        withAnimation(.easeOut(duration: 0.18)) {
                            unblankHoldProgress = 0
                        }
                    }
            )
        }
    }

    private var preventiveAlertText: String? {
        guard !sessionStore.isBlankActive,
              message == nil,
              configIssues.isEmpty,
              let weakHour = weakHourThisWeek(),
              minutesUntilNextHour(weakHour) <= 30 else {
            return nil
        }

        return "Your weak window is coming. Start Blank."
    }

    private var emergencyCoachMessage: String {
        if !storedWeeklyGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "You are breaking your weekly goal."
        }

        guard let weakHour = weakHourThisWeek() else {
            return "Pause for 10 seconds before deciding."
        }

        let currentHour = Calendar.current.component(.hour, from: now)
        if weakHour == currentHour {
            return "You are in your weak window. Try 5 more minutes."
        }

        if minutesUntilNextHour(weakHour) <= 30 {
            return "Your weak window is close. Avoid breaking now."
        }

        return "Breaking now counts as a weekly emergency."
    }

    private func weakHourThisWeek() -> Int? {
        let calendar = Calendar.current
        let weekStart = BlankWeeklySessionAggregator.startOfWeek(for: now, calendar: calendar)
        let brokenEventHours = sessionStore.usageEvents
            .filter { event in
                event.occurredAt >= weekStart &&
                event.occurredAt <= now &&
                (event.kind == .blockBroken || event.endedReason == .emergency)
            }
            .map(\.localHour)
        let emergencySessionHours = sessionStore.sessions
            .filter { session in
                let sessionEnd = session.endedAt ?? now
                return session.startedAt <= now &&
                sessionEnd >= weekStart &&
                session.endedReason == .emergency
            }
            .compactMap(\.localStartHour)

        return mostCommonValue(brokenEventHours + emergencySessionHours)
    }

    private func minutesUntilNextHour(_ hour: Int) -> Int {
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        var minutes = (hour - currentHour) * 60 - currentMinute
        if minutes < 0 {
            minutes += 24 * 60
        }
        return minutes
    }

    private func mostCommonValue<T: Hashable>(_ values: [T]) -> T? {
        let counts = values.reduce(into: [T: Int]()) { counts, value in
            counts[value, default: 0] += 1
        }
        return counts.max { lhs, rhs in lhs.value < rhs.value }?.key
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
                message = approved ? "Screen Time authorized." : "Screen Time is still pending."
                messageAction = approved ? nil : .screenTime
            }
        case .selectApps:
            showingPicker = true
        }
    }

    @ViewBuilder
    private func homeSheetContent(_ sheet: HomeSheet) -> some View {
        switch sheet {
        case .modes:
            ModesList(showingPicker: $showingPicker) {
                activeSheet = nil
            }
            .presentationDetents([.medium, .large])
        case .schedule:
            ScheduleEditorContent()
                .presentationDetents([.medium, .large])
        case .report:
            ReportView()
                .presentationDetents([.medium, .large])
        case .emergency:
            EmergencySheet(
                emergencyUnlocksRemaining: sessionStore.emergencyUnlocksRemaining,
                coachMessage: emergencyCoachMessage
            ) {
                let unlocked = withAnimation(.easeInOut(duration: 0.65)) {
                    sessionStore.deactivateForEmergency()
                }
                if unlocked {
                    screenTimeBlocker.clear()
                    message = nil
                    messageAction = nil
                }
                return unlocked
            }
            .presentationDetents([.medium])
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
    let configCardWidth: CGFloat
    let messageMaxWidth: CGFloat
    let actionWidth: CGFloat
    let centerX: CGFloat
    let topBarCenterY: CGFloat
    let messageCenterY: CGFloat

    init(size: CGSize, safeAreaInsets: EdgeInsets) {
        let width = max(size.width, 320)
        let height = max(size.height, 600)
        let topSafeArea = safeAreaInsets.top > 0 ? safeAreaInsets.top : 44
        horizontalPadding = min(max(width * 0.075, 28), 36)
        topPadding = topSafeArea + 26
        configTopPadding = topPadding + 47 + 14
        bottomPadding = max(safeAreaInsets.bottom + 18, 34)
        configCardWidth = min(max(width - horizontalPadding * 2, 260), 320)
        messageMaxWidth = min(max(width - horizontalPadding * 2, 280), 350)
        actionWidth = min(max(width - horizontalPadding * 2, 260), 342)
        centerX = width / 2
        topBarCenterY = topPadding + 47 / 2
        messageCenterY = height * 0.52
    }
}

private struct HomeBlankearButtonStyle: ButtonStyle {
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

private struct UnblankBreathingPrompt: View {
    let startedAt: Date
    let totalDuration: TimeInterval

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = min(max(0, context.date.timeIntervalSince(startedAt)), totalDuration)
            let step = breathingStep(for: elapsed)

            VStack(spacing: 18) {
                Text(step.title)
                    .id(step.title)
                    .font(.blankInter(size: 34, weight: .medium, relativeTo: .largeTitle))
                    .foregroundStyle(Color.white)
                    .opacity(step.titleOpacity)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .transition(.opacity)
                    .frame(height: 42)

                BreathProgressLine(progress: step.visualProgress)
            }
            .animation(.easeInOut(duration: 0.95), value: step.title)
            .animation(.easeInOut(duration: 0.82), value: step.titleOpacity)
        }
        .frame(width: 260, height: 122)
    }

    private func breathingStep(for elapsed: TimeInterval) -> BreathingStep {
        if elapsed >= totalDuration {
            return BreathingStep(title: "Breathe out", visualProgress: 0.20, titleOpacity: 0)
        }

        if elapsed < 5 {
            let progress = 0.20 + smoothBreathProgress(elapsed / 5) * 0.80
            return BreathingStep(title: "Breathe in", visualProgress: progress)
        }

        if elapsed < 6 {
            return BreathingStep(title: "Breathe in", visualProgress: 1.0, titleOpacity: fadeOutOpacity(elapsed - 5))
        }

        if elapsed < 11 {
            let phaseElapsed = elapsed - 6
            let progress = 1.0 - smoothBreathProgress(phaseElapsed / 5) * 0.80
            return BreathingStep(title: "Breathe out", visualProgress: progress)
        }

        if elapsed < 12 {
            return BreathingStep(title: "Breathe out", visualProgress: 0.20, titleOpacity: fadeOutOpacity(elapsed - 11))
        }

        if elapsed < 17 {
            let phaseElapsed = elapsed - 12
            let progress = 0.20 + smoothBreathProgress(phaseElapsed / 5) * 0.80
            return BreathingStep(title: "Breathe in", visualProgress: progress)
        }

        if elapsed < 18 {
            return BreathingStep(title: "Breathe in", visualProgress: 1.0, titleOpacity: fadeOutOpacity(elapsed - 17))
        }

        let phaseElapsed = elapsed - 18
        let progress = 1.0 - smoothBreathProgress(phaseElapsed / 5) * 0.80
        return BreathingStep(title: "Breathe out", visualProgress: progress)
    }

    private func smoothBreathProgress(_ rawProgress: TimeInterval) -> TimeInterval {
        let x = min(max(rawProgress, 0), 1)
        return 0.5 - cos(Double.pi * x) / 2
    }

    private func fadeOutOpacity(_ elapsed: TimeInterval) -> Double {
        1 - smoothBreathProgress(elapsed)
    }
}

private struct BreathingStep: Equatable {
    let title: String
    let visualProgress: Double
    var titleOpacity: Double = 1
}

private struct BreathProgressLine: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(progress, 0.16), 1)
            let width = proxy.size.width * CGFloat(clamped)

            ZStack(alignment: .center) {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                    .frame(height: 1)

                Capsule()
                    .fill(Color.white.opacity(0.54))
                    .frame(width: width, height: 1.5)
                    .shadow(color: Color.white.opacity(0.14), radius: 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(width: 188, height: 12)
        .animation(.easeInOut(duration: 1.45), value: progress)
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
        case selectApps
    }

    let title: String
    let body: String
    let action: Action

    var id: String { title }
}

private struct AppBackground: View {
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
            .padding(.bottom, 34)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .tint(textColor)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(BlankAtmosphericBackground(dimmed: sessionStore.isBlankActive).ignoresSafeArea())
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
        return "\(count) app \(count == 1 ? "blocked" : "blocked")"
    }
}

private extension View {
    @ViewBuilder
    func blankTransparentPresentation() -> some View {
        if #available(iOS 16.4, *) {
            self.presentationBackground(.clear)
        } else {
            self
        }
    }

}

private struct ScheduleEditorContent: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var enabled = false
    @State private var startMinute = 23 * 60 + 30
    @State private var endMinute = 8 * 60
    private var textColor: Color { sessionStore.isBlankActive ? Color.white : BlankColors.ink }
    private var secondaryColor: Color { sessionStore.isBlankActive ? Color.white.opacity(0.70) : BlankColors.mutedInk }

    var body: some View {
        List {
            VStack(alignment: .center, spacing: 16) {
                TopSheetHeader(
                    title: "Habits",
                    subtitle: "Schedule when Blank starts automatically\nand save your daily routine.",
                    titleColor: textColor,
                    subtitleColor: secondaryColor
                )

                    Toggle("Daily schedule", isOn: $enabled)
                        .font(.blankInter(size: 16, weight: .medium, relativeTo: .body))
                        .foregroundStyle(textColor)
                        .padding(.horizontal, 18)
                        .frame(height: 56)
                        .blankGlassCard(cornerRadius: 18, tintOpacity: 0.28)

                    VStack(spacing: 10) {
                        TimeMenuRow(title: "Start", minute: $startMinute, textColor: textColor)
                        TimeMenuRow(title: "End", minute: $endMinute, textColor: textColor)
                        StaticScheduleRow(title: "Days", value: "Every day", textColor: textColor)
                    }

                    Text("To exit earlier, use Blank or Emergency.")
                        .font(.footnote)
                        .foregroundStyle(secondaryColor)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
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
        .background(BlankAtmosphericBackground(dimmed: sessionStore.isBlankActive).ignoresSafeArea())
        .preferredColorScheme(sessionStore.isBlankActive ? .dark : .light)
        .onAppear {
            enabled = sessionStore.schedule.enabled
            startMinute = sessionStore.schedule.startMinute
            endMinute = sessionStore.schedule.endMinute
        }
    }

    private func saveSchedule() {
        sessionStore.schedule = BlankFocusSchedule(
            enabled: enabled,
            startMinute: startMinute,
            endMinute: endMinute
        )
        dismiss()
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

private struct EmergencySheet: View {
    @Environment(\.dismiss) private var dismiss
    let emergencyUnlocksRemaining: Int
    let coachMessage: String
    let onUnlock: () -> Bool

    var body: some View {
        TechnicalSheetLayout {
            TechnicalSheetTitle("Emergency")
            TechnicalSheetDescription(coachMessage, emphasized: true)
            TechnicalSheetDescription("This turns Blank off without using your Blank and unlocks protected apps. Use it only if you need access now.")
            TechnicalSheetDescription(emergencyUnlocksRemaining > 0 ? "You have \(emergencyUnlocksRemaining) unlocks left this week." : "You have used your 3 unlocks this week.", emphasized: true)
            TechnicalSheetActions {
                Button("Unlock") {
                    if onUnlock() {
                        dismiss()
                    }
                }
                .buttonStyle(BlankPrimaryButtonStyle())
                .disabled(emergencyUnlocksRemaining <= 0)
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct TechnicalSheetLayout<Content: View>: View {
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
    let onStart: (Int) -> Void
    private let options = [15, 30, 45, 60, 90, 120]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Timer")
                .font(.blankInter(size: 38, weight: .medium, relativeTo: .largeTitle))
            Text("Blank turns off automatically when the timer ends. To exit earlier, use Blank or Emergency.")
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(options, id: \.self) { minutes in
                    Button(formatDuration(minutes)) {
                        onStart(minutes)
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

private func formatMinute(_ minuteOfDay: Int) -> String {
    let hour = max(0, min(23, minuteOfDay / 60))
    let minute = max(0, min(59, minuteOfDay % 60))
    return String(format: "%02d:%02d", hour, minute)
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
