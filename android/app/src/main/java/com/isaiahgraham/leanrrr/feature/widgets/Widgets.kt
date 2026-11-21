package com.isaiahgraham.leanrrr.feature.widgets

import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ColorFilter
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.MainActivity
import com.isaiahgraham.leanrrr.R
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.feature.today.Water
import com.isaiahgraham.leanrrr.ui.theme.TargetStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.LocalDate
import java.time.format.TextStyle as DayStyle
import java.util.Locale
import androidx.glance.color.ColorProvider as DayNight

// Jetpack Glance ports of the LeanrWidgets extension. Each widget reads the store through WidgetCalories when it's drawn, and
// WidgetSync redraws them after every save. Tapping a widget opens Today (Progress for steps and calories burnt).

// region Look

private val textPrimary = DayNight(day = Color.Black, night = Color.White)
private val textSecondary = DayNight(day = Color(0x993C3C43), night = Color(0x99EBEBF5))
private val cardBackground = DayNight(day = Color.White, night = Color(0xFF1C1C1E))
private val groupedBackground = DayNight(day = Color(0xFFF2F2F7), night = Color(0xFF1C1C1E))
private val track = DayNight(day = Color(0x29000000), night = Color(0x29FFFFFF))
private val waterColour = DayNight(day = Color(0xFF00698B), night = Color(0xFF64D2FF))

private fun style(size: TextUnit, weight: FontWeight = FontWeight.Normal, colour: ColorProvider = textPrimary) =
    TextStyle(color = colour, fontSize = size, fontWeight = weight)

private val WidgetCalories.accentProvider: ColorProvider get() = DayNight(day = accent(false), night = accent(true))
private fun WidgetCalories.macroProvider(key: String): ColorProvider = DayNight(day = macroColour(key, false), night = macroColour(key, true))
private fun statusProvider(status: TargetStatus): ColorProvider? =
    status.colour(false)?.let { day -> DayNight(day = day, night = status.colour(true)!!) }

@Composable
private fun isNight(): Boolean =
    (LocalContext.current.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES

/** A progress ring drawn as a bitmap, since Glance has no determinate circular progress. */
private fun ring(progress: Double, colour: Color, trackColour: Color, sizePx: Int = 240, strokePx: Float = 24f): Bitmap {
    val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    val inset = strokePx / 2 + 1
    val rect = RectF(inset, inset, sizePx - inset, sizePx - inset)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = strokePx; strokeCap = Paint.Cap.ROUND }
    paint.color = trackColour.toArgb()
    canvas.drawArc(rect, 0f, 360f, false, paint)
    if (progress > 0) {
        paint.color = colour.toArgb()
        canvas.drawArc(rect, -90f, (360 * progress.coerceIn(0.0, 1.0)).toFloat(), false, paint)
    }
    return bitmap
}

private fun openApp(context: Context, host: String) =
    actionStartActivity(Intent(Intent.ACTION_VIEW, Uri.parse("leanr://$host"), context, MainActivity::class.java))

@Composable
private fun Icon(res: Int, colour: ColorProvider, size: Dp = 14.dp) {
    Image(ImageProvider(res), contentDescription = null, modifier = GlanceModifier.size(size), colorFilter = ColorFilter.tint(colour))
}

@Composable
private fun Label(res: Int, text: String, colour: ColorProvider, size: TextUnit = 12.sp) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(res, colour, (size.value + 2).dp)
        Spacer(GlanceModifier.width(5.dp))
        Text(text, style = style(size, FontWeight.Bold, colour), maxLines = 1)
    }
}

@Composable
private fun Bar(progress: Double, colour: ColorProvider, height: Dp = 5.dp) {
    LinearProgressIndicator(progress.coerceIn(0.0, 1.0).toFloat(), GlanceModifier.fillMaxWidth().height(height), color = colour, backgroundColor = track)
}

/** The rounded card every widget sits on, opening the app at `host` when tapped. */
@Composable
private fun WidgetCard(host: String, background: ColorProvider = cardBackground, content: @Composable () -> Unit) {
    val context = LocalContext.current
    Box(
        GlanceModifier.fillMaxSize().appWidgetBackground().cornerRadius(22.dp).background(background).padding(14.dp).clickable(openApp(context, host)),
        contentAlignment = Alignment.TopStart,
    ) { content() }
}

private fun grams(value: Double): String = value.number.replace(",", "")

