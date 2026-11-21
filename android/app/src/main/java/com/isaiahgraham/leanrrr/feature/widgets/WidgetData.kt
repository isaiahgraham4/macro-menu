package com.isaiahgraham.leanrrr.feature.widgets

import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.billing.Premium
import com.isaiahgraham.leanrrr.data.AppStore
import com.isaiahgraham.leanrrr.data.LogEntry
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.Prefs
import com.isaiahgraham.leanrrr.data.QuickLog
import com.isaiahgraham.leanrrr.data.dayKey
import com.isaiahgraham.leanrrr.data.nutrientNames
import com.isaiahgraham.leanrrr.feature.today.Water
import com.isaiahgraham.leanrrr.feature.today.addWater
import com.isaiahgraham.leanrrr.ui.theme.AppAccent
import com.isaiahgraham.leanrrr.ui.theme.MacroColours
import com.isaiahgraham.leanrrr.ui.theme.TargetStatus
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlin.math.abs
import kotlin.math.roundToLong

// Ports of Shared/WidgetCalories.swift and MacroMenu/WidgetSync.swift. On iOS the widget extension reads a snapshot file
// the app writes; on Android widgets run in the app's own process, so they read the store directly through this projection.

data class WidgetNutrientTarget(val id: String, val name: String, val unit: String, val target: Double, val minimum: Boolean)

/** One thing the Log again widget offers: your usual meal for a meal time ("usual:lunch"), or a pinned food ("pin:<food ID>"). */
data class WidgetQuickLog(
    val id: String, val name: String, val calories: Double,
    /** For a usual meal, the meal time it's for and logs to. */
    val mealTime: String? = null,
    /** True once it's in today's log, to show a tick. */
    val loggedToday: Boolean = false,
) {
    val isUsual: Boolean get() = id.startsWith("usual:")
}

