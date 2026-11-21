package com.isaiahgraham.leanrrr.feature.progress

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import androidx.compose.material.icons.filled.FormatListNumbered
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Autorenew
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Celebration
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.MilitaryTech
import androidx.compose.material.icons.filled.MonitorWeight
import androidx.compose.material.icons.filled.PieChart
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.TakeoutDining
import androidx.compose.material.icons.filled.TrackChanges
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.WbTwilight
import androidx.compose.material.icons.outlined.Calculate
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material.icons.outlined.Straighten
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.ui.components.LeanrRow
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

// Small pieces the Progress screens share: icons for SF Symbol names, labelled rows, segmented pickers, bars and dates.

/** The Material icon closest to an SF Symbol the iOS copy names. */
fun symbolIcon(name: String): ImageVector = when (name) {
    "target" -> Icons.Filled.TrackChanges
    "checkmark.seal.fill" -> Icons.Filled.Verified
    "flame.fill", "flame" -> Icons.Filled.LocalFireDepartment
    "shield.fill" -> Icons.Filled.Shield
    "fork.knife" -> Icons.Filled.Restaurant
    "figure.walk" -> Icons.AutoMirrored.Filled.DirectionsWalk
    "scalemass.fill", "scalemass" -> Icons.Filled.MonitorWeight
    "party.popper.fill" -> Icons.Filled.Celebration
    "calendar" -> Icons.Filled.CalendarMonth
    "sparkles" -> Icons.Filled.AutoAwesome
    "sunrise" -> Icons.Filled.WbTwilight
    "chart.bar" -> Icons.Filled.BarChart
    "moon" -> Icons.Filled.Bedtime
    "takeoutbag.and.cup.and.straw" -> Icons.Filled.TakeoutDining
    "exclamationmark.circle" -> Icons.Outlined.ErrorOutline
    "arrow.triangle.2.circlepath" -> Icons.Filled.Autorenew
    "lightbulb" -> Icons.Outlined.Lightbulb
    "ruler" -> Icons.Outlined.Straighten
    "rosette" -> Icons.Filled.MilitaryTech
    "equal.circle" -> Icons.Outlined.Calculate
    "chart.pie" -> Icons.Filled.PieChart
    "list.number" -> Icons.Filled.FormatListNumbered
    else -> Icons.Filled.AutoAwesome
}

/** iOS's system orange, for bars over target and calories burnt. */
@Composable
fun progressOrange(): Color = if (Leanr.colours.dark) Color(0xFFFF9F0A) else Color(0xFFFF9500)

/** A label on the left and its value on the right, as a list row (LabeledContent). */
@Composable
fun ValueRow(title: String, value: String, divider: Boolean = true, valueColour: Color? = null) {
    LeanrRow(title, divider = divider, trailing = {
        Text(value, style = LeanrType.body, color = valueColour ?: Leanr.colours.secondaryText, textAlign = TextAlign.End)
    })
}

/** Plain text inside a section, secondary by default. */
@Composable
fun SectionText(text: String, colour: Color? = null, modifier: Modifier = Modifier, style: androidx.compose.ui.text.TextStyle = LeanrType.subheadline) {
    Text(text, style = style, color = colour ?: Leanr.colours.secondaryText, modifier = modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 11.dp))
}

/** An icon, a bold headline and a line under it (the NavigationLink rows on Progress). */
@Composable
fun FeatureRowContent(icon: ImageVector, title: String, lines: List<String>, modifier: Modifier = Modifier, trailing: @Composable RowScope.() -> Unit = {}) {
    val c = Leanr.colours
    Row(modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = c.accent, modifier = Modifier.size(28.dp))
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, style = LeanrType.headline, color = c.text)
            lines.forEach { Text(it, style = LeanrType.caption, color = c.secondaryText) }
        }
        trailing()
    }
}

