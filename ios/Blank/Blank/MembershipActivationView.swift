import SwiftUI

struct MembershipActivationView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var membershipStore: MembershipStore
    @EnvironmentObject private var screenTimeBlocker: ScreenTimeBlocker
    @State private var code = ""

    var body: some View {
        ZStack {
            BlankAtmosphericBackground()

            VStack(spacing: 0) {
                Spacer(minLength: 96)

                VStack(spacing: 14) {
                    Text("Activate your membership.")
                        .font(.blankInter(size: 32.4, weight: .medium, relativeTo: .largeTitle))
                        .foregroundStyle(BlankColors.ink)
                        .multilineTextAlignment(.center)
                        .lineSpacing(-2)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text("Enter the code you received when activating your Blank plan.")
                        .font(.blankInter(size: 16, relativeTo: .body))
                        .foregroundStyle(BlankColors.mutedInk)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .frame(maxWidth: 330)
                        .padding(.top, 2)

                    TextField("BLANK-XXXX", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.blankInter(size: 18, weight: .medium, relativeTo: .body))
                        .foregroundStyle(BlankColors.ink)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                        .frame(height: 54)
                        .blankGlassCard(cornerRadius: 20, tintOpacity: 0.38)
                        .padding(.top, 18)
                        .frame(maxWidth: 314)

                    Button {
                        Task {
                            await membershipStore.redeem(code: code)
                        }
                    } label: {
                        if membershipStore.isChecking {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Activate Blank")
                        }
                    }
                    .buttonStyle(BlankPrimaryButtonStyle())
                    .frame(width: 214)
                    .disabled(membershipStore.isChecking)
                    .padding(.top, 14)

                    #if DEBUG
                    #if targetEnvironment(simulator)
                    Button("Enter Home in simulator") {
                        enterSimulatorHome()
                    }
                    .buttonStyle(BlankSecondaryButtonStyle())
                    .frame(width: 260)
                    .padding(.top, 2)
                    #endif
                    #endif

                    if let message = membershipStore.message {
                        Text(message)
                            .font(.blankInter(size: 13, relativeTo: .footnote))
                            .foregroundStyle(BlankColors.secondaryText)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                            .frame(maxWidth: 320)
                            .padding(.top, 10)
                    }

                    if membershipStore.status != .locked {
                        Text(membershipStore.accessLabel)
                            .font(.blankInter(size: 13, weight: .semibold, relativeTo: .caption))
                            .foregroundStyle(BlankColors.mutedInk)
                            .padding(.top, 4)
                    }
                }

                Spacer(minLength: 48)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 42)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    #if DEBUG
    #if targetEnvironment(simulator)
    private func enterSimulatorHome() {
        membershipStore.grantSimulatorAccess()
        sessionStore.nfcTagUid = "simulator-nfc-tag"
        screenTimeBlocker.updateSelection(sessionStore.selection, isBlankActive: sessionStore.isBlankActive)
        sessionStore.finishSetup()
    }
    #endif
    #endif
}
