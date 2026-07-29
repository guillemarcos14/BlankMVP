import FamilyControls
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var screenTimeBlocker: ScreenTimeBlocker
    @Environment(\.scenePhase) private var scenePhase

    @State private var now = Date()
    @State private var message: String?
    @State private var messageAction: ConfigIssue.Action?
    @State private var showingPicker = false
    @State private var showingSettings = false
    @State private var showingSchedule = false
    @State private var showingEmergency = false
    @State private var showingReport = false
    @State private var showingModes = false
    @State private var showingRelink = false
    @State private var showingForgetConfirm = false
    @State private var showingTimer = false
    @State private var nfcReader = NFCReader()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let homeTagline = "Shaping what we\ncreate with the\npower of time."

    var body: some View {
        GeometryReader { proxy in
            let layout = HomeLayoutMetrics(size: proxy.size, safeAreaInsets: proxy.safeAreaInsets)

            ZStack {
                AppBackground(isActive: sessionStore.isBlankActive)

                topCluster(spacing: layout.topClusterSpacing)
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.top, layout.topPadding)
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
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(
                showingPicker: $showingPicker,
                showingSchedule: $showingSchedule,
                showingEmergency: $showingEmergency,
                showingRelink: $showingRelink,
                showingForgetConfirm: $showingForgetConfirm
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingReport) {
            NavigationStack {
                ReportView()
            }
            .preferredColorScheme(.light)
        }
        .sheet(isPresented: $showingModes) {
            NavigationStack {
                ModesList(showingPicker: $showingPicker) {
                    showingModes = false
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingSchedule) {
            ScheduleSheet()
                .presentationDetents([.medium])
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
        .sheet(isPresented: $showingTimer) {
            TimerStartSheet { minutes in
                let result = withAnimation(.easeInOut(duration: 0.65)) {
                    sessionStore.activateBlank(durationMinutes: minutes)
                }
                screenTimeBlocker.apply(isBlankActive: sessionStore.isBlankActive)
                setMessage(for: result)
            }
            .presentationDetents([.medium])
        }
    }

    private func topCluster(spacing: CGFloat) -> some View {
        VStack(spacing: spacing) {
            topBar
            configCard
        }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 14) {
            Button {
                showingSettings = true
            } label: {
                Image("blank_logo_white")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 10)

            HStack(spacing: 0) {
                topNavButton("Stats") {
                    showingReport = true
                }
                topNavButton("Mode") {
                    showingModes = true
                }
                topNavButton("Timer") {
                    showingTimer = true
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(Color.white.opacity(0.16))
            .clipShape(Capsule())
        }
        .frame(height: 44)
        .zIndex(2)
    }

    private func topNavButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.blankInter(size: 15, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(Color.white)
                .frame(minWidth: 58)
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        VStack(spacing: 24) {
            Text(homeTagline)
                .font(.blankInter(size: 37, weight: .medium, relativeTo: .largeTitle))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .lineSpacing(1)
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
            let buttonWidth = sessionStore.isBlankActive ? width : min(width, 178)
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
    let topClusterSpacing: CGFloat
    let bottomPadding: CGFloat
    let messageMaxWidth: CGFloat
    let actionWidth: CGFloat
    let centerX: CGFloat
    let messageCenterY: CGFloat

    init(size: CGSize, safeAreaInsets: EdgeInsets) {
        let width = max(size.width, 320)
        let height = max(size.height, 600)
        let topSafeArea = safeAreaInsets.top > 0 ? safeAreaInsets.top : 44
        horizontalPadding = min(max(width * 0.075, 28), 36)
        topPadding = topSafeArea + 10
        topClusterSpacing = 14
        bottomPadding = max(safeAreaInsets.bottom + 18, 34)
        messageMaxWidth = min(max(width - horizontalPadding * 2, 280), 350)
        actionWidth = min(max(width - horizontalPadding * 2, 260), 342)
        centerX = width / 2
        messageCenterY = height * 0.56
    }
}

private struct HomeBlankearButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.blankInter(size: 16, weight: .semibold, relativeTo: .headline))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color(red: 0.69, green: 0.70, blue: 0.72).opacity(0.82))
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.02 : 0.06), radius: 10, y: 5)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
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
    private var secondaryColor: Color { sessionStore.isBlankActive ? Color.white.opacity(0.70) : BlankColors.ink }

    var body: some View {
        List {
            Section {
                ForEach(sessionStore.focusModes) { mode in
                    Button {
                        sessionStore.selectMode(mode.id)
                        onFinish()
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(mode.name)
                                if mode.id == sessionStore.currentModeId {
                                    Text("\(sessionStore.selectionCount) selecciones")
                                        .font(.caption)
                                        .foregroundStyle(secondaryColor)
                                }
                            }
                            Spacer()
                            if mode.id == sessionStore.currentModeId {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(textColor)
                            }
                        }
                    }
                    .foregroundStyle(textColor)
                    .swipeActions {
                        Button(role: .destructive) {
                            sessionStore.deleteMode(mode.id)
                        } label: {
                            Label("Eliminar", systemImage: "trash")
                        }
                        .disabled(sessionStore.focusModes.count <= 1)
                    }
                }
            } header: {
                Text("Modos")
                    .foregroundStyle(textColor)
            }

            Section {
                TextField("Trabajo profundo", text: $newModeName)
                    .foregroundStyle(textColor)
                Button("Crear modo") {
                    sessionStore.createMode(named: newModeName)
                    newModeName = ""
                }
                .foregroundStyle(textColor)
            } header: {
                Text("Crear")
                    .foregroundStyle(textColor)
            }

            Section {
                Button("Editar apps del modo actual") {
                    showingPicker = true
                    onFinish()
                }
                .foregroundStyle(textColor)
            }
        }
        .navigationTitle("Modos")
        .tint(textColor)
        .preferredColorScheme(sessionStore.isBlankActive ? .dark : .light)
    }
}

