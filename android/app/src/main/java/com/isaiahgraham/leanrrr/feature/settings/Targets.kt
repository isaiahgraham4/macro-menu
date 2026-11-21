package com.isaiahgraham.leanrrr.feature.settings

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.Goals
import com.isaiahgraham.leanrrr.data.LogEntry
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Prefs
import com.isaiahgraham.leanrrr.data.StepLimits
import com.isaiahgraham.leanrrr.data.WaterLimits
import com.isaiahgraham.leanrrr.data.WeightEntry
import com.isaiahgraham.leanrrr.data.dayKey
import com.isaiahgraham.leanrrr.data.newId
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.data.nutrientNames
import com.isaiahgraham.leanrrr.data.tenth
import com.isaiahgraham.leanrrr.ui.components.LeanrRow
import com.isaiahgraham.leanrrr.ui.components.NumberField
import com.isaiahgraham.leanrrr.ui.components.OptionalNumberField
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import kotlin.math.abs
import kotlin.math.roundToLong

/**
 * The smoothed weight trend and measured maintenance from WeightTrend in Weight.swift, the two parts the target calculator and
 * the weekly review notification need. Each day moves the trend a fifth of the way to the scale (less recent water).
 */
internal object TrendMath {
    data class Point(val day: LocalDate, val kg: Double, val trend: Double, val water: Double) { val adjusted: Double get() = kg - water }
    const val CALORIES_PER_KG = 7700.0
    private const val DAILY_WEIGHT = 0.2

    fun points(entries: List<WeightEntry>, zone: ZoneId = ZoneId.systemDefault()): List<Point> {
        val byDay = entries.filter { it.isValid }.groupBy { it.date.atZone(zone).toLocalDate() }
        val result = mutableListOf<Point>()
        for (day in byDay.keys.sorted()) {
            val entry = byDay.getValue(day).maxBy { it.date }
            val water = entry.waterKG ?: 0.0; val adjusted = entry.adjustedKG
            val last = result.lastOrNull()
            if (last == null) { result += Point(day, entry.kg, adjusted, water); continue }
            val gap = maxOf(1L, ChronoUnit.DAYS.between(last.day, day))
            var trend = last.trend
            for (step in 1..gap) {
                val scale = last.adjusted + (adjusted - last.adjusted) * step / gap
                trend += DAILY_WEIGHT * (scale - trend)
            }
            result += Point(day, entry.kg, trend, water)
        }
        return result
    }

    data class Maintenance(val calories: Double, val loggedDays: Int, val weighInDays: Int)

    /** Average logged intake less the energy that went into weight change. Needs 10 logged days and two weeks of weigh-ins in the last 28 days. */
    fun maintenance(logs: Map<String, List<LogEntry>>, points: List<Point>, days: Long = 28, today: LocalDate = LocalDate.now()): Maintenance? {
        val start = today.minusDays(days)
        val intakes = (0 until days).mapNotNull { i -> logs[dayKey(start.plusDays(i))]?.takeIf { it.isNotEmpty() }?.let { Nutrition(it.flatMap { e -> e.items }).cal } }
        val window = points.filter { !it.day.isBefore(start) && it.day.isBefore(today) }
        val first = window.firstOrNull() ?: return null; val last = window.last()
        val span = ChronoUnit.DAYS.between(first.day, last.day)
        if (intakes.size < 10 || span < 14) return null
        val calories = intakes.average() - (last.trend - first.trend) * CALORIES_PER_KG / span
        if (calories !in 1000.0..6000.0) return null
        return Maintenance(calories, intakes.size, window.size)
    }
}

private fun Double.rounded(): Double = roundToLong().toDouble()

/** Target sets: switch between them, edit, add or delete (TargetsView in TodayView.swift). */
@Composable
internal fun TargetsScreen(onBack: () -> Unit, edit: (Goals) -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    SettingsPage("Your targets", onBack) {
        item {
            SettingsSection("Target sets") {
                store.data.goalSets.forEach { goal ->
                    val active = goal.id == store.goals.id
                    LeanrRow(goal.name,
                        leading = { Icon(if (active) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked, null, tint = c.accent) },
                        trailing = {
                            if (store.data.goalSets.size > 1) TextButton(onClick = { store.deleteGoals(goal) }) { Text("Delete", color = c.over) }
                            TextButton(onClick = { edit(goal) }) { Text("Edit", color = c.accent) }
                        },
                        onClick = { store.useGoals(goal) })
                }
                ButtonRow("Add target set", divider = false) { edit(store.goals.copy(id = newId(), name = "New targets")) }
            }
        }
        item {
            SettingsSection {
                NoteRow("Switch between training, rest or other day types. Past days keep the target snapshot captured when you logged them. Blank fields are not tracked.")
            }
        }
    }
}

