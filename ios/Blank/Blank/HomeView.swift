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
    @State private var showingModes = false
    @State private var showingSettings = false
    @State private var showingSchedule = false
    @State private var showingEmergency = false
    @State private var showingRelink = false
    @State private var showingTimer = false
    @State private var nfcReader = NFCReader()
    @State private var displayedMessage = "No estas perdiendote nada."

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let idleMessages = ["No estas perdiendote nada.", "El scroll puede esperar.", "Para un momento.", "Toca empezar."]
    private let activeMessages = ["Bien. Ahora el movil espera.", "Sigue un poco mas.", "Respira un poco.", "Nada urgente. Como siempre."]

    var body: some View {
        ZStack {
            AppBackground(isActive: sessionStore.isBlankActive, themeId: sessionStore.backgroundThemeId)

            VStack(spacing: 0) {
                topBar
                configCard
                    .padding(.top, 18)
                Spacer()
                centerMessage
                Spacer()
                bottomAction
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 18)
        }
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
            displayedMessage = (sessionStore.isBlankActive ? activeMessages : idleMessages).randomElement() ?? "Blank"
            screenTimeBlocker.refreshAuthorizationStatus()
        }
        .onChange(of: sessionStore.isBlankActive) { isActive in
            withAnimation(.easeInOut(duration: 0.65)) {
                displayedMessage = (isActive ? activeMessages : idleMessages).randomElement() ?? "Blank"
            }
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            screenTimeBlocker.refreshAuthorizationStatus()
        }
        .familyActivityPicker(isPresented: $showingPicker, selection: $sessionStore.selection)
        .onChange(of: sessionStore.selection) { newSelection in
            screenTimeBlocker.updateSelection(newSelection, isBlankActive: sessionStore.isBlankActive)
        }
        .sheet(isPresented: $showingModes) {
            ModesSheet(showingPicker: $showingPicker)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(
                showingPicker: $showingPicker,
                showingSchedule: $showingSchedule,
                showingRelink: $showingRelink
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingSchedule) {
            ScheduleSheet()
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingEmergency) {
            EmergencySheet {
                withAnimation(.easeInOut(duration: 0.65)) {
                    _ = sessionStore.deactivateBlank()
                }
                screenTimeBlocker.clear()
                message = nil
                messageAction = nil
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingRelink) {
            RelinkSheet(message: $message, messageAction: $messageAction)
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

    private var topBar: some View {
        HStack {
            Button {
                showingModes = true
            } label: {
                HStack(spacing: 5) {
                    Text(sessionStore.currentMode.name)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .opacity(0.72)
                }
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(sessionStore.isBlankActive ? Color.white : BlankColors.ink)
            .buttonStyle(.plain)

            Spacer()

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.bold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(sessionStore.isBlankActive ? Color.white : BlankColors.ink)
            .buttonStyle(.plain)
        }
        .frame(height: 44)
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

    private var centerMessage: some View {
        VStack(spacing: 14) {
            Text(displayedMessage)
                .font(.blankSerif(size: 40, relativeTo: .largeTitle))
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.72)

            if sessionStore.isBlankActive, let blankActiveSince = sessionStore.blankActiveSince {
                Text(elapsedText(since: blankActiveSince))
                    .font(.blankSerif(size: 40, relativeTo: .largeTitle))
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

    private var bottomAction: some View {
        VStack(spacing: 12) {
            Button(sessionStore.isBlankActive ? "Escanear NFC para salir" : "Iniciar Blank") {
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
            .buttonStyle(BlankPrimaryButtonStyle(light: sessionStore.isBlankActive))
            .frame(maxWidth: 342)
            .padding(.horizontal, 6)

            if sessionStore.isBlankActive {
                Button("Emergencia") {
                    showingEmergency = true
                }
                .foregroundStyle(Color.white.opacity(0.74))
            }
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
    let themeId: String

    var body: some View {
        ZStack {
            BlankColors.background
                .opacity(isActive ? 0 : 1)
            BlankColors.ink
                .opacity(isActive ? 1 : 0)
            Image(inactiveAssetName)
                .resizable()
                .scaledToFill()
                .opacity(isActive ? 0 : 0.94)
            Image(activeAssetName)
                .resizable()
                .scaledToFill()
                .opacity(isActive ? 0.94 : 0)
            DotPattern()
                .opacity(isActive ? 0 : 0.22)
                .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.75), value: isActive)
    }

    private var inactiveAssetName: String {
        "bg_\(theme)_1"
    }

    private var activeAssetName: String {
        "bg_\(theme)_2"
    }

    private var theme: String {
        SessionStore.normalizedBackgroundThemeId(themeId)
    }
}

private struct DotPattern: View {
    var body: some View {
        Canvas { context, size in
            let color = BlankColors.mutedInk.opacity(0.35)
            let step: CGFloat = 13
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4)), with: .color(color))
                    x += step
                }
                y += step
            }
        }
    }
}

private struct ModesSheet: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Binding var showingPicker: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var newModeName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Modos") {
                    ForEach(sessionStore.focusModes) { mode in
                        Button {
                            sessionStore.selectMode(mode.id)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(mode.name)
                                    if mode.id == sessionStore.currentModeId {
                                        Text("\(sessionStore.selectionCount) selecciones")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if mode.id == sessionStore.currentModeId {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                sessionStore.deleteMode(mode.id)
                            } label: {
                                Label("Eliminar", systemImage: "trash")
                            }
                            .disabled(sessionStore.focusModes.count <= 1)
                        }
                    }
                }

                Section("Crear") {
                    TextField("Trabajo profundo", text: $newModeName)
                    Button("Crear modo") {
                        sessionStore.createMode(named: newModeName)
                        newModeName = ""
                    }
                }

                Section {
                    Button("Editar apps del modo actual") {
                        showingPicker = true
                        dismiss()
                    }
                }
            }
            .navigationTitle("Modos")
        }
    }
}

