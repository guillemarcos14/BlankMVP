package com.blanknfc.app.analytics

import android.util.Log

class LogcatAnalyticsTracker : AnalyticsTracker {
    override fun track(event: BlankEvent) {
        Log.i("BlankAnalytics", "${event.name} ${event.properties}")
    }
}
