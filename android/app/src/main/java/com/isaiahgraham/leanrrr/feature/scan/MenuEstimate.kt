package com.isaiahgraham.leanrrr.feature.scan

import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.newId
import java.text.Normalizer

// Pure Kotlin (no Android classes), so the JUnit tests run it on the JVM. A port of MenuEstimate.swift, without the
// Apple Intelligence suggestion path (`estimate(suggested:)` and the "suggested" basis), which has no Android equivalent.

/** Half away from zero, like Swift's `rounded()` (Kotlin's `round` rounds halves to even). */
internal fun Double.roundedAway(): Double = if (this < 0) -Math.round(-this).toDouble() else Math.round(this).toDouble()

/** One thing in a dish and how much of it, from Leanrrr's own foods. */
data class MenuComponent(
    val food: Food,
    val quantity: Double,
    /** False when it's been taken out of the dish. */
    val isOn: Boolean = true,
    val id: String = newId(),
) {
    val grams: Double? get() = food.servingWeight?.let { it.first * quantity }
    val portion: Portion get() = Portion(food = food, quantity = quantity)
}

/** What a dish probably has in it, and how that was worked out. The figures always come from Leanrrr's foods. */
data class MenuEstimate(val components: List<MenuComponent>, val basis: Basis) {
    enum class Basis {
        /** The restaurant's own item, found in Leanrrr's menus. */
        OFFICIAL,
        /** A dish Leanrrr knows, at a typical serve. */
        TYPICAL_DISH,
        /** Added up from the ingredients the menu lists. */
        INGREDIENTS,
        /** Very little to go on, such as one ingredient or only the menu's heading. */
        ROUGH,
        /** The person searched for it and picked a food. */
        CHOSEN,
    }

    /** How far off the figure could be, as a share of it either way. */
    val spread: Double
        get() = when (basis) {
            Basis.OFFICIAL, Basis.CHOSEN -> 0.0
            Basis.TYPICAL_DISH -> 0.2
            Basis.INGREDIENTS -> 0.3
            Basis.ROUGH -> 0.4
        }

    val label: String
        get() = when (basis) {
            Basis.OFFICIAL -> "Official figures"
            Basis.TYPICAL_DISH -> "Typical serve"
            Basis.INGREDIENTS -> "From the menu's ingredients"
            Basis.ROUGH -> "Rough guess"
            Basis.CHOSEN -> "Your pick"
        }

    /** An exact food rather than a sum: its figures stand as they are, so sizes and rounding don't apply. */
    val isExact: Boolean get() = basis == Basis.OFFICIAL || basis == Basis.CHOSEN

    fun total(size: PortionSize = PortionSize.REGULAR): Nutrition =
        Nutrition(components.filter { it.isOn }.map { Portion(food = it.food, quantity = it.quantity * (if (isExact) 1.0 else size.factor)) })

    /** What to log for the dish. */
    fun portion(name: String, size: PortionSize = PortionSize.REGULAR): Portion? {
        if (isExact) return components.firstOrNull { it.isOn }?.portion
        return food(name, size)?.let { Portion(food = it) }
    }

    /**
     * The dish as something to log: the restaurant's own item when there is one, otherwise one estimated food, rounded so it
     * doesn't claim to be exact. Null when everything has been taken out.
     */
    fun food(name: String, size: PortionSize = PortionSize.REGULAR): Food? {
        val used = components.filter { it.isOn }
        if (used.isEmpty()) return null
        if (isExact) return used.first().food
        val total = total(size)
        val calories = (total.cal / 10).roundedAway() * 10
        val others = total.nut.filterKeys { it !in total.partial }.mapValues { (it.value * 10).roundedAway() / 10 }
        return Food(
            name = name, kj = (calories * 4.184).roundedAway(), cal = calories, p = total.p.roundedAway(), c = total.c.roundedAway(),
            f = total.f.roundedAway(), serve = "1 dish, estimated", nut = others.ifEmpty { null }, note = "Estimated from a menu photo",
        )
    }
}