/** Editing one target set: its name, each nutrient (at most or at least), and the typical meal (GoalEditor). */
@Composable
internal fun GoalEditorScreen(initial: Goals, onDone: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    var goal by remember(initial.id) { mutableStateOf(initial) }
    // The number fields keep their own text; bumped when the calculator fills them, so they show the new figures.
    var revision by remember { mutableStateOf(0) }
    var calculating by remember { mutableStateOf(false) }
    if (calculating) FullScreenSheet(onDismiss = { calculating = false }) {
        TargetCalculatorScreen(onCancel = { calculating = false }) { values -> goal = goal.copy(values = goal.values + values); revision += 1; calculating = false }
    }
    SettingsPage("Edit targets", onDone, actions = {
        TextButton(onClick = { if (store.saveGoals(goal)) onDone() }, enabled = goal.isValid) {
            Text("Save", style = LeanrType.headline, color = if (goal.isValid) c.accent else c.tertiaryText)
        }
    }) {
        item {
            SettingsSection {
                Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 13.dp)) {
                    if (goal.name.isEmpty()) Text("Target set name", style = LeanrType.body, color = c.tertiaryText)
                    BasicTextField(goal.name, { goal = goal.copy(name = it) }, textStyle = LeanrType.body.copy(color = c.text), singleLine = true,
                        cursorBrush = SolidColor(c.accent), modifier = Modifier.fillMaxWidth())
                }
            }
        }
        item(key = "daily-$revision") {
            SettingsSection("Daily targets") {
                nutrientNames.forEachIndexed { i, n ->
                    val value = goal.values[n.key]
                    OptionalNumberField("${n.label} (${n.unit})", value, { v ->
                        goal = goal.copy(values = if (v == null || v <= 0) goal.values - n.key else goal.values + (n.key to v))
                    }, divider = value == null && i < nutrientNames.lastIndex)
                    if (value != null) {
                        SegmentedRow(listOf(false to "At most", true to "At least"), n.key in goal.minimums, { minimum ->
                            goal = goal.copy(minimums = if (minimum) goal.minimums + n.key else goal.minimums - n.key)
                        })
                        if (i < nutrientNames.lastIndex) androidx.compose.material3.HorizontalDivider(Modifier.padding(start = 16.dp), color = c.separator, thickness = 0.5.dp)
                    }
                }
            }
        }
        item {
            SettingsSection("Typical meal") {
                NumberField("Calories", goal.mealCal, { goal = goal.copy(mealCal = it) })
                NumberField("Protein (g)", goal.mealProtein, { goal = goal.copy(mealProtein = it) }, divider = false)
            }
        }
        item {
            SettingsSection {
                ButtonRow("Estimate targets from body measurements", divider = false) { calculating = true }
            }
        }
    }
}

/** A remembered calculator setting (the iOS @AppStorage "calc.*" keys). */
@Composable
private fun rememberDoublePref(key: String, default: Double) = remember(key) { mutableDoubleStateOf(Prefs.double(key) ?: default) }

/**
 * The Mifflin–St Jeor estimate of maintenance calories and daily macros from age, height, weight, sex and activity, or the
 * maintenance measured from your log and weight trend when there's enough of both (TargetCalculator).
 */
