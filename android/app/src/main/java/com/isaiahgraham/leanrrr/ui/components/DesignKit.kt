package com.isaiahgraham.leanrrr.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlin.math.abs

// A port of DesignKit.swift: the calorie ring, target bars, chips, pills, stat fields, action tiles and the bottom action bar.

/** A number that counts to its new value when it changes (CountingNumber in Motion.swift). */
@Composable
fun countingValue(target: Double): Double {
    val animated by animateFloatAsState(target.toFloat(), tween(450), label = "counting")
    return animated.toDouble()
}

/** Calories eaten against a target, with what's left in the middle. */
@Composable
fun CalorieRing(eaten: Double, target: Double, modifier: Modifier = Modifier) {
    val c = Leanr.colours
    val over = eaten > target
    val progress by animateFloatAsState((eaten / maxOf(target, 1.0)).coerceIn(0.0, 1.0).toFloat(), tween(450), label = "ring")
    val left = countingValue(abs(target - eaten))
    Box(modifier.size(128.dp).semantics { contentDescription = "${eaten.number} of ${target.number} calories" }, contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(128.dp)) {
            val stroke = 13.dp.toPx()
            val inset = stroke / 2
            val arcSize = Size(size.width - stroke, size.height - stroke)
            // The track is a pale wash of the accent, so an empty day still reads as the brand rather than grey.
            drawArc(c.accent.copy(alpha = 0.14f), 0f, 360f, false, Offset(inset, inset), arcSize, style = Stroke(stroke))
            drawArc(if (over) c.over else c.accent, -90f, 360f * progress, false, Offset(inset, inset), arcSize, style = Stroke(stroke, cap = StrokeCap.Round))
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(left.number, style = LeanrType.stat, color = c.text, maxLines = 1)
            Text(if (over) "Cal over" else "Cal left", style = LeanrType.caption, color = c.secondaryText, maxLines = 1)
        }
    }
}

/** One nutrient's progress toward its target, as a label, figures and a thin bar. */
@Composable
fun TargetBar(label: String, value: Double, target: Double, unit: String, minimum: Boolean, colour: Color, modifier: Modifier = Modifier) {
    val c = Leanr.colours
    val over = !minimum && value > target
    val shown = countingValue(value)
    val fraction by animateFloatAsState((value / maxOf(target, 0.001)).coerceIn(0.0, 1.0).toFloat(), tween(450), label = "bar")
    Column(modifier.fillMaxWidth().semantics { contentDescription = "$label: ${value.number} of ${target.number} $unit" }, verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(label, style = LeanrType.label, color = c.secondaryText)
            Spacer(Modifier.weight(1f).width(4.dp))
            Text("${shown.number} / ${target.number} $unit", style = LeanrType.caption, color = if (over) c.over else c.text)
        }
        Box(Modifier.fillMaxWidth().height(6.dp).clip(CircleShape).background(colour.copy(alpha = 0.16f))) {
            Box(Modifier.fillMaxWidth(fraction).fillMaxHeight().clip(CircleShape).background(colour))
        }
    }
}

/** A capsule filter button; filled with the app colour when selected. */
@Composable
fun Chip(title: String, selected: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val c = Leanr.colours
    Text(
        title, style = LeanrType.subheadline.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Medium), maxLines = 1,
        color = if (selected) (if (c.dark) Color.Black else Color.White) else c.text,
        modifier = modifier.clip(CircleShape).background(if (selected) c.accent else c.card).clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 8.dp),
    )
}

/** A capsule shortcut: an accent icon and a label, on the cell fill. They sit in a [ChipRow]. */
@Composable
fun ActionPill(title: String, icon: ImageVector, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val c = Leanr.colours
    Row(
        modifier.clip(CircleShape).background(c.card).clickable(onClick = onClick).padding(start = 14.dp, end = 16.dp, top = 11.dp, bottom = 11.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        Icon(icon, null, tint = c.accent, modifier = Modifier.size(18.dp))
        Text(title, style = LeanrType.subheadline.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Medium), color = c.text, maxLines = 1)
    }
}

