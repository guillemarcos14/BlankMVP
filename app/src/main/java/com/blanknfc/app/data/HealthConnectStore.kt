@file:OptIn(androidx.health.connect.client.feature.ExperimentalMindfulnessSessionApi::class)

package com.blanknfc.app.data

import android.content.Context
import android.os.Build
import androidx.health.connect.client.feature.ExperimentalMindfulnessSessionApi
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ElevationGainedRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.FloorsClimbedRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.HeartRateVariabilityRmssdRecord
import androidx.health.connect.client.records.MindfulnessSessionRecord
import androidx.health.connect.client.records.OxygenSaturationRecord
import androidx.health.connect.client.records.RespiratoryRateRecord
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import androidx.health.connect.client.records.Vo2MaxRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class HealthConnectSummary(
    val available: Boolean = false,
    val permissionGranted: Boolean = false,
    val partialPermission: Boolean = false,
    val grantedPermissionCount: Int = 0,
    val requestedPermissionCount: Int = 0,
    val daysRequested: Int = 14,
    val daysWithAnySignal: Int = 0,
    val daysWithSleep: Int = 0,
    val daysWithVitals: Int = 0,
    val latestSignalAgeHours: Long? = null,
    val steps7d: Long? = null,
    val avgSteps7d: Int? = null,
    val distanceMeters7d: Int? = null,
    val activeCalories7d: Int? = null,
    val totalCalories7d: Int? = null,
    val elevationMeters7d: Int? = null,
    val floorsClimbed7d: Int? = null,
    val sleepSessions7d: Int? = null,
    val avgSleepMinutes7d: Int? = null,
    val avgSleepEfficiency7d: Int? = null,
    val lateSleepNights7d: Int? = null,
    val workouts7d: Int? = null,
    val avgWorkoutMinutes7d: Int? = null,
    val mindfulMinutes7d: Int? = null,
    val heartRateSamples7d: Int? = null,
    val averageHeartRate7d: Int? = null,
    val restingHeartRate7d: Int? = null,
    val hrvRmssd7d: Int? = null,
    val respiratoryRate7d: Int? = null,
    val oxygenSaturation7d: Int? = null,
    val vo2Max7d: Int? = null,
    val recoveryScore: Int? = null,
    val recoveryTrend: String = "learning"
) {
    val lowRecoverySignal: Boolean
        get() = recoveryScore?.let { it < 45 }
            ?: (avgSteps7d?.let { it < 3500 } == true ||
                avgSleepMinutes7d?.let { it < 360 } == true ||
                sleepSessions7d?.let { it < 3 } == true)

    val readableContext: String
        get() = when {
            !available -> "Health Connect is not available on this device."
            partialPermission -> "Health Connect is partially connected. Allow sleep, activity and heart signals for better plans."
            !permissionGranted -> "Connect Health Connect for optional sleep, recovery and activity context."
            latestSignalAgeHours != null && latestSignalAgeHours > 72 -> "Connected, but Health data looks stale. Open your wearable app to sync."
            else -> listOfNotNull(
                recoveryScore?.let { "Recovery $it/100" },
                avgSleepMinutes7d?.let { "${it / 60}h ${it % 60}m avg sleep" } ?: sleepSessions7d?.let { "$it sleep sessions" },
                avgSteps7d?.let { "$it avg steps" },
                hrvRmssd7d?.let { "HRV $it ms" },
                restingHeartRate7d?.let { "RHR $it bpm" }
            ).ifEmpty { listOf("Connected. More wearable samples will improve insights.") }.joinToString(" · ")
        }
}

