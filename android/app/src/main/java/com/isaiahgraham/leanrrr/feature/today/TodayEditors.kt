package com.isaiahgraham.leanrrr.feature.today

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.outlined.Restaurant
import androidx.compose.material.icons.outlined.RemoveCircleOutline
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.Goals
import com.isaiahgraham.leanrrr.data.LogEntry
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.Prefs
import com.isaiahgraham.leanrrr.data.QuickLog
import com.isaiahgraham.leanrrr.data.combined
import com.isaiahgraham.leanrrr.data.dayKey
import com.isaiahgraham.leanrrr.data.mealLines
import com.isaiahgraham.leanrrr.data.newId
import com.isaiahgraham.leanrrr.data.nutrientNames
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.data.parseDayKey
import com.isaiahgraham.leanrrr.data.rememberBoolPref
import com.isaiahgraham.leanrrr.data.tenth
import com.isaiahgraham.leanrrr.feature.meal.ContentFilter
import com.isaiahgraham.leanrrr.feature.meal.MealSharePreview
import com.isaiahgraham.leanrrr.feature.meal.MealShareRequest
import com.isaiahgraham.leanrrr.feature.meal.OffensiveTextNote
import com.isaiahgraham.leanrrr.feature.meal.RecipeEditorScreen
import com.isaiahgraham.leanrrr.feature.progress.WeightTrend
import com.isaiahgraham.leanrrr.ui.components.LabeledValue
import com.isaiahgraham.leanrrr.ui.components.LeanrRow
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.components.NumberField
import com.isaiahgraham.leanrrr.ui.components.NutritionView
import com.isaiahgraham.leanrrr.ui.components.OptionalNumberField
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import kotlin.math.abs
import kotlin.math.max

// The screens in TodayView.swift besides Today itself: one meal time's totals, the logged-meal editor, and the targets.

/** This recipe with new ingredients, its figures worked out again from them (Food.withIngredients). */
internal fun Food.withIngredients(ingredients: List<Portion>): Food {
    val fresh = Nutrition(ingredients).food(name, max(recipeYield ?: 1.0, 0.001), ingredients)
    return copy(kj = fresh.kj, cal = fresh.cal, p = fresh.p, c = fresh.c, f = fresh.f, nut = fresh.nut, price = fresh.price, pf = fresh.pf, ingredients = ingredients)
}

/** A new recipe made of these foods, one serving, with any recipe among them broken into its ingredients. */
internal fun recipeDraftOf(name: String, items: List<Portion>): Food =
    Food(name = name, kj = 0.0, cal = 0.0, p = 0.0, ingredients = QuickLog.copies(mealLines(items)), recipeYield = 1.0)

