package com.isaiahgraham.leanrrr.feature.scan

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.activity.compose.BackHandler
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.feature.find.FoodSearch
import com.isaiahgraham.leanrrr.ui.components.FoodRow
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.components.SearchField
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType

// Small pieces the scanners share: padded text in a section, buttons, a spinner row, a segmented picker, a food search.

@Composable
internal fun Caption(text: String, colour: Color? = null, modifier: Modifier = Modifier) {
    Text(text, style = LeanrType.caption, color = colour ?: Leanr.colours.secondaryText,
        modifier = modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp))
}

@Composable
internal fun Body(text: String, secondary: Boolean = false, headline: Boolean = false) {
    Text(text, style = if (headline) LeanrType.headline else LeanrType.body, color = if (secondary) Leanr.colours.secondaryText else Leanr.colours.text,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp))
}

@Composable
internal fun SectionDivider() = HorizontalDivider(Modifier.padding(start = 16.dp), color = Leanr.colours.separator, thickness = 0.5.dp)

/** A filled accent button across the section (iOS `.borderedProminent`). */
@Composable
internal fun ProminentButton(title: String, enabled: Boolean = true, icon: ImageVector? = null, onClick: () -> Unit) {
    val c = Leanr.colours
    Button(onClick = onClick, enabled = enabled, shape = RoundedCornerShape(12.dp),
        colors = ButtonDefaults.buttonColors(containerColor = c.accent, contentColor = if (c.dark) Color.Black else Color.White),
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp).heightIn(min = 46.dp)) {
        if (icon != null) { Icon(icon, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)) }
        Text(title, style = LeanrType.headline)
    }
}

/** An outlined button across the section (iOS `.bordered`). */
@Composable
internal fun BorderedButton(title: String, enabled: Boolean = true, onClick: () -> Unit) {
    OutlinedButton(onClick = onClick, enabled = enabled, shape = RoundedCornerShape(12.dp),
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp)) {
        Text(title, style = LeanrType.subheadline, color = Leanr.colours.accent)
    }
}

/** A plain accent text row that acts as a button, with an optional icon (an iOS list button). */
@Composable
internal fun ActionRow(title: String, icon: ImageVector? = null, enabled: Boolean = true, divider: Boolean = false, onClick: () -> Unit) {
    val c = Leanr.colours
    Column {
        Row(Modifier.fillMaxWidth().clickable(enabled = enabled, onClick = onClick).padding(horizontal = 16.dp, vertical = 13.dp),
            verticalAlignment = Alignment.CenterVertically) {
            if (icon != null) { Icon(icon, null, tint = if (enabled) c.accent else c.tertiaryText, modifier = Modifier.size(20.dp)); Spacer(Modifier.width(12.dp)) }
            Text(title, style = LeanrType.body, color = if (enabled) c.accent else c.tertiaryText)
        }
        if (divider) SectionDivider()
    }
}

@Composable
internal fun ProgressRow(text: String) {
    Row(Modifier.fillMaxWidth().padding(24.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
        CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = Leanr.colours.accent)
        Spacer(Modifier.width(12.dp))
        Text(text, style = LeanrType.subheadline, color = Leanr.colours.secondaryText)
    }
}

/** A segmented control (iOS `.pickerStyle(.segmented)`). */
@Composable
internal fun <T> Segmented(options: List<Pair<T, String>>, selected: T, modifier: Modifier = Modifier, onSelect: (T) -> Unit) {
    val c = Leanr.colours
    SingleChoiceSegmentedButtonRow(modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)) {
        options.forEachIndexed { i, (value, label) ->
            SegmentedButton(selected = value == selected, onClick = { onSelect(value) }, shape = SegmentedButtonDefaults.itemShape(i, options.size),
                colors = SegmentedButtonDefaults.colors(activeContainerColor = c.accent.copy(alpha = 0.16f), activeContentColor = c.text)) {
                Text(label, style = LeanrType.subheadline)
            }
        }
    }
}

/** A text field on the card fill, for a row in a section. */
@Composable
internal fun FieldRow(value: String, onValueChange: (String) -> Unit, placeholder: String, number: Boolean = false, singleLine: Boolean = true,
                      trailing: (@Composable () -> Unit)? = null) {
    val c = Leanr.colours
    TextField(value = value, onValueChange = onValueChange, singleLine = singleLine,
        placeholder = { Text(placeholder, style = LeanrType.body, color = c.tertiaryText) },
        textStyle = LeanrType.body, trailingIcon = trailing,
        keyboardOptions = if (number) KeyboardOptions(keyboardType = KeyboardType.Number) else KeyboardOptions.Default,
        colors = TextFieldDefaults.colors(focusedContainerColor = c.card, unfocusedContainerColor = c.card, focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent, cursorColor = c.accent),
        modifier = Modifier.fillMaxWidth())
}

/** A square photo thumbnail frame. */
@Composable
internal fun PhotoFrame(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(modifier.padding(12.dp).background(Color.Black, RoundedCornerShape(12.dp)), contentAlignment = Alignment.Center) { content() }
}

/**
 * "Search for it instead": Leanrrr's foods by name (Find's search), picking one serving. Stands in for iOS's BrowseView picker.
 */
@Composable
internal fun ScanFoodSearch(initial: String, pickTitle: String = "Use this", onPick: (Portion) -> Unit, onDismiss: () -> Unit) {
    val store = AppServices.store
    var query by remember { mutableStateOf(initial) }
    BackHandler(onBack = onDismiss)
    val results = remember(query, store.foodsLoaded) { FoodSearch.search(query, store.searchFoods, store.searchChainNames, 40) }
    LeanrScreen("Search", onBack = onDismiss) {
        item { SearchField(query, { query = it }, "Search foods", Modifier.padding(bottom = 12.dp)) }
        if (results.isNotEmpty()) item {
            LeanrSection {
                results.forEachIndexed { i, food ->
                    FoodRow(food, quickAddLabel = pickTitle, divider = i < results.size - 1, onQuickAdd = { onPick(Portion(food = food)) }) { onPick(Portion(food = food)) }
                }
            }
        } else if (query.isNotBlank()) item { Caption("No foods match “${query.trim()}”.") }
    }
}

/** Calories still left today (Assistant.remaining), or null when there's no calorie target. */
internal fun caloriesLeft(): Double? {
    val store = AppServices.store
    val key = com.isaiahgraham.leanrrr.data.dayKey(java.time.LocalDate.now())
    val eaten = com.isaiahgraham.leanrrr.data.Nutrition((store.data.logs[key] ?: emptyList()).flatMap { it.items })
    val target = store.data.dayGoals[key] ?: store.goals
    return target.values["cal"]?.let { it - eaten.cal }
}

/** "120 g protein · 640 Cal" left today (Assistant.leftText), or null when nothing's left. */
internal fun leftText(): String? {
    val store = AppServices.store
    val key = com.isaiahgraham.leanrrr.data.dayKey(java.time.LocalDate.now())
    val eaten = com.isaiahgraham.leanrrr.data.Nutrition((store.data.logs[key] ?: emptyList()).flatMap { it.items })
    val target = store.data.dayGoals[key] ?: store.goals
    val parts = mutableListOf<String>()
    target.values["p"]?.let { it - eaten.p }?.takeIf { it > 0 }?.let { parts += "${it.roundedAway().number} g protein" }
    target.values["cal"]?.let { it - eaten.cal }?.takeIf { it > 0 }?.let { parts += "${it.roundedAway().number} Cal" }
    return if (parts.isEmpty()) null else parts.joinToString(" · ")
}
