package com.isaiahgraham.leanrrr.feature.progress

import com.isaiahgraham.leanrrr.data.AppData
import com.isaiahgraham.leanrrr.data.AppStore
import com.isaiahgraham.leanrrr.data.CheckInLimits
import com.isaiahgraham.leanrrr.data.CheckInRecord
import com.isaiahgraham.leanrrr.data.Goals
import com.isaiahgraham.leanrrr.data.dayKey
import com.isaiahgraham.leanrrr.data.kgText
import com.isaiahgraham.leanrrr.data.replace
import java.time.Instant
import java.time.ZoneId
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * A weekly check-in, like an adaptive coach (CheckIn.swift): maintenance measured from the last four weeks of logging and
 * weigh-ins, the pace you want to lose or gain at, and the calorie target that gets you there. Protein stays put; carbs and
 * fat take up the change in the same proportions as before.
 */
object CheckIn {
    /** Paces offered, in kg a week. */
    val paces = listOf(-1.0, -0.75, -0.5, -0.25, 0.0, 0.25, 0.5)
    val paceRange = CheckInLimits.PACE_RANGE
    val calorieRange = CheckInLimits.CALORIE_RANGE
    /** The lowest target a check-in will suggest. */
    const val LOWEST = 1200.0
    /** The most one check-in moves the calorie target, so a noisy week can't swing it far. */
    const val LARGEST_STEP = 300.0
    /** Days between check-ins. */
    const val INTERVAL = 7L

    fun paceText(pace: Double): String {
        if (pace == 0.0) return "Maintain"
        return "${if (pace < 0) "Lose" else "Gain"} ${abs(pace).kgText} kg a week"
    }

    /** The pace you set, or one that fits your weight goal: losing half a kilo a week, or gaining a quarter. */
    fun pace(data: AppData, now: Instant = Instant.now()): Double {
        data.checkInPace?.let { return it }
        val goal = data.weightGoal ?: return 0.0
        val status = WeightTrend.goalStatus(goal, WeightTrend.points(data.weightLog), now) ?: return 0.0
        return when (status.direction) {
            WeightTrend.GoalStatus.Direction.LOSE -> -0.5
            WeightTrend.GoalStatus.Direction.GAIN -> 0.25
            WeightTrend.GoalStatus.Direction.REACHED -> 0.0
        }
    }

    /** The most recent check-in. */
    fun last(data: AppData): CheckInRecord? = (data.checkIns ?: emptyList()).maxByOrNull { it.date }

    /** When the next check-in is due: a week after the last one, or null if there hasn't been one. */
    fun nextDate(data: AppData, zone: ZoneId = ZoneId.systemDefault()): Instant? {
        val last = last(data) ?: return null
        return last.date.day(zone).plusDays(INTERVAL).atStartOfDay(zone).toInstant()
    }

