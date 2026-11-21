package com.isaiahgraham.leanrrr.feature.find

import com.isaiahgraham.leanrrr.data.AppData
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.Goals
import com.isaiahgraham.leanrrr.data.LogEntry
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.QuickLog
import com.isaiahgraham.leanrrr.data.dayKey
import com.isaiahgraham.leanrrr.data.number
import java.time.Instant
import java.time.ZoneId
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/** The answers behind app shortcuts, suggestions and Ask Leanrrr (Assistant.swift), kept apart from UI so tests can run them. */
object Assistant {
    data class Remaining(val calories: Double?, val protein: Double?)

    /** The meal you've logged most often to `mealTime` in the last 30 days. */
    fun usual(mealTime: MealTime, logs: Map<String, List<LogEntry>>, now: Instant = Instant.now()): LogEntry? =
        QuickLog.frequent(logs.mapValues { (_, entries) -> entries.filter { it.mealTime == mealTime } }, now = now, limit = 1).firstOrNull()

    /** Today's targets less what's been logged today. Null for a target that isn't set. */
    fun remaining(data: AppData, goals: Goals, now: Instant = Instant.now()): Remaining {
        val key = dayKey(now)
        val eaten = Nutrition((data.logs[key] ?: emptyList()).flatMap { it.items })
        val target = data.dayGoals[key] ?: goals
        return Remaining(target.values["cal"]?.let { it - eaten.cal }, target.values["p"]?.let { it - eaten.p })
    }

    private fun hour(now: Instant): Int = now.atZone(ZoneId.systemDefault()).hour

    /**
     * What to look for at one restaurant. Before 4 pm there's still a meal to come, so it's capped at your typical meal;
     * after that it can use everything that's left. Null when today's calories are used up.
     */
    fun budget(data: AppData, goals: Goals, chain: String, now: Instant = Instant.now()): FindQuery? {
        val left = remaining(data, goals, now)
        val lastMeal = hour(now) >= 16
        val calories = left.calories?.let { cal ->
            if (cal < 100) return null
            if (lastMeal) cal else min(cal, goals.mealCal)
        } ?: goals.mealCal
        val protein = max(0.0, left.protein?.let { if (lastMeal) it else min(it, goals.mealProtein) } ?: goals.mealProtein)
        return FindQuery(chains = setOf(chain), calories = calories, protein = protein)
    }

    /** Something to eat that fits what's left today. */
    data class Suggestion(val id: String, val name: String, val items: List<Portion>, val source: Source, val calories: Double, val protein: Double) {
        sealed class Source {
            data object Pinned : Source(); data object Recent : Source(); data object MyFood : Source()
            data object SavedMeal : Source(); data object Everyday : Source(); data class Restaurant(val name: String) : Source()
        }
        /** "Pinned", "Eaten lately", "At KFC"... */
        val sourceText: String
            get() = when (source) {
                Source.Pinned -> "Pinned"
                Source.Recent -> "Eaten lately"
                Source.MyFood -> "Your food"
                Source.SavedMeal -> "Your meal"
                Source.Everyday -> "Everyday food"
                is Source.Restaurant -> "At ${source.name}"
            }
    }

    /** What's left to fill today, in words: "62 g protein · 630 Cal". Null when there's nothing left to fill. */
    fun leftText(data: AppData, goals: Goals, now: Instant = Instant.now()): String? {
        val left = remaining(data, goals, now)
        val parts = mutableListOf<String>()
        left.protein?.let { if (it > 0) parts += "${it.rounded().number} g protein" }
        left.calories?.let { if (it > 0) parts += "${it.rounded().number} Cal" }
        return if (parts.isEmpty()) null else parts.joinToString(" · ")
    }

