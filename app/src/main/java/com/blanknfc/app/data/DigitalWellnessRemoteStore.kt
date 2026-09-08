package com.blanknfc.app.data

import android.util.Log
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

class DigitalWellnessRemoteStore(
    private val backendClient: BlankBackendClient,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
) {
    private val _plan = MutableStateFlow<DigitalWellnessPlan?>(null)
    val plan: StateFlow<DigitalWellnessPlan?> = _plan.asStateFlow()

    fun refresh(
        localPlan: DigitalWellnessPlan,
        stats: FocusStats,
        selectedAppCount: Int,
        emergencyUnlocksRemaining: Int,
        schedule: FocusSchedule,
        healthSummary: HealthConnectSummary
    ) {
        scope.launch {
            runCatching {
                val body = backendClient.commonEnvelope(
                    JSONObject().apply {
                        put("consent_text", "Digital Wellness personalization")
                        put(
                            "payload",
                            buildPayload(
                                stats = stats,
                                selectedAppCount = selectedAppCount,
                                emergencyUnlocksRemaining = emergencyUnlocksRemaining,
                                schedule = schedule,
                                healthSummary = healthSummary
                            )
                        )
                    }
                )
                val response = backendClient.post("digital-wellness-features", body)
                _plan.value = response.optJSONObject("insight")?.toPlan(localPlan)
            }.onFailure {
                Log.w("BlankedAI", "Digital wellness sync failed", it)
                _plan.value = localPlan
            }
        }
    }

    private fun buildPayload(
        stats: FocusStats,
        selectedAppCount: Int,
        emergencyUnlocksRemaining: Int,
        schedule: FocusSchedule,
        healthSummary: HealthConnectSummary
    ): JSONObject {
        val now = Instant.now()
        val end = LocalDate.now()
        val start = end.minusDays(13)
        val activeDays = stats.activityDays.count { it.sessions > 0 || it.protectedMs > 0L || it.blockedAttempts > 0 }
        val blockedMinutes = (stats.protectedMsThisWeek / 60000L).toInt()
        val weakestHour = if (schedule.enabled) schedule.startMinute / 60 else 22
        val usedEmergency = (3 - emergencyUnlocksRemaining).coerceIn(0, 3)
        return JSONObject().apply {
            put("schema_version", 1)
            put("generated_at", now.toString())
            put("period_start", start.atStartOfDay(ZoneId.systemDefault()).toInstant().toString())
            put("period_end", end.atStartOfDay(ZoneId.systemDefault()).toInstant().toString())
            put("common_features", healthSummary.commonFeatures())
            put("provider_features", healthSummary.providerFeatures())
            put("source_confidence", healthSummary.sourceConfidence())
            put("freshness", healthSummary.freshness())
            put(
                "profile",
                JSONObject().apply {
                    put("motivation_cluster", "general_control")
                }
            )
            put(
                "daily",
                JSONArray(
                    stats.activityDays.takeLast(14).map { day ->
                        JSONObject().apply {
                            put("day_key", day.key)
                            put("blocked_minutes", (day.protectedMs / 60000L).toInt())
                            put("blocks_completed", day.sessions)
                            put("blocked_attempts", day.blockedAttempts)
                        }
                    }
                )
            )
            put(
                "weekly",
                JSONObject().apply {
                    put("days_count", 14)
                    put("active_days_7d", activeDays)
                    put("blocked_minutes", blockedMinutes)
                    put("blocks_completed", stats.sessionsThisWeek)
                    put("blocked_attempts", stats.blockedAttemptsThisWeek)
                    put("emergency_unlocks_used", usedEmergency)
                    put("selection_count", selectedAppCount)
                    put("weakest_hour", weakestHour)
                    put("worst_focus_window", hourWindow(weakestHour))
                    put("plan_adherence_percent", if (usedEmergency == 0 && stats.sessionsThisWeek > 0) 85 else 45)
                    put("recommended_plan_difficulty", if (usedEmergency >= 2) "lighter" else "baseline")
                    put("health_days_count", healthSummary.daysWithAnySignal)
                    put("health_days_with_sleep", healthSummary.daysWithSleep)
                    put("health_days_with_vitals", healthSummary.daysWithVitals)
                    healthSummary.latestSignalAgeHours?.let { put("health_latest_signal_age_hours", it.toInt()) }
                    healthSummary.avgSteps7d?.let { put("avg_steps", it) }
                    healthSummary.steps7d?.let { put("steps_total_7d", it) }
                    healthSummary.distanceMeters7d?.let { put("distance_meters_7d", it) }
                    healthSummary.activeCalories7d?.let { put("active_energy_kcal_7d", it) }
                    healthSummary.totalCalories7d?.let { put("total_energy_kcal_7d", it) }
                    healthSummary.elevationMeters7d?.let { put("elevation_meters_7d", it) }
                    healthSummary.floorsClimbed7d?.let { put("floors_climbed_7d", it) }
                    healthSummary.avgSleepMinutes7d?.let { put("avg_sleep_minutes", it) }
                    healthSummary.avgSleepEfficiency7d?.let { put("avg_sleep_efficiency", it) }
                    healthSummary.lateSleepNights7d?.let { put("late_sleep_nights_7d", it) }
                    healthSummary.avgWorkoutMinutes7d?.let { put("avg_workout_minutes", it) }
                    healthSummary.mindfulMinutes7d?.let { put("mindful_minutes_7d", it) }
                    healthSummary.averageHeartRate7d?.let { put("avg_heart_rate", it) }
                    healthSummary.restingHeartRate7d?.let { put("avg_resting_hr", it) }
                    healthSummary.hrvRmssd7d?.let { put("avg_hrv", it) }
                    healthSummary.respiratoryRate7d?.let { put("avg_respiratory_rate", it) }
                    healthSummary.oxygenSaturation7d?.let { put("avg_oxygen_saturation", it) }
                    healthSummary.vo2Max7d?.let { put("avg_vo2_max", it) }
                    healthSummary.recoveryScore?.let { put("avg_recovery_score", it) }
                    put("recovery_trend_14d", healthSummary.recoveryTrend)
                    healthSummary.heartRateSamples7d?.let { put("heart_rate_samples", it) }
                }
            )
            put(
                "correlations",
                JSONObject().apply {
                    put("screen_risk_after_bad_sleep", if (healthSummary.lowRecoverySignal) "high" else "unknown")
                    put("relapses_after_short_sleep", if (healthSummary.lowRecoverySignal) usedEmergency else 0)
                    put("night_scroll_after_late_bedtime", weakestHour >= 21 || weakestHour <= 1)
                }
            )
            put(
                "privacy",
                JSONObject().apply {
                    put("raw_health_samples_sent", false)
                    put("raw_sleep_stage_timestamps_sent", false)
                    put("exact_app_selection_sent", false)
                    put("exact_location_sent", false)
                    put("health_processing_location", "on_device")
                    put("backend_payload_type", "daily_and_weekly_features")
                }
            )
        }
    }

    private fun JSONObject.toPlan(fallback: DigitalWellnessPlan): DigitalWellnessPlan {
        val planUpdate = optJSONObject("plan_update")
        val start = planUpdate?.optInt("proposed_start_minute", -1)?.takeIf { it >= 0 }
        val end = planUpdate?.optInt("proposed_end_minute", -1)?.takeIf { it >= 0 }
        val duration = if (start != null && end != null) {
            ((end - start + 1440) % 1440).coerceAtLeast(15)
        } else {
            fallback.recommendedDurationMinutes
        }
        return fallback.copy(
            archetype = optString("motivation_cluster", fallback.archetype).replace('_', ' ').replaceFirstChar { it.uppercase() },
            score = optInt("confidence", fallback.score),
            riskWindow = optString("risk_window", fallback.riskWindow).ifBlank { fallback.riskWindow },
            riskScore = (100 - optInt("confidence", 70)).coerceIn(10, 95),
            recommendedDurationMinutes = duration.coerceIn(15, 540),
            primaryAction = planUpdate?.takeIf { it.has("action_label") }?.optString("action_label") ?: fallback.primaryAction,
            secondaryAction = optJSONArray("recommendations")?.optString(1) ?: fallback.secondaryAction,
            reportInsight = optString("summary", fallback.reportInsight),
            healthContext = optJSONArray("patterns")?.optString(0) ?: fallback.healthContext
        )
    }

    private fun hourWindow(hour: Int): String {
        return "${formatHour(hour)} to ${formatHour((hour + 2) % 24)}"
    }

    private fun formatHour(hour: Int): String {
        val normalized = ((hour % 24) + 24) % 24
        val display = if (normalized % 12 == 0) 12 else normalized % 12
        val suffix = if (normalized < 12) "AM" else "PM"
        return "$display:00 $suffix"
    }

    private fun HealthConnectSummary.commonFeatures(): JSONObject {
        return JSONObject().apply {
            put("sleep", avgSleepMinutes7d?.toString() ?: "learning")
            put("sleep_timing", lateSleepNights7d?.toString() ?: "learning")
            put("recovery", recoveryScore?.toString() ?: "learning")
            put("activity", avgSteps7d?.toString() ?: "learning")
            put("strain_load", avgWorkoutMinutes7d?.toString() ?: "learning")
            put("stress_proxy", hrvRmssd7d?.toString() ?: "learning")
            put("freshness", latestSignalAgeHours?.toString() ?: "unknown")
            put("coverage", signalCoveragePercent().toString())
            put("confidence", wearableConfidence().toString())
            if (lowRecoverySignal) put("low_recovery_mode", "candidate")
        }
    }

    private fun HealthConnectSummary.providerFeatures(): JSONObject {
        return JSONObject().apply {
            put(
                "health_connect",
                JSONObject().apply {
                    avgSleepEfficiency7d?.let { put("sleep_efficiency", it.toString()) }
                    lateSleepNights7d?.let { put("late_sleep_nights", it.toString()) }
                    activeCalories7d?.let { put("active_energy_kcal", it.toString()) }
                    totalCalories7d?.let { put("total_energy_kcal", it.toString()) }
                    elevationMeters7d?.let { put("elevation_meters", it.toString()) }
                    floorsClimbed7d?.let { put("floors_climbed", it.toString()) }
                    mindfulMinutes7d?.let { put("mindful_minutes", it.toString()) }
                    hrvRmssd7d?.let { put("hrv_rmssd", it.toString()) }
                    respiratoryRate7d?.let { put("respiratory_rate", it.toString()) }
                    oxygenSaturation7d?.let { put("oxygen_saturation", it.toString()) }
                    vo2Max7d?.let { put("vo2_max", it.toString()) }
                }
            )
        }
    }

    private fun HealthConnectSummary.sourceConfidence(): JSONObject {
        return JSONObject().apply {
            put("health_connect", wearableConfidence().toString())
            put("sleep", metricConfidence(daysWithSleep))
            put("recovery", metricConfidence(listOfNotNull(recoveryScore).size))
            put("activity", metricConfidence(listOfNotNull(avgSteps7d).size))
            put("vitals", metricConfidence(daysWithVitals))
        }
    }

    private fun HealthConnectSummary.freshness(): JSONObject {
        return JSONObject().apply {
            put("health_connect_latest_signal_age_hours", latestSignalAgeHours?.toString() ?: "unknown")
            put(
                "status",
                when {
                    latestSignalAgeHours == null -> "no_data"
                    latestSignalAgeHours > 72 -> "stale"
                    else -> "fresh"
                }
            )
        }
    }

    private fun HealthConnectSummary.signalCoveragePercent(): Int {
        return daysWithAnySignal * 100 / daysRequested.coerceAtLeast(1)
    }

    private fun HealthConnectSummary.wearableConfidence(): Int {
        return (signalCoveragePercent() / 2 + daysWithAnySignal.coerceAtMost(7) * 7).coerceIn(0, 100)
    }

    private fun metricConfidence(days: Int): String {
        return (days.coerceIn(0, 7) * 14).toString()
    }
}
