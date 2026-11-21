package com.isaiahgraham.leanrrr.feature.today

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.RemoveCircleOutline
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.LogEntry
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.dayKey
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.feature.scan.BarcodeScanScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrRow
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import java.time.LocalDate
import java.time.ZoneId
import kotlin.math.abs

private val MACROS = listOf("p" to "Protein", "c" to "Carbs", "f" to "Fat")

/** "Today", "Tomorrow" or "Monday 23 November". */
internal fun planDayTitle(day: LocalDate): String = when (day) {
    LocalDate.now() -> "Today"
    LocalDate.now().plusDays(1) -> "Tomorrow"
    else -> weekdayDate(day)
}

private sealed interface PlanAdd {
    val meal: MealTime
    data class Choose(override val meal: MealTime) : PlanAdd
    data class Scan(override val meal: MealTime) : PlanAdd
    data class Describe(override val meal: MealTime) : PlanAdd
}

/**
 * Plan a day's meals ahead against its targets (PlanView.swift). Nothing counts until it's eaten: on the day, Today lists the
 * plan and a tap logs each meal.
 */
@Composable
fun PlanScreen(onBack: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    var dateKey by rememberSaveable { mutableStateOf(dayKey(LocalDate.now().plusDays(1))) }
    val date = LocalDate.parse(dateKey)
    var adding by remember { mutableStateOf<PlanAdd?>(null) }
    var clearing by remember { mutableStateOf(false) }
    var ideas by remember { mutableStateOf(emptyList<LeftToday.Suggestion>()) }

    val key = dayKey(date)
    val entries = MealPlan.entries(store.data, key)
    val goals = store.goals
    val logged = (store.data.logs[key] ?: emptyList()).flatMap { it.items }
    /** What's already logged for the day, so planning today counts it. */
    val eaten = Nutrition(logged)
    val planned = Nutrition(entries.flatMap { it.items })
    /** Logged food plus the plan: where the day ends up if you eat it all. */
    val total = Nutrition(logged + entries.flatMap { it.items })
    /** The first meal with nothing in it yet, where a suggestion goes. */
    val openMeal = MealTime.entries.firstOrNull { meal -> entries.none { it.mealTime == meal } } ?: MealTime.SNACKS

    LaunchedEffect(key, entries.map { it.id }, total.cal.toInt(), goals.values["cal"], store.foodsLoaded) {
        // Ideas that fit what the plan leaves, worked out as if the plan were eaten, at midday so each is one meal's worth.
        if (entries.isEmpty()) { ideas = emptyList(); return@LaunchedEffect }
        val noon = date.atTime(12, 0).atZone(ZoneId.systemDefault()).toInstant()
        val names = entries.map { it.name.lowercase() }.toSet()
        ideas = LeftToday.suggestions(store, MealPlan.asLogged(store.data, key), noon, limit = 6).filter { it.name.lowercase() !in names }.take(3)
    }

    when (val add = adding) {
        is PlanAdd.Choose -> {
            FoodPickerScreen("Choose a food", "Plan for ${add.meal.title}", quickAddLabel = "Plan", onBack = { adding = null }, onPick = { portion ->
                if (store.plan(listOf(portion), portion.food.name, add.meal, date)) adding = null
            })
            return
        }
        is PlanAdd.Scan -> {
            BackTo { adding = null }
            BarcodeScanScreen(onFound = { food ->
                if (store.plan(listOf(Portion(food = food)), food.name, add.meal, date)) { store.notice = "Planned for ${add.meal.title.lowercase()}"; adding = null }
            }, onDismiss = { adding = null })
            return
        }
        is PlanAdd.Describe -> {
            MealTextScreen(add.meal, onBack = { adding = null }, verb = "Plan") { portions, name -> store.plan(portions, name, add.meal, date) }
            return
        }
        null -> {}
    }

    /** What the day leaves after the plan, counting anything already logged. */
    val leftText: String? = run {
        if (entries.isEmpty()) return@run null
        val parts = mutableListOf<String>()
        goals.values["cal"]?.let { cal ->
            val left = cal - total.cal
            parts += if (left >= 0) "${left.whole.number} Cal" else "${abs(left).whole.number} Cal over"
        }
        for ((k, label) in MACROS) {
            val target = goals.values[k] ?: continue
            val left = target - total.value(k)
            parts += if (left >= 0) "${left.whole.number} g ${label.lowercase()}" else "${abs(left).whole.number} g ${label.lowercase()} over"
        }
        if (parts.isEmpty()) return@run null
        val loggedText = if (eaten.cal > 0) "Counts the ${eaten.cal.whole.number} Cal you’ve logged plus ${planned.cal.whole.number} Cal planned. " else ""
        loggedText + "After this plan: " + parts.joinToString(", ") + "."
    }

    BackTo(onBack = onBack)
    LeanrScreen("Plan ahead", onBack = onBack, showSettings = false) {
        item { LeanrSection { PickerRow("Day", date, MealPlan.days(), ::planDayTitle, divider = false) { dateKey = dayKey(it) } } }
        item {
            LeanrSection(if (eaten.cal > 0) "Eaten and planned" else "Planned so far", footer = leftText) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    goals.values["cal"]?.let { EatenPlannedBar("Calories", eaten.cal, planned.cal, it, "Cal", false, c.accent) }
                    MACROS.forEach { (k, label) ->
                        val target = goals.values[k]
                        if (target != null) EatenPlannedBar(label, eaten.value(k), planned.value(k), target, "g", k in goals.minimums, c.nutrient(k))
                        else Row {
                            // No target set: still show the day's running total.
                            Text(label, style = LeanrType.label, color = c.secondaryText, modifier = Modifier.weight(1f))
                            Text("${total.value(k).whole.number} g", style = LeanrType.caption, color = c.text)
                        }
                    }
                }
            }
        }
        MealTime.entries.forEach { meal ->
            item(key = "plan-${meal.raw}") { PlanMealSection(meal, entries.filter { it.mealTime == meal }, date) { adding = it } }
        }
        if (ideas.isNotEmpty()) item {
            LeanrSection("To fill the gap", footer = "Tap + to add it to ${openMeal.title.lowercase()}.") {
                ideas.forEach { idea ->
                    SuggestionRow(idea, "Plan ${idea.name} for ${openMeal.title}", Modifier.padding(start = 16.dp, end = 4.dp, top = 6.dp, bottom = 6.dp)) {
                        store.plan(idea.items, idea.name, openMeal, date)
                    }
                }
            }
        }
        item {
            val today = store.data.logs[dayKey(LocalDate.now())] ?: emptyList()
            val canCopy = date != LocalDate.now() && today.isNotEmpty()
            LeanrSection(footer = "Plans count towards nothing until you log them. On the day, they’re on Today, ready to log with a tap.") {
                if (canCopy) LeanrRow("Copy today’s meals", titleColour = c.accent, divider = entries.isNotEmpty(),
                    leading = { Icon(Icons.Filled.ContentCopy, null, tint = c.accent) }) {
                    store.change(undo = "Copied today’s meals") { state ->
                        today.fold(state) { s, entry -> MealPlan.add(entry.items, entry.name, entry.mealTime ?: MealTime.SNACKS, key, s) }
                    }
                }
                if (entries.isNotEmpty()) LeanrRow("Clear this day’s plan", titleColour = c.over, divider = false,
                    leading = { Icon(Icons.Filled.Delete, null, tint = c.over) }) { clearing = true }
                if (!canCopy && entries.isEmpty()) SectionText("Add meals above to plan this day.")
            }
        }
    }
    if (clearing) ConfirmDialog("Clear the plan for ${planDayTitle(date).lowercase()}?", "Clear plan", onConfirm = {
        store.change(undo = "Cleared your plan") { state ->
            val plans = (state.plans ?: emptyMap()) - key
            state.copy(plans = plans.ifEmpty { null })
        }
    }, onDismiss = { clearing = false })
}

