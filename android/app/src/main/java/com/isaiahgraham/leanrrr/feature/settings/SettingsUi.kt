package com.isaiahgraham.leanrrr.feature.settings

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.isaiahgraham.leanrrr.ui.components.LeanrRow
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrBackground
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

// Small building blocks the Settings screens share: a full-screen sheet, pages, switch rows, pickers and a time picker.

/** A sheet that covers the screen (an iOS sheet with its own navigation stack), on the order-pad paper. */
@Composable
fun FullScreenSheet(onDismiss: () -> Unit, dismissOnBack: Boolean = true, content: @Composable () -> Unit) {
    Dialog(
        onDismissRequest = { if (dismissOnBack) onDismiss() },
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false, dismissOnBackPress = dismissOnBack,
            dismissOnClickOutside = false),
    ) {
        LeanrBackground(Modifier.fillMaxSize()) {
            Box(Modifier.fillMaxSize().navigationBarsPadding().imePadding()) { content() }
        }
    }
}

/** A pushed page inside a sheet: a title, a back arrow, and grouped sections. System back goes back too. */
@Composable
internal fun SettingsPage(title: String, onBack: () -> Unit, actions: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit = {},
                          content: LazyListScope.() -> Unit) {
    BackHandler(onBack = onBack)
    LeanrScreen(title, onBack = onBack, showSettings = false, actions = actions, content = content)
}

/** A row with a leading icon that pushes another page (NavigationLink with a Label). */
@Composable
internal fun LinkRow(title: String, icon: ImageVector?, subtitle: String? = null, divider: Boolean = true, titleColour: Color? = null,
                     trailingText: String? = null, chevron: Boolean = true, onClick: () -> Unit) {
    val c = Leanr.colours
    LeanrRow(title, subtitle, divider = divider, titleColour = titleColour,
        leading = icon?.let { { Icon(it, null, tint = titleColour ?: c.accent, modifier = Modifier.size(24.dp)) } },
        trailing = {
            if (trailingText != null) Text(trailingText, style = LeanrType.subheadline, color = c.secondaryText)
            if (chevron) Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = c.tertiaryText)
        }, onClick = onClick)
}

/** A plain button row in the accent colour (a Button in an iOS list). */
@Composable
internal fun ButtonRow(title: String, icon: ImageVector? = null, divider: Boolean = true, enabled: Boolean = true, colour: Color? = null, onClick: () -> Unit) {
    val c = Leanr.colours
    val tint = if (!enabled) c.tertiaryText else colour ?: c.accent
    LeanrRow(title, divider = divider, titleColour = tint,
        leading = icon?.let { { Icon(it, null, tint = tint, modifier = Modifier.size(24.dp)) } },
        onClick = if (enabled) onClick else null)
}

/** A switch with a label and optional icon (Toggle). */
@Composable
internal fun SwitchRow(title: String, checked: Boolean, onChange: (Boolean) -> Unit, icon: ImageVector? = null, subtitle: String? = null,
                       divider: Boolean = true, enabled: Boolean = true) {
    val c = Leanr.colours
    LeanrRow(title, subtitle, divider = divider, titleColour = if (enabled) null else c.tertiaryText,
        leading = icon?.let { { Icon(it, null, tint = if (enabled) c.accent else c.tertiaryText, modifier = Modifier.size(24.dp)) } },
        trailing = {
            Switch(checked, onCheckedChange = if (enabled) onChange else null, enabled = enabled,
                colors = SwitchDefaults.colors(checkedTrackColor = c.accent, checkedThumbColor = if (c.dark) Color.Black else Color.White))
        }, onClick = if (enabled) ({ onChange(!checked) }) else null)
}

/** Label on the left, value on the right, in a row (LabeledContent). */
@Composable
internal fun ValueRow(title: String, value: String, divider: Boolean = true, onClick: (() -> Unit)? = null) {
    LeanrRow(title, divider = divider, trailing = { Text(value, style = LeanrType.body, color = Leanr.colours.secondaryText) }, onClick = onClick)
}

/** Text inside a section, secondary by default. */
@Composable
internal fun NoteRow(text: String, divider: Boolean = false, primary: Boolean = false, colour: Color? = null) {
    val c = Leanr.colours
    Column {
        Text(text, style = if (primary) LeanrType.body else LeanrType.subheadline, color = colour ?: if (primary) c.text else c.secondaryText,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 11.dp))
        if (divider) androidx.compose.material3.HorizontalDivider(Modifier.padding(start = 16.dp), color = c.separator, thickness = 0.5.dp)
    }
}

/** A menu picker: the title and the chosen option, which opens a dropdown (Picker in a list). */
@Composable
internal fun <T> MenuPickerRow(title: String, options: List<T>, selected: T, label: (T) -> String, onSelect: (T) -> Unit,
                               icon: ImageVector? = null, divider: Boolean = true, enabled: Boolean = true) {
    val c = Leanr.colours
    var open by remember { mutableStateOf(false) }
    Box {
        LeanrRow(title, divider = divider, titleColour = if (enabled) null else c.tertiaryText,
            leading = icon?.let { { Icon(it, null, tint = c.accent, modifier = Modifier.size(24.dp)) } },
            trailing = { Text(label(selected), style = LeanrType.body, color = if (enabled) c.accent else c.tertiaryText) },
            onClick = if (enabled) ({ open = true }) else null)
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, modifier = Modifier.align(Alignment.TopEnd)) {
            options.forEach { option ->
                DropdownMenuItem(text = { Text(label(option), fontWeight = if (option == selected) FontWeight.Bold else FontWeight.Normal) },
                    onClick = { open = false; onSelect(option) })
            }
        }
    }
}

