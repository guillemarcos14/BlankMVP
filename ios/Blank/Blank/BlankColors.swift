import SwiftUI

private struct BlankMinimalAppearanceKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var blankMinimalAppearance: Bool {
        get { self[BlankMinimalAppearanceKey.self] }
        set { self[BlankMinimalAppearanceKey.self] = newValue }
    }
}

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
    static let premiumBlue = Color(red: 0.20, green: 0.47, blue: 0.92)
    static let controlSurface = Color.white.opacity(0.16)
    static let activeControlSurface = Color.white.opacity(0.09)
    static let minimalBackground = Color(red: 0.953, green: 0.953, blue: 0.937)
    static let minimalInk = Color(red: 0.115, green: 0.118, blue: 0.115)
    static let minimalSecondary = Color(red: 0.390, green: 0.395, blue: 0.390)
    static let minimalFaded = Color(red: 0.730, green: 0.732, blue: 0.716)
    static let newLookDarkBackground = Color(red: 0.105, green: 0.105, blue: 0.115)
    static let newLookDarkSecondary = Color(red: 0.290, green: 0.290, blue: 0.305)
    static let newLookRule = Color(red: 0.115, green: 0.118, blue: 0.115).opacity(0.12)
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
    @Environment(\.blankMinimalAppearance) private var minimalAppearance

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.blankInter(size: 16, weight: .medium, relativeTo: .headline))
            .frame(maxWidth: 342)
            .frame(height: minimalAppearance ? 52 : 50)
            .foregroundStyle(light ? BlankColors.ink : Color.white)
            .background {
                ZStack {
                    if minimalAppearance {
                        Rectangle()
                            .fill(light ? BlankColors.minimalInk.opacity(configuration.isPressed ? 0.78 : 1) : Color.white.opacity(configuration.isPressed ? 0.72 : 0.94))
                    } else {
                        Capsule().fill(.ultraThinMaterial)
                        Capsule().fill(light ? Color.white.opacity(0.56) : BlankColors.glassTint.opacity(configuration.isPressed ? 0.58 : 0.48))
                        BlankGlassCornerHighlight(width: 92, height: 34, xOffset: -122, yOffset: -17)
                            .clipShape(Capsule())
                        Capsule().stroke(BlankColors.glassBorder, lineWidth: 1)
                    }
                }
                .allowsHitTesting(false)
            }
            .shadow(color: minimalAppearance ? .clear : Color.black.opacity(configuration.isPressed ? 0.02 : 0.05), radius: 5, y: 3)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct BlankSecondaryButtonStyle: ButtonStyle {
    @Environment(\.blankMinimalAppearance) private var minimalAppearance

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.blankInter(size: 16, weight: .medium, relativeTo: .headline))
            .frame(maxWidth: .infinity)
            .frame(height: minimalAppearance ? 52 : 48)
            .foregroundStyle(BlankColors.ink)
            .background {
                ZStack {
                    if minimalAppearance {
                        Rectangle()
                            .fill(BlankColors.minimalInk.opacity(configuration.isPressed ? 0.08 : 0.04))
                    } else {
                        Capsule().fill(.ultraThinMaterial)
                        Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.42 : 0.30))
                        Capsule().stroke(BlankColors.glassBorder, lineWidth: 1)
                    }
                }
                .allowsHitTesting(false)
            }
            .shadow(color: minimalAppearance ? .clear : Color.black.opacity(configuration.isPressed ? 0.01 : 0.035), radius: 5, y: 3)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct BlankAtmosphericBackground: View {
    var dimmed: Bool = false
    @Environment(\.blankMinimalAppearance) private var minimalAppearance

    var body: some View {
        ZStack {
            if minimalAppearance {
                (dimmed ? BlankColors.newLookDarkBackground : BlankColors.minimalBackground)
            } else {
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
    @Environment(\.blankMinimalAppearance) private var minimalAppearance

    func body(content: Content) -> some View {
        content
            .background {
                if minimalAppearance {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.clear)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(tintOpacity))
                        BlankGlassCornerHighlight(width: 104, height: 40, xOffset: -112, yOffset: -22)
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(minimalAppearance ? Color.clear : Color.white.opacity(0.20), lineWidth: minimalAppearance ? 0 : 1)
            )
            .shadow(color: minimalAppearance ? .clear : BlankColors.ink.opacity(0.045), radius: 14, x: 0, y: 8)
    }
}

private struct BlankControlSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tintOpacity: Double
    let emphasized: Bool
    @Environment(\.blankMinimalAppearance) private var minimalAppearance

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(minimalAppearance ? Color.clear : Color.white.opacity(tintOpacity))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        minimalAppearance ? Color.clear : Color.white.opacity(emphasized ? 0.34 : 0.18),
                        lineWidth: minimalAppearance ? 0 : 0.8
                    )
            }
            .shadow(
                color: minimalAppearance ? .clear : BlankColors.ink.opacity(emphasized ? 0.05 : 0.025),
                radius: emphasized ? 18 : 10,
                x: 0,
                y: emphasized ? 10 : 5
            )
    }
}