/**
 * Works out what's in a dish from its name and description. In order: the restaurant's own item, a dish in `MenuCookbook`,
 * the ingredients the menu lists, a dish with the same name in Leanrrr's everyday foods, then the menu's heading.
 * With nothing to go on it gives no figure at all, rather than a made-up one.
 */
class MenuEstimator(private val foods: List<Food>, private val chainNames: Map<String, String>) {
    private val byName = HashMap<String, Food>()
    private val plain = HashMap<String, MutableList<Food>>()
    /** Each cookbook phrase as joined words, with its place in the table. */
    private val dishNames = HashMap<String, Int>()

    init {
        for ((index, recipe) in MenuCookbook.recipes.withIndex()) {
            for (name in recipe.names) dishNames.putIfAbsent(name.joinToString(" "), index)
        }
        for (food in foods) {
            if (!food.isEveryday) continue
            byName.putIfAbsent(food.name, food)
            plain.getOrPut(tokens(food.name.takeWhile { it != ',' }).joinToString(" ")) { mutableListOf() } += food
        }
    }

    companion object {
        private val COMBINING = Regex("\\p{Mn}+")

        /** Words as the tables hold them: lower case, no accents, no plurals. */
        fun tokens(text: String): List<String> =
            splitWords(
                Normalizer.normalize(text, Normalizer.Form.NFD).replace(COMBINING, "").lowercase()
                    .replace("’", "").replace("'", "").replace("&", " and "),
            ) { !it.isLetterOrDigit() }.map(MealPhoto::stem)

        private val fryingWords = setOf("fried", "crumbed", "battered", "tempura", "karaage", "panko", "schnitzel", "crispy")
        private val weightRegex = Regex("""(?i)\b(\d{2,4})\s?(g|gm|gram|grams)\b""")
    }

    fun food(name: String): Food? = byName[name]

    /** The restaurant a menu belongs to, when Leanrrr has its menu. */
    fun chain(restaurant: String?): String? = MealPhoto.chain(restaurant, chainNames)

    fun estimate(dish: MenuDish, chain: String? = null): MenuEstimate? {
        if (chain != null) official(dish, chain)?.let { return MenuEstimate(listOf(MenuComponent(it, 1.0)), MenuEstimate.Basis.OFFICIAL) }
        val name = tokens(dish.name)
        val details = tokens(dish.details)
        val all = name + "." + details
        val section = dish.section?.let(::tokens) ?: emptyList()
        val scale = scale(section)
        val weight = statedWeight(dish.name + " " + dish.details)

        recipe(name)?.let { (recipe, range) ->
            // The words that named the dish aren't ingredients on top of it: "fried rice" isn't also rice.
            val rest = name.subList(0, range.first) + "." + name.subList(range.last + 1, name.size)
            val found = ingredients(rest + "." + details)
            val basis = if (recipe.style == MenuCookbook.Style.BASE && found.any { it.food != null }) MenuEstimate.Basis.INGREDIENTS else MenuEstimate.Basis.TYPICAL_DISH
            return finish(assemble(recipe, found, all, weight), if (recipe.style == MenuCookbook.Style.AS_SOLD) 1.0 else scale, basis)
        }
        val found = ingredients(all)
        recipe(section)?.first?.let { recipe ->
            val basis = if (recipe.style == MenuCookbook.Style.AS_SOLD) MenuEstimate.Basis.ROUGH else MenuEstimate.Basis.INGREDIENTS
            return finish(assemble(recipe, found, all, weight), if (recipe.style == MenuCookbook.Style.AS_SOLD) 1.0 else scale, basis)
        }
        val useful = found.filter { it.food != null }
        if (useful.size >= 2) return finish(built(useful, all, weight), scale, MenuEstimate.Basis.INGREDIENTS)
        wholeFood(name)?.let { (food, quantity) ->
            return MenuEstimate(listOf(MenuComponent(food, quantity * scale)), MenuEstimate.Basis.TYPICAL_DISH)
        }
        if (useful.size == 1) return finish(built(useful, all, weight), scale, MenuEstimate.Basis.ROUGH)
        return null
    }

    // Finding what's in it

    private fun official(dish: MenuDish, chain: String): Food? {
        val seen = SeenFood(name = dish.name, brand = chainNames[chain], count = 1)
        return MealPhoto.matches(seen, foods, chainNames, limit = 4).firstOrNull { it.chain == chain && MealPhoto.plainly(it, seen) }
    }

