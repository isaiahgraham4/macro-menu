package com.isaiahgraham.leanrrr.feature.settings

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Colorize
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.R
import com.isaiahgraham.leanrrr.billing.Premium
import com.isaiahgraham.leanrrr.data.Prefs
import com.isaiahgraham.leanrrr.data.rememberStringPref
import com.isaiahgraham.leanrrr.ui.theme.AppAccent
import com.isaiahgraham.leanrrr.ui.theme.AppIconTheme
import com.isaiahgraham.leanrrr.ui.theme.ColourPack
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import com.isaiahgraham.leanrrr.ui.theme.MacroColours
import com.isaiahgraham.leanrrr.ui.theme.PaperTint
import com.isaiahgraham.leanrrr.ui.theme.ThemeColour

/**
 * Launcher icons. Each theme is an activity-alias of MainActivity named `.MainActivity<Theme>` ("Default" for the standard
 * icon), so switching enables one alias and disables the rest (setAlternateIconName on iOS).
 */
object AppIcons {
    fun aliasName(theme: AppIconTheme): String = "MainActivity" + if (theme == AppIconTheme.STANDARD) "Default" else theme.raw.replaceFirstChar { it.uppercase() }

    fun preview(theme: AppIconTheme): Int = when (theme) {
        AppIconTheme.STANDARD -> R.drawable.icon_preview_default
        AppIconTheme.BERRY -> R.drawable.icon_preview_berry
        AppIconTheme.CREAM -> R.drawable.icon_preview_cream
        AppIconTheme.CRIMSON -> R.drawable.icon_preview_crimson
        AppIconTheme.FOREST -> R.drawable.icon_preview_forest
        AppIconTheme.LATTE -> R.drawable.icon_preview_latte
        AppIconTheme.MIDNIGHT -> R.drawable.icon_preview_midnight
        AppIconTheme.OCEAN -> R.drawable.icon_preview_ocean
        AppIconTheme.PLUM -> R.drawable.icon_preview_plum
        AppIconTheme.SAGE -> R.drawable.icon_preview_sage
        AppIconTheme.SLATE -> R.drawable.icon_preview_slate
        AppIconTheme.TERRACOTTA -> R.drawable.icon_preview_terracotta
        AppIconTheme.WARM -> R.drawable.icon_preview_warm
    }

