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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Blank")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(secondaryForegroundColor)
                .padding(.top, 1)
                .padding(.leading, 1)

            Spacer(minLength: 8)

            VStack(spacing: 10) {
                actionCircle

                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(foregroundColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
            }
            .frame(maxWidth: .infinity)
            .offset(y: -3)

            Spacer(minLength: 14)
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
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.22, green: 0.22, blue: 0.20),
                        Color(red: 0.10, green: 0.10, blue: 0.09)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    .padding(0.5)
            }
            .overlay(alignment: .top) {
                Circle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 42, height: 16)
                    .blur(radius: 10)
                    .offset(y: 5)
            }
            .shadow(color: Color.black.opacity(0.10), radius: 7, x: 0, y: 5)
            .frame(width: 64, height: 64)
            .contentShape(Circle())
    }

    private var progressCircle: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.025))
            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: 3.25)
            Circle()
                .trim(from: 0, to: entry.activeState.progress(now: entry.date))
                .stroke(Color.white.opacity(0.92), style: StrokeStyle(lineWidth: 3.25, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 64, height: 64)
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
                    isActive ? Color.white.opacity(0.08) : Color.white.opacity(0.36),
                    isActive ? Color.white.opacity(0.00) : Color.white.opacity(0.06)
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
                    isActive ? Color.black.opacity(0.28) : Color.black.opacity(0.028)
                ],
                startPoint: UnitPoint(x: 0.50, y: 0.62),
                endPoint: .bottom
            )

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
                        Color(red: 0.15, green: 0.16, blue: 0.14),
                        Color(red: 0.055, green: 0.065, blue: 0.055)
                    ] : [
                        Color(red: 0.99, green: 0.99, blue: 0.98),
                        Color(red: 0.94, green: 0.94, blue: 0.92)
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