private struct SettingsSheet: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var screenTimeBlocker: ScreenTimeBlocker
    @Binding var showingPicker: Bool
    @Binding var showingSchedule: Bool
    @Binding var showingEmergency: Bool
    @Binding var showingRelink: Bool
    @Binding var showingForgetConfirm: Bool
    @Environment(\.dismiss) private var dismiss
    private var textColor: Color { sessionStore.isBlankActive ? Color.white : BlankColors.ink }

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    ModesList(showingPicker: $showingPicker) {
                        dismiss()
                    }
                } label: {
                    HStack {
                        Text("Modo")
                        Spacer()
                        Text(sessionStore.currentMode.name)
                    }
                    .foregroundStyle(textColor)
                }
                settingsButton("Programar mi Blank", meta: "Diario") {
                    showingSchedule = true
                    dismiss()
                }
                NavigationLink {
                    ReportView()
                        .preferredColorScheme(.light)
                } label: {
                    HStack {
                        Text("Progreso")
                        Spacer()
                        Text("Tiempo")
                    }
                    .foregroundStyle(textColor)
                }
                settingsButton("Vincular nuevo NFC", meta: "Etiqueta") {
                    showingRelink = true
                    dismiss()
                }
                settingsButton("He olvidado mi Blank", meta: "Reset") {
                    showingForgetConfirm = true
                    dismiss()
                }
                settingsButton("Emergencia", meta: "Salida", role: .destructive) {
                    showingEmergency = true
                    dismiss()
                }
            }
            .navigationTitle("Ajustes")
            .tint(textColor)
        }
        .preferredColorScheme(sessionStore.isBlankActive ? .dark : .light)
    }

    private func settingsButton(
        _ label: String,
        meta: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            HStack {
                Text(label)
                Spacer()
                Text(meta)
            }
        }
        .foregroundStyle(role == .destructive ? Color.red : textColor)
    }
}

