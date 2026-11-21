package com.isaiahgraham.leanrrr.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ShowChart
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.newId
import com.isaiahgraham.leanrrr.data.rememberBoolPref
import com.isaiahgraham.leanrrr.feature.find.FindScreen
import com.isaiahgraham.leanrrr.feature.map.MapScreen
import com.isaiahgraham.leanrrr.feature.meal.MealScreen
import com.isaiahgraham.leanrrr.feature.onboarding.OnboardingScreen
import com.isaiahgraham.leanrrr.feature.progress.ProgressScreen
import com.isaiahgraham.leanrrr.feature.settings.SettingsSheet
import com.isaiahgraham.leanrrr.feature.today.TodayScreen
import com.isaiahgraham.leanrrr.ui.components.MomentsOverlay
import com.isaiahgraham.leanrrr.ui.components.StoreToasts
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrBackground
import com.isaiahgraham.leanrrr.ui.theme.LeanrType

enum class AppTab(val title: String, val icon: ImageVector) {
    TODAY("Today", Icons.Filled.CalendarMonth),
    FIND("Find", Icons.Filled.Search),
    MAP("Map", Icons.Filled.Map),
    MEAL("Meal", Icons.Filled.Restaurant),
    PROGRESS("Progress", Icons.AutoMirrored.Filled.ShowChart),
}

/** Which tab is showing, and requests between screens (Navigator in ContentView.swift). */
class Navigator {
    var tab by mutableStateOf(AppTab.TODAY)
    /** A chain id for Find to filter to; Find clears it once applied. */
    var findChain by mutableStateOf<String?>(null)
    /** Changing these rebuilds a tab, returning it to its main screen. */
    var findStack by mutableStateOf(newId()); private set
    var todayStack by mutableStateOf(newId())
    /** Set by the Scan shortcut: Today opens the barcode scanner. */
    var scanRequested by mutableStateOf(false)
    var settingsOpen by mutableStateOf(false)
    var remindersRequested by mutableStateOf(false)
    var showWeeklyReview by mutableStateOf(false)
    var tourRequested by mutableStateOf(false)

    fun showOptions(chain: String) { findChain = chain; findStack = newId(); tab = AppTab.FIND }

    fun openLink(host: String) {
        when (host) {
            "today" -> { settingsOpen = false; todayStack = newId(); tab = AppTab.TODAY }
            "progress" -> { settingsOpen = false; tab = AppTab.PROGRESS }
            "scan" -> { settingsOpen = false; tab = AppTab.TODAY; scanRequested = true }
            "find" -> { settingsOpen = false; tab = AppTab.FIND }
            "meal" -> { settingsOpen = false; tab = AppTab.MEAL }
        }
    }
}

@Composable
fun AppShell() {
    val store = AppServices.store
    val nav = AppServices.nav
    val c = Leanr.colours
    var onboardingCompleted by rememberBoolPref("leanr.onboarding.completed", false)
    val haptics = LocalHapticFeedback.current

    LaunchedEffect(store.mealsLoggedPulse) { if (store.mealsLoggedPulse > 0) haptics.performHapticFeedback(HapticFeedbackType.Confirm) }
    LaunchedEffect(store.refusedPulse) { if (store.refusedPulse > 0) haptics.performHapticFeedback(HapticFeedbackType.Reject) }
    LaunchedEffect(Unit) {
        kotlinx.coroutines.delay(2500)
        store.launchSettled = true
    }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { AppLifecycle.resumed() }

    if (!onboardingCompleted) {
        LeanrBackground { OnboardingScreen(finished = { onboardingCompleted = true }) }
        return
    }

    LeanrBackground {
        androidx.compose.material3.Scaffold(
            containerColor = androidx.compose.ui.graphics.Color.Transparent,
            bottomBar = {
                NavigationBar(containerColor = c.card.copy(alpha = 0.96f)) {
                    AppTab.entries.forEach { tab ->
                        NavigationBarItem(
                            selected = nav.tab == tab,
                            onClick = {
                                // Tapping the tab you're on goes back to its main screen, as on iOS.
                                if (nav.tab == tab) when (tab) { AppTab.TODAY -> nav.todayStack = newId(); AppTab.FIND -> nav.showOptions(""); else -> {} }
                                nav.tab = tab
                            },
                            icon = {
                                if (tab == AppTab.MEAL && store.data.tray.isNotEmpty()) {
                                    BadgedBox(badge = { Badge { Text("${store.data.tray.size}") } }) { Icon(tab.icon, null) }
                                } else Icon(tab.icon, null)
                            },
                            label = { Text(tab.title, style = LeanrType.tabLabel) },
                            colors = NavigationBarItemDefaults.colors(
                                selectedIconColor = c.accent, selectedTextColor = c.accent, indicatorColor = c.accent.copy(alpha = 0.14f),
                                unselectedIconColor = c.secondaryText, unselectedTextColor = c.secondaryText,
                            ),
                        )
                    }
                }
            },
        ) { padding ->
            Box(Modifier.fillMaxSize().padding(bottom = padding.calculateBottomPadding())) {
                when (nav.tab) {
                    AppTab.TODAY -> key(nav.todayStack) { TodayScreen() }
                    AppTab.FIND -> key(nav.findStack) { FindScreen() }
                    AppTab.MAP -> MapScreen()
                    AppTab.MEAL -> MealScreen()
                    AppTab.PROGRESS -> ProgressScreen()
                }
                StoreToasts(Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top = 8.dp))
            }
        }
        MomentsOverlay()
        com.isaiahgraham.leanrrr.feature.settings.SettingsOverlays()
    }
    if (nav.settingsOpen) SettingsSheet(onDismiss = { nav.settingsOpen = false })
}

/** What runs each time the app comes to the front (scenePhase == .active on iOS). Features add to it with [AppLifecycle.onResume]. */
object AppLifecycle {
    private val handlers = mutableListOf<() -> Unit>()
    fun onResume(handler: () -> Unit) { handlers += handler }
    fun resumed() { handlers.forEach { it() } }
}
