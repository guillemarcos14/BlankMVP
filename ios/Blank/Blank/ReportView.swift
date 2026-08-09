import SwiftUI
import UIKit

struct ReportView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var selectedHeroPage = 0
    @AppStorage("blankWeeklyAIGoal", store: BlankSharedState.defaults) private var storedWeeklyGoal = ""
    @AppStorage("blankWeeklyAIPlanFirst", store: BlankSharedState.defaults) private var storedPlanFirst = ""
    @AppStorage("blankWeeklyAIPlanSecond", store: BlankSharedState.defaults) private var storedPlanSecond = ""
    @AppStorage("blankWeeklyAIPlanThird", store: BlankSharedState.defaults) private var storedPlanThird = ""

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

        List {
            VStack(alignment: .center, spacing: 22) {
                    reportHeader()

                    minimalHero(savedTime: savedTime)

                    if hasProgress {
                        periodSummaryCapsule(sessions: sessionStore.sessions)

                        graphCapsule(activityDays: progress.recentActivity)

                        behaviorCapsule(
                            weekly: weekly,
                            progress: progress,
                            emergencyUnlocksRemaining: sessionStore.emergencyUnlocksRemaining
                        )

                        dailyAISummaryCapsule(
                            summary: dailyAISummary(
                                events: sessionStore.usageEvents,
                                sessions: sessionStore.sessions,
                                progress: progress
                            )
                        )

                        weeklyAIReportCapsule(
                            report: weeklyAIReport(
                                events: sessionStore.usageEvents,
                                sessions: sessionStore.sessions,
                                progress: progress
                            )
                        )
                    } else {
                        emptyState()
                    }

                    #if DEBUG
                    aiDemoDataButton()
                    #endif

                    Text(savedTimeExplanation(totalFocusTime: totalFocusTime, sessionCount: totalSessionCount))
                        .font(.caption2)
                        .foregroundStyle(reportSecondary.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .lineSpacing(1)
                        .padding(.horizontal, 24)
                        .frame(maxWidth: 340)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 2)
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 34)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(ReportLiquidBackground().ignoresSafeArea())
        .foregroundStyle(reportPrimary)
    }

    private func reportHeader() -> some View {
        TopSheetHeader(
            title: "Stats",
            subtitle: "Mide el tiempo que Blank te devuelve\ny resume tu ritmo de protección.",
            titleColor: reportPrimary,
            subtitleColor: reportSecondary
        )
    }

    private func minimalHero(savedTime: TimeInterval) -> some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text(formatDuration(savedTime))
                    .font(.blankInter(size: 58, weight: .semibold, relativeTo: .largeTitle))
                    .lineLimit(1)
                    .minimumScaleFactor(0.50)

                Text("Tiempo Recuperado")
                    .font(.body)
                    .foregroundStyle(reportSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 28)
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

    private func periodSummaryCapsule(sessions: [BlankSession]) -> some View {
        let summaries = Array(progressPeriodSummaries(sessions: sessions).prefix(3))

        return VStack(alignment: .center, spacing: 14) {
            Text("Tiempo Blankeado")
                .font(.blankInter(size: 18, weight: .medium, relativeTo: .headline))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(summaries) { summary in
                    statCapsule(title: summary.title, value: summary.value, caption: summary.caption, minHeight: 96)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .liquidGlass(cornerRadius: 28)
    }

    private func graphCapsule(activityDays: [BlankActivityDay]) -> some View {
        VStack(alignment: .center, spacing: 14) {
            Text("Tendencia semanal")
                .font(.blankInter(size: 18, weight: .medium, relativeTo: .headline))

            chartPanel(values: savedSeries(from: Array(activityDays.suffix(7))))
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .liquidGlass(cornerRadius: 28)
    }

    private func behaviorCapsule(
        weekly: BlankWeeklyReport,
        progress: BlankProgressReport,
        emergencyUnlocksRemaining: Int
    ) -> some View {
        VStack(alignment: .center, spacing: 14) {
            Text("Comportamiento")
                .font(.blankInter(size: 18, weight: .medium, relativeTo: .headline))

            VStack(spacing: 10) {
                statCapsule(title: "Mejor día", value: bestDayText(report: weekly), caption: bestDayCaption(report: weekly), minHeight: 86)
                statCapsule(title: "Modo más usado", value: mostUsedModeName(progress: progress), caption: mostUsedModeCaption(progress: progress), minHeight: 86)
                statCapsule(title: "Emergencias", value: "\(usedEmergencyUnlocks(emergencyUnlocksRemaining))/3", caption: emergencyCaption(emergencyUnlocksRemaining), minHeight: 86)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .liquidGlass(cornerRadius: 28)
    }

    private func dailyAISummaryCapsule(summary: DailyAISummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Resumen diario")
                    .font(.blankInter(size: 17, weight: .medium, relativeTo: .headline))
                Text(summary.status)
                    .font(.caption)
                    .foregroundStyle(reportSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                dailySummaryRow(title: "Hoy", value: summary.today)
                dailySummaryRow(title: "Señal", value: summary.signal)
                dailySummaryRow(title: "Siguiente", value: summary.nextAction)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .liquidGlass(cornerRadius: 28)
    }

    private func dailySummaryRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(reportSecondary)
            Text(value)
                .font(.blankInter(size: 13, relativeTo: .footnote))
                .foregroundStyle(reportPrimary.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func weeklyAIReportCapsule(report: WeeklyAIReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Informe semanal AI")
                    .font(.blankInter(size: 17, weight: .medium, relativeTo: .headline))
                Text(report.summary)
                    .font(.caption)
                    .foregroundStyle(reportSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            aiReportSection(title: "Patrones", items: report.patterns)
            aiReportSection(title: "Apps y franjas", items: report.weakSpots)
            aiReportSection(title: "Recomendaciones", items: report.recommendations)

            VStack(alignment: .leading, spacing: 6) {
                Text("Objetivo")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(reportSecondary)
                editableAIField(
                    placeholder: report.goal,
                    text: Binding(
                        get: { storedWeeklyGoal.isEmpty ? report.goal : storedWeeklyGoal },
                        set: { storedWeeklyGoal = $0 }
                    )
                )
            }
            .padding(.top, 2)

            editablePlanSection(report: report)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .liquidGlass(cornerRadius: 28)
    }

    private func editablePlanSection(report: WeeklyAIReport) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Plan")
                .font(.caption.weight(.semibold))
                .foregroundStyle(reportSecondary)

            editableAIField(
                placeholder: report.plan[safe: 0] ?? "Bloque corto en tu franja débil.",
                text: Binding(
                    get: { storedPlanFirst.isEmpty ? (report.plan[safe: 0] ?? "") : storedPlanFirst },
                    set: { storedPlanFirst = $0 }
                )
            )
            editableAIField(
                placeholder: report.plan[safe: 1] ?? "Repite el modo principal sin cambios.",
                text: Binding(
                    get: { storedPlanSecond.isEmpty ? (report.plan[safe: 1] ?? "") : storedPlanSecond },
                    set: { storedPlanSecond = $0 }
                )
            )
            editableAIField(
                placeholder: report.plan[safe: 2] ?? "Revisa el resultado al final de la semana.",
                text: Binding(
                    get: { storedPlanThird.isEmpty ? (report.plan[safe: 2] ?? "") : storedPlanThird },
                    set: { storedPlanThird = $0 }
                )
            )

            Button("Restablecer propuesta") {
                storedWeeklyGoal = ""
                storedPlanFirst = ""
                storedPlanSecond = ""
                storedPlanThird = ""
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(reportSecondary)
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(.top, 2)
    }

    #if DEBUG
    private func aiDemoDataButton() -> some View {
        Button {
            sessionStore.loadAIDemoData()
            storedWeeklyGoal = ""
            storedPlanFirst = ""
            storedPlanSecond = ""
            storedPlanThird = ""
        } label: {
            Text("Cargar datos demo AI")
                .font(.caption.weight(.semibold))
                .foregroundStyle(reportSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background {
                    Capsule()
                        .fill(Color.white.opacity(0.20))
                }
                .overlay {
                    Capsule()
                        .stroke(reportPrimary.opacity(0.07), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cargar datos demo AI")
    }
    #endif

    private func editableAIField(placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text, axis: .vertical)
            .font(.blankInter(size: 13, relativeTo: .footnote))
            .foregroundStyle(reportPrimary.opacity(0.88))
            .lineLimit(1...3)
            .textFieldStyle(.plain)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.24))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(reportPrimary.opacity(0.07), lineWidth: 1)
            }
    }

    private func aiReportSection(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(reportSecondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(reportPrimary.opacity(0.72))
                            .frame(width: 4, height: 4)
                            .padding(.top, 7)
                        Text(item)
                            .font(.blankInter(size: 13, relativeTo: .footnote))
                            .foregroundStyle(reportPrimary.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
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

    private func mostUsedModeName(progress: BlankProgressReport) -> String {
        progress.modeActivity.first?.name ?? "Sin datos"
    }

    private func mostUsedModeCaption(progress: BlankProgressReport) -> String {
        guard let mode = progress.modeActivity.first else {
            return "Esta semana"
        }
        return "\(formatDuration(mode.totalFocusTime)) · \(mode.sessionCount) sesiones"
    }

    private func statCapsule(title: String, value: String, caption: String, minHeight: CGFloat = 104) -> some View {
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
        .frame(maxWidth: .infinity, minHeight: minHeight)
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
                value: formatCompactDuration(duration),
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

    private func dailyAISummary(
        events: [BlankUsageEvent],
        sessions: [BlankSession],
        progress: BlankProgressReport
    ) -> DailyAISummary {
        let calendar = Calendar.current
        let now = Date()
        let dayStart = calendar.startOfDay(for: now)
        let todayEvents = events.filter { $0.occurredAt >= dayStart && $0.occurredAt <= now }
        let todaySessions = sessions.filter { session in
            let sessionEnd = session.endedAt ?? now
            return session.startedAt <= now && sessionEnd >= dayStart
        }
        let startedEvents = todayEvents.filter { $0.kind == .blockStarted }
        let brokenEvents = todayEvents.filter { $0.kind == .blockBroken || $0.endedReason == .emergency }
        let totalFocus = focusTime(sessions: todaySessions, from: dayStart, to: now)
        let modeName = mostCommonModeName(from: todaySessions, events: startedEvents, progress: progress)

        guard !todaySessions.isEmpty || !todayEvents.isEmpty else {
            return DailyAISummary(
                status: "Todavía no hay actividad hoy.",
                today: "Hoy aún no has usado Blank.",
                signal: "Sin señal diaria suficiente.",
                nextAction: "Haz un bloque de 25 min con tu modo principal."
            )
        }

        let status: String
        if brokenEvents.isEmpty {
            status = "Día estable, sin emergencias registradas."
        } else {
            status = "Hoy hubo \(brokenEvents.count) ruptura\(brokenEvents.count == 1 ? "" : "s")."
        }

        let today = "\(formatDuration(totalFocus)) protegidos en \(todaySessions.count) sesión\(todaySessions.count == 1 ? "" : "es")."

        let signal: String
        if let hour = mostCommonValue(brokenEvents.map(\.localHour)) {
            signal = "La franja sensible de hoy fue \(hourRangeText(hour))."
        } else if let hour = mostCommonHour(from: startedEvents, sessions: todaySessions) {
            signal = "Hoy recurriste más a Blank sobre las \(String(format: "%02d:00", hour))."
        } else if let modeName {
            signal = "El modo activo de hoy fue \(modeName)."
        } else {
            signal = "Aún no hay patrón diario claro."
        }

        let nextAction: String
        if let hour = mostCommonValue(brokenEvents.map(\.localHour)) {
            nextAction = "Mañana activa Blank a las \(activationTimeText(before: hour))."
        } else if totalFocus < 25 * 60 {
            nextAction = "Completa un bloque corto más antes de cerrar el día."
        } else if brokenEvents.isEmpty {
            nextAction = "Repite mañana la misma franja y modo."
        } else {
            nextAction = "Reduce duración antes de repetir el bloqueo."
        }

        return DailyAISummary(
            status: status,
            today: today,
            signal: signal,
            nextAction: nextAction
        )
    }

    private func weeklyAIReport(
        events: [BlankUsageEvent],
        sessions: [BlankSession],
        progress: BlankProgressReport
    ) -> WeeklyAIReport {
        let calendar = Calendar.current
        let now = Date()
        let weekStart = BlankWeeklySessionAggregator.startOfWeek(for: now, calendar: calendar)
        let weeklyEvents = events.filter { $0.occurredAt >= weekStart && $0.occurredAt <= now }
        let weeklySessions = sessions.filter { session in
            let sessionEnd = session.endedAt ?? now
            return session.startedAt <= now && sessionEnd >= weekStart
        }

        guard !weeklySessions.isEmpty || !weeklyEvents.isEmpty else {
            return WeeklyAIReport(
                summary: "Aún no hay datos suficientes esta semana.",
                patterns: [
                    "Blank necesita unas sesiones para detectar patrones reales.",
                    "El informe mejora cuando usas varios modos o franjas.",
                    "Las emergencias ayudarán a detectar momentos frágiles."
                ],
                weakSpots: [
                    "Aún falta una franja débil clara.",
                    "Sin rupturas concentradas esta semana.",
                    "Empieza con 3 apps o categorías clave."
                ],
                recommendations: [
                    "Haz una sesión de al menos 25 minutos hoy.",
                    "Usa el modo Estudio antes del primer bloque fuerte.",
                    "Evita usar emergencia salvo que sea imprescindible."
                ],
                goal: "Completa 3 sesiones esta semana para generar un informe útil.",
                plan: [
                    "Hoy: 25 min con tu modo principal.",
                    "Mañana: repite la misma franja.",
                    "Viernes: revisa si hubo emergencias."
                ]
            )
        }

        let startedEvents = weeklyEvents.filter { $0.kind == .blockStarted }
        let brokenEvents = weeklyEvents.filter { $0.kind == .blockBroken || $0.endedReason == .emergency }
        let totalFocus = focusTime(sessions: weeklySessions, from: weekStart, to: now)
        let bestHour = mostCommonHour(from: startedEvents, sessions: weeklySessions)
        let bestWeekday = mostCommonWeekday(from: startedEvents, sessions: weeklySessions)
        let weakSessions = weeklySessions.filter { $0.endedReason == .emergency }
        let weakHour = mostCommonValue(brokenEvents.map(\.localHour)) ?? mostCommonValue(weakSessions.compactMap(\.localStartHour))
        let weakWeekday = mostCommonValue(brokenEvents.map(\.weekday)) ?? mostCommonValue(weakSessions.compactMap(\.startWeekday))
        let modeName = mostCommonModeName(from: weeklySessions, events: startedEvents, progress: progress)
        let selectionProfile = averageSelectionProfile(from: startedEvents, sessions: weeklySessions)

        var patterns: [String] = []
        patterns.append("\(formatDuration(totalFocus)) protegidos en \(weeklySessions.count) sesiones.")
        if let bestHour {
            patterns.append("Tu franja más repetida empieza sobre las \(String(format: "%02d:00", bestHour)).")
        } else if let bestWeekday {
            patterns.append("El día con más uso fue \(weekdayDisplayName(bestWeekday)).")
        } else {
            patterns.append("Aún no hay una franja clara.")
        }
        if let modeName {
            patterns.append("El modo más usado es \(modeName).")
        } else {
            patterns.append("Aún no hay un modo claro.")
        }
        if brokenEvents.count > 0 {
            patterns[2] = "Has roto \(brokenEvents.count) bloqueo\(brokenEvents.count == 1 ? "" : "s") esta semana."
        }

        var weakSpots: [String] = []
        if let weakHour {
            weakSpots.append("Franja débil: \(hourRangeText(weakHour)).")
        } else if let bestHour {
            weakSpots.append("Franja a reforzar: \(hourRangeText(bestHour)).")
        } else {
            weakSpots.append("Aún falta una franja débil clara.")
        }
        if let weakWeekday, brokenEvents.count > 0 {
            weakSpots.append("Rupturas concentradas en \(weekdayDisplayName(weakWeekday)).")
        } else if brokenEvents.count > 0 {
            weakSpots.append("Rupturas detectadas, sin día dominante.")
        } else {
            weakSpots.append("Sin rupturas concentradas esta semana.")
        }
        weakSpots.append(appModeAdjustmentText(profile: selectionProfile, modeName: modeName))

        var recommendations: [String] = []
        if let weakHour {
            recommendations.append("Activa Blank a las \(activationTimeText(before: weakHour)).")
        } else if let bestHour {
            recommendations.append("Activa Blank 10 min antes de las \(String(format: "%02d:00", bestHour)).")
        } else {
            recommendations.append("Elige una franja fija para medir mejor.")
        }
        if brokenEvents.count > 0 {
            recommendations.append("Reduce el siguiente bloqueo si aparece emergencia.")
        } else {
            recommendations.append("Mantén el mismo modo si esta semana no necesitaste emergencia.")
        }
        if selectionProfile.totalAverage < 3 {
            recommendations.append("Añade al menos 3 apps o categorías al modo principal.")
        } else {
            recommendations.append("No cambies demasiadas apps a la vez.")
        }

        let goal: String
        if brokenEvents.count > 0 {
            goal = "3 bloqueos sin emergencia en tu franja más débil."
        } else if weeklySessions.count < 5 {
            goal = "Llegar a 5 sesiones protegidas."
        } else {
            goal = "Subir un 15% el tiempo protegido sin emergencia."
        }

        let plan = weeklyPlan(
            weakHour: weakHour,
            bestHour: bestHour,
            modeName: modeName,
            brokenCount: brokenEvents.count
        )

        return WeeklyAIReport(
            summary: "Generado con tus sesiones reales de esta semana.",
            patterns: Array(patterns.prefix(3)),
            weakSpots: Array(weakSpots.prefix(3)),
            recommendations: Array(recommendations.prefix(3)),
            goal: goal,
            plan: plan
        )
    }

    private func weeklyPlan(
        weakHour: Int?,
        bestHour: Int?,
        modeName: String?,
        brokenCount: Int
    ) -> [String] {
        let mode = modeName ?? "principal"
        let targetHour = weakHour ?? bestHour
        let firstBlock: String
        if let targetHour {
            firstBlock = "3 días: activa Blank a las \(activationTimeText(before: targetHour))."
        } else {
            firstBlock = "3 días: bloque de 25 min a la misma hora."
        }

        let secondBlock = "Modo \(mode): mantén las mismas apps."
        let thirdBlock = brokenCount > 0
            ? "Si aparece emergencia, baja duración antes de repetir."
            : "Domingo: revisa si puedes subir un bloque."

        return [firstBlock, secondBlock, thirdBlock]
    }

    private func mostCommonHour(from events: [BlankUsageEvent], sessions: [BlankSession]) -> Int? {
        mostCommonValue(events.map(\.localHour) + sessions.compactMap(\.localStartHour))
    }

    private func mostCommonWeekday(from events: [BlankUsageEvent], sessions: [BlankSession]) -> Int? {
        mostCommonValue(events.map(\.weekday) + sessions.compactMap(\.startWeekday))
    }

    private func mostCommonModeName(
        from sessions: [BlankSession],
        events: [BlankUsageEvent],
        progress: BlankProgressReport
    ) -> String? {
        let sessionNames = sessions.compactMap { $0.modeName }
        let eventNames = events.compactMap { $0.modeName }
        return mostCommonValue(sessionNames + eventNames) ?? progress.modeActivity.first?.name
    }

    private func averageSelectionProfile(from events: [BlankUsageEvent], sessions: [BlankSession]) -> SelectionProfile {
        let snapshots = events.map(\.selectionSnapshot) + sessions.compactMap(\.selectionSnapshot)
        let activeSnapshots = snapshots.filter { $0.totalCount > 0 }
        guard !activeSnapshots.isEmpty else {
            return SelectionProfile(applicationAverage: 1, categoryAverage: 1, webDomainAverage: 0)
        }

        let count = activeSnapshots.count
        let appTotal = activeSnapshots.reduce(0) { $0 + $1.applicationCount }
        let categoryTotal = activeSnapshots.reduce(0) { $0 + $1.categoryCount }
        let webTotal = activeSnapshots.reduce(0) { $0 + $1.webDomainCount }
        return SelectionProfile(
            applicationAverage: appTotal / count,
            categoryAverage: categoryTotal / count,
            webDomainAverage: webTotal / count
        )
    }

    private func appModeAdjustmentText(profile: SelectionProfile, modeName: String?) -> String {
        let mode = modeName ?? "principal"
        if profile.totalAverage < 3 {
            return "Refuerza el modo \(mode) con más apps o categorías."
        }
        if profile.applicationAverage == 0 {
            return "Añade apps concretas si una categoría es demasiado amplia."
        }
        if profile.categoryAverage == 0 {
        return "Agrupa apps parecidas en una categoría si repites ajustes."
        }
        return "Mantén apps/modos una semana más antes de cambiar."
    }

    private func hourRangeText(_ hour: Int) -> String {
        "\(String(format: "%02d:00", hour))-\(String(format: "%02d:00", (hour + 1) % 24))"
    }

    private func activationTimeText(before hour: Int) -> String {
        String(format: "%02d:50", (hour + 23) % 24)
    }

    private func mostCommonValue<T: Hashable>(_ values: [T]) -> T? {
        let counts = values.reduce(into: [T: Int]()) { counts, value in
            counts[value, default: 0] += 1
        }
        return counts.max { lhs, rhs in lhs.value < rhs.value }?.key
    }

    private func weekdayDisplayName(_ weekday: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        let symbols = formatter.weekdaySymbols ?? []
        guard symbols.indices.contains(weekday - 1) else { return "esta semana" }
        return symbols[weekday - 1].capitalized(with: Locale(identifier: "es_ES"))
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

    private func formatCompactDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = max(0, Int(duration / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours == 0 {
            return "\(minutes)m"
        }
        if minutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(minutes)m"
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

private struct WeeklyAIReport {
    let summary: String
    let patterns: [String]
    let weakSpots: [String]
    let recommendations: [String]
    let goal: String
    let plan: [String]
}

private struct DailyAISummary {
    let status: String
    let today: String
    let signal: String
    let nextAction: String
}

private struct SelectionProfile {
    let applicationAverage: Int
    let categoryAverage: Int
    let webDomainAverage: Int

    var totalAverage: Int {
        applicationAverage + categoryAverage + webDomainAverage
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
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.28))
                    BlankGlassCornerHighlight(width: 112, height: 42, xOffset: -120, yOffset: -23)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
                .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(BlankColors.glassBorder, lineWidth: 1)
            }
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

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
