package com.isaiahgraham.leanrrr.feature.find

import com.isaiahgraham.leanrrr.data.AppStore
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Portion
import kotlin.math.floor
import kotlin.math.max

// A port of MealFinder.swift: whole orders from one restaurant that fit a calorie limit, ranked against a protein target.

/** Swift's `rounded()`: to the nearest whole number, halves away from zero (Kotlin's `round` rounds halves to even). */
internal fun Double.rounded(): Double = if (this < 0) -floor(-this + 0.5) else floor(this + 0.5)
/** Swift's `rounded(.down)`. */
internal fun Double.roundedDown(): Double = floor(this)

data class FindQuery(
    val chains: Set<String> = emptySet(),
    val calories: Double = 500.0,
    val protein: Double = 40.0,
    val carbs: Double? = null,
    val fat: Double? = null,
    val budget: Double? = null,
    val maxItems: Int = 2,
    val sort: String = "fit",
    /** Also try each item customised: sauce or cheese taken off, or another patty or fillet added. */
    val customise: Boolean = true,
    /** Dietary needs: only items the restaurant's words show fit are used. */
    val diet: DietFilter = DietFilter(),
    /** Coles and Woolworths products instead of restaurant menus; `chains` then picks between the two. */
    val supermarket: Boolean = false,
) {
    /** Also true when a question named a supermarket. */
    val usesSupermarkets: Boolean get() = supermarket || chains.any { it in Food.SUPERMARKETS }
}

/**
 * One suggested order. The totals the ranking needs are added up straight away; the portions and full nutrition are only made
 * for the orders that are kept, since the finder looks at a great many.
 */
class MealMatch(val foods: List<Food>) {
    val id: String by lazy { foods.joinToString("|") { it.id } }
    val items: List<Portion> by lazy { foods.map { Portion(food = it) } }
    val total: Nutrition by lazy { Nutrition(items) }
    val cal: Double = foods.sumOf { it.cal }
    val p: Double = foods.sumOf { it.p }
    val price: Double = foods.sumOf { it.price ?: 0.0 }
    val chain: String get() = foods.firstOrNull()?.chain ?: "mine"
    /** Items changed from how the restaurant sells them. */
    val customised: Int = foods.count { MealFinder.isVariant(it) }
    val name: String get() = foods.joinToString(" + ") { it.name }

    override fun equals(other: Any?): Boolean = other is MealMatch && other.id == id
    override fun hashCode(): Int = id.hashCode()
}

/** The foods one order search needs. A question can name a supermarket and a restaurant together. */
fun AppStore.orderFoods(query: FindQuery): List<Food> {
    if (!query.usesSupermarkets) return orderFoods
    return if (query.chains.isEmpty()) supermarket else supermarket + orderFoods
}

object MealFinder {
    /** Customised copies of a food get an ID made from the original's and the changes, after this mark. */
    const val VARIANT_MARK = '~'
    fun isVariant(food: Food): Boolean = food.id.contains(VARIANT_MARK)
    fun baseID(food: Food): String = food.id.substringBefore(VARIANT_MARK)

    /** Parts that make an item what it is (the bun, the meat), so they're never taken off to make it fit. */
    private val structural = setOf("bun", "bread", "roll", "muffin", "tortilla", "wrap", "base", "crust", "toast", "rice",
        "patty", "patties", "beef", "chicken", "fillet", "fish", "egg", "sausage", "ham", "steak", "pork", "tofu")

    fun isStructural(name: String): Boolean {
        val lower = name.lowercase()
        return lower.startsWith("make it a") || lower.split(Regex("[^\\p{L}]+")).any { it in structural }
    }

    /** Whether the item is named after the part a removal takes off, like cheese on a Cheeseburger. */
    fun names(food: Food, removal: com.isaiahgraham.leanrrr.data.Modifier): Boolean {
        val part = removal.name.lowercase().removePrefix("no ")
        return food.name.lowercase().contains(part)
    }

