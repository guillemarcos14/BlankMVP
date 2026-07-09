import SwiftUI

enum BrickColors {
    static let red = Color(red: 0.827, green: 0.184, blue: 0.184)
    static let redDark = Color(red: 0.718, green: 0.110, blue: 0.110)
    static let green = Color(red: 0.220, green: 0.557, blue: 0.235)
    static let background = Color(red: 0.071, green: 0.071, blue: 0.071)
    static let surface = Color(red: 0.118, green: 0.118, blue: 0.118)
    static let text = Color.white
    static let secondaryText = Color.white.opacity(0.70)
    static let warmBackground = Color(red: 0.906, green: 0.902, blue: 0.878)
    static let warmSurface = Color.white.opacity(0.72)
    static let ink = Color(red: 0.100, green: 0.098, blue: 0.090)
    static let mutedInk = Color(red: 0.365, green: 0.357, blue: 0.325)
    static let line = Color(red: 0.741, green: 0.733, blue: 0.690)
}

struct BlankPrimaryButtonStyle: ButtonStyle {
    var light: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(light ? Color.white : BrickColors.ink)
            .foregroundStyle(light ? BrickColors.ink : Color.white)
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.03 : 0.08), radius: 10, y: 5)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct BlankSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .foregroundStyle(BrickColors.ink)
            .overlay(Capsule().stroke(BrickColors.ink.opacity(0.35), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}
