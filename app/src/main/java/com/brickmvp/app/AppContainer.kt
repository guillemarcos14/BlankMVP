package com.brickmvp.app

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.preferencesDataStore
import com.brickmvp.app.data.SessionManager

val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "brick_prefs")

class AppContainer(context: Context) {
    val sessionManager = SessionManager(context.dataStore)
}