@Composable
private fun PlanMealSection(meal: MealTime, planned: List<LogEntry>, date: LocalDate, add: (PlanAdd) -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    var menu by remember { mutableStateOf(false) }
    val header = meal.title + if (planned.isEmpty()) "" else "  ·  ${Nutrition(planned.flatMap { it.items }).cal.whole.number} Cal"
    LeanrSection(header) {
        planned.forEach { entry ->
            LeanrRow(entry.name, Nutrition(entry.items).text, trailing = {
                IconButton(onClick = { store.removePlanned(entry.id, date) }) { Icon(Icons.Outlined.RemoveCircleOutline, "Remove ${entry.name}", tint = c.over) }
            })
        }
        Box {
            LeanrRow("Add to ${meal.title.lowercase()}", titleColour = c.accent, divider = false, leading = { Icon(Icons.Filled.AddCircle, null, tint = c.accent) }) { menu = true }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(text = { Text("Choose a food") }, leadingIcon = { Icon(Icons.Filled.Search, null) }, onClick = { menu = false; add(PlanAdd.Choose(meal)) })
                DropdownMenuItem(text = { Text("Scan a barcode") }, leadingIcon = { Icon(Icons.Filled.QrCodeScanner, null) }, onClick = { menu = false; add(PlanAdd.Scan(meal)) })
                DropdownMenuItem(text = { Text("Describe it") }, leadingIcon = { Icon(Icons.Outlined.ChatBubbleOutline, null) }, onClick = { menu = false; add(PlanAdd.Describe(meal)) })
                if (store.data.meals.isNotEmpty()) {
                    HorizontalDivider()
                    Text("Saved meals", style = LeanrType.caption, color = c.secondaryText, modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp))
                    store.data.meals.forEach { saved ->
                        DropdownMenuItem(text = { Text(saved.name) }, onClick = { menu = false; store.plan(saved.items, saved.name, meal, date) })
                    }
                }
                LeftToday.usual(meal, store.data.logs)?.let { usual ->
                    DropdownMenuItem(text = { Text("Your usual: ${usual.name}") }, leadingIcon = { Icon(Icons.AutoMirrored.Filled.Undo, null) },
                        onClick = { menu = false; store.plan(usual.items, usual.name, meal, date) })
                }
            }
        }
    }
}