    /** Switches the launcher icon. The new alias is enabled before the others are turned off, so the app never leaves the launcher. */
    fun select(context: Context, theme: AppIconTheme) {
        Prefs.set(AppIconTheme.STORAGE_KEY, theme.raw)
        val pm = context.packageManager
        fun component(t: AppIconTheme) = ComponentName(context.packageName, "${context.packageName}.${aliasName(t)}")
        val chosen = component(theme)
        val ok = runCatching {
            pm.setComponentEnabledSetting(chosen, PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
        }.isSuccess
        if (!ok) return
        AppIconTheme.entries.filter { it != theme }.forEach { other ->
            runCatching { pm.setComponentEnabledSetting(component(other), PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP) }
        }
    }

    /** Puts the standard icon back when Even Leanrrr has ended (the colours fall back by themselves). */
    fun resetIfLocked(context: Context) {
        val current = AppIconTheme.fromRaw(Prefs.string(AppIconTheme.STORAGE_KEY))
        if (!Premium.isUnlocked && current != AppIconTheme.STANDARD) select(context, AppIconTheme.STANDARD)
    }
}

/** A short note when a custom colour is shown a shade darker or lighter than picked, so text stays readable. */
internal fun lightWarning(raw: String): String? =
    if (ThemeColour.isAdjusted(raw)) "Leanrrr shows it a shade darker or lighter where needed so text stays easy to read." else null

/** One accent swatch: a filled circle with a tick when chosen and a lock when locked, ringed when chosen. */
@Composable
internal fun AccentSwatch(colour: Color, chosen: Boolean, locked: Boolean, label: String, onClick: () -> Unit) {
    Box(
        Modifier.size(46.dp).semantics { contentDescription = label; selected = chosen }.clip(CircleShape).clickable(onClick = onClick)
            .border(2.dp, if (chosen) colour else Color.Transparent, CircleShape).padding(5.dp).clip(CircleShape).background(colour),
        contentAlignment = Alignment.Center,
    ) {
        if (chosen) Icon(Icons.Filled.Check, null, tint = Color.White, modifier = Modifier.size(20.dp))
        else if (locked) Icon(Icons.Filled.Lock, null, tint = Color.White, modifier = Modifier.size(13.dp))
    }
}

/** A grid of swatches, six to a row like the iOS LazyVGrid. */
@Composable
internal fun SwatchGrid(columns: Int = 6, count: Int, cell: @Composable (Int) -> Unit) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        (0 until count).chunked(columns).forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                row.forEach { i -> Box(Modifier.weight(1f), contentAlignment = Alignment.Center) { cell(i) } }
                repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

/**
 * A background tint as a tiny screen: the light shade with the app's dot grid and two cards, and the dark shade as a band on
 * the right with its own cards. `compact` draws only the two shades, for the colour pack rows.
 */
@Composable
internal fun PaperSwatch(tint: PaperTint, modifier: Modifier, compact: Boolean = false) {
    val c = Leanr.colours
    val radius = if (compact) 3.dp else 10.dp
    Canvas(modifier.clip(RoundedCornerShape(radius)).border(0.5.dp, c.separator, RoundedCornerShape(radius))) {
        val split = Math.round(size.width * if (compact) 0.62f else 0.64f).toFloat()
        drawRect(tint.color(false), size = Size(split, size.height))
        drawRect(tint.color(true), topLeft = Offset(split, 0f), size = Size(size.width - split, size.height))
        if (compact) return@Canvas
        val step = 6.dp.toPx(); val dot = 0.55.dp.toPx()
        fun dots(x0: Float, x1: Float, ink: Color) {
            var x = x0 + step / 2
            while (x < x1) { var y = step / 2; while (y < size.height) { drawCircle(ink, dot, Offset(x, y)); y += step }; x += step }
        }
        dots(0f, split, Color(0.40f, 0.31f, 0.20f, 0.22f))
        dots(split, size.width, Color.White.copy(alpha = 0.14f))
        fun cards(x0: Float, width: Float, card: Color, line: Color, second: Boolean) {
            val inset = (if (width > 40.dp.toPx()) 7.dp else 5.dp).toPx()
            val w = width - inset * 2
            val top = Math.round(size.height * 0.16f).toFloat(); val h = Math.round(size.height * 0.3f).toFloat()
            drawRoundRect(card, Offset(x0 + inset, top), Size(w, h), CornerRadius(3.5.dp.toPx()))
            drawRoundRect(line, Offset(x0 + inset + 4.dp.toPx(), top + h / 2 - 1.25.dp.toPx()), Size(w * 0.5f, 2.5.dp.toPx()), CornerRadius(1.25.dp.toPx()))
            if (second) drawRoundRect(card, Offset(x0 + inset, top + h + 4.dp.toPx()), Size(Math.round(w * 0.62f).toFloat(), Math.round(size.height * 0.18f).toFloat()),
                CornerRadius(3.dp.toPx()))
        }
        cards(0f, split, Color.White, Color.Black.copy(alpha = 0.12f), true)
        cards(split, size.width - split, Color(0xFF1C1C1E), Color.White.copy(alpha = 0.16f), false)
    }
}

/** A tile with a corner lock badge and a ring when chosen: used for backgrounds and app icons. */
@Composable
internal fun ChoiceTile(name: String, chosen: Boolean, locked: Boolean, width: Dp, height: Dp, radius: Dp, label: String, onClick: () -> Unit,
                        content: @Composable (Modifier) -> Unit) {
    val c = Leanr.colours
    Column(Modifier.semantics { contentDescription = label; selected = chosen }.clickable(onClick = onClick).padding(4.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(Modifier.size(width, height).border(3.dp, if (chosen) c.accent else Color.Transparent, RoundedCornerShape(radius + 2.dp)).padding(3.dp)) {
            content(Modifier.size(width - 6.dp, height - 6.dp))
            if (locked) Box(Modifier.align(Alignment.BottomEnd).padding(4.dp).size(22.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.6f)),
                contentAlignment = Alignment.Center) { Icon(Icons.Filled.Lock, null, tint = Color.White, modifier = Modifier.size(11.dp)) }
        }
        Text(name, style = LeanrType.caption.copy(fontWeight = FontWeight.Medium), color = c.text)
    }
}

/** One pack in Settings: its icon, name, a line about it, and swatches for the app colour, the three macros and the background. */
@Composable
internal fun ColourPackRow(pack: ColourPack, selected: Boolean, locked: Boolean, divider: Boolean, onClick: () -> Unit) {
    val c = Leanr.colours
    Column {
        Row(Modifier.fillMaxWidth().semantics { contentDescription = if (locked) "${pack.name} colour pack, needs Even Leanrrr" else "${pack.name} colour pack"; this.selected = selected }
            .clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Image(painterResource(AppIcons.preview(pack.icon)), null, contentScale = ContentScale.Crop,
                modifier = Modifier.size(44.dp).clip(RoundedCornerShape(10.dp)).border(0.5.dp, c.separator, RoundedCornerShape(10.dp)))
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(pack.name, style = LeanrType.body.copy(fontWeight = FontWeight.Medium), color = c.text)
                Text(pack.detail, style = LeanrType.caption, color = c.secondaryText, maxLines = 2)
                Row(Modifier.padding(top = 3.dp), horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                    // The app colour is a short bar, the macros are dots, so the two kinds read apart.
                    Box(Modifier.size(22.dp, 10.dp).clip(CircleShape).background(pack.accent.color(c.dark)))
                    listOf(pack.protein, pack.carbs, pack.fat).forEach { Box(Modifier.size(10.dp).clip(CircleShape).background(it.color(c.dark))) }
                    Spacer(Modifier.width(3.dp))
                    PaperSwatch(pack.paper, Modifier.size(18.dp, 12.dp), compact = true)
                }
            }
            Spacer(Modifier.width(8.dp))
            if (selected) Icon(Icons.Filled.Check, null, tint = c.accent)
            else if (locked) Icon(Icons.Filled.Lock, null, tint = c.secondaryText, modifier = Modifier.size(14.dp))
        }
        if (divider) androidx.compose.material3.HorizontalDivider(Modifier.padding(start = 72.dp), color = c.separator, thickness = 0.5.dp)
    }
}

