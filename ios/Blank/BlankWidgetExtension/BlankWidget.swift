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
        VStack(alignment: .leading, spacing: 0) {
            Text("Blank")
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.96))
                .padding(.top, 1)
                .padding(.leading, 1)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                actionCircle

                Text(title)
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.97))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
            }
            .frame(maxWidth: .infinity)
            .offset(y: -1)

            Spacer(minLength: 8)
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
            .fill(Color.white.opacity(0.98))
            .overlay {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.20),
                                Color.white.opacity(0.00)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .frame(width: 60, height: 60)
            .contentShape(Circle())
    }

    private var progressCircle: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.20), lineWidth: 5)
            Circle()
                .trim(from: 0, to: entry.activeState.progress(now: entry.date))
                .stroke(Color.white.opacity(0.94), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(Color.white.opacity(0.08))
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
            Rectangle().fill(.ultraThinMaterial)
            Rectangle()
                .fill(Color.white.opacity(isActive ? 0.13 : 0.19))
            LinearGradient(
                colors: [
                    Color.white.opacity(isActive ? 0.22 : 0.32),
                    Color.white.opacity(isActive ? 0.05 : 0.12),
                    Color.black.opacity(isActive ? 0.22 : 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [
                    Color.white.opacity(isActive ? 0.30 : 0.38),
                    Color.white.opacity(0.00)
                ],
                center: .topLeading,
                startRadius: 8,
                endRadius: 120
            )
            LinearGradient(
                colors: [
                    Color(red: 0.70, green: 0.80, blue: 0.92).opacity(isActive ? 0.20 : 0.12),
                    Color.clear
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.34),
                            Color.white.opacity(0.06),
                            Color.white.opacity(0.00)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .padding(0.5)
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