// endregion

// region Base

/** A Leanrrr widget: draws from the store each time, at the exact size it's placed at. */
abstract class LeanrWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Exact
    /** Only Log again lists usual meals and pinned foods, which take a search through every food to work out. */
    open val needsQuickLogs: Boolean = false

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        AppServices.start(context.applicationContext as android.app.Application)
        provideContent { Content(WidgetCalories.current(quickLogs = needsQuickLogs)) }
    }

    @Composable abstract fun Content(snapshot: WidgetCalories)
}

/** Shown on a Premium widget while Even Leanrrr is locked. */
@Composable
private fun Locked(snapshot: WidgetCalories, title: String? = null) {
    Column(GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically, horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(R.drawable.widget_ic_lock, snapshot.accentProvider, 26.dp)
        if (title != null) { Spacer(GlanceModifier.height(8.dp)); Text(title, style = style(20.sp, FontWeight.Bold)) }
        Spacer(GlanceModifier.height(6.dp))
        Text("Open Leanrrr to unlock this widget", style = style(13.sp, colour = textSecondary))
    }
}

@Composable
private fun Prompt(text: String) {
    Column(GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
        Label(R.drawable.widget_ic_leaf, "Leanrrr", textPrimary, 14.sp)
        Spacer(GlanceModifier.height(6.dp))
        Text(text, style = style(14.sp))
    }
}

// endregion

// region Calories left

/** Today's calories remaining against your target. Free in every size. */
class CaloriesWidget : LeanrWidget() {
    @Composable override fun Content(snapshot: WidgetCalories) {
        val wide = LocalSize.current.width >= 220.dp
        val accent = snapshot.accentProvider
        val night = isNight()
        WidgetCard("today") {
            Row(GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                Column(GlanceModifier.defaultWeight().fillMaxHeight()) {
                    Label(R.drawable.widget_ic_leaf, "Leanrrr", accent)
                    Spacer(GlanceModifier.defaultWeight())
                    if (snapshot.remaining != null) {
                        Text(snapshot.value, style = style(36.sp, FontWeight.Bold), maxLines = 1)
                        Text(snapshot.caption, style = style(14.sp, FontWeight.Medium), maxLines = 1)
                        Spacer(GlanceModifier.defaultWeight())
                        Text("${snapshot.whole(snapshot.eaten)} / ${snapshot.whole(snapshot.target ?: 0.0)} Cal", style = style(11.sp, colour = textSecondary), maxLines = 1)
                    } else {
                        Text(snapshot.prompt, style = style(16.sp, FontWeight.Medium))
                        Text("Calories left today.", style = style(12.sp, colour = textSecondary))
                        Spacer(GlanceModifier.defaultWeight())
                    }
                }
                if (wide && snapshot.remaining != null) {
                    Spacer(GlanceModifier.width(12.dp))
                    Box(GlanceModifier.size(96.dp), contentAlignment = Alignment.Center) {
                        val colour = snapshot.accent(night)
                        Image(ImageProvider(ring(snapshot.progress, colour, colour.copy(alpha = 0.18f), strokePx = 22f)), null, GlanceModifier.fillMaxSize())
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Icon(R.drawable.widget_ic_fork, accent, 20.dp)
                            Text("Today", style = style(12.sp, FontWeight.Medium))
                        }
                    }
                }
            }
        }
    }
}

// endregion

// region Macros

@Composable
private fun MacroRow(snapshot: WidgetCalories, id: String, name: String, bar: Boolean, size: TextUnit = 11.sp, compact: Boolean = false) {
    val value = snapshot.nutrients[id] ?: 0.0
    val target = snapshot.nutrientTargets.firstOrNull { it.id == id }?.target
    val partial = id in snapshot.partial
    val targetText = target?.let { grams(it) } ?: "—"
    // Green once the protein goal is met, orange once carbs or fat go past their target.
    val status = targetStatus(id, value, target)
    val statusColour = statusProvider(status)
    val weight = if (status == TargetStatus.NONE) FontWeight.Medium else FontWeight.Bold
    Column(GlanceModifier.fillMaxWidth()) {
        Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(if (compact) name.take(1) else name, style = style(size, weight, statusColour ?: textSecondary), maxLines = 1)
            Spacer(GlanceModifier.defaultWeight())
            Text(if (compact) "${grams(value)}${if (partial) "+" else ""}/${targetText}g" else "${grams(value)}${if (partial) "+" else ""} / $targetText g",
                style = style(size, weight, statusColour ?: textPrimary), maxLines = 1)
        }
        if (bar) {
            Spacer(GlanceModifier.height(4.dp))
            Bar(target?.let { value / it } ?: 0.0, snapshot.macroProvider(id))
        }
    }
}

