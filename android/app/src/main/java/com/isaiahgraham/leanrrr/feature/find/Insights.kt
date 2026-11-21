package com.isaiahgraham.leanrrr.feature.find

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Fastfood
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.NightsStay
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.WbTwilight
import androidx.compose.ui.graphics.vector.ImageVector
import com.isaiahgraham.leanrrr.data.AppData
import com.isaiahgraham.leanrrr.data.Goals
import com.isaiahgraham.leanrrr.data.LogEntry
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.dayKey
import com.isaiahgraham.leanrrr.data.number
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.TextStyle
import java.util.Locale
import kotlin.math.abs

/**
 * Short observations from your own log over the Progress range (Insights.swift): "Weekends average 600 Cal more than weekdays".
 * Each only appears when there's enough to go on and the difference is big enough to matter, strongest first.
 */
object Insights {
    data class Insight(val id: String, val text: String, val strength: Double) {
        /** The icon for this kind of observation (the SF Symbol's closest match). */
        val icon: ImageVector
            get() = when (id) {
                "weekends" -> Icons.Filled.CalendarMonth
                "breakfast" -> Icons.Filled.WbTwilight
                "weekday" -> Icons.Filled.BarChart
                "late" -> Icons.Filled.NightsStay
                "takeaway" -> Icons.Filled.Fastfood
                "over-food" -> Icons.Filled.ErrorOutline
                "low-protein" -> Icons.Filled.Restaurant
                else -> Icons.Filled.Lightbulb
            }
    }

    private class Day(val date: LocalDate, val calories: Double, val protein: Double, val calorieTarget: Double?, val proteinTarget: Double?, val entries: List<LogEntry>) {
        val hitProtein: Boolean? get() = proteinTarget?.let { protein >= it }
        val overCalories: Boolean? get() = calorieTarget?.let { calories > it }
        val isWeekend: Boolean get() = date.dayOfWeek == DayOfWeek.SATURDAY || date.dayOfWeek == DayOfWeek.SUNDAY
    }

    fun make(data: AppData, goals: Goals, days: Int, ending: LocalDate = LocalDate.now(), limit: Int = 4): List<Insight> {
        val logged = (0 until days).mapNotNull { offset ->
            val date = ending.minusDays(offset.toLong())
            val key = dayKey(date)
            val entries = data.logs[key]?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
            val total = Nutrition(entries.flatMap { it.items })
            val target = data.dayGoals[key] ?: goals
            Day(date, total.cal, total.p, target.values["cal"], target.values["p"], entries)
        }
        if (logged.size < 5) return emptyList()
        val found = listOfNotNull(weekends(logged), breakfast(logged), biggestDay(logged), lateEating(logged), takeaway(logged),
            overTargetFood(logged), lowProteinMeal(logged))
        return found.sortedByDescending { it.strength }.take(limit)
    }

    private fun average(values: List<Double>): Double? = if (values.isEmpty()) null else values.sum() / values.size
    /** To the nearest 10, which is as close as a pattern can honestly be. */
    fun calories(value: Double): String = ((value / 10).rounded() * 10).number
    /** To the nearest 5%. */
    fun percent(value: Double): String = "${((value * 20).rounded() * 5).toInt()}%"

    const val WEEKEND_GAP = 150.0

    private fun weekends(days: List<Day>): Insight? {
        val weekend = days.filter { it.isWeekend }.map { it.calories }
        val weekday = days.filter { !it.isWeekend }.map { it.calories }
        if (weekend.size < 2 || weekday.size < 3) return null
        val a = average(weekend) ?: return null; val b = average(weekday) ?: return null
        if (abs(a - b) < WEEKEND_GAP) return null
        return Insight("weekends", "Weekends average ${calories(abs(a - b))} Cal ${if (a > b) "more" else "less"} than weekdays.", abs(a - b) / 100)
    }

    private fun breakfast(days: List<Day>): Insight? {
        val counted = days.filter { it.hitProtein != null }
        val with = counted.filter { d -> d.entries.any { it.mealTime == MealTime.BREAKFAST } }
        val without = counted.filter { d -> d.entries.none { it.mealTime == MealTime.BREAKFAST } }
        if (with.size < 3 || without.size < 3) return null
        val a = with.count { it.hitProtein == true }.toDouble() / with.size
        val b = without.count { it.hitProtein == true }.toDouble() / without.size
        if (abs(a - b) < 0.2) return null
        return Insight("breakfast", "Days you log breakfast, you hit your protein target ${percent(a)} of the time, against ${percent(b)} without.", abs(a - b) * 10)
    }