/**
 * Any colour, stored as "#RRGGBB" next to the preset swatches (the system ColorPicker on iOS; hue, saturation and brightness
 * sliders and a hex field here). Locked rows open Even Leanrrr when `onLocked` is given; otherwise they sit greyed out.
 */
@Composable
internal fun CustomColourRow(title: String, raw: String, onChange: (String) -> Unit, fallback: AppAccent, onLocked: (() -> Unit)?, divider: Boolean = false) {
    val c = Leanr.colours
    val isCustom = ThemeColour.isCustom(raw)
    var picking by remember { mutableStateOf(false) }
    if (!Premium.isUnlocked) {
        if (onLocked != null) LinkRow(title, Icons.Filled.Lock, divider = divider, chevron = false, onClick = onLocked)
        else LinkRow(title, Icons.Filled.Colorize, divider = divider, chevron = false, titleColour = c.tertiaryText, onClick = {})
        return
    }
    LinkRow(title, if (isCustom) Icons.Filled.CheckCircle else Icons.Filled.Colorize, divider = divider, chevron = false,
        subtitle = if (isCustom) (if (ThemeColour.isAdjusted(raw)) "$raw · adjusted to stay readable" else raw) else null,
        onClick = { picking = true })
    if (picking) {
        // The picked value itself, not the readable shade, so nudging it starts from what was chosen.
        val start = ThemeColour.rgb(raw)?.color() ?: fallback.color(false)
        ColourPickerDialog(title, start, onDismiss = { picking = false }, onPick = { onChange(ThemeColour.hex(it)); picking = false })
    }
}

