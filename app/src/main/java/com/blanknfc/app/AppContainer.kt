package com.blanknfc.app

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.preferencesDataStore
import com.blanknfc.app.analytics.LogcatAnalyticsTracker
import com.blanknfc.app.data.SessionManager

val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "blank_prefs")

class AppContainer(context: Context) {
    val analyticsTracker = LogcatAnalyticsTracker()
    val sessionManager = SessionManager(context.dataStore, analyticsTracker = analyticsTracker)
}