/** What the widgets show for one moment: today's totals against the active targets, and the extras each widget needs. */
data class WidgetCalories(
    val date: LocalDate,
    /** False when the saved data couldn't be read, so widgets ask you to open Leanrrr. */
    val readable: Boolean,
    val target: Double?,
    val eaten: Double,
    val nutrientTargets: List<WidgetNutrientTarget>,
    val nutrients: Map<String, Double>,
    val partial: Set<String>,
    val trackedDays: Set<String>,
    val premiumUnlocked: Boolean,
    val accentRaw: String,
    val macroChoices: Map<String, String>,
    val steps: Map<String, Double>,
    val stepGoal: Double,
    val activeEnergy: Map<String, Double>,
    val waterToday: Double,
    val waterTarget: Double,
    val quickLogs: List<WidgetQuickLog>,
) {
    val remaining: Double? get() = target?.let { it - eaten }
    val todayKey: String get() = dayKey(date)

    /** Rounded with no decimals, like the iOS widgets. */
    fun whole(value: Double): String = "%,d".format(java.util.Locale.US, value.roundToLong())
    val value: String get() = remaining?.let { whole(abs(it)) } ?: "—"
    val eatenValue: String get() = whole(eaten)
    val targetValue: String get() = target?.let { it.roundToLong().toString() } ?: "—"
    val caption: String get() = if ((remaining ?: 0.0) < 0) "Cal over target" else "Cals left today"
    val progress: Double get() = target?.let { (eaten / it).coerceIn(0.0, 1.0) } ?: 0.0
    val prompt: String get() = if (!readable) "Open Leanrrr to sync" else "Set a calorie target"

    val streak: Int get() = TrackingStreak.count(trackedDays, date)
    val trackedToday: Boolean get() = todayKey in trackedDays

    fun stepCount(day: LocalDate): Double? = steps[dayKey(day)]?.takeIf { it > 0 }
    fun energyBurnt(day: LocalDate): Double? = activeEnergy[dayKey(day)]?.takeIf { it > 0 }
    /** The average over the other days that have any recorded, to put today in context. */
    val energyAverage: Double?
        get() {
            val others = activeEnergy.filter { it.key != todayKey && it.value > 0 }.values
            return if (others.isEmpty()) null else others.sum() / others.size
        }

    /** What the Log again widget shows now: the usual meal for this meal time first, then pinned foods (listed once). */
    fun quickLogsNow(slot: MealTime = MealTime.suggested()): List<WidgetQuickLog> {
        val usual = quickLogs.filter { it.isUsual && it.mealTime == slot.raw }
        return usual + quickLogs.filter { pin -> !pin.isUsual && usual.none { it.name == pin.name } }
    }

    fun accent(dark: Boolean) = AppAccent.resolvedColor(accentRaw, dark)
    fun macroColour(key: String, dark: Boolean) = MacroColours.colour(key, macroChoices, dark)

    companion object {
        fun current(store: AppStore = AppServices.store, now: Instant = Instant.now(), quickLogs: Boolean = true): WidgetCalories {
            val data = store.data
            val today = now.atZone(ZoneId.systemDefault()).toLocalDate()
            val key = dayKey(today)
            // The set in use, not a past day's snapshot, matching Today.
            val goal = data.goalSets.firstOrNull { it.id == data.activeGoal } ?: data.goalSets.firstOrNull()
            val targets = nutrientNames.mapNotNull { n ->
                if (n.key == "cal") return@mapNotNull null
                val t = goal?.values?.get(n.key) ?: return@mapNotNull null
                WidgetNutrientTarget(n.key, n.label, n.unit, t, goal.minimums.contains(n.key))
            }
            val entries = data.logs[key] ?: emptyList()
            val total = Nutrition(entries.flatMap { it.items })
            val keys = targets.map { it.id }.toSet() + setOf("p", "c", "f")
            val partial = if (entries.isEmpty()) emptySet() else keys.filter { k ->
                total.isPartial(k) || (k !in setOf("p", "c", "f") && total.nut[k] == null)
            }.toSet()
            val unlocked = Premium.isUnlocked
            return WidgetCalories(
                date = today, readable = store.loadError == null, target = goal?.values?.get("cal"), eaten = total.cal,
                nutrientTargets = targets, nutrients = keys.associateWith { total.value(it) }, partial = partial,
                trackedDays = data.logs.filter { (_, list) -> list.any { it.items.isNotEmpty() } }.keys,
                premiumUnlocked = unlocked,
                accentRaw = Prefs.string(AppAccent.STORAGE_KEY) ?: AppAccent.standard.raw,
                macroChoices = if (unlocked) mapOf(
                    "p" to (Prefs.string(MacroColours.PROTEIN_KEY) ?: "blue"),
                    "c" to (Prefs.string(MacroColours.CARBS_KEY) ?: "orange"),
                    "f" to (Prefs.string(MacroColours.FAT_KEY) ?: "red"),
                ) else emptyMap(),
                steps = store.widgetSteps, stepGoal = data.stepGoal ?: AppStore.DEFAULT_STEP_GOAL, activeEnergy = store.widgetEnergy,
                waterToday = Water.total(data, key), waterTarget = Water.target(data),
                quickLogs = if (quickLogs) store.quickLogOptions(today) else emptyList(),
            )
        }
    }
}

/** Where a day's total stands against a target: protein is a goal to reach, carbs and fat are limits. Compared as shown, to a tenth. */
fun targetStatus(id: String, value: Double, target: Double?): TargetStatus {
    if (target == null || target <= 0 || !value.isFinite()) return TargetStatus.NONE
    val shown = Math.round(value * 10) / 10.0
    val goal = Math.round(target * 10) / 10.0
    return when (id) {
        "p" -> if (shown >= goal) TargetStatus.REACHED else TargetStatus.NONE
        "c", "f" -> if (shown > goal) TargetStatus.OVER else TargetStatus.NONE
        else -> TargetStatus.NONE
    }
}

