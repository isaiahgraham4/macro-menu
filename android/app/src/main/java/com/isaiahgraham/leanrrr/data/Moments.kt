package com.isaiahgraham.leanrrr.data

import com.isaiahgraham.leanrrr.feature.progress.TrackingStreak
import com.isaiahgraham.leanrrr.feature.progress.WeeklyReview
import com.isaiahgraham.leanrrr.feature.progress.WeightTrend
import com.isaiahgraham.leanrrr.feature.progress.YearReview
import com.isaiahgraham.leanrrr.feature.progress.grouped
import com.isaiahgraham.leanrrr.feature.progress.markingGoalReached
import com.isaiahgraham.leanrrr.feature.progress.wholeText
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.WeekFields
import java.util.Locale

// A port of Moments.swift: what's worth marking, worked out by comparing the data before and after a change.

/** Something worth stopping to mark, shown over the app for a few seconds. The goal weight gets the whole screen. */
sealed interface Moment {
    data class Hit(val name: String, val value: Double, val target: Double, val unit: String)

    data class Targets(val hits: List<Hit>) : Moment
    /** Every tracked target on target in one day; `count` is how many. */
    data class AllTargets(val count: Int) : Moment
    data class Streak(val days: Int) : Moment
    /** A missed day that didn't end the streak, now that logging has picked up again. */
    data class StreakSaved(val days: Int) : Moment
    data class Meals(val count: Int) : Moment
    data class Steps(val steps: Double, val goal: Double) : Moment
    /** How far the trend has moved towards a goal weight since it was set. */
    data class WeighIn(val moved: Double, val losing: Boolean, val progress: Double, val remaining: Double, val goal: Double) : Moment
    data class GoalReached(val goal: WeightGoal) : Moment
    /** Last week, on the first open of a new one. */
    data class Week(val logged: Int, val onTarget: Int, val protein: Int) : Moment
    /** The year's review, once it's ready in December. */
    data class Year(val year: Int) : Moment

    /** What a moment says, on its card and on the image it shares. `icon` is the SF Symbol name; the UI maps it. */
    data class Copy(
        val icon: String,
        val title: String,
        /** A number that counts up on the card: its value, the step it counts in, and its unit. */
        val figure: Figure? = null,
        val detail: String,
        val progress: Double? = null,
        /** Worth a picture for a story. */
        val shareable: Boolean,
    )
    data class Figure(val value: Double, val step: Double, val unit: String)

    val copy: Copy
        get() = when (this) {
            is Targets -> Copy("target", if (hits.size == 1) "${hits[0].name} target hit" else "${hits.size} targets hit",
                detail = if (hits.size == 1) "${hits[0].value.number} of ${hits[0].target.number} ${hits[0].unit}" else listText(hits.map { it.name }),
                shareable = false)
            is AllTargets -> Copy("checkmark.seal.fill", "Every target hit", detail = "All $count for the day. That's the whole job.", shareable = true)
            is Streak -> Copy("flame.fill", "$days days in a row", detail = "Logging is becoming a habit. Keep it going.", shareable = true)
            is StreakSaved -> Copy("shield.fill", "Streak saved", detail = "One missed day didn't end your $days days.", shareable = false)
            is Meals -> Copy("fork.knife", if (count == 1) "First meal logged" else "${count.grouped()} meals logged",
                detail = if (count == 1) "That's the hard part done." else "It all adds up.", shareable = count > 1)
            is Steps -> Copy("figure.walk", "Step goal hit", detail = "${steps.wholeText()} steps today, past your ${goal.wholeText()}.", shareable = true)
            is WeighIn -> Copy("scalemass.fill", if (losing) "You've lost" else "You've gained", Figure(moved, 0.1, "kg"),
                "${remaining.number} kg to go until ${goal.number} kg", progress, shareable = true)
            is GoalReached -> Copy("party.popper.fill", "Goal reached", Figure(kotlin.math.abs(goal.startKg - goal.kg), 0.1, "kg"),
                "${if (goal.kg < goal.startKg) "lost" else "gained"} since you started at ${goal.startKg.number} kg. You're at ${goal.kg.number} kg.",
                shareable = true)
            is Week -> Copy("calendar", "$logged of 7 days logged",
                detail = "On or under calories $onTarget ${if (onTarget == 1) "day" else "days"}, protein hit $protein. Tap for your review.", shareable = true)
            is Year -> Copy("sparkles", "Your $year is ready", detail = "Tap to see your year in Leanrrr.", shareable = false)
        }

    /** Tapping the card opens a review rather than closing it. */
    val opensReview: Boolean get() = this is Week || this is Year

