import FamilyControls
import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var screenTimeBlocker: ScreenTimeBlocker
    @Environment(\.scenePhase) private var scenePhase

    @State private var currentStep = 0
    @State private var showingPicker = false
    @State private var message: String?
    @State private var nfcReader = NFCReader()

    var body: some View {
        ZStack {
            BlankAtmosphericBackground()

            VStack(spacing: 0) {
            header

            Spacer(minLength: 48)

            Group {
                switch currentStep {
                case 0:
                    stepContent(
                        eyebrow: "Paso 1 de 3",
                        title: "Permite que Blank bloquee.",
                        body: screenTimeDescription,
                        statusText: screenTimeBlocker.authorizationStatus == .approved ? "Screen Time listo" : nil,
                        primaryTitle: screenTimeBlocker.authorizationStatus == .approved ? "Continuar" : "Autorizar Screen Time",
                        secondaryTitle: nil,
                        primaryAction: authorizeScreenTime
                    )
                case 1:
                    stepContent(
                        eyebrow: "Paso 2 de 3",
                        title: "Elige qué quieres dejar fuera.",
                        body: sessionStore.hasSelectedApps
                            ? "\(sessionStore.selectionCount) selecciones protegidas en \(sessionStore.currentMode.name)."
                            : "Selecciona apps, categorías o dominios. En iOS Apple entrega tokens privados, no nombres de paquetes.",
                        statusText: sessionStore.hasSelectedApps ? "Apps listas" : nil,
                        primaryTitle: sessionStore.hasSelectedApps ? "Continuar" : "Seleccionar apps",
                        secondaryTitle: sessionStore.hasSelectedApps ? "Editar selección" : nil,
                        primaryAction: selectAppsOrContinue,
                        secondaryAction: { showingPicker = true }
                    )
                case 2:
                    stepContent(
                        eyebrow: "Paso 3 de 3",
                        title: "Vincula tu pieza física.",
                        body: sessionStore.nfcTagUid == nil
                            ? "Escanea el NFC que activará y desactivará Blank en este iPhone."
                            : "NFC registrado. Blank ya puede usar tu pieza física.",
                        statusText: sessionStore.nfcTagUid == nil ? nil : "NFC listo",
                        primaryTitle: sessionStore.nfcTagUid == nil ? "Escanear mi Blank" : "Hacer mi primer Blank",
                        secondaryTitle: nil,
                        primaryAction: scanOrFinish
                    )
                default:
                    EmptyView()
                }
            }

            if let message {
                Text(message)
                    .font(.blankInter(size: 13, relativeTo: .footnote))
                    .foregroundStyle(BlankColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.top, 18)
            }

            #if DEBUG
            #if targetEnvironment(simulator)
            Button("Entrar al Home en simulador") {
                enterSimulatorHome()
            }
            .buttonStyle(BlankSecondaryButtonStyle())
            .frame(width: onboardingButtonWidth(for: "Entrar al Home en simulador"))
            .padding(.top, message == nil ? 18 : 10)
            #endif
            #endif

            Spacer(minLength: 48)
            stepIndicator
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 42)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(BlankColors.ink)
        .familyActivityPicker(isPresented: $showingPicker, selection: $sessionStore.selection)
        .task {
            await refreshScreenTimeAndContinueIfApproved()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            Task {
                await refreshScreenTimeAndContinueIfApproved()
            }
        }
        .onChange(of: sessionStore.selection) { newSelection in
            screenTimeBlocker.updateSelection(newSelection, isBlankActive: sessionStore.isBlankActive)
        }
    }

    private var header: some View {
        HStack {
            Text("Blank")
                .font(.blankInter(size: 17, weight: .medium, relativeTo: .headline))
            Spacer()
            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index == currentStep ? BlankColors.ink : BlankColors.line)
                        .frame(width: index == currentStep ? 22 : 8, height: 8)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .blankGlassCard(cornerRadius: 24, tintOpacity: 0.22)
    }

    private var screenTimeDescription: String {
        if screenTimeBlocker.authorizationStatus == .approved {
            return "Screen Time está autorizado. Blank ya puede proteger las apps que elijas."
        }
        return "Blank necesita acceso a Screen Time para proteger las apps que elijas."
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index <= currentStep ? BlankColors.ink : BlankColors.line)
                    .frame(width: index == currentStep ? 22 : 8, height: 8)
            }
        }
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
        VStack(spacing: 14) {
            Text(eyebrow)
                .font(.blankInter(size: 15, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(BlankColors.mutedInk)
            Text(title)
                .font(.blankInter(size: 32.4, weight: .medium, relativeTo: .largeTitle))
                .multilineTextAlignment(.center)
                .lineSpacing(-2)
                .lineLimit(3)
                .minimumScaleFactor(0.78)
            Text(body)
                .font(.blankInter(size: 16, relativeTo: .body))
                .foregroundStyle(BlankColors.mutedInk)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 340)
                .padding(.top, 2)
            if let statusText {
                StatusPill(text: statusText)
                    .padding(.top, 10)
            }
            Button(primaryTitle, action: primaryAction)
                .buttonStyle(BlankPrimaryButtonStyle())
                .frame(width: onboardingButtonWidth(for: primaryTitle))
                .padding(.top, 14)

            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(BlankSecondaryButtonStyle())
                    .frame(width: onboardingButtonWidth(for: secondaryTitle))
            }
        }
    }

    private func StatusPill(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.blankInter(size: 13, weight: .semibold, relativeTo: .caption))
            Text(text)
                .font(.blankInter(size: 15, weight: .semibold, relativeTo: .subheadline))
        }
        .foregroundStyle(BlankColors.ink)
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background {
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(Color.white.opacity(0.34))
                Capsule().stroke(BlankColors.glassBorder, lineWidth: 1)
            }
        }
    }

    private func authorizeScreenTime() {
        if screenTimeBlocker.authorizationStatus == .approved {
            currentStep = 1
            message = nil
            return
        }

        Task {
            if await screenTimeBlocker.requestAuthorization() {
                currentStep = 1
                message = nil
            } else {
                let status = "Estado iOS: \(screenTimeBlocker.authorizationStatusLabel)."
                if let lastErrorMessage = screenTimeBlocker.lastErrorMessage {
                    message = "\(lastErrorMessage) \(status)"
                } else {
                    message = "Screen Time no ha quedado autorizado. \(status)"
                }
            }
        }
    }

    private func refreshScreenTimeAndContinueIfApproved() async {
        await screenTimeBlocker.refreshAuthorizationStatusUntilSettled()
        if screenTimeBlocker.authorizationStatus == .approved, currentStep == 0 {
            currentStep = 1
            message = nil
        }
    }

    private func selectAppsOrContinue() {
        if sessionStore.hasSelectedApps {
            currentStep = 2
        } else {
            showingPicker = true
        }
    }

    private func scanOrFinish() {
        if sessionStore.nfcTagUid != nil {
            screenTimeBlocker.updateSelection(sessionStore.selection, isBlankActive: sessionStore.isBlankActive)
            sessionStore.finishSetup()
            return
        }

        nfcReader.scan { result in
            Task { @MainActor in
                switch result {
                case .success(let uid):
                    _ = sessionStore.handleNfcTag(uid: uid)
                    message = "NFC registrado."
                case .failure(let error):
                    message = error.localizedDescription
                }
            }
        }
    }

    #if DEBUG
    #if targetEnvironment(simulator)
    private func enterSimulatorHome() {
        sessionStore.nfcTagUid = "simulator-nfc-tag"
        screenTimeBlocker.updateSelection(sessionStore.selection, isBlankActive: sessionStore.isBlankActive)
        sessionStore.finishSetup()
    }
    #endif
    #endif

    private func onboardingButtonWidth(for title: String) -> CGFloat {
        let estimated = CGFloat(title.count) * 8.6 + 64
        return min(max(estimated, 184), 260)
    }
}
