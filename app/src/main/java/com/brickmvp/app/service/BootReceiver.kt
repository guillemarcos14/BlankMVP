package com.brickmvp.app.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // The AccessibilityService is managed by the system.
        // This receiver ensures the app process starts on boot so
        // DataStore state is loaded and the service can reference it.
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            // Simply accessing the app container initializes SessionManager
            com.brickmvp.app.BrickApp.get(context).container
        }
    }
}
