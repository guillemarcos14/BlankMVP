import FamilyControls
import Foundation
import ManagedSettings

@MainActor
final class ScreenTimeBlocker: ObservableObject {
    @Published private(set) var authorizationStatus = AuthorizationCenter.shared.authorizationStatus
    @Published var lastErrorMessage: String?

    private let store = ManagedSettingsStore()
    private var selection = FamilyActivitySelection()
    #if DEBUG
    private var usesPreviewAuthorizationStatus = false
    #endif

    var authorizationStatusLabel: String {
        switch authorizationStatus {
        case .notDetermined:
            return "notDetermined"
        case .denied:
            return "denied"
        case .approved:
            return "approved"
        @unknown default:
            return "unknown"
        }
    }

    func refreshAuthorizationStatus() {
        #if DEBUG
        guard !usesPreviewAuthorizationStatus else { return }
        #endif
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        #if DEBUG
        if usesPreviewAuthorizationStatus {
            return authorizationStatus == .approved
        }
        #endif
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            await refreshAuthorizationStatusUntilSettled()
            lastErrorMessage = nil
            return authorizationStatus == .approved
        } catch {
            await refreshAuthorizationStatusUntilSettled()
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    func refreshAuthorizationStatusUntilSettled() async {
        for _ in 0..<10 {
            refreshAuthorizationStatus()
            if authorizationStatus == .approved {
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        refreshAuthorizationStatus()
    }

    func restore(selection: FamilyActivitySelection) async {
        self.selection = selection
    }

    func updateSelection(_ selection: FamilyActivitySelection, isBlankActive: Bool) {
        self.selection = selection
        apply(isBlankActive: isBlankActive)
    }

    func apply(isBlankActive: Bool) {
        guard isBlankActive else {
            clear()
            return
        }

        store.shield.applications = selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens
    }

    func clear() {
        store.clearAllSettings()
    }
}

#if DEBUG
extension ScreenTimeBlocker {
    static func preview(authorizationApproved: Bool = true) -> ScreenTimeBlocker {
        let blocker = ScreenTimeBlocker()
        blocker.usesPreviewAuthorizationStatus = true
        blocker.authorizationStatus = authorizationApproved ? .approved : .notDetermined
        return blocker
    }
}
#endif