/** Calories remaining in a ring with protein, carbs and fat against your targets. Premium. */
class MacrosWidget : LeanrWidget() {
    @Composable override fun Content(snapshot: WidgetCalories) {
        val night = isNight()
        WidgetCard("today", groupedBackground) {
            when {
                !snapshot.readable -> Prompt("Open Leanrrr to sync your targets")
                !snapshot.premiumUnlocked -> Locked(snapshot)
                else -> Row(GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                    val side = maxOf(48.dp, minOf(LocalSize.current.height - 28.dp, LocalSize.current.width * 0.37f))
                    Box(GlanceModifier.size(side), contentAlignment = Alignment.Center) {
                        val colour = snapshot.accent(night)
                        Image(ImageProvider(ring(snapshot.progress, colour, if (night) Color(0x29FFFFFF) else Color(0x29000000))), null, GlanceModifier.fillMaxSize())
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(snapshot.value, style = style(24.sp, FontWeight.Bold), maxLines = 1)
                            Icon(R.drawable.widget_ic_leaf, snapshot.accentProvider, 11.dp)
                            Text(if (snapshot.remaining == null) "Set target" else if ((snapshot.remaining ?: 0.0) < 0) "Cals over" else "Cals left",
                                style = style(11.sp, colour = textSecondary), maxLines = 1)
                        }
                    }
                    Spacer(GlanceModifier.width(16.dp))
                    Column(GlanceModifier.defaultWeight()) {
                        MacroRow(snapshot, "p", "Protein", bar = true)
                        Spacer(GlanceModifier.height(10.dp))
                        MacroRow(snapshot, "c", "Carbs", bar = true)
                        Spacer(GlanceModifier.height(10.dp))
                        MacroRow(snapshot, "f", "Fat", bar = true)
                    }
                }
            }
        }
    }
}

/** Calories left as a big number with protein, carbs and fat underneath, laid out like a weather widget. Premium. */
class MacroSummaryWidget : LeanrWidget() {
    @Composable override fun Content(snapshot: WidgetCalories) {
        val wide = LocalSize.current.width >= 220.dp
        WidgetCard("today", groupedBackground) {
            when {
                !snapshot.readable -> Prompt("Open Leanrrr to sync your targets")
                !snapshot.premiumUnlocked -> Locked(snapshot)
                wide -> Row(GlanceModifier.fillMaxSize()) {
                    Column(GlanceModifier.defaultWeight()) { SummaryHeader(snapshot) }
                    Spacer(GlanceModifier.width(18.dp))
                    Column(GlanceModifier.defaultWeight().fillMaxHeight(), verticalAlignment = Alignment.CenterVertically) {
                        MacroRow(snapshot, "p", "Protein", bar = true, size = 12.sp)
                        Spacer(GlanceModifier.height(10.dp))
                        MacroRow(snapshot, "c", "Carbs", bar = true, size = 12.sp)
                        Spacer(GlanceModifier.height(10.dp))
                        MacroRow(snapshot, "f", "Fat", bar = true, size = 12.sp)
                    }
                }
                else -> Column(GlanceModifier.fillMaxSize()) {
                    SummaryHeader(snapshot)
                    Spacer(GlanceModifier.defaultWeight())
                    MacroRow(snapshot, "p", "Protein", bar = false, size = 13.sp, compact = true)
                    Spacer(GlanceModifier.height(3.dp))
                    MacroRow(snapshot, "c", "Carbs", bar = false, size = 13.sp, compact = true)
                    Spacer(GlanceModifier.height(3.dp))
                    MacroRow(snapshot, "f", "Fat", bar = false, size = 13.sp, compact = true)
                }
            }
        }
    }
}

