package com.isaiahgraham.leanrrr.feature.progress

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.MilitaryTech
import androidx.compose.material.icons.filled.MonitorWeight
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.achievements
import com.isaiahgraham.leanrrr.data.dayKey
import com.isaiahgraham.leanrrr.data.kgText
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.data.rememberStringPref
import com.isaiahgraham.leanrrr.ui.components.LeanrRow
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import java.time.LocalDate
import kotlin.math.abs

// A port of ProgressTabView.swift: weight, measurements and photos, and a breakdown of the last week, month or three months.

/** Progress is split into three pages so each one fits on a screen or two, instead of one long scroll. */
enum class ProgressPage(val raw: String, val title: String) {
    OVERVIEW("overview", "Overview"), BODY("body", "Body"), EATING("eating", "Eating");
    companion object {
        const val STORAGE_KEY = "progress.page"
        fun fromRaw(raw: String) = entries.firstOrNull { it.raw == raw } ?: OVERVIEW
    }
}

/** The sections of the Progress tab, in the order and with the ones hidden that you chose. */
enum class ProgressPart(val raw: String, val title: String, val page: ProgressPage, val symbol: String) {
    CHECK_IN("checkIn", "Weekly check-in", ProgressPage.OVERVIEW, "arrow.triangle.2.circlepath"),
    INSIGHTS("insights", "Insights", ProgressPage.OVERVIEW, "lightbulb"),
    WEIGHT("weight", "Weight", ProgressPage.BODY, "scalemass"),
    STEPS("steps", "Steps", ProgressPage.BODY, "figure.walk"),
    ACTIVE_ENERGY("activeEnergy", "Calories burnt", ProgressPage.BODY, "flame"),
    BODY("body", "Measurements and photos", ProgressPage.BODY, "ruler"),
    WEEK("week", "Your week", ProgressPage.OVERVIEW, "calendar"),
    ACHIEVEMENTS("achievements", "Achievements", ProgressPage.OVERVIEW, "rosette"),
    CALORIES("calories", "Calories per day", ProgressPage.EATING, "chart.bar"),
    AVERAGES("averages", "Daily averages", ProgressPage.EATING, "equal.circle"),
    MACROS("macros", "Where the calories come from", ProgressPage.EATING, "chart.pie"),
    MEALS("meals", "By meal", ProgressPage.EATING, "fork.knife"),
    CONTRIBUTORS("contributors", "Biggest contributors", ProgressPage.EATING, "list.number");

    companion object {
        const val ORDER_KEY = "progress.order"
        const val HIDDEN_KEY = "progress.hidden"
        /** The saved order, with any section added since put at the end. Stored as names separated by commas. */
        fun order(text: String): List<ProgressPart> {
            val parts = text.split(",").mapNotNull { name -> entries.firstOrNull { it.raw == name } }.distinct()
            return parts + entries.filter { it !in parts }
        }
        fun hidden(text: String): Set<ProgressPart> = text.split(",").mapNotNull { name -> entries.firstOrNull { it.raw == name } }.toSet()
        fun shown(order: String, hidden: String): List<ProgressPart> { val h = hidden(hidden); return order(order).filter { it !in h } }
        fun text(parts: Iterable<ProgressPart>) = parts.joinToString(",") { it.raw }
    }
}

/** Screens pushed within the Progress tab. */
private sealed interface ProgressRoute {
    data object Weight : ProgressRoute
    data object CheckIn : ProgressRoute
    data object Week : ProgressRoute
    data object Achievements : ProgressRoute
    data object Measurements : ProgressRoute
    data class Site(val site: String) : ProgressRoute
    data object Photos : ProgressRoute
}

@Composable
fun ProgressScreen() {
    var stack by remember { mutableStateOf(listOf<ProgressRoute>()) }
    val push: (ProgressRoute) -> Unit = { stack = stack + it }
    val pop: () -> Unit = { stack = stack.dropLast(1) }
    BackHandler(enabled = stack.isNotEmpty(), onBack = pop)
    when (val top = stack.lastOrNull()) {
        null -> ProgressMain(push)
        ProgressRoute.Weight -> WeightScreen(pop)
        ProgressRoute.CheckIn -> CheckInScreen(pop)
        ProgressRoute.Week -> WeeklyReviewScreen(pop)
        ProgressRoute.Achievements -> AchievementsScreen(pop)
        ProgressRoute.Measurements -> MeasurementsScreen(pop) { push(ProgressRoute.Site(it)) }
        is ProgressRoute.Site -> MeasurementChartScreen(top.site, pop)
        ProgressRoute.Photos -> ProgressPhotosScreen(pop)
    }
}

