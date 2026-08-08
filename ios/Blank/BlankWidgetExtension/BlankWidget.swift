import SwiftUI
import WidgetKit

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
                endsAt: nil
            ),
            hasConfiguration: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (BlankWidgetEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BlankWidgetEntry>) -> Void) {
        let current = entry()
        let nextRefresh = current.activeState.isActive ? Date().addingTimeInterval(10) : Date().addingTimeInterval(60)
        completion(Timeline(entries: [current], policy: .after(nextRefresh)))
    }

    private func entry(date: Date = Date()) -> BlankWidgetEntry {
        let defaults = BlankSharedState.defaults
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
    private var titleColor: Color { isActive ? Color.white.opacity(0.96) : Color(red: 0.13, green: 0.13, blue: 0.12) }

    var body: some View {
        actionContent
            .buttonStyle(.plain)
            .blankWidgetBackground(isActive: entry.activeState.isActive)
            .animation(.easeInOut(duration: 0.45), value: isActive)
    }

    @ViewBuilder
    private var actionContent: some View {
        if entry.activeState.isActive {
            Link(destination: URL(string: "blank://scan-blank")!) {
                content
            }
        } else if entry.hasConfiguration {
            Link(destination: URL(string: "blank://start-blank")!) {
                content
            }
        } else {
            Link(destination: URL(string: "blank://configure-block")!) {
                content
            }
        }
    }

    private var content: some View {
        Group {
            if isActive {
                activeContent
            } else {
                idleContent
            }
        }
        .contentShape(Rectangle())
        .unredacted()
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
            .unredacted()
    }

    private var title: String {
        entry.activeState.isActive ? "Blankeado" : "Blankear"
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
        GeometryReader { proxy in
            Image(isActive ? "blank_home_background_active" : "blank_home_background_idle")
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
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
