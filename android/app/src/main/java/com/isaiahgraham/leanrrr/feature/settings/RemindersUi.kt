package com.isaiahgraham.leanrrr.feature.settings

import android.Manifest
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.billing.Premium
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.Prefs
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.launch

/** Asks for POST_NOTIFICATIONS (Android 13 and later) from a composable, as a suspend call answering whether reminders can be sent. */
class NotificationAsk internal constructor(private val context: Context, private val launch: () -> Unit) {
    internal var waiting: CompletableDeferred<Boolean>? = null

    suspend fun request(): Boolean {
        if (MealReminders.notificationsAllowed(context)) return true
        if (Build.VERSION.SDK_INT < 33) return false
        val answer = CompletableDeferred<Boolean>()
        waiting = answer
        launch()
        return answer.await() && MealReminders.notificationsAllowed(context)
    }
}

@Composable
fun rememberNotificationAsk(): NotificationAsk {
    val context = LocalContext.current
    val holder = remember { arrayOfNulls<NotificationAsk>(1) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        holder[0]?.waiting?.complete(granted); holder[0]?.waiting = null
    }
    return remember {
        NotificationAsk(context) { if (Build.VERSION.SDK_INT >= 33) launcher.launch(Manifest.permission.POST_NOTIFICATIONS) }.also { holder[0] = it }
    }
}

/** The phone's notification settings for Leanrrr. */
fun openNotificationSettings(context: Context) {
    runCatching {
        context.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}

@Composable
internal fun NotificationsOffAlert(onDismiss: () -> Unit, cancelLabel: String = "Cancel") {
    val context = LocalContext.current
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Notifications are off for Leanrrr", style = LeanrType.headline) },
        text = { Text("Turn on notifications for Leanrrr in your phone’s Settings to get reminders.", style = LeanrType.subheadline) },
        confirmButton = { TextButton(onClick = { openNotificationSettings(context); onDismiss() }) { Text("Open Settings") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(cancelLabel) } },
    )
}

/** Reminders to log food: breakfast, lunch, dinner and late night, each ticked on and timed separately, plus water and the weekly review. */
@Composable
internal fun ReminderSettingsScreen(onBack: () -> Unit) {
    val ask = rememberNotificationAsk()
    val scope = rememberCoroutineScope()
    var denied by remember { mutableStateOf(false) }
    // Bumped to redraw after a setting is saved, since the settings live in Prefs.
    var revision by remember { mutableIntStateOf(0) }
    val unlocked = Premium.isUnlocked
    fun reload() { revision += 1; MealReminders.rebook(force = true) }
    fun save(key: String, value: Boolean) { Prefs.set(key, value); reload() }
    fun save(key: String, value: Int) { Prefs.set(key, value.toLong()); reload() }
    fun turnOn(key: String) { scope.launch { if (ask.request()) save(key, true) else denied = true } }

    SettingsPage("Reminders", onBack) {
        if (!unlocked) item { SettingsSection { PremiumPromptRow("Choosing your meal and water reminders comes with Even Leanrrr.") } }
        if (!MealReminders.allOn) item {
            SettingsSection(footerText = "Breakfast, lunch, dinner, late night and water at their usual times. Change any of them below.") {
                ButtonRow("Turn on all reminders", Icons.Outlined.NotificationsActive, divider = false, enabled = unlocked) {
                    scope.launch { if (ask.request()) { MealReminders.enableAll(); reload() } else denied = true }
                }
            }
        }
        MealReminders.meals.forEach { meal ->
            item(key = "meal-${meal.raw}-$revision") {
                SettingsSection(footerText = if (meal == MealTime.SNACKS) "A last nudge, only if you haven't logged anything at all today." else null) {
                    val on = MealReminders.isOn(meal)
                    SwitchRow(MealReminders.title(meal), on, { v -> if (v) turnOn(MealReminders.enabledKey(meal)) else save(MealReminders.enabledKey(meal), false) },
                        divider = on, enabled = unlocked)
                    if (on) TimeRow("Remind me at", MealReminders.minutes(meal), { save(MealReminders.timeKey(meal), it) }, divider = false, enabled = unlocked)
                }
            }
        }
        item {
            SettingsSection(footer = { if (!unlocked) LockedFooter("Choosing which meals remind you, and when, comes with Even Leanrrr.") }) {
                NoteRow("Leanrrr only reminds you if nothing has been logged to that meal by then. Log it and today's reminder is cancelled. The wording changes from day to day.")
            }
        }
        item(key = "water-$revision") {
            SettingsSection(footerText = "Spaced through the day. Once you've reached your water target, the rest of that day's water reminders are dropped.") {
                val on = MealReminders.waterOn
                SwitchRow("Water", on, { v -> if (v) turnOn(MealReminders.WATER_ON_KEY) else save(MealReminders.WATER_ON_KEY, false) }, divider = on, enabled = unlocked)
                if (on) {
                    val schedule = MealReminders.waterSchedule
                    TimeRow("From", schedule.from, { minutes ->
                        Prefs.set(MealReminders.WATER_FROM_KEY, minutes.toLong())
                        // The end never sits before the start.
                        if (schedule.until < minutes) Prefs.set(MealReminders.WATER_UNTIL_KEY, minOf(minutes + 60, 23 * 60 + 59).toLong())
                        reload()
                    }, enabled = unlocked)
                    TimeRow("Until", schedule.until, { save(MealReminders.WATER_UNTIL_KEY, maxOf(it, schedule.from)) }, enabled = unlocked)
                    MenuPickerRow("Every", MealReminders.WaterSchedule.hourChoices, schedule.everyHours, { if (it == 1) "Hour" else "$it hours" },
                        { save(MealReminders.WATER_EVERY_KEY, it) }, divider = false, enabled = unlocked)
                }
            }
        }
        item(key = "weekly-$revision") {
            val minutes = MealReminders.weeklyMinutes(unlocked)
            SettingsSection(footer = {
                Column(Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Sundays at ${clockText(minutes)}: days logged, average calories, protein days and your weight trend.", style = LeanrType.footnote,
                        color = Leanr.colours.secondaryText)
                }
                if (!unlocked) LockedFooter("Choosing the time comes with Even Leanrrr.")
            }) {
                val on = MealReminders.weeklyOn
                SwitchRow("Weekly review", on, { v -> if (v) turnOn(MealReminders.WEEKLY_KEY) else save(MealReminders.WEEKLY_KEY, false) }, divider = on)
                if (on) TimeRow("Sundays at", minutes, { save(MealReminders.WEEKLY_TIME_KEY, it) }, divider = false, enabled = unlocked)
            }
        }
    }
    if (denied) NotificationsOffAlert({ denied = false })
}

