import AppIntents
import FamilyControls
import ManagedSettings
import SwiftUI
import WidgetKit

struct StartQuickBlockIntent: AppIntent {
    static var title: LocalizedStringResource = "Iniciar Blank"
    static var description = IntentDescription("Inicia un bloqueo rapido con la configuracion actual de Blank.")

    func perform() async throws -> some IntentResult {
        let defaults = BlankSharedState.defaults
        guard BlankSharedState.startQuickBlock(defaults: defaults) else {
            return .result()
        }

        if let selection = BlankSharedState.loadSelection(from: defaults) {
            let store = ManagedSettingsStore()
            store.shield.applications = selection.applicationTokens
            store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
            store.shield.webDomains = selection.webDomainTokens
        }

        WidgetCenter.shared.reloadTimelines(ofKind: "BlankQuickBlockWidget")
        return .result()
    }
}

struct BlankWidgetEntry: TimelineEntry {
    let date: Date
    let activeState: BlankSharedState.ActiveState
    let hasConfiguration: Bool
}

struct BlankWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BlankWidgetEntry {
        BlankWidgetEntry(
            date: Date(),
            activeState: BlankSharedState.ActiveState(
                isActive: false,
                startedAt: nil,
                endsAt: nil,
                totalMinutes: BlankSharedState.quickBlockDurationMinutes
            ),
            hasConfiguration: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (BlankWidgetEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BlankWidgetEntry>) -> Void) {
        let current = entry()
        let nextRefresh = current.activeState.endsAt ?? Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [current], policy: .after(nextRefresh)))
    }

    private func entry(date: Date = Date()) -> BlankWidgetEntry {
        let defaults = BlankSharedState.defaults
        if BlankSharedState.finishExpiredBlock(defaults: defaults, now: date) {
            ManagedSettingsStore().clearAllSettings()
        }
        return BlankWidgetEntry(
            date: date,
            activeState: BlankSharedState.loadActiveState(now: date, defaults: defaults),
            hasConfiguration: BlankSharedState.hasConfiguredBlock(in: defaults)
        )
    }
}

struct BlankWidgetView: View {
    let entry: BlankWidgetEntry
    private var isActive: Bool { entry.activeState.isActive }
    private var foregroundColor: Color { isActive ? Color.white.opacity(0.96) : Color(red: 0.14, green: 0.14, blue: 0.13) }
    private var secondaryForegroundColor: Color { isActive ? Color.white.opacity(0.76) : Color.black.opacity(0.62) }
    private var widgetURL: URL? {
        URL(string: isActive ? "blank://scan-blank" : "blank://configure-block")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Blank")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(secondaryForegroundColor)
                .padding(.top, 1)
                .padding(.leading, 1)

            Spacer(minLength: isActive ? 6 : 10)

            VStack(spacing: isActive ? 8 : 11) {
                actionCircle

                Text(title)
                    .font(.system(size: isActive ? 14.5 : 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(foregroundColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
            }
            .frame(maxWidth: .infinity)
            .offset(y: isActive ? -1 : -3)

            Spacer(minLength: isActive ? 12 : 15)
        }
        .padding(16)
        .blankWidgetBackground(isActive: entry.activeState.isActive)
        .widgetURL(widgetURL)
    }

    @ViewBuilder
    private var actionCircle: some View {
        if entry.activeState.isActive {
            progressCircle
        } else if entry.hasConfiguration {
            if #available(iOSApplicationExtension 17.0, *) {
                Button(intent: StartQuickBlockIntent()) {
                    idleCircle
                }
                .buttonStyle(.plain)
            } else {
                Link(destination: URL(string: "blank://configure-block")!) {
                    idleCircle
                }
            }
        } else {
            Link(destination: URL(string: "blank://configure-block")!) {
                idleCircle
            }
        }
    }

    private var idleCircle: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.20, green: 0.20, blue: 0.18),
                            Color(red: 0.035, green: 0.04, blue: 0.035)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Circle()
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
                .padding(-1)

            Circle()
                .fill(Color.white.opacity(0.13))
                .frame(width: 46, height: 20)
                .blur(radius: 12)
                .offset(y: -19)

            Circle()
                .fill(Color.black.opacity(0.24))
                .frame(width: 52, height: 20)
                .blur(radius: 12)
                .offset(y: 22)
        }
        .frame(width: 70, height: 70)
        .overlay(alignment: .bottom) {
            Capsule()
                .fill(Color.white.opacity(0.10))
                .frame(width: 22, height: 3)
                .offset(y: -8)
            }
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 7)
        .contentShape(Circle())
    }

    private var progressCircle: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.035))
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 3)
            Circle()
                .trim(from: 0, to: entry.activeState.progress(now: entry.date))
                .stroke(Color.white.opacity(0.94), style: StrokeStyle(lineWidth: 3, lineCap: .butt))
                .rotationEffect(.degrees(-90))

            Text("\(entry.activeState.remainingMinutes(now: entry.date) ?? 0)")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.92))
                .monospacedDigit()
        }
        .frame(width: 72, height: 72)
    }

    private var title: String {
        guard entry.activeState.isActive else { return "Bloquear" }
        let minutes = entry.activeState.remainingMinutes(now: entry.date) ?? 0
        return "Activo \(minutes)m"
    }
}

private struct BlankWidgetGlassBackground: View {
    var isActive = false

    var body: some View {
        ZStack {
            baseFill

            LinearGradient(
                colors: [
                    isActive ? Color.white.opacity(0.10) : Color.white.opacity(0.52),
                    isActive ? Color.white.opacity(0.00) : Color.white.opacity(0.08)
                ],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.48)
            )

            RadialGradient(
                colors: [
                    isActive ? Color.white.opacity(0.06) : Color.white.opacity(0.34),
                    Color.white.opacity(0.00)
                ],
                center: UnitPoint(x: 0.12, y: 0.00),
                startRadius: 6,
                endRadius: 112
            )

            LinearGradient(
                colors: [
                    Color.clear,
                    isActive ? Color.black.opacity(0.34) : Color.black.opacity(0.018)
                ],
                startPoint: UnitPoint(x: 0.50, y: 0.62),
                endPoint: .bottom
            )

            if isActive {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.00),
                                Color.white.opacity(0.045),
                                Color.white.opacity(0.00)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .rotationEffect(.degrees(-8))
                    .offset(y: -22)
            }

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            isActive ? Color.white.opacity(0.22) : Color.white.opacity(0.88),
                            isActive ? Color.white.opacity(0.07) : Color.white.opacity(0.26),
                            isActive ? Color.white.opacity(0.03) : Color.black.opacity(0.045)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .padding(0.6)
        }
    }

    private var baseFill: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: isActive ? [
                        Color(red: 0.17, green: 0.18, blue: 0.16),
                        Color(red: 0.025, green: 0.035, blue: 0.028)
                    ] : [
                        Color.white,
                        Color(red: 0.965, green: 0.962, blue: 0.945)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
}

private extension View {
    @ViewBuilder
    func blankWidgetBackground(isActive: Bool) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) {
                BlankWidgetGlassBackground(isActive: isActive)
            }
        } else {
            background(BlankWidgetGlassBackground(isActive: isActive))
        }
    }
}

struct BlankQuickBlockWidget: Widget {
    let kind = "BlankQuickBlockWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BlankWidgetProvider()) { entry in
            BlankWidgetView(entry: entry)
        }
        .configurationDisplayName("Blank")
        .description("Inicia un bloqueo rapido.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct BlankWidgetBundle: WidgetBundle {
    var body: some Widget {
        BlankQuickBlockWidget()
    }
}