/** Picks a day up to today (DatePicker with `in: ...Date()`). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun DayPickerDialog(date: LocalDate, onPick: (LocalDate) -> Unit, onDismiss: () -> Unit) {
    val todayMillis = LocalDate.now().atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
    val state = rememberDatePickerState(
        initialSelectedDateMillis = date.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
        selectableDates = object : SelectableDates {
            override fun isSelectableDate(utcTimeMillis: Long) = utcTimeMillis <= todayMillis
            override fun isSelectableYear(year: Int) = year <= LocalDate.now().year
        },
    )
    DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = {
                state.selectedDateMillis?.let { onPick(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()) }
                onDismiss()
            }) { Text("Done", color = Leanr.colours.accent) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    ) { DatePicker(state) }
}

/** One meal time on one day: its totals and the food logged to it (MealTimeDetailView). */
@Composable
fun MealTimeDetailScreen(mealTime: MealTime, date: LocalDate, onBack: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    var editing by remember { mutableStateOf<LogEntry?>(null) }
    var savingRecipe by remember { mutableStateOf(false) }
    var sharing by remember { mutableStateOf(false) }
    val day = dayKey(date)
    val entries = (store.data.logs[day] ?: emptyList()).filter { it.mealTime == mealTime }

    editing?.let { entry -> LogEditorScreen(entry, day, onBack = { editing = null }); return }
    if (savingRecipe) {
        /** The one meal's name, or "Dinner 21 Oct" for several, to change before saving. */
        val name = if (entries.size == 1) entries[0].name else "${mealTime.title} ${shortDate(date)}"
        BackTo { savingRecipe = false }
        RecipeEditorScreen(recipeDraftOf(name, entries.flatMap { it.items }), onClose = { savingRecipe = false }, imported = true) { store.notice = "Saved to My foods" }
        return
    }
    if (sharing) {
        BackTo { sharing = false }
        MealSharePreview(MealShareRequest.meal(mealTime, entries, date), onDismiss = { sharing = false })
        return
    }

    BackTo(onBack = onBack)
    LeanrScreen(mealTime.title, onBack = onBack, showSettings = false) {
        item {
            LeanrSection("${mealTime.title} totals", footer = "Includes only food logged to ${mealTime.title.lowercase()} on this day.") {
                Text(longDate(date), style = LeanrType.subheadline, color = c.secondaryText, modifier = Modifier.padding(start = 16.dp, top = 12.dp))
                NutritionView(Nutrition(entries.flatMap { it.items }))
            }
        }
        item {
            LeanrSection("Logged food") {
                if (entries.isEmpty()) SectionText("Nothing logged for ${mealTime.title.lowercase()} yet.")
                entries.forEachIndexed { i, entry ->
                    LeanrRow(entry.name, Nutrition(entry.items).text, divider = i < entries.size - 1, onClick = { editing = entry }, trailing = {
                        IconButton(onClick = { store.deleteLog(entry, day) }) { Icon(Icons.Outlined.RemoveCircleOutline, "Delete ${entry.name}", tint = c.over) }
                    })
                }
            }
        }
        if (entries.isNotEmpty()) item {
            LeanrSection(footer = "Puts everything in ${mealTime.title.lowercase()} into one recipe in My foods, so you can log it again in one go and change the amounts each time.") {
                LeanrRow("Share as image", titleColour = c.accent, leading = { Icon(Icons.Filled.Image, null, tint = c.accent) }) { sharing = true }
                LeanrRow("Save as a recipe", titleColour = c.accent, divider = false, leading = { Icon(Icons.Outlined.Restaurant, null, tint = c.accent) }) { savingRecipe = true }
            }
        }
    }
}

/**
 * Changes a logged meal: its name, meal time and day, the amounts, and which foods are in it (LogEditor).
 * Nothing changes until Save, and Undo puts the old version back.
 */
