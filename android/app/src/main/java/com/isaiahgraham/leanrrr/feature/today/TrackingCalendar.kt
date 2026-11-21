package com.isaiahgraham.leanrrr.feature.today

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.AppData
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.dayKey
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlinx.coroutines.delay
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.time.temporal.WeekFields
import java.util.Locale

/**
 * The tracking streak (TrackingStreak in WidgetCalories.swift): days with food logged in a row up to today. One missed day
 * doesn't end a streak, as long as six logged days sit between missed ones: about one a week. Today remains available to log,
 * so it never counts against the streak.
 */
object TrackingStreak {
    const val LOGGED_DAYS_BETWEEN_MISSES = 6

    /** Days with any food logged. */
    fun trackingDays(data: AppData): Set<String> = data.logs.filter { (_, entries) -> entries.any { it.items.isNotEmpty() } }.keys

    /** Calories eaten each day. */
    fun dailyCalories(data: AppData): Map<String, Double> = data.logs.mapValues { (_, entries) -> Nutrition(entries.flatMap { it.items }).cal }

    /** The logged days in the streak running up to `date`, and the missed days it has carried. */
    fun walk(days: Set<String>, date: LocalDate): Pair<Int, Set<String>> {
        var cursor = date
        if (dayKey(cursor) !in days) cursor = cursor.minusDays(1)
        var count = 0
        val missed = mutableSetOf<String>()
        var sinceMiss = LOGGED_DAYS_BETWEEN_MISSES
        while (true) {
            if (dayKey(cursor) in days) {
                count += 1; sinceMiss += 1
            } else {
                if (sinceMiss < LOGGED_DAYS_BETWEEN_MISSES || dayKey(cursor.minusDays(1)) !in days) break
                missed += dayKey(cursor); sinceMiss = 0
            }
            cursor = cursor.minusDays(1)
        }
        return Pair(count, missed)
    }

    fun count(days: Set<String>, date: LocalDate = LocalDate.now()): Int = walk(days, date).first
    fun streak(data: AppData, date: LocalDate = LocalDate.now()): Int = count(trackingDays(data), date)
    /** Days missed that the streak up to `date` has carried. */
    fun protectedDays(days: Set<String>, date: LocalDate): Set<String> = walk(days, date).second
}

