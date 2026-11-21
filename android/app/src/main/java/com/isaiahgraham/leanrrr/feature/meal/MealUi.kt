package com.isaiahgraham.leanrrr.feature.meal

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.activity.compose.BackHandler
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.QuickLog
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.feature.find.FoodSearch
import com.isaiahgraham.leanrrr.ui.components.FoodRow
import com.isaiahgraham.leanrrr.ui.components.LeanrRow
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.components.SearchField
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale

// Small controls the Meal screens share: a stepper, text and toggle rows, a swipe to delete, pickers and the food picker.

/** "+ / −" amount control in steps of 0.5, from 0.5 to 50 (SwiftUI's Stepper). */
@Composable
fun QuantityStepper(value: Double, onChange: (Double) -> Unit, label: String, range: ClosedFloatingPointRange<Double> = 0.5..50.0, step: Double = 0.5) {
    val c = Leanr.colours
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text("× ${value.number}", style = LeanrType.subheadline.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Medium), color = c.text)
        Spacer(Modifier.width(4.dp))
        Row(Modifier.background(c.text.copy(alpha = 0.06f), androidx.compose.foundation.shape.RoundedCornerShape(8.dp)), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = { onChange(maxOf(range.start, value - step)) }, enabled = value - step >= range.start - 1e-9, modifier = Modifier.size(40.dp)) {
                Icon(Icons.Filled.Remove, "Less $label", tint = if (value - step >= range.start - 1e-9) c.accent else c.tertiaryText)
            }
            IconButton(onClick = { onChange(minOf(range.endInclusive, value + step)) }, enabled = value + step <= range.endInclusive + 1e-9, modifier = Modifier.size(40.dp)) {
                Icon(Icons.Filled.Add, "More $label", tint = if (value + step <= range.endInclusive + 1e-9) c.accent else c.tertiaryText)
            }
        }
    }
}

/** A text field row inside a section (TextField in a Form). */
@Composable
fun TextRow(value: String, onChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier, singleLine: Boolean = true,
            keyboard: KeyboardType = KeyboardType.Text, divider: Boolean = true, leading: ImageVector? = null, trailing: @Composable RowScope.() -> Unit = {}) {
    val c = Leanr.colours
    Column {
        Row(modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp, top = 6.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            if (leading != null) { Icon(leading, null, tint = c.secondaryText, modifier = Modifier.size(20.dp)); Spacer(Modifier.width(12.dp)) }
            Box(Modifier.weight(1f).padding(vertical = 6.dp)) {
                if (value.isEmpty()) Text(placeholder, style = LeanrType.body, color = c.tertiaryText)
                BasicTextField(value, onChange, singleLine = singleLine, textStyle = LeanrType.body.copy(color = c.text),
                    keyboardOptions = KeyboardOptions(keyboardType = keyboard), cursorBrush = SolidColor(c.accent), modifier = Modifier.fillMaxWidth())
            }
            trailing()
        }
        if (divider) HorizontalDivider(Modifier.padding(start = 16.dp), color = c.separator, thickness = 0.5.dp)
    }
}

@Composable
fun ToggleRow(title: String, checked: Boolean, onChange: (Boolean) -> Unit, enabled: Boolean = true, divider: Boolean = true, leading: ImageVector? = null) {
    val c = Leanr.colours
    LeanrRow(title, divider = divider, leading = leading?.let { { Icon(it, null, tint = c.accent) } }, trailing = {
        Switch(checked, onChange, enabled = enabled, colors = SwitchDefaults.colors(checkedTrackColor = c.accent))
    }, onClick = if (enabled) ({ onChange(!checked) }) else null)
}

/** A segmented picker on its own row. */
@Composable
fun <T> SegmentedRow(options: List<Pair<T, String>>, selected: T, onSelect: (T) -> Unit, divider: Boolean = true) {
    val c = Leanr.colours
    Column {
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
            options.forEachIndexed { i, (value, label) ->
                SegmentedButton(selected = value == selected, onClick = { onSelect(value) }, shape = SegmentedButtonDefaults.itemShape(i, options.size),
                    colors = SegmentedButtonDefaults.colors(activeContainerColor = c.accent.copy(alpha = 0.16f), activeContentColor = c.text)) {
                    Text(label, style = LeanrType.subheadline)
                }
            }
        }
        if (divider) HorizontalDivider(Modifier.padding(start = 16.dp), color = c.separator, thickness = 0.5.dp)
    }
}