    fun isDue(data: AppData, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Boolean {
        val next = nextDate(data, zone) ?: return true
        return !now.isBefore(next)
    }

    /** How close you are to having enough: 10 logged days and two weeks of weigh-ins in the last four weeks. */
    data class Readiness(val loggedDays: Int, val weighInSpan: Int) {
        val daysNeeded: Int get() = max(0, 10 - loggedDays)
        val weighInDaysNeeded: Int get() = max(0, 14 - weighInSpan)
    }

    fun readiness(data: AppData, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Readiness {
        val today = now.day(zone)
        val start = today.minusDays(28)
        val logged = (0 until 28L).map { dayKey(start.plusDays(it)) }.count { !(data.logs[it] ?: emptyList()).isEmpty() }
        val window = WeightTrend.points(data.weightLog, zone).filter { !it.date.isBefore(start) && it.date.isBefore(today) }
        val span = if (window.isEmpty()) 0 else daysBetween(window.first().date, window.last().date)
        return Readiness(logged, span)
    }

    data class Suggestion(
        val maintenance: Double,
        val loggedDays: Int,
        /** Trend change per week over the last four weeks, signed. */
        val weeklyChange: Double?,
        val trendWeight: Double?,
        val pace: Double,
        val currentCalories: Double?,
        /** The new calorie target, and the full set of targets that goes with it. */
        val calories: Double,
        val values: Map<String, Double>,
        /** True when the target was held to `LARGEST_STEP` from the current one, or to `LOWEST`. */
        val limitedByStep: Boolean,
        val limitedByFloor: Boolean,
        /** True when the pace is more than 1% of body weight a week. */
        val paceIsFast: Boolean,
    ) {
        val change: Double? get() = currentCalories?.let { calories - it }
    }

    /** The suggested targets for a pace. Null until maintenance can be measured. */
    fun suggestion(data: AppData, goals: Goals, pace: Double, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Suggestion? {
        val points = WeightTrend.points(data.weightLog, zone)
        val measured = WeightTrend.maintenance(data.logs, points, now = now, zone = zone) ?: return null
        val current = goals.values["cal"]
        var calories = measured.calories + WeightTrend.dailyCalorieDifference(pace)
        var limitedByStep = false; var limitedByFloor = false
        if (current != null && abs(calories - current) > LARGEST_STEP) {
            calories = current + if (calories > current) LARGEST_STEP else -LARGEST_STEP
            limitedByStep = true
        }
        if (calories < LOWEST) { calories = LOWEST; limitedByFloor = true }
        calories = min(calorieRange.endInclusive, (calories / 10).rounded() * 10)
        val trend = points.lastOrNull()?.trend
        val fast = trend?.let { abs(pace) > it * 0.01 } ?: false
        return Suggestion(measured.calories, measured.loggedDays, WeightTrend.weeklyChange(points, now = now, zone = zone), trend, pace, current,
            calories, values(goals, calories), limitedByStep, limitedByFloor, fast)
    }

    /** Targets for a new calorie figure. Protein is kept; carbs and fat share what's left in the same proportion as now. */
    fun values(goals: Goals, calories: Double): Map<String, Double> {
        val values = mutableMapOf("cal" to calories)
        val c = goals.values["c"] ?: return values
        val f = goals.values["f"] ?: return values
        val protein = goals.values["p"] ?: 0.0
        val before = c * 4 + f * 9; val after = calories - protein * 4
        if (before <= 0 || after <= 0) return values
        val scale = after / before
        values["c"] = (c * scale).rounded()
        values["f"] = (f * scale).rounded()
        return values
    }

    /** "You're losing 0.32 kg a week. Your goal is to lose 0.5 kg a week." and so on. */
    fun headline(suggestion: Suggestion): String {
        val pace = suggestion.pace
        val asked = if (pace == 0.0) "to hold steady" else "${abs(pace).kgText} kg a week"
        val weekly = suggestion.weeklyChange ?: return "Your goal is ${if (pace == 0.0) "to maintain" else asked}."
        val amount = abs(weekly).kgText
        val moving = if (abs(weekly) < WeightTrend.FLAT_PACE) "Your weight is holding steady" else "You're ${if (weekly < 0) "losing" else "gaining"} $amount kg a week"
        return if (pace == 0.0) "$moving. Your goal is to maintain." else "$moving. Your goal is to ${if (pace < 0) "lose" else "gain"} $asked."
    }

    /** Notes a check-in. Only the last 52 are kept. */
    fun record(suggestion: Suggestion, accepted: Boolean, data: AppData, now: Instant = Instant.now()): AppData {
        val record = CheckInRecord(date = now, weeklyChange = suggestion.weeklyChange, maintenance = suggestion.maintenance, pace = suggestion.pace,
            previousCalories = suggestion.currentCalories, calories = suggestion.calories, accepted = accepted)
        return data.copy(checkIns = ((data.checkIns ?: emptyList()) + record).sortedBy { it.date }.takeLast(52))
    }
}

/** Uses a check-in's targets, or keeps the current ones, and notes the check-in either way. */
fun AppStore.finishCheckIn(suggestion: CheckIn.Suggestion, accept: Boolean): Boolean {
    val activeID = goals.id
    return change(undo = if (accept) "Updated your targets" else null) { state ->
        val noted = CheckIn.record(suggestion, accept, state).copy(checkInPace = suggestion.pace)
        val index = noted.goalSets.indexOfFirst { it.id == activeID }
        if (!accept || index < 0) return@change noted
        val updated = noted.goalSets[index].copy(values = noted.goalSets[index].values + suggestion.values)
        noted.copy(goalSets = noted.goalSets.replace(index, updated), activeGoal = activeID,
            dayGoals = noted.dayGoals + (dayKey(Instant.now()) to updated))
    }
}

fun AppStore.setCheckInPace(pace: Double): Boolean {
    if (pace !in CheckIn.paceRange) return false
    return change { it.copy(checkInPace = pace) }
}

/** Saves the daily step goal if it's within range. */
fun AppStore.setStepGoal(goal: Double): Boolean {
    if (goal !in Steps.GOAL_RANGE) return false
    return change { it.copy(stepGoal = goal) }
}
