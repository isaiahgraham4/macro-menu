package com.isaiahgraham.leanrrr

/**
 * Where each feature wires itself into the store when the app starts (Health Connect hooks, widget refreshes, reminders,
 * billing). Each feature adds one line here calling its own `install()`.
 */
object Startup {
    fun register() {
        com.isaiahgraham.leanrrr.feature.settings.SettingsInstall.install()
        com.isaiahgraham.leanrrr.feature.progress.ProgressFeature.install()
        com.isaiahgraham.leanrrr.feature.today.TodayStartup.install()
        com.isaiahgraham.leanrrr.feature.widgets.PlatformHooks.install()
    }
}