private struct ScheduleSheet: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var enabled = false
    @State private var startMinute = 23 * 60 + 30
    @State private var endMinute = 8 * 60

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Toggle("Activar horario diario", isOn: $enabled)
                    .font(.blankInter(size: 16, weight: .medium, relativeTo: .body))

                VStack(spacing: 10) {
                    TimeMenuRow(title: "Inicio", minute: $startMinute)
                    TimeMenuRow(title: "Fin", minute: $endMinute)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Ventana activa")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BlankColors.mutedInk)
                    Text("\(formatMinute(startMinute)) - \(formatMinute(endMinute))")
                        .font(.blankInter(size: 28, weight: .semibold, relativeTo: .title2))
                    Text("Blank se activa solo en esa franja. Para salir antes sigues necesitando tu NFC.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                Spacer(minLength: 0)
            }
            .padding(24)
            .navigationTitle("Horario")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        sessionStore.schedule = BlankFocusSchedule(
                            enabled: enabled,
                            startMinute: startMinute,
                            endMinute: endMinute
                        )
                        dismiss()
                    }
                }
            }
            .onAppear {
                enabled = sessionStore.schedule.enabled
                startMinute = sessionStore.schedule.startMinute
                endMinute = sessionStore.schedule.endMinute
            }
        }
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
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BlankColors.mutedInk)
            }
            .foregroundStyle(BlankColors.ink)
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background(Color.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

private struct ForgetBlankConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("He olvidado mi Blank")
                .font(.blankSerif(size: 40, relativeTo: .largeTitle))
            Text("Esto desactiva Blank, borra la pieza NFC vinculada y vuelve al onboarding para que puedas registrar una nueva.")
                .foregroundStyle(.secondary)
            Text("Tus modos y apps seleccionadas se mantienen.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

            Button("Sí, olvidar mi Blank") {
                onConfirm()
                dismiss()
            }
            .buttonStyle(BlankPrimaryButtonStyle())

            Button("Cancelar") {
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
    }
}

private struct EmergencySheet: View {
    @Environment(\.dismiss) private var dismiss
    let emergencyUnlocksRemaining: Int
    let onUnlock: () -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Emergencia")
                .font(.blankSerif(size: 42, relativeTo: .largeTitle))
            Text("Esto desactiva Blank sin usar tu NFC y desbloquea las apps protegidas. Usalo solo si necesitas recuperar el acceso ahora.")
                .foregroundStyle(.secondary)
            Text(emergencyUnlocksRemaining > 0 ? "Te quedan \(emergencyUnlocksRemaining) desbloqueos de emergencia esta semana." : "Ya has usado tus 3 desbloqueos de emergencia esta semana.")
                .foregroundStyle(.secondary)
            Button("Confirmar emergencia") {
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
            Spacer()
        }
        .padding(24)
    }
}

private struct RelinkSheet: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss
    @Binding var message: String?
    @Binding var messageAction: ConfigIssue.Action?
    @State private var nfcReader = NFCReader()

    var body: some View {
        VStack(spacing: 18) {
            Text("Nueva pieza NFC")
                .font(.largeTitle.weight(.bold))
            Text("Blank mantendra tus apps protegidas y cambiara solo la llave fisica.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Escanear NFC") {
                nfcReader.scan { result in
                    Task { @MainActor in
                        switch result {
                        case .success(let uid):
                            sessionStore.nfcTagUid = uid
                            message = "Nueva pieza NFC vinculada."
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
            Spacer()
        }
        .padding(24)
    }
}

private struct TimerStartSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onStart: (Int) -> Void
    private let options = [15, 30, 45, 60, 90, 120]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Timer")
                .font(.blankSerif(size: 42, relativeTo: .largeTitle))
            Text("Blank se desactiva automaticamente al terminar. Si quieres salir antes, usa tu NFC o emergencia.")
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