    /** The cookbook dish with the longest name in these words; the earlier in the table when two are as long. */
    private fun recipe(words: List<String>): Pair<MenuCookbook.Recipe, IntRange>? {
        var bestStart = -1; var bestLength = 0; var bestIndex = 0
        for (start in words.indices) {
            for (length in 1..minOf(4, words.size - start)) {
                val index = dishNames[words.subList(start, start + length).joinToString(" ")] ?: continue
                if (bestStart < 0 || length > bestLength || (length == bestLength && index < bestIndex)) { bestStart = start; bestLength = length; bestIndex = index }
            }
        }
        return if (bestStart < 0) null else MenuCookbook.recipes[bestIndex] to (bestStart until bestStart + bestLength)
    }

    private data class Found(
        val food: String?,
        val role: MenuCookbook.Role,
        val grams: Double,
        /** "or" came just before it, so it's an alternative to what's listed before. */
        val isChoice: Boolean,
    )

    /** Ingredients in the order they're named, taking the longest run of words each time. Anything after "add" or "no" is left out. */
    private fun ingredients(words: List<String>): List<Found> {
        val found = mutableListOf<Found>()
        var index = 0
        while (index < words.size) {
            var matched = false
            for (length in minOf(4, words.size - index) downTo 1) {
                val item = MenuCookbook.ingredients[words.subList(index, index + length).joinToString(" ")] ?: continue
                val before = if (index > 0) words[index - 1] else ""
                if (before !in setOf("no", "without", "add", "extra")) found += Found(item.food, item.role, item.grams, before == "or")
                index += length; matched = true
                break
            }
            if (!matched) index += 1
        }
        return found
    }

    /** The weight a menu prints, as in "300 g scotch fillet". */
    private fun statedWeight(text: String): Double? {
        val grams = weightRegex.find(text)?.groupValues?.get(1)?.toDoubleOrNull() ?: return null
        return if (grams in 50.0..1500.0) grams else null
    }

    /** Whether something in the dish is crumbed or deep fried. A fried egg, stir fried noodles and crispy skin don't count. */
    private fun isFried(words: List<String>): Boolean = words.indices.any { index ->
        if (words[index] !in fryingWords) return@any false
        val before = if (index > 0) words[index - 1] else ""
        val after = if (index + 1 < words.size) words[index + 1] else ""
        before != "stir" && after !in setOf("egg", "rice", "skin")
    }

    /** The proteins to use for `slot` grams. One named is the lot; several share a little more; a choice ("chicken or tofu") is the first. */
    private fun proteins(found: List<Found>, slot: Double): List<MenuCookbook.Part> {
        var list = found.filter { it.role == MenuCookbook.Role.PROTEIN && it.food != null }
        val seen = HashSet<String>()
        list = list.filter { seen.add(it.food ?: "") }
        if (list.any { it.isChoice }) list = list.take(1)
        if (list.size <= 1) return list.firstOrNull()?.let { listOf(MenuCookbook.Part(it.food ?: "", slot)) } ?: emptyList()
        val share = slot * minOf(1.5, 1 + 0.25 * (list.size - 1)) / list.size
        return list.take(4).map { MenuCookbook.Part(it.food ?: "", share) }
    }

    /**
     * A starch the menu names: it takes the place of the dish's usual one of the same kind, or joins the plate if there's none.
     * Rice, pasta or noodles are left out of a dish that's already made with them.
     */
    private fun add(item: Found, parts: MutableList<MenuCookbook.Part>) {
        val food = item.food ?: return
        if (item.isChoice || parts.any { it.food == food }) return
        val kind = MenuCookbook.swaps.firstOrNull { food in it }
        if (kind != null) {
            val usual = parts.indexOfFirst { it.food in kind }
            if (usual < 0 && kind == MenuCookbook.swaps[0] && parts.any { it.food in MenuCookbook.filled }) return
            if (usual >= 0) { parts[usual] = MenuCookbook.Part(food, parts[usual].grams); return }
        }
        parts += MenuCookbook.Part(food, item.grams)
    }