    companion object {
        /** Days in a row of logging that are worth marking. */
        val streaks = listOf(3, 7, 14, 30, 60, 100, 180, 365)
        /** Meals logged in all that are worth marking. */
        val mealCounts = listOf(1, 10, 25, 50, 100, 250, 500, 1000, 2500)
        /** More new entries than this at once is a restored backup, not a meal. */
        const val MOST_NEW_ENTRIES = 12
        /** An at-most target counts as hit from this share of it, up to the target itself. */
        private const val CLOSE_TO_LIMIT = 0.95
        /** A week with fewer logged days than this isn't worth a card. */
        const val FEWEST_WEEK_DAYS = 3

        /** Whether a daily figure is on target: at or past an at-least target, or close under an at-most one. */
        fun onTarget(value: Double, target: Double, minimum: Boolean): Boolean =
            if (minimum) value >= target else value >= target * CLOSE_TO_LIMIT && value <= target
    }
}

/** "Protein, Carbs and Fat", as Swift's list formatting writes it. */
private fun listText(items: List<String>): String = when (items.size) {
    0 -> ""
    1 -> items[0]
    else -> items.dropLast(1).joinToString(", ") + " and " + items.last()
}

val AppData.mealsLogged: Int get() = logs.values.sumOf { it.size }

private val AppData.activeGoals: Goals get() = goalSets.firstOrNull { it.id == activeGoal } ?: goalSets[0]

/**
 * What a change has just earned, biggest first, and the data with each one marked in `celebrated` so nothing is earned twice
 * (AppData.earnMoments in Moments.swift). The goal weight's `reached` date is set here too.
 */