    /** The restaurant you've logged most in the last 30 days, if any of it was from a restaurant. */
    fun usualChain(logs: Map<String, List<LogEntry>>, now: Instant = Instant.now(), days: Long = 30): String? {
        val start = dayKey(now.atZone(ZoneId.systemDefault()).toLocalDate().minusDays(days))
        val counts = HashMap<String, Int>()
        for ((day, entries) in logs) {
            if (day < start) continue
            for (item in entries.flatMap { it.items }) {
                val food = item.food
                if (food.chain != "mine" && food.chain != Food.EVERYDAY && !food.isSupermarket) counts[food.chain] = (counts[food.chain] ?: 0) + 1
            }
        }
        // Most logged; ties go to the name that sorts first.
        return counts.entries.sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key }).firstOrNull()?.key
    }

    /**
     * Up to `limit` things that fit what's left of today: foods you pinned, ate lately, saved or made yourself first, an order at
     * the restaurant you use most, then everyday foods to fill any gap. Ranked by how much of a meal's protein they cover per
     * calorie. Nothing when today's calories are used up or the protein target is met.
     * `diet` leaves out pinned, recent and saved things that don't fit (pass `everyday` and `restaurantFoods` already filtered).
     */
    fun suggestions(
        data: AppData, goals: Goals, pinned: List<Food>, everyday: List<Food>, restaurantFoods: List<Food>, chainNames: Map<String, String>,
        diet: DietFilter = DietFilter(), now: Instant = Instant.now(), limit: Int = 3,
    ): List<Suggestion> {
        val left = remaining(data, goals, now)
        left.calories?.let { if (it < 100) return emptyList() }
        left.protein?.let { if (it <= 0) return emptyList() }
        // A suggestion is one meal, so it's held to your typical meal (a half more after 4 pm), and counts protein only up to a
        // typical meal's worth, so a huge platter doesn't outrank a sensible one.
        val lastMeal = hour(now) >= 16
        val mealCap = if (lastMeal) goals.mealCal * 1.5 else goals.mealCal
        val budget = left.calories?.let { min(it, mealCap) } ?: mealCap
        val want = left.protein ?: goals.mealProtein
        val useful = if (goals.mealProtein > 0) min(want, goals.mealProtein) else want
        val floor = max(3.0, min(useful, 10.0))

        fun suggestion(name: String, items: List<Portion>, source: Suggestion.Source, id: String): Suggestion? {
            val total = Nutrition(items)
            if (items.isEmpty() || !(diet.isEmpty || items.all { diet.allows(it.food) }) || !items.all { it.isValid } ||
                total.cal < 30 || total.cal > budget || total.p < floor) return null
            return Suggestion(id, name, items, source, total.cal, total.p)
        }
        fun ranked(list: List<Suggestion>): List<Suggestion> {
            fun score(item: Suggestion) = min(item.protein, useful) / item.calories
            return list.sortedWith(compareByDescending<Suggestion> { score(it) }.thenByDescending { min(it.protein, useful) }.thenBy { it.name })
        }
        val seen = mutableSetOf<String>()
        fun fresh(s: Suggestion?): Suggestion? = if (s != null && seen.add(s.name.lowercase())) s else null

        val usual = mutableListOf<Suggestion>()
        for (food in pinned) fresh(suggestion(food.name, listOf(Portion(food = food)), Suggestion.Source.Pinned, "food:${food.id}"))?.let { usual += it }
        for (food in QuickLog.recentFoods(data.logs, now = now, limit = 60)) fresh(suggestion(food.name, listOf(Portion(food = food)), Suggestion.Source.Recent, "food:${food.id}"))?.let { usual += it }
        for (food in data.foods) fresh(suggestion(food.name, listOf(Portion(food = food)), Suggestion.Source.MyFood, "food:${food.id}"))?.let { usual += it }
        for (meal in data.meals) fresh(suggestion(meal.name, QuickLog.copies(meal.items), Suggestion.Source.SavedMeal, "meal:${meal.id}"))?.let { usual += it }
        val chosen = ranked(usual).take(limit).toMutableList()

        // One order at the restaurant you use most, found the same way "What fits at KFC" finds it.
        var restaurant: Suggestion? = null
        usualChain(data.logs, now)?.let { chain ->
            val query = FindQuery(chains = setOf(chain), calories = budget, protein = useful, customise = false)
            val match = MealFinder.find(restaurantFoods, query).firstOrNull { it.total.p >= floor && it.total.cal <= budget }
            if (match != null) restaurant = suggestion(describe(match.items), match.items, Suggestion.Source.Restaurant(chainNames[chain] ?: chain), "order:${match.id}")
        }

        if (chosen.size < limit) {
            val usualNames = chosen.map { it.name.lowercase() }.toSet()
            val staples = everyday.filter { it.cat in listOf("food", "breakfast") && !it.name.lowercase().contains("raw") && it.name.lowercase() !in usualNames }
            val fill = ranked(staples.mapNotNull { fresh(suggestion(it.name, listOf(Portion(food = it)), Suggestion.Source.Everyday, "food:${it.id}")) })
            chosen += fill.take(max(0, limit - chosen.size - (if (restaurant == null) 0 else 1)))
        }
        restaurant?.let {
            if (chosen.size >= limit) chosen.removeAt(chosen.size - 1)
            chosen += it
        }
        return chosen.take(limit)
    }

    /** What to offer for a spoken food name: a food named exactly that, on its own; several exact matches are all offered. */
    fun spokenMatches(foods: List<Food>, query: String, chainNames: Map<String, String>, limit: Int = 10): List<Food> {
        val found = FoodSearch.browse(foods, chainNames, FoodSearch.Browse(search = query))
        val words = FoodSearch.tokens(query)
        val exact = found.filter { FoodSearch.tokens(it.name) == words }
        return (exact.ifEmpty { found }).take(limit)
    }

    /** How many servings a spoken amount means. Null when the amount isn't sensible. */
    fun servings(servings: Double?, grams: Double?, food: Food): Double? {
        if (grams != null) {
            val weight = food.servingWeight?.first
            if (grams <= 0 || weight == null || weight <= 0) return null
            val quantity = grams / weight
            return if (quantity in 0.01..100.0) quantity else null
        }
        val quantity = servings ?: 1.0
        return if (quantity.isFinite() && quantity > 0 && quantity <= 100) quantity else null
    }

    /** "Logged 2 × Banana to snacks: 210 Cal, 2.6 g protein. 1,200 Cal left today." */
    fun loggedAnswer(food: Food, quantity: Double, mealTime: MealTime, caloriesLeft: Double?): String {
        val total = Nutrition(listOf(Portion(food = food, quantity = quantity)))
        val amount = if (quantity == 1.0) "" else "${quantity.number} × "
        var text = "Logged $amount${food.name} to ${mealTime.title.lowercase()}: ${total.cal.rounded().number} Cal, ${total.p.number} g protein."
        if (caloriesLeft != null) {
            text += if (caloriesLeft >= 0) " ${caloriesLeft.rounded().number} Cal left today." else " That's ${abs(caloriesLeft).rounded().number} Cal over today's target."
        }
        return text
    }

    /** "Banana (1 medium, 118 g) from Everyday foods has 105 Cal, 1.3 g protein, 27 g carbs and 0.4 g fat." */
    fun macrosAnswer(food: Food, place: String): String {
        val parts = mutableListOf("${food.cal.rounded().number} Cal", "${food.p.number} g protein")
        food.c?.let { parts += "${it.number} g carbs" }
        food.f?.let { parts += "${it.number} g fat" }
        val list = if (parts.size > 1) parts.dropLast(1).joinToString(", ") + " and " + parts.last() else parts[0]
        val serve = if (food.serve.isEmpty()) "" else " (${food.serve})"
        return "${food.name}$serve from $place has $list."
    }

    /** A shown answer to "What fits at …?". */
    fun fitsAnswer(restaurant: String, query: FindQuery?, matches: List<MealMatch>, caloriesLeft: Double?): String {
        if (query == null) {
            val used = caloriesLeft?.let { " You're ${abs(it).rounded().number} Cal ${if (it < 0) "over" else "under"} today's target." } ?: ""
            return "You've used today's calories, so nothing at $restaurant fits.$used"
        }
        val heading = "At $restaurant, for up to ${query.calories.rounded().number} Cal with ${query.protein.rounded().number} g protein:"
        if (matches.isEmpty()) return "Nothing at $restaurant fits in ${query.calories.rounded().number} Cal."
        val lines = matches.take(3).map { "• ${describe(it.items)}: ${it.total.cal.rounded().number} Cal, ${it.total.p.number} g protein" }
        return (listOf(heading) + lines).joinToString("\n")
    }

    /** "2 × Zinger Burger + Chips", grouping repeats of the same food. */
    fun describe(items: List<Portion>): String {
        val order = mutableListOf<String>()
        val counts = HashMap<String, Pair<String, Double>>()
        for (item in items) {
            if (item.food.id !in counts) order += item.food.id
            val current = counts[item.food.id]
            counts[item.food.id] = Pair(item.food.name, (current?.second ?: 0.0) + item.quantity)
        }
        return order.mapNotNull { counts[it] }.joinToString(" + ") { if (it.second == 1.0) it.first else "${it.second.number} × ${it.first}" }
    }

    /** Restaurant names people say that differ from the menu's name. */
    val nicknames: Map<String, String> = mapOf(
        "maccas" to "mcd", "macca's" to "mcd", "mcdonalds" to "mcd", "hj" to "hj", "hjs" to "hj", "hungry jacks" to "hj",
        "gyg" to "gyg", "guzman" to "gyg", "guzman y gomez" to "gyg", "red rooster" to "rr", "rooster" to "rr",
        "dominos" to "dominos", "subway" to "sub", "kentucky" to "kfc", "zambreros" to "zam", "zambrero's" to "zam",
        "boost" to "boost", "boost juice" to "boost", "schnitz" to "schnitz", "grilld" to "grilld", "grill'd" to "grilld", "grill’d" to "grilld",
        "bettys" to "betty", "betty's" to "betty", "betty’s" to "betty", "five guys" to "fiveguys", "crust" to "crust", "donut king" to "donutking",
        "michels" to "michels", "michel's" to "michels", "michel’s" to "michels", "brumbys" to "brumbys", "brumby's" to "brumbys", "brumby’s" to "brumbys",
        "soul origin" to "soul", "rolld" to "rolld", "roll'd" to "rolld", "roll’d" to "rolld", "fishbowl" to "thisbowl", "this bowl" to "thisbowl",
        "woolies" to "woolworths", "woolis" to "woolworths",
        // US menu: only used when that menu is loaded.
        "chickfila" to "us-cfa", "chick fil a" to "us-cfa", "chick-fil-a" to "us-cfa", "wendys" to "us-wendys", "wendy's" to "us-wendys", "wendy’s" to "us-wendys",
        "taco bell" to "us-tacobell", "tacobell" to "us-tacobell", "panda" to "us-panda", "panda express" to "us-panda",
        "burger king" to "hj", "bk" to "hj", "popeyes" to "us-popeyes", "popeye's" to "us-popeyes",
        // Canada, UK and New Zealand menus.
        "tims" to "ca-tims", "timmies" to "ca-tims", "tim hortons" to "ca-tims", "greggs" to "uk-greggs", "maccies" to "mcd", "mickey d's" to "mcd",
        // South African menu.
        "wimpy" to "za-wimpy", "debonairs" to "za-debonairs", "debonairs pizza" to "za-debonairs", "kauai" to "za-kauai",
        // Indian menu.
        "pizza hut" to "in-pizzahut", "pizzahut" to "in-pizzahut",
    )
}
