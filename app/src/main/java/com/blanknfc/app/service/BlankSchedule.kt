package com.blanknfc.app.service

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import com.blanknfc.app.data.FocusSchedule
import java.util.Calendar

object BlankSchedule {
    const val ACTION_START = "com.blanknfc.app.action.SCHEDULE_START"
    const val ACTION_END = "com.blanknfc.app.action.SCHEDULE_END"

    fun schedule(context: Context, schedule: FocusSchedule) {
        cancel(context)
        if (!schedule.enabled) return

        val alarmManager = context.getSystemService(AlarmManager::class.java)
        alarmManager.setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            nextTriggerAt(schedule.startMinute),
            pendingIntent(context, ACTION_START, 1001)
        )
        alarmManager.setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            nextTriggerAt(schedule.endMinute),
            pendingIntent(context, ACTION_END, 1002)
        )
    }

    fun cancel(context: Context) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        alarmManager.cancel(pendingIntent(context, ACTION_START, 1001))
        alarmManager.cancel(pendingIntent(context, ACTION_END, 1002))
    }

    private fun pendingIntent(context: Context, action: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, ScheduleReceiver::class.java).setAction(action)
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun nextTriggerAt(minuteOfDay: Int): Long {
        val now = Calendar.getInstance()
        val trigger = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, minuteOfDay / 60)
            set(Calendar.MINUTE, minuteOfDay % 60)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (!after(now)) {
                add(Calendar.DAY_OF_YEAR, 1)
            }
        }
        return trigger.timeInMillis
    }
}
