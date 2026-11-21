package com.isaiahgraham.leanrrr.feature.progress

import com.isaiahgraham.leanrrr.data.AppData
import com.isaiahgraham.leanrrr.data.BodyMeasurement
import com.isaiahgraham.leanrrr.data.LogEntry
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.StepLimits
import com.isaiahgraham.leanrrr.data.WeightEntry
import com.isaiahgraham.leanrrr.data.WeightGoal
import com.isaiahgraham.leanrrr.data.dayKey
import com.isaiahgraham.leanrrr.data.kgText
import com.isaiahgraham.leanrrr.data.number
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min

// A port of Weight.swift, BodyMeasurements.swift, Steps.swift and ActiveEnergy.swift: the maths behind the Progress tab.

/** Swift's `rounded()`: to the nearest whole number, halves away from zero (Kotlin's `round` rounds halves to even). */
fun Double.rounded(): Double = if (this >= 0) floor(this + 0.5) else ceil(this - 0.5)

private val wholeNumber = DecimalFormat("#,##0", DecimalFormatSymbols(Locale.US))
/** A whole number with thousands separators: 1250.6 → "1,251". */
fun Double.wholeText(): String = wholeNumber.format(rounded())
fun Int.grouped(): String = wholeNumber.format(this)

internal fun daysBetween(a: LocalDate, b: LocalDate): Int = ChronoUnit.DAYS.between(a, b).toInt()
internal fun Instant.day(zone: ZoneId = ZoneId.systemDefault()): LocalDate = atZone(zone).toLocalDate()

/** A smoothed weight trend that looks past day-to-day water swings, and what it says about maintenance calories. */
object WeightTrend {
    data class Point(
        val date: LocalDate,
        /** What the scale said. */
        val kg: Double,
        val trend: Double,
        /** Kilograms of the reading estimated to be recent water, left out of the trend. */
        val water: Double = 0.0,
    ) {
        /** The reading the trend moves towards: the scale less recent water. */
        val adjusted: Double get() = kg - water
    }

    /** Kilocalories in a kilogram of body weight change, the usual rule of thumb. */
    const val CALORIES_PER_KG = 7700.0
    /** How far each day moves the trend towards that day's weight. */
    const val DAILY_WEIGHT = 0.2
    /** Within this many kilograms of the goal counts as there. */
    const val REACHED_WITHIN = 0.1
    /** A trend that moves less than this per week is treated as flat. */
    const val FLAT_PACE = 0.05
    const val LONGEST_PROJECTION_DAYS = 5 * 365

    /**
     * One point per day with a weigh-in (the day's last), smoothed so each day moves the trend a fifth of the way to the scale
     * (less any water drunk just before). Days between weigh-ins are filled in along a straight line from one reading to the next.
     */
    fun points(entries: List<WeightEntry>, zone: ZoneId = ZoneId.systemDefault()): List<Point> {
        val byDay = entries.filter { it.isValid }.groupBy { it.date.day(zone) }
        val result = mutableListOf<Point>()
        for (day in byDay.keys.sorted()) {
            val entry = byDay.getValue(day).maxBy { it.date }
            val kg = entry.kg; val water = entry.waterKG ?: 0.0; val adjusted = entry.adjustedKG
            val last = result.lastOrNull()
            if (last == null) { result += Point(day, kg, adjusted, water); continue }
            val gap = max(1, daysBetween(last.date, day))
            var trend = last.trend
            for (step in 1..gap) {
                val scale = last.adjusted + (adjusted - last.adjusted) * step / gap
                trend += DAILY_WEIGHT * (scale - trend)
            }
            result += Point(day, kg, trend, water)
        }
        return result
    }

    /** Days of staying at `kg` before a trend at `trend` comes within `within` kg of it. */
    fun daysToCatchUp(from: Double, to: Double, within: Double = 0.2): Int {
        val gap = abs(to - from)
        if (gap <= within) return 0
        return ceil(ln(within / gap) / ln(1 - DAILY_WEIGHT)).toInt()
    }

