package com.blanknfc.app.data

import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.stringSetPreferencesKey

object PrefsKeys {
    val IS_BLANK_ACTIVE = booleanPreferencesKey("IS_BLANK_ACTIVE")
    val BLANK_ACTIVE_SINCE = longPreferencesKey("BLANK_ACTIVE_SINCE")
    val BLOCKED_PACKAGES = stringSetPreferencesKey("blocked_packages")
    val FOCUS_MODES = stringPreferencesKey("focus_modes")
    val CURRENT_MODE_ID = stringPreferencesKey("current_mode_id")
    val NFC_TAG_UID = stringPreferencesKey("nfc_tag_uid")
    val SETUP_COMPLETE = booleanPreferencesKey("setup_complete")
    val BACKGROUND_THEME_ID = stringPreferencesKey("background_theme_id")
}
