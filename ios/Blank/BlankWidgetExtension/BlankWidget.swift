import AppIntents
import FamilyControls
import ManagedSettings
import SwiftUI
import WidgetKit

struct StartQuickBlockIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Blank"
    static var description = IntentDescription("Starts a quick block with your current Blanked configuration.")

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
    let pendingTimerMinutes: Int?
}

struct BlankWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BlankWidgetEntry {
        BlankWidgetEntry(
            date: Date(),
            activeState: BlankSharedState.ActiveState(
                isActive: false,
                startedAt: nil,
                endsAt: nil
            ),
            hasConfiguration: true,
            pendingTimerMinutes: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (BlankWidgetEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BlankWidgetEntry>) -> Void) {
        let current = entry()
        let nextRefresh = current.activeState.endsAt ?? (current.activeState.isActive ? Date().addingTimeInterval(60) : Date().addingTimeInterval(15 * 60))
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
            hasConfiguration: BlankSharedState.hasConfiguredBlock(in: defaults),
            pendingTimerMinutes: BlankSharedState.pendingWidgetTimerMinutes(defaults: defaults)
        )
    }
}

struct BlankWidgetView: View {
    let entry: BlankWidgetEntry
    @Environment(\.widgetFamily) private var widgetFamily
    private var isActive: Bool { entry.activeState.isActive }
    private var titleColor: Color { isActive ? Color.white.opacity(0.96) : Color(red: 0.13, green: 0.13, blue: 0.12) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            actionContent
                .buttonStyle(.plain)

            if showsTimerBadge {
                timerBadge
                    .padding(.top, 15)
                    .padding(.leading, 15)
            }
        }
            .blankWidgetBackground(isActive: entry.activeState.isActive, family: widgetFamily)
            .animation(.easeInOut(duration: 0.45), value: isActive)
            .animation(.easeInOut(duration: 0.28), value: entry.pendingTimerMinutes)
    }

    @ViewBuilder
    private var actionContent: some View {
        if entry.activeState.isActive {
            Link(destination: URL(string: "blank://open")!) {
                content
            }
        } else if entry.hasConfiguration {
            if #available(iOSApplicationExtension 17.0, *) {
                Button(intent: StartQuickBlockIntent()) {
                    content
                }
            } else {
                Link(destination: URL(string: "blank://configure-block")!) {
                    content
                }
            }
        } else {
            Link(destination: URL(string: "blank://configure-block")!) {
                content
            }
        }
    }

    private var content: some View {
        Group {
            switch widgetFamily {
            case .accessoryInline:
                Text(isActive ? "Blanked active" : "Start Blanked")
            case .accessoryCircular:
                Image(systemName: isActive ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 18, weight: .semibold))
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(isActive ? "Blanked" : "Start Blank")
                        .font(.headline.weight(.semibold))
                    Text(isActive ? "Protected now" : entry.hasConfiguration ? "Tap to block" : "Choose apps")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                if isActive {
                    activeContent
                } else {
                    idleContent
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var activeContent: some View {
        widgetTitle
    }

    private var idleContent: some View {
        widgetTitle
    }

    private var widgetTitle: some View {
        Text(title)
            .font(.custom("Inter", size: 19.5, relativeTo: .headline).weight(.semibold))
            .foregroundStyle(titleColor)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .contentTransition(.opacity)
            .padding(.leading, 7)
            .padding(.bottom, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private var title: String {
        entry.activeState.isActive ? "Blanked" : "Start Blank"
    }

    private var showsTimerBadge: Bool {
        switch widgetFamily {
        case .systemSmall:
            return true
        default:
            return false
        }
    }

    private var timerBadge: some View {
        Link(destination: URL(string: "blank://timer")!) {
            Group {
                if entry.activeState.isActive, let endsAt = entry.activeState.endsAt {
                    Text(endsAt, style: .timer)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                } else if let pendingTimerMinutes = entry.pendingTimerMinutes {
                    Text(formatTimerBadge(minutes: pendingTimerMinutes))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                } else {
                    Image(systemName: "clock")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .foregroundStyle(Color.white)
            .frame(width: badgeWidth, height: 34)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(red: 0.78, green: 0.78, blue: 0.76).opacity(isActive ? 0.28 : 0.82))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(isActive ? 0.10 : 0.22), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var badgeWidth: CGFloat {
        if entry.activeState.isActive, entry.activeState.endsAt != nil {
            return 58
        }
        if let pendingTimerMinutes = entry.pendingTimerMinutes, pendingTimerMinutes >= 60 {
            return 46
        }
        return entry.pendingTimerMinutes == nil ? 34 : 42
    }

    private func formatTimerBadge(minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h\(rest)"
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
    func blankWidgetBackground(isActive: Bool, family: WidgetFamily) -> some View {
        if family == .accessoryInline || family == .accessoryCircular || family == .accessoryRectangular {
            self
        } else if #available(iOSApplicationExtension 17.0, *) {
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
        .configurationDisplayName("Blanked")
        .description("Start a quick block.")
        .supportedFamilies([.systemSmall, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct BlankWidgetBundle: WidgetBundle {
    var body: some Widget {
        BlankQuickBlockWidget()
    }
}
