import SwiftUI

struct ReportView: View {
    @EnvironmentObject private var sessionStore: SessionStore

    var body: some View {
        let report = sessionStore.currentWeekReport

        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Informe")
                    .font(.largeTitle.weight(.bold))

                Text("Una lectura basica de lo que Blank ha protegido esta semana.")
                    .font(.body)
                    .foregroundStyle(BrickColors.secondaryText)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(formatDuration(report.estimatedTimeSaved))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.72)

                Text("tiempo recuperado estimado")
                    .font(.headline)
                    .foregroundStyle(BrickColors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .background(BrickColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            VStack(spacing: 12) {
                reportRow(title: "Tiempo protegido", value: formatDuration(report.totalFocusTime))
                reportRow(title: "Sesiones completadas", value: "\(report.completedSessionCount)")
                reportRow(title: "Mejor dia", value: bestDayText(report: report))
            }

            Text("La estimacion usa una aproximacion conservadora de 15 minutos salvados por sesion completada. Se ajustara cuando Blank tenga mas datos reales.")
                .font(.footnote)
                .foregroundStyle(BrickColors.secondaryText)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrickColors.background)
        .foregroundStyle(BrickColors.text)
        .navigationTitle("Informe")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func reportRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(BrickColors.secondaryText)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
        .padding(18)
        .background(BrickColors.surface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
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
