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
    private var foregroundColor: Color { isActive ? Color.white.opacity(0.95) : Color.black.opacity(0.78) }
    private var secondaryForegroundColor: Color { isActive ? Color.white.opacity(0.88) : Color.black.opacity(0.70) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Blank")
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundStyle(secondaryForegroundColor)
                .padding(.top, 2)
                .padding(.leading, 1)

            Spacer(minLength: 10)

            VStack(spacing: 12) {
                actionCircle

                Text(title)
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(foregroundColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
            }
            .frame(maxWidth: .infinity)
            .offset(y: -2)

            Spacer(minLength: 12)
        }
        .padding(16)
        .blankWidgetBackground(isActive: entry.activeState.isActive)
        .widgetURL(URL(string: "blank://configure-block"))
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
        Circle()
            .fill(Color(red: 0.18, green: 0.18, blue: 0.17))
            .overlay {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                Color.white.opacity(0.00)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .frame(width: 54, height: 54)
            .contentShape(Circle())
    }

    private var progressCircle: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.20), lineWidth: 4)
            Circle()
                .trim(from: 0, to: entry.activeState.progress(now: entry.date))
                .stroke(Color.white.opacity(0.94), style: StrokeStyle(lineWidth: 4, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(Color.white.opacity(0.04))
        }
        .frame(width: 60, height: 60)
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
            Rectangle()
                .fill(isActive ? AnyShapeStyle(Color(red: 0.08, green: 0.09, blue: 0.08)) : AnyShapeStyle(.ultraThinMaterial))

            Rectangle()
                .fill(isActive ? Color.black.opacity(0.18) : Color.white.opacity(0.82))

            LinearGradient(
                colors: [
                    isActive ? Color.white.opacity(0.10) : Color.white.opacity(0.26),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.42)
            )

            RadialGradient(
                colors: [
                    isActive ? Color.white.opacity(0.10) : Color.white.opacity(0.18),
                    Color.white.opacity(0.00)
                ],
                center: UnitPoint(x: 0.14, y: 0.04),
                startRadius: 6,
                endRadius: 100
            )

            LinearGradient(
                colors: [
                    Color.clear,
                    isActive ? Color.white.opacity(0.05) : Color.black.opacity(0.035)
                ],
                startPoint: UnitPoint(x: 0.50, y: 0.70),
                endPoint: .bottom
            )

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            isActive ? Color.white.opacity(0.26) : Color.white.opacity(0.74),
                            isActive ? Color.white.opacity(0.10) : Color.white.opacity(0.28),
                            isActive ? Color.white.opacity(0.04) : Color.black.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.15
                )
                .padding(0.6)
        }
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
