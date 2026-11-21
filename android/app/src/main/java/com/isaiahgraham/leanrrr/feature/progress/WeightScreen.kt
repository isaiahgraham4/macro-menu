package com.isaiahgraham.leanrrr.feature.progress

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.MonitorWeight
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.AppStore
import com.isaiahgraham.leanrrr.data.WaterSip
import com.isaiahgraham.leanrrr.data.WeightEntry
import com.isaiahgraham.leanrrr.data.WeightGoal
import com.isaiahgraham.leanrrr.data.hundredth
import com.isaiahgraham.leanrrr.data.kgText
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.data.weighInMoment
import com.isaiahgraham.leanrrr.feature.health.HealthSync
import com.isaiahgraham.leanrrr.feature.today.WaterWeight
import com.isaiahgraham.leanrrr.ui.components.LeanrRow
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.components.NumberField
import com.isaiahgraham.leanrrr.ui.components.OptionalNumberField
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset
import kotlin.math.abs
import kotlin.math.ceil

// A port of WeightView.swift: the trend, a goal weight with a projected date, logging a weigh-in, and the history.

/** "+0.4", "−1.2" as WeightView writes it (not rounded to a tenth first). */
private fun weightSigned(value: Double): String = (if (value > 0) "+" else if (value < 0) "−" else "") + abs(value).number

private const val WATER_WINDOW_SECONDS = 8 * 3600L

/** Why a weigh-in has water taken off (WaterWeight.explanation). */
internal fun waterExplanation(kg: Double, at: Instant, sips: List<WaterSip>): String {
    val recent = sips.filter { it.isValid && !it.time.isAfter(at) && it.time.isAfter(at.minusSeconds(WATER_WINDOW_SECONDS)) }
    val total = recent.sumOf { it.millilitres }
    val earliest = recent.minOfOrNull { it.time } ?: at
    val hours = maxOf(1, ceil((at.epochSecond - earliest.epochSecond) / 3600.0).toInt())
    val water = if (total < 1000) "${total.rounded().toInt()} mL" else "${(total / 1000).kgText} L"
    return "About ${kg.number} kg of this is probably water you haven't passed yet, from the $water you logged " +
        "in the ${if (hours == 1) "hour" else "$hours hours"} before. Your trend uses ${kg.number} kg less. Weighing before you drink in the morning avoids this."
}

/** A row showing a date (and time) that opens pickers, never later than now (DatePicker in ...Date()). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DateTimeRow(title: String, value: Instant, onChange: (Instant) -> Unit, withTime: Boolean = true, divider: Boolean = true) {
    val zone = ZoneId.systemDefault()
    var pickingDate by remember { mutableStateOf(false) }
    var pickingTime by remember { mutableStateOf(false) }
    val local = value.atZone(zone)
    LeanrRow(title, divider = divider, trailing = {
        TextButton(onClick = { pickingDate = true }) { Text(dayMonthYear(local.toLocalDate()), style = LeanrType.body, color = Leanr.colours.accent) }
        if (withTime) TextButton(onClick = { pickingTime = true }) {
            Text(local.toLocalTime().format(java.time.format.DateTimeFormatter.ofLocalizedTime(java.time.format.FormatStyle.SHORT)), style = LeanrType.body, color = Leanr.colours.accent)
        }
    })
    if (pickingDate) {
        val todayUtc = LocalDate.now().atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
        val state = rememberDatePickerState(initialSelectedDateMillis = local.toLocalDate().atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
            selectableDates = object : SelectableDates { override fun isSelectableDate(utcTimeMillis: Long) = utcTimeMillis <= todayUtc })
        DatePickerDialog(onDismissRequest = { pickingDate = false }, confirmButton = {
            TextButton(onClick = {
                state.selectedDateMillis?.let { millis ->
                    val day = Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).toLocalDate()
                    val picked = day.atTime(local.toLocalTime()).atZone(zone).toInstant()
                    onChange(if (picked.isAfter(Instant.now())) Instant.now() else picked)
                }
                pickingDate = false
            }) { Text("Done") }
        }, dismissButton = { TextButton(onClick = { pickingDate = false }) { Text("Cancel") } }) { DatePicker(state) }
    }
    if (pickingTime) {
        val state = rememberTimePickerState(local.hour, local.minute)
        AlertDialog(onDismissRequest = { pickingTime = false }, text = { TimePicker(state) }, confirmButton = {
            TextButton(onClick = {
                val picked = local.toLocalDate().atTime(LocalTime.of(state.hour, state.minute)).atZone(zone).toInstant()
                onChange(if (picked.isAfter(Instant.now())) Instant.now() else picked)
                pickingTime = false
            }) { Text("Done") }
        }, dismissButton = { TextButton(onClick = { pickingTime = false }) { Text("Cancel") } })
    }
}

/** The weight, date and water fields with Save (the "Log weight" section). Calls `saved` after a weigh-in is logged. */
@Composable
private fun LogWeightSection(store: AppStore, saved: () -> Unit = {}) {
    var kg by remember { mutableStateOf((store.data.weightLog.maxByOrNull { it.date }?.kg ?: 0.0).hundredth) }
    var date by remember { mutableStateOf(Instant.now()) }
    val recentWater = WaterWeight.kilograms(date, store.data)
    val valid = kg in 20.0..400.0
    LeanrSection("Log weight", footer = if (recentWater > 0) waterExplanation(recentWater, date, store.data.waterSips ?: emptyList()) else null) {
        NumberField("Weight (kg)", kg, { kg = it })
        DateTimeRow("Date", date, { date = it })
        if (recentWater > 0) {
            ValueRow("Recent water", "about ${recentWater.number} kg")
            if (valid) ValueRow("Without it", "${(kg - recentWater).kgText} kg")
        }
        LeanrRow("Save weight", divider = false, titleColour = if (valid) Leanr.colours.accent else Leanr.colours.tertiaryText,
            onClick = if (valid) ({ if (store.logWeight(WeightEntry(date = date, kg = kg.hundredth))) { date = Instant.now(); saved() } }) else null)
    }
}

