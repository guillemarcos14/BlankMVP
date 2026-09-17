package com.blanknfc.app.data

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import com.blanknfc.app.analytics.AnalyticsTracker
import com.blanknfc.app.analytics.BlankEvent
import com.blanknfc.app.analytics.BlankEvents
import java.util.Calendar
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

data class FocusStats(
    val sessionsThisWeek: Int = 0,
    val protectedMsThisWeek: Long = 0L,
    val blockedAttemptsThisWeek: Int = 0,
    val totalSessions: Int = 0,
    val totalProtectedMs: Long = 0L,
    val activityDays: List<FocusActivityDay> = emptyList()
)

data class FocusActivityDay(
    val key: String,
    val dayOfWeek: Int,
    val sessions: Int = 0,
    val protectedMs: Long = 0L,
    val blockedAttempts: Int = 0
)

data class FocusSchedule(
    val enabled: Boolean = false,
    val startMinute: Int = 23 * 60 + 30,
    val endMinute: Int = 8 * 60,
    val expiresAtMillis: Long? = null
)

class SessionManager(
    private val dataStore: DataStore<Preferences>,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO),
    private val analyticsTracker: AnalyticsTracker? = null
) {

    private val _isBlankActive = MutableStateFlow(false)
    val isBlankActive: StateFlow<Boolean> = _isBlankActive.asStateFlow()

    private val _blankActiveSince = MutableStateFlow(0L)
    val blankActiveSince: StateFlow<Long> = _blankActiveSince.asStateFlow()

    private val _blockedPackages = MutableStateFlow<Set<String>>(emptySet())
    val blockedPackages: StateFlow<Set<String>> = _blockedPackages.asStateFlow()

    private val _nfcTagUid = MutableStateFlow<String?>(null)
    val nfcTagUid: StateFlow<String?> = _nfcTagUid.asStateFlow()

    private val _setupComplete = MutableStateFlow(false)
    val setupComplete: StateFlow<Boolean> = _setupComplete.asStateFlow()

    private val _stateLoaded = MutableStateFlow(false)
    val stateLoaded: StateFlow<Boolean> = _stateLoaded.asStateFlow()

    private val _isRelinkingNfc = MutableStateFlow(false)
    val isRelinkingNfc: StateFlow<Boolean> = _isRelinkingNfc.asStateFlow()

    private val _nfcRelinkCompleted = MutableStateFlow(false)
    val nfcRelinkCompleted: StateFlow<Boolean> = _nfcRelinkCompleted.asStateFlow()

    private val _stats = MutableStateFlow(FocusStats())
    val stats: StateFlow<FocusStats> = _stats.asStateFlow()

    private val _emergencyUnlocksThisWeek = MutableStateFlow(0)
    val emergencyUnlocksThisWeek: StateFlow<Int> = _emergencyUnlocksThisWeek.asStateFlow()

    private val _emergencyUnlocksRemaining = MutableStateFlow(MAX_EMERGENCY_UNLOCKS_PER_WEEK)
    val emergencyUnlocksRemaining: StateFlow<Int> = _emergencyUnlocksRemaining.asStateFlow()

    private val _schedule = MutableStateFlow(FocusSchedule())
    val schedule: StateFlow<FocusSchedule> = _schedule.asStateFlow()

    private var emergencyUnlockWeekKey = currentWeekKey()

    init {
        scope.launch {
            dataStore.data.collect { prefs ->
                _isBlankActive.value = prefs[PrefsKeys.IS_BLANK_ACTIVE] ?: false
                _blankActiveSince.value = prefs[PrefsKeys.BLANK_ACTIVE_SINCE] ?: 0L
                val savedPackages = prefs[PrefsKeys.BLOCKED_PACKAGES] ?: emptySet()
                val migratedPackages = if (savedPackages.isNotEmpty()) savedPackages else legacySelectedPackages(
                    serialized = prefs[PrefsKeys.LEGACY_FOCUS_MODES],
                    currentId = prefs[PrefsKeys.LEGACY_CURRENT_MODE_ID]
                )
                _blockedPackages.value = migratedPackages
                if (prefs[PrefsKeys.LEGACY_FOCUS_MODES] != null || prefs[PrefsKeys.LEGACY_CURRENT_MODE_ID] != null) {
                    scope.launch {
                        dataStore.edit { stored ->
                            stored[PrefsKeys.BLOCKED_PACKAGES] = migratedPackages
                            stored.remove(PrefsKeys.LEGACY_FOCUS_MODES)
                            stored.remove(PrefsKeys.LEGACY_CURRENT_MODE_ID)
                        }
                    }
                }
                _nfcTagUid.value = prefs[PrefsKeys.NFC_TAG_UID]
                _setupComplete.value = prefs[PrefsKeys.SETUP_COMPLETE] ?: false
                val currentWeekKey = currentWeekKey()
                val storedWeekKey = prefs[PrefsKeys.STATS_WEEK_KEY] ?: currentWeekKey
                val activityDays = parseActivityDays(prefs[PrefsKeys.STATS_ACTIVITY_DAYS])
                val totalSessions = prefs[PrefsKeys.STATS_TOTAL_SESSIONS]
                    ?: activityDays.sumOf { it.sessions }
                val totalProtectedMs = prefs[PrefsKeys.STATS_TOTAL_PROTECTED_MS]
                    ?: activityDays.sumOf { it.protectedMs }
                _stats.value = if (storedWeekKey == currentWeekKey) {
                    FocusStats(
                        sessionsThisWeek = prefs[PrefsKeys.STATS_SESSIONS_THIS_WEEK] ?: 0,
                        protectedMsThisWeek = prefs[PrefsKeys.STATS_PROTECTED_MS_THIS_WEEK] ?: 0L,
                        blockedAttemptsThisWeek = prefs[PrefsKeys.STATS_BLOCKED_ATTEMPTS_THIS_WEEK] ?: 0,
                        totalSessions = totalSessions,
                        totalProtectedMs = totalProtectedMs,
                        activityDays = activityDays
                    )
                } else {
                    FocusStats(
                        totalSessions = totalSessions,
                        totalProtectedMs = totalProtectedMs,
                        activityDays = activityDays
                    )
                }
                val storedEmergencyWeekKey = prefs[PrefsKeys.EMERGENCY_UNLOCK_WEEK_KEY] ?: currentWeekKey
                emergencyUnlockWeekKey = currentWeekKey
                val emergencyUnlocks = if (storedEmergencyWeekKey == currentWeekKey) {
                    prefs[PrefsKeys.EMERGENCY_UNLOCKS_THIS_WEEK] ?: 0
                } else {
                    0
                }
                _emergencyUnlocksThisWeek.value = emergencyUnlocks
                _emergencyUnlocksRemaining.value = (MAX_EMERGENCY_UNLOCKS_PER_WEEK - emergencyUnlocks).coerceAtLeast(0)
                _schedule.value = FocusSchedule(
                    enabled = prefs[PrefsKeys.SCHEDULE_ENABLED] ?: false,
                    startMinute = prefs[PrefsKeys.SCHEDULE_START_MINUTE] ?: (23 * 60 + 30),
                    endMinute = prefs[PrefsKeys.SCHEDULE_END_MINUTE] ?: (8 * 60),
                    expiresAtMillis = prefs[PrefsKeys.SCHEDULE_EXPIRES_AT]?.takeIf { it > 0L }
                )
                _stateLoaded.value = true
            }
        }
    }

    fun isAppBlocked(packageName: String): Boolean {
        return _isBlankActive.value && _blockedPackages.value.contains(packageName)
    }

    suspend fun isAppBlockedAfterLoad(packageName: String): Boolean {
        if (!_stateLoaded.value) {
            _stateLoaded.filter { it }.first()
        }
        return isAppBlocked(packageName)
    }

    fun handleNfcTag(uid: String): NfcResult {
        val savedUid = _nfcTagUid.value

        if (savedUid == null) {
            _nfcTagUid.value = uid
            analyticsTracker?.track(BlankEvent(BlankEvents.NFC_TAG_REGISTERED))
            scope.launch {
                dataStore.edit { prefs ->
                    prefs[PrefsKeys.NFC_TAG_UID] = uid
                }
            }
            return NfcResult.TAG_REGISTERED
        }

        if (savedUid != uid) {
            analyticsTracker?.track(BlankEvent(BlankEvents.NFC_WRONG_TAG))
            return NfcResult.WRONG_TAG
        }

        if (!_isBlankActive.value) {
            return NfcResult.NOT_ACTIVE
        }

        val savedStart = _blankActiveSince.value
        _isBlankActive.value = false
        _blankActiveSince.value = 0L
        recordSessionCompleted(savedStart = savedStart)
        scope.launch {
            dataStore.edit { prefs ->
                prefs[PrefsKeys.IS_BLANK_ACTIVE] = false
                prefs[PrefsKeys.BLANK_ACTIVE_SINCE] = 0L
            }
        }
        analyticsTracker?.track(
            BlankEvent(
                BlankEvents.BLANK_MODE_DEACTIVATED,
                mapOf("blocked_app_count" to _blockedPackages.value.size.toString())
            )
        )
        return NfcResult.UNBLANKED
    }

    fun activateBlank(): NfcResult {
        if (_blockedPackages.value.isEmpty()) {
            analyticsTracker?.track(BlankEvent(BlankEvents.NFC_NO_APPS_SELECTED))
            return NfcResult.NO_APPS_SELECTED
        }
        if (_isBlankActive.value) {
            return NfcResult.BLANKED
        }

        _isBlankActive.value = true
        _blankActiveSince.value = System.currentTimeMillis()
        scope.launch {
            dataStore.edit { prefs ->
                prefs[PrefsKeys.IS_BLANK_ACTIVE] = true
                prefs[PrefsKeys.BLANK_ACTIVE_SINCE] = _blankActiveSince.value
            }
        }
        analyticsTracker?.track(
            BlankEvent(
                BlankEvents.BLANK_MODE_ACTIVATED,
                mapOf("blocked_app_count" to _blockedPackages.value.size.toString())
            )
        )
        return NfcResult.BLANKED
    }

    fun setBlockedPackages(packages: Set<String>) {
        _blockedPackages.value = packages
        analyticsTracker?.track(
            BlankEvent(
                BlankEvents.BLOCKED_APPS_UPDATED,
                mapOf("blocked_app_count" to packages.size.toString())
            )
        )
        scope.launch {
            dataStore.edit { prefs ->
                prefs[PrefsKeys.BLOCKED_PACKAGES] = packages
            }
        }
    }

    fun setNfcTag(uid: String) {
        _nfcTagUid.value = uid
        _isRelinkingNfc.value = false
        analyticsTracker?.track(BlankEvent(BlankEvents.NFC_TAG_REGISTERED))
        scope.launch {
            dataStore.edit { prefs ->
                prefs[PrefsKeys.NFC_TAG_UID] = uid
            }
        }
    }

    fun startNfcRelink() {
        _isRelinkingNfc.value = true
        _nfcRelinkCompleted.value = false
    }

    fun cancelNfcRelink() {
        _isRelinkingNfc.value = false
    }

    fun completeNfcRelink(uid: String) {
        setNfcTag(uid)
        _nfcRelinkCompleted.value = true
    }

    fun deactivateForEmergency(): Boolean {
        resetEmergencyUnlocksIfNeeded()
        if (_isBlankActive.value && _emergencyUnlocksThisWeek.value >= MAX_EMERGENCY_UNLOCKS_PER_WEEK) {
            return false
        }

        if (_isBlankActive.value) {
            val updatedEmergencyUnlocks = _emergencyUnlocksThisWeek.value + 1
            _emergencyUnlocksThisWeek.value = updatedEmergencyUnlocks
            _emergencyUnlocksRemaining.value = (MAX_EMERGENCY_UNLOCKS_PER_WEEK - updatedEmergencyUnlocks).coerceAtLeast(0)
        }

        val savedStart = _blankActiveSince.value
        _isBlankActive.value = false
        _blankActiveSince.value = 0L
        recordSessionCompleted(savedStart = savedStart)
        scope.launch {
            dataStore.edit { prefs ->
                prefs[PrefsKeys.IS_BLANK_ACTIVE] = false
                prefs[PrefsKeys.BLANK_ACTIVE_SINCE] = 0L
                prefs[PrefsKeys.EMERGENCY_UNLOCK_WEEK_KEY] = emergencyUnlockWeekKey
                prefs[PrefsKeys.EMERGENCY_UNLOCKS_THIS_WEEK] = _emergencyUnlocksThisWeek.value
            }
        }
        analyticsTracker?.track(BlankEvent(BlankEvents.BLANK_MODE_DEACTIVATED))
        return true
    }

    fun forgetNfcTag() {
        _nfcTagUid.value = null
        _isBlankActive.value = false
        _blankActiveSince.value = 0L
        _setupComplete.value = false
        analyticsTracker?.track(BlankEvent(BlankEvents.TAG_FORGOTTEN))
        scope.launch {
            dataStore.edit { prefs ->
                prefs.remove(PrefsKeys.NFC_TAG_UID)
                prefs[PrefsKeys.IS_BLANK_ACTIVE] = false
                prefs[PrefsKeys.BLANK_ACTIVE_SINCE] = 0L
                prefs[PrefsKeys.SETUP_COMPLETE] = false
            }
        }
    }

    fun setSetupComplete() {
        _setupComplete.value = true
        analyticsTracker?.track(
            BlankEvent(
                BlankEvents.SETUP_COMPLETED,
                mapOf("blocked_app_count" to _blockedPackages.value.size.toString())
            )
        )
        scope.launch {
            dataStore.edit { prefs ->
                prefs[PrefsKeys.SETUP_COMPLETE] = true
            }
        }
    }

    fun recordBlockedAttempt() {
        val updated = _stats.value.copy(
            blockedAttemptsThisWeek = _stats.value.blockedAttemptsThisWeek + 1,
            activityDays = updateTodayActivity(_stats.value.activityDays, blockedAttemptsDelta = 1)
        )
        _stats.value = updated
        scope.launch {
            persistStats(updated)
        }
    }

    fun updateSchedule(schedule: FocusSchedule) {
        val cleanSchedule = schedule.copy(
            startMinute = schedule.startMinute.coerceIn(0, MINUTES_PER_DAY - 1),
            endMinute = schedule.endMinute.coerceIn(0, MINUTES_PER_DAY - 1)
        )
        _schedule.value = cleanSchedule
        scope.launch {
            dataStore.edit { prefs ->
                prefs[PrefsKeys.SCHEDULE_ENABLED] = cleanSchedule.enabled
                prefs[PrefsKeys.SCHEDULE_START_MINUTE] = cleanSchedule.startMinute
                prefs[PrefsKeys.SCHEDULE_END_MINUTE] = cleanSchedule.endMinute
                if (cleanSchedule.expiresAtMillis == null) {
                    prefs.remove(PrefsKeys.SCHEDULE_EXPIRES_AT)
                } else {
                    prefs[PrefsKeys.SCHEDULE_EXPIRES_AT] = cleanSchedule.expiresAtMillis
                }
            }
        }
    }

    fun applyScheduleWindow(nowMillis: Long = System.currentTimeMillis()) {
        resetEmergencyUnlocksIfNeeded()

        val schedule = _schedule.value
        if (schedule.expiresAtMillis?.let { nowMillis >= it } == true) {
            expireSchedule()
            return
        }
        if (!schedule.enabled) return
        if (isMinuteInWindow(minuteOfDay(nowMillis), schedule.startMinute, schedule.endMinute)) {
            activateBlank()
        } else if (_isBlankActive.value) {
            val savedStart = _blankActiveSince.value
            _isBlankActive.value = false
            _blankActiveSince.value = 0L
            recordSessionCompleted(savedStart = savedStart)
            scope.launch {
                dataStore.edit { prefs ->
                    prefs[PrefsKeys.IS_BLANK_ACTIVE] = false
                    prefs[PrefsKeys.BLANK_ACTIVE_SINCE] = 0L
                }
            }
        }
    }

    enum class NfcResult {
        TAG_REGISTERED,
        BLANKED,
        UNBLANKED,
        WRONG_TAG,
        NO_APPS_SELECTED,
        NOT_ACTIVE
    }

    fun expireSchedule() {
        val schedule = _schedule.value
        if (!schedule.enabled && schedule.expiresAtMillis == null) return

        if (_isBlankActive.value) {
            val savedStart = _blankActiveSince.value
            _isBlankActive.value = false
            _blankActiveSince.value = 0L
            recordSessionCompleted(savedStart = savedStart)
        }

        updateSchedule(schedule.copy(enabled = false, expiresAtMillis = null))
    }

    private fun legacySelectedPackages(serialized: String?, currentId: String?): Set<String> {
        if (serialized.isNullOrBlank()) return emptySet()
        val selections = serialized.split(MODE_SEPARATOR).mapNotNull { raw ->
            val parts = raw.split(FIELD_SEPARATOR)
            if (parts.size < 3) null else parts[0] to parts[2].split(PACKAGE_SEPARATOR).filter { it.isNotBlank() }.toSet()
        }
        return selections.firstOrNull { it.first == currentId }?.second
            ?: selections.firstOrNull { it.second.isNotEmpty() }?.second
            ?: emptySet()
    }

    private fun recordSessionCompleted(savedStart: Long) {
        if (savedStart <= 0L) return
        val elapsed = (System.currentTimeMillis() - savedStart).coerceAtLeast(0L)
        val updated = _stats.value.copy(
            sessionsThisWeek = _stats.value.sessionsThisWeek + 1,
            protectedMsThisWeek = _stats.value.protectedMsThisWeek + elapsed,
            totalSessions = _stats.value.totalSessions + 1,
            totalProtectedMs = _stats.value.totalProtectedMs + elapsed,
            activityDays = updateTodayActivity(
                _stats.value.activityDays,
                sessionsDelta = 1,
                protectedMsDelta = elapsed
            )
        )
        _stats.value = updated
        scope.launch {
            persistStats(updated)
        }
    }

    private suspend fun persistStats(stats: FocusStats) {
        dataStore.edit { prefs ->
            prefs[PrefsKeys.STATS_WEEK_KEY] = currentWeekKey()
            prefs[PrefsKeys.STATS_SESSIONS_THIS_WEEK] = stats.sessionsThisWeek
            prefs[PrefsKeys.STATS_PROTECTED_MS_THIS_WEEK] = stats.protectedMsThisWeek
            prefs[PrefsKeys.STATS_BLOCKED_ATTEMPTS_THIS_WEEK] = stats.blockedAttemptsThisWeek
            prefs[PrefsKeys.STATS_TOTAL_SESSIONS] = stats.totalSessions
            prefs[PrefsKeys.STATS_TOTAL_PROTECTED_MS] = stats.totalProtectedMs
            prefs[PrefsKeys.STATS_ACTIVITY_DAYS] = serializeActivityDays(stats.activityDays)
        }
    }

    private fun updateTodayActivity(
        days: List<FocusActivityDay>,
        sessionsDelta: Int = 0,
        protectedMsDelta: Long = 0L,
        blockedAttemptsDelta: Int = 0
    ): List<FocusActivityDay> {
        val today = todayKey()
        val existing = days.firstOrNull { it.key == today }
            ?: FocusActivityDay(key = today, dayOfWeek = currentDayOfWeek())
        val updatedToday = existing.copy(
            dayOfWeek = currentDayOfWeek(),
            sessions = existing.sessions + sessionsDelta,
            protectedMs = existing.protectedMs + protectedMsDelta,
            blockedAttempts = existing.blockedAttempts + blockedAttemptsDelta
        )
        return (days.filterNot { it.key == today } + updatedToday)
            .sortedBy { it.key }
            .takeLast(366)
    }

    private fun serializeActivityDays(days: List<FocusActivityDay>): String {
        return days.sortedBy { it.key }.takeLast(366).joinToString(";") { day ->
            listOf(
                day.key,
                day.dayOfWeek.toString(),
                day.sessions.toString(),
                day.protectedMs.toString(),
                day.blockedAttempts.toString()
            ).joinToString(",")
        }
    }

    private fun parseActivityDays(raw: String?): List<FocusActivityDay> {
        if (raw.isNullOrBlank()) return emptyList()
        return raw.split(";").mapNotNull { item ->
            val parts = item.split(",")
            if (parts.size != 5) return@mapNotNull null
            FocusActivityDay(
                key = parts[0],
                dayOfWeek = parts[1].toIntOrNull() ?: Calendar.MONDAY,
                sessions = parts[2].toIntOrNull() ?: 0,
                protectedMs = parts[3].toLongOrNull() ?: 0L,
                blockedAttempts = parts[4].toIntOrNull() ?: 0
            )
        }.sortedBy { it.key }.takeLast(366)
    }

    private fun resetEmergencyUnlocksIfNeeded() {
        val currentWeekKey = currentWeekKey()
        if (emergencyUnlockWeekKey == currentWeekKey) return
        emergencyUnlockWeekKey = currentWeekKey
        _emergencyUnlocksThisWeek.value = 0
        _emergencyUnlocksRemaining.value = MAX_EMERGENCY_UNLOCKS_PER_WEEK
    }

    companion object {
        private const val MINUTES_PER_DAY = 24 * 60
        private const val MAX_EMERGENCY_UNLOCKS_PER_WEEK = 3
        private const val MODE_SEPARATOR = ";"
        private const val FIELD_SEPARATOR = "|"
        private const val PACKAGE_SEPARATOR = ","

        private fun currentWeekKey(): String {
            val calendar = Calendar.getInstance().apply {
                firstDayOfWeek = Calendar.MONDAY
                minimalDaysInFirstWeek = 4
            }
            val year = calendar.getWeekYear()
            val week = calendar.get(Calendar.WEEK_OF_YEAR)
            return "$year-$week"
        }

        private fun todayKey(): String {
            val calendar = Calendar.getInstance()
            val year = calendar.get(Calendar.YEAR)
            val day = calendar.get(Calendar.DAY_OF_YEAR).toString().padStart(3, '0')
            return "$year-$day"
        }

        private fun currentDayOfWeek(): Int {
            return Calendar.getInstance().get(Calendar.DAY_OF_WEEK)
        }

        private fun minuteOfDay(nowMillis: Long): Int {
            val calendar = Calendar.getInstance().apply { timeInMillis = nowMillis }
            return calendar.get(Calendar.HOUR_OF_DAY) * 60 + calendar.get(Calendar.MINUTE)
        }

        private fun isMinuteInWindow(minute: Int, start: Int, end: Int): Boolean {
            return if (start < end) {
                minute in start until end
            } else {
                minute >= start || minute < end
            }
        }
    }
}