/** Two or three choices side by side (a segmented Picker). */
@Composable
internal fun <T> SegmentedRow(options: List<Pair<T, String>>, selected: T, onSelect: (T) -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    val c = Leanr.colours
    SingleChoiceSegmentedButtonRow(modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
        options.forEachIndexed { i, (value, label) ->
            SegmentedButton(selected = selected == value, onClick = { onSelect(value) }, enabled = enabled, shape = SegmentedButtonDefaults.itemShape(i, options.size),
                colors = SegmentedButtonDefaults.colors(activeContainerColor = c.accent.copy(alpha = 0.16f), activeContentColor = c.text)) {
                Text(label, style = LeanrType.subheadline)
            }
        }
    }
}

/** "9:30 am" in the phone's own style. */
internal fun clockText(minutes: Int): String =
    LocalTime.of((minutes / 60).coerceIn(0, 23), (minutes % 60).coerceIn(0, 59)).format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT))

/** A time of day you tap to change (DatePicker with .hourAndMinute). Minutes after midnight. */
@Composable
internal fun TimeRow(title: String, minutes: Int, onChange: (Int) -> Unit, divider: Boolean = true, enabled: Boolean = true) {
    var picking by remember { mutableStateOf(false) }
    val c = Leanr.colours
    LeanrRow(title, divider = divider, titleColour = if (enabled) null else c.tertiaryText,
        trailing = { Text(clockText(minutes), style = LeanrType.body, color = if (enabled) c.accent else c.tertiaryText) },
        onClick = if (enabled) ({ picking = true }) else null)
    if (picking) {
        val context = LocalContext.current
        val state = rememberTimePickerState(minutes / 60, minutes % 60, android.text.format.DateFormat.is24HourFormat(context))
        AlertDialog(
            onDismissRequest = { picking = false },
            confirmButton = { TextButton(onClick = { picking = false; onChange(state.hour * 60 + state.minute) }) { Text("Done") } },
            dismissButton = { TextButton(onClick = { picking = false }) { Text("Cancel") } },
            text = { TimePicker(state) },
        )
    }
}

/** A row telling a locked user what Even Leanrrr adds, which opens the Even Leanrrr screen. Shows nothing once they have it. */
@Composable
fun PremiumPromptRow(message: String = "Part of Even Leanrrr.", divider: Boolean = false) {
    if (com.isaiahgraham.leanrrr.billing.Premium.isUnlocked) return
    var showing by remember { mutableStateOf(false) }
    val c = Leanr.colours
    Row(Modifier.fillMaxWidth().clickable { showing = true }.padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Filled.Lock, null, tint = c.accent, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(10.dp))
        Text(message, style = LeanrType.body, color = c.text, modifier = Modifier.weight(1f))
        Spacer(Modifier.width(8.dp))
        Text("See Even Leanrrr", style = LeanrType.subheadline.copy(fontWeight = FontWeight.SemiBold), color = c.accent)
    }
    if (divider) androidx.compose.material3.HorizontalDivider(Modifier.padding(start = 16.dp), color = c.separator, thickness = 0.5.dp)
    if (showing) PremiumSheet(onDismiss = { showing = false })
}

/** A footer line with a lock in front ("Colour packs come with Even Leanrrr."). */
@Composable
internal fun LockedFooter(text: String) {
    val c = Leanr.colours
    Row(Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Filled.Lock, null, tint = c.secondaryText, modifier = Modifier.size(13.dp))
        Spacer(Modifier.width(6.dp))
        Text(text, style = LeanrType.footnote, color = c.secondaryText)
    }
}

internal fun openUrl(context: Context, url: String) {
    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}

/** A simple OK alert. */
@Composable
internal fun MessageAlert(title: String, message: String? = null, onDismiss: () -> Unit) {
    AlertDialog(onDismissRequest = onDismiss, confirmButton = { TextButton(onClick = onDismiss) { Text("OK") } },
        title = { Text(title, style = LeanrType.headline) }, text = message?.let { { Text(it, style = LeanrType.subheadline) } })
}

/** A grouped section whose header and footer can hold more than text (LeanrSection with slots). */
@Composable
internal fun SettingsSection(
    header: String? = null,
    footerText: String? = null,
    headerContent: (@Composable () -> Unit)? = null,
    footer: (@Composable () -> Unit)? = null,
    content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit,
) {
    val c = Leanr.colours
    Column(Modifier.fillMaxWidth().padding(bottom = 20.dp)) {
        if (headerContent != null) Box(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 6.dp)) { headerContent() }
        else if (header != null) Text(header.uppercase(), style = LeanrType.footnote, color = c.secondaryText, modifier = Modifier.padding(start = 16.dp, bottom = 6.dp))
        Column(Modifier.fillMaxWidth().clip(androidx.compose.foundation.shape.RoundedCornerShape(12.dp)).background(c.card), content = content)
        if (footerText != null) Text(footerText, style = LeanrType.footnote, color = c.secondaryText, modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp))
        footer?.invoke()
    }
}
