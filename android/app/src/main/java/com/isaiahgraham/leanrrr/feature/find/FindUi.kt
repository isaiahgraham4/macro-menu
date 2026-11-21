package com.isaiahgraham.leanrrr.feature.find

import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlin.math.sqrt

// Small pieces the Find screens share.

/** Hands text to the share sheet (ShareLink). */
fun shareText(context: Context, text: String, title: String = "Share") {
    val send = Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, text) }
    context.startActivity(Intent.createChooser(send, title).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}

/** iOS's orange, used for "short" and warnings; green is kept for "Protein target met". */
val Leanr.orange: Color @Composable get() = if (colours.dark) Color(0xFFFF9F0A) else Color(0xFFC75100)

/** A menu-style picker: the chosen option's words in the accent, a list on tap (Picker with .menu style). */
@Composable
fun <T> MenuPicker(options: List<Pair<T, String>>, selected: T, onSelect: (T) -> Unit, modifier: Modifier = Modifier) {
    val c = Leanr.colours
    var open by remember { mutableStateOf(false) }
    Box(modifier) {
        TextButton(onClick = { open = true }) {
            Text(options.firstOrNull { it.first == selected }?.second ?: "", style = LeanrType.subheadline, color = c.accent, maxLines = 1)
            Icon(Icons.Filled.ArrowDropDown, null, tint = c.accent)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            options.forEach { (value, label) ->
                DropdownMenuItem(text = { Text(label, fontWeight = if (value == selected) FontWeight.Bold else FontWeight.Normal) }, onClick = { onSelect(value); open = false })
            }
        }
    }
}

/** A row with a switch (Toggle). */
@Composable
fun SwitchRow(title: String, checked: Boolean, onChecked: (Boolean) -> Unit, subtitle: String? = null, trailingText: String? = null, divider: Boolean = true, enabled: Boolean = true) {
    val c = Leanr.colours
    Column {
        Row(Modifier.fillMaxWidth().clickable(enabled = enabled) { onChecked(!checked) }.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(title, style = LeanrType.body, color = c.text)
                if (subtitle != null) Text(subtitle, style = LeanrType.caption, color = c.secondaryText)
            }
            if (trailingText != null) Text(trailingText, style = LeanrType.subheadline, color = c.secondaryText, modifier = Modifier.padding(horizontal = 8.dp))
            Switch(checked = checked, onCheckedChange = onChecked, enabled = enabled,
                colors = SwitchDefaults.colors(checkedTrackColor = c.accent, checkedThumbColor = if (c.dark) Color.Black else Color.White))
        }
        if (divider) HorizontalDivider(Modifier.padding(start = 16.dp), color = c.separator, thickness = 0.5.dp)
    }
}

/** A count with minus and plus (Stepper). */
@Composable
fun StepperRow(title: String, value: Int, range: IntRange, onChange: (Int) -> Unit, subtitle: String? = null, divider: Boolean = true) {
    val c = Leanr.colours
    Column {
        Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp, top = 6.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(title, style = LeanrType.body, color = c.text)
                if (subtitle != null) Text(subtitle, style = LeanrType.caption, color = c.secondaryText)
            }
            IconButton(onClick = { if (value > range.first) onChange(value - 1) }, enabled = value > range.first) { Icon(Icons.Filled.Remove, "Fewer", tint = if (value > range.first) c.accent else c.tertiaryText) }
            IconButton(onClick = { if (value < range.last) onChange(value + 1) }, enabled = value < range.last) { Icon(Icons.Filled.Add, "More", tint = if (value < range.last) c.accent else c.tertiaryText) }
        }
        if (divider) HorizontalDivider(Modifier.padding(start = 16.dp), color = c.separator, thickness = 0.5.dp)
    }
}

/** A row that opens and closes the rows under it (DisclosureGroup). */
@Composable
fun DisclosureRow(title: String, expanded: Boolean, onToggle: () -> Unit, value: String? = null, divider: Boolean = true) {
    val c = Leanr.colours
    Column {
        Row(Modifier.fillMaxWidth().clickable(onClick = onToggle).padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = LeanrType.body, color = c.text, modifier = Modifier.weight(1f))
            if (value != null) Text(value, style = LeanrType.subheadline, color = c.secondaryText, maxLines = 2, textAlign = TextAlign.End, modifier = Modifier.padding(start = 8.dp).weight(1f, fill = false))
            Spacer(Modifier.width(6.dp))
            Icon(if (expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, if (expanded) "Collapse" else "Expand", tint = c.accent)
        }
        if (divider) HorizontalDivider(Modifier.padding(start = 16.dp), color = c.separator, thickness = 0.5.dp)
    }
}