fun AppData.earning(old: AppData, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Pair<AppData, List<Moment>> {
    val earned = mutableListOf<Moment>()
    var state = this
    state.markingGoalReached(old, now)?.let { marked -> state = marked; marked.weightGoal?.let { earned += Moment.GoalReached(it) } }
    val marked = (state.celebrated ?: emptySet()).toMutableSet()
    val todayDate = now.atZone(zone).toLocalDate()
    val today = dayKey(todayDate); val todayMark = "day:$today:"
    val hits = state.targetHits(old, today).filter { marked.add(todayMark + it.name) }
    // The last target of the day gets the bigger card instead of its own.
    val all = state.allTargetsHit(today)
    if (all != null && hits.isNotEmpty() && marked.add(todayMark + "All")) earned += Moment.AllTargets(all)
    else if (hits.isNotEmpty()) earned += Moment.Targets(hits)
    val before = old.mealsLogged; val after = state.mealsLogged
    if (after > before && after - before <= Moment.MOST_NEW_ENTRIES) {
        val days = TrackingStreak.days(state)
        val walk = TrackingStreak.walk(days, todayDate)
        val streak = walk.first; val streakBefore = TrackingStreak.count(TrackingStreak.days(old), todayDate)
        // The first log today after a missed day is what shows the streak survived it.
        val yesterday = dayKey(todayDate.minusDays(1))
        if ((old.logs[today] ?: emptyList()).isEmpty() && yesterday in walk.second && streak >= Moment.streaks[0] && marked.add(todayMark + "Saved")) {
            earned += Moment.StreakSaved(streak)
        }
        Moment.streaks.lastOrNull { streakBefore < it && streak >= it }?.let { if (marked.add("streak:$it")) earned += Moment.Streak(it) }
        Moment.mealCounts.lastOrNull { before < it && after >= it }?.let { if (marked.add("meals:$it")) earned += Moment.Meals(it) }
    }
    // Yesterday's targets no longer matter, so only milestones are kept for good.
    val kept = marked.filter { !it.startsWith("day:") || it.startsWith(todayMark) }.toSet()
    if (kept.isNotEmpty() || state.celebrated != null) state = state.copy(celebrated = kept)
    return Pair(state, earned)
}

/** Moments a change has earned, comparing the data before and after it. [AppStore.change] uses [earning] directly so the marks are saved with the change. */
fun earnMoments(new: AppData, old: AppData): List<Moment> = new.earning(old).second

/** The step goal passed today, as new counts come in from Health Connect. A count already past the goal when it first arrived doesn't count. */
fun stepsReachedMoment(before: Map<String, Double>, after: Map<String, Double>, goal: Double, day: String): Moment? {
    val now = after[day] ?: return null
    val earlier = before[day] ?: return null
    return if (now >= goal && earlier < goal) Moment.Steps(now, goal) else null
}

/** Last week's card, the first time Leanrrr opens in a new week, when enough of it was logged. Null otherwise or once shown. */
fun AppData.offerWeek(now: LocalDate = LocalDate.now(), locale: Locale = Locale.getDefault()): Pair<AppData, Moment>? {
    val weekStart = now.with(WeekFields.of(locale).dayOfWeek(), 1)
    val mark = "week:${dayKey(weekStart)}"
    if ((celebrated ?: emptySet()).contains(mark)) return null
    val review = WeeklyReview.make(this, activeGoals, ending = now.minusDays(1))
    if (review.loggedDays < Moment.FEWEST_WEEK_DAYS) return null
    return Pair(copy(celebrated = (celebrated ?: emptySet()) + mark), Moment.Week(review.loggedDays, review.calorieDays, review.proteinDays))
}

/** This year's review card, the first open once it's ready, with enough of the year logged. Null otherwise or once shown. */
fun AppData.offerYear(now: LocalDate = LocalDate.now()): Pair<AppData, Moment>? {
    val year = YearReview.showing(now) ?: return null
    val mark = "year:$year"
    if ((celebrated ?: emptySet()).contains(mark) || YearReview.make(this, year).days < YearReview.FEWEST_DAYS) return null
    return Pair(copy(celebrated = (celebrated ?: emptySet()) + mark), Moment.Year(year))
}

/** The keys of the daily targets that are tracked: the macros, and anything else with an at-least target. */
private fun trackedTargets(goals: Goals): List<Triple<String, Double, Boolean>> = nutrientNames.mapNotNull { nutrient ->
    val minimum = nutrient.key in goals.minimums
    val target = goals.values[nutrient.key]
    if (nutrient.key == "cal" || !(nutrient.key in listOf("p", "c", "f") || minimum) || target == null) null else Triple(nutrient.key, target, minimum)
}

/** How many targets there are when every one of them is on target today, with at least two to hit. Null otherwise. */
private fun AppData.allTargetsHit(day: String): Int? {
    val tracked = trackedTargets(activeGoals)
    val total = Nutrition((logs[day] ?: emptyList()).flatMap { it.items })
    if (tracked.size < 2 || !tracked.all { Moment.onTarget(total.value(it.first), it.second, it.third) }) return null
    return tracked.size
}

/** Macro targets, other at-least targets and water that this change has brought onto target today. */
private fun AppData.targetHits(old: AppData, day: String): List<Moment.Hit> {
    val total = Nutrition((logs[day] ?: emptyList()).flatMap { it.items })
    val earlier = Nutrition((old.logs[day] ?: emptyList()).flatMap { it.items })
    val hits = trackedTargets(activeGoals).mapNotNull { (key, target, minimum) ->
        val nutrient = nutrientNames.firstOrNull { it.key == key }
        if (total.value(key) > earlier.value(key) && Moment.onTarget(total.value(key), target, minimum) &&
            !Moment.onTarget(earlier.value(key), target, minimum) && nutrient != null) Moment.Hit(nutrient.label, total.value(key), target, nutrient.unit) else null
    }.toMutableList()
    val water = water?.get(day) ?: 0.0; val waterBefore = old.water?.get(day) ?: 0.0; val waterTarget = waterTarget ?: 2000.0
    if (water >= waterTarget && waterBefore < waterTarget) hits += Moment.Hit("Water", water, waterTarget, "mL")
    return hits
}

/** How a new weigh-in stands against the goal weight. Null with no goal, once there, or with nothing gained on it yet. */
val AppData.weighInMoment: Moment?
    get() {
        val goal = weightGoal ?: return null
        val status = WeightTrend.goalStatus(goal, WeightTrend.points(weightLog)) ?: return null
        if (status.direction == WeightTrend.GoalStatus.Direction.REACHED) return null
        val losing = goal.kg < goal.startKg
        val moved = ((goal.startKg - status.current) * (if (losing) 1 else -1)).tenth
        if (moved <= 0) return null
        return Moment.WeighIn(moved, losing, status.progress, status.remaining, goal.kg)
    }

/** A milestone on the achievements shelf: earned, or the next one to reach. */
data class Achievement(
    val group: Group,
    val moment: Moment,
    val earned: Boolean,
    /** How far there is to go, for one not earned yet. */
    val left: String? = null,
    val progress: Double? = null,
) {
    enum class Group(val title: String) { STREAKS("Streaks"), MEALS("Meals logged"), WEIGHT("Weight") }
}

/** Everything earned so far and the next of each kind, worked out from what's logged. */
fun AppData.achievements(now: LocalDate = LocalDate.now()): List<Achievement> {
    val days = TrackingStreak.days(this)
    val best = TrackingStreak.best(days); val current = TrackingStreak.count(days, now); val meals = mealsLogged
    fun ladder(group: Achievement.Group, steps: List<Int>, reached: Int, towards: Int, unit: String, moment: (Int) -> Moment): List<Achievement> {
        val shelf = steps.filter { reached >= it }.map { Achievement(group, moment(it), true) }.toMutableList()
        steps.firstOrNull { reached < it && towards < it }?.let { next ->
            shelf += Achievement(group, moment(next), false, "${(next - towards).grouped()} $unit to go", towards.toDouble() / next)
        }
        return shelf
    }
    val all = (ladder(Achievement.Group.STREAKS, Moment.streaks, best, current, "days") { Moment.Streak(it) } +
        ladder(Achievement.Group.MEALS, Moment.mealCounts, meals, meals, "meals") { Moment.Meals(it) }).toMutableList()
    val goal = weightGoal
    val status = goal?.let { WeightTrend.goalStatus(it, WeightTrend.points(weightLog)) }
    if (goal != null && status != null) {
        val reached = goal.reached != null || status.direction == WeightTrend.GoalStatus.Direction.REACHED
        all += Achievement(Achievement.Group.WEIGHT, Moment.GoalReached(goal), reached,
            if (reached) null else "${status.remaining.number} kg to go", if (reached) null else status.progress)
    }
    return all
}