/** Counting days in a row with food logged (TrackingStreak in WidgetCalories.swift). */
object TrackingStreak {
    /** One missed day doesn't end a streak, as long as this many logged days sit between missed ones: about one a week. */
    const val LOGGED_DAYS_BETWEEN_MISSES = 6

    /** The logged days in the streak up to `date`. Today is still open to log, so it never counts against the streak. */
    fun count(days: Set<String>, date: LocalDate): Int {
        var cursor = date
        if (dayKey(cursor) !in days) cursor = cursor.minusDays(1)
        var count = 0
        var sinceMiss = LOGGED_DAYS_BETWEEN_MISSES
        while (true) {
            if (dayKey(cursor) in days) {
                count += 1; sinceMiss += 1
            } else {
                if (sinceMiss < LOGGED_DAYS_BETWEEN_MISSES || dayKey(cursor.minusDays(1)) !in days) break
                sinceMiss = 0
            }
            cursor = cursor.minusDays(1)
        }
        return count
    }
}

/** The meal logged most often to `mealTime` in the last 30 days (Assistant.usual). */
fun usualMeal(mealTime: MealTime, logs: Map<String, List<LogEntry>>, now: Instant = Instant.now()): LogEntry? =
    QuickLog.frequent(logs.mapValues { (_, list) -> list.filter { it.mealTime == mealTime } }, now, limit = 1).firstOrNull()

/** What the Log again widget can log: the usual meal for each meal time, then pinned foods. */
fun AppStore.quickLogOptions(today: LocalDate = LocalDate.now()): List<WidgetQuickLog> {
    val now = Instant.now()
    val logged = data.logs[dayKey(today)] ?: emptyList()
    val usual = MealTime.entries.mapNotNull { meal ->
        val entry = usualMeal(meal, data.logs, now) ?: return@mapNotNull null
        WidgetQuickLog("usual:${meal.raw}", entry.name, Nutrition(entry.items).cal, meal.raw,
            loggedToday = logged.any { it.mealTime == meal && it.name == entry.name })
    }
    val pins = pinnedFoods.map { food ->
        WidgetQuickLog("pin:${food.id}", food.name, food.cal, loggedToday = logged.any { e -> e.items.any { it.food.id == food.id } })
    }
    return usual + pins
}

/** The Water widget's buttons: "water:250" adds 250 mL to today. */
fun waterOption(millilitres: Double) = "water:${Math.round(millilitres)}"
private fun waterAmount(option: String): Double? =
    option.removePrefix("water:").takeIf { option.startsWith("water:") }?.toDoubleOrNull()?.takeIf { it > 0 && it <= 2000 }

/**
 * Logs one of the widget's or a shortcut's options: a usual meal to its own meal time, a serving of a pinned food to the meal
 * time it is now, or water. The same thing logged in the last 10 seconds is taken as a double tap. Returns the name logged.
 */
fun AppStore.logAgain(option: String, at: Instant = Instant.now()): String? {
    val date = at.atZone(ZoneId.systemDefault()).toLocalDate()
    fun justLogged(name: String) = (data.logs[dayKey(date)] ?: emptyList()).any { it.name == name && abs(it.time.epochSecond - at.epochSecond) < 10 }
    if (option.startsWith("usual:")) {
        val meal = MealTime.fromRaw(option.removePrefix("usual:")) ?: return null
        val usual = usualMeal(meal, data.logs, at) ?: return null
        if (justLogged(usual.name)) return null
        return if (log(QuickLog.copies(usual.items), usual.name, date, mealTime = meal, time = at)) usual.name else null
    }
    waterAmount(option)?.let { amount -> return if (addWater(amount, date, at)) Water.text(amount) else null }
    if (option.startsWith("pin:")) {
        val food = pinnedFoods.firstOrNull { "pin:${it.id}" == option } ?: return null
        if (justLogged(food.name)) return null
        return if (log(listOf(Portion(food = food)), food.name, date, mealTime = MealTime.suggested(at), time = at)) food.name else null
    }
    return null
}

