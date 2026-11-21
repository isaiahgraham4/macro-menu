package com.isaiahgraham.leanrrr.feature.progress

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Autorenew
import androidx.compose.material.icons.filled.HourglassEmpty
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.CheckInRecord
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.ui.components.LeanrRow
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import java.time.LocalDate
import kotlin.math.abs

// A port of CheckInView.swift: how the week went, the pace you want, and a new calorie target to accept or pass on.

@Composable
fun CheckInScreen(onBack: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    var pace by remember { mutableStateOf(CheckIn.pace(store.data)) }
    val suggestion = CheckIn.suggestion(store.data, store.goals, pace)
    val week = WeeklyReview.make(store.data, store.goals, ending = LocalDate.now().minusDays(1))
    LeanrScreen("Weekly check-in", onBack = onBack) {
        if (suggestion != null) {
            item {
                LeanrSection("How it's going", footer = "Maintenance is what you've eaten less what went into weight change, from ${suggestion.loggedDays} logged days and your weight trend over the last 4 weeks. It's most accurate when you log everything.") {
                    SectionText(CheckIn.headline(suggestion), colour = c.text, style = LeanrType.headline)
                    suggestion.trendWeight?.let { ValueRow("Trend weight", "${it.number} kg") }
                    ValueRow("Days logged this week", "${week.loggedDays} of 7")
                    week.averageCalories?.let { ValueRow("Average eaten", "${it.rounded().number} Cal a day") }
                    ValueRow("Measured maintenance", "${suggestion.maintenance.rounded().number} Cal a day", divider = false)
                }
            }
            item {
                LeanrSection("Your goal") {
                    MenuPickerRow("Pace", CheckIn.paces.map { it to CheckIn.paceText(it) }, pace, { pace = it }, divider = suggestion.paceIsFast)
                    if (suggestion.paceIsFast) SectionText("That's more than 1% of your body weight a week, which is hard to keep up and can cost muscle. A slower pace is easier to stick with.",
                        colour = progressOrange(), style = LeanrType.caption)
                }
            }
            item {
                val current = store.goals.values
                LeanrSection("New daily targets", footer = when {
                    suggestion.limitedByFloor -> "Leanrrr won't suggest less than ${CheckIn.LOWEST.number} Cal a day. Choose a slower pace, or talk to a health professional about going lower."
                    suggestion.limitedByStep -> "Your pace needs a bigger change than this, so it's taken ${CheckIn.LARGEST_STEP.number} Cal at a time. Next week's check-in goes further if it's still needed."
                    else -> "Protein stays where it is. Carbs and fat change together, in the same proportions as now."
                }) {
                    ChangeRow("Calories", current["cal"], suggestion.calories, "Cal")
                    current["p"]?.let { ValueRow("Protein", "${it.rounded().number} g · unchanged") }
                    suggestion.values["c"]?.let { ChangeRow("Carbs", current["c"], it, "g") }
                    suggestion.values["f"]?.let { ChangeRow("Fat", current["f"], it, "g") }
                }
            }
            item {
                LeanrSection(footer = "Either way, the next check-in is in a week. These are estimates: talk to a doctor or Accredited Practising Dietitian before big changes, especially if you're pregnant, have a medical condition or have had an eating disorder.") {
                    Button(
                        onClick = { if (store.finishCheckIn(suggestion, accept = true)) { store.notice = "Targets updated"; onBack() } },
                        colors = ButtonDefaults.buttonColors(containerColor = c.accent, contentColor = if (c.dark) Color.Black else Color.White),
                        shape = RoundedCornerShape(14.dp), modifier = Modifier.fillMaxWidth().padding(12.dp).heightIn(min = 50.dp),
                    ) { Text("Use new targets", style = LeanrType.headline) }
                    TextButton(onClick = { if (store.finishCheckIn(suggestion, accept = false)) { store.notice = "Check-in done"; onBack() } },
                        modifier = Modifier.fillMaxWidth().padding(bottom = 6.dp)) { Text("Keep my current targets", color = c.accent) }
                }
            }
        } else {
            item {
                val ready = CheckIn.readiness(store.data)
                LeanrSection(footer = "Check-ins measure your maintenance from what you eat and how your weight moves, so they need at least 10 logged days and two weeks of weigh-ins in the last four weeks. Weigh in a few times a week, ideally at the same time of day.") {
                    LeanrRow("Not enough to go on yet", leading = { Icon(Icons.Filled.HourglassEmpty, null, tint = c.accent) })
                    if (ready.daysNeeded > 0) ValueRow("Days logged (last 4 weeks)", "${ready.loggedDays} of 10")
                    if (ready.weighInDaysNeeded > 0) ValueRow("Weigh-ins span", "${ready.weighInSpan} of 14 days", divider = false)
                }
            }
        }
        val records = (store.data.checkIns ?: emptyList()).sortedByDescending { it.date }.take(8)
        if (records.isNotEmpty()) item {
            LeanrSection("Earlier check-ins") {
                records.forEachIndexed { i, record -> LeanrRow(mediumDate(record.date), subtitle = historyText(record), divider = i < records.size - 1) }
            }
        }
    }
}

@Composable
private fun ChangeRow(title: String, old: Double?, new: Double, unit: String) {
    ValueRow(title, if (old != null && abs(old - new) >= 1) "${old.rounded().number} → ${new.rounded().number} $unit" else "${new.rounded().number} $unit",
        valueColour = Leanr.colours.text)
}

private fun historyText(record: CheckInRecord): String {
    val parts = mutableListOf<String>()
    record.weeklyChange?.let { parts += "${WeeklyReview.signed(it)} kg a week" }
    parts += if (record.accepted) {
        record.previousCalories?.let { "${it.rounded().number} → ${record.calories.rounded().number} Cal" } ?: "${record.calories.rounded().number} Cal"
    } else {
        "kept ${record.previousCalories?.let { "${it.rounded().number} Cal" } ?: "targets"}"
    }
    return parts.joinToString(" · ")
}

/** A row that opens the check-in, saying whether it's ready, when the next is, or what it still needs. */
@Composable
fun CheckInRow(open: () -> Unit) {
    val store = AppServices.store
    val data = store.data
    val status = if (CheckIn.isDue(data)) {
        val suggestion = CheckIn.suggestion(data, store.goals, CheckIn.pace(data))
        if (suggestion != null) {
            suggestion.change?.let { if (abs(it) >= 1) "Ready: a new target of ${suggestion.calories.rounded().number} Cal" else "Ready: your target still fits" } ?: "Ready to look at"
        } else {
            val ready = CheckIn.readiness(data)
            val needs = mutableListOf<String>()
            if (ready.daysNeeded > 0) needs += "${ready.daysNeeded} more logged ${if (ready.daysNeeded == 1) "day" else "days"}"
            if (ready.weighInDaysNeeded > 0) needs += "${ready.weighInDaysNeeded} more days of weigh-ins"
            if (needs.isEmpty()) "Not enough data yet" else "Needs " + needs.joinToString(" and ")
        }
    } else CheckIn.nextDate(data)?.let { "Next on ${weekdayDayMonth(it.day())}" } ?: ""
    LeanrSection {
        androidx.compose.foundation.layout.Box(Modifier.fillMaxWidth().clickable(onClick = open)) {
            FeatureRowContent(Icons.Filled.Autorenew, "Weekly check-in", listOf(status))
        }
    }
}
