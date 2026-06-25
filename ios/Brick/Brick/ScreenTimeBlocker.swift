import FamilyControls
import Foundation
import ManagedSettings

@MainActor
final class ScreenTimeBlocker: ObservableObject {
    @Published private(set) var authorizationStatus = AuthorizationCenter.shared.authorizationStatus
    @Published var lastErrorMessage: String?

    private let store = ManagedSettingsStore()
    private var selection = FamilyActivitySelection()

    func requestAuthorization() async -> Bool {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            authorizationStatus = AuthorizationCenter.shared.authorizationStatus
            lastErrorMessage = nil
            return authorizationStatus == .approved
        } catch {
            authorizationStatus = AuthorizationCenter.shared.authorizationStatus
            lastErrorMessage = error.localizedDescription
            return false
        }
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
