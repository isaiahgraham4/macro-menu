package com.isaiahgraham.leanrrr.feature.today

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.rememberScrollState as rememberScroll
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material.icons.outlined.RemoveCircleOutline
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.Prefs
import com.isaiahgraham.leanrrr.data.dayKey
import com.isaiahgraham.leanrrr.data.kgText
import com.isaiahgraham.leanrrr.ui.components.BottomActionBar
import com.isaiahgraham.leanrrr.ui.components.LeanrRow
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.components.NumberField
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import java.time.LocalDate
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

// A port of WaterView.swift: Today's water row, the any-amount sheet and the water settings.

/** Water's own colour (cyan), the same in every theme. */
internal val WaterCyan = Color(0xFF32ADE6)
private const val LAST_AMOUNT_KEY = "waterLastAmount"

/** Today's water: a bar against the target, chips for the usual amounts, and a sheet for any other amount. */
@Composable
fun WaterRow(date: LocalDate) {
    val store = AppServices.store
    val c = Leanr.colours
    var picking by remember { mutableStateOf(false) }
    /** The last amount added from the sheet, offered as a chip of its own. */
    var lastAmount by remember { mutableDoubleStateOf(Prefs.double(LAST_AMOUNT_KEY) ?: 0.0) }
    val total = Water.total(store.data, dayKey(date))
    val target = Water.target(store.data)
    val glass = Water.glass(store.data)
    val progress by animateFloatAsState(Water.progress(total, target).toFloat(), label = "water")

    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.WaterDrop, null, tint = WaterCyan, modifier = Modifier.width(32.dp).size(26.dp))
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("Water", style = LeanrType.headline, color = c.text)
                Text("${Water.text(total)} of ${Water.text(target)}", style = LeanrType.caption, color = c.secondaryText)
            }
            IconButton(onClick = { store.addWater(-glass, date) }, enabled = total > 0) {
                Icon(Icons.Outlined.RemoveCircleOutline, "Take off a glass of water", tint = if (total > 0) c.accent else c.tertiaryText, modifier = Modifier.size(28.dp))
            }
            IconButton(onClick = { store.addWater(glass, date) }) {
                Icon(Icons.Filled.AddCircle, "Add a glass of water, ${Water.text(glass)}", tint = c.accent, modifier = Modifier.size(28.dp))
            }
        }
        Box(Modifier.fillMaxWidth().height(6.dp).clip(CircleShape).background(WaterCyan.copy(alpha = 0.18f))) {
            Box(Modifier.fillMaxWidth(progress).fillMaxHeight().clip(CircleShape).background(WaterCyan))
        }
        // The chips scroll sideways when they don't fit.
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Water.quickAmounts(glass, if (lastAmount > 0) lastAmount else null).forEach { amount ->
                WaterChip("+${Water.text(amount)}", "Add ${Water.text(amount)} of water") { store.addWater(amount, date, undoable = true) }
            }
            WaterChip("Other", "Add another amount of water") { picking = true }
        }
        if (total >= target && target > 0) Text("Target reached.", style = LeanrType.caption, color = c.secondaryText)
    }
    if (picking) {
        WaterAmountSheet(date, start = if (lastAmount > 0) lastAmount else glass, onDismiss = { picking = false }) {
            lastAmount = it; Prefs.set(LAST_AMOUNT_KEY, it)
        }
    }
}

@Composable
private fun WaterChip(title: String, description: String, onClick: () -> Unit) {
    Text(
        title, style = LeanrType.subheadline.copy(fontWeight = FontWeight.Medium), color = WaterCyan, maxLines = 1,
        modifier = Modifier.clip(CircleShape).background(WaterCyan.copy(alpha = 0.14f)).clickable(onClickLabel = description, onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 6.dp),
    )
}

