package com.isaiahgraham.leanrrr.feature.today

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.ui.components.LeanrRow
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

// Small pieces the Today screens share.

private val AU = Locale.forLanguageTag("en-AU")
private val dayMonth = DateTimeFormatter.ofPattern("d MMM", AU)
private val weekdayDayMonth = DateTimeFormatter.ofPattern("EEEE d MMMM", AU)
private val abbreviated = DateTimeFormatter.ofPattern("d MMM yyyy", AU)
private val clock = DateTimeFormatter.ofPattern("h:mm a", AU)

/** "21 Nov". */
internal fun shortDate(date: LocalDate): String = date.format(dayMonth)
/** "Saturday 21 November". */
internal fun weekdayDate(date: LocalDate): String = date.format(weekdayDayMonth)
/** "21 Nov 2026". */
internal fun abbreviatedDate(date: LocalDate): String = date.format(abbreviated)
/** "6:30 pm". */
internal fun clockTime(time: java.time.Instant): String = time.atZone(java.time.ZoneId.systemDefault()).format(clock).lowercase()

/** A text action at the top right of a pushed screen ("Log", "Save"). */
@Composable
internal fun TopAction(title: String, enabled: Boolean = true, onClick: () -> Unit) {
    TextButton(onClick = onClick, enabled = enabled) {
        Text(title, style = LeanrType.headline, color = if (enabled) Leanr.colours.accent else Leanr.colours.tertiaryText)
    }
}

/** A text field on a section card, without a box of its own. */
@Composable
internal fun SectionTextField(value: String, onValueChange: (String) -> Unit, placeholder: String, singleLine: Boolean = true, minLines: Int = 1) {
    val c = Leanr.colours
    TextField(
        value = value, onValueChange = onValueChange, singleLine = singleLine, minLines = minLines,
        placeholder = { Text(placeholder, style = LeanrType.body, color = c.tertiaryText) },
        textStyle = LeanrType.body,
        colors = TextFieldDefaults.colors(
            focusedContainerColor = Color.Transparent, unfocusedContainerColor = Color.Transparent,
            focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent, cursorColor = c.accent,
        ),
        modifier = Modifier.fillMaxWidth(),
    )
}

/** A row that picks one of several values from a menu (Picker in a Form). */
@Composable
internal fun <T> PickerRow(title: String, value: T, options: List<T>, label: (T) -> String, divider: Boolean = true, onChange: (T) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        LeanrRow(title, divider = divider, onClick = { open = true }, trailing = {
            Text(label(value), style = LeanrType.body, color = Leanr.colours.secondaryText)
        })
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, modifier = Modifier.align(Alignment.TopEnd)) {
            options.forEach { option -> DropdownMenuItem(text = { Text(label(option)) }, onClick = { onChange(option); open = false }) }
        }
    }
}

@Composable
internal fun MealTimeRow(title: String, value: MealTime, divider: Boolean = true, onChange: (MealTime) -> Unit) =
    PickerRow(title, value, MealTime.entries, { it.title }, divider, onChange)

/** Two or more choices side by side (a segmented Picker). */
@Composable
internal fun <T> Segmented(options: List<Pair<T, String>>, selected: T, modifier: Modifier = Modifier, onChange: (T) -> Unit) {
    val c = Leanr.colours
    SingleChoiceSegmentedButtonRow(modifier.fillMaxWidth()) {
        options.forEachIndexed { i, (value, label) ->
            SegmentedButton(selected = selected == value, onClick = { onChange(value) }, shape = SegmentedButtonDefaults.itemShape(i, options.size),
                colors = SegmentedButtonDefaults.colors(activeContainerColor = c.accent.copy(alpha = 0.16f), activeContentColor = c.text)) {
                Text(label, style = LeanrType.subheadline)
            }
        }
    }
}

/** A number that may be left blank, typed on the right of a row with its unit (QuickAdd's fields). */
@Composable
internal fun BlankableNumberRow(title: String, unit: String, value: Double?, placeholder: String = "–", divider: Boolean = true, onChange: (Double?) -> Unit) {
    val c = Leanr.colours
    var text by remember { mutableStateOf(value?.number?.replace(",", "") ?: "") }
    LeanrRow(title, divider = divider, trailing = {
        Box(Modifier.widthIn(min = 60.dp, max = 100.dp), contentAlignment = Alignment.CenterEnd) {
            if (text.isEmpty()) Text(placeholder, style = LeanrType.body, color = c.tertiaryText)
            BasicTextField(
                value = text,
                onValueChange = { new -> text = new; onChange(new.replace(",", ".").toDoubleOrNull()?.takeIf { it.isFinite() }) },
                textStyle = LeanrType.body.copy(color = c.text, textAlign = TextAlign.End),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                singleLine = true, cursorBrush = SolidColor(c.accent),
            )
        }
        Text(unit, style = LeanrType.body, color = c.secondaryText, modifier = Modifier.widthIn(min = 28.dp))
    })
}

/** Plain text in a section, padded like a row. */
@Composable
internal fun SectionText(text: String, colour: Color? = null, modifier: Modifier = Modifier) {
    Text(text, style = LeanrType.body, color = colour ?: Leanr.colours.secondaryText, modifier = modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp))
}

/** A destructive confirmation (confirmationDialog). */
@Composable
internal fun ConfirmDialog(title: String, action: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss, title = { Text(title, style = LeanrType.headline) },
        confirmButton = { TextButton(onClick = { onConfirm(); onDismiss() }) { Text(action, color = Leanr.colours.over) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

/** "Couldn't log this" and the like. */
@Composable
internal fun MessageDialog(title: String, message: String, onDismiss: () -> Unit) {
    AlertDialog(onDismissRequest = onDismiss, title = { Text(title, style = LeanrType.headline) }, text = { Text(message) },
        confirmButton = { TextButton(onClick = onDismiss) { Text("OK") } })
}

/** A pushed screen's system back: closes it rather than leaving the tab. */
@Composable
internal fun BackTo(enabled: Boolean = true, onBack: () -> Unit) = BackHandler(enabled = enabled, onBack = onBack)

/** A heading row in a section: bold title with optional trailing text. */
@Composable
internal fun HeaderRow(title: String, trailing: String? = null) {
    val c = Leanr.colours
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(title, style = LeanrType.headline.copy(fontWeight = FontWeight.Medium), color = c.text)
        if (trailing != null) Text(trailing, style = LeanrType.subheadline, color = c.secondaryText)
    }
}

/** Column of rows with standard spacing, for content inside a card. */
@Composable
internal fun Padded(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) { content() }
}