/** Today's planned meals, each logged with a tap (PlannedSection). */
@Composable
fun PlannedSection(date: LocalDate) {
    val store = AppServices.store
    val c = Leanr.colours
    val planned = MealPlan.entries(store.data, dayKey(date))
    if (planned.isEmpty()) return
    LeanrSection("Planned", footer = "Tick a meal when you’ve eaten it to log it.") {
        MealTime.entries.forEach { meal ->
            planned.filter { it.mealTime == meal }.forEach { entry ->
                val n = Nutrition(entry.items)
                LeanrRow(entry.name, "${meal.title} · ${n.cal.whole.number} Cal · ${n.p.whole.number} g protein", trailing = {
                    IconButton(onClick = { store.removePlanned(entry.id, date) }) { Icon(Icons.Outlined.RemoveCircleOutline, "Remove ${entry.name}", tint = c.secondaryText) }
                    IconButton(onClick = { if (store.logPlanned(setOf(entry.id), date)) store.notice = "Logged ${entry.name}" }) {
                        Icon(Icons.Outlined.CheckCircle, "Log ${entry.name}", tint = c.accent, modifier = Modifier.size(28.dp))
                    }
                })
            }
        }
        if (planned.size > 1) {
            LeanrRow("Log all ${planned.size}", titleColour = c.accent, divider = false) {
                if (store.logPlanned(planned.map { it.id }.toSet(), date)) store.notice = "Logged your plan"
            }
        }
    }
}

/** A target bar split in two: what's eaten in the full colour, then what's planned in a lighter shade of it. */
@Composable
private fun EatenPlannedBar(label: String, eaten: Double, planned: Double, target: Double, unit: String, minimum: Boolean, colour: Color) {
    val c = Leanr.colours
    val total = (eaten + planned).whole
    val over = !minimum && total > target
    Column(Modifier.fillMaxWidth().clearAndSetSemantics {
        contentDescription = "$label: ${eaten.whole.number} eaten and ${planned.whole.number} planned, of ${target.number} $unit"
    }, verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(label, style = LeanrType.label, color = c.secondaryText)
            Spacer(Modifier.weight(1f).width(4.dp))
            Text("${total.number} / ${target.number} $unit", style = LeanrType.caption, color = if (over) c.over else c.text)
        }
        val eatenShare = (eaten / maxOf(target, 0.001)).coerceIn(0.0, 1.0).toFloat()
        val bothShare = ((eaten + planned) / maxOf(target, 0.001)).coerceIn(0.0, 1.0).toFloat()
        Box(Modifier.fillMaxWidth().height(6.dp).clip(CircleShape).background(c.text.copy(alpha = 0.08f))) {
            Box(Modifier.fillMaxWidth(bothShare).fillMaxHeight().clip(CircleShape).background(colour.copy(alpha = 0.4f)))
            Box(Modifier.fillMaxWidth(eatenShare).fillMaxHeight().clip(CircleShape).background(colour))
        }
    }
}