/** A row with a title and a menu of choices on the right (a Picker in a Form). */
@Composable
fun <T> MenuRow(title: String, options: List<Pair<T, String>>, selected: T, onSelect: (T) -> Unit, divider: Boolean = true) {
    val c = Leanr.colours
    var open by remember { mutableStateOf(false) }
    LeanrRow(title, divider = divider, onClick = { open = true }, trailing = {
        Box {
            Text(options.firstOrNull { it.first == selected }?.second ?: "", style = LeanrType.body, color = c.accent)
            DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                options.forEach { (value, label) -> DropdownMenuItem(text = { Text(label) }, onClick = { onSelect(value); open = false }) }
            }
        }
    })
}

@Composable
fun MealTimeRow(title: String, selected: MealTime, onSelect: (MealTime) -> Unit, divider: Boolean = true) =
    MenuRow(title, MealTime.entries.map { it to it.title }, selected, onSelect, divider)

/** A button-styled row in a section: accent text, optional icon. */
@Composable
fun ActionRow(title: String, icon: ImageVector? = null, enabled: Boolean = true, destructive: Boolean = false, divider: Boolean = true, onClick: () -> Unit) {
    val c = Leanr.colours
    val colour = when { !enabled -> c.tertiaryText; destructive -> if (c.dark) Color(0xFFFF453A) else Color(0xFFD70015); else -> c.accent }
    LeanrRow(title, titleColour = colour, divider = divider, leading = icon?.let { { Icon(it, null, tint = colour) } }, onClick = if (enabled) onClick else null)
}