@Composable
fun LogEditorScreen(entry: LogEntry, day: String, onBack: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    // A recipe made from another recipe lists that recipe's ingredients, so each one can be changed here.
    val original = remember(entry.id) { entry.copy(items = entry.items.map { it.copy(food = it.food.brokenIntoIngredients) }) }
    var edited by remember(entry.id) { mutableStateOf(original) }
    var date by remember(entry.id) { mutableStateOf(parseDayKey(day) ?: entry.time.atZone(ZoneId.systemDefault()).toLocalDate()) }
    var picking by remember { mutableStateOf(false) }
    var choosingDay by remember { mutableStateOf(false) }
    var confirmingDelete by remember { mutableStateOf(false) }
    var sharingImage by remember { mutableStateOf(false) }
    /** Goes up when amounts change from outside the fields, so the fields show the new figure. */
    var revision by remember { mutableIntStateOf(0) }
    val newDay = dayKey(date)
    val changed = edited != original || newDay != day
    val canSave = changed && edited.isValid && edited.name.isNotBlank() && !ContentFilter.flags(edited.name)

    if (picking) {
        FoodPickerScreen("Add food", "Add to ${edited.name}", quickAddLabel = "Add", onBack = { picking = false }, onPick = { portion ->
            val fresh = portion.copy(id = newId())
            val items = edited.items.toMutableList()
            val i = items.indexOfFirst { it.food == fresh.food }
            if (i >= 0) items[i] = items[i].copy(quantity = items[i].quantity + fresh.quantity) else items += fresh
            edited = edited.copy(items = combined(items)); revision += 1
            picking = false
        })
        return
    }
    if (sharingImage) {
        val subtitle = edited.mealTime?.let { "${it.title} · ${shortDate(date)}" } ?: shortDate(date)
        BackTo { sharingImage = false }
        MealSharePreview(edited.name, edited.items, onDismiss = { sharingImage = false }, subtitle = subtitle)
        return
    }

    fun save() {
        var saved = edited.copy(name = edited.name.trim())
        // Moved to another day: same clock time, new date.
        if (newDay != day) {
            val clock = edited.time.atZone(ZoneId.systemDefault()).toLocalTime()
            saved = saved.copy(time = date.atTime(clock).atZone(ZoneId.systemDefault()).toInstant())
        }
        if (store.updateLog(saved, day, newDay)) {
            store.notice = if (newDay == day) "Saved ${saved.name}" else "Moved ${saved.name} to ${abbreviatedDate(date)}"
            onBack()
        }
    }
    fun updateItem(id: String, change: (Portion) -> Portion) { edited = edited.copy(items = edited.items.map { if (it.id == id) change(it) else it }) }

    BackTo(onBack = onBack)
    LeanrScreen("Edit logged meal", onBack = onBack, showSettings = false, actions = { TopAction("Save", enabled = canSave) { save() } }) {
        item {
            LeanrSection {
                SectionTextField(edited.name, { edited = edited.copy(name = it) }, "Meal name", singleLine = false)
                OffensiveTextNote(edited.name, modifier = Modifier.padding(horizontal = 16.dp))
                PickerRow("Meal time", edited.mealTime, listOf<MealTime?>(null) + MealTime.entries, { it?.title ?: "Unassigned" }) { edited = edited.copy(mealTime = it) }
                LeanrRow("Day", divider = false, onClick = { choosingDay = true }, trailing = { Text(abbreviatedDate(date), style = LeanrType.body, color = c.accent) })
            }
        }
        item(key = "foods") {
            LeanrSection("Foods", footer = "Tap the minus to take a food out.") {
                if (edited.items.isEmpty()) SectionText("Add at least one food to keep this meal.")
                edited.items.forEach { item ->
                    key(item.id, revision) {
                        Column(Modifier.padding(top = 10.dp)) {
                            LeanrRow(item.food.name, "${(item.food.cal * item.quantity).number} Cal · ${(item.food.p * item.quantity).number} g protein", divider = false, trailing = {
                                IconButton(onClick = { edited = edited.copy(items = edited.items.filter { it.id != item.id }) }) {
                                    Icon(Icons.Outlined.RemoveCircleOutline, "Take out ${item.food.name}", tint = c.over)
                                }
                            })
                            NumberField("Servings", item.quantity, { q -> updateItem(item.id) { it.copy(quantity = q) } })
                        }
                    }
                }
                LeanrRow("Add food", titleColour = c.accent, divider = false, leading = { Icon(Icons.Filled.AddCircle, null, tint = c.accent) }) { picking = true }
            }
        }
        edited.items.forEach { item ->
            val ingredients = item.ingredientPortions ?: return@forEach
            item(key = "in-${item.id}") {
                LeanrSection("In ${item.food.name}", footer = "Change an amount or take one out for this meal only. Your saved recipe stays as it is.") {
                    ingredients.forEachIndexed { j, ingredient ->
                        val weight = ingredient.food.servingWeight
                        key(ingredient.id, revision) {
                            LeanrRow(ingredient.food.name, "${(ingredient.food.cal * ingredient.quantity).whole.number} Cal · ${(ingredient.food.p * ingredient.quantity).number} g protein",
                                divider = false, trailing = {
                                    if (ingredients.size > 1) IconButton(onClick = {
                                        val list = (item.food.ingredients ?: return@IconButton).filterIndexed { k, _ -> k != j }
                                        if (list.isNotEmpty()) updateItem(item.id) { it.copy(food = it.food.withIngredients(list)) }
                                    }) { Icon(Icons.Outlined.RemoveCircleOutline, "Take out ${ingredient.food.name}", tint = c.over) }
                                })
                            val unit = weight?.first ?: 1.0
                            NumberField(weight?.let { if (it.second == "g") "Grams" else "mL" } ?: "Servings", unit * ingredient.quantity, { value ->
                                // Back from this portion to the whole recipe, which the saved figures are worked out from.
                                if (!value.isFinite() || value <= 0 || abs(ingredient.quantity * unit - value) < 0.0001) return@NumberField
                                val list = (item.food.ingredients ?: return@NumberField).toMutableList()
                                if (j !in list.indices) return@NumberField
                                list[j] = list[j].copy(quantity = value / unit * (item.food.recipeYield ?: 1.0) / max(item.quantity, 0.001))
                                updateItem(item.id) { it.copy(food = it.food.withIngredients(list)) }
                            })
                        }
                    }
                }
            }
        }
        if (edited.items.isNotEmpty()) {
            item { LeanrSection("Totals") { NutritionView(Nutrition(edited.items)) } }
            item {
                val withIngredients = edited.items.any { it.ingredientPortions != null }
                LeanrSection(footer = "A story-sized card with the macros${if (withIngredients) " and ingredients" else ""}, for Instagram, TikTok or your photos.") {
                    LeanrRow("Share as image", titleColour = c.accent, divider = false, leading = { Icon(Icons.Filled.Image, null, tint = c.accent) }) { sharingImage = true }
                }
            }
        }
        item {
            LeanrSection {
                LeanrRow("Delete from log", titleColour = c.over, divider = false, leading = { Icon(Icons.Filled.Delete, null, tint = c.over) }) { confirmingDelete = true }
            }
        }
    }
    if (choosingDay) DayPickerDialog(date, { date = it }, { choosingDay = false })
    if (confirmingDelete) ConfirmDialog("Delete ${original.name} from your log?", "Delete from log", onConfirm = {
        if (store.deleteLog(original, day)) onBack()
    }, onDismiss = { confirmingDelete = false })
}

