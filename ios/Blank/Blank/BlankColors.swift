import SwiftUI
import UIKit

enum BlankColors {
    static let red = Color(uiColor: .systemRed)
    static let redDark = Color(red: 0.125, green: 0.129, blue: 0.141)
    static let green = Color(red: 0.125, green: 0.129, blue: 0.141)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let text = Color.white
    static let secondaryText = Color(uiColor: .secondaryLabel)
    static let warmBackground = Color(uiColor: .systemGroupedBackground)
    static let warmSurface = Color(uiColor: .secondarySystemGroupedBackground).opacity(0.78)
    static let ink = Color(uiColor: .label)
    static let mutedInk = Color(uiColor: .secondaryLabel)
    static let tertiaryInk = Color(uiColor: .tertiaryLabel)
    static let line = Color(uiColor: .separator).opacity(0.34)
    static let airBlue = Color(uiColor: .systemBlue)
    static let airMist = Color(uiColor: .systemTeal)
    static let airStone = Color(uiColor: .systemGray3)
    static let glassTint = Color(uiColor: .secondarySystemFill)
    static let controlFill = Color(uiColor: .systemFill)
    static let elevatedSurface = Color(uiColor: .tertiarySystemGroupedBackground)
    static let glassBorder = LinearGradient(
        colors: [
            Color.white.opacity(0.48),
            Color.white.opacity(0.18),
            Color(uiColor: .separator).opacity(0.12),
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
            .font(.blankInter(size: 16, weight: .semibold, relativeTo: .headline))
            .frame(maxWidth: 342)
            .frame(minHeight: 50)
            .foregroundStyle(light ? BlankColors.ink : Color.white)
            .background {
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(light ? Color.white.opacity(configuration.isPressed ? 0.72 : 0.88) : BlankColors.glassTint.opacity(configuration.isPressed ? 0.66 : 0.54))
                    BlankGlassCornerHighlight(width: 92, height: 34, xOffset: -122, yOffset: -17)
                        .clipShape(Capsule())
                    Capsule().stroke(BlankColors.glassBorder, lineWidth: 1)
                }
                .allowsHitTesting(false)
            }
            .contentShape(Capsule())
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.02 : 0.07), radius: 9, y: 5)
            .scaleEffect(configuration.isPressed ? 0.982 : 1)
    }
}

struct BlankSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.blankInter(size: 16, weight: .semibold, relativeTo: .headline))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .foregroundStyle(BlankColors.ink)
            .background {
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.54 : 0.42))
                    Capsule().stroke(BlankColors.glassBorder, lineWidth: 1)
                }
                .allowsHitTesting(false)
            }
            .contentShape(Capsule())
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.01 : 0.045), radius: 7, y: 4)
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
                    BlankColors.airBlue.opacity(dimmed ? 0.08 : 0.16),
                    BlankColors.airStone.opacity(dimmed ? 0.08 : 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    Color.black.opacity(dimmed ? 0.20 : 0.05),
                    Color.black.opacity(dimmed ? 0.12 : 0.00),
                    Color.black.opacity(dimmed ? 0.28 : 0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
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
    func blankGlassCard(cornerRadius: CGFloat = 18, tintOpacity: Double = 0.34) -> some View {
        modifier(BlankGlassCardModifier(cornerRadius: cornerRadius, tintOpacity: tintOpacity))
    }
}

struct TopSheetHeader: View {
    let title: String
    let subtitle: String
    var titleColor: Color = BlankColors.ink
    var subtitleColor: Color = BlankColors.mutedInk

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.blankInter(size: 34, weight: .semibold, relativeTo: .largeTitle))
                .foregroundStyle(titleColor)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.86)

            Text(subtitle)
                .font(.blankInter(size: 16, relativeTo: .body))
                .foregroundStyle(subtitleColor)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 330)
        }
        .frame(maxWidth: .infinity)
    }
}

struct TopSheetPrimaryButtonLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.blankInter(size: 16, weight: .medium, relativeTo: .headline))
            .foregroundStyle(BlankColors.ink)
            .padding(.horizontal, 26)
            .frame(height: 46)
            .background {
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(Color.white.opacity(0.34))
                    BlankGlassCornerHighlight(width: 74, height: 28, xOffset: -44, yOffset: -15)
                        .clipShape(Capsule())
                }
                .allowsHitTesting(false)
            }
            .overlay {
                Capsule().stroke(BlankColors.glassBorder, lineWidth: 1)
            }
            .shadow(color: BlankColors.ink.opacity(0.045), radius: 12, x: 0, y: 7)
    }
}
