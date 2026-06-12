package com.brickmvp.app.data

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

class SessionManager(private val dataStore: DataStore<Preferences>) {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _isBricked = MutableStateFlow(false)
    val isBricked: StateFlow<Boolean> = _isBricked.asStateFlow()

    private val _brickedSince = MutableStateFlow(0L)
    val brickedSince: StateFlow<Long> = _brickedSince.asStateFlow()

    private val _blockedPackages = MutableStateFlow<Set<String>>(emptySet())
    val blockedPackages: StateFlow<Set<String>> = _blockedPackages.asStateFlow()

    private val _nfcTagUid = MutableStateFlow<String?>(null)
    val nfcTagUid: StateFlow<String?> = _nfcTagUid.asStateFlow()

    private val _setupComplete = MutableStateFlow(false)
    val setupComplete: StateFlow<Boolean> = _setupComplete.asStateFlow()

    init {
        scope.launch {
            dataStore.data.collect { prefs ->
                _isBricked.value = prefs[PrefsKeys.IS_BRICKED] ?: false
                _brickedSince.value = prefs[PrefsKeys.BRICKED_SINCE] ?: 0L
                _blockedPackages.value = prefs[PrefsKeys.BLOCKED_PACKAGES] ?: emptySet()
                _nfcTagUid.value = prefs[PrefsKeys.NFC_TAG_UID]
                _setupComplete.value = prefs[PrefsKeys.SETUP_COMPLETE] ?: false
            }
        }
    }

    fun isAppBlocked(packageName: String): Boolean {
        return _isBricked.value && _blockedPackages.value.contains(packageName)
    }

    fun handleNfcTag(uid: String): NfcResult {
        val savedUid = _nfcTagUid.value

        // First time: register the tag
        if (savedUid == null) {
            scope.launch {
                dataStore.edit { prefs ->
                    prefs[PrefsKeys.NFC_TAG_UID] = uid
                }
            }
            return NfcResult.TAG_REGISTERED
        }

        // Wrong tag
        if (savedUid != uid) {
            return NfcResult.WRONG_TAG
        }

        // Toggle brick mode
        val newState = !_isBricked.value
        scope.launch {
            dataStore.edit { prefs ->
                prefs[PrefsKeys.IS_BRICKED] = newState
                if (newState) {
                    prefs[PrefsKeys.BRICKED_SINCE] = System.currentTimeMillis()
                } else {
                    prefs[PrefsKeys.BRICKED_SINCE] = 0L
                }
            }
        }
        return if (newState) NfcResult.BRICKED else NfcResult.UNBRICKED
    }

    fun setBlockedPackages(packages: Set<String>) {
        scope.launch {
            dataStore.edit { prefs ->
                prefs[PrefsKeys.BLOCKED_PACKAGES] = packages
            }
        }
    }

    fun setSetupComplete() {
        scope.launch {
            dataStore.edit { prefs ->
                prefs[PrefsKeys.SETUP_COMPLETE] = true
            }
        }
    }

    enum class NfcResult {
        TAG_REGISTERED,
        BRICKED,
        UNBRICKED,
        WRONG_TAG
    }
}