/** Target sets: switch between training, rest or other day types, and edit them (TargetsView). */
@Composable
fun TodayTargetsScreen(onBack: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    var editing by remember { mutableStateOf<Goals?>(null) }
    editing?.let { goal -> GoalEditorScreen(goal, onDone = { editing = null }); return }
    BackTo(onBack = onBack)
    LeanrScreen("Your targets", onBack = onBack, showSettings = false) {
        item {
            LeanrSection("Target sets") {
                store.data.goalSets.forEach { goal ->
                    val active = goal.id == store.goals.id
                    LeanrRow(goal.name, onClick = { store.useGoals(goal) },
                        leading = { Icon(if (active) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked, null, tint = c.accent) },
                        trailing = {
                            if (store.data.goalSets.size > 1) IconButton(onClick = { store.deleteGoals(goal) }) { Icon(Icons.Filled.Delete, "Delete ${goal.name}", tint = c.over) }
                            TextButton(onClick = { editing = goal }) { Text("Edit", color = c.accent) }
                        })
                }
                LeanrRow("Add target set", titleColour = c.accent, divider = false) { editing = store.goals.copy(id = newId(), name = "New targets") }
            }
        }
        item {
            LeanrSection {
                SectionText("Switch between training, rest or other day types. Past days keep the target snapshot captured when you logged them. Blank fields are not tracked.")
            }
        }
    }
}

