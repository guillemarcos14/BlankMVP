package com.brickmvp.app.data

import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.stringSetPreferencesKey

object PrefsKeys {
    val IS_BRICKED = booleanPreferencesKey("is_bricked")
    val BRICKED_SINCE = longPreferencesKey("bricked_since")
    val BLOCKED_PACKAGES = stringSetPreferencesKey("blocked_packages")
    val NFC_TAG_UID = stringPreferencesKey("nfc_tag_uid")
    val SETUP_COMPLETE = booleanPreferencesKey("setup_complete")
}