@OptIn(ExperimentalMindfulnessSessionApi::class)
class HealthConnectStore(
    private val context: Context,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
) {
    private val _summary = MutableStateFlow(HealthConnectSummary(available = isAvailable()))
    val summary: StateFlow<HealthConnectSummary> = _summary.asStateFlow()

    val permissions = setOf(
        HealthPermission.getReadPermission(StepsRecord::class),
        HealthPermission.getReadPermission(DistanceRecord::class),
        HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class),
        HealthPermission.getReadPermission(TotalCaloriesBurnedRecord::class),
        HealthPermission.getReadPermission(ElevationGainedRecord::class),
        HealthPermission.getReadPermission(FloorsClimbedRecord::class),
        HealthPermission.getReadPermission(SleepSessionRecord::class),
        HealthPermission.getReadPermission(ExerciseSessionRecord::class),
        HealthPermission.getReadPermission(MindfulnessSessionRecord::class),
        HealthPermission.getReadPermission(HeartRateRecord::class),
        HealthPermission.getReadPermission(RestingHeartRateRecord::class),
        HealthPermission.getReadPermission(HeartRateVariabilityRmssdRecord::class),
        HealthPermission.getReadPermission(RespiratoryRateRecord::class),
        HealthPermission.getReadPermission(OxygenSaturationRecord::class),
        HealthPermission.getReadPermission(Vo2MaxRecord::class)
    )

    fun refresh() {
        scope.launch {
            if (!isAvailable()) {
                _summary.value = HealthConnectSummary(available = false)
                return@launch
            }
            runCatching {
                val client = HealthConnectClient.getOrCreate(context)
                val grantedPermissions = client.permissionController.getGrantedPermissions()
                val hasAllPermissions = grantedPermissions.containsAll(permissions)
                if (!hasAllPermissions) {
                    _summary.value = HealthConnectSummary(
                        available = true,
                        permissionGranted = false,
                        partialPermission = grantedPermissions.isNotEmpty(),
                        grantedPermissionCount = grantedPermissions.size,
                        requestedPermissionCount = permissions.size
                    )
                    return@launch
                }
                _summary.value = readSummary(client)
            }.onFailure {
                _summary.value = HealthConnectSummary(available = true, permissionGranted = false)
            }
        }
    }

    private suspend fun readSummary(client: HealthConnectClient): HealthConnectSummary {
        val end = Instant.now()
        val start14 = end.minus(14, ChronoUnit.DAYS)
        val start7 = end.minus(7, ChronoUnit.DAYS)
        val range7 = TimeRangeFilter.between(start7, end)
        val range14 = TimeRangeFilter.between(start14, end)
        val aggregates = client.aggregate(
            AggregateRequest(
                metrics = setOf(
                    StepsRecord.COUNT_TOTAL,
                    DistanceRecord.DISTANCE_TOTAL,
                    ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL,
                    TotalCaloriesBurnedRecord.ENERGY_TOTAL,
                    ElevationGainedRecord.ELEVATION_GAINED_TOTAL,
                    FloorsClimbedRecord.FLOORS_CLIMBED_TOTAL,
                    HeartRateRecord.BPM_AVG,
                    RestingHeartRateRecord.BPM_AVG
                ),
                timeRangeFilter = range7
            )
        )
        val sleep7 = client.readRecords(ReadRecordsRequest(SleepSessionRecord::class, timeRangeFilter = range7)).records
        val sleep14 = client.readRecords(ReadRecordsRequest(SleepSessionRecord::class, timeRangeFilter = range14)).records
        val workouts7 = client.readRecords(ReadRecordsRequest(ExerciseSessionRecord::class, timeRangeFilter = range7)).records
        val heartRate7 = client.readRecords(ReadRecordsRequest(HeartRateRecord::class, timeRangeFilter = range7)).records
        val hrv7 = client.readRecords(ReadRecordsRequest(HeartRateVariabilityRmssdRecord::class, timeRangeFilter = range7)).records
        val respiratory7 = client.readRecords(ReadRecordsRequest(RespiratoryRateRecord::class, timeRangeFilter = range7)).records
        val oxygen7 = client.readRecords(ReadRecordsRequest(OxygenSaturationRecord::class, timeRangeFilter = range7)).records
        val vo27 = client.readRecords(ReadRecordsRequest(Vo2MaxRecord::class, timeRangeFilter = range7)).records
        val mindfulness7 = client.readRecords(ReadRecordsRequest(MindfulnessSessionRecord::class, timeRangeFilter = range7)).records

        val steps7d = aggregates[StepsRecord.COUNT_TOTAL]
        val avgSteps7d = steps7d?.let { (it / 7L).toInt() }
        val sleepMinutes7 = sleep7.map { Duration.between(it.startTime, it.endTime).toMinutes().toInt() }.filter { it > 0 }
        val sleepMinutes14 = sleep14.map { Duration.between(it.startTime, it.endTime).toMinutes().toInt() }.filter { it > 0 }
        val workoutMinutes = workouts7.map { Duration.between(it.startTime, it.endTime).toMinutes().toInt() }.filter { it > 0 }
        val mindfulMinutes = mindfulness7.sumOf { Duration.between(it.startTime, it.endTime).toMinutes().toInt().coerceAtLeast(0) }
        val heartSamples = heartRate7.flatMap { it.samples }
        val hrv = hrv7.map { it.heartRateVariabilityMillis.toInt() }.averageOrNullInt()
        val restingHeartRate = aggregates[RestingHeartRateRecord.BPM_AVG]?.toInt()
        val oxygen = oxygen7.map { it.percentage.value.toInt() }.averageOrNullInt()
        val latest = latestSignalTime(sleep7, workouts7, heartRate7, hrv7, respiratory7, oxygen7, vo27, mindfulness7)
        val recoveryScore = recoveryScore(
            avgSleepMinutes = sleepMinutes7.averageOrNullInt(),
            avgSteps = avgSteps7d,
            restingHeartRate = restingHeartRate,
            hrv = hrv,
            oxygen = oxygen
        )

        return HealthConnectSummary(
            available = true,
            permissionGranted = true,
            grantedPermissionCount = permissions.size,
            requestedPermissionCount = permissions.size,
            daysRequested = 14,
            daysWithAnySignal = daysWithAnySignal(sleep14, workouts7, heartRate7, hrv7, respiratory7, oxygen7, vo27),
            daysWithSleep = sleep14.map { it.startTime.toLocalDateKey() }.toSet().size,
            daysWithVitals = (heartRate7.map { it.startTime.toLocalDateKey() } +
                hrv7.map { it.time.toLocalDateKey() } +
                respiratory7.map { it.time.toLocalDateKey() } +
                oxygen7.map { it.time.toLocalDateKey() }).toSet().size,
            latestSignalAgeHours = latest?.let { Duration.between(it, end).toHours().coerceAtLeast(0) },
            steps7d = steps7d,
            avgSteps7d = avgSteps7d,
            distanceMeters7d = lengthMeters(aggregates[DistanceRecord.DISTANCE_TOTAL]),
            activeCalories7d = energyKilocalories(aggregates[ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL]),
            totalCalories7d = energyKilocalories(aggregates[TotalCaloriesBurnedRecord.ENERGY_TOTAL]),
            elevationMeters7d = lengthMeters(aggregates[ElevationGainedRecord.ELEVATION_GAINED_TOTAL]),
            floorsClimbed7d = aggregates[FloorsClimbedRecord.FLOORS_CLIMBED_TOTAL]?.toInt(),
            sleepSessions7d = sleep7.size,
            avgSleepMinutes7d = sleepMinutes7.averageOrNullInt(),
            avgSleepEfficiency7d = sleepEfficiency(sleepMinutes7),
            lateSleepNights7d = sleep7.count { it.startTime.atZone(ZoneId.systemDefault()).hour >= 23 || it.startTime.atZone(ZoneId.systemDefault()).hour <= 2 },
            workouts7d = workouts7.size,
            avgWorkoutMinutes7d = workoutMinutes.averageOrNullInt(),
            mindfulMinutes7d = mindfulMinutes.takeIf { it > 0 },
            heartRateSamples7d = heartSamples.size,
            averageHeartRate7d = heartSamples.map { it.beatsPerMinute.toInt() }.averageOrNullInt()
                ?: aggregates[HeartRateRecord.BPM_AVG]?.toInt(),
            restingHeartRate7d = restingHeartRate,
            hrvRmssd7d = hrv,
            respiratoryRate7d = respiratory7.map { it.rate.toInt() }.averageOrNullInt(),
            oxygenSaturation7d = oxygen,
            vo2Max7d = vo27.map { it.vo2MillilitersPerMinuteKilogram.toInt() }.averageOrNullInt(),
            recoveryScore = recoveryScore,
            recoveryTrend = recoveryTrend(sleepMinutes14, recoveryScore)
        )
    }

    private fun isAvailable(): Boolean {
        return Build.VERSION.SDK_INT >= 28 &&
            HealthConnectClient.getSdkStatus(context) != HealthConnectClient.SDK_UNAVAILABLE
    }
}

