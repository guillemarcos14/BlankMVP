import SwiftUI

enum BlankColors {
    static let red = Color(red: 0.827, green: 0.184, blue: 0.184)
    static let redDark = Color(red: 0.125, green: 0.129, blue: 0.141)
    static let green = Color(red: 0.125, green: 0.129, blue: 0.141)
    static let background = Color(red: 0.914, green: 0.914, blue: 0.906)
    static let surface = Color(red: 0.961, green: 0.961, blue: 0.961)
    static let text = Color.white
    static let secondaryText = Color.white.opacity(0.70)
    static let warmBackground = Color(red: 0.914, green: 0.914, blue: 0.906)
    static let warmSurface = Color.white.opacity(0.72)
    static let ink = Color(red: 0.125, green: 0.129, blue: 0.141)
    static let mutedInk = Color(red: 0.400, green: 0.408, blue: 0.400)
    static let line = Color(red: 0.125, green: 0.129, blue: 0.141).opacity(0.10)
}

extension Font {
    static func blankSerif(size: CGFloat, relativeTo textStyle: TextStyle = .title) -> Font {
        .custom("Instrument Serif", size: size, relativeTo: textStyle)
    }

    static func blankInter(size: CGFloat, weight: Weight = .regular, relativeTo textStyle: TextStyle = .body) -> Font {
        .custom("Inter", size: size, relativeTo: textStyle).weight(weight)
    }

    static var blankBody: Font {
        .blankInter(size: 16)
    }
}

struct BlankPrimaryButtonStyle: ButtonStyle {
    var light: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.blankInter(size: 16, weight: .semibold, relativeTo: .headline))
            .frame(maxWidth: 342)
            .frame(height: 48)
            .background(light ? Color.white : BlankColors.ink)
            .foregroundStyle(light ? BlankColors.ink : Color.white)
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.03 : 0.08), radius: 10, y: 5)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct BlankSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.blankInter(size: 16, weight: .semibold, relativeTo: .headline))
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .foregroundStyle(BlankColors.ink)
            .overlay(Capsule().stroke(BlankColors.ink.opacity(0.35), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}