/** Any amount of water, added or taken off: a slider in 50 mL steps, a field for an exact figure, and common containers. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WaterAmountSheet(date: LocalDate, start: Double, onDismiss: () -> Unit, added: (Double) -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var amount by remember { mutableDoubleStateOf(min(Water.SINGLE_LIMIT, max(Water.PICKER_STEP, start.roundToInt().toDouble()))) }
    var takingOff by remember { mutableStateOf(false) }
    var typed by remember { mutableStateOf(amount.roundToInt().toString()) }
    val total = Water.total(store.data, dayKey(date))
    val target = Water.target(store.data)
    val valid = amount.isFinite() && amount >= 1 && amount <= Water.SINGLE_LIMIT && (!takingOff || total > 0)
    val after = min(Water.DAY_LIMIT, max(0.0, total + if (takingOff) -amount else amount))
    val dayName = if (date == LocalDate.now()) "today" else "on " + weekdayDate(date)

    fun set(value: Double) { amount = value; typed = value.roundToInt().toString() }
    fun nudge(step: Double) {
        val snapped = Math.round(amount / Water.PICKER_STEP) * Water.PICKER_STEP
        set(min(Water.SINGLE_LIMIT, max(Water.PICKER_STEP, snapped + step)))
    }
    fun save() {
        if (!valid) { store.refuse("Enter an amount from 1 to 5,000 mL"); return }
        val rounded = amount.roundToInt().toDouble()
        if (!store.addWater(if (takingOff) -rounded else rounded, date, undoable = true)) return
        if (!takingOff) added(rounded)
        onDismiss()
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheet, containerColor = c.paper) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScroll()).navigationBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = onDismiss) { Text("Cancel", color = c.accent) }
                Text(if (takingOff) "Take off water" else "Add water", style = LeanrType.headline, color = c.text, textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
                Spacer(Modifier.width(72.dp))
            }
            Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                LeanrSection {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Segmented(listOf(false to "Add", true to "Take off"), takingOff) { takingOff = it }
                        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                            Row(verticalAlignment = Alignment.Bottom) {
                                Text(if (amount >= 1000) (amount / 1000).kgText else "${amount.roundToInt()}", style = LeanrType.display(56f), color = c.text)
                                Spacer(Modifier.width(6.dp))
                                Text(if (amount >= 1000) "L" else "mL", style = LeanrType.title3, color = c.secondaryText, modifier = Modifier.padding(bottom = 12.dp))
                            }
                            Text("Then ${Water.text(after)} of ${Water.text(target)} $dayName", style = LeanrType.caption, color = c.secondaryText)
                        }
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            FilledTonalIconButton(onClick = { nudge(-Water.PICKER_STEP) }) { Icon(Icons.Filled.Remove, "50 mL less") }
                            Slider(
                                value = amount.coerceIn(Water.PICKER_RANGE).toFloat(),
                                onValueChange = { set((Math.round(it / Water.PICKER_STEP) * Water.PICKER_STEP).toDouble()) },
                                valueRange = Water.PICKER_RANGE.start.toFloat()..Water.PICKER_RANGE.endInclusive.toFloat(),
                                steps = ((Water.PICKER_RANGE.endInclusive - Water.PICKER_RANGE.start) / Water.PICKER_STEP).toInt() - 1,
                                colors = SliderDefaults.colors(thumbColor = WaterCyan, activeTrackColor = WaterCyan),
                                modifier = Modifier.weight(1f),
                            )
                            FilledTonalIconButton(onClick = { nudge(Water.PICKER_STEP) }) { Icon(Icons.Filled.Add, "50 mL more") }
                        }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("Exact amount", style = LeanrType.body, color = c.text, modifier = Modifier.weight(1f))
                            BasicTextField(
                                value = typed,
                                onValueChange = { new -> typed = new.filter { it.isDigit() }; typed.toDoubleOrNull()?.let { amount = it } },
                                textStyle = LeanrType.body.copy(color = c.text, textAlign = TextAlign.End),
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                                singleLine = true, cursorBrush = SolidColor(c.accent), modifier = Modifier.widthIn(min = 60.dp, max = 90.dp),
                            )
                            Spacer(Modifier.width(6.dp))
                            Text("mL", style = LeanrType.body, color = c.secondaryText)
                        }
                    }
                }
                LeanrSection("Containers") {
                    CONTAINERS.forEachIndexed { i, (name, size) ->
                        LeanrRow(name, divider = i < CONTAINERS.size - 1, onClick = { set(size) }, trailing = {
                            Text(Water.text(size), style = LeanrType.body, color = c.secondaryText)
                            if (amount == size) Icon(Icons.Filled.Check, null, tint = c.accent)
                        })
                    }
                }
            }
            BottomActionBar(if (takingOff) "Take off ${Water.text(amount)}" else "Add ${Water.text(amount)}", enabled = valid) { save() }
        }
    }
}

/** Everyday containers, in millilitres. */
private val CONTAINERS = listOf("Cup" to 200.0, "Can" to 375.0, "Bottle" to 600.0, "Sports bottle" to 750.0, "1 L bottle" to 1000.0, "1.5 L bottle" to 1500.0)

/** The daily water target and the size of a glass (WaterSettings). Settings opens this. */
@Composable
fun WaterSettingsScreen(onBack: () -> Unit) {
    val store = AppServices.store
    var target by remember { mutableDoubleStateOf(Water.target(store.data)) }
    var glass by remember { mutableDoubleStateOf(Water.glass(store.data)) }
    val valid = target in Water.TARGET_RANGE && glass in Water.GLASS_RANGE
    val changed = target != Water.target(store.data) || glass != Water.glass(store.data)
    BackTo(onBack = onBack)
    LeanrScreen("Water", onBack = onBack, showSettings = false) {
        item {
            LeanrSection(footer = "The plus on Today adds one glass. The chips under the bar add a bottle, a litre or the last other amount you added, and Other picks anything up to 5 L. If Health Connect is connected, each day’s total is saved to Health Connect as water.") {
                NumberField("Daily target (mL)", target, { target = it })
                NumberField("One glass (mL)", glass, { glass = it }, divider = changed)
                if (changed) {
                    TextButton(onClick = { if (store.setWater(target.roundToInt().toDouble(), glass.roundToInt().toDouble())) store.notice = "Water settings saved" },
                        enabled = valid, modifier = Modifier.padding(horizontal = 4.dp)) { Text("Save", color = if (valid) Leanr.colours.accent else Leanr.colours.tertiaryText) }
                }
            }
        }
        if (!valid) item { LeanrSection { SectionText("Use a target from 250 to 10,000 mL and a glass from 50 to 2,000 mL.") } }
    }
}