@Composable
internal fun TargetCalculatorScreen(onCancel: () -> Unit, apply: (Map<String, Double>) -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    var female by remember { mutableStateOf(Prefs.bool("calc.female")) }
    var age by rememberDoublePref("calc.age", 30.0)
    var height by rememberDoublePref("calc.height", 175.0)
    var weight by rememberDoublePref("calc.weight", 75.0)
    var activity by rememberDoublePref("calc.activity", 1.375)
    var adjustment by rememberDoublePref("calc.adjustment", 0.0)
    var proteinPerKG by rememberDoublePref("calc.proteinPerKG", 1.6)
    var fatPercent by rememberDoublePref("calc.fatPercent", 25.0)
    var useMeasured by remember { mutableStateOf(true) }
    // Remembered, so updating targets later only needs what's changed.
    LaunchedEffect(female, age, height, weight, activity, adjustment, proteinPerKG, fatPercent) {
        Prefs.set("calc.female", female); Prefs.set("calc.age", age); Prefs.set("calc.height", height); Prefs.set("calc.weight", weight)
        Prefs.set("calc.activity", activity); Prefs.set("calc.adjustment", adjustment); Prefs.set("calc.proteinPerKG", proteinPerKG); Prefs.set("calc.fatPercent", fatPercent)
    }
    val points = remember(store.data.weights) { TrendMath.points(store.data.weightLog) }
    val measured = remember(store.data.logs, points) { TrendMath.maintenance(store.data.logs, points) }
    // The last week of active energy from Health Connect, before today (today isn't finished).
    val activeEnergy = store.widgetEnergy.filterKeys { it != dayKey(LocalDate.now()) }.values.takeIf { it.isNotEmpty() }?.average()
    var fieldRevision by remember { mutableStateOf(0) }
    LaunchedEffect(Unit) { points.lastOrNull()?.let { weight = it.trend.tenth; fieldRevision += 1 } }

    val activityLevels = listOf(1.2, 1.375, 1.55, 1.725, 1.9)
    val bmr = 10 * weight + 6.25 * height - 5 * age + if (female) -161 else 5
    val equation = bmr * activity
    val usingMeasured = useMeasured && measured != null
    val maintenance = if (usingMeasured) measured.calories else equation
    val calories = maintenance + adjustment
    val protein = weight * proteinPerKG
    val fat = calories * fatPercent / 100 / 9
    val carbs = maxOf(0.0, (calories - protein * 4 - fat * 9) / 4)
    val valid = age in 18.0..100.0 && height in 120.0..230.0 && weight in 35.0..250.0 && proteinPerKG in 0.8..3.3 && fatPercent in 15.0..45.0 &&
        calories > 0 && protein * 4 + fat * 9 <= calories

    SettingsPage("Estimate targets", onCancel, actions = { TextButton(onClick = onCancel) { Text("Cancel", color = c.accent) } }) {
        if (points.isNotEmpty() || measured != null || activeEnergy != null) item(key = "data-$fieldRevision") {
            SettingsSection("From your data", footerText = if (usingMeasured) "Measured maintenance replaces the activity-based estimate below. Your goal is still added or subtracted." else null) {
                points.lastOrNull()?.let { last ->
                    ValueRow("Trend weight", "${last.trend.number} kg")
                    if (abs(last.trend - weight) >= 0.1) ButtonRow("Use my trend weight") { weight = last.trend.tenth; fieldRevision += 1 }
                }
                measured?.let { m ->
                    SwitchRow("Use my measured maintenance", useMeasured, { useMeasured = it },
                        subtitle = "${m.calories.rounded().number} Cal/day from ${m.loggedDays} logged days")
                }
                activeEnergy?.let { active ->
                    ValueRow("Active energy (Health Connect)", "${active.rounded().number} Cal/day")
                    if (!usingMeasured) ButtonRow("Set activity from Health Connect", divider = false) {
                        // Resting burn plus measured activity, plus about 10% for digesting food.
                        val factor = 1.1 * (bmr + active) / maxOf(bmr, 1.0)
                        activity = activityLevels.minBy { abs(it - factor) }
                    }
                }
            }
        }
        item(key = "body-$fieldRevision") {
            SettingsSection("Body measurements") {
                MenuPickerRow("Sex used in equation", listOf(false, true), female, { if (it) "Female" else "Male" }, { female = it })
                NumberField("Age (18–100)", age, { age = it })
                NumberField("Height (cm)", height, { height = it })
                NumberField("Weight (kg)", weight, { weight = it })
                val activities = listOf(1.2 to "Mostly sitting", 1.375 to "Light · 1–3 days/week", 1.55 to "Moderate · 3–5 days/week",
                    1.725 to "Hard · 6–7 days/week", 1.9 to "Very hard / physical job")
                MenuPickerRow("Activity", activities.map { it.first }, activity, { a -> activities.firstOrNull { it.first == a }?.second ?: a.number }, { activity = it })
                val goals = listOf(0.0 to "Maintain", -275.0 to "Lose ~0.25 kg/week", -550.0 to "Lose ~0.5 kg/week", 275.0 to "Gain ~0.25 kg/week")
                MenuPickerRow("Goal", goals.map { it.first }, adjustment, { a -> goals.firstOrNull { it.first == a }?.second ?: a.number }, { adjustment = it })
                NumberField("Protein (g/kg)", proteinPerKG, { proteinPerKG = it })
                NumberField("Fat share (%)", fatPercent, { fatPercent = it }, divider = false)
            }
        }
        item {
            SettingsSection("Estimate") {
                if (valid) {
                    ValueRow(if (usingMeasured) "Measured maintenance" else "Estimated maintenance", maintenance.rounded().number + " Cals/day")
                    ValueRow("Daily calorie target", calories.number + " Cals")
                    ValueRow("Protein", protein.number + " g")
                    ValueRow("Carbs", carbs.number + " g")
                    ValueRow("Fat", fat.number + " g")
                    ButtonRow("Use these targets") {
                        apply(mapOf("cal" to calories.rounded(), "p" to protein.rounded(), "c" to carbs.rounded(), "f" to fat.rounded()))
                    }
                } else NoteRow("Enter valid measurements and macro settings.", divider = true, primary = true)
                Text("Mifflin–St Jeor estimate for adults. Actual needs vary; review against your own progress. Talk to a doctor or Accredited Practising Dietitian before making big changes to how you eat, especially if you're pregnant, have a medical condition or have had an eating disorder.",
                    style = LeanrType.caption, color = c.secondaryText, modifier = Modifier.padding(16.dp))
            }
        }
    }
}