    /**
     * Ways to order a food so it fits better, each a customised copy of it.
     * Lighter: taking off up to three of the parts that save the most energy (sauces, cheese, bacon), never the bun or the meat.
     * More protein: the extra patty or fillet with the most protein for its energy, alone and with the lighter changes.
     * With dietary needs set, only removals are used.
     */
    fun variants(food: Food, additions: Boolean = true): List<Food> {
        val mods = food.modifiers ?: emptyList()
        if (mods.isEmpty() || food.cal <= 0) return emptyList()
        val groups = mutableSetOf<String>()
        val removals = mods.filter { it.kind == "r" && -it.kj >= 60 && -it.p <= max(2.0, food.p * 0.15) && !isStructural(it.name) && !names(food, it) }
            .sortedBy { it.kj }
            .filter { groups.add(it.group ?: it.key) }
        val protein = if (additions) mods.filter { it.kind == "f" && it.p >= 4 && it.kj > 0 }.maxByOrNull { it.p / it.kj } else null
        val plans = mutableListOf<Map<String, Double>>()
        for (count in 1..minOf(3, max(1, removals.size))) {
            if (removals.size >= count) plans += removals.take(count).associate { it.key to 1.0 }
        }
        if (protein != null) {
            val lighter = plans.toList()
            plans += mapOf(protein.key to 1.0)
            for (plan in lighter) plans += plan + (protein.key to 1.0)
        }
        return plans.map { plan ->
            food.customised(plan).copy(id = food.id + VARIANT_MARK + plan.keys.sorted().joinToString("+"))
        }.filter { it.isValid }
    }

    private val dippable = Regex("Tender|Fries|Nugget|Wing|Pops|Fried Chicken|Chicken Piece|Strips|Bolas|Bites|Chips|Drumstick", RegexOption.IGNORE_CASE)
    private val gygSmall = Regex("Mini|Little G|Taco|Quesadilla|Fries|Tender")

    fun extraFits(main: Food, extra: Food): Boolean {
        if (extra.name.startsWith("Mini Extra:")) return main.name.contains("Mini")
        if (extra.name.startsWith("Brekkie Extra:")) return main.cat == "breakfast"
        if (extra.name.startsWith("Dipping Sauce:")) return dippable.containsMatchIn(main.name)
        if (extra.chain == "gyg" && extra.name.startsWith("Extra ")) return main.cat != "breakfast" && !gygSmall.containsMatchIn(main.name)
        return !(extra.chain == "sub" && extra.name.startsWith("Extra ") && main.name.contains("Nachos"))
    }

    /**
     * A supermarket has thousands of products, far too many to try in every combination, so only the likeliest of each kind go
     * in: the most protein for their calories, plus whatever the chosen ranking wants first.
     */
    fun shortlist(foods: List<Food>, limit: Int, sort: String): List<Food> {
        if (foods.size <= limit) return foods
        val dense = foods.sortedByDescending { it.p / max(it.cal, 1.0) }
        val first = when (sort) {
            "protein" -> foods.sortedByDescending { it.p }
            "lean" -> foods.sortedBy { it.cal }
            else -> dense
        }
        val seen = mutableSetOf<String>()
        return (first.take(limit / 2) + dense).filter { seen.add(it.id) }.take(limit)
    }

    /** True when `a` ranks above `b` for this query. */
    fun better(a: MealMatch, b: MealMatch, q: FindQuery): Boolean {
        val sx = max(0.0, q.protein - a.p).rounded()
        val sy = max(0.0, q.protein - b.p).rounded()
        if (q.sort == "protein") return if (a.p == b.p) (if (a.cal == b.cal) a.customised < b.customised else a.cal < b.cal) else a.p > b.p
        if (sx != sy) return sx < sy
        // Otherwise equal orders: the one with fewer changes from how it's sold.
        if (a.cal.rounded() == b.cal.rounded() && a.customised != b.customised) return a.customised < b.customised
        return when (q.sort) {
            "lean" -> a.cal < b.cal
            "cheap" -> a.price < b.price
            "value" -> a.p / max(a.price, 0.01) > b.p / max(b.price, 0.01)
            else -> {
                // Closest fit: when both meet protein equally, an order as it's sold beats one that needs changes.
                if (a.customised != b.customised) a.customised < b.customised
                else if (a.cal == b.cal) a.foods.size < b.foods.size else a.cal > b.cal
            }
        }
    }

    /** A stable merge sort by `before`, which never throws if the ordering isn't perfectly consistent (TimSort can). */
    fun <T> sortedBy(list: List<T>, before: (T, T) -> Boolean): List<T> {
        if (list.size < 2) return list
        val mid = list.size / 2
        val left = sortedBy(list.subList(0, mid), before)
        val right = sortedBy(list.subList(mid, list.size), before)
        val out = ArrayList<T>(list.size)
        var i = 0; var j = 0
        while (i < left.size && j < right.size) {
            if (before(right[j], left[i])) out += right[j++] else out += left[i++]
        }
        while (i < left.size) out += left[i++]
        while (j < right.size) out += right[j++]
        return out
    }

