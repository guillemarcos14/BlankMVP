package com.blanknfc.app.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.blanknfc.app.BlankApp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

class ScheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pendingResult = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try {
                val sessionManager = BlankApp.get(context).container.sessionManager
                sessionManager.stateLoaded.filter { it }.first()
                sessionManager.applyScheduleWindow()
                BlankSchedule.schedule(context, sessionManager.schedule.value)
            } finally {
                pendingResult.finish()
            }
        }
    }
}