/** The sheet for typing a weigh-in (from Today and Progress). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WeightLogSheet(onDismiss: () -> Unit) {
    val store = AppServices.store
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = Leanr.colours.paper) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
            Text("Log weight", style = LeanrType.title, color = Leanr.colours.text, modifier = Modifier.padding(start = 4.dp, bottom = 12.dp))
            LogWeightSection(store, saved = onDismiss)
        }
    }
}

/** What the measured maintenance would mean as targets: pick a pace and use it (stands in for the target calculator). */
@Composable
private fun MaintenanceTargetsDialog(maintenance: Double, onDismiss: () -> Unit) {
    val store = AppServices.store
    var pace by remember { mutableStateOf(CheckIn.pace(store.data)) }
    val calories = ((maintenance + WeightTrend.dailyCalorieDifference(pace)).coerceIn(CheckIn.LOWEST, CheckIn.calorieRange.endInclusive) / 10).rounded() * 10
    AlertDialog(onDismissRequest = onDismiss, title = { Text("Update my targets") }, text = {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Measured maintenance is ${maintenance.rounded().number} Cal a day.", style = LeanrType.subheadline)
            MenuPickerRow("Pace", CheckIn.paces.map { it to CheckIn.paceText(it) }, pace, { pace = it }, divider = false)
            Text("New calorie target: ${calories.number} Cal. Protein stays where it is; carbs and fat change together.", style = LeanrType.subheadline,
                color = Leanr.colours.secondaryText)
        }
    }, confirmButton = {
        TextButton(onClick = {
            if (store.applyEstimatedTargets(CheckIn.values(store.goals, calories))) { store.notice = "Targets updated"; onDismiss() }
        }) { Text("Use these targets") }
    }, dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } })
}