    /** Swift's weekday numbers: 1 is Sunday. */
    private fun weekdayNumber(date: LocalDate): Int = date.dayOfWeek.value % 7 + 1

    private fun biggestDay(days: List<Day>): Insight? {
        val overall = average(days.map { it.calories }) ?: return null
        val byWeekday = days.groupBy { weekdayNumber(it.date) }.filter { it.value.size >= 2 }
        if (byWeekday.size < 3) return null
        val top = byWeekday.mapValues { (_, list) -> average(list.map { it.calories })!! }.entries
            .sortedWith(compareByDescending<Map.Entry<Int, Double>> { it.value }.thenBy { it.key }).first()
        if (top.value - overall < 250) return null
        val dow = DayOfWeek.of(if (top.key == 1) 7 else top.key - 1)
        val name = dow.getDisplayName(TextStyle.FULL_STANDALONE, Locale.getDefault())
        return Insight("weekday", "${name}s are your biggest day, averaging ${calories(top.value)} Cal.", (top.value - overall) / 120)
    }

    private fun lateEating(days: List<Day>): Insight? {
        val entries = days.flatMap { it.entries }
        val total = entries.sumOf { Nutrition(it.items).cal }
        if (total <= 0) return null
        val late = entries.filter { it.time.atZone(ZoneId.systemDefault()).hour >= 20 }.sumOf { Nutrition(it.items).cal }
        val share = late / total
        if (share < 0.25) return null
        return Insight("late", "${percent(share)} of your calories come after 8 pm.", share * 8)
    }

    private fun takeaway(days: List<Day>): Insight? {
        fun fromRestaurant(day: Day) = day.entries.flatMap { it.items }.any { it.food.chain != "mine" && !it.food.isEveryday && !it.food.isSupermarket }
        val with = days.filter(::fromRestaurant).map { it.calories }
        val without = days.filter { !fromRestaurant(it) }.map { it.calories }
        if (with.size < 3 || without.size < 3) return null
        val a = average(with) ?: return null; val b = average(without) ?: return null
        if (abs(a - b) < 200) return null
        return Insight("takeaway", "Days with takeaway average ${calories(abs(a - b))} Cal ${if (a > b) "more" else "less"} than days without.", abs(a - b) / 100)
    }

    private fun overTargetFood(days: List<Day>): Insight? {
        val over = days.filter { it.overCalories == true }
        val under = days.filter { it.overCalories == false }
        if (over.size < 3 || under.size < 3) return null
        fun has(day: Day, name: String) = day.entries.flatMap { it.items }.any { it.food.name.lowercase() == name }
        fun share(name: String, group: List<Day>) = group.count { has(it, name) }.toDouble() / group.size
        val names = over.flatMap { d -> d.entries.flatMap { it.items }.map { it.food.name.lowercase() } }.toSet()
        data class Scored(val name: String, val over: Double, val under: Double)
        val scored = names.map { Scored(it, share(it, over), share(it, under)) }.filter { it.over >= 0.5 && it.over - it.under >= 0.3 }
        val best = scored.sortedWith(compareByDescending<Scored> { it.over - it.under }.thenBy { it.name }).firstOrNull() ?: return null
        val display = over.flatMap { d -> d.entries.flatMap { it.items } }.firstOrNull { it.food.name.lowercase() == best.name }?.food?.name ?: return null
        val count = over.count { has(it, best.name) }
        return Insight("over-food", "$display is on $count of the ${over.size} days you went over your calories.", (best.over - best.under) * 9)
    }

    private fun lowProteinMeal(days: List<Day>): Insight? {
        if (days.none { it.proteinTarget != null }) return null
        val meals = MealTime.entries.filter { it != MealTime.SNACKS }.mapNotNull { meal ->
            val amounts = days.mapNotNull { day ->
                val entries = day.entries.filter { it.mealTime == meal }
                if (entries.isEmpty()) null else Nutrition(entries.flatMap { it.items }).p
            }
            if (amounts.size >= 3) average(amounts)?.let { meal to it } else null
        }
        if (meals.size < 2) return null
        val low = meals.minByOrNull { it.second } ?: return null
        if (low.second >= 20) return null
        return Insight("low-protein", "${low.first.title} brings you ${low.second.rounded().number} g of protein on average, your lowest meal.", (20 - low.second) / 4)
    }
}