/** A segmented picker (a segmented `Picker` on iOS). */
@Composable
fun <T> Segmented(options: List<Pair<T, String>>, selected: T, onSelect: (T) -> Unit, modifier: Modifier = Modifier) {
    val c = Leanr.colours
    SingleChoiceSegmentedButtonRow(modifier.fillMaxWidth()) {
        options.forEachIndexed { i, (value, label) ->
            SegmentedButton(selected = selected == value, onClick = { onSelect(value) }, shape = SegmentedButtonDefaults.itemShape(i, options.size),
                icon = {}, colors = SegmentedButtonDefaults.colors(activeContainerColor = c.accent.copy(alpha = 0.16f), activeContentColor = c.text)) {
                Text(label, style = LeanrType.footnote, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

/** A row with a menu of choices on the right (a menu `Picker` on iOS). */
@Composable
fun <T> MenuPickerRow(title: String, options: List<Pair<T, String>>, selected: T, onSelect: (T) -> Unit, divider: Boolean = true) {
    var open by remember { mutableStateOf(false) }
    LeanrRow(title, divider = divider, trailing = {
        Box {
            TextButton(onClick = { open = true }) { Text(options.firstOrNull { it.first == selected }?.second ?: "", style = LeanrType.body, color = Leanr.colours.accent) }
            DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                options.forEach { (value, label) -> DropdownMenuItem(text = { Text(label) }, onClick = { onSelect(value); open = false }) }
            }
        }
    })
}

/** A thin rounded progress bar in the accent (ProgressView). */
@Composable
fun ThinBar(fraction: Double, modifier: Modifier = Modifier, colour: Color = Leanr.colours.accent, track: Color = Leanr.colours.text.copy(alpha = 0.1f), height: Int = 6) {
    Box(modifier.fillMaxWidth().height(height.dp).clip(CircleShape).background(track)) {
        Box(Modifier.fillMaxWidth(fraction.coerceIn(0.0, 1.0).toFloat()).fillMaxHeight().clip(CircleShape).background(colour))
    }
}

/** ContentUnavailableView: an icon, a title and a description, centred in a section. */
@Composable
fun EmptyState(icon: ImageVector, title: String, description: String) {
    val c = Leanr.colours
    Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 28.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(icon, null, tint = c.secondaryText, modifier = Modifier.size(40.dp))
        Text(title, style = LeanrType.title3.copy(fontWeight = FontWeight.Bold), color = c.text, textAlign = TextAlign.Center)
        Text(description, style = LeanrType.subheadline, color = c.secondaryText, textAlign = TextAlign.Center)
    }
}

private fun pattern(p: String) = DateTimeFormatter.ofPattern(p, Locale.getDefault())
/** "14 Oct 2026". */
fun dayMonthYear(date: LocalDate): String = date.format(pattern("d MMM yyyy"))
/** "Monday 14 Oct". */
fun weekdayDayMonth(date: LocalDate): String = date.format(pattern("EEEE d MMM"))
/** The date as a medium date: "14 Oct 2026". */
fun mediumDate(instant: Instant): String = instant.atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(Locale.getDefault()))
/** Date and time: "14 Oct 2026, 7:02 am". */
fun mediumDateTime(instant: Instant): String = instant.atZone(ZoneId.systemDefault())
    .format(DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).withLocale(Locale.getDefault()))
/** The long date for a story card's footnote: "21 November 2026". */
fun longDate(date: LocalDate): String = date.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.LONG).withLocale(Locale.getDefault()))

/** "today", "yesterday" or "14 Oct". */
fun relativeDay(date: LocalDate): String {
    val today = LocalDate.now()
    return when (date) { today -> "today"; today.minusDays(1) -> "yesterday"; else -> shortDay(date) }
}

/** "3 days", "5 weeks", "4 months": how long until a date. */
fun weeksText(until: LocalDate): String {
    val days = maxOf(0, daysBetween(LocalDate.now(), until))
    if (days < 14) return if (days == 1) "1 day" else "$days days"
    if (days < 70) return "${(days / 7.0).rounded().toInt()} weeks"
    return "${(days / 30.4).rounded().toInt()} months"
}

/** "+0.4", "−1.2", "0". */
fun signed(value: Double): String = WeeklyReview.signed(value)
