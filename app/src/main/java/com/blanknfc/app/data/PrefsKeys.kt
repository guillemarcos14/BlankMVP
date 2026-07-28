package com.blanknfc.app.data

import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.intPreferencesKey
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
    val STATS_WEEK_KEY = stringPreferencesKey("stats_week_key")
    val STATS_SESSIONS_THIS_WEEK = intPreferencesKey("stats_sessions_this_week")
    val STATS_PROTECTED_MS_THIS_WEEK = longPreferencesKey("stats_protected_ms_this_week")
    val STATS_BLOCKED_ATTEMPTS_THIS_WEEK = intPreferencesKey("stats_blocked_attempts_this_week")
    val STATS_TOTAL_SESSIONS = intPreferencesKey("stats_total_sessions")
    val STATS_TOTAL_PROTECTED_MS = longPreferencesKey("stats_total_protected_ms")
    val STATS_ACTIVITY_DAYS = stringPreferencesKey("stats_activity_days")
    val EMERGENCY_UNLOCK_WEEK_KEY = stringPreferencesKey("emergency_unlock_week_key")
    val EMERGENCY_UNLOCKS_THIS_WEEK = intPreferencesKey("emergency_unlocks_this_week")
    val SCHEDULE_ENABLED = booleanPreferencesKey("schedule_enabled")
    val SCHEDULE_START_MINUTE = intPreferencesKey("schedule_start_minute")
    val SCHEDULE_END_MINUTE = intPreferencesKey("schedule_end_minute")
}
