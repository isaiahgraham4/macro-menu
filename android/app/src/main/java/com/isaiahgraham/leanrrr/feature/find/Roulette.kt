package com.isaiahgraham.leanrrr.feature.find

import com.isaiahgraham.leanrrr.data.AppData
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.Goals
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.dayKey
import java.time.Instant
import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random

/** Takeaway roulette (Roulette.swift): a wheel of restaurants, each holding the dinners there that fit what's left today. */
object Roulette {
    /** A juice bar and the bakeries and cafes, which sell lunch and shut early. */
    val notDinner = setOf("boost", "brumbys", "donutking", "michels", "soul")
    /** A dinner uses at least this much of the limit, so a snack can't win the night. */
    const val LEAST_OF_LIMIT = 0.5
    /** Anything smaller is a dip or a sauce, not a side. */
    const val SMALLEST_SIDE = 100.0
    /** A full burger twice is two dinners; two of something small is one. */
    const val LARGEST_DOUBLED = 300.0
    /** The restaurants chosen for the wheel, joined with commas. Empty is every restaurant. */
    const val STORAGE_KEY = "roulette.chains"

    /**
     * The restaurants on the wheel: the ones chosen, or every one when none are. Places out of reach stay off unless they're
     * chosen. Chosen IDs no longer on the menu don't count.
     */
    fun onWheel(all: List<String>, chosen: Set<String>, outOfReach: Set<String>): Set<String> {
        val picked = chosen.intersect(all.toSet())
        return if (picked.isEmpty()) all.toSet() - outOfReach else picked
    }

    /** One restaurant on the wheel. */
    data class Slice(val chain: String, val orders: List<MealMatch>)

    /**
     * The limits for tonight. Dinner can use what's left today, up to half as much again as a typical meal. Carbs and fat count
     * when they're daily limits with some left. Null when today's calories are used up.
     */
    fun limits(data: AppData, goals: Goals, diet: DietFilter = DietFilter(), now: Instant = Instant.now()): FindQuery? {
        val left = Assistant.remaining(data, goals, now)
        val cap = goals.mealCal * 1.5
        val calories = left.calories?.let { if (it < 100) return null; min(it, cap).roundedDown() } ?: cap
        val protein = max(0.0, min(left.protein ?: goals.mealProtein, goals.mealProtein)).rounded()
        val eaten = Nutrition((data.logs[dayKey(now)] ?: emptyList()).flatMap { it.items })
        val target = data.dayGoals[dayKey(now)] ?: goals
        fun remaining(key: String, eaten: Double): Double? {
            val limit = target.values[key] ?: return null
            if (key in target.minimums) return null
            return max(0.0, limit - eaten).roundedDown()
        }
        return FindQuery(calories = calories, protein = protein, carbs = remaining("c", eaten.c), fat = remaining("f", eaten.f), customise = false, diet = diet)
    }

    private val notDinnerName = Regex("""\b(Brekky|Breakfast|Hash Brown|Kids|Kid's)\b""", RegexOption.IGNORE_CASE)

    /** What can go in a dinner: mains and real sides. Not drinks, desserts, extras, sauces, breakfast or kids' items. */
    fun isDinnerFood(food: Food): Boolean {
        if (!(food.cat == "main" || (food.cat == "side" && food.cal >= SMALLEST_SIDE))) return false
        return !notDinnerName.containsMatchIn(food.name)
    }

    /** Whether an order counts as dinner within `query`: it meets protein and is more than a snack. */
    fun isDinner(order: MealMatch, query: FindQuery): Boolean {
        val doubled = order.foods.size == 2 && order.foods[0].id == order.foods[1].id
        return order.p >= query.protein && order.cal >= query.calories * LEAST_OF_LIMIT && (!doubled || order.foods[0].cal <= LARGEST_DOUBLED)
    }

    /** The dinners at each restaurant that fit, closest fits first. A restaurant with none gets no slice. */
    fun slices(foods: List<Food>, query: FindQuery, isCancelled: () -> Boolean = { false }): List<Slice> {
        val slices = mutableListOf<Slice>()
        for ((chain, menu) in foods.filter(::isDinnerFood).groupBy { it.chain }.toSortedMap()) {
            if (isCancelled()) return emptyList()
            if (chain == "mine" || chain in notDinner || (query.chains.isNotEmpty() && chain !in query.chains)) continue
            val orders = MealFinder.find(menu, query, isCancelled).filter { isDinner(it, query) }
            if (orders.isNotEmpty()) slices += Slice(chain, orders)
        }
        return slices
    }

    /**
     * What one spin lands on: a slice, then one of its dinners. Every restaurant gets the same chance, and neither the last
     * restaurant nor the last order comes up twice running when there's another to choose.
     */
    fun spin(slices: List<Slice>, after: MealMatch?, random: Random = Random.Default): Pair<Int, MealMatch>? {
        val fresh = slices.indices.filter { slices[it].chain != after?.chain }
        val pool = fresh.ifEmpty { slices.indices.toList() }
        if (pool.isEmpty()) return null
        val slice = pool.random(random)
        val orders = slices[slice].orders
        val unseen = orders.filter { it.id != after?.id }
        val order = (unseen.ifEmpty { orders }).randomOrNull(random) ?: return null
        return slice to order
    }

    /**
     * Where the wheel stops, in degrees clockwise, so the middle of `slice` plus `offset` slice-widths sits under the pointer at
     * the top, after at least `turns` whole turns from `angle`. Slice 0 starts at the pointer and they run clockwise.
     */
    fun landing(from: Double, slice: Int, count: Int, turns: Int, offset: Double = 0.0): Double {
        val sweep = 360.0 / max(count, 1)
        val stop = 360 - (slice + 0.5 + offset) * sweep
        val start = from % 360
        val extra = (stop - start) % 360
        return from + turns * 360 + (if (extra < 0) extra + 360 else extra)
    }

    /** The slice under the pointer when the wheel is turned to `angle`. */
    fun sliceAt(angle: Double, count: Int): Int {
        if (count <= 0) return 0
        val turned = (360 - angle % 360) % 360
        return min(count - 1, ((if (turned < 0) turned + 360 else turned) / (360.0 / count)).toInt())
    }
}
