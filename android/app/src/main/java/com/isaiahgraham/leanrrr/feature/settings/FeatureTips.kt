package com.isaiahgraham.leanrrr.feature.settings

import android.appwidget.AppWidgetManager
import android.content.Context
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Chat
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.CameraAlt
import androidx.compose.material.icons.outlined.EditCalendar
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material.icons.outlined.Straighten
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material.icons.outlined.WaterDrop
import androidx.compose.material.icons.outlined.Widgets
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.BuildConfig
import com.isaiahgraham.leanrrr.billing.Premium
import com.isaiahgraham.leanrrr.data.AppStore
import com.isaiahgraham.leanrrr.data.LeanrJson
import com.isaiahgraham.leanrrr.data.Prefs
import com.isaiahgraham.leanrrr.feature.health.HealthSync
import com.isaiahgraham.leanrrr.ui.AppTab
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/**
 * A feature Leanrrr points out once, on Today, to someone who hasn't tried it (FeatureTips.swift). One tip at a time, spaced
 * out, never repeated after it's been dealt with, and never for something already in use. In the order they're offered.
 */
enum class FeatureTip(val raw: String, val title: String, val detail: String, val icon: ImageVector, val action: Pair<String, Action>?, val minLoggedDays: Int = 0) {
    DESCRIBE("describe", "Say what you ate", "Type or say a meal in your own words and Leanrrr works out the numbers.", Icons.AutoMirrored.Outlined.Chat, "Try it" to Action.DESCRIBE),
    SCAN("scan", "Scan a barcode", "Scan a packaged food's barcode to log it in a tap.", Icons.Outlined.QrCodeScanner, "Scan one" to Action.SCAN),
    WATER("water", "Track your water", "Tap the plus on the Water row each time you have a glass.", Icons.Outlined.WaterDrop, null),
    HEALTH("health", "Connect Health Connect", "See your steps and calories burnt next to what you eat.", Icons.Outlined.FavoriteBorder, "Open Settings" to Action.SETTINGS),
    REMINDERS("reminders", "Get a nudge to log", "Meal and water reminders that skip anything you've already logged.", Icons.Outlined.NotificationsActive, "Choose reminders" to Action.REMINDERS),
    PLAN("plan", "Plan your meals ahead", "Plan tomorrow's meals now and tick them off with one tap.", Icons.Outlined.EditCalendar, "Plan ahead" to Action.PLAN, 3),
    PHOTO("photo", "Log a meal from a photo", "Take a photo of your plate and Leanrrr suggests the foods in it.", Icons.Outlined.CameraAlt, "Try it" to Action.PHOTO),
    ASK_LEANR("askLeanr", "Ask Leanrrr", "Ask for something like \"high protein, no dairy\" and get matching meals.", Icons.Outlined.AutoAwesome, "Open Find" to Action.FIND),
    WIDGETS("widgets", "Add a widget", "Calories left, water and steps on your Home screen.", Icons.Outlined.Widgets, null),
    CHECK_IN("checkIn", "Try the weekly check-in", "Once a week, get a suggestion on whether to adjust your target.", Icons.Outlined.Sync, "Open Progress" to Action.PROGRESS, 7),
    BODY("body", "Track measurements and photos", "Log measurements and progress photos privately.", Icons.Outlined.Straighten, "Open Progress" to Action.PROGRESS, 5);

    /** What the tip's button does, handled where the tip is shown (see [FeatureTips.perform] for the ones that aren't Today's own). */
    enum class Action { DESCRIBE, SCAN, PHOTO, PLAN, SETTINGS, REMINDERS, FIND, PROGRESS }

    companion object { fun fromRaw(raw: String) = entries.firstOrNull { it.raw == raw } }
}

/** What has been shown, and what is finished with. Kept on this phone. Dates are epoch seconds. */
@Serializable
data class FeatureTipState(
    /** When Leanrrr first ran with tips, and whether it was already in use then. */
    val firstSeen: Long? = null,
    val existingUser: Boolean = false,
    val shownAt: Map<String, Long> = emptyMap(),
    /** Dismissed, acted on, used, or timed out. */
    val finished: Set<String> = emptySet(),
    val lastFinished: Long? = null,
)