/** Nothing to show, with why (ContentUnavailableView). */
@Composable
fun EmptyState(title: String, message: String, icon: ImageVector, modifier: Modifier = Modifier) {
    val c = Leanr.colours
    Column(modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 28.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(icon, null, tint = c.secondaryText, modifier = Modifier.size(40.dp))
        Text(title, style = LeanrType.title3.copy(fontWeight = FontWeight.Bold), color = c.text, textAlign = TextAlign.Center)
        Text(message, style = LeanrType.subheadline, color = c.secondaryText, textAlign = TextAlign.Center)
    }
}

/** A spinner with words, while something is worked out. */
@Composable
fun Working(text: String, modifier: Modifier = Modifier) {
    val c = Leanr.colours
    Row(modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        CircularProgressIndicator(Modifier.size(20.dp), color = c.accent, strokeWidth = 2.dp)
        Text(text, style = LeanrType.subheadline, color = c.secondaryText)
    }
}

/** A small capsule label, like "Protein target met". */
@Composable
fun Pill(text: String, colour: Color, modifier: Modifier = Modifier, background: Color = colour.copy(alpha = 0.15f)) {
    Text(text, style = LeanrType.label, color = colour, maxLines = 1,
        modifier = modifier.clip(CircleShape).background(background).padding(horizontal = 8.dp, vertical = 3.dp))
}

/** Plain text in a row inside a section. */
@Composable
fun SectionText(text: String, colour: Color? = null, modifier: Modifier = Modifier, style: androidx.compose.ui.text.TextStyle = LeanrType.body) {
    Text(text, style = style, color = colour ?: Leanr.colours.text, modifier = modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp))
}

/** A row that's a button in the accent colour, with an optional icon. */
@Composable
fun ActionRow(title: String, icon: ImageVector? = null, colour: Color? = null, enabled: Boolean = true, divider: Boolean = true, onClick: () -> Unit) {
    val c = Leanr.colours
    val tint = if (!enabled) c.tertiaryText else colour ?: c.accent
    Column {
        Row(Modifier.fillMaxWidth().clickable(enabled = enabled, onClick = onClick).padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            if (icon != null) { Icon(icon, null, tint = tint, modifier = Modifier.size(22.dp)); Spacer(Modifier.width(12.dp)) }
            Text(title, style = LeanrType.body, color = tint)
        }
        if (divider) HorizontalDivider(Modifier.padding(start = 16.dp), color = c.separator, thickness = 0.5.dp)
    }
}

/** Label on the left and value on the right, as a padded row (LabeledContent in a list). */
@Composable
fun ValueRow(label: String, value: String, divider: Boolean = true) {
    val c = Leanr.colours
    Column {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 11.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(label, style = LeanrType.body, color = c.text, modifier = Modifier.padding(end = 12.dp))
            Spacer(Modifier.weight(1f))
            Text(value, style = LeanrType.body, color = c.secondaryText, textAlign = TextAlign.End)
        }
        if (divider) HorizontalDivider(Modifier.padding(start = 16.dp), color = c.separator, thickness = 0.5.dp)
    }
}

/** Calls `onShake` when the phone is shaken, while this is on screen (no permission needed for the accelerometer). */
@Composable
fun ShakeDetector(onShake: () -> Unit) {
    val context = LocalContext.current
    val latest by rememberUpdatedState(onShake)
    DisposableEffect(Unit) {
        val manager = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        val sensor = manager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        var last = 0L
        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                val (x, y, z) = Triple(event.values[0], event.values[1], event.values[2])
                val g = sqrt(x * x + y * y + z * z) / SensorManager.GRAVITY_EARTH
                val now = System.currentTimeMillis()
                if (g > 2.6f && now - last > 1200) { last = now; latest() }
            }
            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }
        if (sensor != null) manager.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_UI)
        onDispose { manager?.unregisterListener(listener) }
    }
}

/** "150 g" when the food is weighed, otherwise "2 × 1 wrap" (or just "1 wrap" for one). */
fun amountText(portion: com.isaiahgraham.leanrrr.data.Portion): String {
    portion.food.servingWeight?.let { (grams, unit) -> return "${(grams * portion.quantity).rounded().number} $unit" }
    return if (portion.quantity == 1.0) portion.food.serve else "${portion.quantity.number} × ${portion.food.serve}"
}
