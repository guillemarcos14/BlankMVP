import AVFoundation
import SwiftUI
import UIKit

struct ReportView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var selectedHeroPage = 0

    private let reportBackground = BlankColors.background
    private let reportPrimary = BlankColors.ink
    private let reportSecondary = BlankColors.mutedInk

    private var report: BlankProgressReport {
        BlankProgressAggregator.aggregate(
            sessions: sessionStore.sessions,
            modes: sessionStore.focusModes
        )
    }

    var body: some View {
        let progress = report
        let weekly = progress.weeklyReport
        let savedTime = cappedSavedTime(weekly)
        let hasProgress = weekly.completedSessionCount > 0 || weekly.totalFocusTime > 0

        ZStack {
            ReportLiquidBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    heroCarousel(
                        weekly: weekly,
                        savedTime: savedTime,
                        activityDays: progress.recentActivity,
                        insight: insightText(weekly: weekly, progress: progress)
                    )

                    if hasProgress {
                        metricList(weekly: weekly, progress: progress)

                        if !progress.modeActivity.isEmpty {
                            modesSection(progress.modeActivity)
                        }
                    } else {
                        emptyState()
                    }

                    Text("Cada sesion cuenta. Blank solo mide lo necesario.")
                        .font(.footnote)
                        .foregroundStyle(reportSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 34)
            }
        }
        .foregroundStyle(reportPrimary)
        .navigationTitle("Progreso")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(reportBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .onChange(of: selectedHeroPage) { _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func heroCarousel(
        weekly: BlankWeeklyReport,
        savedTime: TimeInterval,
        activityDays: [BlankActivityDay],
        insight: String
    ) -> some View {
        VStack(spacing: 16) {
            TabView(selection: $selectedHeroPage) {
                heroPage(
                    label: "Tiempo ahorrado",
                    value: formatDuration(savedTime),
                    description: "recuperadas de tu vida gracias a Blank",
                    chartTitle: "Ahorro estimado",
                    chartValues: savedSeries(from: activityDays)
                )
                .tag(0)

                heroPage(
                    label: "Tiempo en Blank",
                    value: formatDuration(weekly.totalFocusTime),
                    description: "protegidas esta semana",
                    chartTitle: "Modo Blank",
                    chartValues: activityDays.map(\.totalFocusTime)
                )
                .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 414)

            HStack(spacing: 7) {
                ForEach(0..<2, id: \.self) { page in
                    Capsule()
                        .fill(page == selectedHeroPage ? reportPrimary : reportPrimary.opacity(0.18))
                        .frame(width: page == selectedHeroPage ? 18 : 6, height: 6)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: selectedHeroPage)
            .frame(maxWidth: .infinity)

            Text(insight)
                .font(.footnote.weight(.medium))
                .foregroundStyle(reportSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .transition(.opacity.combined(with: .move(edge: .bottom)))

            Text("Tiempo ahorrado: estimamos 15 min por sesion completada y lo limitamos al tiempo real en Blank.")
                .font(.caption2)
                .foregroundStyle(reportSecondary.opacity(0.78))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
        }
    }

    private func heroPage(
        label: String,
        value: String,
        description: String,
        chartTitle: String,
        chartValues: [TimeInterval]
    ) -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text(label.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(2.4)
                    .foregroundStyle(reportSecondary)

                Text(value)
                    .font(.blankInter(size: 68, weight: .bold, relativeTo: .largeTitle))
                    .lineLimit(1)
                    .minimumScaleFactor(0.50)

                Text(description)
                    .font(.body)
                    .foregroundStyle(reportSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
            .padding(.top, 10)
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.28), value: selectedHeroPage)

            chartPanel(title: chartTitle, values: chartValues)
        }
    }

    private func chartPanel(title: String, values: [TimeInterval]) -> some View {
        let scale = ChartScale(values: values)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline.weight(.semibold))

                Spacer()

                Text("Ultimos 28 dias")
                    .font(.caption)
                    .foregroundStyle(reportSecondary)
            }

            HStack(alignment: .top, spacing: 12) {
                ProgressLineChart(values: values, maxValue: scale.maxValue, primary: reportPrimary, secondary: reportSecondary)
                    .frame(height: 144)

                VStack(alignment: .trailing) {
                    Text(formatChartScale(scale.maxValue))
                    Spacer()
                    Text(formatChartScale(scale.maxValue / 2))
                    Spacer()
                    Text("0")
                }
                .font(.caption2)
                .foregroundStyle(reportSecondary.opacity(0.88))
                .frame(height: 144)
            }

            HStack {
                Text("28 dias atras")
                Spacer()
                Text("Hoy")
            }
            .font(.caption2)
            .foregroundStyle(reportSecondary.opacity(0.88))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 17)
        .liquidGlass(cornerRadius: 26)
    }

    private func metricList(weekly: BlankWeeklyReport, progress: BlankProgressReport) -> some View {
        VStack(spacing: 0) {
            metricRow(title: "Sesiones", value: "\(weekly.completedSessionCount)", caption: "completadas")
            subtleDivider()
            metricRow(title: "Media", value: formatDuration(weekly.averageSessionDuration), caption: "por sesion")
            subtleDivider()
            metricRow(title: "Racha", value: "\(progress.currentStreakDays)d", caption: "actual")
            subtleDivider()
            metricRow(title: "Mejor dia", value: bestDayText(report: weekly), caption: "esta semana")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
        .liquidGlass(cornerRadius: 22)
    }

    private func metricRow(title: String, value: String, caption: String) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))

                Text(caption)
                    .font(.caption)
                    .foregroundStyle(reportSecondary)
            }

            Spacer(minLength: 12)

            Text(value)
                .font(.blankInter(size: 22, weight: .semibold, relativeTo: .title3))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.vertical, 14)
    }

    private func modesSection(_ activities: [BlankModeActivity]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Modos esta semana")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(activities.indices, id: \.self) { index in
                    let activity = activities[index]
                    modeRow(activity)
                    if index < activities.count - 1 {
                        subtleDivider()
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 4)
            .liquidGlass(cornerRadius: 22)
        }
    }

    private func modeRow(_ activity: BlankModeActivity) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                Text("\(activity.sessionCount) sesiones")
                    .font(.blankInter(size: 12, relativeTo: .caption))
                    .foregroundStyle(reportSecondary)
            }

            Spacer()

            Text(formatDuration(activity.totalFocusTime))
                .font(.blankInter(size: 17, weight: .semibold, relativeTo: .body))
        }
        .padding(.vertical, 14)
    }

    private func subtleDivider() -> some View {
        Rectangle()
            .fill(reportPrimary.opacity(0.07))
            .frame(height: 1)
    }

    private func emptyState() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tu tiempo recuperado aparecera aqui.")
                .font(.headline.weight(.semibold))

            Text("Activa Blank y vuelve cuando tengas tu primera sesion protegida.")
                .font(.body)
                .foregroundStyle(reportSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .liquidGlass(cornerRadius: 22)
    }

    private func insightText(weekly: BlankWeeklyReport, progress: BlankProgressReport) -> String {
        if weekly.completedSessionCount == 0 {
            return "Tu primera sesion empezara a construir esta grafica."
        }

        let savedTime = cappedSavedTime(weekly)

        if savedTime >= 8 * 60 * 60 {
            return "Has recuperado casi medio dia para ti."
        }

        if savedTime >= 4 * 60 * 60 {
            return "Has recuperado varias horas que antes se iban solas."
        }

        if savedTime >= 60 * 60 {
            return "Has recuperado mas de una hora sin convertirla en otra pantalla."
        }

        if progress.currentStreakDays >= 3 {
            return "Blank te ha protegido \(progress.currentStreakDays) dias seguidos."
        }

        if weekly.completedSessionCount >= 5 {
            return "Ya hay \(weekly.completedSessionCount) momentos en los que no volviste al bucle."
        }

        return "Has recuperado tiempo real sin convertirlo en otra pantalla mas."
    }

    private func savedSeries(from days: [BlankActivityDay]) -> [TimeInterval] {
        days.map { day in
            min(day.totalFocusTime, TimeInterval(day.sessionCount * 15 * 60))
        }
    }

    private func cappedSavedTime(_ report: BlankWeeklyReport) -> TimeInterval {
        min(report.estimatedTimeSaved, report.totalFocusTime)
    }

    private func bestDayText(report: BlankWeeklyReport) -> String {
        guard let bestIndex = report.dailyDurations.indices.max(by: {
            report.dailyDurations[$0] < report.dailyDurations[$1]
        }), report.dailyDurations[bestIndex] > 0 else {
            return "Sin datos"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        let symbols = formatter.weekdaySymbols ?? []
        guard !symbols.isEmpty else {
            return "Sin datos"
        }
        let calendarStartIndex = Calendar.current.firstWeekday - 1
        let symbolIndex = (calendarStartIndex + bestIndex) % symbols.count
        return symbols[symbolIndex].capitalized(with: Locale(identifier: "es_ES"))
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = max(0, Int(duration / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours == 0 {
            return "\(minutes) min"
        }

        if minutes == 0 {
            return "\(hours) h"
        }

        return "\(hours) h \(minutes) min"
    }

    private func formatChartScale(_ duration: TimeInterval) -> String {
        let totalMinutes = max(0, Int((duration / 60).rounded()))
        if totalMinutes < 60 {
            return "\(totalMinutes) min"
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min"
    }
}

private struct ReportLiquidBackground: View {
    var body: some View {
        ZStack {
            BlankColors.background

            ReportLoopingVideoBackground(resourceName: "blank_background_idle")
                .opacity(0.10)
                .saturation(0.18)
                .contrast(0.88)
                .blendMode(.softLight)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.40),
                    BlankColors.background.opacity(0.70),
                    Color.white.opacity(0.26)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

private extension View {
    func liquidGlass(cornerRadius: CGFloat) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.72),
                                BlankColors.ink.opacity(0.055),
                                Color.white.opacity(0.28)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: BlankColors.ink.opacity(0.045), radius: 18, x: 0, y: 10)
    }
}

private struct ReportLoopingVideoBackground: UIViewRepresentable {
    let resourceName: String

    func makeUIView(context: Context) -> ReportLoopingVideoView {
        let view = ReportLoopingVideoView()
        view.configure(resourceName: resourceName)
        return view
    }

    func updateUIView(_ uiView: ReportLoopingVideoView, context: Context) {
        uiView.configure(resourceName: resourceName)
    }
}

private final class ReportLoopingVideoView: UIView {
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var currentResourceName: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    func configure(resourceName: String) {
        if currentResourceName == resourceName {
            player?.play()
            return
        }

        currentResourceName = resourceName
        configureAmbientAudioSession()
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp4") else { return }

        let playerItem = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true
        queuePlayer.actionAtItemEnd = .none
        playerLayer.player = queuePlayer
        looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
        player = queuePlayer
        queuePlayer.play()
    }

    private func configureAmbientAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
    }
}

private struct ProgressLineChart: View {
    let values: [TimeInterval]
    let maxValue: TimeInterval
    let primary: Color
    let secondary: Color

    var body: some View {
        GeometryReader { proxy in
            let points = chartPoints(in: proxy.size)

            ZStack {
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { index in
                        Rectangle()
                            .fill(secondary.opacity(index == 2 ? 0.08 : 0.045))
                            .frame(height: 1)
                        if index < 2 {
                            Spacer()
                        }
                    }
                }

                chartFill(points: points, height: proxy.size.height)
                    .fill(
                        LinearGradient(
                            colors: [primary.opacity(0.075), primary.opacity(0.00)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                chartPath(points: points)
                    .stroke(primary.opacity(0.86), style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))

                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    if shouldShowPoint(at: index, total: points.count) {
                        Circle()
                            .fill(primary)
                            .frame(width: index == points.count - 1 ? 6 : 4, height: index == points.count - 1 ? 6 : 4)
                            .position(point)
                    }
                }
            }
        }
    }

    private var cappedValues: [TimeInterval] {
        let fallback = Array(repeating: TimeInterval.zero, count: 28)
        return values.isEmpty ? fallback : values
    }

    private func chartPoints(in size: CGSize) -> [CGPoint] {
        let data = cappedValues
        guard data.count > 1 else {
            return [CGPoint(x: size.width / 2, y: size.height)]
        }

        return data.enumerated().map { index, value in
            let x = CGFloat(index) / CGFloat(data.count - 1) * size.width
            let ratio = min(max(value / maxValue, 0), 1)
            let y = size.height - CGFloat(ratio) * size.height
            return CGPoint(x: x, y: y)
        }
    }

    private func chartPath(points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)

            for index in points.indices.dropFirst() {
                let previous = points[index - 1]
                let current = points[index]
                let midpoint = CGPoint(
                    x: (previous.x + current.x) / 2,
                    y: (previous.y + current.y) / 2
                )
                path.addQuadCurve(to: midpoint, control: previous)
                path.addQuadCurve(to: current, control: current)
            }
        }
    }

    private func chartFill(points: [CGPoint], height: CGFloat) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: CGPoint(x: first.x, y: height))
            path.addLine(to: first)

            for index in points.indices.dropFirst() {
                let previous = points[index - 1]
                let current = points[index]
                let midpoint = CGPoint(
                    x: (previous.x + current.x) / 2,
                    y: (previous.y + current.y) / 2
                )
                path.addQuadCurve(to: midpoint, control: previous)
                path.addQuadCurve(to: current, control: current)
            }

            path.addLine(to: CGPoint(x: last.x, y: height))
            path.closeSubpath()
        }
    }

    private func shouldShowPoint(at index: Int, total: Int) -> Bool {
        index == total - 1 || index % 7 == 0
    }
}

private struct ChartScale {
    let maxValue: TimeInterval

    init(values: [TimeInterval]) {
        let largestValue = values.max() ?? 0
        maxValue = Self.roundedMaxValue(for: largestValue)
    }

    private static func roundedMaxValue(for value: TimeInterval) -> TimeInterval {
        let fallback = 30 * 60
        let target = max(value, TimeInterval(fallback))
        let steps: [TimeInterval] = [
            15 * 60,
            30 * 60,
            60 * 60,
            2 * 60 * 60,
            4 * 60 * 60,
            6 * 60 * 60,
            8 * 60 * 60,
            12 * 60 * 60,
            16 * 60 * 60,
            24 * 60 * 60
        ]

        if let step = steps.first(where: { $0 >= target }) {
            return step
        }

        let hours = ceil(target / (6 * 60 * 60)) * 6
        return hours * 60 * 60
    }
}
