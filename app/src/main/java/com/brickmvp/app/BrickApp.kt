package com.brickmvp.app

import android.app.Application

class BrickApp : Application() {

    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
    }

    companion object {
        fun get(context: android.content.Context): BrickApp {
            return context.applicationContext as BrickApp
        }
    }
}