@Composable
private fun ProgressMain(push: (ProgressRoute) -> Unit) {
    val store = AppServices.store
    var rangeRaw by rememberStringPref("progress.range", "30")
    var pageRaw by rememberStringPref(ProgressPage.STORAGE_KEY, ProgressPage.OVERVIEW.raw)
    var orderText by rememberStringPref(ProgressPart.ORDER_KEY, "")
    var hiddenText by rememberStringPref(ProgressPart.HIDDEN_KEY, "")
    var arranging by remember { mutableStateOf(false) }
    var yearReview by remember { mutableStateOf<YearReview?>(null) }
    val range = rangeRaw.toIntOrNull()?.takeIf { it in ProgressBreakdown.ranges } ?: 30
    val page = ProgressPage.fromRaw(pageRaw)
    val breakdown = ProgressBreakdown.make(store.data, store.goals, range)

    yearReview?.let { review -> YearReviewScreen(review) { yearReview = null }; return }

    LeanrScreen("Progress", actions = {
        IconButton(onClick = { arranging = true }) { Icon(Icons.Filled.SwapVert, "Arrange sections", tint = Leanr.colours.accent) }
    }) {
        item {
            Column(Modifier.padding(bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Segmented(ProgressPage.entries.map { it to it.title }, page, { pageRaw = it.raw })
                // The range changes the graphs, so Overview (check-in, insights and this week) leaves it out.
                if (page != ProgressPage.OVERVIEW) Segmented(listOf(7 to "7 days", 30 to "30 days", 90 to "90 days"), range, { rangeRaw = it.toString() })
            }
        }
        ProgressPart.shown(orderText, hiddenText).filter { it.page == page }.forEach { part ->
            item(key = part.raw) { PartSection(part, breakdown, push, openYear = { yearReview = it }) }
        }
    }
    if (arranging) ArrangeSheet(orderText, hiddenText, { orderText = it }, { hiddenText = it }) { arranging = false }
}

@Composable
private fun PartSection(part: ProgressPart, breakdown: ProgressBreakdown, push: (ProgressRoute) -> Unit, openYear: (YearReview) -> Unit) {
    val logged = breakdown.loggedDays > 0
    val dayKeys = breakdown.points.map { it.key }
    when (part) {
        ProgressPart.CHECK_IN -> CheckInRow { push(ProgressRoute.CheckIn) }
        ProgressPart.INSIGHTS -> InsightsSection(breakdown.days)
        ProgressPart.WEIGHT -> WeightSection(breakdown) { push(ProgressRoute.Weight) }
        ProgressPart.STEPS -> StepsProgressSection(dayKeys)
        ProgressPart.ACTIVE_ENERGY -> ActiveEnergyProgressSection(dayKeys)
        ProgressPart.BODY -> BodySection({ push(ProgressRoute.Measurements) }, { push(ProgressRoute.Photos) })
        ProgressPart.WEEK -> WeekSection { push(ProgressRoute.Week) }
        ProgressPart.ACHIEVEMENTS -> AchievementsSection({ push(ProgressRoute.Achievements) }, openYear)
        ProgressPart.CALORIES -> if (logged) CaloriesSection(breakdown) else LeanrSection {
            EmptyState(Icons.Filled.BarChart, "Nothing logged in the last ${breakdown.days} days", "Log a few days and your averages, macro split and biggest contributors fill in here.")
        }
        ProgressPart.AVERAGES -> if (logged) AveragesSection(breakdown)
        ProgressPart.MACROS -> if (logged) breakdown.share?.let { MacroSection(it, breakdown.shareComplete) }
        ProgressPart.MEALS -> if (logged && breakdown.mealTimes.isNotEmpty()) MealTimeSection(breakdown)
        ProgressPart.CONTRIBUTORS -> if (logged && breakdown.topFoods.isNotEmpty()) ContributorsSection(breakdown)
    }
}

@Composable
private fun InsightsSection(days: Int) {
    val store = AppServices.store
    val insights = ProgressInsights.make(store.data, store.goals, days)
    if (insights.isEmpty()) return
    LeanrSection("Insights · last $days days") {
        insights.forEachIndexed { i, insight ->
            LeanrRow(insight.text, divider = i < insights.size - 1, leading = { Icon(symbolIcon(insight.icon), null, tint = Leanr.colours.accent) })
        }
    }
}

@Composable
private fun AchievementsSection(open: () -> Unit, openYear: (YearReview) -> Unit) {
    val store = AppServices.store
    val shelf = store.data.achievements()
    val earned = shelf.count { it.earned }
    val year = YearReview.showing(LocalDate.now())
    LeanrSection {
        Box(Modifier.fillMaxWidth().clickable(onClick = open)) {
            FeatureRowContent(Icons.Filled.MilitaryTech, if (earned == 1) "1 achievement" else "$earned achievements",
                listOfNotNull(shelf.firstOrNull { !it.earned }?.let { "Next: ${it.moment.copy.title}" }))
        }
        if (year != null) LeanrRow("Your $year in Leanrrr", divider = false, titleColour = Leanr.colours.accent,
            leading = { Icon(Icons.Filled.AutoAwesome, null, tint = Leanr.colours.accent) },
            onClick = { openYear(YearReview.make(store.data, year, store.catalog.chains.map { it.id }.toSet())) })
    }
}

/** This week at a glance, whatever range is chosen. The full review has earlier weeks and a card to share. */
@Composable
private fun WeekSection(open: () -> Unit) {
    val store = AppServices.store
    val review = WeeklyReview.make(store.data, store.goals)
    LeanrSection("Your week · ${review.range}") {
        if (review.loggedDays == 0) {
            SectionText("Nothing logged this week yet.")
        } else {
            ValueRow("Days logged", "${review.loggedDays} of 7")
            review.averageCalories?.let { ValueRow("Average calories", "${it.rounded().number}${review.calorieTarget?.let { t -> " · target ${t.rounded().number}" } ?: ""}") }
            review.averageProtein?.let { ValueRow("Average protein", "${it.rounded().number} g${review.proteinTarget?.let { t -> " · target ${t.rounded().number}" } ?: ""}") }
            if (review.proteinTarget != null) ValueRow("Protein target hit", "${review.proteinDays} ${if (review.proteinDays == 1) "day" else "days"}")
            if (review.calorieTarget != null) ValueRow("On or under calories", "${review.calorieDays} ${if (review.calorieDays == 1) "day" else "days"}")
            review.weightChange?.let { ValueRow("Weight trend", "${WeeklyReview.signed(it)} kg") }
            review.nudges.forEach { SectionText(it) }
            if (review.topMeals.isNotEmpty()) ValueRow("Most logged", review.topMeals.joinToString(", ") { it.name })
        }
        LeanrRow("Full review and sharing", divider = false, titleColour = Leanr.colours.accent,
            leading = { Icon(Icons.Filled.BarChart, null, tint = Leanr.colours.accent) }, onClick = open)
    }
}

@Composable
private fun WeightSection(breakdown: ProgressBreakdown, open: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    val trend = WeightTrend.points(store.data.weightLog)
    val shown = trend.takeLast(5)
    val last = trend.lastOrNull()
    val lines = mutableListOf<String>()
    val title: String
    if (last != null) {
        title = "${last.trend.number} kg trend"
        if (abs(last.trend - last.kg) >= 0.1) lines += "Last weigh-in ${last.kg.kgText} kg"
        val change = breakdown.weightChange
        val weekly = WeightTrend.weeklyChange(trend)
        if (change != null) lines += "${WeeklyReview.signed(change)} kg over ${breakdown.days} days"
        else if (weekly != null) lines += "Trend ${WeeklyReview.signed(weekly)} kg a week"
        val goal = store.data.weightGoal
        val status = goal?.let { WeightTrend.goalStatus(it, trend) }
        if (goal != null && status != null) lines += if (status.direction == WeightTrend.GoalStatus.Direction.REACHED) "At your goal of ${goal.kg.kgText} kg"
            else "Goal ${goal.kg.kgText} kg · ${status.remaining.number} kg to go"
    } else {
        title = "Log your weight"
        lines += "See your trend, set a goal and a projected date"
    }
    val active = store.widgetEnergy[dayKey(LocalDate.now())]?.takeIf { it > 0 }
    LeanrSection("Weight") {
        Box(Modifier.fillMaxWidth().clickable(onClick = open)) {
            FeatureRowContent(Icons.Filled.MonitorWeight, title, lines) {
                if (active != null) Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text("${active.rounded().number} Cal", style = LeanrType.headline, color = c.text)
                    Text("active today", style = LeanrType.caption, color = c.secondaryText)
                }
            }
        }
        if (shown.size >= 2) WeighInChart(shown, Modifier.padding(horizontal = 12.dp), height = 150.dp)
    }
}

