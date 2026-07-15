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
            VStack(alignment: .leading, spacing: 22) {
                heroCarousel(
                    weekly: weekly,
                    savedTime: savedTime,
                    activityDays: progress.recentActivity
                )

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    metricTile(
                        title: "Sesiones",
                        value: "\(weekly.completedSessionCount)",
                        caption: "completadas"
                    )
                    metricTile(
                        title: "Media",
                        value: formatDuration(weekly.averageSessionDuration),
                        caption: "por sesion"
                    )
                    metricTile(
                        title: "Racha",
                        value: "\(progress.currentStreakDays)d",
                        caption: "actual"
                    )
                    metricTile(
                        title: "Mejor dia",
                        value: bestDayText(report: weekly),
                        caption: "esta semana"
                    )
                }

                if !progress.modeActivity.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Modos esta semana")
                            .font(.headline)

                        VStack(spacing: 10) {
                            ForEach(progress.modeActivity) { activity in
                                modeRow(activity)
                            }
                        }
                    }
                }

                Text("Cada sesion cuenta. Blank solo mide lo necesario.")
                    .font(.footnote)
                    .foregroundStyle(reportSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 22)
            .padding(.top, 26)
            .padding(.bottom, 32)
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
        .tabViewStyle(.page(indexDisplayMode: .always))
        .frame(height: 468)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(reportSurface.opacity(0.58))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(.white.opacity(0.66), lineWidth: 1)
                )
        )
    }

    private func heroPage(
        label: String,
        value: String,
        description: String,
        chartTitle: String,
        chartValues: [TimeInterval]
    ) -> some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                Text(label.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(2.6)
                    .foregroundStyle(reportSecondary)

                Text(value)
                    .font(.blankInter(size: 64, weight: .bold, relativeTo: .largeTitle))
                    .lineLimit(1)
                    .minimumScaleFactor(0.54)

                Text(description)
                    .font(.body)
                    .foregroundStyle(reportSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
            .padding(.top, 28)
            .frame(maxWidth: .infinity)

            chartCard(title: chartTitle, values: chartValues)

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 18)
    }

    private func chartCard(title: String, values: [TimeInterval]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)

                Spacer()

                Text("Ultimos 28 dias")
                    .font(.caption)
                    .foregroundStyle(reportSecondary)
            }

            HStack(alignment: .top, spacing: 12) {
                ProgressLineChart(values: values, primary: reportPrimary, secondary: reportSecondary)
                    .frame(height: 150)

                VStack(alignment: .trailing) {
                    Text("2 h")
                    Spacer()
                    Text("1 h")
                    Spacer()
                    Text("0")
                }
                .font(.caption)
                .foregroundStyle(reportSecondary)
                .frame(height: 150)
            }

            HStack {
                Text("28 dias atras")
                Spacer()
                Text("Hoy")
            }
            .font(.caption)
            .foregroundStyle(reportSecondary)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(reportBackground.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(reportPrimary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func metricTile(title: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(reportSecondary)

            Text(value)
                .font(.blankInter(size: 30, weight: .bold, relativeTo: .title))
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Text(caption)
                .font(.caption)
                .foregroundStyle(reportSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(reportSurface.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(reportPrimary.opacity(0.06), lineWidth: 1)
                )
        )
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
                .font(.blankInter(size: 16, weight: .semibold, relativeTo: .body))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(reportSurface.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(reportPrimary.opacity(0.06), lineWidth: 1)
                )
        )
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
                            .fill(secondary.opacity(index == 2 ? 0.10 : 0.06))
                            .frame(height: 1)
                        if index < 2 {
                            Spacer()
                        }
                    }
                }

                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { _ in
                        Rectangle()
                            .fill(secondary.opacity(0.10))
                            .frame(width: 1)
                        Spacer()
                    }
                }

                chartFill(points: points, height: proxy.size.height)
                    .fill(
                        LinearGradient(
                            colors: [primary.opacity(0.10), primary.opacity(0.00)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                chartPath(points: points)
                    .stroke(primary.opacity(0.88), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    if shouldShowPoint(at: index, total: points.count) {
                        Circle()
                            .fill(primary)
                            .frame(width: 5, height: 5)
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
        index == 0 || index == total - 1 || index % 4 == 0
    }
}
