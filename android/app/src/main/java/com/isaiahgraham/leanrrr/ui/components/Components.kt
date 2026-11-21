package com.isaiahgraham.leanrrr.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.nutrientNames
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType

// A port of Components.swift: number fields, the nutrition summary, food rows and the log target picker.

private fun Double.editText(): String = if (this == 0.0) "" else number.replace(",", "")

/** A titled number in a row, typed on the right (NumberField). */
@Composable
fun NumberField(title: String, value: Double, onValueChange: (Double) -> Unit, modifier: Modifier = Modifier, divider: Boolean = true) {
    OptionalNumberField(title, value, { onValueChange(it ?: 0.0) }, modifier, divider, placeholder = "0")
}

/** A titled number that may be left empty ("Not set"). */
@Composable
fun OptionalNumberField(title: String, value: Double?, onValueChange: (Double?) -> Unit, modifier: Modifier = Modifier, divider: Boolean = true, placeholder: String = "Not set") {
    val c = Leanr.colours
    var text by remember { mutableStateOf(value?.editText() ?: "") }
    LeanrRow(title, modifier = modifier, divider = divider, trailing = {
        Box(Modifier.widthIn(min = 60.dp, max = 120.dp), contentAlignment = Alignment.CenterEnd) {
            if (text.isEmpty()) Text(placeholder, style = LeanrType.body, color = c.tertiaryText)
            BasicTextField(
                value = text,
                onValueChange = { new -> text = new; onValueChange(new.replace(",", ".").toDoubleOrNull()) },
                textStyle = LeanrType.body.copy(color = c.text, textAlign = TextAlign.End),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                singleLine = true, cursorBrush = SolidColor(c.accent),
            )
        }
    })
}

/** Calories big, then protein, carbs and fat in their colours, an energy split bar, and other nutrients (NutritionView). */
@Composable
fun NutritionView(total: Nutrition, details: Boolean = true, modifier: Modifier = Modifier) {
    val c = Leanr.colours
    Column(modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(countingValue(total.cal).number, style = LeanrType.statHero, color = c.text)
            Spacer(Modifier.width(6.dp))
            Text("Cal", style = LeanrType.body, color = c.secondaryText, modifier = Modifier.padding(bottom = 4.dp))
        }
        Row {
            Macro("Protein", total.p, false, c.protein, Modifier.weight(1f))
            Macro("Carbs", total.c, total.missingCarbs, c.carbs, Modifier.weight(1f))
            Macro("Fat", total.f, total.missingFat, c.fat, Modifier.weight(1f))
        }
        val energy = maxOf(1.0, total.p * 4 + total.c * 4 + total.f * 9)
        Row(Modifier.fillMaxWidth().height(6.dp).clip(CircleShape), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            val pw = (total.p * 4 / energy).toFloat(); val cw = (total.c * 4 / energy).toFloat(); val fw = (total.f * 9 / energy).toFloat()
            if (pw > 0) Box(Modifier.weight(pw).height(6.dp).background(c.protein))
            if (cw > 0) Box(Modifier.weight(cw).height(6.dp).background(c.carbs))
            if (fw > 0) Box(Modifier.weight(fw).height(6.dp).background(c.fat))
            if (pw + cw + fw == 0f) Box(Modifier.weight(1f).height(6.dp).background(c.text.copy(alpha = 0.08f)))
        }
        if (total.missingCarbs || total.missingFat) Text("+ Partial total: some items don’t publish all macros.", style = LeanrType.caption, color = c.secondaryText)
        if (details) {
            Text("${total.kj.number} kJ", style = LeanrType.caption, color = c.secondaryText)
            nutrientNames.drop(4).forEach { n ->
                total.nut[n.key]?.let { value ->
                    LabeledValue(n.label, "${value.number} ${n.unit}${if (n.key in total.partial) " (partial)" else ""}")
                }
            }
            total.nut.keys.filter { key -> nutrientNames.none { it.key == key } }.sorted().forEach { key ->
                LabeledValue(key, "${(total.nut[key] ?: 0.0).number}${if (key in total.partial) " (partial)" else ""}")
            }
        }
    }
}