@Composable
private fun CaloriesSection(breakdown: ProgressBreakdown) {
    val c = Leanr.colours
    val orange = progressOrange()
    val bars = breakdown.points.map { p -> ChartBar(p.key, p.date, p.calories, if (p.calorieTarget != null && (p.calories ?: 0.0) > p.calorieTarget) orange else c.accent) }
    LeanrSection("Calories per day", footer = if (breakdown.calorieTarget == null) "Days you didn't log are left empty."
        else "The dashed line is your target. Bars over it are orange, and days you didn't log are left empty.") {
        BarChart(bars, listOfNotNull(breakdown.calorieTarget?.let { ChartRule(it, c.secondaryText, dashed = true) }),
            "Calories per day over ${breakdown.days} days", Modifier.padding(horizontal = 12.dp), height = 170.dp)
    }
}

@Composable
private fun AveragesSection(b: ProgressBreakdown) {
    LeanrSection("Daily averages", footer = "Averages count only the days you logged. Carbs, fat, fibre and sodium count only days where every food you logged lists them.") {
        ValueRow("Days logged", "${b.loggedDays} of ${b.days}")
        b.averageCalories?.let {
            ValueRow("Calories", "${it.rounded().number}${b.calorieTarget?.let { t -> " · target ${t.rounded().number}" } ?: ""}")
            if (b.calorieTarget != null) ValueRow("Days on or under target", "${b.calorieDays} of ${b.loggedDays}")
        }
        b.averageProtein?.let {
            ValueRow("Protein", "${it.rounded().number} g${b.proteinTarget?.let { t -> " · target ${t.rounded().number}" } ?: ""}")
            if (b.proteinTarget != null) ValueRow("Days on or over target", "${b.proteinDays} of ${b.loggedDays}")
        }
        listOf(Triple("Carbs", b.carbs, "g"), Triple("Fat", b.fat, "g"), Triple("Fibre", b.fibre, "g"), Triple("Sodium", b.sodium, "mg")).forEach { (title, avg, unit) ->
            avg.value?.let { ValueRow(title, "${it.rounded().number} $unit · ${avg.countedDays} days counted") }
        }
        b.water.value?.let {
            val text = if (it < 1000) "${it.rounded().toInt()} mL" else "${(it / 1000).kgText} L"
            ValueRow("Water", "$text · ${b.water.countedDays} days logged", divider = false)
        }
    }
}

