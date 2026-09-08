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
    val healthContext: String
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
        val baseScore = 72 + min(14, sessions * 3) - min(28, breaks * 9) - min(18, stats.blockedAttemptsThisWeek * 3)
        val healthPenalty = when {
            healthSummary.recoveryScore != null && healthSummary.recoveryScore < 45 -> 12
            healthSummary.lowRecoverySignal -> 8
            healthSummary.recoveryScore != null && healthSummary.recoveryScore >= 75 -> -4
            else -> 0
        }
        val score = (baseScore - healthPenalty).coerceIn(0, 100)
        val riskScore = (100 - score + if (minutesUntilHour(weakHour, now) <= 60) 18 else 0).coerceIn(18, 96)
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
        return DigitalWellnessPlan(
            archetype = archetype,
            score = score,
            riskWindow = riskWindow,
            riskScore = riskScore,
            recommendedDurationMinutes = duration,
            primaryAction = "Start $duration min before $riskWindow.",
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
            healthContext = healthText
        )
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
