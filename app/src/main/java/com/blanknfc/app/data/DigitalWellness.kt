package com.blanknfc.app.data

import java.util.Calendar
import kotlin.math.max
import kotlin.math.min

data class DigitalWellnessPlan(
    val archetype: String,
    val score: Int,
    val riskWindow: String,
    val riskScore: Int,
    val recommendedDurationMinutes: Int,
    val primaryAction: String,
    val secondaryAction: String,
    val reportInsight: String,
    val healthContext: String,
    val forecastReasons: List<String> = emptyList(),
    val behaviorChain: String = "Learning",
    val experimentName: String = "Stable Repeat",
    val experimentWhy: String = "Repeat the same window before increasing difficulty.",
    val experimentMetric: String = "Completed sessions without emergency exits.",
    val recommendationId: String? = null
)

object DigitalWellnessEngine {
    fun build(
        stats: FocusStats,
        selectedAppCount: Int,
        emergencyUnlocksRemaining: Int,
        schedule: FocusSchedule,
        healthSummary: HealthConnectSummary = HealthConnectSummary()
    ): DigitalWellnessPlan {
        val now = Calendar.getInstance()
        val currentHour = now.get(Calendar.HOUR_OF_DAY)
        val weakHour = when {
            schedule.enabled -> schedule.startMinute / 60
            stats.blockedAttemptsThisWeek > 0 -> currentHour
            currentHour in 21..23 || currentHour in 0..1 -> 22
            currentHour in 8..16 -> 9
            else -> 20
        }
        val sessions = stats.sessionsThisWeek
        val breaks = 3 - emergencyUnlocksRemaining
        val pickupPressure = pickupPressureScore(stats, breaks)
        val behaviorChain = behaviorChain(stats, schedule)
        val baseScore = 72 + min(14, sessions * 3) - min(28, breaks * 9) - min(18, stats.blockedAttemptsThisWeek * 3) - min(10, pickupPressure / 12)
        val healthPenalty = when {
            healthSummary.recoveryScore != null && healthSummary.recoveryScore < 45 -> 12
            healthSummary.lowRecoverySignal -> 8
            healthSummary.recoveryScore != null && healthSummary.recoveryScore >= 75 -> -4
            else -> 0
        }
        val score = (baseScore - healthPenalty).coerceIn(0, 100)
        val riskScore = (100 - score + pickupPressure / 5 + if (minutesUntilHour(weakHour, now) <= 60) 18 else 0).coerceIn(18, 96)
        val duration = when {
            breaks >= 2 || healthSummary.lowRecoverySignal -> 25
            sessions >= 4 && score >= 78 -> 60
            selectedAppCount < 3 -> 25
            else -> 45
        }
        val archetype = when {
            weakHour in 21..23 || weakHour in 0..1 -> "Night Scroller"
            weakHour in 8..16 -> "Focus Breaker"
            stats.blockedAttemptsThisWeek >= 3 -> "Dopamine Loop"
            else -> "Habit Rebuilder"
        }
        val riskWindow = hourRange(weakHour)
        val healthText = healthSummary.readableContext
        val forecastReasons = forecastReasons(
            pickupPressure = pickupPressure,
            behaviorChain = behaviorChain,
            breaks = breaks,
            healthSummary = healthSummary,
            riskWindow = riskWindow
        )
        val experiment = experimentFor(
            pickupPressure = pickupPressure,
            breaks = breaks,
            adherenceGood = sessions >= 3 && breaks == 0,
            lowRecovery = healthSummary.lowRecoverySignal
        )
        return DigitalWellnessPlan(
            archetype = archetype,
            score = score,
            riskWindow = riskWindow,
            riskScore = riskScore,
            recommendedDurationMinutes = duration,
            primaryAction = "Next risk: $riskWindow. Start $duration min before it.",
            secondaryAction = if (selectedAppCount < 3) {
                "Add at least 3 apps before judging results."
            } else {
                "Keep your current app list for the next 3 sessions."
            },
            reportInsight = if (sessions == 0) {
                "Start Blanked and come back after your first protected session."
            } else {
                "Score $score/100. Next risk: $riskWindow."
            },
            healthContext = healthText,
            forecastReasons = forecastReasons,
            behaviorChain = behaviorChain,
            experimentName = experiment.name,
            experimentWhy = experiment.hypothesis,
            experimentMetric = experiment.metric
        )
    }

