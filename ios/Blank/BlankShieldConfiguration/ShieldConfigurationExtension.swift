import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration(appName: application.localizedDisplayName ?? "This app")
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration(appName: application.localizedDisplayName ?? "This app")
    }

    private func makeConfiguration(appName: String) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 0.05, green: 0.06, blue: 0.06, alpha: 0.92),
            icon: nil,
            title: ShieldConfiguration.Label(
                text: "\(appName) is Blanked",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "\(appName) is now blocked.\nYou're doing a great job.",
                color: UIColor(white: 0.72, alpha: 1.0)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Continue focus",
                color: UIColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1.0)
            ),
            primaryButtonBackgroundColor: .white
        )
    }
}
