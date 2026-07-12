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
                        primaryTitle: screenTimeBlocker.authorizationStatus == .approved ? "Continuar" : "Autorizar Screen Time",
                        secondaryTitle: nil,
                        primaryAction: authorizeScreenTime
                    )
                case 1:
                    stepContent(
                        eyebrow: "Paso 2 de 3",
                        title: "Elige que quieres dejar fuera.",
                        body: sessionStore.hasSelectedApps
                            ? "\(sessionStore.selectionCount) selecciones protegidas en \(sessionStore.currentMode.name)."
                            : "Selecciona apps, categorias o dominios. En iOS Apple entrega tokens privados, no nombres de paquetes.",
                        primaryTitle: sessionStore.hasSelectedApps ? "Continuar" : "Seleccionar apps",
                        secondaryTitle: sessionStore.hasSelectedApps ? "Editar seleccion" : nil,
                        primaryAction: selectAppsOrContinue,
                        secondaryAction: { showingPicker = true }
                    )
                case 2:
                    stepContent(
                        eyebrow: "Paso 3 de 3",
                        title: "Vincula tu pieza fisica.",
                        body: sessionStore.nfcTagUid == nil
                            ? "Escanea el NFC que activara y desactivara Blank en este iPhone."
                            : "NFC registrado. Blank ya puede usar tu pieza fisica.",
                        primaryTitle: sessionStore.nfcTagUid == nil ? "Escanear NFC" : "Entrar en Blank",
                        secondaryTitle: nil,
                        primaryAction: scanOrFinish
                    )
                default:
                    EmptyView()
                }
            }

            if let message {
                Text(message)
                    .font(.footnote)
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
            .padding(.top, message == nil ? 18 : 10)
            #endif
            #endif

            Spacer(minLength: 48)
            stepIndicator
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 42)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BlankColors.warmBackground)
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
                .font(.headline)
            Spacer()
            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index == currentStep ? BlankColors.ink : BlankColors.line)
                        .frame(width: index == currentStep ? 22 : 8, height: 8)
                }
            }
        }
    }

    private var screenTimeDescription: String {
        if screenTimeBlocker.authorizationStatus == .approved {
            return "Screen Time esta autorizado. Blank usara FamilyControls y ManagedSettings, el equivalente permitido por Apple."
        }
        return "Blank necesita acceso a Screen Time para proteger las apps que elijas. Esto sustituye al servicio de Accesibilidad de Android."
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
        primaryTitle: String,
        secondaryTitle: String?,
        primaryAction: @escaping () -> Void,
        secondaryAction: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 14) {
            Text(eyebrow)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BlankColors.mutedInk)
            Text(title)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
            Text(body)
                .font(.body)
                .foregroundStyle(BlankColors.mutedInk)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 340)
                .padding(.top, 2)
            Button(primaryTitle, action: primaryAction)
                .buttonStyle(BlankPrimaryButtonStyle())
                .padding(.top, 14)

            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(BlankSecondaryButtonStyle())
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
}