object FeatureTips {
    const val ENABLED_KEY = "tips.enabled"
    const val STATE_KEY = "tips.state"
    const val USED_KEY = "tips.used"
    /** A tip stays up this long if it's ignored, then is retired for good. */
    const val HOLD_DAYS = 3
    /** Quiet time after one tip is dealt with before the next appears. */
    const val GAP_DAYS = 2
    /** A new person gets a day to find their feet before the first tip. */
    const val NEW_USER_DELAY_DAYS = 1
    /** Intent extra (debug builds) that shows the first tip every time and keeps nothing, like `-demoTips`. */
    const val DEMO_EXTRA = "demoTips"
    var demo = false

    data class Decision(val show: FeatureTip? = null, val begins: Boolean = false, val finishing: List<FeatureTip> = emptyList())

    private fun days(since: Long, now: Long, zone: ZoneId = ZoneId.systemDefault()): Long =
        ChronoUnit.DAYS.between(Instant.ofEpochSecond(since).atZone(zone).toLocalDate(), Instant.ofEpochSecond(now).atZone(zone).toLocalDate())

    /** Which tip to show. Pure, so the pacing can be checked. */
    fun decide(available: Set<FeatureTip>, used: Set<FeatureTip>, loggedDays: Int, state: FeatureTipState, now: Long): Decision {
        val firstSeen = state.firstSeen ?: return Decision()
        val finishing = mutableListOf<FeatureTip>()
        val finished = state.finished.toMutableSet()
        // Tips already up: finished once used, or after being ignored for the hold time.
        for (tip in FeatureTip.entries) {
            val shown = state.shownAt[tip.raw] ?: continue
            if (tip.raw in finished) continue
            if (tip in used || days(shown, now) >= HOLD_DAYS) { finishing += tip; finished += tip.raw }
        }
        FeatureTip.entries.firstOrNull { state.shownAt[it.raw] != null && it.raw !in finished && it in available }?.let {
            return Decision(show = it, finishing = finishing)
        }
        // Nothing up. Wait out the quiet time, and a new person's first day.
        val lastEnd = if (finishing.isEmpty()) state.lastFinished else now
        if (lastEnd != null && days(lastEnd, now) < GAP_DAYS) return Decision(finishing = finishing)
        if (!state.existingUser && days(firstSeen, now) < NEW_USER_DELAY_DAYS) return Decision(finishing = finishing)
        val next = FeatureTip.entries.firstOrNull {
            it in available && it !in used && it.raw !in finished && state.shownAt[it.raw] == null && it.minLoggedDays <= loggedDays
        }
        return Decision(show = next, begins = next != null, finishing = finishing)
    }

    val enabled: Boolean get() = Prefs.bool(ENABLED_KEY, true)

    fun load(): FeatureTipState = Prefs.string(STATE_KEY)?.let { runCatching { LeanrJson.decodeFromString<FeatureTipState>(it) }.getOrNull() } ?: FeatureTipState()
    fun save(state: FeatureTipState) = Prefs.set(STATE_KEY, LeanrJson.encodeToString(FeatureTipState.serializer(), state))

    /** Notes the first run with tips. Someone who had already finished onboarding is an existing user, who sees tips straight away. */
    fun noteLaunch(onboardingCompleted: Boolean, now: Long = Instant.now().epochSecond) {
        val state = load()
        if (state.firstSeen != null) return
        save(state.copy(firstSeen = now, existingUser = onboardingCompleted))
    }

    /** Features used in ways Leanrrr can't see from the data, marked when the person opens them. */
    fun marked(): Set<FeatureTip> = (Prefs.string(USED_KEY) ?: "").split(",").mapNotNull { FeatureTip.fromRaw(it) }.toSet()

    fun markUsed(tip: FeatureTip) {
        val current = (Prefs.string(USED_KEY) ?: "").split(",").filter { it.isNotEmpty() }.toMutableSet()
        if (current.add(tip.raw)) Prefs.set(USED_KEY, current.sorted().joinToString(","))
    }

    fun apply(decision: Decision, state: FeatureTipState, now: Long): FeatureTipState {
        var updated = state
        for (tip in decision.finishing) updated = updated.copy(finished = updated.finished + tip.raw, lastFinished = now)
        if (decision.begins && decision.show != null) updated = updated.copy(shownAt = updated.shownAt + (decision.show.raw to now))
        return updated
    }

    fun finish(tip: FeatureTip, state: FeatureTipState, now: Long): FeatureTipState =
        state.copy(finished = state.finished + tip.raw, lastFinished = now, shownAt = if (state.shownAt[tip.raw] == null) state.shownAt + (tip.raw to now) else state.shownAt)