    private fun assemble(recipe: MenuCookbook.Recipe, found: List<Found>, text: List<String>, stated: Double?): List<MenuCookbook.Part> {
        var parts = recipe.parts.toMutableList()
        when (recipe.style) {
            MenuCookbook.Style.AS_SOLD -> return parts
            MenuCookbook.Style.PLATE -> {
                for (item in found) if (item.role == MenuCookbook.Role.STARCH) add(item, parts)
                return parts
            }
            MenuCookbook.Style.BASE -> {
                var fillings = proteins(found, recipe.protein)
                if (fillings.isEmpty() && recipe.usual != null) fillings = listOf(recipe.usual)
                if (stated != null && fillings.isNotEmpty()) fillings = listOf(fillings[0].copy(grams = stated)) + fillings.drop(1)
                parts = (fillings.filter { part -> parts.none { it.food == part.food } } + parts).toMutableList()
                for (item in found) {
                    if (item.role == MenuCookbook.Role.PROTEIN || item.role in recipe.covers) continue
                    if (item.role == MenuCookbook.Role.STARCH) add(item, parts)
                    else if (item.food != null && parts.none { it.food == item.food }) parts += MenuCookbook.Part(item.food, item.grams * 0.7)
                }
                if (isFried(text)) parts += frying
                return parts
            }
        }
    }

    private val frying: List<MenuCookbook.Part> get() = listOf(MenuCookbook.Part("Plain flour", 20.0), MenuCookbook.Part("Canola oil", 15.0))

    /** A dish with no cookbook entry, from its ingredients, with a little oil the way a kitchen would use it. */
    private fun built(found: List<Found>, text: List<String>, stated: Double?): List<MenuCookbook.Part> {
        var parts = proteins(found, found.firstOrNull { it.role == MenuCookbook.Role.PROTEIN }?.grams ?: 0.0).toMutableList()
        if (stated != null && parts.isNotEmpty()) parts[0] = parts[0].copy(grams = stated)
        for (item in found) {
            if (item.role == MenuCookbook.Role.PROTEIN) continue
            if (item.food != null && parts.none { it.food == item.food }) parts += MenuCookbook.Part(item.food, item.grams)
        }
        return parts + (if (isFried(text)) frying else listOf(MenuCookbook.Part("Olive oil", 10.0)))
    }

    /** A food called exactly what the dish is called. A food sold by the cup is a small measure, so it's made a plateful. */
    private fun wholeFood(name: List<String>): Pair<Food, Double>? {
        val hits = plain[name.joinToString(" ")] ?: return null
        val food = MealPhoto.ordered(hits, name).firstOrNull() ?: return null
        val weight = food.servingWeight?.first?.takeIf { it > 0 } ?: return null
        return food to (if (food.serve.contains("cup") || weight <= 100) 350 / weight else 1.0)
    }

    /** Starters and shared plates are smaller than a main, and so are sides and kids' meals. */
    private fun scale(section: List<String>): Double {
        if (section.any { it in setOf("entree", "starter", "small", "share", "sharing", "tapa", "appetiser", "appetizer", "antipasti", "snack", "bar") }) return 0.55
        if (section.any { it in setOf("side", "kid", "children", "junior", "little") }) return 0.6
        return 1.0
    }

    private fun component(name: String, grams: Double): MenuComponent? = byName[name]?.let { component(it, grams) }

    private fun component(food: Food, grams: Double): MenuComponent? {
        val weight = food.servingWeight?.first?.takeIf { it > 0 } ?: return null
        return MenuComponent(food, grams / weight)
    }

    private fun finish(parts: List<MenuCookbook.Part>, scale: Double, basis: MenuEstimate.Basis): MenuEstimate? {
        val components = mutableListOf<MenuComponent>()
        for (part in parts) {
            val made = component(part.food, part.grams * scale) ?: continue
            val index = components.indexOfFirst { it.food.id == made.food.id }
            if (index >= 0) components[index] = components[index].copy(quantity = components[index].quantity + made.quantity) else components += made
        }
        return if (components.isEmpty()) null else MenuEstimate(components, basis)
    }
}