@Composable
private fun ColourPickerDialog(title: String, start: Color, onDismiss: () -> Unit, onPick: (Color) -> Unit) {
    val c = Leanr.colours
    val hsv = remember { FloatArray(3).also { android.graphics.Color.colorToHSV(android.graphics.Color.rgb((start.red * 255).toInt(), (start.green * 255).toInt(), (start.blue * 255).toInt()), it) } }
    var hue by remember { mutableFloatStateOf(hsv[0]) }
    var saturation by remember { mutableFloatStateOf(hsv[1]) }
    var brightness by remember { mutableFloatStateOf(hsv[2]) }
    val colour = Color(android.graphics.Color.HSVToColor(floatArrayOf(hue, saturation, brightness)))
    var hexText by remember(colour) { mutableStateOf(ThemeColour.hex(colour)) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title, style = LeanrType.headline) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.fillMaxWidth().height(56.dp).clip(RoundedCornerShape(12.dp)).background(colour))
                Text("Hue", style = LeanrType.caption, color = c.secondaryText)
                Slider(hue, { hue = it }, valueRange = 0f..360f, colors = SliderDefaults.colors(thumbColor = colour, activeTrackColor = colour))
                Text("Saturation", style = LeanrType.caption, color = c.secondaryText)
                Slider(saturation, { saturation = it }, colors = SliderDefaults.colors(thumbColor = colour, activeTrackColor = colour))
                Text("Brightness", style = LeanrType.caption, color = c.secondaryText)
                Slider(brightness, { brightness = it }, colors = SliderDefaults.colors(thumbColor = colour, activeTrackColor = colour))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Hex", style = LeanrType.body, color = c.text, modifier = Modifier.weight(1f))
                    BasicTextField(hexText, { text ->
                        hexText = text.uppercase()
                        ThemeColour.rgb(hexText)?.let { rgb ->
                            val out = FloatArray(3)
                            android.graphics.Color.colorToHSV(android.graphics.Color.rgb((rgb.r * 255).toInt(), (rgb.g * 255).toInt(), (rgb.b * 255).toInt()), out)
                            hue = out[0]; saturation = out[1]; brightness = out[2]
                        }
                    }, singleLine = true, textStyle = LeanrType.body.copy(color = c.text, fontFamily = FontFamily.Monospace), cursorBrush = SolidColor(c.accent),
                        modifier = Modifier.width(96.dp))
                }
            }
        },
        confirmButton = { TextButton(onClick = { onPick(colour) }) { Text("Use colour") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

/** Separate colours for protein, carbs and fat in Leanrrr and its widgets (MacroColourSettings). */
@Composable
internal fun MacroColourScreen(onBack: () -> Unit) {
    var protein by rememberStringPref(MacroColours.PROTEIN_KEY, "blue")
    var carbs by rememberStringPref(MacroColours.CARBS_KEY, "orange")
    var fat by rememberStringPref(MacroColours.FAT_KEY, "red")
    val unlocked = Premium.isUnlocked
    SettingsPage("Target colours", onBack) {
        if (!unlocked) item { SettingsSection { PremiumPromptRow("Separate macro colours come with Even Leanrrr.") } }
        item { MacroSwatches("Protein", "p", protein, { protein = it }, unlocked) }
        item { MacroSwatches("Carbs", "c", carbs, { carbs = it }, unlocked) }
        item { MacroSwatches("Fat", "f", fat, { fat = it }, unlocked) }
        item {
            SettingsSection(footerText = "Choose separate colours for your macros in Leanrrr and its widgets.") {
                ButtonRow("Reset to default colours", divider = false, enabled = unlocked) { protein = "blue"; carbs = "orange"; fat = "red" }
            }
        }
    }
}

/** Real colour swatches, like App colour. */
@Composable
private fun MacroSwatches(title: String, key: String, selection: String, onSelect: (String) -> Unit, enabled: Boolean) {
    val c = Leanr.colours
    val current = MacroColours.colour(key, mapOf(key to selection), c.dark)
    val name = AppAccent.fromRaw(selection)?.title ?: if (ThemeColour.isCustom(selection)) "Custom" else ""
    val fallback = when (key) { "p" -> AppAccent.BLUE; "c" -> AppAccent.ORANGE; else -> AppAccent.RED }
    SettingsSection(headerContent = {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title.uppercase(), style = LeanrType.footnote, color = c.secondaryText, modifier = Modifier.weight(1f))
            Box(Modifier.size(10.dp).clip(CircleShape).background(current))
            Spacer(Modifier.width(6.dp))
            Text(name, style = LeanrType.footnote, color = c.secondaryText)
        }
    }) {
        SwatchGrid(count = AppAccent.entries.size) { i ->
            val colour = AppAccent.entries[i]
            AccentSwatch(colour.color(c.dark), chosen = colour.raw == selection, locked = false, label = "$title, ${colour.title}") { if (enabled) onSelect(colour.raw) }
        }
        CustomColourRow("Custom ${title.lowercase()} colour", selection, onSelect, fallback, onLocked = null)
    }
}
