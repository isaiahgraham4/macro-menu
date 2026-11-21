package com.isaiahgraham.leanrrr.feature.widgets

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Toast
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import androidx.glance.appwidget.updateAll
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.MainActivity
import com.isaiahgraham.leanrrr.R
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.feature.health.HealthSync
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant
import kotlin.math.abs

/** Wires Health Connect, the widgets and the app shortcuts into the store. The one call in Startup.kt. */
object PlatformHooks {
    fun install() {
        HealthSync.install()
        WidgetSync.install()
    }
}

/**
 * Keeps the widgets up to date (WidgetSync.swift's refreshWidgets). The store calls `widgetsRefreshed` after every save and
 * Health Connect read; quick runs of saves are drawn once, a moment later. Pinned foods also become app shortcuts here.
 */
object WidgetSync {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val requests = Channel<Unit>(Channel.CONFLATED)
    private var lastPins: List<String>? = null

    fun install() {
        val store = AppServices.store
        val previous = store.widgetsRefreshed
        store.widgetsRefreshed = { previous?.invoke(); refresh() }
        scope.launch {
            for (request in requests) {
                delay(400)
                updateNow(AppServices.app)
            }
        }
        refresh()
    }

    fun refresh() {
        requests.trySend(Unit)
        scope.launch(Dispatchers.Main) { AppShortcuts.update(AppServices.app) }
    }

    suspend fun updateNow(context: Context) {
        for (widget in allWidgets) runCatching { widget.updateAll(context) }
    }

    internal fun pinsChanged(ids: List<String>): Boolean {
        if (ids == lastPins) return false
        lastPins = ids
        return true
    }
}

/** App shortcuts for pinned foods (the dynamic part of LeanrIntents); the static ones are in res/xml/shortcuts_main.xml. */
object AppShortcuts {
    const val ACTION_LOG = "com.isaiahgraham.leanrrr.LOG_PINNED"
    const val ACTION_USUAL = "com.isaiahgraham.leanrrr.LOG_USUAL"
    const val EXTRA_OPTION = "option"
    /** The launcher shows four or five shortcuts in all; three are static. */
    private const val PINNED_SHORTCUTS = 4

    fun update(context: Context) {
        val store = AppServices.store
        // Only when the pins change: working out their current figures means a search through every food.
        if (!WidgetSync.pinsChanged((store.data.pinned ?: emptyList()).map { it.id + "|" + it.name } + "loaded:${store.foodsLoaded}")) return
        val pins = store.pinnedFoods
        val max = runCatching { ShortcutManagerCompat.getMaxShortcutCountPerActivity(context) }.getOrDefault(5)
        val shortcuts = pins.take(minOf(PINNED_SHORTCUTS, maxOf(0, max - 3))).mapIndexed { i, food ->
            ShortcutInfoCompat.Builder(context, "pin:${food.id}")
                .setShortLabel(food.name.take(24))
                .setLongLabel("Log ${food.name}".take(45))
                .setIcon(IconCompat.createWithResource(context, R.drawable.shortcuts_ic_pin))
                .setRank(i)
                .setIntent(Intent(context, ShortcutActivity::class.java).setAction(ACTION_LOG).putExtra(EXTRA_OPTION, "pin:${food.id}"))
                .build()
        }
        runCatching { ShortcutManagerCompat.setDynamicShortcuts(context, shortcuts) }
    }
}

/**
 * Runs a shortcut without opening the app: logs a pinned food or your usual meal for this time of day, says so in a toast,
 * and closes. Falls back to Today when there's nothing to log.
 */
class ShortcutActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AppServices.start(application)
        val store = AppServices.store
        val option = when (intent?.action) {
            AppShortcuts.ACTION_LOG -> intent.getStringExtra(AppShortcuts.EXTRA_OPTION)
            AppShortcuts.ACTION_USUAL -> "usual:${MealTime.suggested().raw}"
            else -> null
        }
        val message: String
        if (option == null) {
            message = "This shortcut is no longer available"
        } else if (option.startsWith("usual:")) {
            val meal = MealTime.fromRaw(option.removePrefix("usual:")) ?: MealTime.suggested()
            val usual = usualMeal(meal, store.data.logs)
            message = when {
                usual == null -> "You haven’t logged ${meal.title.lowercase()} in the last month, so there’s no usual ${meal.title.lowercase()} yet."
                store.logAgain(option) == null -> "Leanrrr couldn’t save that. Open the app to check your data."
                else -> {
                    val total = Nutrition(usual.items)
                    var text = "Logged ${usual.name} to ${meal.title.lowercase()}: ${Math.round(total.cal).toDouble().number} Cal, ${total.p.number} g protein."
                    remainingCalories()?.let { left ->
                        text += if (left >= 0) " ${Math.round(left).toDouble().number} Cal left today." else " That’s ${Math.round(abs(left)).toDouble().number} Cal over today’s target."
                    }
                    text
                }
            }
            if (usual == null) startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("leanr://today"), this, MainActivity::class.java))
        } else {
            val name = store.logAgain(option, Instant.now())
            message = if (name != null) "Logged $name to ${MealTime.suggested().title.lowercase()}" else
                if (store.pinnedFoods.none { "pin:${it.id}" == option }) "This shortcut is no longer available" else "Already logged"
        }
        Toast.makeText(applicationContext, message, Toast.LENGTH_LONG).show()
        finish()
    }

    private fun remainingCalories(): Double? {
        val store = AppServices.store
        val key = com.isaiahgraham.leanrrr.data.dayKey(Instant.now())
        val eaten = Nutrition((store.data.logs[key] ?: emptyList()).flatMap { it.items })
        val target = store.data.dayGoals[key] ?: store.goals
        return target.values["cal"]?.let { it - eaten.cal }
    }
}
