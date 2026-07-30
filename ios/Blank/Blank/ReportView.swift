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
        let totalFocusTime = focusTime(sessions: sessionStore.sessions, from: .distantPast, to: Date())
        let totalSessionCount = sessionCount(sessions: sessionStore.sessions, from: .distantPast, to: Date())
        let savedTime = cappedSavedTime(totalFocusTime: totalFocusTime, sessionCount: totalSessionCount)
        let hasRecentActivity = progress.recentActivity.contains { $0.sessionCount > 0 || $0.totalFocusTime > 0 }
        let hasProgress = totalSessionCount > 0 || totalFocusTime > 0 || hasRecentActivity

        ZStack {
            ReportLiquidBackground()

            ScrollView {
                VStack(alignment: .center, spacing: 22) {
                    reportHeader()

                    minimalHero(
                        savedTime: savedTime,
                        activityDays: progress.recentActivity,
                        insight: insightText(totalSessionCount: totalSessionCount, savedTime: savedTime, progress: progress)
                    )

                    if hasProgress {
                        weeklySummary(
                            weekly: weekly,
                            emergencyUnlocksRemaining: sessionStore.emergencyUnlocksRemaining
                        )

                        nextStepCard(progress: progress)

                        detailDisclosure(
                            weekly: weekly,
                            totalFocusTime: totalFocusTime,
                            totalSessionCount: totalSessionCount,
                            progress: progress,
                            emergencyUnlocksRemaining: sessionStore.emergencyUnlocksRemaining
                        )
                    } else {
                        emptyState()
                    }

                    VStack(spacing: 10) {
                        Text("Cada sesión cuenta. Blank solo mide lo necesario.")
                            .font(.footnote)
                            .foregroundStyle(reportSecondary)

                        Text(savedTimeExplanation(totalFocusTime: totalFocusTime, sessionCount: totalSessionCount))
                            .font(.caption2)
                            .foregroundStyle(reportSecondary.opacity(0.78))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 34)
            }
        }
        .foregroundStyle(reportPrimary)
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
    }

    private func reportHeader() -> some View {
        VStack(spacing: 8) {
            Text("Stats")
                .font(.blankInter(size: 34, weight: .medium, relativeTo: .largeTitle))
                .multilineTextAlignment(.center)
                .lineLimit(1)

            Text("Una lectura ligera de lo que Blank te ha devuelto.")
                .font(.body)
                .foregroundStyle(reportSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 330)
        }
        .frame(maxWidth: .infinity)
    }

    private func minimalHero(
        savedTime: TimeInterval,
        activityDays: [BlankActivityDay],
        insight: String
    ) -> some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text(formatDuration(savedTime))
                    .font(.blankInter(size: 58, weight: .semibold, relativeTo: .largeTitle))
                    .lineLimit(1)
                    .minimumScaleFactor(0.50)

                Text("tiempo recuperado")
                    .font(.body)
                    .foregroundStyle(reportSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 18)

            Text(insight)
                .font(.footnote.weight(.medium))
                .foregroundStyle(reportSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .transition(.opacity.combined(with: .move(edge: .bottom)))

            chartPanel(values: savedSeries(from: activityDays))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .liquidGlass(cornerRadius: 30)
    }

    private func heroPage(
        value: String,
        description: String,
        chartValues: [TimeInterval]
    ) -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text(value)
                    .font(.blankInter(size: 64, weight: .semibold, relativeTo: .largeTitle))
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

            chartPanel(values: chartValues)
        }
    }

    private func chartPanel(values: [TimeInterval]) -> some View {
        let scale = ChartScale(values: values)

        return VStack(alignment: .center, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ProgressLineChart(values: values, maxValue: scale.maxValue, primary: reportPrimary, secondary: reportSecondary)
                    .frame(height: 118)

                VStack(alignment: .trailing) {
                    Text(formatChartScale(scale.maxValue))
                    Spacer()
                    Text(formatChartScale(scale.maxValue / 2))
                    Spacer()
                    Text("0")
                }
                .font(.caption2)
                .foregroundStyle(reportSecondary.opacity(0.88))
                .frame(height: 118)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    private func weeklySummary(
        weekly: BlankWeeklyReport,
        emergencyUnlocksRemaining: Int
    ) -> some View {
        VStack(alignment: .center, spacing: 14) {
            Text("Esta semana")
                .font(.blankInter(size: 18, weight: .medium, relativeTo: .headline))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                statCapsule(title: "Protegidas", value: formatDuration(weekly.totalFocusTime), caption: "Tiempo en Blank")
                statCapsule(title: "Sesiones", value: "\(weekly.completedSessionCount)", caption: "Bloques de foco")
                statCapsule(title: "Emergencias", value: "\(emergencyUnlocksRemaining)", caption: "Restantes")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func nextStepCard(progress: BlankProgressReport) -> some View {
        VStack(alignment: .center, spacing: 8) {
            Text("Siguiente mejora")
                .font(.blankInter(size: 18, weight: .medium, relativeTo: .headline))

            Text(nextStepText(progress: progress))
                .font(.body)
                .foregroundStyle(reportSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 330)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(20)
        .liquidGlass(cornerRadius: 26)
    }

    private func detailDisclosure(
        weekly: BlankWeeklyReport,
        totalFocusTime: TimeInterval,
        totalSessionCount: Int,
        progress: BlankProgressReport,
        emergencyUnlocksRemaining: Int
    ) -> some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                metricRow(title: "Tiempo blankeado", value: formatDuration(totalFocusTime), caption: "Total protegido")
                subtleDivider()
                metricRow(title: "Sesiones totales", value: "\(totalSessionCount)", caption: "Desde el inicio")
                subtleDivider()
                metricRow(title: "Mejor día", value: bestDayText(report: weekly), caption: bestDayCaption(report: weekly))
                subtleDivider()
                metricRow(title: "Rescates usados", value: "\(usedEmergencyUnlocks(emergencyUnlocksRemaining))/3", caption: emergencyCaption(emergencyUnlocksRemaining))

                if !progress.modeActivity.isEmpty {
                    subtleDivider()
                    ForEach(progress.modeActivity.indices, id: \.self) { index in
                        modeRow(progress.modeActivity[index])
                        if index < progress.modeActivity.count - 1 {
                            subtleDivider()
                        }
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Text("Ver detalle")
                .font(.body.weight(.medium))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .liquidGlass(cornerRadius: 22)
    }

    private func progressInsightCards(
        weekly: BlankWeeklyReport,
        progress: BlankProgressReport,
        emergencyUnlocksRemaining: Int
    ) -> some View {
        VStack(spacing: 0) {
            metricRow(
                title: "Momento de riesgo",
                value: riskMomentValue(activityDays: progress.recentActivity),
                caption: riskMomentCaption(activityDays: progress.recentActivity)
            )
            subtleDivider()
            metricRow(
                title: "Calidad de protección",
                value: "\(protectionQualityScore(weekly: weekly, progress: progress, emergencyUnlocksRemaining: emergencyUnlocksRemaining))/100",
                caption: protectionQualityCaption(weekly: weekly, emergencyUnlocksRemaining: emergencyUnlocksRemaining)
            )
            subtleDivider()
            metricRow(
                title: "Control recuperado",
                value: controlRecoveryValue(weekly: weekly, emergencyUnlocksRemaining: emergencyUnlocksRemaining),
                caption: controlRecoveryCaption(weekly: weekly, emergencyUnlocksRemaining: emergencyUnlocksRemaining)
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
        .liquidGlass(cornerRadius: 22)
    }

    private func periodSummaryCards(sessions: [BlankSession]) -> some View {
        let summaries = progressPeriodSummaries(sessions: sessions)
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(summaries) { summary in
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(reportSecondary)
                    Text(summary.value)
                        .font(.blankInter(size: 24, weight: .semibold, relativeTo: .title3))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(summary.caption)
                        .font(.caption2)
                        .foregroundStyle(reportSecondary.opacity(0.82))
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .liquidGlass(cornerRadius: 18)
            }
        }
    }

    private func metricList(
        weekly: BlankWeeklyReport,
        progress: BlankProgressReport,
        emergencyUnlocksRemaining: Int
    ) -> some View {
        VStack(spacing: 0) {
            metricRow(title: "Sesiones", value: "\(weekly.completedSessionCount)", caption: "Protegidas esta semana")
            subtleDivider()
            metricRow(title: "Media protegida", value: formatDuration(weekly.averageSessionDuration), caption: "Por sesión real")
            subtleDivider()
            metricRow(title: "Racha", value: "\(progress.currentStreakDays)d", caption: "Días con Blank")
            subtleDivider()
            metricRow(title: "Mejor día", value: bestDayText(report: weekly), caption: bestDayCaption(report: weekly))
            subtleDivider()
            metricRow(title: "Emergencias", value: "\(usedEmergencyUnlocks(emergencyUnlocksRemaining))/3", caption: emergencyCaption(emergencyUnlocksRemaining))
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
            Text("Tu tiempo recuperado aparecerá aquí.")
                .font(.headline.weight(.semibold))

            Text("Activa Blank y vuelve cuando tengas tu primera sesión protegida.")
                .font(.body)
                .foregroundStyle(reportSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .liquidGlass(cornerRadius: 22)
    }

    private func insightText(totalSessionCount: Int, savedTime: TimeInterval, progress: BlankProgressReport) -> String {
        if totalSessionCount == 0 {
            return "Blank ya está midiendo esta sesión. Las señales se vuelven más útiles al terminarla."
        }

        if savedTime >= 8 * 60 * 60 {
            return "Has recuperado casi medio día para ti."
        }

        if savedTime >= 4 * 60 * 60 {
            return "Has recuperado varias horas que antes se iban solas."
        }

        if savedTime >= 60 * 60 {
            return "Has recuperado más de una hora sin convertirla en otra pantalla."
        }

        if progress.currentStreakDays >= 3 {
            return "Blank te ha protegido \(progress.currentStreakDays) días seguidos."
        }

        if totalSessionCount >= 5 {
            return "Ya hay \(totalSessionCount) momentos en los que no volviste al bucle."
        }

        return "Has recuperado tiempo real sin convertirlo en otra pantalla más."
    }

    private func nextStepText(progress: BlankProgressReport) -> String {
        guard let riskyDay = riskiestDay(activityDays: progress.recentActivity) else {
            return "Completa unas sesiones más y Blank detectará qué momento conviene reforzar."
        }

        let dayName = weekdayName(for: riskyDay.date).lowercased(with: Locale(identifier: "es_ES"))
        if riskyDay.sessionCount > 1 {
            return "Tu momento de riesgo suele ser el \(dayName). Programa Blank antes de esa franja."
        }

        return "El \(dayName) fue tu punto más sensible. Refuerza esa franja antes de que aparezca el impulso."
    }

    private func statCapsule(title: String, value: String, caption: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(reportSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text(value)
                .font(.blankInter(size: 24, weight: .semibold, relativeTo: .title3))
                .lineLimit(1)
                .minimumScaleFactor(0.70)

            Text(caption)
                .font(.caption2)
                .foregroundStyle(reportSecondary.opacity(0.82))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, minHeight: 104)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .liquidGlass(cornerRadius: 24)
    }

    private func savedSeries(from days: [BlankActivityDay]) -> [TimeInterval] {
        days.map { day in
            min(day.totalFocusTime, TimeInterval(day.sessionCount * 7 * 60) + day.totalFocusTime * 0.10)
        }
    }

    private func cappedSavedTime(totalFocusTime: TimeInterval, sessionCount: Int) -> TimeInterval {
        min(totalFocusTime, TimeInterval(sessionCount * 7 * 60) + totalFocusTime * 0.10)
    }

    private func savedTimeExplanation(totalFocusTime: TimeInterval, sessionCount: Int) -> String {
        "Tiempo ahorrado: \(formatDuration(cappedSavedTime(totalFocusTime: totalFocusTime, sessionCount: sessionCount))) estimados con 7 min por sesión y un 10% del tiempo protegido, limitado al tiempo real en Blank."
    }

    private func riskMomentValue(activityDays: [BlankActivityDay]) -> String {
        guard let day = riskiestDay(activityDays: activityDays) else {
            return "Sin patrón"
        }
        return weekdayName(for: day.date)
    }

    private func riskMomentCaption(activityDays: [BlankActivityDay]) -> String {
        guard let day = riskiestDay(activityDays: activityDays) else {
            return "Con más datos aparecerá tu franja vulnerable"
        }
        if day.sessionCount > 1 {
            return "\(day.sessionCount) sesiones: día donde más recurres a Blank"
        }
        return "Día donde más tiempo pediste protección"
    }

    private func riskiestDay(activityDays: [BlankActivityDay]) -> BlankActivityDay? {
        activityDays
            .filter { $0.sessionCount > 0 || $0.totalFocusTime > 0 }
            .max { lhs, rhs in
                let lhsScore = TimeInterval(lhs.sessionCount) * 20 * 60 + lhs.totalFocusTime
                let rhsScore = TimeInterval(rhs.sessionCount) * 20 * 60 + rhs.totalFocusTime
                return lhsScore < rhsScore
            }
    }

    private func protectionQualityScore(
        weekly: BlankWeeklyReport,
        progress: BlankProgressReport,
        emergencyUnlocksRemaining: Int
    ) -> Int {
        guard weekly.completedSessionCount > 0 || weekly.totalFocusTime > 0 else { return 0 }
        let usedEmergencies = usedEmergencyUnlocks(emergencyUnlocksRemaining)
        let averageMinutes = weekly.averageSessionDuration / 60
        let durationBonus: Int
        if averageMinutes >= 60 {
            durationBonus = 12
        } else if averageMinutes >= 30 {
            durationBonus = 8
        } else if averageMinutes >= 15 {
            durationBonus = 4
        } else {
            durationBonus = 0
        }
        let streakBonus = min(progress.currentStreakDays, 5) * 3
        let emergencyPenalty = usedEmergencies * 14
        return min(max(78 + durationBonus + streakBonus - emergencyPenalty, 0), 100)
    }

    private func protectionQualityCaption(weekly: BlankWeeklyReport, emergencyUnlocksRemaining: Int) -> String {
        guard weekly.completedSessionCount > 0 else {
            return "Completa una sesión para medirlo"
        }
        let usedEmergencies = usedEmergencyUnlocks(emergencyUnlocksRemaining)
        if usedEmergencies == 0 {
            return "Sesiones limpias, sin rescates esta semana"
        }
        if usedEmergencies < 3 {
            return "Mejorará al reducir emergencias"
        }
        return "Semana frágil: ya usaste todas las emergencias"
    }

    private func controlRecoveryValue(weekly: BlankWeeklyReport, emergencyUnlocksRemaining: Int) -> String {
        let usedEmergencies = usedEmergencyUnlocks(emergencyUnlocksRemaining)
        if weekly.completedSessionCount > 0 && usedEmergencies == 0 {
            return "Estable"
        }
        if usedEmergencies < 3 {
            return "\(3 - usedEmergencies) reservas"
        }
        return "Límite"
    }

    private func controlRecoveryCaption(weekly: BlankWeeklyReport, emergencyUnlocksRemaining: Int) -> String {
        let usedEmergencies = usedEmergencyUnlocks(emergencyUnlocksRemaining)
        if weekly.completedSessionCount > 0 && usedEmergencies == 0 {
            return "Todavía no necesitaste rescates esta semana"
        }
        if usedEmergencies < 3 {
            return "Emergencias restantes esta semana"
        }
        return "Toca volver a depender del NFC"
    }

    private func usedEmergencyUnlocks(_ emergencyUnlocksRemaining: Int) -> Int {
        min(max(3 - emergencyUnlocksRemaining, 0), 3)
    }

    private func emergencyCaption(_ emergencyUnlocksRemaining: Int) -> String {
        let used = usedEmergencyUnlocks(emergencyUnlocksRemaining)
        if used == 0 {
            return "Sin rescates esta semana"
        }
        if emergencyUnlocksRemaining > 0 {
            return "\(emergencyUnlocksRemaining) disponibles todavía"
        }
        return "Límite semanal alcanzado"
    }

    private func bestDayCaption(report: BlankWeeklyReport) -> String {
        guard let bestIndex = report.dailyDurations.indices.max(by: {
            report.dailyDurations[$0] < report.dailyDurations[$1]
        }), report.dailyDurations[bestIndex] > 0 else {
            return "Esta semana"
        }
        let duration = formatDuration(report.dailyDurations[bestIndex])
        let sessions = report.dailySessionCounts[bestIndex]
        return "\(duration) · \(sessions) sesiones"
    }

    private func progressPeriodSummaries(sessions: [BlankSession]) -> [ProgressPeriodSummary] {
        let calendar = Calendar.current
        let now = Date()
        let periods: [(String, Date)] = [
            ("Hoy", calendar.startOfDay(for: now)),
            ("Semana", BlankWeeklySessionAggregator.startOfWeek(for: now, calendar: calendar)),
            ("Mes", calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)),
            ("Año", calendar.dateInterval(of: .year, for: now)?.start ?? calendar.startOfDay(for: now))
        ]

        return periods.map { title, start in
            let duration = focusTime(sessions: sessions, from: start, to: now)
            let count = sessionCount(sessions: sessions, from: start, to: now)
            return ProgressPeriodSummary(
                title: title,
                value: formatDuration(duration),
                caption: count == 1 ? "1 sesión" : "\(count) sesiones"
            )
        }
    }

    private func focusTime(sessions: [BlankSession], from start: Date, to end: Date) -> TimeInterval {
        sessions.reduce(0) { total, session in
            let sessionEnd = session.endedAt ?? end
            let overlapStart = max(session.startedAt, start)
            let overlapEnd = min(sessionEnd, end)
            guard overlapStart < overlapEnd else { return total }
            return total + overlapEnd.timeIntervalSince(overlapStart)
        }
    }

    private func sessionCount(sessions: [BlankSession], from start: Date, to end: Date) -> Int {
        sessions.filter { session in
            let sessionEnd = session.endedAt ?? end
            return session.startedAt < end && sessionEnd > start
        }.count
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

    private func weekdayName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date).capitalized(with: Locale(identifier: "es_ES"))
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
            BlankAtmosphericBackground()

            LinearGradient(
                colors: [
                    Color.white.opacity(0.22),
                    BlankColors.background.opacity(0.28),
                    Color.white.opacity(0.14)
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
            .background(Color.white.opacity(0.28), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(BlankColors.glassBorder, lineWidth: 1)
            )
            .shadow(color: BlankColors.ink.opacity(0.045), radius: 14, x: 0, y: 8)
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

private struct ProgressPeriodSummary: Identifiable {
    let title: String
    let value: String
    let caption: String

    var id: String { title }
}
