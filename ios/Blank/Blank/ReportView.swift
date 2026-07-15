import SwiftUI

struct ReportView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var selectedHeroPage = 0

    private let reportBackground = BlankColors.background
    private let reportSurface = BlankColors.surface
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

        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                heroCarousel(
                    weekly: weekly,
                    savedTime: savedTime,
                    activityDays: progress.recentActivity
                )

                metricList(weekly: weekly, progress: progress)

                if !progress.modeActivity.isEmpty {
                    modesSection(progress.modeActivity)
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
        .background(reportBackground.ignoresSafeArea())
        .foregroundStyle(reportPrimary)
        .navigationTitle("Progreso")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(reportBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
    }

    private func heroCarousel(
        weekly: BlankWeeklyReport,
        savedTime: TimeInterval,
        activityDays: [BlankActivityDay]
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
            .frame(height: 404)

            HStack(spacing: 7) {
                ForEach(0..<2, id: \.self) { page in
                    Capsule()
                        .fill(page == selectedHeroPage ? reportPrimary : reportPrimary.opacity(0.18))
                        .frame(width: page == selectedHeroPage ? 18 : 6, height: 6)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: selectedHeroPage)
            .frame(maxWidth: .infinity)
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

            chartPanel(title: chartTitle, values: chartValues)
        }
    }

    private func chartPanel(title: String, values: [TimeInterval]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline.weight(.semibold))

                Spacer()

                Text("Ultimos 28 dias")
                    .font(.caption)
                    .foregroundStyle(reportSecondary)
            }

            HStack(alignment: .top, spacing: 12) {
                ProgressLineChart(values: values, primary: reportPrimary, secondary: reportSecondary)
                    .frame(height: 144)

                VStack(alignment: .trailing) {
                    Text("2 h")
                    Spacer()
                    Text("1 h")
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
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(reportSurface.opacity(0.52))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(reportPrimary.opacity(0.05), lineWidth: 1)
                )
        )
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
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(reportSurface.opacity(0.60))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(reportPrimary.opacity(0.05), lineWidth: 1)
                )
        )
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
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(reportSurface.opacity(0.60))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(reportPrimary.opacity(0.05), lineWidth: 1)
                    )
            )
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
        let symbols = formatter.shortWeekdaySymbols ?? []
        guard !symbols.isEmpty else {
            return "Sin datos"
        }
        let calendarStartIndex = Calendar.current.firstWeekday - 1
        let symbolIndex = (calendarStartIndex + bestIndex) % symbols.count
        return symbols[symbolIndex]
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
}

private struct ProgressLineChart: View {
    let values: [TimeInterval]
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

    private var maxValue: TimeInterval {
        max(cappedValues.max() ?? 0, 2 * 60 * 60)
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