    private data class Experiment(val name: String, val hypothesis: String, val metric: String)

    private fun pickupPressureScore(stats: FocusStats, breaks: Int): Int {
        val recentPressure = stats.activityDays.takeLast(7).sumOf { day ->
            day.blockedAttempts * 14 + if (day.sessions == 0 && day.blockedAttempts > 0) 10 else 0
        }
        return (recentPressure + breaks * 12).coerceIn(0, 100)
    }

    private fun behaviorChain(stats: FocusStats, schedule: FocusSchedule): String {
        val recent = stats.activityDays.takeLast(7)
        val attempts = recent.sumOf { it.blockedAttempts }
        val sessions = recent.sumOf { it.sessions }
        return when {
            attempts >= 3 && schedule.enabled -> "scheduled window -> blocked app urge"
            attempts >= 3 -> "quick check -> blocked app urge"
            attempts > sessions -> "urge before planned block"
            sessions >= 3 -> "planned block -> clean session"
            else -> "learning"
        }
    }

    private fun forecastReasons(
        pickupPressure: Int,
        behaviorChain: String,
        breaks: Int,
        healthSummary: HealthConnectSummary,
        riskWindow: String
    ): List<String> {
        val reasons = mutableListOf<String>()
        if (pickupPressure >= 50) reasons += "Pickup pressure is above baseline."
        if (behaviorChain != "learning") reasons += "Repeated chain: $behaviorChain."
        if (breaks > 0) reasons += "Recent exits increase risk in $riskWindow."
        if (healthSummary.lowRecoverySignal) reasons += "Recovery suggests using lighter protection."
        if (reasons.isEmpty()) reasons += "Blanked is learning baseline timing and outcomes."
        return reasons.take(4)
    }

    private fun experimentFor(pickupPressure: Int, breaks: Int, adherenceGood: Boolean, lowRecovery: Boolean): Experiment {
        return when {
            pickupPressure >= 65 -> Experiment(
                name = "Chain Intercept",
                hypothesis = "Stop the second quick check before it becomes a longer scroll loop.",
                metric = "Fewer blocked attempts in the same window."
            )
            breaks >= 2 || lowRecovery -> Experiment(
                name = "Lighter Earlier Block",
                hypothesis = "A shorter earlier block should hold better than strict late friction.",
                metric = "Completed block without emergency exit."
            )
            adherenceGood -> Experiment(
                name = "Progressive Window",
                hypothesis = "A stable user can extend one protected window safely.",
                metric = "Three completed sessions without relapse."
            )
            else -> Experiment(
                name = "Stable Repeat",
                hypothesis = "Repeat the same window to build a clean baseline.",
                metric = "Completed sessions without emergency exits."
            )
        }
    }

    private fun minutesUntilHour(hour: Int, now: Calendar): Int {
        val currentHour = now.get(Calendar.HOUR_OF_DAY)
        val currentMinute = now.get(Calendar.MINUTE)
        if (currentHour == hour) return 0
        val hoursUntil = (hour - currentHour + 24) % 24
        return max(0, hoursUntil * 60 - currentMinute)
    }

    private fun hourRange(hour: Int): String {
        val start = formatHour(hour)
        val end = formatHour((hour + 1) % 24)
        return "$start to $end"
    }

    private fun formatHour(hour: Int): String {
        val normalized = ((hour % 24) + 24) % 24
        val display = if (normalized % 12 == 0) 12 else normalized % 12
        val suffix = if (normalized < 12) "AM" else "PM"
        return "$display:00 $suffix"
    }
}