@Composable
fun WeightScreen(onBack: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    val data = store.data
    val points = WeightTrend.points(data.weightLog)
    val shown = points.takeLast(5)
    val weekly = WeightTrend.weeklyChange(points)
    val maintenance = WeightTrend.maintenance(data.logs, points)
    var goalKG by remember { mutableStateOf(data.weightGoal?.kg) }
    var sharing by remember { mutableStateOf(false) }
    var estimating by remember { mutableStateOf(false) }
    var pace by remember { mutableStateOf(0.5) }

    LeanrScreen("Weight", onBack = onBack) {
        item {
            val last = points.lastOrNull()
            LeanrSection(footer = last?.let { "Your last five weigh-ins, joined in order. The trend figure above smooths out day-to-day swings from water and food." +
                (WeightTrend.gapText(it)?.let { gap -> " $gap" } ?: "") }) {
                if (last != null) {
                    Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.Bottom) {
                        Column(Modifier.weight(1f)) {
                            Text("Trend", style = LeanrType.caption, color = c.secondaryText)
                            Text("${com.isaiahgraham.leanrrr.ui.components.countingValue(last.trend).number} kg", style = LeanrType.statHero, color = c.text)
                        }
                        if (weekly != null) Column(horizontalAlignment = Alignment.End) {
                            Text("Per week", style = LeanrType.caption, color = c.secondaryText)
                            Text("${weightSigned(weekly)} kg", style = LeanrType.title3.copy(fontWeight = FontWeight.SemiBold), color = c.text)
                        }
                    }
                    ValueRow("Last weigh-in", "${last.kg.kgText} kg · ${relativeDay(last.date)}")
                    WeighInChart(shown, Modifier.padding(horizontal = 12.dp))
                } else {
                    EmptyState(Icons.Filled.MonitorWeight, "No weigh-ins yet", "Log your weight below. A few weigh-ins a week is enough to see your trend.")
                }
            }
        }
        item { GoalSection(points, goalKG, { goalKG = it }, pace, { pace = it }, onShare = { sharing = true }) }
        item { LogWeightSection(store) }
        item {
            if (maintenance != null) {
                LeanrSection("What your data says", footer = "From ${maintenance.loggedDays} logged days and your weight trend over the last 4 weeks. It's most accurate when you log everything you eat.") {
                    ValueRow("Measured maintenance", "${maintenance.calories.rounded().number} Cal/day")
                    LeanrRow("Update my targets from this", divider = false, titleColour = c.accent, onClick = { estimating = true })
                }
            } else if (points.size >= 2) {
                LeanrSection { SectionText("Log your food on most days and weigh in over two weeks, and Leanrrr will estimate the calories that hold your weight steady.") }
            }
        }
        item {
            if (HealthSync.enabled) {
                LeanrSection {
                    LeanrRow("Weights from Health Connect are included, and weights you log here are saved to Health Connect.", divider = false,
                        leading = { Icon(Icons.Filled.Favorite, null, tint = c.secondaryText) })
                }
            } else if (HealthSync.available) {
                LeanrSection {
                    LeanrRow("Connect Health Connect", divider = false, titleColour = c.accent, leading = { Icon(Icons.Filled.Favorite, null, tint = c.accent) },
                        onClick = { AppServices.nav.settingsOpen = true })
                }
            }
        }
        if (data.weightLog.isNotEmpty()) item {
            LeanrSection("History") {
                val history = data.weightLog.sortedByDescending { it.date }
                history.forEachIndexed { i, entry ->
                    LeanrRow(mediumDateTime(entry.date), subtitle = entry.waterKG?.let { "${entry.adjustedKG.kgText} kg less ${it.number} kg water" },
                        divider = i < history.size - 1,
                        leading = if (entry.healthID != null) ({ Icon(Icons.Filled.Favorite, "From Health Connect", tint = healthPink, modifier = Modifier.size(16.dp)) }) else null,
                        trailing = {
                            Text("${entry.kg.kgText} kg", style = LeanrType.body, color = c.text)
                            IconButton(onClick = {
                                store.change(undo = "Deleted ${entry.kg.kgText} kg weigh-in") { s -> s.copy(weights = s.weights?.filter { it.id != entry.id }) }
                            }) { Icon(Icons.Filled.Delete, "Delete", tint = c.secondaryText) }
                        })
                }
            }
        }
    }
    if (sharing) data.weighInMoment?.let { MomentShareSheet(it) { sharing = false } } ?: run { sharing = false }
    if (estimating && maintenance != null) MaintenanceTargetsDialog(maintenance.calories) { estimating = false }
}

private val healthPink = androidx.compose.ui.graphics.Color(0xFFFF2D55)