/** Leaf and calories left on one line, then what the number means and how much has been eaten. */
@Composable
private fun SummaryHeader(snapshot: WidgetCalories) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(R.drawable.widget_ic_leaf, snapshot.accentProvider, 20.dp)
        Spacer(GlanceModifier.width(6.dp))
        Text(snapshot.value, style = style(30.sp, FontWeight.Bold), maxLines = 1)
    }
    Text(if (snapshot.remaining == null) "Set a calorie target" else if ((snapshot.remaining ?: 0.0) < 0) "Cals over" else "Cals left",
        style = style(15.sp, FontWeight.Medium), maxLines = 1)
    Text("${snapshot.eatenValue} of ${snapshot.targetValue} eaten", style = style(12.sp, colour = textSecondary), maxLines = 1)
}

// endregion

// region All targets

/** Calories and every nutrient target you track. Premium. */
class TargetsWidget : LeanrWidget() {
    @Composable override fun Content(snapshot: WidgetCalories) {
        val accent = snapshot.accentProvider
        WidgetCard("today") {
            when {
                !snapshot.readable -> Prompt("Open Leanrrr to sync your targets")
                !snapshot.premiumUnlocked -> Locked(snapshot, "All targets")
                else -> Column(GlanceModifier.fillMaxSize()) {
                    Label(R.drawable.widget_ic_leaf, "Leanrrr", accent, 15.sp)
                    Spacer(GlanceModifier.height(8.dp))
                    Row(verticalAlignment = Alignment.Bottom) {
                        Text(snapshot.eatenValue, style = style(28.sp, FontWeight.Bold), maxLines = 1)
                        Spacer(GlanceModifier.width(4.dp))
                        Text("/ ${snapshot.targetValue} cals", style = style(14.sp, colour = textSecondary), maxLines = 1)
                    }
                    Spacer(GlanceModifier.height(6.dp))
                    Bar(snapshot.progress, accent, 6.dp)
                    Spacer(GlanceModifier.height(10.dp))
                    val targets = snapshot.nutrientTargets
                    if (targets.isEmpty()) {
                        Text("Add nutrient targets in Leanrrr to see them here.", style = style(14.sp, colour = textSecondary))
                        Spacer(GlanceModifier.defaultWeight())
                    } else {
                        val compact = targets.size > 8
                        Column(GlanceModifier.defaultWeight().fillMaxWidth()) {
                            targets.chunked(2).forEach { pair ->
                                Row(GlanceModifier.fillMaxWidth().defaultWeight()) {
                                    pair.forEachIndexed { i, target ->
                                        if (i == 1) Spacer(GlanceModifier.width(12.dp))
                                        Box(GlanceModifier.defaultWeight()) { NutrientCell(snapshot, target, compact) }
                                    }
                                    if (pair.size == 1) { Spacer(GlanceModifier.width(12.dp)); Spacer(GlanceModifier.defaultWeight()) }
                                }
                            }
                        }
                    }
                    Text(if (snapshot.partial.isEmpty()) "Today · Your active targets" else "+ Partial totals: some food data is missing",
                        style = style(9.sp, colour = textSecondary), maxLines = 1)
                }
            }
        }
    }
}

@Composable
private fun NutrientCell(snapshot: WidgetCalories, target: WidgetNutrientTarget, compact: Boolean) {
    val value = snapshot.nutrients[target.id] ?: 0.0
    val incomplete = target.id in snapshot.partial
    val status = targetStatus(target.id, value, target.target)
    val colour = statusProvider(status)
    val weight = if (status == TargetStatus.NONE) FontWeight.Normal else FontWeight.Bold
    Column(GlanceModifier.fillMaxWidth()) {
        if (compact) {
            Row(GlanceModifier.fillMaxWidth()) {
                Text(target.name, style = style(9.sp, FontWeight.Medium, colour ?: textPrimary), maxLines = 1)
                Spacer(GlanceModifier.defaultWeight())
                Text("${grams(value)}${if (incomplete) "+" else ""}/${grams(target.target)} ${target.unit}", style = style(8.sp, weight, colour ?: textSecondary), maxLines = 1)
            }
        } else {
            Text(target.name, style = style(12.sp, FontWeight.Medium, colour ?: textPrimary), maxLines = 1)
            Text("${grams(value)}${if (incomplete) "+" else ""} / ${if (target.minimum) "≥" else "≤"}${grams(target.target)} ${target.unit}",
                style = style(11.sp, weight, colour ?: textSecondary), maxLines = 1)
        }
        Spacer(GlanceModifier.height(if (compact) 1.dp else 4.dp))
        Bar(value / target.target, if (target.id in setOf("p", "c", "f")) snapshot.macroProvider(target.id) else snapshot.accentProvider, 4.dp)
    }
}