extension View {
    func blankGlassCard(cornerRadius: CGFloat = 22, tintOpacity: Double = 0.34) -> some View {
        modifier(BlankGlassCardModifier(cornerRadius: cornerRadius, tintOpacity: tintOpacity))
    }

    func blankControlSurface(cornerRadius: CGFloat = 18, tintOpacity: Double = 0.12, emphasized: Bool = false) -> some View {
        modifier(BlankControlSurfaceModifier(cornerRadius: cornerRadius, tintOpacity: tintOpacity, emphasized: emphasized))
    }
}

struct TopSheetHeader: View {
    @Environment(\.blankMinimalAppearance) private var minimalAppearance
    let title: String
    let subtitle: String
    var titleColor: Color = BlankColors.ink
    var subtitleColor: Color = BlankColors.mutedInk

    var body: some View {
        VStack(alignment: minimalAppearance ? .leading : .center, spacing: minimalAppearance ? 5 : 10) {
            Text(minimalAppearance ? title.lowercased() : title)
                .font(.blankInter(
                    size: minimalAppearance ? 40 : 34,
                    weight: minimalAppearance ? .bold : .medium,
                    relativeTo: .largeTitle
                ))
                .foregroundStyle(titleColor)
                .tracking(minimalAppearance ? -0.6 : 0)
                .multilineTextAlignment(minimalAppearance ? .leading : .center)
                .lineLimit(1)
                .minimumScaleFactor(0.86)

            Text(minimalAppearance ? subtitle.lowercased() : subtitle)
                .font(minimalAppearance ? .blankInter(size: 13, weight: .medium, relativeTo: .caption) : .body)
                .foregroundStyle(subtitleColor)
                .multilineTextAlignment(minimalAppearance ? .leading : .center)
                .lineSpacing(minimalAppearance ? 0 : 2)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 330)
        }
        .frame(maxWidth: .infinity, alignment: minimalAppearance ? .leading : .center)
    }
}

struct TopSheetPrimaryButtonLabel: View {
    @Environment(\.blankMinimalAppearance) private var minimalAppearance
    let title: String

    var body: some View {
        Text(title)
            .font(.blankInter(size: 16, weight: .medium, relativeTo: .headline))
            .foregroundStyle(minimalAppearance ? BlankColors.minimalInk : BlankColors.ink)
            .padding(.horizontal, 26)
            .frame(height: minimalAppearance ? 52 : 46)
            .background {
                ZStack {
                    if minimalAppearance {
                        Rectangle().fill(BlankColors.minimalInk.opacity(0.08))
                    } else {
                        Capsule().fill(.ultraThinMaterial)
                        Capsule().fill(Color.white.opacity(0.34))
                        BlankGlassCornerHighlight(width: 74, height: 28, xOffset: -44, yOffset: -15)
                            .clipShape(Capsule())
                    }
                }
                .allowsHitTesting(false)
            }
            .overlay {
                if !minimalAppearance {
                    Capsule().stroke(BlankColors.glassBorder, lineWidth: 1)
                }
            }
            .shadow(color: minimalAppearance ? .clear : BlankColors.ink.opacity(0.045), radius: 12, x: 0, y: 7)
    }
}