@Composable
private fun MacroSection(share: ProgressBreakdown.MacroShare, complete: Boolean) {
    val c = Leanr.colours
    val parts = listOf(Triple("Protein", c.protein, share.protein), Triple("Carbs", c.carbs, share.carbs), Triple("Fat", c.fat, share.fat))
    LeanrSection("Where the calories come from", footer = if (complete) "Protein and carbs count 4 Cal a gram and fat 9. Alcohol isn't a macro, so it isn't in the split."
        else "Some foods you logged list no carbs or fat, so these shares are approximate.") {
        Row(Modifier.fillMaxWidth().padding(16.dp).height(28.dp).clip(RoundedCornerShape(6.dp))) {
            parts.forEach { (_, colour, value) -> if (value > 0) Box(Modifier.weight(value.toFloat()).height(28.dp).background(colour)) }
        }
        parts.forEachIndexed { i, (name, colour, value) ->
            LeanrRow(name, divider = i < 2, leading = { Box(Modifier.size(10.dp).clip(CircleShape).background(colour)) },
                trailing = { Text("${(value * 100).rounded().toInt()}%", style = LeanrType.body, color = c.secondaryText) })
        }
    }
}

@Composable
private fun MealTimeSection(b: ProgressBreakdown) {
    val c = Leanr.colours
    val biggest = maxOf(b.mealTimes.maxOf { it.averageCalories }, 1.0)
    LeanrSection("By meal", footer = "Average calories at each meal on the days you logged.") {
        b.mealTimes.forEach { meal ->
            Column(Modifier.padding(horizontal = 16.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row {
                    Text(meal.title, style = LeanrType.body, color = c.text, modifier = Modifier.weight(1f))
                    Text("${meal.averageCalories.rounded().number} Cal a day", style = LeanrType.body, color = c.secondaryText)
                }
                ThinBar(meal.averageCalories / biggest)
            }
        }
    }
}

@Composable
private fun ContributorsSection(b: ProgressBreakdown) {
    LeanrSection("Biggest contributors", footer = "The foods that added the most calories over these ${b.days} days.") {
        b.topFoods.forEachIndexed { i, food ->
            LeanrRow(food.name, subtitle = "${food.servings.number} ${if (food.servings == 1.0) "serving" else "servings"} · ${food.calories.rounded().number} Cal · ${food.protein.rounded().number} g protein",
                divider = i < b.topFoods.size - 1)
        }
    }
}

/** Put the Progress sections in the order you want, and hide the ones you don't use. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ArrangeSheet(orderText: String, hiddenText: String, setOrder: (String) -> Unit, setHidden: (String) -> Unit, onDismiss: () -> Unit) {
    val c = Leanr.colours
    val order = ProgressPart.order(orderText)
    val hidden = ProgressPart.hidden(hiddenText)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = c.paper) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Arrange Progress", style = LeanrType.headline, color = c.text, modifier = Modifier.weight(1f).padding(start = 4.dp))
                TextButton(onClick = onDismiss) { Text("Done", fontWeight = FontWeight.Bold, color = c.accent) }
            }
            Spacer(Modifier.height(8.dp))
            LeanrSection(footer = "Use the arrows to reorder. Tap the eye to hide a section or bring it back.") {
                order.forEachIndexed { i, part ->
                    val off = part in hidden
                    LeanrRow(part.title, divider = i < order.size - 1, titleColour = if (off) c.secondaryText else c.text,
                        leading = { Icon(symbolIcon(part.symbol), null, tint = if (off) c.tertiaryText else c.accent) },
                        trailing = {
                            IconButton(onClick = { setOrder(ProgressPart.text(order.toMutableList().apply { add(i - 1, removeAt(i)) })) }, enabled = i > 0) {
                                Icon(Icons.Filled.KeyboardArrowUp, "Move ${part.title} up", tint = if (i > 0) c.accent else c.tertiaryText)
                            }
                            IconButton(onClick = { setOrder(ProgressPart.text(order.toMutableList().apply { add(i + 1, removeAt(i)) })) }, enabled = i < order.size - 1) {
                                Icon(Icons.Filled.KeyboardArrowDown, "Move ${part.title} down", tint = if (i < order.size - 1) c.accent else c.tertiaryText)
                            }
                            IconButton(onClick = {
                                val updated = if (off) hidden - part else hidden + part
                                setHidden(ProgressPart.text(ProgressPart.entries.filter { it in updated }))
                            }) { Icon(if (off) Icons.Filled.VisibilityOff else Icons.Filled.Visibility, if (off) "Show ${part.title}" else "Hide ${part.title}", tint = c.accent) }
                        })
                }
            }
            LeanrSection {
                val changed = orderText.isNotEmpty() || hiddenText.isNotEmpty()
                LeanrRow("Reset to the usual order", divider = false, titleColour = if (changed) c.accent else c.tertiaryText,
                    onClick = if (changed) ({ setOrder(""); setHidden("") }) else null)
            }
        }
    }
}