    /** Whether any of Leanrrr's widgets is on the Home screen. */
    private fun widgetsPlaced(context: Context): Boolean = runCatching {
        val manager = AppWidgetManager.getInstance(context)
        manager.getInstalledProvidersForPackage(context.packageName, null).any { manager.getAppWidgetIds(it.provider).isNotEmpty() }
    }.getOrDefault(false)

    /** Works out which tip to show now for what this person has and hasn't used, and records it. Call from Today. */
    fun current(store: AppStore = AppServices.store, now: Long = Instant.now().epochSecond): FeatureTip? {
        if (!enabled) return null
        val data = store.data
        var used = marked().toMutableSet()
        if (data.water?.isNotEmpty() == true) used += FeatureTip.WATER
        if (HealthSync.enabled) used += FeatureTip.HEALTH
        if ((data.plans ?: emptyMap()).values.any { it.isNotEmpty() }) used += FeatureTip.PLAN
        if (MealReminders.anyOn) used += FeatureTip.REMINDERS
        if (data.measurementLog.isNotEmpty()) used += FeatureTip.BODY
        if (!data.checkIns.isNullOrEmpty()) used += FeatureTip.CHECK_IN
        if (widgetsPlaced(AppServices.app)) used += FeatureTip.WIDGETS
        val available = FeatureTip.entries.toMutableSet()
        if (!HealthSync.available) available -= FeatureTip.HEALTH
        if (!Premium.isUnlocked) { available -= FeatureTip.REMINDERS; available -= FeatureTip.PLAN }
        var state = load()
        val demo = BuildConfig.DEBUG && demo
        if (demo) { state = FeatureTipState(firstSeen = now - 5 * 24 * 3600, existingUser = true); used = mutableSetOf() }
        val loggedDays = data.logs.values.count { it.isNotEmpty() }
        val decision = decide(available, used, loggedDays, state, now)
        if (!demo && (decision.begins || decision.finishing.isNotEmpty())) save(apply(decision, state, now))
        return decision.show
    }

    /** The person dismissed the tip or acted on it. */
    fun finish(tip: FeatureTip, now: Long = Instant.now().epochSecond) {
        if (BuildConfig.DEBUG && demo) return
        save(finish(tip, load(), now))
    }

    /**
     * Does the actions that aren't Today's own: Settings, reminders, Find, Progress and the barcode scanner. Returns false for
     * Describe, Photo and Plan, which Today opens itself.
     */
    fun perform(action: FeatureTip.Action): Boolean {
        val nav = AppServices.nav
        when (action) {
            FeatureTip.Action.SETTINGS -> nav.settingsOpen = true
            FeatureTip.Action.REMINDERS -> nav.remindersRequested = true
            FeatureTip.Action.FIND -> nav.tab = AppTab.FIND
            FeatureTip.Action.PROGRESS -> nav.tab = AppTab.PROGRESS
            FeatureTip.Action.SCAN -> { nav.tab = AppTab.TODAY; nav.scanRequested = true }
            else -> return false
        }
        return true
    }
}

/** The tip card at the top of Today. Closing it, or doing what it suggests, finishes that tip for good (FeatureTipCard). */
@Composable
fun FeatureTipCard(tip: FeatureTip, act: (FeatureTip.Action) -> Unit, dismiss: () -> Unit, modifier: Modifier = Modifier) {
    val c = Leanr.colours
    Row(modifier.fillMaxWidth().padding(start = 16.dp, top = 6.dp, bottom = 6.dp), verticalAlignment = Alignment.Top) {
        Icon(tip.icon, null, tint = c.accent, modifier = Modifier.padding(top = 8.dp).size(26.dp))
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f).clickable { tip.action?.let { act(it.second) } ?: dismiss() }.padding(vertical = 6.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(tip.title, style = LeanrType.headline, color = c.text)
            Text(tip.detail, style = LeanrType.subheadline, color = c.secondaryText)
            tip.action?.let { Text(it.first, style = LeanrType.subheadline.copy(fontWeight = FontWeight.SemiBold), color = c.accent, modifier = Modifier.padding(top = 4.dp)) }
        }
        IconButton(onClick = dismiss) { Icon(Icons.Filled.Close, "Dismiss tip", tint = c.secondaryText, modifier = Modifier.size(18.dp)) }
    }
}

