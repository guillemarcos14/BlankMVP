import FamilyControls
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var screenTimeBlocker: ScreenTimeBlocker
    @Environment(\.scenePhase) private var scenePhase

    @State private var now = Date()
    @State private var message: String?
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
    private let activeMessages = ["Bien. Ahora el movil espera.", "Sigue un poco mas.", "Blank esta activo.", "Nada urgente. Como siempre."]

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
            .padding(.vertical, 42)
        }
        .foregroundStyle(sessionStore.isBlankActive ? Color.white : BlankColors.ink)
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
            displayedMessage = (isActive ? activeMessages : idleMessages).randomElement() ?? "Blank"
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
                _ = sessionStore.deactivateBlank()
                screenTimeBlocker.clear()
                message = "Blank desactivado por emergencia."
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingRelink) {
            RelinkSheet(message: $message)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingTimer) {
            TimerStartSheet { minutes in
                let result = sessionStore.activateBlank(durationMinutes: minutes)
                screenTimeBlocker.apply(isBlankActive: sessionStore.isBlankActive)
                message = messageText(for: result)
            }
            .presentationDetents([.medium])
        }
    }

    private var topBar: some View {
        HStack {
            Button(sessionStore.currentMode.name) {
                showingModes = true
            }
            .font(.body.weight(.semibold))
            .buttonStyle(.plain)
            Spacer()
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var configCard: some View {
        let issues = configIssues
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(issues, id: \.title) { issue in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.circle")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(issue.title)
                                .font(.subheadline.weight(.semibold))
                            Text(issue.body)
                                .font(.footnote)
                                .foregroundStyle(BlankColors.mutedInk)
                        }
                    }
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
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.72)

            if sessionStore.isBlankActive, let blankActiveSince = sessionStore.blankActiveSince {
                Text(elapsedText(since: blankActiveSince))
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                if let blankActiveUntil = sessionStore.blankActiveUntil {
                    Text("Termina en \(remainingText(until: blankActiveUntil))")
                        .font(.body)
                        .foregroundStyle(Color.white.opacity(0.76))
                    Text(sessionStore.deviceActivityTimerScheduled ? "Timer del sistema activo" : "Timer interno activo")
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.58))
                }
            } else {
                Text("\(sessionStore.selectionCount) selecciones protegidas")
                    .font(.body)
                    .foregroundStyle(BlankColors.mutedInk)
            }

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(sessionStore.isBlankActive ? Color.white.opacity(0.72) : BlankColors.mutedInk)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
        }
    }

    private var bottomAction: some View {
        VStack(spacing: 12) {
            Button(sessionStore.isBlankActive ? "Escanear NFC para salir" : "Iniciar Blank") {
                if sessionStore.isBlankActive {
                    scanTag()
                } else {
                    let result = sessionStore.activateBlank()
                    screenTimeBlocker.apply(isBlankActive: sessionStore.isBlankActive)
                    message = messageText(for: result)
                }
            }
            .buttonStyle(BlankPrimaryButtonStyle(light: sessionStore.isBlankActive))

            if sessionStore.isBlankActive {
                Button("Emergencia") {
                    showingEmergency = true
                }
                .foregroundStyle(Color.white.opacity(0.74))
            }
        }
    }

    private var configIssues: [(title: String, body: String)] {
        var issues: [(String, String)] = []
        if screenTimeBlocker.authorizationStatus != .approved {
            issues.append(("Screen Time pendiente", "Autoriza Screen Time para que iOS aplique los escudos."))
        }
        if sessionStore.nfcTagUid == nil {
            issues.append(("NFC sin vincular", "Escanea una pieza fisica para poder salir de Blank."))
        }
        if !sessionStore.hasSelectedApps {
            issues.append(("Sin apps seleccionadas", "Elige apps, categorias o dominios antes de iniciar."))
        }
        return issues
    }

    private func scanTag() {
        nfcReader.scan { result in
            Task { @MainActor in
                switch result {
                case .success(let uid):
                    let nfcResult = sessionStore.handleNfcTag(uid: uid)
                    screenTimeBlocker.apply(isBlankActive: sessionStore.isBlankActive)
                    message = messageText(for: nfcResult)
                case .failure(let error):
                    message = error.localizedDescription
                }
            }
        }
    }

    private func messageText(for result: SessionStore.NfcResult) -> String {
        switch result {
        case .tagRegistered:
            return "NFC registrado."
        case .blanked:
            return "Blank activado."
        case .unblanked:
            return "Blank desactivado."
        case .wrongTag:
            return "Ese NFC no es tu pieza de Blank."
        case .noAppsSelected:
            return "Selecciona al menos una app antes."
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

private struct AppBackground: View {
    let isActive: Bool
    let themeId: String

    var body: some View {
        LinearGradient(
            colors: isActive ? [Color.black, BlankColors.redDark] : colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay {
            if !isActive {
                DotPattern()
                    .opacity(0.22)
                    .ignoresSafeArea()
            }
        }
    }

    private var colors: [Color] {
        switch themeId {
        case "sage":
            return [Color(red: 0.80, green: 0.84, blue: 0.75), BlankColors.warmBackground]
        case "mint":
            return [Color(red: 0.76, green: 0.88, blue: 0.82), BlankColors.warmBackground]
        case "teal":
            return [Color(red: 0.62, green: 0.80, blue: 0.78), BlankColors.warmBackground]
        case "blue":
            return [Color(red: 0.75, green: 0.82, blue: 0.90), BlankColors.warmBackground]
        case "indigo":
            return [Color(red: 0.68, green: 0.72, blue: 0.88), BlankColors.warmBackground]
        case "purple":
            return [Color(red: 0.78, green: 0.70, blue: 0.88), BlankColors.warmBackground]
        case "rose":
            return [Color(red: 0.91, green: 0.78, blue: 0.80), BlankColors.warmBackground]
        case "coral":
            return [Color(red: 0.92, green: 0.70, blue: 0.64), BlankColors.warmBackground]
        case "amber":
            return [Color(red: 0.92, green: 0.78, blue: 0.50), BlankColors.warmBackground]
        default:
            return [BlankColors.warmBackground, Color(red: 0.82, green: 0.82, blue: 0.78)]
        }
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
                    Text("Grey").tag("grey")
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
    @State private var startTime = "23:30"
    @State private var endTime = "08:00"

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Activar horario diario", isOn: $enabled)
                TextField("Inicio", text: $startTime)
                    .keyboardType(.numbersAndPunctuation)
                TextField("Fin", text: $endTime)
                    .keyboardType(.numbersAndPunctuation)
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
                            startMinute: parseMinute(startTime) ?? sessionStore.schedule.startMinute,
                            endMinute: parseMinute(endTime) ?? sessionStore.schedule.endMinute
                        )
                        dismiss()
                    }
                }
            }
            .onAppear {
                enabled = sessionStore.schedule.enabled
                startTime = formatMinute(sessionStore.schedule.startMinute)
                endTime = formatMinute(sessionStore.schedule.endMinute)
            }
        }
    }
}

private struct EmergencySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var phrase = ""
    let onUnlock: () -> Void
    private let expected = "necesito salir de Blank"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Emergencia")
                .font(.largeTitle.weight(.bold))
            Text("Escribe la frase completa para desbloquear sin NFC.")
                .foregroundStyle(.secondary)
            Text(expected)
                .font(.headline)
            TextField("Frase", text: $phrase)
                .textFieldStyle(.roundedBorder)
            Button("Desbloquear") {
                onUnlock()
                dismiss()
            }
            .buttonStyle(BlankPrimaryButtonStyle())
            .disabled(phrase.trimmingCharacters(in: .whitespacesAndNewlines) != expected)
            Spacer()
        }
        .padding(24)
    }
}

private struct RelinkSheet: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss
    @Binding var message: String?
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
                            dismiss()
                        case .failure(let error):
                            message = error.localizedDescription
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
                .font(.largeTitle.weight(.bold))
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
