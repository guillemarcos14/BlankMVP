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
    const val SETUP_STEP_VIEWED = "setup_step_viewed"
    const val SETUP_COMPLETED = "setup_completed"
    const val NFC_TAG_REGISTERED = "nfc_tag_registered"
    const val NFC_WRONG_TAG = "nfc_wrong_tag"
    const val NFC_NO_APPS_SELECTED = "nfc_no_apps_selected"
    const val BLANK_MODE_ACTIVATED = "BLANK_MODE_activated"
    const val BLANK_MODE_DEACTIVATED = "BLANK_MODE_deactivated"
    const val BLOCKED_APPS_UPDATED = "blocked_apps_updated"
    const val BLOCK_SCREEN_SHOWN = "block_screen_shown"
    const val NFC_SCAN_FAILED = "nfc_scan_failed"
    const val TAG_FORGOTTEN = "tag_forgotten"
}
