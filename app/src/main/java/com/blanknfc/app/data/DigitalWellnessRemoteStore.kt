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

    fun recordExecution(
        recommendationId: String?,
        plan: DigitalWellnessPlan?,
        success: Boolean,
        outcome: String = if (success) "completed" else "failed"
    ) {
        if (recommendationId.isNullOrBlank()) return
        scope.launch {
            var loop: JSONObject? = null
            var loopStatus: String? = null
            var loopId: String? = null
            runCatching {
                loop = startLoop(recommendationId, plan)
                loop = advanceLoop(loop, "confirm")
                loop = advanceLoop(loop, "execution_started")
                loop = advanceLoop(
                    loop,
                    "executed",
                    success = success,
                    verification = if (success) "passed" else null,
                    reason = if (success) "Android local app state matched the requested action." else "Android local app did not confirm the requested action."
                )
                if (success) {
                    loop = advanceLoop(
                        loop,
                        "verified",
                        success = true,
                        verification = "passed",
                        reason = "Android local app verification passed."
                    )
                }
                loop = advanceLoop(
                    loop,
                    "outcome_recorded",
                    success = success,
                    outcome = if (success) "held" else "failed",
                    outcomeScore = if (success) 24 else -28,
                    verification = if (success) "passed" else "failed",
                    reason = if (success) "Android local outcome recorded after device verification." else "Android local outcome recorded after failed device verification."
                )
                loopStatus = loop?.optString("status")?.takeIf { it.isNotBlank() }
                loopId = loop?.optString("loop_id")?.takeIf { it.isNotBlank() }
            }.onFailure {
                Log.w("BlankedAI", "BM loop sync failed; recording outcome without loop", it)
            }
            runCatching {
                backendClient.post(
                    "bai-outcome",
                    backendClient.commonEnvelope(JSONObject().apply {
                        put("recommendation_id", recommendationId)
                        put("outcome", outcome)
                        put("outcome_score", when (outcome) {
                            "activated" -> 16
                            "completed" -> 24
                            "held" -> 30
                            "broke" -> -30
                            "relapse_after" -> -26
                            else -> JSONObject.NULL
                        })
                        put("metadata", JSONObject().apply {
                            put("source", "android")
                            put("surface", "wellness_dashboard")
                            loopId?.let { put("loop_id", it) }
                            loopStatus?.let { put("loop_status", it) }
                        })
                    })
                )
            }.onFailure {
                Log.w("BlankedAI", "BM outcome sync failed", it)
            }
        }
    }

    private fun startLoop(recommendationId: String, plan: DigitalWellnessPlan?): JSONObject? {
        val response = backendClient.post(
            "bm-loop",
            backendClient.commonEnvelope(JSONObject().apply {
                put("operation", "start")
                put("prompt_hash", recommendationId)
                put("context", JSONObject().apply {
                    put("mode", "android")
                    put("has_selected_apps", true)
                    put("screen_time_authorized", true)
                    put("single_distraction_block", true)
                    put("protection_target", "selected_distractions")
                })
                put("plan", JSONObject().apply {
                    put("title", plan?.archetype ?: "digital_wellness")
                    put("intent", "apply_ai_plan")
                    put("actions", JSONArray().put(JSONObject().put("type", "apply_ai_plan")))
                })
            })
        )
        return response.optJSONObject("loop")
    }

    private fun advanceLoop(
        loop: JSONObject?,
        type: String,
        success: Boolean = false,
        verification: String? = null,
        reason: String? = null,
        outcome: String? = null,
        outcomeScore: Int? = null
    ): JSONObject? {
        if (loop == null) return null
        val event = JSONObject().apply {
            put("type", type)
            put("event_id", "bme_${java.util.UUID.randomUUID()}")
            put("success", success)
            put("source", "android")
            verification?.let { put("verification", it) }
            reason?.let { put("reason", it) }
            outcome?.let { put("outcome", it) }
            outcomeScore?.let { put("outcome_score", it) }
        }
        val response = backendClient.post(
            "bm-loop",
            backendClient.commonEnvelope(JSONObject().apply {
                put("operation", "advance")
                put("loop", loop)
                put("event", event)
            })
        )
        return response.optJSONObject("loop") ?: loop
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
        val pickupPressure = pickupPressureScore(stats, usedEmergency)
        val behaviorChain = behaviorChain(stats, schedule)
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
                    put("pickup_pressure_score", pickupPressure)
                    put("unlock_pressure_score", pickupPressure)
                    put("dominant_app_sequence", behaviorChain)
                    put("behavior_chain", behaviorChain)
                    put("app_sequence_risk", sequenceRisk(pickupPressure, stats.blockedAttemptsThisWeek))
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
                    put("rapid_pickups_before_relapse", pickupPressure >= 65)
                    put("sequence_risk_after_harmless_check", pickupPressure >= 50)
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
        val forecast = optJSONObject("behavior_forecast")
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
            riskScore = forecast?.optInt("risk_score", fallback.riskScore) ?: (100 - optInt("confidence", 70)).coerceIn(10, 95),
            recommendedDurationMinutes = duration.coerceIn(15, 540),
            primaryAction = forecast?.optString("action_label")?.takeIf { it.isNotBlank() }?.let { "$it: ${optString("risk_window", fallback.riskWindow).ifBlank { fallback.riskWindow }}" }
                ?: planUpdate?.takeIf { it.has("action_label") }?.optString("action_label")
                ?: fallback.primaryAction,
            secondaryAction = optJSONArray("recommendations")?.optString(1) ?: fallback.secondaryAction,
            reportInsight = optString("summary", fallback.reportInsight),
            healthContext = optJSONArray("patterns")?.optString(0) ?: fallback.healthContext,
            forecastReasons = forecast?.optJSONArray("reasons")?.toStringList() ?: fallback.forecastReasons,
            behaviorChain = fallback.behaviorChain,
            experimentName = optJSONObject("experiment")?.optString("name")?.takeIf { it.isNotBlank() } ?: fallback.experimentName,
            experimentWhy = optJSONObject("experiment")?.optString("hypothesis")?.takeIf { it.isNotBlank() } ?: fallback.experimentWhy,
            experimentMetric = optJSONObject("experiment")?.optString("success_metric")?.takeIf { it.isNotBlank() } ?: fallback.experimentMetric,
            recommendationId = optString("recommendation_id").takeIf { it.isNotBlank() } ?: fallback.recommendationId
        )
    }

    private fun JSONArray.toStringList(): List<String> {
        return (0 until length()).mapNotNull { index -> optString(index).takeIf { it.isNotBlank() } }
    }

    private fun pickupPressureScore(stats: FocusStats, usedEmergency: Int): Int {
        val recentPressure = stats.activityDays.takeLast(7).sumOf { day ->
            day.blockedAttempts * 14 + if (day.sessions == 0 && day.blockedAttempts > 0) 10 else 0
        }
        return (recentPressure + usedEmergency * 12).coerceIn(0, 100)
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

    private fun sequenceRisk(pickupPressure: Int, blockedAttempts: Int): String {
        return when {
            pickupPressure >= 70 || blockedAttempts >= 5 -> "high"
            pickupPressure >= 40 || blockedAttempts >= 2 -> "medium"
            else -> "low"
        }
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
