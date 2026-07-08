package com.blanknfc.app.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // The AccessibilityService is managed by the system.
        // This receiver ensures the app process starts on boot so
        // DataStore state is loaded and the service can reference it.
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            val pendingResult = goAsync()
            CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
                try {
                    val sessionManager = com.blanknfc.app.BlankApp.get(context).container.sessionManager
                    sessionManager.stateLoaded.filter { it }.first()
                    BlankSchedule.schedule(context, sessionManager.schedule.value)
                } finally {
                    pendingResult.finish()
                }
            }
        }
    }
}