@Composable
private fun GoalEditorScreen(initial: Goals, onDone: () -> Unit) {
    val store = AppServices.store
    var goal by remember(initial.id) { mutableStateOf(initial) }
    var calculator by remember { mutableStateOf(false) }
    var revision by remember { mutableIntStateOf(0) }
    if (calculator) {
        TargetCalculatorScreen(onCancel = { calculator = false }) { values -> goal = goal.copy(values = goal.values + values); revision += 1; calculator = false }
        return
    }
    BackTo(onBack = onDone)
    LeanrScreen("Edit targets", onBack = onDone, showSettings = false, actions = {
        TopAction("Save", enabled = goal.isValid) { if (store.saveGoals(goal)) onDone() }
    }) {
        item { LeanrSection { SectionTextField(goal.name, { goal = goal.copy(name = it) }, "Target set name") } }
        item(key = "daily-$revision") {
            LeanrSection("Daily targets") {
                nutrientNames.forEach { n ->
                    OptionalNumberField("${n.label} (${n.unit})", goal.values[n.key], { value ->
                        goal = goal.copy(values = if (value == null) goal.values - n.key else goal.values + (n.key to value))
                    }, divider = goal.values[n.key] == null)
                    if (goal.values[n.key] != null) {
                        Segmented(listOf(false to "At most", true to "At least"), n.key in goal.minimums, Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) { minimum ->
                            goal = goal.copy(minimums = if (minimum) goal.minimums + n.key else goal.minimums - n.key)
                        }
                    }
                }
            }
        }
        item {
            LeanrSection("Typical meal") {
                NumberField("Calories", goal.mealCal, { goal = goal.copy(mealCal = it) })
                NumberField("Protein (g)", goal.mealProtein, { goal = goal.copy(mealProtein = it) }, divider = false)
            }
        }
        item { LeanrSection { LeanrRow("Estimate targets from body measurements", titleColour = Leanr.colours.accent, divider = false) { calculator = true } } }
    }
}

@Composable
private fun rememberDoublePref(key: String, default: Double) = remember(key) { mutableDoubleStateOf(Prefs.double(key) ?: default) }

