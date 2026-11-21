package com.isaiahgraham.leanrrr.feature.today

import com.isaiahgraham.leanrrr.data.AppData
import com.isaiahgraham.leanrrr.data.Goals
import com.isaiahgraham.leanrrr.data.LogEntry
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.QuickLog
import com.isaiahgraham.leanrrr.data.combined
import com.isaiahgraham.leanrrr.data.dayKey
import com.isaiahgraham.leanrrr.data.isDayKey
import com.isaiahgraham.leanrrr.data.newId
import com.isaiahgraham.leanrrr.data.number
import java.time.Instant
import java.time.LocalDate
import kotlin.math.roundToLong

/**
 * Meals set out ahead of time, by day (MealPlan.swift). A plan counts towards nothing until each meal is logged, which moves
 * it from the plan into the log with the time it was eaten.
 */
object MealPlan {
    /** How far ahead you can plan, counting today. */
    const val DAYS_AHEAD = 7

    fun entries(data: AppData, day: String): List<LogEntry> = data.plans?.get(day) ?: emptyList()

    /** Days you can plan for: today and the six after it. */
    fun days(from: LocalDate = LocalDate.now()): List<LocalDate> = (0 until DAYS_AHEAD).map { from.plusDays(it.toLong()) }

    /** Adds a meal to a day's plan, with fresh item IDs so it's independent of where it came from. */
    fun add(items: List<Portion>, name: String, mealTime: MealTime, day: String, data: AppData): AppData {
        if (!isDayKey(day) || items.isEmpty()) return data
        val plans = (data.plans ?: emptyMap()).toMutableMap()
        plans[day] = (plans[day] ?: emptyList()) + LogEntry(name = name, items = QuickLog.copies(combined(items)), mealTime = mealTime)
        return data.copy(plans = plans)
    }

    fun remove(id: String, day: String, data: AppData): AppData {
        val plans = data.plans?.toMutableMap() ?: return data
        plans[day]?.let { list -> plans[day] = list.filter { it.id != id } }
        if (plans[day]?.isEmpty() == true) plans.remove(day)
        return data.copy(plans = plans.ifEmpty { null })
    }

    /**
     * Moves planned meals into the log for that day, stamped `time`, and takes them off the plan.
     * The day's targets are kept as they were, like any other logging.
     */
    fun log(ids: Set<String>, day: String, time: Instant, goals: Goals, data: AppData): AppData {
        val chosen = entries(data, day).filter { it.id in ids }
        if (chosen.isEmpty()) return data
        var state = data
        for (planned in chosen) {
            val entry = planned.copy(id = newId(), time = time, items = QuickLog.copies(planned.items))
            state = state.copy(logs = state.logs + (day to ((state.logs[day] ?: emptyList()) + entry)))
            state = remove(planned.id, day, state)
        }
        if (state.dayGoals[day] == null) state = state.copy(dayGoals = state.dayGoals + (day to goals))
        return state
    }

    /** Drops plans for days already gone. */
    fun pruned(data: AppData, now: LocalDate = LocalDate.now()): AppData {
        val plans = data.plans ?: return data
        val today = dayKey(now)
        val kept = plans.filter { it.key >= today && it.value.isNotEmpty() }
        return data.copy(plans = kept.ifEmpty { null })
    }

    /** What a day's plan adds up to against its targets: "1,650 of 2,200 Cal · 120 of 150 g protein". */
    fun summary(entries: List<LogEntry>, goals: Goals): String {
        val total = Nutrition(entries.flatMap { it.items })
        val cal = "${total.cal.whole.number}${goals.values["cal"]?.let { " of ${it.whole.number}" } ?: ""} Cal"
        val protein = "${total.p.whole.number}${goals.values["p"]?.let { " of ${it.whole.number}" } ?: ""} g protein"
        return "$cal · $protein"
    }

    /** The day as it would be with the plan eaten, for working out what's left to plan around. */
    fun asLogged(data: AppData, day: String): AppData =
        data.copy(logs = data.logs + (day to ((data.logs[day] ?: emptyList()) + entries(data, day))))
}

/** Rounded to a whole number, like Swift's `.rounded()`. */
internal val Double.whole: Double get() = if (isFinite()) roundToLong().toDouble() else this