/** Caption text inside a section, under a row. */
@Composable
fun SectionNote(text: String, colour: Color? = null) {
    Text(text, style = LeanrType.caption, color = colour ?: Leanr.colours.secondaryText, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
}

val warningColour: Color @Composable get() = if (Leanr.colours.dark) Color(0xFFFF9F0A) else Color(0xFFC93400)

private val mediumDate = DateTimeFormatter.ofPattern("d MMM yyyy", Locale.forLanguageTag("en-AU"))
fun LocalDate.abbreviated(): String = format(mediumDate)

/** A date row that opens a calendar, up to today (DatePicker with `in: ...Date()`). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DateRow(title: String, date: LocalDate, onChange: (LocalDate) -> Unit, divider: Boolean = true) {
    var open by remember { mutableStateOf(false) }
    LeanrRow(title, divider = divider, onClick = { open = true }, trailing = { Text(date.abbreviated(), style = LeanrType.body, color = Leanr.colours.accent) })
    if (open) {
        val todayMillis = LocalDate.now().atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
        val state = rememberDatePickerState(
            initialSelectedDateMillis = date.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
            selectableDates = object : SelectableDates { override fun isSelectableDate(utcTimeMillis: Long) = utcTimeMillis <= todayMillis },
        )
        DatePickerDialog(onDismissRequest = { open = false }, confirmButton = {
            TextButton(onClick = {
                state.selectedDateMillis?.let { onChange(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()) }
                open = false
            }) { Text("Done") }
        }, dismissButton = { TextButton(onClick = { open = false }) { Text("Cancel") } }) { DatePicker(state) }
    }
}

/** Swipe left to delete, like `.onDelete` in a List. */
@Composable
fun SwipeToDelete(onDelete: () -> Unit, content: @Composable () -> Unit) {
    val state = rememberSwipeToDismissBoxState()
    val scope = rememberCoroutineScope()
    val red = if (Leanr.colours.dark) Color(0xFFFF453A) else Color(0xFFD70015)
    SwipeToDismissBox(
        state = state,
        enableDismissFromStartToEnd = false,
        onDismiss = { onDelete(); scope.launch { state.reset() } },
        backgroundContent = {
            Box(Modifier.fillMaxSize().background(red).padding(horizontal = 20.dp), contentAlignment = Alignment.CenterEnd) {
                Icon(Icons.Filled.Delete, "Delete", tint = Color.White)
            }
        },
    ) { Box(Modifier.background(Leanr.colours.card)) { content() } }
}

/** A yes-or-no question before something destructive (confirmationDialog). */
@Composable
fun ConfirmDialog(title: String, confirm: String, message: String? = null, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    val red = if (Leanr.colours.dark) Color(0xFFFF453A) else Color(0xFFD70015)
    AlertDialog(onDismissRequest = onDismiss, title = { Text(title) }, text = message?.let { { Text(it) } },
        confirmButton = { TextButton(onClick = { onConfirm(); onDismiss() }) { Text(confirm, color = red) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } })
}

/**
 * Pick a food to add (BrowseView in pick mode): search every food, or choose from My foods and recent foods. Tapping a food
 * asks how many servings; the "+" adds one.
 */
@Composable
fun FoodPickerScreen(title: String, onPick: (Portion) -> Unit, onDone: () -> Unit, quickAddLabel: String = "Add") {
    val store = AppServices.store
    val c = Leanr.colours
    var query by remember { mutableStateOf("") }
    var choosing by remember { mutableStateOf<Food?>(null) }
    BackHandler(onBack = onDone)
    val results = remember(query, store.foodsLoaded, store.data.foods, store.communityRevision) {
        if (query.isBlank()) emptyList() else FoodSearch.search(query, store.searchFoods, store.searchChainNames)
    }
    val recent = remember(store.data.logs) { QuickLog.recentFoods(store.data.logs) }
    LeanrScreen(title, onBack = onDone, showSettings = false, actions = { TextButton(onClick = onDone) { Text("Done", color = c.accent) } }) {
        item { SearchField(query, { query = it }, "Search foods and menus", Modifier.padding(bottom = 16.dp)) }
        fun section(header: String, foods: List<Food>) {
            if (foods.isEmpty()) return
            item(key = "h-$header") { Text(header.uppercase(), style = LeanrType.footnote, color = c.secondaryText, modifier = Modifier.padding(start = 16.dp, bottom = 6.dp)) }
            items(foods, key = { "$header-${it.chain}-${it.id}" }) { food ->
                Box(Modifier.background(c.card)) {
                    FoodRow(food, quickAddLabel = quickAddLabel, onQuickAdd = { onPick(Portion(food = food.copy(modifiers = null))) }, onClick = { choosing = food })
                }
            }
            item(key = "s-$header") { Spacer(Modifier.padding(bottom = 20.dp)) }
        }
        if (query.isNotBlank()) {
            if (results.isEmpty()) item { LeanrSection { LeanrRow("No foods found", "Try another word, or add it in My foods.", divider = false) } }
            section("Results", results)
        } else {
            section("My foods", store.data.foods)
            section("Recent", recent.filter { r -> store.data.foods.none { it.id == r.id } })
        }
    }
    choosing?.let { food ->
        var servings by remember(food.id) { mutableDoubleStateOf(1.0) }
        AlertDialog(onDismissRequest = { choosing = null }, title = { Text(food.name) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("${(food.cal * servings).number} Cal · ${(food.p * servings).number} g protein", style = LeanrType.subheadline, color = c.secondaryText)
                    Text(food.serve, style = LeanrType.caption, color = c.secondaryText)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Servings", style = LeanrType.body, modifier = Modifier.weight(1f))
                        QuantityStepper(servings, { servings = it }, "servings", range = 0.25..50.0, step = 0.25)
                    }
                }
            },
            confirmButton = { TextButton(onClick = { onPick(Portion(food = food.copy(modifiers = null), quantity = servings)); choosing = null }) { Text(quickAddLabel) } },
            dismissButton = { TextButton(onClick = { choosing = null }) { Text("Cancel") } })
    }
}

/** A plain clickable caption row used for links. */
@Composable
fun LinkRow(title: String, icon: ImageVector, onClick: () -> Unit) {
    val c = Leanr.colours
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = c.accent, modifier = Modifier.size(20.dp)); Spacer(Modifier.width(12.dp))
        Text(title, style = LeanrType.body, color = c.accent)
    }
}

internal val zone: ZoneId get() = ZoneId.systemDefault()
