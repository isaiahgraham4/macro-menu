package com.isaiahgraham.leanrrr

import android.app.Application
import com.isaiahgraham.leanrrr.data.AppStore
import com.isaiahgraham.leanrrr.data.Prefs
import com.isaiahgraham.leanrrr.ui.Navigator

class LeanrApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Prefs.init(this)
        AppServices.start(this)
    }
}

/**
 * The single store and navigator (AppServices.swift). Widgets, workers and notification actions reach the same store
 * through here, so there's never a second copy of the data in memory.
 */
object AppServices {
    lateinit var app: Application
        private set
    lateinit var store: AppStore
        private set
    val nav = Navigator()

    /** Hooks other features register at start (Health Connect, widgets, reminders). Run once, after the store exists. */
    private val starters = mutableListOf<(Application) -> Unit>()
    fun onStart(starter: (Application) -> Unit) { starters += starter }

    fun start(application: Application) {
        if (::store.isInitialized) return
        app = application
        store = AppStore(application)
        Startup.register()
        starters.forEach { it(application) }
    }
}