// endregion

// region Streak

/** Counts the days in a row you've logged food. */
class StreakWidget : LeanrWidget() {
    @Composable override fun Content(snapshot: WidgetCalories) {
        val count = snapshot.streak
        val wide = LocalSize.current.width >= 220.dp
        WidgetCard("today") {
            Column(GlanceModifier.fillMaxSize()) {
                Label(R.drawable.widget_ic_flame, "Tracking streak", snapshot.accentProvider)
                Spacer(GlanceModifier.height(8.dp))
                Text(if (!snapshot.readable) "—" else "$count day${if (count == 1) "" else "s"}", style = style(32.sp, FontWeight.Bold), maxLines = 1)
                Text(when {
                    !snapshot.readable -> "Open Leanrrr to sync"
                    snapshot.trackedToday -> "Tracked today"
                    else -> "Log today to ${if (count > 0) "keep it going" else "start"}"
                }, style = style(12.sp, colour = textSecondary))
                if (wide) Text("Any day with food logged counts.", style = style(12.sp, colour = textSecondary))
            }
        }
    }
}

// endregion

// region Steps and calories burnt

@Composable
private fun RingWithWeek(
    snapshot: WidgetCalories, icon: Int, progress: Double, valueText: String, under: String, caption: String,
    week: List<Pair<LocalDate, Double>>, reached: (Double) -> Boolean, height: (Double) -> Double,
) {
    val wide = LocalSize.current.width >= 220.dp
    val night = isNight()
    val accent = snapshot.accent(night)
    @Composable fun ringBox() {
        Box(GlanceModifier.size(maxOf(48.dp, minOf(110.dp, LocalSize.current.height - 48.dp))), contentAlignment = Alignment.Center) {
            Image(ImageProvider(ring(progress, accent, accent.copy(alpha = 0.2f))), null, GlanceModifier.fillMaxSize())
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(icon, snapshot.accentProvider, 13.dp)
                Text(valueText, style = style(18.sp, FontWeight.Bold), maxLines = 1)
                Text(under, style = style(10.sp, colour = textSecondary), maxLines = 1)
            }
        }
    }
    if (!wide) {
        Column(GlanceModifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalAlignment = Alignment.CenterVertically) {
            ringBox()
            Spacer(GlanceModifier.height(6.dp))
            Text(caption, style = style(12.sp, colour = textSecondary), maxLines = 1)
        }
    } else {
        Row(GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
            ringBox()
            Spacer(GlanceModifier.width(18.dp))
            Column(GlanceModifier.defaultWeight()) {
                Text("Last 7 days", style = style(12.sp, colour = textSecondary))
                Spacer(GlanceModifier.height(8.dp))
                Row(GlanceModifier.fillMaxWidth().height(76.dp), verticalAlignment = Alignment.Bottom) {
                    week.forEachIndexed { i, (day, value) ->
                        if (i > 0) Spacer(GlanceModifier.width(6.dp))
                        Column(GlanceModifier.defaultWeight(), horizontalAlignment = Alignment.CenterHorizontally) {
                            val barColour = if (reached(value)) accent else accent.copy(alpha = 0.45f)
                            Box(GlanceModifier.fillMaxWidth().height(maxOf(4.0, 56 * height(value)).dp).cornerRadius(3.dp).background(barColour)) {}
                            Spacer(GlanceModifier.height(4.dp))
                            Text(day.dayOfWeek.getDisplayName(DayStyle.NARROW, Locale.getDefault()), style = style(10.sp, colour = textSecondary))
                        }
                    }
                }
            }
        }
    }
}

private fun whole(value: Double) = "%,d".format(Locale.US, Math.round(value))

/** Today's steps from Health Connect against your goal. */
class StepsWidget : LeanrWidget() {
    @Composable override fun Content(snapshot: WidgetCalories) {
        val goal = snapshot.stepGoal
        val count = snapshot.stepCount(snapshot.date)
        val progress = if (goal > 0) minOf(1.0, (count ?: 0.0) / goal) else 0.0
        val caption = when {
            !snapshot.readable -> "Open Leanrrr to sync"
            count == null -> "No steps yet today"
            count >= goal -> "Goal reached"
            else -> "${whole(goal - count)} to go"
        }
        val week = (6 downTo 0).map { snapshot.date.minusDays(it.toLong()) }.map { it to (snapshot.stepCount(it) ?: 0.0) }
        WidgetCard("progress") {
            RingWithWeek(snapshot, R.drawable.widget_ic_walk, progress, count?.let(::whole) ?: "—", "of ${whole(goal)}", caption, week,
                reached = { it >= goal }, height = { minOf(1.0, it / maxOf(goal, 1.0)) })
        }
    }
}