/** Mifflin–St Jeor targets from body measurements, or from measured maintenance when there's enough data (TargetCalculator). */
@Composable
private fun TargetCalculatorScreen(onCancel: () -> Unit, apply: (Map<String, Double>) -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    // Remembered, so updating targets later only needs what's changed.
    var female by rememberBoolPref("calc.female", false)
    var age by rememberDoublePref("calc.age", 30.0)
    var height by rememberDoublePref("calc.height", 175.0)
    var weight by rememberDoublePref("calc.weight", 75.0)
    var activity by rememberDoublePref("calc.activity", 1.375)
    var adjustment by rememberDoublePref("calc.adjustment", 0.0)
    var proteinPerKG by rememberDoublePref("calc.proteinPerKG", 1.6)
    var fatPercent by rememberDoublePref("calc.fatPercent", 25.0)
    var useMeasured by remember { mutableStateOf(true) }
    var revision by remember { mutableIntStateOf(0) }
    val points = remember(store.data.weightLog) { WeightTrend.points(store.data.weightLog) }
    val measured = remember(store.data.logs, points) { WeightTrend.maintenance(store.data.logs, points) }
    LaunchedEffect(Unit) { points.lastOrNull()?.let { weight = it.trend.tenth; revision += 1 } }
    LaunchedEffect(female, age, height, weight, activity, adjustment, proteinPerKG, fatPercent) {
        Prefs.set("calc.age", age); Prefs.set("calc.height", height); Prefs.set("calc.weight", weight); Prefs.set("calc.activity", activity)
        Prefs.set("calc.adjustment", adjustment); Prefs.set("calc.proteinPerKG", proteinPerKG); Prefs.set("calc.fatPercent", fatPercent)
    }
    val bmr = 10 * weight + 6.25 * height - 5 * age + (if (female) -161 else 5)
    val equation = bmr * activity
    /** Measured from your log and weight trend when there's enough data, otherwise the equation's estimate. */
    val maintenance = if (useMeasured) measured?.calories ?: equation else equation
    val calories = maintenance + adjustment
    val protein = weight * proteinPerKG
    val fat = calories * fatPercent / 100 / 9
    val carbs = max(0.0, (calories - protein * 4 - fat * 9) / 4)
    val valid = age in 18.0..100.0 && height in 120.0..230.0 && weight in 35.0..250.0 && proteinPerKG in 0.8..3.3 && fatPercent in 15.0..45.0 &&
        calories > 0 && protein * 4 + fat * 9 <= calories

    BackTo(onBack = onCancel)
    LeanrScreen("Estimate targets", onBack = onCancel, showSettings = false) {
        if (points.isNotEmpty() || measured != null) item {
            LeanrSection("From your data", footer = if (measured != null && useMeasured) "Measured maintenance replaces the activity-based estimate below. Your goal is still added or subtracted." else null) {
                points.lastOrNull()?.let { last ->
                    LeanrRow("Trend weight", divider = true, trailing = { Text("${last.trend.number} kg", style = LeanrType.body, color = c.secondaryText) })
                    if (abs(last.trend - weight) >= 0.1) LeanrRow("Use my trend weight", titleColour = c.accent) { weight = last.trend.tenth; revision += 1 }
                }
                measured?.let { m ->
                    LeanrRow("Use my measured maintenance", "${m.calories.whole.number} Cal/day from ${m.loggedDays} logged days", divider = false, onClick = { useMeasured = !useMeasured }, trailing = {
                        Switch(useMeasured, { useMeasured = it }, colors = SwitchDefaults.colors(checkedTrackColor = c.accent))
                    })
                }
            }
        }
        item(key = "body-$revision") {
            LeanrSection("Body measurements") {
                PickerRow("Sex used in equation", female, listOf(false, true), { if (it) "Female" else "Male" }) { female = it }
                NumberField("Age (18–100)", age, { age = it })
                NumberField("Height (cm)", height, { height = it })
                NumberField("Weight (kg)", weight, { weight = it })
                PickerRow("Activity", activity, ACTIVITY.map { it.first }, { a -> ACTIVITY.firstOrNull { it.first == a }?.second ?: a.number }) { activity = it }
                PickerRow("Goal", adjustment, GOAL.map { it.first }, { a -> GOAL.firstOrNull { it.first == a }?.second ?: a.number }) { adjustment = it }
                NumberField("Protein (g/kg)", proteinPerKG, { proteinPerKG = it })
                NumberField("Fat share (%)", fatPercent, { fatPercent = it }, divider = false)
            }
        }
        item {
            LeanrSection("Estimate") {
                Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    if (valid) {
                        LabeledValue(if (useMeasured && measured != null) "Measured maintenance" else "Estimated maintenance", maintenance.whole.number + " Cals/day")
                        LabeledValue("Daily calorie target", calories.number + " Cals")
                        LabeledValue("Protein", protein.number + " g")
                        LabeledValue("Carbs", carbs.number + " g")
                        LabeledValue("Fat", fat.number + " g")
                        TextButton(onClick = { apply(mapOf("cal" to calories.whole, "p" to protein.whole, "c" to carbs.whole, "f" to fat.whole)) }) {
                            Text("Use these targets", color = c.accent, style = LeanrType.body)
                        }
                    } else Text("Enter valid measurements and macro settings.", style = LeanrType.body, color = c.text)
                    Text("Mifflin–St Jeor estimate for adults. Actual needs vary; review against your own progress. Talk to a doctor or Accredited Practising Dietitian before making big changes to how you eat, especially if you’re pregnant, have a medical condition or have had an eating disorder.",
                        style = LeanrType.caption, color = c.secondaryText)
                }
            }
        }
    }
}

private val ACTIVITY = listOf(1.2 to "Mostly sitting", 1.375 to "Light · 1–3 days/week", 1.55 to "Moderate · 3–5 days/week", 1.725 to "Hard · 6–7 days/week", 1.9 to "Very hard / physical job")
private val GOAL = listOf(0.0 to "Maintain", -275.0 to "Lose ~0.25 kg/week", -550.0 to "Lose ~0.5 kg/week", 275.0 to "Gain ~0.25 kg/week")
