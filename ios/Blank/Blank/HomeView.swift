import FamilyControls
import SwiftUI

private enum SettingsRoute: Hashable {
    case modes
    case schedule
    case report
}

struct HomeView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var screenTimeBlocker: ScreenTimeBlocker
    @Environment(\.scenePhase) private var scenePhase

    @State private var now = Date()
    @State private var message: String?
    @State private var messageAction: ConfigIssue.Action?
    @State private var showingPicker = false
    @State private var showingSettings = false
    @State private var settingsRoute: SettingsRoute?
    @State private var showingEmergency = false
    @State private var showingRelink = false
    @State private var showingForgetConfirm = false
    @State private var nfcReader = NFCReader()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let homeTagline = "Shaping what we\ncreate with the\npower of time."

    var body: some View {
        GeometryReader { proxy in
            let layout = HomeLayoutMetrics(size: proxy.size, safeAreaInsets: proxy.safeAreaInsets)

            ZStack {
                AppBackground(isActive: sessionStore.isBlankActive)

                topBar
                    .position(x: layout.centerX, y: layout.topBarCenterY)
                    .zIndex(2)

                configCard
                    .padding(.horizontal, layout.horizontalPadding)
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
            sessionStore.applyScheduleWindow(at: date)
            screenTimeBlocker.apply(isBlankActive: sessionStore.isBlankActive)
        }
        .onAppear {
            screenTimeBlocker.refreshAuthorizationStatus()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            screenTimeBlocker.refreshAuthorizationStatus()
        }
        .familyActivityPicker(isPresented: $showingPicker, selection: $sessionStore.selection)
        .onChange(of: sessionStore.selection) { newSelection in
            screenTimeBlocker.updateSelection(newSelection, isBlankActive: sessionStore.isBlankActive)
        }
        .onChange(of: sessionStore.shouldOpenBlockConfiguration) { shouldOpen in
            guard shouldOpen else { return }
            openSettings(.modes)
            sessionStore.shouldOpenBlockConfiguration = false
        }
        .sheet(isPresented: $showingSettings, onDismiss: {
            settingsRoute = nil
        }) {
            SettingsSheet(
                initialRoute: $settingsRoute,
                showingPicker: $showingPicker,
                showingEmergency: $showingEmergency,
                showingRelink: $showingRelink,
                showingForgetConfirm: $showingForgetConfirm
            )
            .presentationDetents([.medium, .large])
            .blankTransparentPresentation()
        }
        .sheet(isPresented: $showingEmergency) {
            EmergencySheet(emergencyUnlocksRemaining: sessionStore.emergencyUnlocksRemaining) {
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
                openSettings()
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
                    openSettings(.report)
                }
                topNavButton("Mode") {
                    openSettings(.modes)
                }
                topNavButton("Habits") {
                    openSettings(.schedule)
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

    private func openSettings(_ route: SettingsRoute? = nil) {
        settingsRoute = route
        showingSettings = true
    }

    @ViewBuilder
    private var configCard: some View {
        let issues = configIssues
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(issues) { issue in
                    Button {
                        resolve(issue.action)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.circle")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(issue.title)
                                    .font(.blankInter(size: 15, weight: .semibold, relativeTo: .subheadline))
                                Text(issue.body)
                                    .font(.blankInter(size: 13, relativeTo: .footnote))
                                    .foregroundStyle(BlankColors.mutedInk)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BlankColors.mutedInk)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func centerContent(maxWidth: CGFloat, actionWidth: CGFloat) -> some View {
        VStack(spacing: 22) {
            Text(homeTagline)
                .font(.blankInter(size: 32.4, weight: .medium, relativeTo: .largeTitle))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .lineSpacing(-2)
                .lineLimit(3)
                .minimumScaleFactor(0.78)

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
                    Text("Termina en \(remainingText(until: blankActiveUntil))")
                        .font(.blankBody)
                        .foregroundStyle(Color.white.opacity(0.76))
                    Text(sessionStore.deviceActivityTimerScheduled ? "Timer del sistema activo" : "Timer interno activo")
                        .font(.blankInter(size: 13, relativeTo: .footnote))
                        .foregroundStyle(Color.white.opacity(0.58))
                }
                if let schedulePausedUntil = sessionStore.schedulePausedUntil, now < schedulePausedUntil {
                    Text("Horario pausado \(remainingText(until: schedulePausedUntil))")
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
            Button(sessionStore.isBlankActive ? "Escanear Blank para salir" : "Blankear") {
                if sessionStore.isBlankActive {
                    scanTag()
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
        }
    }

    private var configIssues: [ConfigIssue] {
        var issues: [ConfigIssue] = []
        if screenTimeBlocker.authorizationStatus != .approved {
            issues.append(ConfigIssue(
                title: "Screen Time pendiente",
                body: "Autoriza Screen Time para que iOS aplique los escudos.",
                action: .screenTime
            ))
        }
        if sessionStore.nfcTagUid == nil {
            issues.append(ConfigIssue(
                title: "NFC sin vincular",
                body: "Escanea una pieza fisica para poder salir de Blank.",
                action: .relinkNfc
            ))
        }
        if !sessionStore.hasSelectedApps {
            issues.append(ConfigIssue(
                title: "Sin apps seleccionadas",
                body: "Elige apps, categorias o dominios antes de iniciar.",
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
                message = approved ? "Screen Time autorizado." : "Screen Time sigue pendiente."
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

    private func setMessage(for result: SessionStore.NfcResult) {
        switch result {
        case .tagRegistered:
            message = "NFC registrado."
            messageAction = nil
        case .blanked, .unblanked:
            message = nil
            messageAction = nil
        case .schedulePaused:
            message = "Apps desbloqueadas 5 minutos."
            messageAction = nil
        case .wrongTag:
            message = "Ese NFC no es tu pieza de Blank."
            messageAction = nil
        case .noAppsSelected:
            message = "Sin apps seleccionadas"
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
                subtitle: "Elige el modo activo de bloqueo\ny edita las apps que protege.",
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
                            Label("Eliminar", systemImage: "trash")
                        }
                        .disabled(sessionStore.focusModes.count <= 1)
                    }
            }

            VStack(spacing: 10) {
                TextField("Crea un modo personalizado", text: $newModeName)
                    .font(.blankInter(size: 16, weight: .medium, relativeTo: .body))
                    .foregroundStyle(textColor)
                    .padding(.horizontal, 18)
                    .frame(height: 56)
                    .blankGlassCard(cornerRadius: 18, tintOpacity: 0.20)

                Button {
                    sessionStore.createMode(named: newModeName)
                    newModeName = ""
                } label: {
                    TopSheetPrimaryButtonLabel(title: "Crear modo")
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
                    Text("Editar apps del modo actual")
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

                    Text(isSelected ? blockedAppsText : "Toca para activar este modo")
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
        return "\(count) app \(count == 1 ? "bloqueada" : "bloqueadas")"
    }
}

private struct SettingsSheet: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var screenTimeBlocker: ScreenTimeBlocker
    @Binding var initialRoute: SettingsRoute?
    @Binding var showingPicker: Bool
    @Binding var showingEmergency: Bool
    @Binding var showingRelink: Bool
    @Binding var showingForgetConfirm: Bool
    @Environment(\.dismiss) private var dismiss
    private var textColor: Color { sessionStore.isBlankActive ? Color.white : BlankColors.ink }

    var body: some View {
        Group {
            if initialRoute == nil {
                NavigationStack {
                    settingsContent
                }
            } else {
                routeContent
            }
        }
        .preferredColorScheme(sessionStore.isBlankActive ? .dark : .light)
    }

    @ViewBuilder
    private var routeContent: some View {
        switch initialRoute {
        case .modes:
            ModesList(showingPicker: $showingPicker) {
                dismiss()
            }
        case .schedule:
            ScheduleEditorContent()
        case .report:
            ReportView()
                .preferredColorScheme(.light)
        case nil:
            EmptyView()
        }
    }

    private var settingsContent: some View {
        List {
            Text("Ajustes")
                .font(.blankInter(size: 34, weight: .medium, relativeTo: .largeTitle))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            settingsButton("Vincular nuevo Blank") {
                showingRelink = true
                dismiss()
            }
            settingsButton("He olvidado mi Blank") {
                showingForgetConfirm = true
                dismiss()
            }
            settingsButton("Emergencia", role: .destructive) {
                showingEmergency = true
                dismiss()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(BlankAtmosphericBackground(dimmed: sessionStore.isBlankActive).ignoresSafeArea())
        .toolbarBackground(.hidden, for: .navigationBar)
        .tint(textColor)
    }

    private func settingsButton(
        _ label: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            HStack {
                Text(label)
                Spacer()
            }
        }
        .foregroundStyle(role == .destructive ? Color.red : textColor)
        .listRowBackground(Color.clear)
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

    var body: some View {
        List {
            VStack(alignment: .center, spacing: 16) {
                TopSheetHeader(
                    title: "Habits",
                    subtitle: "Programa cuándo Blank se activa solo\ny guarda tu horario diario."
                )

                    Toggle("Horario diario", isOn: $enabled)
                        .font(.blankInter(size: 16, weight: .medium, relativeTo: .body))
                        .padding(.horizontal, 18)
                        .frame(height: 56)
                        .blankGlassCard(cornerRadius: 18, tintOpacity: 0.28)

                    VStack(spacing: 10) {
                        TimeMenuRow(title: "Inicio", minute: $startMinute)
                        TimeMenuRow(title: "Fin", minute: $endMinute)
                        StaticScheduleRow(title: "Días", value: "Todos")
                    }

                    Text("Para salir antes necesitas tu Blank o emergencia.")
                        .font(.footnote)
                        .foregroundStyle(BlankColors.mutedInk)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                        .padding(.top, 2)

                    Button {
                        saveSchedule()
                    } label: {
                        TopSheetPrimaryButtonLabel(title: "Guardar")
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
        .background(BlankAtmosphericBackground().ignoresSafeArea())
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

    var body: some View {
        HStack {
            Text(title)
                .font(.blankInter(size: 16, weight: .medium, relativeTo: .body))
            Spacer()
            Text(value)
                .font(.blankInter(size: 20, weight: .semibold, relativeTo: .title3))
        }
        .foregroundStyle(BlankColors.ink)
        .padding(.horizontal, 18)
        .frame(height: 56)
        .blankGlassCard(cornerRadius: 18, tintOpacity: 0.30)
    }
}

private struct TimeMenuRow: View {
    let title: String
    @Binding var minute: Int

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
            .foregroundStyle(BlankColors.ink)
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
            TechnicalSheetTitle("He olvidado mi Blank")
            TechnicalSheetDescription("Esto desactiva Blank, borra la pieza vinculada y vuelve al onboarding para que puedas registrar una nueva.")
            TechnicalSheetDescription("Tus modos y apps seleccionadas se mantienen.", emphasized: true)
            TechnicalSheetActions {
                Button("He olvidado mi Blank") {
                    onConfirm()
                    dismiss()
                }
                .buttonStyle(BlankPrimaryButtonStyle())

                Button("Cancelar") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct EmergencySheet: View {
    @Environment(\.dismiss) private var dismiss
    let emergencyUnlocksRemaining: Int
    let onUnlock: () -> Bool

    var body: some View {
        TechnicalSettingsSheetLayout {
            TechnicalSheetTitle("Emergencia")
            TechnicalSheetDescription("Esto desactiva Blank sin usar tu Blank y desbloquea las apps protegidas. Usalo solo si necesitas recuperar el acceso ahora.")
            TechnicalSheetDescription(emergencyUnlocksRemaining > 0 ? "Te quedan \(emergencyUnlocksRemaining) desbloqueos esta semana." : "Ya has usado tus 3 desbloqueos esta semana.", emphasized: true)
            TechnicalSheetActions {
                Button("Desbloquear") {
                    if onUnlock() {
                        dismiss()
                    }
                }
                .buttonStyle(BlankPrimaryButtonStyle())
                .disabled(emergencyUnlocksRemaining <= 0)
                Button("Cancelar") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
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
            TechnicalSheetTitle("Nuevo Blank")
            TechnicalSheetDescription("Escanea el nuevo Blank para sustituir el que tienes vinculado. Tus modos y apps protegidas se mantienen.")
            TechnicalSheetActions {
                Button("Escanear nuevo Blank") {
                    nfcReader.scan { result in
                        Task { @MainActor in
                            switch result {
                            case .success(let uid):
                                sessionStore.nfcTagUid = uid
                                message = "Nuevo Blank vinculado."
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

                Button("Cancelar") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct TechnicalSettingsSheetLayout<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 18) {
            content
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BlankAtmosphericBackground())
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
            Text("Blank se desactiva automaticamente al terminar. Si quieres salir antes, usa tu Blank o emergencia.")
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

#Preview("Home - Reposo") {
    HomePreviewScene("Home - Reposo")
}

#Preview("Home - Sin apps") {
    HomePreviewScene("Home - Sin apps", protectedSelectionCount: 0)
}

#Preview("Home - NFC pendiente") {
    HomePreviewScene("Home - NFC pendiente", nfcLinked: false)
}

#Preview("Blank activo") {
    HomePreviewScene("Blank activo", isBlankActive: true)
}

#Preview("Blank activo - Timer") {
    HomePreviewScene(
        "Blank activo - Timer",
        isBlankActive: true,
        timedUntil: Date().addingTimeInterval(38 * 60)
    )
}

#Preview("Horario pausado") {
    HomePreviewScene(
        "Horario pausado",
        isBlankActive: false,
        schedule: BlankFocusSchedule(enabled: true, startMinute: 0, endMinute: 24 * 60 - 1),
        schedulePausedUntil: Date().addingTimeInterval(5 * 60)
    )
}

#Preview("Permiso pendiente") {
    HomePreviewScene("Permiso pendiente", authorizationApproved: false)
}
#endif