/** Today's active calories from Health Connect, against the average of the other days this week. */
class CaloriesBurntWidget : LeanrWidget() {
    @Composable override fun Content(snapshot: WidgetCalories) {
        val burnt = snapshot.energyBurnt(snapshot.date)
        val average = snapshot.energyAverage
        val progress = if (burnt != null && average != null && average > 0) minOf(1.0, burnt / average) else 0.0
        val caption = when {
            !snapshot.readable -> "Open Leanrrr to sync"
            burnt == null -> "None recorded yet"
            else -> average?.let { "Average ${whole(it)} Cal" } ?: "Active today"
        }
        val week = (6 downTo 0).map { snapshot.date.minusDays(it.toLong()) }.map { it to (snapshot.energyBurnt(it) ?: 0.0) }
        val top = maxOf(week.maxOf { it.second }, average ?: 0.0, 1.0)
        WidgetCard("progress") {
            RingWithWeek(snapshot, R.drawable.widget_ic_flame, progress, burnt?.let(::whole) ?: "—", "Cal burnt", caption, week,
                reached = { average != null && it >= average }, height = { it / top })
        }
    }
}

// endregion

// region Water

/** Today's water against your target, with buttons that add a set amount. */
class WaterWidget : LeanrWidget() {
    @Composable override fun Content(snapshot: WidgetCalories) {
        val drunk = snapshot.waterToday
        val target = snapshot.waterTarget
        val progress = if (target > 0) minOf(1.0, drunk / target) else 0.0
        val wide = LocalSize.current.width >= 220.dp
        // A sip and a glass. Both are fixed, so they don't follow the glass size in Settings.
        val sip = 100.0; val glass = 250.0
        WidgetCard("today") {
            Row(GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                Column(GlanceModifier.defaultWeight().fillMaxHeight()) {
                    Label(R.drawable.widget_ic_drop, "Water", waterColour)
                    Spacer(GlanceModifier.defaultWeight())
                    Text(Water.text(drunk), style = style(26.sp, FontWeight.Bold), maxLines = 1)
                    Text(if (drunk >= target) "Target reached" else "of ${Water.text(target)}", style = style(12.sp, colour = textSecondary), maxLines = 1)
                    Spacer(GlanceModifier.height(6.dp))
                    Bar(progress, waterColour)
                    if (!wide) { Spacer(GlanceModifier.height(8.dp)); LogButton(waterOption(glass), "+ ${Water.text(glass)}", waterColour) }
                }
                if (wide) {
                    Spacer(GlanceModifier.width(16.dp))
                    Column(GlanceModifier.width(110.dp)) {
                        LogButton(waterOption(sip), "+ ${Water.text(sip)}", waterColour)
                        Spacer(GlanceModifier.height(8.dp))
                        LogButton(waterOption(glass), "+ ${Water.text(glass)}", waterColour)
                    }
                }
            }
        }
    }
}

// endregion

// region Log again

internal val optionKey = ActionParameters.Key<String>("option")

/** The widget's log button: logs straight to the store, so Health Connect and the other widgets follow at once. */
class LogAgainAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val option = parameters[optionKey] ?: return
        AppServices.start(context.applicationContext as android.app.Application)
        withContext(Dispatchers.Main) { AppServices.store.logAgain(option) }
        WidgetSync.updateNow(context)
    }
}

