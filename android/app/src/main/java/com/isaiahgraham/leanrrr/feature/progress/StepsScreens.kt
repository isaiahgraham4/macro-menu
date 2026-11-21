package com.isaiahgraham.leanrrr.feature.progress

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.dayKey
import com.isaiahgraham.leanrrr.data.parseDayKey
import com.isaiahgraham.leanrrr.feature.health.HealthSync
import com.isaiahgraham.leanrrr.ui.components.LeanrRow
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.components.NumberField
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import java.time.LocalDate

// Ports of StepsView.swift and ActiveEnergyView.swift. The counts come from Health Connect through the store
// (`store.widgetSteps` / `store.widgetEnergy`, kept up to date by the Health feature), and are never saved.

@Composable
private fun Figure(title: String, value: String, modifier: Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(title, style = LeanrType.caption, color = Leanr.colours.secondaryText)
        Text(value, style = LeanrType.headline.copy(fontWeight = FontWeight.Bold), color = Leanr.colours.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** The one row that gets steps flowing: connect Health Connect from Settings. */
@Composable
private fun ConnectHealthRow() {
    val c = Leanr.colours
    LeanrRow("Connect Health Connect", divider = false, titleColour = c.accent, leading = { Icon(Icons.Filled.Favorite, null, tint = c.accent) },
        onClick = { AppServices.nav.settingsOpen = true })
}

/** Today's steps against the goal, for the day being looked at on Today. Read-only. */
@Composable
fun StepsRow(date: LocalDate) {
    if (!HealthSync.available) return
    val store = AppServices.store
    val c = Leanr.colours
    val steps = store.widgetSteps
    val count = steps[dayKey(date)] ?: 0.0
    val goal = Steps.goal(store.data)
    val detail = when {
        !HealthSync.enabled -> "Connect Health Connect to see your steps"
        steps.isEmpty() -> "No steps found in Health Connect yet"
        else -> "${Steps.text(count)} of ${Steps.text(goal)}"
    }
    Column(Modifier.fillMaxWidth()) {
        FeatureRowContent(Icons.AutoMirrored.Filled.DirectionsWalk, "Steps", listOf(detail))
        if (HealthSync.enabled && steps.isNotEmpty()) ThinBar(Steps.progress(count, goal), Modifier.padding(start = 16.dp, end = 16.dp, bottom = 12.dp))
        else if (!HealthSync.enabled) ConnectHealthRow()
    }
}

/** Calories burnt on the day being looked at on Today. Shown once Health Connect is connected. */
@Composable
fun ActiveEnergyRow(date: LocalDate) {
    if (!HealthSync.available || !HealthSync.enabled) return
    val energy = AppServices.store.widgetEnergy
    val count = energy[dayKey(date)] ?: 0.0
    val detail = when {
        energy.isEmpty() -> "No active calories found in Health Connect yet"
        count <= 0 -> "None recorded"
        else -> "${ActiveEnergy.text(count)} Cal active"
    }
    Row(Modifier.fillMaxWidth()) {
        FeatureRowContent(Icons.Filled.LocalFireDepartment, "Calories burnt", listOf(detail))
    }
}

/** Steps over the Progress range: a bar per day against the goal, the average, how often you reached it, and a tap to read any day. */
@Composable
fun StepsProgressSection(days: List<String>) {
    if (!HealthSync.available) return
    val store = AppServices.store
    val c = Leanr.colours
    var selected by remember { mutableStateOf<String?>(null) }
    val steps = store.widgetSteps
    val goal = Steps.goal(store.data)
    val summary = Steps.summary(steps, days, goal)
    val today = steps[dayKey(LocalDate.now())]
    LeanrSection("Steps", footer = "From Health Connect. Days with no steps recorded aren't counted in the average. The dashed line is your goal of ${Steps.text(goal)} and the solid line is your average. Change the goal in Settings → Targets → Steps.") {
        val average = summary.average
        if (average != null) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Figure("Today", today?.let(Steps::text) ?: "–", Modifier.weight(1f))
                Figure("Average", Steps.text(average), Modifier.weight(1f))
                Figure("Best", summary.best?.let(Steps::text) ?: "–", Modifier.weight(1f))
                Figure("At goal", "${summary.daysMet} of ${summary.countedDays}", Modifier.weight(1f))
            }
            val bars = days.mapNotNull { key ->
                val date = parseDayKey(key) ?: return@mapNotNull null
                val value = steps[key]?.takeIf { it > 0 }
                ChartBar(key, date, value, c.accent, if ((value ?: 0.0) >= goal) 1f else 0.45f)
            }
            BarChart(bars, listOf(ChartRule(goal, c.secondaryText, dashed = true, label = "Goal ${Steps.text(goal)}"), ChartRule(average, c.accent, dashed = false, width = 1.5.dp)),
                "Steps per day, average ${Steps.text(average)}, goal ${Steps.text(goal)}", Modifier.padding(horizontal = 12.dp), selected = selected, onSelect = { selected = it })
            selected?.let { key ->
                val date = parseDayKey(key); val value = steps[key]?.takeIf { it > 0 }
                if (date != null && value != null) SectionText("${weekdayDayMonth(date)}: ${Steps.text(value)} steps", colour = c.text,
                    style = LeanrType.subheadline.copy(fontWeight = FontWeight.Medium))
            }
        } else {
            LeanrRow(if (HealthSync.enabled) "No steps found in Health Connect for these days" else "Connect Health Connect to see your steps",
                titleColour = c.secondaryText, divider = !HealthSync.enabled, leading = { Icon(Icons.AutoMirrored.Filled.DirectionsWalk, null, tint = c.secondaryText) })
            if (!HealthSync.enabled) ConnectHealthRow()
        }
    }
}

