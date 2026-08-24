import SwiftUI
import UIKit

struct ReportView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var healthKitStore = HealthKitStore()
    @State private var selectedHeroPage = 0
    @AppStorage("blankWeeklyAIGoal", store: BlankSharedState.defaults) private var storedWeeklyGoal = ""
    @AppStorage("blankWeeklyAIPlanFirst", store: BlankSharedState.defaults) private var storedPlanFirst = ""
    @AppStorage("blankWeeklyAIPlanSecond", store: BlankSharedState.defaults) private var storedPlanSecond = ""
    @AppStorage("blankWeeklyAIPlanThird", store: BlankSharedState.defaults) private var storedPlanThird = ""

    private var reportPrimary: Color { sessionStore.isBlankActive ? Color.white : BlankColors.ink }
    private var reportSecondary: Color { sessionStore.isBlankActive ? Color.white.opacity(0.70) : BlankColors.mutedInk }
    private var accentBlue: Color { Color(red: 0.25, green: 0.55, blue: 0.95) }
    private var recoveryGreen: Color { Color(red: 0.18, green: 0.78, blue: 0.38) }
    private var sleepBlue: Color { Color(red: 0.18, green: 0.48, blue: 0.95) }
    private var activityOrange: Color { Color(red: 0.92, green: 0.50, blue: 0.16) }

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
        let diagnosis = DigitalWellnessAI.currentDiagnosis(
            events: sessionStore.usageEvents,
            sessions: sessionStore.sessions,
            selectionCount: sessionStore.selectionCount
        )
        let healthContext = healthRecoveryContext(summaries: healthKitStore.summaries)
        let healthInsights = healthDigitalWellnessInsights(
            summaries: healthKitStore.summaries,
            sessions: sessionStore.sessions,
            events: sessionStore.usageEvents,
            context: healthContext
        )
        let controlForecast = healthControlForecast(
            context: healthContext,
            events: sessionStore.usageEvents,
            sessions: sessionStore.sessions,
            diagnosis: diagnosis
        )

        List {
            VStack(alignment: .center, spacing: 22) {
                    reportHeader()

                    controlDashboardCapsule(
                        forecast: controlForecast,
                        savedTime: savedTime,
                        totalFocusTime: totalFocusTime,
                        context: healthContext
                    )

                    v3SystemCapsule(system: sessionStore.digitalWellnessV3)

                    healthAccessCapsule()

                    if hasProgress {
                        weeklyVisualCapsule(
                            activityDays: progress.recentActivity,
                            weekly: weekly
                        )

                        statsDetailsCapsule(
                            summary: dailyAISummary(
                                events: sessionStore.usageEvents,
                                sessions: sessionStore.sessions,
                                progress: progress
                            ),
                            report: weeklyAIReport(
                                events: sessionStore.usageEvents,
                                sessions: sessionStore.sessions,
                                progress: progress,
                                healthContext: healthContext
                            ),
                            forecast: controlForecast,
                            healthInsights: healthInsights,
                            weekly: weekly,
                            progress: progress,
                            emergencyUnlocksRemaining: sessionStore.emergencyUnlocksRemaining
                        )
                    } else {
                        emptyState()
                    }

                    #if DEBUG
                    aiDemoDataButton()
                    #endif

                    Text("For digital wellness only. Blanked does not provide medical diagnosis.")
                        .font(.caption2)
                        .foregroundStyle(reportSecondary.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
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
        .background(ReportLiquidBackground(isActive: sessionStore.isBlankActive).ignoresSafeArea())
        .foregroundStyle(reportPrimary)
        .preferredColorScheme(sessionStore.isBlankActive ? .dark : .light)
        .onAppear {
            healthKitStore.refresh()
        }
    }

    private func reportHeader() -> some View {
        TopSheetHeader(
            title: "Digital Wellness",
            subtitle: "Understand your patterns\nand follow your next best block.",
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

                Text("Time Recovered")
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

    private func controlDashboardCapsule(
        forecast: ControlForecast,
        savedTime: TimeInterval,
        totalFocusTime: TimeInterval,
        context: HealthRecoveryContext
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 18) {
                controlRiskRing(forecast: forecast)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Control today", systemImage: "sparkle.magnifyingglass")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(reportSecondary)

                    Text(forecast.riskLabel)
                        .font(.blankInter(size: 34, weight: .semibold, relativeTo: .title))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(forecast.windowText)
                        .font(.blankInter(size: 15, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(accentBlue.opacity(0.95))
                        .lineLimit(1)
                }
            }

            keyMetricStrip(
                savedTime: savedTime,
                totalFocusTime: totalFocusTime,
                forecast: forecast
            )

            controlDriverBars(forecast: forecast, context: context)

            todayMoveCard(forecast: forecast)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .liquidGlass(cornerRadius: 28)
    }

    private func controlRiskRing(forecast: ControlForecast) -> some View {
        ZStack {
            Circle()
                .stroke(reportPrimary.opacity(0.08), lineWidth: 11)

            Circle()
                .trim(from: 0, to: CGFloat(forecast.riskPercent) / 100)
                .stroke(
                    AngularGradient(
                        colors: [
                            forecastColor(forecast.level).opacity(0.40),
                            forecastColor(forecast.level),
                            forecastColor(forecast.level).opacity(0.72)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 11, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text("\(forecast.riskPercent)")
                    .font(.blankInter(size: 29, weight: .semibold, relativeTo: .title3))
                    .lineLimit(1)
                Text("%")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(reportSecondary)
            }
        }
        .frame(width: 112, height: 112)
        .accessibilityLabel("Control risk \(forecast.riskPercent) percent")
    }

    private func keyMetricStrip(
        savedTime: TimeInterval,
        totalFocusTime: TimeInterval,
        forecast: ControlForecast
    ) -> some View {
        HStack(spacing: 10) {
            keyMetricTile(title: "Recovered", value: formatDuration(savedTime), tint: recoveryGreen, symbol: "arrow.counterclockwise")
            keyMetricTile(title: "Blanked", value: formatDuration(totalFocusTime), tint: accentBlue, symbol: "shield.fill")
            keyMetricTile(title: "Risk", value: "\(forecast.riskPercent)%", tint: forecastColor(forecast.level), symbol: "waveform.path.ecg")
        }
    }

    private func keyMetricTile(title: String, value: String, tint: Color, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(reportSecondary)
                    .lineLimit(1)
            }

            Text(value)
                .font(.blankInter(size: 20, weight: .semibold, relativeTo: .body))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.10))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        }
    }

    private func controlDriverBars(forecast: ControlForecast, context: HealthRecoveryContext) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Main drivers")
                .font(.caption.weight(.semibold))
                .foregroundStyle(reportSecondary)

            driverBar(title: "Phone control", value: max(0, 100 - forecast.riskPercent), tint: accentBlue)
            driverBar(title: "Recovery", value: context.recoveryScore ?? 50, tint: recoveryGreen)
            driverBar(title: "Sleep", value: sleepDriverScore(context.averageSleepMinutes), tint: sleepBlue)
            driverBar(title: "Activity", value: activityDriverScore(context.averageSteps), tint: activityOrange)
        }
    }

    private func driverBar(title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(reportPrimary.opacity(0.82))
                Spacer()
                Text("\(value)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(reportSecondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(reportPrimary.opacity(0.08))
                    Capsule()
                        .fill(tint.opacity(0.82))
                        .frame(width: proxy.size.width * CGFloat(max(0, min(100, value))) / 100)
                }
            }
            .frame(height: 7)
        }
    }

    private func todayMoveCard(forecast: ControlForecast) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Next best block", systemImage: "arrow.forward.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(reportSecondary)

            Text(forecast.actionText)
                .font(.blankInter(size: 14, weight: .medium, relativeTo: .subheadline))
                .foregroundStyle(reportPrimary.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)

            if sessionStore.isBlankActive {
                Text("Blanked is active")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(reportSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background { Capsule().fill(Color.white.opacity(0.16)) }
            } else {
                Button {
                    sessionStore.activateBlank()
                } label: {
                    Text("Activate Blanked")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(reportPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background { Capsule().fill(Color.white.opacity(0.24)) }
                }
                .buttonStyle(.plain)

                Button {
                    sessionStore.activateBlank(durationMinutes: forecast.durationMinutes)
                } label: {
                    Text("Try \(forecast.durationMinutes) min block")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(reportSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(forecastColor(forecast.level).opacity(0.10))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(forecastColor(forecast.level).opacity(0.18), lineWidth: 1)
        }
    }

    private func healthAccessCapsule() -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Health context", systemImage: "heart.text.square.fill")
                        .font(.blankInter(size: 16, weight: .medium, relativeTo: .headline))
                    Text(healthSignalsSubtitle)
                        .font(.caption)
                        .foregroundStyle(reportSecondary)
                }

                Spacer()

                healthStatePill()
            }

            if case .notRequested = healthKitStore.state {
                Button {
                    healthKitStore.requestAccess()
                } label: {
                    Text("Connect Apple Health")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(reportPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background { Capsule().fill(Color.white.opacity(0.20)) }
                }
                .buttonStyle(.plain)
            } else if case .failed(_) = healthKitStore.state {
                Button {
                    healthKitStore.requestAccess()
                } label: {
                    Text("Retry Apple Health")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(reportPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background { Capsule().fill(Color.white.opacity(0.20)) }
                }
                .buttonStyle(.plain)
            } else if case .connected = healthKitStore.state {
                Button {
                    healthKitStore.disconnect()
                } label: {
                    Text("Stop using Apple Health")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(reportSecondary)
                }
                .buttonStyle(.plain)
            }

            Button {
                healthKitStore.loadSyntheticAppleWatchData()
            } label: {
                Text("Load Apple Watch demo data")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(reportSecondary)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .liquidGlass(cornerRadius: 24)
    }

    private func healthStatePill() -> some View {
        let text: String
        switch healthKitStore.state {
        case .connected:
            text = healthKitStore.summaries.isEmpty ? "No data" : "On"
        case .requesting:
            text = "Opening"
        case .unavailable:
            text = "Off"
        case .notRequested:
            text = "Optional"
        case .failed(_):
            text = "Retry"
        }

        return Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(reportPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background { Capsule().fill(Color.white.opacity(0.16)) }
    }

    private func weeklyVisualCapsule(activityDays: [BlankActivityDay], weekly: BlankWeeklyReport) -> some View {
        let days = Array(activityDays.suffix(7))
        let maxValue = max(days.map(\.totalFocusTime).max() ?? 0, 30 * 60)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("This week")
                    .font(.blankInter(size: 17, weight: .medium, relativeTo: .headline))
                Spacer()
                Label("\(weekly.completedSessionCount) starts", systemImage: "bolt.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentBlue)
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(days) { day in
                    weekBar(day: day, maxValue: maxValue)
                }
            }
            .frame(height: 122)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .liquidGlass(cornerRadius: 28)
    }

    private func weekBar(day: BlankActivityDay, maxValue: TimeInterval) -> some View {
        let ratio = max(0.06, min(1, day.totalFocusTime / maxValue))

        return VStack(spacing: 7) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(day.totalFocusTime > 0 ? accentBlue.opacity(0.88) : reportPrimary.opacity(0.12))
                .frame(height: CGFloat(ratio) * 82)

            Text(shortWeekdayName(for: day.date))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(reportSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func statsDetailsCapsule(
        summary: DailyAISummary,
        report: WeeklyAIReport,
        forecast: ControlForecast,
        healthInsights: [String],
        weekly: BlankWeeklyReport,
        progress: BlankProgressReport,
        emergencyUnlocksRemaining: Int
    ) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                dailySummaryRow(title: "Today", value: summary.today)
                dailySummaryRow(title: "Signal", value: summary.signal)
                dailySummaryRow(title: "Next", value: summary.nextAction)

                subtleDivider()

                aiReportSection(title: "Why", items: forecast.reasons, tint: accentBlue)
                aiReportSection(title: "Plan", items: forecast.plan, tint: recoveryGreen)
                aiReportSection(title: "Patterns", items: report.patterns.prefix(2).map { $0 }, tint: sleepBlue)
                aiReportSection(title: "Health", items: healthInsights.prefix(2).map { $0 }, tint: activityOrange)

                subtleDivider()

                VStack(spacing: 10) {
                    metricRow(title: "Best day", value: bestDayText(report: weekly), caption: bestDayCaption(report: weekly))
                    metricRow(title: "Most used mode", value: mostUsedModeName(progress: progress), caption: mostUsedModeCaption(progress: progress))
                    metricRow(title: "Emergencies", value: "\(usedEmergencyUnlocks(emergencyUnlocksRemaining))/3", caption: emergencyCaption(emergencyUnlocksRemaining))
                }
            }
            .padding(.top, 10)
        } label: {
            HStack {
                Label("Details", systemImage: "slider.horizontal.3")
                    .font(.blankInter(size: 16, weight: .medium, relativeTo: .headline))
                Spacer()
                Text("Signals and plan")
                    .font(.caption)
                    .foregroundStyle(reportSecondary)
            }
        }
        .padding(17)
        .liquidGlass(cornerRadius: 28)
    }

    private func v3SystemCapsule(system: DigitalWellnessV3System) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Adaptive Plan")
                    .font(.blankInter(size: 17, weight: .medium, relativeTo: .headline))
                Text(system.weeklyInsight)
                    .font(.caption)
                    .foregroundStyle(reportSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                statCapsule(title: "Adherence", value: "\(system.profile.adherenceScore)/100", caption: "Current plan score", minHeight: 84)
                statCapsule(title: "Risk", value: "\(system.forecast.riskScore)/100", caption: system.forecast.riskWindow, minHeight: 84)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(system.plan.weeklyGoal)
                    .font(.blankInter(size: 13, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(reportPrimary.opacity(0.90))
                    .fixedSize(horizontal: false, vertical: true)
                Text(system.plan.adjustmentReason)
                    .font(.blankInter(size: 13, relativeTo: .footnote))
                    .foregroundStyle(reportSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(system.forecast.recommendedAction)
                    .font(.blankInter(size: 13, relativeTo: .footnote))
                    .foregroundStyle(reportPrimary.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .liquidGlass(cornerRadius: 28)
    }

    private func sleepDriverScore(_ minutes: Int?) -> Int {
        guard let minutes else { return 50 }
        return max(0, min(100, Int(Double(minutes) / Double(8 * 60) * 100)))
    }

    private func activityDriverScore(_ steps: Int?) -> Int {
        guard let steps else { return 50 }
        return max(0, min(100, Int(Double(steps) / 8000 * 100)))
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
            Text("Time Blanked")
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
            Text("Weekly Trend")
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
            Text("Behavior")
                .font(.blankInter(size: 18, weight: .medium, relativeTo: .headline))

            VStack(spacing: 10) {
                statCapsule(title: "Best day", value: bestDayText(report: weekly), caption: bestDayCaption(report: weekly), minHeight: 86)
                statCapsule(title: "Most used mode", value: mostUsedModeName(progress: progress), caption: mostUsedModeCaption(progress: progress), minHeight: 86)
                statCapsule(title: "Emergencies", value: "\(usedEmergencyUnlocks(emergencyUnlocksRemaining))/3", caption: emergencyCaption(emergencyUnlocksRemaining), minHeight: 86)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .liquidGlass(cornerRadius: 28)
    }

    private func dailyAISummaryCapsule(summary: DailyAISummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Daily Summary")
                    .font(.blankInter(size: 17, weight: .medium, relativeTo: .headline))
                Text(summary.status)
                    .font(.caption)
                    .foregroundStyle(reportSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                dailySummaryRow(title: "Today", value: summary.today)
                dailySummaryRow(title: "Signal", value: summary.signal)
                dailySummaryRow(title: "Next", value: summary.nextAction)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .liquidGlass(cornerRadius: 28)
    }

    private func digitalWellnessDiagnosisCapsule(
        diagnosis: DigitalWellnessDiagnosis,
        recommendation: SmartBlockRecommendation
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(diagnosis.archetype)
                    .font(.blankInter(size: 19, weight: .medium, relativeTo: .headline))
                Text(diagnosis.riskTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(reportSecondary)
                Text(diagnosis.riskBody)
                    .font(.blankInter(size: 13, relativeTo: .footnote))
                    .foregroundStyle(reportPrimary.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                statCapsule(title: "Risk window", value: diagnosis.weakMoment, caption: "First plan", minHeight: 82)
                statCapsule(title: "Smart block", value: "\(recommendation.durationMinutes)m", caption: recommendation.title, minHeight: 82)
            }

            aiReportSection(
                title: "7-day plan",
                items: diagnosis.plan.prefix(3).map { "\($0.title): \($0.action)" }
            )

            Text("Full plan adapts as real sessions and emergency unlocks appear.")
                .font(.caption2)
                .foregroundStyle(reportSecondary.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .liquidGlass(cornerRadius: 28)
    }

    private func healthSignalsCapsule(
        insights: [String],
        context: HealthRecoveryContext,
        forecast: ControlForecast
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Control Forecast")
                    .font(.blankInter(size: 17, weight: .medium, relativeTo: .headline))
                Text(healthSignalsSubtitle)
                    .font(.caption)
                    .foregroundStyle(reportSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                healthKitStore.loadSyntheticAppleWatchData()
            } label: {
                Text("Load Apple Watch demo data")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(reportPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        Capsule()
                            .fill(Color.white.opacity(0.20))
                    }
                    .overlay {
                        Capsule()
                            .stroke(reportPrimary.opacity(0.10), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)

            switch healthKitStore.state {
            case .unavailable:
                Text("Apple Health is not available on this device.")
                    .font(.blankInter(size: 13, relativeTo: .footnote))
                    .foregroundStyle(reportPrimary.opacity(0.84))
                    .fixedSize(horizontal: false, vertical: true)
            case .notRequested, .failed(_):
                Button {
                    healthKitStore.requestAccess()
                } label: {
                    Text("Connect Apple Health")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(reportPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background {
                            Capsule()
                                .fill(Color.white.opacity(0.24))
                        }
                        .overlay {
                            Capsule()
                                .stroke(reportPrimary.opacity(0.08), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            case .requesting:
                Text("Opening Apple Health permissions...")
                    .font(.blankInter(size: 13, relativeTo: .footnote))
                    .foregroundStyle(reportPrimary.opacity(0.84))
            case .connected:
                if healthKitStore.summaries.isEmpty {
                    Text("Connected. Insights appear after Apple Health has sleep, activity or heart data.")
                        .font(.blankInter(size: 13, relativeTo: .footnote))
                        .foregroundStyle(reportPrimary.opacity(0.84))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    controlForecastCard(forecast)

                    if let latest = healthKitStore.summaries.last {
                        HStack(spacing: 10) {
                            statCapsule(title: "Sleep", value: sleepValue(latest.sleepMinutes), caption: "Last signal", minHeight: 82)
                            statCapsule(title: "Steps", value: stepsValue(latest.steps), caption: "Last signal", minHeight: 82)
                        }
                    }
                    HStack(spacing: 10) {
                        statCapsule(title: "Recovery", value: recoveryValue(context.recoveryScore), caption: "Context only", minHeight: 82)
                        statCapsule(title: "Sleep drift", value: driftValue(context.bedtimeDriftMinutes), caption: "Recent timing", minHeight: 82)
                    }
                    aiReportSection(title: "Why", items: forecast.reasons)
                    aiReportSection(title: "Unblank Pattern", items: unblankPatternInsights(events: sessionStore.usageEvents, sessions: sessionStore.sessions))
                    aiReportSection(title: "Intervention Learning", items: interventionLearningInsights(events: sessionStore.usageEvents, sessions: sessionStore.sessions))
                    aiReportSection(title: "Adaptive Plan", items: forecast.plan)
                    aiReportSection(title: "Wellness insights", items: insights)

                    Button {
                        healthKitStore.disconnect()
                    } label: {
                        Text("Stop using Apple Health")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(reportSecondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }

            Text("For digital wellness only. Blanked does not provide medical diagnosis.")
                .font(.caption2)
                .foregroundStyle(reportSecondary.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .liquidGlass(cornerRadius: 28)
    }

    private func controlForecastCard(_ forecast: ControlForecast) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(forecast.riskLabel)
                    .font(.blankInter(size: 26, weight: .semibold, relativeTo: .title2))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 8)

                Text("\(forecast.riskPercent)%")
                    .font(.blankInter(size: 20, weight: .semibold, relativeTo: .headline))
                    .foregroundStyle(forecastColor(forecast.level))
                    .lineLimit(1)
            }

            Text(forecast.headline)
                .font(.blankInter(size: 14, weight: .medium, relativeTo: .subheadline))
                .foregroundStyle(reportPrimary.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 5) {
                forecastMiniRow(title: "Best window", value: forecast.windowText)
                forecastMiniRow(title: "Do this", value: forecast.actionText)
            }

            if sessionStore.isBlankActive {
                Text("Protection is already active.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(reportSecondary)
            } else {
                Button {
                    sessionStore.activateBlank()
                } label: {
                    Text("Activate Blanked")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(reportPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background {
                            Capsule()
                                .fill(Color.white.opacity(0.24))
                        }
                        .overlay {
                            Capsule()
                                .stroke(reportPrimary.opacity(0.08), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)

                Button {
                    sessionStore.activateBlank(durationMinutes: forecast.durationMinutes)
                } label: {
                    Text("Try \(forecast.durationMinutes) min block")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(reportSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(forecastColor(forecast.level).opacity(0.12))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(forecastColor(forecast.level).opacity(0.22), lineWidth: 1)
        }
    }

    private func forecastMiniRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(reportSecondary)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(.blankInter(size: 13, relativeTo: .footnote))
                .foregroundStyle(reportPrimary.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func forecastColor(_ level: ControlForecast.Level) -> Color {
        switch level {
        case .low:
            return recoveryGreen
        case .medium:
            return activityOrange
        case .high:
            return Color(red: 0.95, green: 0.22, blue: 0.22)
        }
    }

    private func dailySummaryRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: dailySummarySymbol(title))
                .font(.caption.weight(.semibold))
                .foregroundStyle(reportSecondary)
            Text(value)
                .font(.blankInter(size: 14, weight: .medium, relativeTo: .footnote))
                .foregroundStyle(reportPrimary.opacity(0.90))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(reportPrimary.opacity(0.055))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(reportPrimary.opacity(0.07), lineWidth: 1)
        }
    }

    private func dailySummarySymbol(_ title: String) -> String {
        switch title {
        case "Today":
            return "calendar"
        case "Signal":
            return "waveform"
        case "Next":
            return "arrow.forward.circle"
        default:
            return "circle"
        }
    }

    private func weeklyAIReportCapsule(report: WeeklyAIReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Digital Wellness Report")
                    .font(.blankInter(size: 17, weight: .medium, relativeTo: .headline))
                Text(report.summary)
                    .font(.caption)
                    .foregroundStyle(reportSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            aiReportSection(title: "Patterns", items: report.patterns)
            aiReportSection(title: "Apps and Windows", items: report.weakSpots)
            aiReportSection(title: "Recommendations", items: report.recommendations)

            VStack(alignment: .leading, spacing: 6) {
                Text("Goal")
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
                placeholder: report.plan[safe: 0] ?? "Short block in your weak window.",
                text: Binding(
                    get: { storedPlanFirst.isEmpty ? (report.plan[safe: 0] ?? "") : storedPlanFirst },
                    set: { storedPlanFirst = $0 }
                )
            )
            editableAIField(
                placeholder: report.plan[safe: 1] ?? "Repeat the main mode unchanged.",
                text: Binding(
                    get: { storedPlanSecond.isEmpty ? (report.plan[safe: 1] ?? "") : storedPlanSecond },
                    set: { storedPlanSecond = $0 }
                )
            )
            editableAIField(
                placeholder: report.plan[safe: 2] ?? "Review the result at the end of the week.",
                text: Binding(
                    get: { storedPlanThird.isEmpty ? (report.plan[safe: 2] ?? "") : storedPlanThird },
                    set: { storedPlanThird = $0 }
                )
            )

            Button("Reset proposal") {
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
            Text("Load AI demo data")
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
        .accessibilityLabel("Load AI demo data")
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

    private func aiReportSection(title: String, items: [String], tint: Color? = nil) -> some View {
        let sectionTint = tint ?? reportPrimary.opacity(0.72)

        return VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(reportSecondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(sectionTint)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(sectionTint.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(sectionTint.opacity(0.14), lineWidth: 1)
        }
    }

    private func nextStepCard(progress: BlankProgressReport) -> some View {
        VStack(alignment: .center, spacing: 8) {
            Text("Next improvement")
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
                metricRow(title: "Time blanked", value: formatDuration(totalFocusTime), caption: "Total protected")
                subtleDivider()
                metricRow(title: "Total sessions", value: "\(totalSessionCount)", caption: "Since the beginning")
                subtleDivider()
                metricRow(title: "Best day", value: bestDayText(report: weekly), caption: bestDayCaption(report: weekly))
                subtleDivider()
                metricRow(title: "Rescues used", value: "\(usedEmergencyUnlocks(emergencyUnlocksRemaining))/3", caption: emergencyCaption(emergencyUnlocksRemaining))

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
            Text("View details")
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
                title: "Risk moment",
                value: riskMomentValue(activityDays: progress.recentActivity),
                caption: riskMomentCaption(activityDays: progress.recentActivity)
            )
            subtleDivider()
            metricRow(
                title: "Protection quality",
                value: "\(protectionQualityScore(weekly: weekly, progress: progress, emergencyUnlocksRemaining: emergencyUnlocksRemaining))/100",
                caption: protectionQualityCaption(weekly: weekly, emergencyUnlocksRemaining: emergencyUnlocksRemaining)
            )
            subtleDivider()
            metricRow(
                title: "Recovered control",
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
            metricRow(title: "Sessions", value: "\(weekly.completedSessionCount)", caption: "Protected this week")
            subtleDivider()
            metricRow(title: "Average protected", value: formatDuration(weekly.averageSessionDuration), caption: "Per real session")
            subtleDivider()
            metricRow(title: "Streak", value: "\(progress.currentStreakDays)d", caption: "Days with Blank")
            subtleDivider()
            metricRow(title: "Best day", value: bestDayText(report: weekly), caption: bestDayCaption(report: weekly))
            subtleDivider()
            metricRow(title: "Emergencies", value: "\(usedEmergencyUnlocks(emergencyUnlocksRemaining))/3", caption: emergencyCaption(emergencyUnlocksRemaining))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
        .liquidGlass(cornerRadius: 22)
    }

    private func metricRow(title: String, value: String, caption: String) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.blankInter(size: 15, weight: .medium, relativeTo: .body))

                Text(caption)
                    .font(.caption)
                    .foregroundStyle(reportSecondary)
            }

            Spacer(minLength: 12)

            Text(value)
                .font(.blankInter(size: 19, weight: .semibold, relativeTo: .headline))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(reportPrimary.opacity(0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(reportPrimary.opacity(0.065), lineWidth: 1)
        }
    }

    private func modesSection(_ activities: [BlankModeActivity]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Modes this week")
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

                Text("\(activity.sessionCount) sessions")
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
            .fill(reportPrimary.opacity(0.055))
            .frame(height: 1)
    }

    private func emptyState() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your recovered time will appear here.")
                .font(.headline.weight(.semibold))

            Text("Start Blank and come back after your first protected session.")
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
            return "Blank is already measuring this session. Signals become more useful when it ends."
        }

        if savedTime >= 8 * 60 * 60 {
            return "You have recovered almost half a day for yourself."
        }

        if savedTime >= 4 * 60 * 60 {
            return "You have recovered several hours that used to disappear."
        }

        if savedTime >= 60 * 60 {
            return "You have recovered more than an hour without turning it into another screen."
        }

        if progress.currentStreakDays >= 3 {
            return "Blank has protected you for \(progress.currentStreakDays) days in a row."
        }

        if totalSessionCount >= 5 {
            return "There are already \(totalSessionCount) moments where you did not go back to the loop."
        }

        return "You have recovered real time without turning it into another screen."
    }

    private func nextStepText(progress: BlankProgressReport) -> String {
        guard let riskyDay = riskiestDay(activityDays: progress.recentActivity) else {
            return "Complete a few more sessions and Blank will detect which moment to reinforce."
        }

        let dayName = weekdayName(for: riskyDay.date).lowercased(with: Locale(identifier: "en_US"))
        if riskyDay.sessionCount > 1 {
            return "Your risk moment is usually \(dayName). Start Blank before that window."
        }

        return "\(dayName) was your most sensitive point. Reinforce that window before the impulse appears."
    }

    private func mostUsedModeName(progress: BlankProgressReport) -> String {
        progress.modeActivity.first?.name ?? "No data"
    }

    private func mostUsedModeCaption(progress: BlankProgressReport) -> String {
        guard let mode = progress.modeActivity.first else {
            return "This week"
        }
        return "\(formatDuration(mode.totalFocusTime)) · \(mode.sessionCount) sessions"
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
        "Time saved: \(formatDuration(cappedSavedTime(totalFocusTime: totalFocusTime, sessionCount: sessionCount))) estimated with 7 min per session and 10% of protected time, capped at real time in Blank."
    }

    private var healthSignalsSubtitle: String {
        switch healthKitStore.state {
        case .connected:
            return "Optional Apple Health context for your digital habits."
        case .notRequested:
            return "Optional. Sleep, activity and heart signals stay local."
        case .requesting:
            return "Waiting for Apple Health permission."
        case .unavailable:
            return "Apple Health is unavailable here."
        case .failed(_):
            return "Permission can be retried any time."
        }
    }

    private func sleepValue(_ minutes: Int?) -> String {
        guard let minutes else { return "No data" }
        let hours = minutes / 60
        let remaining = minutes % 60
        return remaining == 0 ? "\(hours)h" : "\(hours)h \(remaining)m"
    }

    private func stepsValue(_ steps: Int?) -> String {
        guard let steps else { return "No data" }
        if steps >= 1000 {
            return String(format: "%.1fk", Double(steps) / 1000)
        }
        return "\(steps)"
    }

    private func recoveryValue(_ score: Int?) -> String {
        guard let score else { return "Learning" }
        if score < 45 { return "Light" }
        if score >= 75 { return "Strong" }
        return "Stable"
    }

    private func driftValue(_ minutes: Int?) -> String {
        guard let minutes else { return "Learning" }
        if minutes < 60 { return "<1h" }
        let hours = minutes / 60
        let remaining = minutes % 60
        return remaining == 0 ? "\(hours)h" : "\(hours)h \(remaining)m"
    }

    private func healthDigitalWellnessInsights(
        summaries: [HealthDaySummary],
        sessions: [BlankSession],
        events: [BlankUsageEvent],
        context: HealthRecoveryContext
    ) -> [String] {
        let calendar = Calendar.current
        let recentSummaries = Array(summaries.suffix(7))
        guard !recentSummaries.isEmpty else {
            return [
                "Connect Apple Health to compare sleep and activity with your screen habit patterns.",
                "Blanked only uses this for digital wellness insights.",
                "No medical diagnosis is generated."
            ]
        }

        let sleepValues = recentSummaries.compactMap(\.sleepMinutes)
        let stepValues = recentSummaries.compactMap(\.steps)
        let hrvValues = recentSummaries.compactMap(\.hrvSDNN)
        let averageSleep = sleepValues.isEmpty ? nil : sleepValues.reduce(0, +) / sleepValues.count
        let averageSteps = stepValues.isEmpty ? nil : stepValues.reduce(0, +) / stepValues.count
        let averageHRV = hrvValues.isEmpty ? nil : hrvValues.reduce(0, +) / hrvValues.count
        let lowSleepDays = Set(recentSummaries.filter { ($0.sleepMinutes ?? 999) < 6 * 60 }.map { calendar.startOfDay(for: $0.date) })
        let brokenDays = Set(events.filter { $0.kind == .blockBroken || $0.endedReason == .emergency }.map { calendar.startOfDay(for: $0.occurredAt) })
        let nightSessionCount = sessions.filter { session in
            let hour = session.localStartHour ?? calendar.component(.hour, from: session.startedAt)
            return hour >= 21 || hour <= 3
        }.count

        var insights: [String] = []
        if let bedtimeDrift = context.bedtimeDriftMinutes, bedtimeDrift >= 75 {
            insights.append("Sleep timing is irregular. Keep tonight's block short and start it before your usual drift.")
        } else if !lowSleepDays.isDisjoint(with: brokenDays) {
            insights.append("Low-sleep days overlap with break attempts. Protect the evening window earlier.")
        } else if let averageSleep {
            insights.append("Average sleep signal: \(sleepValue(averageSleep)). Compare it with evening blocks this week.")
        } else {
            insights.append("Sleep data is not available yet. Evening patterns will improve when it appears.")
        }

        if let workoutMinutes = context.averageWorkoutMinutes, workoutMinutes >= 20 {
            insights.append("Higher-activity days are good candidates for your longer focus block.")
        } else if let averageSteps, averageSteps < 3500 {
            insights.append("Low-activity days may need shorter blocks and earlier starts.")
        } else if let averageSteps {
            insights.append("Average activity signal: \(stepsValue(averageSteps)) steps. Keep the same block window for cleaner learning.")
        } else {
            insights.append("Activity data is not available yet. Steps can help spot low-energy relapse days.")
        }

        if let score = context.recoveryScore, score < 45 {
            insights.append("Recovery context looks light. Use a simple block today instead of increasing difficulty.")
        } else if nightSessionCount > 0 {
            insights.append("Night blocks are active. Keep the final hour before sleep protected.")
        } else if let averageHRV {
            insights.append("HRV signal averages \(averageHRV) ms. Use it as context, not a medical score.")
        } else {
            insights.append("Heart signals are optional context for recovery, not a score or diagnosis.")
        }

        return Array(insights.prefix(3))
    }

    private func healthRecoveryContext(summaries: [HealthDaySummary]) -> HealthRecoveryContext {
        let recent = Array(summaries.suffix(7))
        let sleepValues = recent.compactMap(\.sleepMinutes)
        let stepsValues = recent.compactMap(\.steps)
        let workoutValues = recent.compactMap(\.workoutMinutes)
        let hrvValues = recent.compactMap(\.hrvSDNN)
        let restingHeartRateValues = recent.compactMap(\.restingHeartRate)
        let bedtimeValues = recent.compactMap(\.bedtimeMinute)
        let wakeValues = recent.compactMap(\.wakeMinute)

        let averageSleep = average(sleepValues)
        let averageSteps = average(stepsValues)
        let averageWorkoutMinutes = average(workoutValues)
        let averageHRV = average(hrvValues)
        let averageRestingHeartRate = average(restingHeartRateValues)
        let bedtimeDrift = circularMinuteDrift(bedtimeValues)
        let wakeDrift = circularMinuteDrift(wakeValues)

        var scoreParts: [Int] = []
        if let averageSleep {
            scoreParts.append(min(100, max(0, Int(Double(averageSleep) / (8 * 60) * 100))))
        }
        if let averageSteps {
            scoreParts.append(min(100, max(0, Int(Double(averageSteps) / 8000 * 100))))
        }
        if let averageWorkoutMinutes {
            scoreParts.append(min(100, max(0, Int(Double(averageWorkoutMinutes) / 30 * 100))))
        }
        if let bedtimeDrift {
            scoreParts.append(max(0, 100 - min(100, bedtimeDrift)))
        }
        if averageHRV != nil || averageRestingHeartRate != nil {
            scoreParts.append(70)
        }

        return HealthRecoveryContext(
            averageSleepMinutes: averageSleep,
            averageSteps: averageSteps,
            averageWorkoutMinutes: averageWorkoutMinutes,
            averageHRV: averageHRV,
            averageRestingHeartRate: averageRestingHeartRate,
            bedtimeDriftMinutes: bedtimeDrift,
            wakeDriftMinutes: wakeDrift,
            recoveryScore: average(scoreParts)
        )
    }

    private func phoneImpactInsights(
        context: HealthRecoveryContext,
        sessions: [BlankSession],
        events: [BlankUsageEvent]
    ) -> [String] {
        let calendar = Calendar.current
        let nightSessions = sessions.filter { session in
            let hour = session.localStartHour ?? calendar.component(.hour, from: session.startedAt)
            return hour >= 21 || hour <= 3
        }.count
        let breaks = events.filter { $0.kind == .blockBroken || $0.endedReason == .emergency }.count

        if nightSessions > 0, let bedtimeDrift = context.bedtimeDriftMinutes, bedtimeDrift >= 75 {
            return ["Late blocks and irregular sleep timing overlap. Treat the final hour as protected."]
        }
        if breaks > 0, let averageSleep = context.averageSleepMinutes, averageSleep < 6 * 60 {
            return ["Break attempts are appearing while sleep is short. Lower friction before increasing duration."]
        }
        if nightSessions > 0 {
            return ["Night protection is active. Keep measuring whether it improves sleep regularity."]
        }
        return ["Blanked is learning how your phone windows relate to sleep and energy."]
    }

    private func recoveryPatternInsights(context: HealthRecoveryContext, events: [BlankUsageEvent]) -> [String] {
        let brokenCount = events.filter { $0.kind == .blockBroken || $0.endedReason == .emergency }.count
        if let recoveryScore = context.recoveryScore, recoveryScore < 45 {
            return ["Recovery context is light. Choose consistency over intensity for the next block."]
        }
        if let averageWorkoutMinutes = context.averageWorkoutMinutes, averageWorkoutMinutes >= 20, brokenCount == 0 {
            return ["Higher-activity days look compatible with stronger protection windows."]
        }
        if let averageHRV = context.averageHRV {
            return ["HRV averages \(averageHRV) ms. Use it only as context for digital habits."]
        }
        return ["Recovery patterns need a few more Health samples before becoming useful."]
    }

    private func healthSuggestedNextStep(
        context: HealthRecoveryContext,
        events: [BlankUsageEvent],
        sessions: [BlankSession]
    ) -> String {
        if let recoveryScore = context.recoveryScore, recoveryScore < 45 {
            return "Tonight: start a 25-30 min block before your usual weak window."
        }
        if let weakHour = DigitalWellnessAI.weakHour(events: events, sessions: sessions) {
            return "Next block: start at \(activationTimeText(before: weakHour)) and keep the same apps."
        }
        if let bedtimeDrift = context.bedtimeDriftMinutes, bedtimeDrift >= 75 {
            return "This week: protect the same bedtime window for 3 nights."
        }
        return "Repeat your strongest window one more day before changing the plan."
    }

    private func healthControlForecast(
        context: HealthRecoveryContext,
        events: [BlankUsageEvent],
        sessions: [BlankSession],
        diagnosis: DigitalWellnessDiagnosis
    ) -> ControlForecast {
        let calendar = Calendar.current
        let now = Date()
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let recentEvents = events.filter {
            $0.occurredAt >= weekAgo
        }
        let manualUnblanks = recentEvents.filter { $0.endedReason == .manual }.count
        let emergencyBreaks = recentEvents.filter { $0.kind == .blockBroken || $0.endedReason == .emergency }.count
        let shortManualUnblanks = recentEvents.filter { event in
            event.endedReason == .manual && (event.duration ?? .greatestFiniteMagnitude) < 20 * 60
        }.count
        let weakHour = DigitalWellnessAI.weakHour(events: events, sessions: sessions, now: now) ?? diagnosis.recommendedHour
        let minutesToWeakWindow = minutesUntilNextHour(weakHour, now: now)

        var risk = 28
        var reasons: [String] = []
        var plan: [String] = []

        if let score = context.recoveryScore {
            if score < 45 {
                risk += 24
                reasons.append("Recovery looks light, so Blanked should reduce friction before the weak window.")
            } else if score >= 75 {
                risk -= 10
                reasons.append("Recovery looks strong enough to hold protection through a longer window.")
            }
        } else {
            risk += 8
            reasons.append("Blanked needs more Health samples to separate low-energy days from normal days.")
        }

        if let sleep = context.averageSleepMinutes {
            if sleep < 6 * 60 {
                risk += 18
                reasons.append("Recent sleep is short, which often makes automatic scrolling harder to resist.")
            } else if sleep >= 7 * 60 + 15 {
                risk -= 6
            }
        }

        if let drift = context.bedtimeDriftMinutes, drift >= 75 {
            risk += 12
            reasons.append("Sleep timing is drifting, so late-phone protection matters more tonight.")
        }

        if let steps = context.averageSteps, steps < 3500 {
            risk += 8
            reasons.append("Activity is low, so the plan should be simple: activate and stay protected.")
        } else if let workout = context.averageWorkoutMinutes, workout >= 25 {
            risk -= 5
        }

        if manualUnblanks > 0 {
            risk += min(28, manualUnblanks * 9)
            reasons.append("Recent hold-to-unblank exits are the main relapse signal Blanked is learning from.")
        }

        if shortManualUnblanks > 0 {
            risk += min(12, shortManualUnblanks * 6)
            reasons.append("Some exits happened early, which suggests the protection started too hard or too late.")
        }

        if emergencyBreaks > 0 {
            risk += min(16, emergencyBreaks * 6)
            reasons.append("Emergency exits add a stronger warning signal on top of manual unblanks.")
        }

        if minutesToWeakWindow <= 90 {
            risk += 14
            reasons.append("\(DigitalWellnessAI.hourRangeText(weakHour)) is close to your current high-risk window.")
        }

        let riskPercent = min(92, max(12, risk))
        let level: ControlForecast.Level
        let riskLabel: String
        if riskPercent >= 70 {
            level = .high
            riskLabel = "High risk"
        } else if riskPercent >= 45 {
            level = .medium
            riskLabel = "Medium risk"
        } else {
            level = .low
            riskLabel = "Low risk"
        }

        let duration: Int
        switch level {
        case .high:
            duration = 25
            plan.append("Activate Blanked before the weak window and keep it on through that window.")
            plan.append("Use the \(duration)-min block only if indefinite protection feels too heavy today.")
        case .medium:
            duration = max(30, min(45, diagnosis.initialBlockMinutes))
            plan.append("Protect the same window again so Blanked can learn whether it prevents manual unblanking.")
            plan.append("Optional: test a \(duration)-min block as a lighter version of full Blanked.")
        case .low:
            duration = max(45, diagnosis.initialBlockMinutes)
            plan.append("Use this as a strong control day: activate Blanked during your best window.")
            plan.append("Optional: try a \(duration)-min block to compare timed protection with indefinite Blanked.")
        }

        let actionText: String
        if minutesToWeakWindow <= 90 {
            actionText = "Activate Blanked at \(activationTimeText(before: weakHour)) and stay protected through the window."
        } else {
            actionText = "Protect \(DigitalWellnessAI.hourRangeText(weakHour)) with Blanked. Timed block: \(duration) min optional."
        }

        let headline: String
        switch level {
        case .high:
            headline = "Tonight may be harder than usual. Blanked should protect you before the urge arrives."
        case .medium:
            headline = "Risk is manageable. The best move is consistency, not a bigger challenge."
        case .low:
            headline = "This looks like a strong control day. Use it to reinforce your best window."
        }

        if reasons.isEmpty {
            reasons.append("Blanked is combining Health context with your block history to find your control pattern.")
        }

        return ControlForecast(
            level: level,
            riskPercent: riskPercent,
            riskLabel: riskLabel,
            headline: headline,
            windowText: DigitalWellnessAI.hourRangeText(weakHour),
            actionText: actionText,
            durationMinutes: duration,
            reasons: Array(reasons.prefix(3)),
            plan: Array(plan.prefix(2))
        )
    }

    private func unblankPatternInsights(events: [BlankUsageEvent], sessions: [BlankSession]) -> [String] {
        let calendar = Calendar.current
        let now = Date()
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let manualEvents = events.filter {
            $0.occurredAt >= weekAgo && $0.endedReason == .manual
        }
        let emergencyEvents = events.filter {
            $0.occurredAt >= weekAgo && ($0.kind == .blockBroken || $0.endedReason == .emergency)
        }

        guard !manualEvents.isEmpty || !emergencyEvents.isEmpty else {
            return ["No manual unblank pattern this week. Blanked is learning from completed protection windows."]
        }

        let weakHour = DigitalWellnessAI.weakHour(events: events, sessions: sessions, now: now)
        let averageProtectedMinutes = average(manualEvents.compactMap { event in
            event.duration.map { Int($0 / 60) }
        })
        var insights: [String] = []

        if let weakHour {
            let count = manualEvents.filter { $0.localHour == weakHour }.count
            if count > 0 {
                insights.append("\(count) hold-to-unblank exit\(count == 1 ? "" : "s") happened around \(DigitalWellnessAI.hourRangeText(weakHour)).")
            }
        }

        if let averageProtectedMinutes {
            insights.append("Average protection before manual exit: \(averageProtectedMinutes) min.")
        }

        if emergencyEvents.count > 0 {
            insights.append("Emergency exits are rare but high-signal; manual hold exits are the baseline relapse signal.")
        }

        return Array(insights.prefix(3))
    }

    private func interventionLearningInsights(events: [BlankUsageEvent], sessions: [BlankSession]) -> [String] {
        let calendar = Calendar.current
        let now = Date()
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let recentSessions = sessions.filter { session in
            session.startedAt >= weekAgo && session.startedAt <= now && session.endedAt != nil
        }
        let completedIndefinite = recentSessions.filter {
            $0.plannedDurationMinutes == nil && $0.endedReason != .manual && $0.endedReason != .emergency
        }.count
        let manualIndefinite = recentSessions.filter {
            $0.plannedDurationMinutes == nil && $0.endedReason == .manual
        }
        let timedCompleted = recentSessions.filter {
            $0.plannedDurationMinutes != nil && $0.endedReason != .manual && $0.endedReason != .emergency
        }.count
        let timedManual = recentSessions.filter {
            $0.plannedDurationMinutes != nil && $0.endedReason == .manual
        }.count

        if completedIndefinite > manualIndefinite.count, completedIndefinite > 0 {
            return ["Indefinite Blanked is working better than early exits this week. Keep it as the default."]
        }
        if timedCompleted > timedManual, timedCompleted > 0 {
            return ["Timed blocks look easier to complete right now. Use them as a lighter entry into Blanked."]
        }
        if let weakHour = DigitalWellnessAI.weakHour(events: events, sessions: sessions, now: now) {
            return ["Blanked is still learning the best intervention. For now, activate before \(DigitalWellnessAI.hourRangeText(weakHour))."]
        }
        return ["Blanked needs more starts and exits before it can compare indefinite protection with timed blocks."]
    }

    private func riskMomentValue(activityDays: [BlankActivityDay]) -> String {
        guard let day = riskiestDay(activityDays: activityDays) else {
            return "No pattern"
        }
        return weekdayName(for: day.date)
    }

    private func riskMomentCaption(activityDays: [BlankActivityDay]) -> String {
        guard let day = riskiestDay(activityDays: activityDays) else {
            return "Your vulnerable window will appear with more data"
        }
        if day.sessionCount > 1 {
            return "\(day.sessionCount) sessions: day where you use Blank most"
        }
        return "Day where you asked for the most protection"
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
            return "Complete one session to measure it"
        }
        let usedEmergencies = usedEmergencyUnlocks(emergencyUnlocksRemaining)
        if usedEmergencies == 0 {
            return "Clean sessions, no rescues this week"
        }
        if usedEmergencies < 3 {
            return "It will improve as emergency unlocks decrease"
        }
        return "Fragile week: you used all emergency unlocks"
    }

    private func controlRecoveryValue(weekly: BlankWeeklyReport, emergencyUnlocksRemaining: Int) -> String {
        let usedEmergencies = usedEmergencyUnlocks(emergencyUnlocksRemaining)
        if weekly.completedSessionCount > 0 && usedEmergencies == 0 {
            return "Stable"
        }
        if usedEmergencies < 3 {
            return "\(3 - usedEmergencies) reserves"
        }
        return "Limit"
    }

    private func controlRecoveryCaption(weekly: BlankWeeklyReport, emergencyUnlocksRemaining: Int) -> String {
        let usedEmergencies = usedEmergencyUnlocks(emergencyUnlocksRemaining)
        if weekly.completedSessionCount > 0 && usedEmergencies == 0 {
            return "You have not needed rescues this week"
        }
        if usedEmergencies < 3 {
            return "Emergency unlocks left this week"
        }
        return "Use emergency unlock only when it matters"
    }

    private func usedEmergencyUnlocks(_ emergencyUnlocksRemaining: Int) -> Int {
        min(max(3 - emergencyUnlocksRemaining, 0), 3)
    }

    private func emergencyCaption(_ emergencyUnlocksRemaining: Int) -> String {
        let used = usedEmergencyUnlocks(emergencyUnlocksRemaining)
        if used == 0 {
            return "No rescues this week"
        }
        if emergencyUnlocksRemaining > 0 {
            return "\(emergencyUnlocksRemaining) still available"
        }
        return "Weekly limit reached"
    }

    private func bestDayCaption(report: BlankWeeklyReport) -> String {
        guard let bestIndex = report.dailyDurations.indices.max(by: {
            report.dailyDurations[$0] < report.dailyDurations[$1]
        }), report.dailyDurations[bestIndex] > 0 else {
            return "This week"
        }
        let duration = formatDuration(report.dailyDurations[bestIndex])
        let sessions = report.dailySessionCounts[bestIndex]
        return "\(duration) · \(sessions) sessions"
    }

    private func progressPeriodSummaries(sessions: [BlankSession]) -> [ProgressPeriodSummary] {
        let calendar = Calendar.current
        let now = Date()
        let periods: [(String, Date)] = [
            ("Today", calendar.startOfDay(for: now)),
            ("Week", BlankWeeklySessionAggregator.startOfWeek(for: now, calendar: calendar)),
            ("Month", calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)),
            ("Year", calendar.dateInterval(of: .year, for: now)?.start ?? calendar.startOfDay(for: now))
        ]

        return periods.map { title, start in
            let duration = focusTime(sessions: sessions, from: start, to: now)
            let count = sessionCount(sessions: sessions, from: start, to: now)
            return ProgressPeriodSummary(
                title: title,
                value: formatCompactDuration(duration),
                caption: count == 1 ? "1 session" : "\(count) sessions"
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
            return "No data"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        let symbols = formatter.weekdaySymbols ?? []
        guard !symbols.isEmpty else {
            return "No data"
        }
        let calendarStartIndex = Calendar.current.firstWeekday - 1
        let symbolIndex = (calendarStartIndex + bestIndex) % symbols.count
        return symbols[symbolIndex].capitalized(with: Locale(identifier: "en_US"))
    }

    private func weekdayName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date).capitalized(with: Locale(identifier: "en_US"))
    }

    private func shortWeekdayName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "E"
        return formatter.string(from: date)
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
                status: "No activity yet today.",
                today: "You have not used Blank today yet.",
                signal: "Not enough daily signal.",
                nextAction: "Do a 25 min block with your main mode."
            )
        }

        let status: String
        if brokenEvents.isEmpty {
            status = "Stable day, no emergencies recorded."
        } else {
            status = "Today had \(brokenEvents.count) break\(brokenEvents.count == 1 ? "" : "s")."
        }

        let today = "\(formatDuration(totalFocus)) protected across \(todaySessions.count) session\(todaySessions.count == 1 ? "" : "s")."

        let signal: String
        if let hour = mostCommonValue(brokenEvents.map(\.localHour)) {
            signal = "Today sensitive window was \(hourRangeText(hour))."
        } else if let hour = mostCommonHour(from: startedEvents, sessions: todaySessions) {
            signal = "Today you used Blank most around \(String(format: "%02d:00", hour))."
        } else if let modeName {
            signal = "Today's active mode was \(modeName)."
        } else {
            signal = "No clear daily pattern yet."
        }

        let nextAction: String
        if let hour = mostCommonValue(brokenEvents.map(\.localHour)) {
            nextAction = "Tomorrow, start Blank at \(activationTimeText(before: hour))."
        } else if totalFocus < 25 * 60 {
            nextAction = "Complete one more short block before the day ends."
        } else if brokenEvents.isEmpty {
            nextAction = "Repeat the same window and mode tomorrow."
        } else {
            nextAction = "Reduce duration before repeating the block."
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
        progress: BlankProgressReport,
        healthContext: HealthRecoveryContext
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
                summary: "Not enough data this week yet.",
                patterns: [
                    "Blank needs a few sessions to detect real patterns.",
                    "The report improves when you use several modes or windows.",
                    "Emergency unlocks help detect fragile moments."
                ],
                weakSpots: [
                    "No clear weak window yet.",
                    "No concentrated breaks this week.",
                    "Start with 3 key apps or categories."
                ],
                recommendations: [
                    "Do a session of at least 25 minutes today.",
                    "Use Study mode before the first strong block.",
                    "Avoid Emergency unless it is essential."
                ],
                goal: "Complete 3 sessions this week to generate a useful report.",
                plan: [
                    "Today: 25 min with your main mode.",
                    "Tomorrow: repeat the same window.",
                    "Friday: review whether there were emergencies."
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
        patterns.append("\(formatDuration(totalFocus)) protected across \(weeklySessions.count) sessions.")
        if let bedtimeDrift = healthContext.bedtimeDriftMinutes, bedtimeDrift >= 75 {
            patterns.append("Sleep timing varies by about \(bedtimeDrift) min across recent Health data.")
        } else if let bestHour {
            patterns.append("Your most repeated window starts around \(String(format: "%02d:00", bestHour)).")
        } else if let bestWeekday {
            patterns.append("The highest-use day was \(weekdayDisplayName(bestWeekday)).")
        } else {
            patterns.append("There is no clear window yet.")
        }
        if let modeName {
            patterns.append("The most used mode is \(modeName).")
        } else {
            patterns.append("There is no clear mode yet.")
        }
        if brokenEvents.count > 0 {
            patterns[2] = "You broke \(brokenEvents.count) block\(brokenEvents.count == 1 ? "" : "s") this week."
        }

        var weakSpots: [String] = []
        if let weakHour {
            weakSpots.append("Weak window: \(hourRangeText(weakHour)).")
        } else if let bestHour {
            weakSpots.append("Window to reinforce: \(hourRangeText(bestHour)).")
        } else {
            weakSpots.append("No clear weak window yet.")
        }
        if let weakWeekday, brokenEvents.count > 0 {
            weakSpots.append("Breaks concentrated on \(weekdayDisplayName(weakWeekday)).")
        } else if brokenEvents.count > 0 {
            weakSpots.append("Breaks detected, with no dominant day.")
        } else {
            weakSpots.append("No concentrated breaks this week.")
        }
        weakSpots.append(appModeAdjustmentText(profile: selectionProfile, modeName: modeName))

        var recommendations: [String] = []
        if let weakHour {
            recommendations.append("Start Blank at \(activationTimeText(before: weakHour)).")
        } else if let recoveryScore = healthContext.recoveryScore, recoveryScore < 45 {
            recommendations.append("Keep today's block short: 25-30 min before the risky window.")
        } else if let bestHour {
            recommendations.append("Start Blank 10 min before \(String(format: "%02d:00", bestHour)).")
        } else {
            recommendations.append("Choose a fixed window to measure better.")
        }
        if brokenEvents.count > 0 {
            recommendations.append("Reduce the next block if Emergency appears.")
        } else {
            recommendations.append("Keep the same mode if you did not need Emergency this week.")
        }
        if selectionProfile.totalAverage < 3 {
            recommendations.append("Add at least 3 apps or categories to the main mode.")
        } else {
            recommendations.append("Do not change too many apps at once.")
        }

        let goal: String
        if brokenEvents.count > 0 {
            goal = "3 blocks without Emergency in your weakest window."
        } else if weeklySessions.count < 5 {
            goal = "Reach 5 protected sessions."
        } else {
            goal = "Increase protected time by 15% without Emergency."
        }

        let plan = weeklyPlan(
            weakHour: weakHour,
            bestHour: bestHour,
            modeName: modeName,
            brokenCount: brokenEvents.count,
            healthContext: healthContext
        )

        return WeeklyAIReport(
            summary: "Generated from your real sessions this week.",
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
        brokenCount: Int,
        healthContext: HealthRecoveryContext
    ) -> [String] {
        let mode = modeName ?? "main"
        let targetHour = weakHour ?? bestHour
        let firstBlock: String
        if let recoveryScore = healthContext.recoveryScore, recoveryScore < 45 {
            firstBlock = "3 days: keep blocks at 25-30 min while recovery is light."
        } else if let targetHour {
            firstBlock = "3 days: start Blank at \(activationTimeText(before: targetHour))."
        } else {
            firstBlock = "3 days: 25 min block at the same time."
        }

        let secondBlock = "Mode \(mode): keep the same apps."
        let thirdBlock = brokenCount > 0
            ? "If Emergency appears, reduce duration before repeating."
            : "Sunday: review whether you can increase one block."

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
        let mode = modeName ?? "main"
        if profile.totalAverage < 3 {
            return "Reinforce mode \(mode) with more apps or categories."
        }
        if profile.applicationAverage == 0 {
            return "Add specific apps if a category is too broad."
        }
        if profile.categoryAverage == 0 {
        return "Group similar apps in a category if you repeat adjustments."
        }
        return "Keep apps/modes one more week before changing."
    }

    private func hourRangeText(_ hour: Int) -> String {
        "\(String(format: "%02d:00", hour))-\(String(format: "%02d:00", (hour + 1) % 24))"
    }

    private func activationTimeText(before hour: Int) -> String {
        String(format: "%02d:50", (hour + 23) % 24)
    }

    private func minutesUntilNextHour(_ hour: Int, now: Date) -> Int {
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        if currentHour == hour {
            return 0
        }
        let hoursUntil = (hour - currentHour + 24) % 24
        return max(0, hoursUntil * 60 - currentMinute)
    }

    private func mostCommonValue<T: Hashable>(_ values: [T]) -> T? {
        let counts = values.reduce(into: [T: Int]()) { counts, value in
            counts[value, default: 0] += 1
        }
        return counts.max { lhs, rhs in lhs.value < rhs.value }?.key
    }

    private func average(_ values: [Int]) -> Int? {
        values.isEmpty ? nil : values.reduce(0, +) / values.count
    }

    private func circularMinuteDrift(_ minutes: [Int]) -> Int? {
        guard minutes.count >= 2 else { return nil }
        let normalized = minutes.map { $0 < 12 * 60 ? $0 + 24 * 60 : $0 }
        guard let minValue = normalized.min(), let maxValue = normalized.max() else { return nil }
        return maxValue - minValue
    }

    private func weekdayDisplayName(_ weekday: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        let symbols = formatter.weekdaySymbols ?? []
        guard symbols.indices.contains(weekday - 1) else { return "this week" }
        return symbols[weekday - 1].capitalized(with: Locale(identifier: "en_US"))
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

private struct HealthRecoveryContext {
    let averageSleepMinutes: Int?
    let averageSteps: Int?
    let averageWorkoutMinutes: Int?
    let averageHRV: Int?
    let averageRestingHeartRate: Int?
    let bedtimeDriftMinutes: Int?
    let wakeDriftMinutes: Int?
    let recoveryScore: Int?
}

private struct ControlForecast {
    enum Level {
        case low
        case medium
        case high
    }

    let level: Level
    let riskPercent: Int
    let riskLabel: String
    let headline: String
    let windowText: String
    let actionText: String
    let durationMinutes: Int
    let reasons: [String]
    let plan: [String]
}

private struct ReportLiquidBackground: View {
    let isActive: Bool

    var body: some View {
        ZStack {
            BlankAtmosphericBackground(dimmed: isActive)

            LinearGradient(
                colors: [
                    Color.white.opacity(isActive ? 0.04 : 0.22),
                    (isActive ? BlankColors.ink : BlankColors.background).opacity(isActive ? 0.22 : 0.28),
                    Color.white.opacity(isActive ? 0.03 : 0.14)
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
                        .fill(Color.white.opacity(0.18))
                    BlankGlassCornerHighlight(width: 112, height: 42, xOffset: -120, yOffset: -23)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .opacity(0.58)
                }
                .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(BlankColors.glassBorder, lineWidth: 0.8)
            }
            .shadow(color: BlankColors.ink.opacity(0.038), radius: 18, x: 0, y: 10)
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