@Composable
private fun GoalSection(points: List<WeightTrend.Point>, goalKG: Double?, setGoalKG: (Double?) -> Unit, pace: Double, setPace: (Double) -> Unit, onShare: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    val goal = store.data.weightGoal
    val status = goal?.let { WeightTrend.goalStatus(it, points) }
    LeanrSection("Goal", footer = if (goal == null) "Set a goal weight to see how far off you are and when you could get there at your current pace."
        else "Projections use your trend, not a single weigh-in, so they settle as you log more. They're an estimate, not a promise.") {
        OptionalNumberField("Goal weight (kg)", goalKG, setGoalKG)
        if (goalKG != null && goalKG in 20.0..400.0 && goalKG.hundredth != goal?.kg) {
            LeanrRow(if (goal == null) "Set goal" else "Update goal", titleColour = c.accent, onClick = {
                val target = goalKG.hundredth
                val start = (points.lastOrNull()?.trend ?: store.data.weightLog.maxByOrNull { it.date }?.kg ?: target).hundredth
                val new = WeightGoal(kg = target, startKg = if (start in 20.0..400.0) start else target, set = Instant.now())
                if (store.change(undo = "Set goal weight to ${new.kg.kgText} kg") { it.copy(weightGoal = new) }) setGoalKG(new.kg)
            })
        }
        if (goal != null && status != null) {
            ValueRow("Trend weight", "${status.current.number} kg")
            when (status.direction) {
                WeightTrend.GoalStatus.Direction.REACHED -> LeanrRow("You're at your goal weight", titleColour = c.accent,
                    leading = { Icon(Icons.Filled.Verified, null, tint = c.accent) })
                else -> {
                    ValueRow("To go", "${status.remaining.number} kg to ${if (status.direction == WeightTrend.GoalStatus.Direction.LOSE) "lose" else "gain"}")
                    Column(Modifier.padding(horizontal = 16.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("${(status.progress * 100).rounded().toInt()}% of the way from ${goal.startKg.number} kg", style = LeanrType.caption, color = c.text)
                        ThinBar(status.progress)
                    }
                }
            }
            if (status.direction != WeightTrend.GoalStatus.Direction.REACHED) Projection(status, pace, setPace)
            if (store.data.weighInMoment != null) LeanrRow("Share your progress", titleColour = c.accent,
                leading = { Icon(Icons.Filled.Share, null, tint = c.accent) }, onClick = onShare)
        } else if (goal != null) {
            SectionText("Log a weigh-in to see how far off you are.")
        }
        if (goal != null) LeanrRow("Remove goal", divider = false, titleColour = c.over, onClick = {
            if (store.change(undo = "Removed weight goal") { it.copy(weightGoal = null) }) setGoalKG(null)
        })
    }
}

@Composable
private fun Projection(status: WeightTrend.GoalStatus, pace: Double, setPace: (Double) -> Unit) {
    val c = Leanr.colours
    when (status.pace) {
        WeightTrend.GoalStatus.Pace.TOWARDS -> if (status.projected != null && status.weeklyChange != null) {
            ValueRow("At your pace", dayMonthYear(status.projected))
            SectionText("About ${weeksText(status.projected)} away, at ${weightSigned(status.weeklyChange)} kg a week.", style = LeanrType.caption)
        }
        WeightTrend.GoalStatus.Pace.AWAY -> SectionText("Your trend is moving the other way (${weightSigned(status.weeklyChange ?: 0.0)} kg a week), so there's no date yet.", style = LeanrType.caption)
        WeightTrend.GoalStatus.Pace.FLAT -> SectionText("Your trend is steady, so there's no date at this pace.", style = LeanrType.caption)
        WeightTrend.GoalStatus.Pace.TOO_FAR -> SectionText("At this pace it's more than five years away.", style = LeanrType.caption)
        WeightTrend.GoalStatus.Pace.UNKNOWN -> SectionText("A week or more of weigh-ins shows your pace and a date.", style = LeanrType.caption)
    }
    // What a chosen pace would mean, whatever the trend is doing now.
    Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
        Text("If you aim for", style = LeanrType.caption, color = c.secondaryText)
        Spacer(Modifier.width(4.dp))
        Segmented(listOf(0.25, 0.5, 0.75, 1.0).map { it to "${it.kgText} kg/wk" }, pace, setPace)
    }
    WeightTrend.date(status.remaining, pace)?.let { date ->
        val calories = WeightTrend.dailyCalorieDifference(pace).rounded()
        ValueRow("At ${pace.kgText} kg a week", dayMonthYear(date))
        SectionText("About ${weeksText(date)}, ${calories.number} Cal a day ${if (status.direction == WeightTrend.GoalStatus.Direction.LOSE) "below" else "above"} what holds your weight. Slower is easier to keep up.",
            style = LeanrType.caption)
    }
}
