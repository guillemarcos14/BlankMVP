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

    var body: some View {
        ZStack {
            BlankWidgetGlassBackground()

            VStack(alignment: .leading, spacing: 0) {
                Text("Blank")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.92))

                Spacer(minLength: 0)

                VStack(spacing: 11) {
                    actionCircle

                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .blankWidgetBackground()
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
            .fill(Color.white.opacity(0.95))
            .frame(width: 58, height: 58)
            .contentShape(Circle())
    }

    private var progressCircle: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.24), lineWidth: 5)
            Circle()
                .trim(from: 0, to: entry.activeState.progress(now: entry.date))
                .stroke(Color.white.opacity(0.92), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 58, height: 58)
    }

    private var title: String {
        guard entry.activeState.isActive else { return "Bloquear" }
        let minutes = entry.activeState.remainingMinutes(now: entry.date) ?? 0
        return "Activo \(minutes)m"
    }
}

private struct BlankWidgetGlassBackground: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(
                colors: [
                    Color(red: 0.84, green: 0.88, blue: 0.94).opacity(0.34),
                    Color(red: 0.18, green: 0.21, blue: 0.26).opacity(0.50)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private extension View {
    @ViewBuilder
    func blankWidgetBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) {
                BlankWidgetGlassBackground()
            }
        } else {
            background(BlankWidgetGlassBackground())
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
