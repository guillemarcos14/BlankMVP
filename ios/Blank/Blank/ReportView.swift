import SwiftUI

struct ReportView: View {
    @EnvironmentObject private var sessionStore: SessionStore

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

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Progreso")
                        .font(.largeTitle.weight(.bold))

                    Text("Actividad real de tus sesiones. Sin premios ni ruido.")
                        .font(.body)
                        .foregroundStyle(reportSecondary)
                }

                heroMetric(
                    value: formatDuration(weekly.totalFocusTime),
                    label: "tiempo protegido esta semana"
                )

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
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
                        title: "Mejor racha",
                        value: "\(progress.longestStreakDays)d",
                        caption: "ultimos 365 dias"
                    )
                }

                activitySection(days: progress.recentActivity)

                VStack(spacing: 10) {
                    reportRow(title: "Mejor dia", value: bestDayText(report: weekly))
                    reportRow(title: "Tiempo recuperado estimado", value: formatDuration(weekly.estimatedTimeSaved))
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

                Text("La estimacion usa 15 minutos recuperados por sesion completada. El mapa de actividad reparte el tiempo por dia cuando una sesion cruza medianoche.")
                    .font(.footnote)
                    .foregroundStyle(reportSecondary)
            }
            .padding(24)
        }
        .background(reportBackground.ignoresSafeArea())
        .foregroundStyle(reportPrimary)
        .navigationTitle("Progreso")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(reportBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
    }

    private func heroMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value)
                .font(.blankInter(size: 56, weight: .bold, relativeTo: .largeTitle))
                .minimumScaleFactor(0.62)
                .lineLimit(1)

            Text(label)
                .font(.headline)
                .foregroundStyle(reportSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(reportSurface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func metricTile(title: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(reportSecondary)

            Text(value)
                .font(.blankInter(size: 30, weight: .bold, relativeTo: .title))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(caption)
                .font(.caption)
                .foregroundStyle(reportSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(reportSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func activitySection(days: [BlankActivityDay]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Ultimos 28 dias")
                    .font(.headline)

                Spacer()

                HStack(spacing: 8) {
                    legendItem(label: "<1h", opacity: 0.30)
                    legendItem(label: "1-3h", opacity: 0.52)
                    legendItem(label: ">3h", opacity: 0.84)
                }
            }

            VStack(spacing: 8) {
                ForEach(Array(weekRows(from: days).enumerated()), id: \.offset) { row in
                    HStack(spacing: 6) {
                        ForEach(row.element) { day in
                            activitySquare(day)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(reportSurface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func legendItem(label: String, opacity: Double) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(reportPrimary.opacity(opacity))
                .frame(width: 9, height: 9)

            Text(label)
                .font(.caption2)
                .foregroundStyle(reportSecondary)
        }
    }

    private func activitySquare(_ day: BlankActivityDay) -> some View {
        VStack(spacing: 3) {
            Text(dayNumber(day.date))
                .font(.blankInter(size: 10, weight: .medium, relativeTo: .caption2))
                .foregroundStyle(reportSecondary)
                .frame(height: 12)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(activityColor(for: day.totalFocusTime))
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(reportPrimary.opacity(day.sessionCount > 0 ? 0.16 : 0.04), lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(dayNumber(day.date)): \(formatDuration(day.totalFocusTime))")
    }

    private func reportRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(reportSecondary)
            Spacer()
            Text(value)
                .font(.blankInter(size: 16, weight: .semibold, relativeTo: .body))
        }
        .padding(18)
        .background(reportSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        .background(reportSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func activityColor(for duration: TimeInterval) -> Color {
        let hours = duration / 3600
        switch hours {
        case 0:
            return reportPrimary.opacity(0.08)
        case 0..<1:
            return reportPrimary.opacity(0.30)
        case 1..<3:
            return reportPrimary.opacity(0.52)
        default:
            return reportPrimary.opacity(0.84)
        }
    }

    private func weekRows(from days: [BlankActivityDay]) -> [[BlankActivityDay]] {
        stride(from: 0, to: days.count, by: 7).map { start in
            Array(days[start..<min(start + 7, days.count)])
        }
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

    private func dayNumber(_ date: Date) -> String {
        String(Calendar.current.component(.day, from: date))
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
