package com.isaiahgraham.leanrrr.feature.settings

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ShowChart
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.feature.onboarding.BOARD_INK
import com.isaiahgraham.leanrrr.feature.onboarding.CuttingBoard
import com.isaiahgraham.leanrrr.ui.AppTab
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType

/**
 * The short tour of the tabs that follows first-run onboarding, and that Settings can replay (TabTour.swift). Each step
 * switches to its tab, so the screen behind the card is the one being described and the tab bar shows which tab it is.
 */
enum class TourStep(val title: String, val detail: String, val icon: ImageVector) {
    TODAY("Today", "Log what you eat and see what's left of your day. Scan, Photo and Describe are the quickest ways in.", Icons.Filled.CalendarMonth),
    FIND("Find", "Say what you have left and Leanrrr suggests orders that fit, using each restaurant's own numbers.", Icons.Filled.Search),
    MAP("Map", "The closest restaurant of each chain, with the best order at each for what's left today.", Icons.Filled.Map),
    MEAL("Meal", "Build a meal from any foods, or send an order here from Find, then log it in one go.", Icons.Filled.Restaurant),
    PROGRESS("Progress", "Your weight trend, measurements and how your week, month or three months went.", Icons.AutoMirrored.Filled.ShowChart),
    SETTINGS("Settings", "Targets, reminders, Health Connect and colours live behind the gear at the top right of every tab.", Icons.Filled.Settings);

    /** The tab showing behind the card. Settings is reached from Today's gear. */
    val tab: AppTab get() = when (this) {
        TODAY, SETTINGS -> AppTab.TODAY
        FIND -> AppTab.FIND
        MAP -> AppTab.MAP
        MEAL -> AppTab.MEAL
        PROGRESS -> AppTab.PROGRESS
    }

    val next: TourStep? get() = entries.getOrNull(ordinal + 1)
    val isLast: Boolean get() = next == null

    companion object {
        /** Every tab has a step. */
        fun step(tab: AppTab): TourStep = when (tab) {
            AppTab.TODAY -> TODAY; AppTab.FIND -> FIND; AppTab.MAP -> MAP; AppTab.MEAL -> MEAL; AppTab.PROGRESS -> PROGRESS
        }
    }
}

object TabTour {
    /** Set once the tour has been finished or skipped, so it's offered only once. */
    const val SEEN_KEY = "leanr.tour.seen"
}

/** The card for one step, on the same cutting board as the moment cards and onboarding, above the tab bar. */
@Composable
private fun TabTourCard(step: TourStep, advance: () -> Unit, skip: () -> Unit) {
    val accent = Leanr.colours.accent
    Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp), contentAlignment = Alignment.Center) {
        CuttingBoard(Modifier.widthIn(max = 420.dp).fillMaxWidth()) {
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    TourStep.entries.forEach { other ->
                        Box(Modifier.weight(1f).height(4.dp).clip(CircleShape).background(if (other.ordinal <= step.ordinal) accent else BOARD_INK.copy(alpha = 0.14f)))
                    }
                }
                Row(Modifier.semantics(mergeDescendants = true) {
                    contentDescription = "${step.title}, ${step.ordinal + 1} of ${TourStep.entries.size}. ${step.detail}"
                }, verticalAlignment = Alignment.Top) {
                    Icon(step.icon, null, tint = accent, modifier = Modifier.size(34.dp))
                    Spacer(Modifier.size(14.dp))
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(step.title, style = LeanrType.display(20f), color = BOARD_INK)
                        Text(step.detail, style = LeanrType.subheadline, color = BOARD_INK)
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (!step.isLast) TextButton(onClick = skip, modifier = Modifier.heightIn(min = 44.dp)) { Text("Skip tour", color = BOARD_INK.copy(alpha = 0.7f)) }
                    Spacer(Modifier.weight(1f))
                    Button(onClick = advance, colors = ButtonDefaults.buttonColors(containerColor = accent, contentColor = Color.White)) {
                        Text(if (step.isLast) "Done" else "Next", style = LeanrType.headline)
                    }
                }
            }
        }
    }
}

/** Runs the tour over the tabs: a scrim that keeps taps off the screens, and the card for the current step. */
@Composable
internal fun TabTourOverlay(step: TourStep?, onStep: (TourStep?) -> Unit, finished: () -> Unit) {
    val nav = AppServices.nav
    val haptics = LocalHapticFeedback.current
    fun finish() { finished(); onStep(null); nav.tab = AppTab.TODAY }
    LaunchedEffect(step) {
        if (step == null) return@LaunchedEffect
        nav.tab = step.tab
        haptics.performHapticFeedback(HapticFeedbackType.SegmentTick)
    }
    if (step != null) BackHandler { finish() }
    // The last step stays on the card while it slides away.
    var shownStep by remember { mutableStateOf(step ?: TourStep.TODAY) }
    if (step != null) shownStep = step
    Box(Modifier.fillMaxSize()) {
        AnimatedVisibility(step != null, enter = fadeIn(), exit = fadeOut()) {
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.28f))
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {})
        }
        AnimatedVisibility(step != null, modifier = Modifier.align(Alignment.BottomCenter),
            enter = slideInVertically { it } + fadeIn(), exit = slideOutVertically { it } + fadeOut()) {
            val shown = shownStep
            Box(Modifier.navigationBarsPadding().padding(bottom = 92.dp)) {
                TabTourCard(shown, advance = { shown.next?.let(onStep) ?: finish() }, skip = { finish() })
            }
        }
    }
}