/** Calories burnt over the Progress range: a bar per day with the average, and a tap to read any day. */
@Composable
fun ActiveEnergyProgressSection(days: List<String>) {
    if (!HealthSync.available || !HealthSync.enabled) return
    val store = AppServices.store
    val c = Leanr.colours
    val orange = progressOrange()
    var selected by remember { mutableStateOf<String?>(null) }
    val energy = store.widgetEnergy
    val summary = ActiveEnergy.summary(energy, days)
    val today = energy[dayKey(LocalDate.now())]?.takeIf { it > 0 }
    LeanrSection("Calories burnt", footer = "Active calories from Health Connect. Days with none recorded aren't counted in the average, shown as the solid line. Change the source in Health Connect.") {
        val average = summary.average
        if (average != null) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Figure("Today", today?.let(ActiveEnergy::text) ?: "–", Modifier.weight(1f))
                Figure("Average", ActiveEnergy.text(average), Modifier.weight(1f))
                Figure("Best", summary.best?.let(ActiveEnergy::text) ?: "–", Modifier.weight(1f))
                Figure("Total", ActiveEnergy.text(summary.total), Modifier.weight(1f))
            }
            val bars = days.mapNotNull { key -> parseDayKey(key)?.let { ChartBar(key, it, energy[key]?.takeIf { v -> v > 0 }, orange) } }
            BarChart(bars, listOf(ChartRule(average, c.secondaryText, dashed = false, width = 1.5.dp)), "Calories burnt per day, average ${ActiveEnergy.text(average)}",
                Modifier.padding(horizontal = 12.dp), selected = selected, onSelect = { selected = it })
            selected?.let { key ->
                val date = parseDayKey(key); val value = energy[key]?.takeIf { it > 0 }
                if (date != null && value != null) SectionText("${weekdayDayMonth(date)}: ${ActiveEnergy.text(value)} Cal burnt", colour = c.text,
                    style = LeanrType.subheadline.copy(fontWeight = FontWeight.Medium))
            }
        } else {
            LeanrRow("No active calories found in Health Connect for these days", divider = false, titleColour = c.secondaryText,
                leading = { Icon(Icons.Filled.LocalFireDepartment, null, tint = c.secondaryText) })
        }
    }
}

/** The daily step goal (Settings → Targets → Steps). */
@Composable
fun StepsSettingsScreen(onBack: () -> Unit) {
    val store = AppServices.store
    var goal by remember { mutableStateOf(Steps.goal(store.data)) }
    val valid = goal in Steps.GOAL_RANGE
    val changed = goal != Steps.goal(store.data)
    LeanrScreen("Steps", onBack = onBack) {
        item {
            LeanrSection(footer = "Steps come from Health Connect. Leanrrr only reads them and doesn't copy them to your backup.") {
                NumberField("Daily goal (steps)", goal, { goal = it }, divider = changed)
                if (changed) LeanrRow("Save", divider = false, titleColour = if (valid) Leanr.colours.accent else Leanr.colours.tertiaryText,
                    onClick = if (valid) ({ if (store.setStepGoal(goal.rounded())) store.notice = "Step goal saved" }) else null)
            }
        }
        if (!valid) item { LeanrSection { SectionText("Use a goal from 1,000 to 100,000 steps.") } }
    }
}

/** What calories burnt are (Settings → Targets → Calories burnt). Choosing a source belongs to Health Connect itself. */
@Composable
fun ActiveEnergySettingsScreen(onBack: () -> Unit) {
    LeanrScreen("Calories burnt", onBack = onBack) {
        if (!HealthSync.enabled) item {
            LeanrSection(footer = "Calories burnt come from Health Connect. Leanrrr only reads them and doesn't copy them to your backup.") { ConnectHealthRow() }
        }
        item {
            LeanrSection { SectionText("These are active calories, the energy you burn moving around and exercising. They don't include the calories your body uses at rest.") }
        }
    }
}