@Composable
private fun LogButton(option: String, title: String, colour: ColorProvider, logged: Boolean = false, iconOnly: Boolean = false) {
    val modifier = GlanceModifier.cornerRadius(20.dp).background(colour).clickable(actionRunCallback<LogAgainAction>(actionParametersOf(optionKey to option)))
    val onColour = DayNight(day = Color.White, night = Color.Black)
    if (iconOnly) {
        Box(modifier.size(30.dp), contentAlignment = Alignment.Center) {
            Icon(if (logged) R.drawable.widget_ic_check else R.drawable.widget_ic_plus, onColour, 18.dp)
        }
    } else {
        Row(modifier.fillMaxWidth().padding(vertical = 7.dp, horizontal = 10.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalAlignment = Alignment.CenterVertically) {
            if (title.startsWith("+").not()) { Icon(if (logged) R.drawable.widget_ic_check else R.drawable.widget_ic_plus, onColour, 16.dp); Spacer(GlanceModifier.width(4.dp)) }
            Text(title, style = style(14.sp, FontWeight.Bold, onColour), maxLines = 1)
        }
    }
}

/** One-tap logging from the Home Screen: your usual meal for this time of day, then pinned foods. */
class LogAgainWidget : LeanrWidget() {
    override val needsQuickLogs: Boolean = true
    @Composable override fun Content(snapshot: WidgetCalories) {
        val options = snapshot.quickLogsNow()
        val accent = snapshot.accentProvider
        val wide = LocalSize.current.width >= 220.dp
        fun calories(o: WidgetQuickLog) = whole(o.calories)
        fun detail(o: WidgetQuickLog) = if (o.isUsual) "Usual ${o.mealTime ?: "meal"}" else "Pinned"
        WidgetCard("today") {
            val first = options.firstOrNull()
            when {
                first == null -> Column(GlanceModifier.fillMaxSize()) {
                    Label(R.drawable.widget_ic_undo, "Log again", accent)
                    Spacer(GlanceModifier.height(6.dp))
                    Text(if (!snapshot.readable) "Open Leanrrr to sync" else "Pin a food or log a few meals in Leanrrr to see them here.",
                        style = style(12.sp, colour = textSecondary))
                }
                !wide -> Column(GlanceModifier.fillMaxSize()) {
                    Label(R.drawable.widget_ic_undo, "Log again", accent)
                    Spacer(GlanceModifier.defaultWeight())
                    Text(first.name, style = style(16.sp, FontWeight.Medium), maxLines = 2)
                    Text("${calories(first)} Cal · ${detail(first)}", style = style(12.sp, colour = textSecondary), maxLines = 1)
                    Spacer(GlanceModifier.defaultWeight())
                    LogButton(first.id, if (first.loggedToday) "Log again" else "Log", accent, logged = first.loggedToday)
                }
                else -> Column(GlanceModifier.fillMaxSize()) {
                    Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Label(R.drawable.widget_ic_undo, "Log again", accent)
                        Spacer(GlanceModifier.defaultWeight())
                        snapshot.remaining?.let { left ->
                            Text(if (left >= 0) "${snapshot.value} Cal left" else "${snapshot.value} Cal over", style = style(12.sp, colour = textSecondary), maxLines = 1)
                        }
                    }
                    options.take(3).forEach { option ->
                        Spacer(GlanceModifier.height(6.dp))
                        Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Column(GlanceModifier.defaultWeight()) {
                                Text(option.name, style = style(14.sp, FontWeight.Bold), maxLines = 1)
                                Text("${calories(option)} Cal · ${detail(option)}", style = style(12.sp, colour = textSecondary), maxLines = 1)
                            }
                            Spacer(GlanceModifier.width(8.dp))
                            LogButton(option.id, "", accent, logged = option.loggedToday, iconOnly = true)
                        }
                    }
                }
            }
        }
    }
}

// endregion

// region Receivers (each declared in the manifest with its res/xml/widget_*.xml)

class CaloriesWidgetReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget: GlanceAppWidget = CaloriesWidget() }
class TargetsWidgetReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget: GlanceAppWidget = TargetsWidget() }
class MacrosWidgetReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget: GlanceAppWidget = MacrosWidget() }
class MacroSummaryWidgetReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget: GlanceAppWidget = MacroSummaryWidget() }
class StreakWidgetReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget: GlanceAppWidget = StreakWidget() }
class LogAgainWidgetReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget: GlanceAppWidget = LogAgainWidget() }
class StepsWidgetReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget: GlanceAppWidget = StepsWidget() }
class CaloriesBurntWidgetReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget: GlanceAppWidget = CaloriesBurntWidget() }
class WaterWidgetReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget: GlanceAppWidget = WaterWidget() }

/** Every widget, for redrawing them all. */
internal val allWidgets: List<GlanceAppWidget> get() = listOf(
    WaterWidget(), LogAgainWidget(), StepsWidget(), CaloriesBurntWidget(), CaloriesWidget(), TargetsWidget(), MacrosWidget(), MacroSummaryWidget(), StreakWidget(),
)

// endregion