private fun List<Int>.averageOrNullInt(): Int? = if (isEmpty()) null else average().toInt()

private fun Instant.toLocalDateKey(): LocalDate = atZone(ZoneId.systemDefault()).toLocalDate()

private fun sleepEfficiency(sleepMinutes: List<Int>): Int? {
    if (sleepMinutes.isEmpty()) return null
    val avg = sleepMinutes.average().toInt()
    return (avg * 100 / (avg + 35)).coerceIn(0, 100)
}

private fun recoveryScore(
    avgSleepMinutes: Int?,
    avgSteps: Int?,
    restingHeartRate: Int?,
    hrv: Int?,
    oxygen: Int?
): Int? {
    val parts = buildList {
        avgSleepMinutes?.let { add((it * 100 / (8 * 60)).coerceIn(0, 100)) }
        avgSteps?.let { add((it * 100 / 8000).coerceIn(0, 100)) }
        restingHeartRate?.let { add(((92 - it).coerceIn(0, 40) + 45).coerceIn(0, 100)) }
        hrv?.let { add((it * 100 / 65).coerceIn(0, 100)) }
        oxygen?.let { add(((it - 90) * 10).coerceIn(0, 100)) }
    }
    return parts.averageOrNullInt()
}

private fun recoveryTrend(sleepMinutes14: List<Int>, latestRecovery: Int?): String {
    if (sleepMinutes14.size < 7 || latestRecovery == null) return "learning"
    val first = sleepMinutes14.take(sleepMinutes14.size / 2).averageOrNullInt() ?: return "learning"
    val second = sleepMinutes14.takeLast(sleepMinutes14.size / 2).averageOrNullInt() ?: return "learning"
    return when {
        second - first >= 30 -> "improving"
        first - second >= 30 -> "declining"
        latestRecovery < 45 -> "low"
        else -> "stable"
    }
}

