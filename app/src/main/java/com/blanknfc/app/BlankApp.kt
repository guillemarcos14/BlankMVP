package com.blanknfc.app

import android.app.Application

class BlankApp : Application() {

    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
        container.analyticsTracker.track(
            com.blanknfc.app.analytics.BlankEvent(
                com.blanknfc.app.analytics.BlankEvents.APP_OPENED
            )
        )
    }

    companion object {
        fun get(context: android.content.Context): BlankApp {
            return context.applicationContext as BlankApp
        }
    }
}