@Composable
private fun Macro(name: String, value: Double, partial: Boolean, colour: androidx.compose.ui.graphics.Color, modifier: Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(name, style = LeanrType.caption, color = Leanr.colours.secondaryText)
        Text("${countingValue(value).number}${if (partial) "+" else ""} g", style = LeanrType.headline, color = colour)
    }
}

/** Label on the left, value on the right (LabeledContent). */
@Composable
fun LabeledValue(label: String, value: String, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth()) {
        Text(label, style = LeanrType.subheadline, color = Leanr.colours.text, modifier = Modifier.weight(1f))
        Text(value, style = LeanrType.subheadline, color = Leanr.colours.secondaryText)
    }
}

/** A food in a list: name, restaurant and serve, calories and protein, with an optional "+" that logs one serving (FoodRow). */
@Composable
fun FoodRow(food: Food, modifier: Modifier = Modifier, quickAddLabel: String = "Log", divider: Boolean = true, onQuickAdd: (() -> Unit)? = null, onClick: (() -> Unit)? = null) {
    val c = Leanr.colours
    val store = AppServices.store
    Column {
        Row(modifier.fillMaxWidth().then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier).padding(start = 16.dp, end = 4.dp, top = 8.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f).padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Text(food.name, style = LeanrType.headline, color = c.text)
                val chain = store.chainName(food.chain)
                Text(if (food.serve.isEmpty()) chain else "$chain · ${food.serve}", style = LeanrType.caption, color = c.secondaryText)
                Text("${food.cal.number} Cal · ${food.p.number} g protein", style = LeanrType.subheadline, color = c.secondaryText)
            }
            if (onQuickAdd != null) IconButton(onClick = onQuickAdd) { Icon(Icons.Filled.AddCircle, "$quickAddLabel ${food.name}", tint = c.accent, modifier = Modifier.size(28.dp)) }
        }
        if (divider) androidx.compose.material3.HorizontalDivider(Modifier.padding(start = 16.dp), color = c.separator, thickness = 0.5.dp)
    }
}

/** Today or yesterday, and which meal: where one-tap logging goes (LogTargetPicker). */
@Composable
fun LogTargetPicker(yesterday: Boolean, onYesterday: (Boolean) -> Unit, meal: MealTime, onMeal: (MealTime) -> Unit, modifier: Modifier = Modifier) {
    val c = Leanr.colours
    var menu by remember { mutableStateOf(false) }
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        SingleChoiceSegmentedButtonRow(Modifier.weight(1f)) {
            listOf(false to "Today", true to "Yesterday").forEachIndexed { i, (value, label) ->
                SegmentedButton(selected = yesterday == value, onClick = { onYesterday(value) }, shape = SegmentedButtonDefaults.itemShape(i, 2),
                    colors = SegmentedButtonDefaults.colors(activeContainerColor = c.accent.copy(alpha = 0.16f), activeContentColor = c.text)) { Text(label, style = LeanrType.subheadline) }
            }
        }
        Box {
            TextButton(onClick = { menu = true }) { Text(meal.title, style = LeanrType.body, color = c.accent) }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                MealTime.entries.forEach { m -> DropdownMenuItem(text = { Text(m.title) }, onClick = { onMeal(m); menu = false }) }
            }
        }
    }
}

/** A small rounded card with padding, for content that isn't a list row. */
@Composable
fun Card(modifier: Modifier = Modifier, onClick: (() -> Unit)? = null, content: @Composable () -> Unit) {
    Box(modifier.fillMaxWidth().clip(androidx.compose.foundation.shape.RoundedCornerShape(16.dp)).background(Leanr.colours.card)
        .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier).padding(16.dp)) { content() }
}