private fun latestSignalTime(vararg groups: List<Any>): Instant? {
    return groups.flatMap { it }.mapNotNull { value ->
        when (value) {
            is SleepSessionRecord -> value.endTime
            is ExerciseSessionRecord -> value.endTime
            is HeartRateRecord -> value.endTime
            is HeartRateVariabilityRmssdRecord -> value.time
            is RespiratoryRateRecord -> value.time
            is OxygenSaturationRecord -> value.time
            is Vo2MaxRecord -> value.time
            is MindfulnessSessionRecord -> value.endTime
            else -> null
        }
    }.maxOrNull()
}

private fun daysWithAnySignal(vararg groups: List<Any>): Int {
    return groups.flatMap { it }.mapNotNull { value ->
        when (value) {
            is SleepSessionRecord -> value.startTime.toLocalDateKey()
            is ExerciseSessionRecord -> value.startTime.toLocalDateKey()
            is HeartRateRecord -> value.startTime.toLocalDateKey()
            is HeartRateVariabilityRmssdRecord -> value.time.toLocalDateKey()
            is RespiratoryRateRecord -> value.time.toLocalDateKey()
            is OxygenSaturationRecord -> value.time.toLocalDateKey()
            is Vo2MaxRecord -> value.time.toLocalDateKey()
            else -> null
        }
    }.toSet().size
}

private fun lengthMeters(value: Any?): Int? {
    return numericGetter(value, "getMeters")
}

private fun energyKilocalories(value: Any?): Int? {
    return numericGetter(value, "getKilocalories")
}

private fun numericGetter(value: Any?, getterName: String): Int? {
    val raw = runCatching { value?.javaClass?.getMethod(getterName)?.invoke(value) as? Number }.getOrNull()
    return raw?.toDouble()?.toInt()
}