/** A month of rings against each day's calorie target, the streak, and a tap to open any day (TrackingCalendarView.swift). */
@Composable
fun TrackingCalendarScreen(selectedDate: LocalDate, onSelect: (LocalDate) -> Unit, onBack: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    var month by remember { mutableStateOf(YearMonth.from(selectedDate)) }
    var now by remember { mutableStateOf(LocalDate.now()) }
    LaunchedEffect(Unit) { while (true) { delay(60_000); now = LocalDate.now() } }
    val days = TrackingStreak.trackingDays(store.data)
    val calories = TrackingStreak.dailyCalories(store.data)
    val (streak, carried) = TrackingStreak.walk(days, now)
    val firstDay = WeekFields.of(Locale.getDefault()).firstDayOfWeek
    val weekdays = (0 until 7).map { firstDay.plus(it.toLong()) }
    val offset = (month.atDay(1).dayOfWeek.value - firstDay.value + 7) % 7

    BackTo(onBack = onBack)
    LeanrScreen("Tracking calendar", onBack = onBack, showSettings = false, actions = { TopAction("Done", onClick = onBack) }) {
        item {
            LeanrSection {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.LocalFireDepartment, null, tint = c.accent)
                        Spacer(Modifier.width(8.dp))
                        Text("$streak day${if (streak == 1) "" else "s"} in a row", style = LeanrType.roboto(22f, FontWeight.Bold), color = c.accent)
                    }
                    Text("Every day you log food counts, and staying within your target isn’t required. One missed day a week won’t end your streak.",
                        style = LeanrType.subheadline, color = c.secondaryText)
                    if (dayKey(now) !in days) {
                        Text(if (streak > 0) "Log today to continue your streak." else "Log food today to start your streak.",
                            style = LeanrType.subheadline.copy(fontWeight = FontWeight.Medium), color = c.text)
                    }
                }
            }
        }
        item {
            LeanrSection(footer = "Rings show calories eaten against that day’s target. A dot means food was logged, and a shield means a missed day that didn’t end your streak. Tap a day to view its meals.") {
                Column(Modifier.padding(horizontal = 8.dp, vertical = 8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        IconButton(onClick = { month = month.minusMonths(1) }) { Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, "Previous month", tint = c.accent) }
                        Text(month.format(DateTimeFormatter.ofPattern("MMMM yyyy", Locale.forLanguageTag("en-AU"))), style = LeanrType.headline, color = c.text,
                            textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
                        val atNow = month == YearMonth.from(now)
                        IconButton(onClick = { month = month.plusMonths(1) }, enabled = !atNow) {
                            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, "Next month", tint = if (atNow) c.tertiaryText else c.accent)
                        }
                    }
                    Row(Modifier.fillMaxWidth()) {
                        weekdays.forEach { day ->
                            Text(day.getDisplayName(TextStyle.NARROW_STANDALONE, Locale.getDefault()), style = LeanrType.caption, color = c.secondaryText,
                                textAlign = TextAlign.Center, modifier = Modifier.weight(1f).semantics { contentDescription = day.getDisplayName(TextStyle.FULL_STANDALONE, Locale.getDefault()) })
                        }
                    }
                    Spacer(Modifier.height(8.dp))
                    val cells: List<LocalDate?> = List(offset) { null } + (1..month.lengthOfMonth()).map { month.atDay(it) }
                    cells.chunked(7).forEach { week ->
                        Row(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                            (0 until 7).forEach { i ->
                                val day = week.getOrNull(i)
                                Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                                    if (day != null) DayCell(day, now, days, calories, carried) { onSelect(day); onBack() }
                                    else Spacer(Modifier.height(44.dp))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DayCell(day: LocalDate, now: LocalDate, tracked: Set<String>, calories: Map<String, Double>, carried: Set<String>, onClick: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    val key = dayKey(day)
    val logged = key in tracked
    val eaten = calories[key] ?: 0.0
    val goal = if (day == now) store.goals else store.data.dayGoals[key] ?: store.goals
    val target = goal.values["cal"]
    val progress = target?.let { (eaten / it).coerceIn(0.0, 1.0) } ?: 0.0
    val future = day.isAfter(now)
    val status = if (logged) "tracked" else if (key in carried) "missed, streak protected" else "not tracked"
    Column(
        Modifier.fillMaxWidth().heightIn(min = 44.dp).alpha(if (future) 0.3f else 1f).clip(CircleShape)
            .clickable(enabled = !future, onClick = onClick)
            .semantics { contentDescription = "${longDate(day)}, $status, ${eaten.number} calories${target?.let { " of ${it.number}" } ?: ""}" },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Box(Modifier.size(32.dp), contentAlignment = Alignment.Center) {
            Canvas(Modifier.size(32.dp)) {
                val stroke = 3.dp.toPx()
                val arc = Size(size.width - stroke, size.height - stroke)
                drawArc(c.secondaryText.copy(alpha = 0.15f), 0f, 360f, false, Offset(stroke / 2, stroke / 2), arc, style = Stroke(stroke))
                if (progress > 0) drawArc(c.accent, -90f, 360f * progress.toFloat(), false, Offset(stroke / 2, stroke / 2), arc, style = Stroke(stroke, cap = StrokeCap.Round))
            }
            Text("${day.dayOfMonth}", style = LeanrType.roboto(12f, if (day == LocalDate.now()) FontWeight.Bold else FontWeight.Normal), color = c.text)
        }
        if (key in carried) Icon(Icons.Filled.Shield, null, tint = c.accent, modifier = Modifier.size(8.dp))
        else Box(Modifier.size(4.dp).clip(CircleShape).background(if (logged) c.accent else androidx.compose.ui.graphics.Color.Transparent))
    }
}

