package com.isaiahgraham.leanrrr.feature.settings

import android.app.Activity
import android.app.Application
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.BuildConfig
import com.isaiahgraham.leanrrr.billing.Premium
import com.isaiahgraham.leanrrr.billing.Purchases
import com.isaiahgraham.leanrrr.data.Prefs
import com.isaiahgraham.leanrrr.data.rememberBoolPref
import com.isaiahgraham.leanrrr.ui.AppLifecycle
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Wires Settings into the app at start (AppServices.start on iOS): Google Play Billing, reminders that follow the log,
 * Premium turning on or off, and the weekly review notification's tap. Called once from Startup.register().
 */
object SettingsInstall {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    fun install() {
        val app = AppServices.app
        val store = AppServices.store
        // Premium turning on or off changes the app colour, the widgets, the icon and which reminders are booked.
        if (Premium.SUBSCRIPTIONS_ENABLED) {
            Purchases.onChange = { store.refreshWidgets(); MealReminders.rebook(force = true); AppIcons.resetIfLocked(app) }
            Purchases.start(app)
        }
        // Other features hook `saved` too, so this adds to what's there, after every install() has run, rather than replacing it.
        AppServices.onStart {
            val previous = store.saved
            store.saved = { previous?.invoke(); MealReminders.rebook() }
        }
        MealReminders.rebook(force = true)
        AppLifecycle.onResume {
            if (Premium.SUBSCRIPTIONS_ENABLED) scope.launch { Purchases.refresh() }
            MealReminders.rebook()
        }
        FeatureTips.noteLaunch(Prefs.bool("leanr.onboarding.completed"))
        app.registerActivityLifecycleCallbacks(WeeklyReviewLinks)
    }

    /** The weekly review notification opens Leanrrr with an extra; this turns it into Navigator's weekly review sheet. */
    private object WeeklyReviewLinks : Application.ActivityLifecycleCallbacks {
        private fun handle(intent: Intent?) {
            if (intent?.getBooleanExtra(ReminderReceiver.EXTRA_WEEKLY_REVIEW, false) == true) {
                intent.removeExtra(ReminderReceiver.EXTRA_WEEKLY_REVIEW)
                AppServices.nav.showWeeklyReview = true
            }
            if (BuildConfig.DEBUG && intent?.getBooleanExtra(FeatureTips.DEMO_EXTRA, false) == true) FeatureTips.demo = true
        }
        override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {
            if (savedInstanceState == null) handle(activity.intent)
            (activity as? ComponentActivity)?.addOnNewIntentListener { handle(it) }
        }
        override fun onActivityStarted(activity: Activity) {}
        override fun onActivityResumed(activity: Activity) {}
        override fun onActivityPaused(activity: Activity) {}
        override fun onActivityStopped(activity: Activity) {}
        override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
        override fun onActivityDestroyed(activity: Activity) {}
    }
}

/**
 * What Settings shows over the tabs (ContentView.swift's tour overlay and reminders sheet): the tour of the tabs after first
 * setup and whenever `nav.tourRequested` is set, and the reminders question for someone back after a few days away (or when
 * `nav.remindersRequested` is set). Place once in AppShell, over the tabs.
 */
@Composable
fun SettingsOverlays() {
    val nav = AppServices.nav
    val context = androidx.compose.ui.platform.LocalContext.current
    var tourSeen by rememberBoolPref(TabTour.SEEN_KEY, false)
    var step by remember { mutableStateOf<TourStep?>(null) }
    var reminderPrompt by remember { mutableStateOf(false) }

    // Onboarding is done: after the launch animation, the tour is offered to someone who hasn't had it.
    LaunchedEffect(Unit) {
        if (tourSeen) return@LaunchedEffect
        delay(2500)
        if (!tourSeen && step == null) step = TourStep.TODAY
    }
    LaunchedEffect(nav.tourRequested) {
        if (!nav.tourRequested) return@LaunchedEffect
        nav.tourRequested = false
        nav.settingsOpen = false
        // After the Settings sheet has gone, so the first tab is in view.
        delay(600)
        step = TourStep.TODAY
    }
    LaunchedEffect(nav.remindersRequested) {
        if (!nav.remindersRequested) return@LaunchedEffect
        nav.remindersRequested = false
        reminderPrompt = true
    }
    LaunchedEffect(nav.scanRequested) { if (nav.scanRequested) reminderPrompt = false }

    /** Offers reminders to someone coming back after a few days away with none set up. A first launch never asks straight away. */
    fun checkReminderPrompt() {
        val now = System.currentTimeMillis() / 1000
        val last = Prefs.long(ReminderPrompt.LAST_ACTIVE_KEY)
        Prefs.set(ReminderPrompt.LAST_ACTIVE_KEY, now)
        if (step != null || reminderPrompt || nav.settingsOpen || nav.showWeeklyReview) return
        if (ReminderPrompt.shouldShow(now, last, Prefs.long(ReminderPrompt.ASKED_KEY), MealReminders.anyOn,
                notificationsDenied = !androidx.core.app.NotificationManagerCompat.from(context).areNotificationsEnabled(), canChoose = Premium.isUnlocked)) {
            reminderPrompt = true
        }
    }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { checkReminderPrompt() }
    LifecycleEventEffect(Lifecycle.Event.ON_STOP) { Prefs.set(ReminderPrompt.LAST_ACTIVE_KEY, System.currentTimeMillis() / 1000) }

    Box(Modifier.fillMaxSize()) {
        TabTourOverlay(step, onStep = { step = it }, finished = { tourSeen = true })
    }
    if (reminderPrompt) FullScreenSheet(onDismiss = { reminderPrompt = false }) { ReminderPromptScreen(onDismiss = { reminderPrompt = false }) }
}