/** Offered when someone comes back after a few days away with no reminders set up: pick what to be nudged about. */
@Composable
internal fun ReminderPromptScreen(onDismiss: () -> Unit) {
    val c = Leanr.colours
    val ask = rememberNotificationAsk()
    val scope = rememberCoroutineScope()
    var meals by remember { mutableStateOf(setOf(MealTime.BREAKFAST, MealTime.LUNCH, MealTime.DINNER)) }
    var water by remember { mutableStateOf(true) }
    var denied by remember { mutableStateOf(false) }
    var working by remember { mutableStateOf(false) }
    val schedule = MealReminders.WaterSchedule()
    val waterDetail = "Every ${schedule.everyHours} hours, ${clockText(schedule.from)} to ${clockText(schedule.until)}. Stops once you've reached your target."
    fun markAsked() = Prefs.set(ReminderPrompt.ASKED_KEY, System.currentTimeMillis() / 1000)
    // Closing the sheet any way counts as asking, so it isn't offered again straight away.
    DisposableEffect(Unit) { onDispose { if (Prefs.long(ReminderPrompt.ASKED_KEY) == null) markAsked() } }

    LeanrScreen("Reminders", showSettings = false) {
        item {
            SettingsSection {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Outlined.NotificationsActive, null, tint = c.accent, modifier = Modifier.size(34.dp))
                    Text("Want a nudge to keep logging?", style = LeanrType.roboto(22f, FontWeight.Bold), color = c.text)
                    Text("Leanrrr can remind you about meals and water. Reminders only go out if you haven't already logged, and you can change or stop them any time in Settings.",
                        style = LeanrType.subheadline, color = c.secondaryText)
                }
            }
        }
        item {
            SettingsSection {
                MealReminders.meals.forEach { meal ->
                    val minutes = MealReminders.minutes(meal)
                    ChoiceRow(MealReminders.title(meal), if (meal == MealTime.SNACKS) "${clockText(minutes)}, only if nothing's logged all day" else clockText(minutes),
                        meal in meals) { meals = if (meal in meals) meals - meal else meals + meal }
                }
                ChoiceRow("Water", waterDetail, water, divider = false) { water = !water }
            }
        }
        item {
            Column(Modifier.fillMaxWidth().padding(bottom = 20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Button(
                    onClick = {
                        working = true
                        scope.launch {
                            val granted = ask.request()
                            working = false
                            markAsked()
                            if (granted) { MealReminders.enable(meals, water); MealReminders.rebook(force = true); onDismiss() } else denied = true
                        }
                    },
                    enabled = !working && (meals.isNotEmpty() || water),
                    colors = ButtonDefaults.buttonColors(containerColor = c.accent, contentColor = if (c.dark) Color.Black else Color.White),
                    shape = RoundedCornerShape(14.dp), modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp),
                ) { Text("Turn on reminders", style = LeanrType.headline) }
                TextButton(onClick = { markAsked(); onDismiss() }, modifier = Modifier.heightIn(min = 44.dp)) { Text("Not now", color = c.accent) }
            }
        }
    }
    if (denied) NotificationsOffAlert({ denied = false; onDismiss() }, cancelLabel = "Not now")
}

@Composable
private fun ChoiceRow(title: String, detail: String, on: Boolean, divider: Boolean = true, toggle: () -> Unit) {
    val c = Leanr.colours
    Column {
        Row(Modifier.fillMaxWidth().clickable(onClick = toggle).padding(horizontal = 16.dp, vertical = 11.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(title, style = LeanrType.body.copy(fontWeight = FontWeight.Medium), color = c.text)
                Text(detail, style = LeanrType.caption, color = c.secondaryText)
            }
            Icon(if (on) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked, null, tint = if (on) c.accent else c.secondaryText)
        }
        if (divider) androidx.compose.material3.HorizontalDivider(Modifier.padding(start = 16.dp), color = c.separator, thickness = 0.5.dp)
    }
}
