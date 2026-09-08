package com.blanknfc.app.analytics

interface AnalyticsTracker {
    fun track(event: BlankEvent)
}

data class BlankEvent(
    val name: String,
    val properties: Map<String, String> = emptyMap()
)

object BlankEvents {
    const val APP_OPENED = "app_opened"
    const val SETUP_STEP_VIEWED = "onboarding_step_viewed"
    const val SETUP_COMPLETED = "setup_completed"
    const val NFC_TAG_REGISTERED = "nfc_tag_registered"
    const val NFC_WRONG_TAG = "nfc_wrong_tag"
    const val NFC_NO_APPS_SELECTED = "nfc_no_apps_selected"
    const val BLANK_MODE_ACTIVATED = "blank_mode_activated"
    const val BLANK_MODE_DEACTIVATED = "blank_mode_deactivated"
    const val BLOCKED_APPS_UPDATED = "blocked_apps_updated"
    const val BLOCK_SCREEN_SHOWN = "block_screen_shown"
    const val NFC_SCAN_FAILED = "nfc_scan_failed"
    const val TAG_FORGOTTEN = "tag_forgotten"
    const val PERMISSION_REQUESTED = "permission_requested"
    const val PERMISSION_GRANTED = "permission_granted"
    const val HEALTH_DATA_AVAILABLE = "health_data_available"
    const val STALE_HEALTH_DATA = "stale_health_data"
    const val PROACTIVE_HEALTH_ALERT = "proactive_health_alert"
    const val WEARABLE_SOURCE_VIEWED = "wearable_source_viewed"
    const val WEARABLE_CONNECT_STARTED = "wearable_connect_started"
    const val WEARABLE_CONNECTED = "wearable_connected"
    const val WEARABLE_DATA_AVAILABLE = "wearable_data_available"
    const val WEARABLE_DATA_STALE = "wearable_data_stale"
}
