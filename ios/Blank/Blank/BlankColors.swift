import SwiftUI

enum BlankColors {
    static let red = Color(red: 0.827, green: 0.184, blue: 0.184)
    static let redDark = Color(red: 0.125, green: 0.129, blue: 0.141)
    static let green = Color(red: 0.125, green: 0.129, blue: 0.141)
    static let background = Color(red: 0.914, green: 0.914, blue: 0.906)
    static let surface = Color(red: 0.961, green: 0.961, blue: 0.961)
    static let text = Color.white
    static let secondaryText = Color(red: 0.400, green: 0.408, blue: 0.400)
    static let warmBackground = Color(red: 0.914, green: 0.914, blue: 0.906)
    static let warmSurface = Color.white.opacity(0.72)
    static let ink = Color(red: 0.125, green: 0.129, blue: 0.141)
    static let mutedInk = Color(red: 0.400, green: 0.408, blue: 0.400)
    static let line = Color(red: 0.125, green: 0.129, blue: 0.141).opacity(0.10)
    static let airBlue = Color(red: 0.573, green: 0.690, blue: 0.800)
    static let airMist = Color(red: 0.784, green: 0.814, blue: 0.846)
    static let airStone = Color(red: 0.769, green: 0.765, blue: 0.757)
    static let glassTint = Color(red: 0.722, green: 0.725, blue: 0.733)
    static let glassBorder = LinearGradient(
        colors: [
            Color.white.opacity(0.48),
            Color.white.opacity(0.16),
            Color.white.opacity(0.04),
            Color.white.opacity(0.00)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
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
            .font(.blankInter(size: 16, weight: .medium, relativeTo: .headline))
            .frame(maxWidth: 342)
            .frame(height: 50)
            .foregroundStyle(light ? BlankColors.ink : Color.white)
            .background {
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(light ? Color.white.opacity(0.56) : BlankColors.glassTint.opacity(configuration.isPressed ? 0.58 : 0.48))
                    BlankGlassCornerHighlight(width: 92, height: 34, xOffset: -122, yOffset: -17)
                        .clipShape(Capsule())
                    Capsule().stroke(BlankColors.glassBorder, lineWidth: 1)
                }
                .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.02 : 0.05), radius: 5, y: 3)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct BlankSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.blankInter(size: 16, weight: .medium, relativeTo: .headline))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(BlankColors.ink)
            .background {
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.42 : 0.30))
                    Capsule().stroke(BlankColors.glassBorder, lineWidth: 1)
                }
                .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.01 : 0.035), radius: 5, y: 3)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct BlankAtmosphericBackground: View {
    var dimmed: Bool = false

    var body: some View {
        ZStack {
            Image(dimmed ? "blank_home_background_active" : "blank_home_background_idle")
                .resizable()
                .scaledToFill()
                .opacity(dimmed ? 1 : 0.94)

            LinearGradient(
                colors: [
                    Color.white.opacity(dimmed ? 0.02 : 0.14),
                    BlankColors.airMist.opacity(dimmed ? 0.10 : 0.20),
                    BlankColors.airStone.opacity(dimmed ? 0.06 : 0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

struct BlankGlassCornerHighlight: View {
    let width: CGFloat
    let height: CGFloat
    let xOffset: CGFloat
    let yOffset: CGFloat

    var body: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.24),
                        Color.white.opacity(0.08),
                        Color.white.opacity(0.00)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: max(width, height) / 2
                )
            )
            .frame(width: width, height: height)
            .offset(x: xOffset, y: yOffset)
    }
}

private struct BlankGlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tintOpacity: Double

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(tintOpacity))
                    BlankGlassCornerHighlight(width: 104, height: 40, xOffset: -112, yOffset: -22)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
                .allowsHitTesting(false)
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(BlankColors.glassBorder, lineWidth: 1)
            )
            .shadow(color: BlankColors.ink.opacity(0.045), radius: 14, x: 0, y: 8)
    }
}

extension View {
    func blankGlassCard(cornerRadius: CGFloat = 22, tintOpacity: Double = 0.34) -> some View {
        modifier(BlankGlassCardModifier(cornerRadius: cornerRadius, tintOpacity: tintOpacity))
    }
}
