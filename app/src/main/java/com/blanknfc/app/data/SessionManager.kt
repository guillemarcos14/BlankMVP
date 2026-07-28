package com.blanknfc.app.data

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import com.blanknfc.app.analytics.AnalyticsTracker
import com.blanknfc.app.analytics.BlankEvent
import com.blanknfc.app.analytics.BlankEvents
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

data class BlankMode(
    val id: String,
    val name: String,
    val packages: Set<String>
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

    private val _modes = MutableStateFlow<List<BlankMode>>(defaultModes())
    val modes: StateFlow<List<BlankMode>> = _modes.asStateFlow()

    private val _currentModeId = MutableStateFlow(DEFAULT_MODE_ID)
    val currentModeId: StateFlow<String> = _currentModeId.asStateFlow()

    private val _nfcTagUid = MutableStateFlow<String?>(null)
    val nfcTagUid: StateFlow<String?> = _nfcTagUid.asStateFlow()

    private val _setupComplete = MutableStateFlow(false)
    val setupComplete: StateFlow<Boolean> = _setupComplete.asStateFlow()

    private val _backgroundThemeId = MutableStateFlow(DEFAULT_BACKGROUND_THEME_ID)
    val backgroundThemeId: StateFlow<String> = _backgroundThemeId.asStateFlow()

    private val _stateLoaded = MutableStateFlow(false)
    val stateLoaded: StateFlow<Boolean> = _stateLoaded.asStateFlow()

    private val _isRelinkingNfc = MutableStateFlow(false)
    val isRelinkingNfc: StateFlow<Boolean> = _isRelinkingNfc.asStateFlow()

    private val _nfcRelinkCompleted = MutableStateFlow(false)
    val nfcRelinkCompleted: StateFlow<Boolean> = _nfcRelinkCompleted.asStateFlow()

    init {
        scope.launch {
            dataStore.data.collect { prefs ->
                _isBlankActive.value = prefs[PrefsKeys.IS_BLANK_ACTIVE] ?: false
                _blankActiveSince.value = prefs[PrefsKeys.BLANK_ACTIVE_SINCE] ?: 0L
                val legacyPackages = prefs[PrefsKeys.BLOCKED_PACKAGES] ?: emptySet()
                val parsedModes = parseModes(prefs[PrefsKeys.FOCUS_MODES], legacyPackages)
                val currentId = prefs[PrefsKeys.CURRENT_MODE_ID]
                    ?.takeIf { id -> parsedModes.any { it.id == id } }
                    ?: parsedModes.first().id
                _modes.value = parsedModes
                _currentModeId.value = currentId
                _blockedPackages.value = parsedModes.first { it.id == currentId }.packages
                _nfcTagUid.value = prefs[PrefsKeys.NFC_TAG_UID]
                _setupComplete.value = prefs[PrefsKeys.SETUP_COMPLETE] ?: false
                _backgroundThemeId.value = prefs[PrefsKeys.BACKGROUND_THEME_ID] ?: DEFAULT_BACKGROUND_THEME_ID
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

        _isBlankActive.value = false
        _blankActiveSince.value = 0L
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
        return NfcResult.UNBRICKED
    }

    fun activateBlank(): NfcResult {
        if (_blockedPackages.value.isEmpty()) {
            analyticsTracker?.track(BlankEvent(BlankEvents.NFC_NO_APPS_SELECTED))
            return NfcResult.NO_APPS_SELECTED
        }
        if (_isBlankActive.value) {
            return NfcResult.BRICKED
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
        return NfcResult.BRICKED
    }

    fun setBlockedPackages(packages: Set<String>) {
        _blockedPackages.value = packages
        _modes.value = _modes.value.map { mode ->
            if (mode.id == _currentModeId.value) mode.copy(packages = packages) else mode
        }
        analyticsTracker?.track(
            BlankEvent(
                BlankEvents.BLOCKED_APPS_UPDATED,
                mapOf("blocked_app_count" to packages.size.toString())
            )
        )
        scope.launch {
            dataStore.edit { prefs ->
                prefs[PrefsKeys.BLOCKED_PACKAGES] = packages
                prefs[PrefsKeys.FOCUS_MODES] = serializeModes(_modes.value)
            }
        }
    }

    fun selectMode(modeId: String) {
        val mode = _modes.value.firstOrNull { it.id == modeId } ?: return
        _currentModeId.value = mode.id
        _blockedPackages.value = mode.packages
        scope.launch {
            dataStore.edit { prefs ->
                prefs[PrefsKeys.CURRENT_MODE_ID] = mode.id
                prefs[PrefsKeys.BLOCKED_PACKAGES] = mode.packages
            }
        }
    }

    fun createMode(name: String, packages: Set<String>) {
        val cleanName = name.trim().ifBlank { "Nuevo modo" }
        val mode = BlankMode(
            id = "mode_${System.currentTimeMillis()}",
            name = cleanName,
            packages = packages
        )
        _modes.value = _modes.value + mode
        selectMode(mode.id)
        persistModes()
    }

    fun renameMode(modeId: String, name: String) {
        val cleanName = name.trim()
        if (cleanName.isBlank()) return
        _modes.value = _modes.value.map { mode ->
            if (mode.id == modeId) mode.copy(name = cleanName) else mode
        }
        persistModes()
    }

    fun updateModePackages(modeId: String, packages: Set<String>) {
        _modes.value = _modes.value.map { mode ->
            if (mode.id == modeId) mode.copy(packages = packages) else mode
        }
        if (_currentModeId.value == modeId) {
            _blockedPackages.value = packages
        }
        analyticsTracker?.track(
            BlankEvent(
                BlankEvents.BLOCKED_APPS_UPDATED,
                mapOf("blocked_app_count" to packages.size.toString())
            )
        )
        scope.launch {
            dataStore.edit { prefs ->
                prefs[PrefsKeys.FOCUS_MODES] = serializeModes(_modes.value)
                if (_currentModeId.value == modeId) {
                    prefs[PrefsKeys.BLOCKED_PACKAGES] = packages
                }
            }
        }
    }

    fun deleteMode(modeId: String) {
        if (_modes.value.size <= 1) return
        val updated = _modes.value.filterNot { it.id == modeId }
        _modes.value = updated
        if (_currentModeId.value == modeId) {
            selectMode(updated.first().id)
        }
        persistModes()
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

    fun deactivateForEmergency() {
        _isBlankActive.value = false
        _blankActiveSince.value = 0L
        scope.launch {
            dataStore.edit { prefs ->
                prefs[PrefsKeys.IS_BLANK_ACTIVE] = false
                prefs[PrefsKeys.BLANK_ACTIVE_SINCE] = 0L
            }
        }
        analyticsTracker?.track(BlankEvent(BlankEvents.BLANK_MODE_DEACTIVATED))
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

    fun selectBackgroundTheme(themeId: String) {
        _backgroundThemeId.value = themeId
        scope.launch {
            dataStore.edit { prefs ->
                prefs[PrefsKeys.BACKGROUND_THEME_ID] = themeId
            }
        }
    }

    enum class NfcResult {
        TAG_REGISTERED,
        BRICKED,
        UNBRICKED,
        WRONG_TAG,
        NO_APPS_SELECTED,
        NOT_ACTIVE
    }

    private fun persistModes() {
        scope.launch {
            dataStore.edit { prefs ->
                prefs[PrefsKeys.FOCUS_MODES] = serializeModes(_modes.value)
                prefs[PrefsKeys.CURRENT_MODE_ID] = _currentModeId.value
                prefs[PrefsKeys.BLOCKED_PACKAGES] = _blockedPackages.value
            }
        }
    }

    private fun parseModes(serialized: String?, legacyPackages: Set<String>): List<BlankMode> {
        if (serialized.isNullOrBlank()) {
            return listOf(BlankMode(DEFAULT_MODE_ID, "Rutina diaria", legacyPackages))
        }

        val modes = serialized.split(MODE_SEPARATOR).mapNotNull { rawMode ->
            val parts = rawMode.split(FIELD_SEPARATOR)
            if (parts.size < 3) return@mapNotNull null
            BlankMode(
                id = parts[0],
                name = decode(parts[1]).ifBlank { "Modo" },
                packages = parts[2].split(PACKAGE_SEPARATOR).filter { it.isNotBlank() }.toSet()
            )
        }

        return modes.ifEmpty { listOf(BlankMode(DEFAULT_MODE_ID, "Rutina diaria", legacyPackages)) }
    }

    private fun serializeModes(modes: List<BlankMode>): String {
        return modes.joinToString(MODE_SEPARATOR) { mode ->
            listOf(
                mode.id,
                encode(mode.name),
                mode.packages.joinToString(PACKAGE_SEPARATOR)
            ).joinToString(FIELD_SEPARATOR)
        }
    }

    private fun encode(value: String): String {
        return value
            .replace("%", "%25")
            .replace("|", "%7C")
            .replace(";", "%3B")
            .replace(",", "%2C")
    }

    private fun decode(value: String): String {
        return value
            .replace("%2C", ",")
            .replace("%3B", ";")
            .replace("%7C", "|")
            .replace("%25", "%")
    }

    companion object {
        const val DEFAULT_BACKGROUND_THEME_ID = "blank"

        private const val DEFAULT_MODE_ID = "daily"
        private const val MODE_SEPARATOR = ";"
        private const val FIELD_SEPARATOR = "|"
        private const val PACKAGE_SEPARATOR = ","

        private fun defaultModes(): List<BlankMode> {
            return listOf(BlankMode(DEFAULT_MODE_ID, "Rutina diaria", emptySet()))
        }
    }
}