private struct SettingsSheet: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var screenTimeBlocker: ScreenTimeBlocker
    @Binding var showingPicker: Bool
    @Binding var showingSchedule: Bool
    @Binding var showingRelink: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    ReportView()
                } label: {
                    HStack {
                        Text("Progreso")
                        Spacer()
                        Text("Semana")
                            .foregroundStyle(.secondary)
                    }
                }
                settingsButton("Programar mi Blank", meta: "Diario") {
                    showingSchedule = true
                    dismiss()
                }
                settingsButton("Comprar NFC", meta: "Amazon") {
                    if let url = URL(string: "https://getblank.netlify.app/nfc.html") {
                        openURL(url)
                    }
                    dismiss()
                }
                Picker("Cambiar fondo", selection: $sessionStore.backgroundThemeId) {
                    Text("Grey").tag("gray")
                    Text("Sage").tag("sage")
                    Text("Mint").tag("mint")
                    Text("Teal").tag("teal")
                    Text("Blue").tag("blue")
                    Text("Indigo").tag("indigo")
                    Text("Purple").tag("purple")
                    Text("Rose").tag("rose")
                    Text("Coral").tag("coral")
                    Text("Amber").tag("amber")
                }
                settingsButton("Vincular nuevo NFC", meta: "Etiqueta") {
                    showingRelink = true
                    dismiss()
                }
                settingsButton("He olvidado mi Blank", meta: "Reset", role: .destructive) {
                    sessionStore.forgetNfcTag()
                    screenTimeBlocker.clear()
                    dismiss()
                }
            }
            .navigationTitle("Ajustes")
        }
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
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ScheduleSheet: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var enabled = false
    @State private var startDate = dateForMinute(23 * 60 + 30)
    @State private var endDate = dateForMinute(8 * 60)

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Activar horario diario", isOn: $enabled)
                Section("Inicio") {
                    DatePicker("Inicio", selection: $startDate, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                }
                Section("Fin") {
                    DatePicker("Fin", selection: $endDate, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                }
                Text("Blank se activa solo en esa franja. Para salir antes sigues necesitando tu NFC.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Horario")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        sessionStore.schedule = BlankFocusSchedule(
                            enabled: enabled,
                            startMinute: minuteOfDay(from: startDate),
                            endMinute: minuteOfDay(from: endDate)
                        )
                        dismiss()
                    }
                }
            }
            .onAppear {
                enabled = sessionStore.schedule.enabled
                startDate = dateForMinute(sessionStore.schedule.startMinute)
                endDate = dateForMinute(sessionStore.schedule.endMinute)
            }
        }
    }
}

private struct EmergencySheet: View {
    @Environment(\.dismiss) private var dismiss
    let onUnlock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Emergencia")
                .font(.blankSerif(size: 42, relativeTo: .largeTitle))
            Text("Esto desactiva Blank sin usar tu NFC y desbloquea las apps protegidas. Usalo solo si necesitas recuperar el acceso ahora.")
                .foregroundStyle(.secondary)
            Button("Confirmar emergencia") {
                onUnlock()
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
        backgroundThemeId: String = "gray",
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
            backgroundThemeId: backgroundThemeId,
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

#Preview("Home - Grey") {
    HomePreviewScene("Home - Grey", backgroundThemeId: "gray")
}

#Preview("Home - Mint") {
    HomePreviewScene("Home - Mint", backgroundThemeId: "mint")
}

#Preview("Home - Sin apps") {
    HomePreviewScene("Home - Sin apps", protectedSelectionCount: 0)
}

#Preview("Home - NFC pendiente") {
    HomePreviewScene("Home - NFC pendiente", nfcLinked: false)
}

#Preview("Blank activo") {
    HomePreviewScene("Blank activo", isBlankActive: true, backgroundThemeId: "gray")
}

#Preview("Blank activo - Timer") {
    HomePreviewScene(
        "Blank activo - Timer",
        isBlankActive: true,
        backgroundThemeId: "indigo",
        timedUntil: Date().addingTimeInterval(38 * 60)
    )
}

#Preview("Horario pausado") {
    HomePreviewScene(
        "Horario pausado",
        isBlankActive: false,
        backgroundThemeId: "teal",
        schedule: BlankFocusSchedule(enabled: true, startMinute: 0, endMinute: 24 * 60 - 1),
        schedulePausedUntil: Date().addingTimeInterval(5 * 60)
    )
}

#Preview("Permiso pendiente") {
    HomePreviewScene("Permiso pendiente", authorizationApproved: false)
}
#endif