/** The daily water target and the size of a glass (WaterSettings). */
@Composable
internal fun WaterSettingsScreen(onBack: () -> Unit) {
    val store = AppServices.store
    var target by remember { mutableDoubleStateOf(store.data.waterTarget ?: 2000.0) }
    var glass by remember { mutableDoubleStateOf(store.data.waterGlass ?: 250.0) }
    val valid = target in WaterLimits.TARGET_RANGE && glass in WaterLimits.GLASS_RANGE
    val changed = target != (store.data.waterTarget ?: 2000.0) || glass != (store.data.waterGlass ?: 250.0)
    SettingsPage("Water", onBack) {
        item {
            SettingsSection(footerText = "The plus on Today adds one glass. The chips under the bar add a bottle, a litre or the last other amount you added, and Other picks anything up to 5 L. If Health Connect is connected, each day's total is saved to Health Connect as water.") {
                NumberField("Daily target (mL)", target, { target = it })
                NumberField("One glass (mL)", glass, { glass = it }, divider = changed)
                if (changed) ButtonRow("Save", divider = false, enabled = valid) {
                    if (store.change { it.copy(waterTarget = target.rounded(), waterGlass = glass.rounded()) }) store.notice = "Water settings saved"
                }
            }
        }
        if (!valid) item { SettingsSection { NoteRow("Use a target from 250 to 10,000 mL and a glass from 50 to 2,000 mL.") } }
    }
}

/** The daily step goal (StepsSettings). Choosing a step source lives with Health Connect. */
@Composable
internal fun StepsSettingsScreen(onBack: () -> Unit) {
    val store = AppServices.store
    val saved = store.data.stepGoal ?: com.isaiahgraham.leanrrr.data.AppStore.DEFAULT_STEP_GOAL
    var goal by remember { mutableDoubleStateOf(saved) }
    val valid = goal in StepLimits.GOAL_RANGE
    SettingsPage("Steps", onBack) {
        item {
            SettingsSection(footerText = "Steps come from Health Connect. Leanrrr only reads them and doesn't copy them to your backup.") {
                NumberField("Daily goal (steps)", goal, { goal = it }, divider = goal != saved)
                if (goal != saved) ButtonRow("Save", divider = false, enabled = valid) {
                    if (store.change { it.copy(stepGoal = goal.rounded()) }) store.notice = "Step goal saved"
                }
            }
        }
        if (!valid) item { SettingsSection { NoteRow("Use a goal from 1,000 to 100,000 steps.") } }
    }
}