    /** Why the trend isn't the last weigh-in, when they're 0.1 kg or more apart. */
    fun gapText(point: Point): String? {
        val gap = point.trend - point.adjusted
        if (abs(gap) < 0.1) return null
        val days = daysToCatchUp(point.trend, point.adjusted)
        val reading = if (point.water > 0) "your last weigh-in less recent water" else "your last weigh-in"
        return "Your trend is ${abs(gap).number} kg ${if (gap > 0) "above" else "below"} $reading, because each day moves it only a fifth " +
            "of the way to the scale, so one reading doesn't swing it. If you stay around ${point.adjusted.kgText} kg, it catches up in about $days ${if (days == 1) "day" else "days"}."
    }

    /** Trend change per week over the last `days` days, once weigh-ins span at least a week. */
    fun weeklyChange(points: List<Point>, days: Int = 28, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Double? {
        val start = now.atZone(zone).minusDays(days.toLong()).toInstant()
        val recent = points.filter { !it.date.atStartOfDay(zone).toInstant().isBefore(start) }
        val first = recent.firstOrNull() ?: return null
        val last = recent.last()
        val span = daysBetween(first.date, last.date)
        if (span < 7) return null
        return (last.trend - first.trend) / span * 7
    }

    /** How far you are from a goal weight, and when you'd get there. */
    data class GoalStatus(
        val goal: Double,
        /** Today's trend weight. */
        val current: Double,
        val direction: Direction,
        /** Kilograms still to go, never negative. */
        val remaining: Double,
        /** 0...1, how much of the way from the starting weight you've come. */
        val progress: Double,
        /** Trend change per week over the last four weeks, signed. */
        val weeklyChange: Double?,
        val pace: Pace,
        /** When the goal is reached if the trend keeps going at its current pace. */
        val projected: LocalDate?,
    ) {
        enum class Direction { LOSE, GAIN, REACHED }
        enum class Pace {
            /** Not enough weigh-ins over a week or more to measure a pace. */
            UNKNOWN,
            /** Moving towards the goal, so `projected` is set. */
            TOWARDS,
            AWAY,
            FLAT,
            /** Moving towards it, but more than five years off. */
            TOO_FAR,
        }
    }

    /** Where you stand against a goal weight, from the smoothed trend. Null until there's a weigh-in. */
    fun goalStatus(goal: WeightGoal, points: List<Point>, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): GoalStatus? {
        val current = points.lastOrNull()?.trend ?: return null
        val difference = goal.kg - current
        val remaining = max(0.0, abs(difference))
        val direction = if (remaining <= REACHED_WITHIN) GoalStatus.Direction.REACHED else if (difference < 0) GoalStatus.Direction.LOSE else GoalStatus.Direction.GAIN
        val journey = abs(goal.startKg - goal.kg)
        var progress = 1.0
        if (direction != GoalStatus.Direction.REACHED) {
            val travelled = (goal.startKg - current) * (if (goal.startKg > goal.kg) 1 else -1)
            progress = if (journey > 0) min(1.0, max(0.0, travelled / journey)) else 0.0
        }
        val weekly = weeklyChange(points, now = now, zone = zone)
        val status = GoalStatus(goal.kg, current, direction, remaining, progress, weekly, GoalStatus.Pace.UNKNOWN, null)
        if (direction == GoalStatus.Direction.REACHED || weekly == null) return status
        val towards = if (difference < 0) -weekly else weekly
        if (abs(weekly) < FLAT_PACE) return status.copy(pace = GoalStatus.Pace.FLAT)
        if (towards <= 0) return status.copy(pace = GoalStatus.Pace.AWAY)
        val date = date(remaining, towards, now, zone)
        return if (date != null) status.copy(pace = GoalStatus.Pace.TOWARDS, projected = date) else status.copy(pace = GoalStatus.Pace.TOO_FAR)
    }

    /** The day `kg` kilograms are covered at `kgPerWeek`, or null when that's more than five years away. */
    fun date(toCover: Double, kgPerWeek: Double, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): LocalDate? {
        if (toCover < 0 || kgPerWeek <= 0) return null
        val days = ceil(toCover / kgPerWeek * 7)
        if (!days.isFinite() || days > LONGEST_PROJECTION_DAYS) return null
        return now.day(zone).plusDays(days.toLong())
    }

    /** Calories a day below (losing) or above (gaining) what holds your weight steady, for a pace in kg a week. */
    fun dailyCalorieDifference(kgPerWeek: Double): Double = kgPerWeek * CALORIES_PER_KG / 7

    data class Maintenance(val calories: Double, val loggedDays: Int, val weighInDays: Int)

    /**
     * Calories that would hold your weight steady: average logged intake, less the energy that went into weight change.
     * Needs at least 10 logged days and two weeks of weigh-ins in the last `days` days (today isn't counted; it's unfinished).
     */
    fun maintenance(logs: Map<String, List<LogEntry>>, points: List<Point>, days: Int = 28, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Maintenance? {
        val today = now.day(zone)
        val start = today.minusDays(days.toLong())
        val intakes = (0 until days).map { dayKey(start.plusDays(it.toLong())) }.mapNotNull { key ->
            val entries = logs[key]
            if (entries.isNullOrEmpty()) null else Nutrition(entries.flatMap { it.items }).cal
        }
        val window = points.filter { !it.date.isBefore(start) && it.date.isBefore(today) }
        val first = window.firstOrNull() ?: return null
        val last = window.last()
        val span = daysBetween(first.date, last.date)
        if (intakes.size < 10 || span < 14) return null
        val intake = intakes.sum() / intakes.size
        val calories = intake - (last.trend - first.trend) * CALORIES_PER_KG / span
        if (calories !in 1000.0..6000.0) return null
        return Maintenance(calories, intakes.size, window.size)
    }
}

/**
 * Marks the goal weight as reached when new weigh-ins are what took the trend there. Returns the marked data the first time
 * only, and not for a goal set at the weight you're already at; null otherwise.
 */
fun AppData.markingGoalReached(old: AppData, now: Instant = Instant.now()): AppData? {
    val goal = weightGoal ?: return null
    if (weightLog == old.weightLog || goal.reached != null || abs(goal.startKg - goal.kg) <= WeightTrend.REACHED_WITHIN) return null
    val nowStatus = WeightTrend.goalStatus(goal, WeightTrend.points(weightLog), now)
    val oldStatus = WeightTrend.goalStatus(goal, WeightTrend.points(old.weightLog), now)
    if (nowStatus?.direction != WeightTrend.GoalStatus.Direction.REACHED || oldStatus?.direction == WeightTrend.GoalStatus.Direction.REACHED) return null
    return copy(weightGoal = goal.copy(reached = now))
}

/** A place on the body that can be measured. Stored by `raw`, so a site added later still loads on an older build. */
enum class BodySite(val raw: String, val title: String) {
    WAIST("waist", "Waist"), HIPS("hips", "Hips"), CHEST("chest", "Chest"), NECK("neck", "Neck"), ARM("arm", "Upper arm"), THIGH("thigh", "Thigh");
    companion object { fun fromRaw(raw: String) = entries.firstOrNull { it.raw == raw } }
}

object BodyMeasurements {
    data class Reading(val date: Instant, val cm: Double)

    /** What a site has done: the latest reading, the one before it and the first ever. */
    data class Change(val latest: Reading, val previous: Reading?, val first: Reading?) {
        val sinceLast: Double? get() = previous?.let { latest.cm - it.cm }
        val sinceFirst: Double? get() = first?.let { latest.cm - it.cm }
    }

    /** One reading a day for a site (the day's last), oldest first. */
    fun readings(entries: List<BodyMeasurement>, site: String, zone: ZoneId = ZoneId.systemDefault()): List<Reading> {
        val byDay = mutableMapOf<LocalDate, Reading>()
        for (entry in entries) {
            if (!entry.isValid) continue
            val cm = entry.values[site] ?: continue
            val day = entry.date.day(zone)
            val existing = byDay[day]
            if (existing != null && existing.date >= entry.date) continue
            byDay[day] = Reading(entry.date, cm)
        }
        return byDay.keys.sorted().map { byDay.getValue(it) }
    }

    fun change(readings: List<Reading>): Change? {
        val latest = readings.lastOrNull() ?: return null
        if (readings.size < 2) return Change(latest, null, null)
        return Change(latest, readings[readings.size - 2], readings[0])
    }

    /** Sites with at least one reading: the standard ones in their usual order, then any others. */
    fun sites(entries: List<BodyMeasurement>): List<String> {
        val present = entries.filter { it.isValid }.flatMap { it.values.keys }.toSet()
        val standard = BodySite.entries.map { it.raw }.filter { it in present }
        return standard + (present - standard.toSet()).sorted()
    }

    fun title(site: String): String = BodySite.fromRaw(site)?.title
        ?: site.split(" ").joinToString(" ") { word -> word.lowercase().replaceFirstChar { it.uppercase() } }

    /** "−3.5 cm", "+1 cm", "no change". */
    fun signed(cm: Double): String {
        val rounded = (cm * 10).rounded() / 10
        if (rounded == 0.0) return "no change"
        return (if (rounded > 0) "+" else "−") + abs(rounded).number + " cm"
    }
}

/** Daily steps. The counts come from Health Connect and are only held in memory; only the goal is Leanrrr's own. */
object Steps {
    const val DEFAULT_GOAL = 8000.0
    val GOAL_RANGE = StepLimits.GOAL_RANGE

    fun goal(data: AppData): Double = data.stepGoal ?: DEFAULT_GOAL

    /** 6420 → "6,420". */
    fun text(steps: Double): String = steps.wholeText()

    /** How far through the goal, from 0 to 1. */
    fun progress(steps: Double, goal: Double): Double = if (goal > 0) min(1.0, max(0.0, steps / goal)) else 0.0

    data class Summary(val average: Double?, val countedDays: Int, val daysMet: Int, val total: Double, val best: Double?)

    /** Steps across the given days. A day with nothing recorded isn't counted, so a phone left at home doesn't pull the average down. */
    fun summary(steps: Map<String, Double>, days: List<String>, goal: Double): Summary {
        val counted = days.mapNotNull { steps[it] }.filter { it > 0 }
        val total = counted.sum()
        return Summary(if (counted.isEmpty()) null else total / counted.size, counted.size, counted.count { it >= goal }, total, counted.maxOrNull())
    }
}

/** Calories burnt: the active energy Health Connect holds for each day. Only held in memory, never saved. */
object ActiveEnergy {
    /** 412.4 → "412". */
    fun text(calories: Double): String = calories.wholeText()

    data class Summary(val average: Double?, val countedDays: Int, val total: Double, val best: Double?)

    fun summary(energy: Map<String, Double>, days: List<String>): Summary {
        val counted = days.mapNotNull { energy[it] }.filter { it > 0 }
        val total = counted.sum()
        return Summary(if (counted.isEmpty()) null else total / counted.size, counted.size, total, counted.maxOrNull())
    }

    /** The average over the fortnight before `date`, not counting `date` itself. Null until three days have anything recorded. */
    fun recentAverage(energy: Map<String, Double>, before: LocalDate): Double? {
        val days = (1..14).mapNotNull { energy[dayKey(before.minusDays(it.toLong()))] }.filter { it > 0 }
        return if (days.size >= 3) days.sum() / days.size else null
    }
}