    /** Orders that fit `q`, best first, at most 24. `isCancelled` lets a newer search stop this one early. */
    fun find(allFoods: List<Food>, q: FindQuery, isCancelled: () -> Boolean = { false }): List<MealMatch> {
        if (q.calories <= 0) return emptyList()
        val foods = if (q.diet.isEmpty) allFoods else allFoods.filter { q.diet.allows(it) }
        val best = HashMap<String, MutableList<MealMatch>>()
        val needsMacros = q.carbs != null || q.fat != null
        val needsPrice = q.budget != null || q.sort == "cheap" || q.sort == "value"

        fun consider(list: List<Food>) {
            var cal = 0.0
            for (f in list) cal += f.cal
            if (cal > q.calories) return
            if (list.count { it.cat == "drink" } > 1 || list.count { it.cat == "sweet" } > 1) return
            val extras = list.filter { it.cat == "extra" }
            if (extras.size > 1 || !extras.all { extraFits(list[0], it) }) return
            if (needsMacros && !list.all { it.c != null && it.f != null }) return
            q.carbs?.let { cap -> if (list.sumOf { it.c ?: 0.0 } > cap) return }
            q.fat?.let { cap -> if (list.sumOf { it.f ?: 0.0 } > cap) return }
            if (needsPrice && !list.all { it.price != null }) return
            q.budget?.let { budget -> if (list.sumOf { it.price ?: 0.0 } > budget) return }
            val match = MealMatch(list)
            // An item and its customised versions share two places, so one burger doesn't fill the list.
            val anchor = baseID(list[0])
            val candidates = best.getOrPut(anchor) { mutableListOf() }
            var at = candidates.size
            while (at > 0 && better(match, candidates[at - 1], q)) at--
            if (at < 2) {
                candidates.add(at, match)
                while (candidates.size > 2) candidates.removeAt(candidates.size - 1)
            }
        }

        for (chain in foods.map { it.chain }.toSortedSet()) {
            if (q.chains.isNotEmpty() && chain !in q.chains) continue
            val eligible = foods.filter { it.chain == chain && it.cat != "swap" && it.cal > 0 && it.cal <= q.calories }
            // A chain with no mains (a juice bar) builds orders around its drinks instead.
            val anchors = foods.any { it.chain == chain && it.isAnchor }
            var mains = if (anchors) eligible.filter { it.isAnchor } else eligible
            val supermarket = chain in Food.SUPERMARKETS
            if (supermarket) mains = shortlist(mains, 100, q.sort)
            if (q.customise) {
                // Built from every main, including those over the limit as sold: taking the sauce off may bring one under it.
                val all = foods.filter { it.chain == chain && it.cat != "swap" && it.cal > 0 && (!anchors || it.isAnchor) }
                mains = mains + all.flatMap { variants(it, additions = q.diet.isEmpty) }.filter { it.cal <= q.calories }
            }
            var sides = if (anchors) eligible.filter { !it.isAnchor && (it.cal >= 50 || it.cat == "drink") }.sortedBy { it.cal } else emptyList()
            if (supermarket) {
                sides = shortlist(sides, 24, q.sort).sortedBy { it.cal }
                // A snack can be all you're after, alone or as a pair, when there's no room for a meal.
                for (snack in shortlist(eligible.filter { it.cat == "snack" }, 60, q.sort)) {
                    consider(listOf(snack))
                    if (q.maxItems > 1) consider(listOf(snack, snack))
                }
            }
            for (main in mains) {
                if (isCancelled()) return emptyList()
                // Customised items are tried alone, doubled and with one side; three-item orders stay as sold.
                val full = q.maxItems > 2 && !isVariant(main)
                consider(listOf(main))
                if (q.maxItems <= 1) continue
                consider(listOf(main, main))
                for (a in sides.indices) {
                    if (main.cal + sides[a].cal > q.calories) break
                    consider(listOf(main, sides[a]))
                    if (full) {
                        consider(listOf(main, main, sides[a]))
                        for (b in a until sides.size) {
                            if (main.cal + sides[a].cal + sides[b].cal > q.calories) break
                            consider(listOf(main, sides[a], sides[b]))
                        }
                    }
                }
                if (full) consider(listOf(main, main, main))
            }
        }
        return sortedBy(best.values.flatten()) { a, b -> better(a, b, q) }.take(24)
    }
}