/** A full-width, horizontally scrolling row of chips, placed directly on the list background. */
@Composable
fun ChipRow(modifier: Modifier = Modifier, content: @Composable RowScope.() -> Unit) {
    Row(modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), content = content)
}

/** A number you can type, shown large on its own tile so two can sit side by side. */
@Composable
fun StatField(title: String, unit: String, value: Double, onValueChange: (Double) -> Unit, modifier: Modifier = Modifier) {
    val c = Leanr.colours
    var text by remember { mutableStateOf(if (value == 0.0) "" else value.number.replace(",", "")) }
    Column(modifier.clip(RoundedCornerShape(14.dp)).background(c.text.copy(alpha = 0.06f)).padding(12.dp)) {
        Text(title, style = LeanrType.caption, color = c.secondaryText)
        Row(verticalAlignment = Alignment.Bottom) {
            androidx.compose.foundation.text.BasicTextField(
                value = text,
                onValueChange = { new -> text = new; new.replace(",", ".").toDoubleOrNull()?.let(onValueChange) },
                textStyle = LeanrType.stat.copy(color = c.text),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                singleLine = true,
                cursorBrush = androidx.compose.ui.graphics.SolidColor(c.accent),
                modifier = Modifier.weight(1f),
            )
            Text(unit, style = LeanrType.subheadline, color = c.secondaryText)
        }
    }
}

/** An action tile: an icon over a short label, on the card fill. Several sit in a [TileRow]. */
@Composable
fun ActionTile(title: String, icon: ImageVector, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val c = Leanr.colours
    Column(
        modifier.heightIn(min = 78.dp).clip(RoundedCornerShape(16.dp)).background(c.card).clickable(onClick = onClick).padding(horizontal = 4.dp, vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically),
    ) {
        Icon(icon, null, tint = c.accent, modifier = Modifier.size(24.dp))
        Text(title, style = LeanrType.label, color = c.text, textAlign = TextAlign.Center, maxLines = 2)
    }
}

/** A row of action tiles of equal width and height, placed directly on the list background. */
@Composable
fun TileRow(modifier: Modifier = Modifier, content: @Composable RowScope.() -> Unit) {
    Row(modifier.fillMaxWidth().height(IntrinsicSize.Max).padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), content = content)
}

/** A full-width prominent button pinned above the tab bar. */
@Composable
fun BottomActionBar(title: String, enabled: Boolean = true, icon: ImageVector? = null, onClick: () -> Unit) {
    val c = Leanr.colours
    Button(
        onClick = onClick, enabled = enabled,
        colors = ButtonDefaults.buttonColors(containerColor = c.accent, contentColor = if (c.dark) Color.Black else Color.White),
        shape = RoundedCornerShape(14.dp),
        modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 10.dp).heightIn(min = 50.dp),
    ) {
        if (icon != null) { Icon(icon, null); Spacer(Modifier.width(8.dp)) }
        Text(title, style = LeanrType.headline)
    }
}

/** A plain search field on the card fill. */
@Composable
fun SearchField(value: String, onValueChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier) {
    val c = Leanr.colours
    TextField(
        value = value, onValueChange = onValueChange, singleLine = true,
        placeholder = { Text(placeholder, style = LeanrType.body, color = c.secondaryText) },
        leadingIcon = { Icon(androidx.compose.material.icons.Icons.Filled.Search, null, tint = c.secondaryText) },
        textStyle = LeanrType.body,
        shape = RoundedCornerShape(12.dp),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = c.card, unfocusedContainerColor = c.card, focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent, cursorColor = c.accent,
        ),
        modifier = modifier.fillMaxWidth(),
    )
}

/** "28.7 g" with a "+" when only some items list it, like the iOS figures. */
fun grams(value: Double, partial: Boolean = false, unit: String = "g") = "${value.number}${if (partial) "+" else ""} $unit"
