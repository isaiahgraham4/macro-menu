package com.isaiahgraham.leanrrr.feature.find

import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.MenuRegion
import com.isaiahgraham.leanrrr.data.number

/**
 * Ask Leanrrr (AskLeanr.swift): a question in plain words ("40 g protein under 600 Cal at Nando's") turned into an order search.
 * These rules read the numbers, restaurants and dietary needs. Nothing here makes up nutrition: the answers are the order
 * finder's, from the menus. (The iOS app can also fill gaps with Apple Intelligence; that path is omitted on Android.)
 */
object AskLeanr {
    enum class Field { CALORIES, PROTEIN, CARBS, FAT, ITEMS, CHAINS, SORT, DIET }

    data class Request(
        val query: FindQuery,
        /** Words for what was understood, shown above the answers so a misreading is easy to spot. */
        val understood: List<String>,
        /** "What's left today" was asked for: the calories and protein come from today's targets. */
        val usesRemaining: Boolean = false,
        /** What was read from the words rather than left at its default. */
        val said: Set<Field> = emptySet(),
    )

    private const val NUMBER = """(\d+(?:\.\d+)?)"""
    private val numberRegex = Regex(NUMBER)

    /** The question as an order search. `defaults` gives the calories and protein when the question doesn't. */
    fun parse(text: String, chainNames: Map<String, String>, defaults: FindQuery): Request {
        var query = defaults.copy(chains = emptySet())
        val said = mutableSetOf<Field>()
        val lower = " " + text.lowercase().replace("’", "'").replace(",", " ").replace("-", " ") + " "

        // Numbers with what they measure: "40 g protein", "protein of 40", "600 cal", "2500 kJ", "under 30 g carbs".
        fun value(patterns: List<String>): Double? {
            for (pattern in patterns) {
                val match = Regex(pattern).find(lower) ?: continue
                numberRegex.find(match.value)?.value?.toDoubleOrNull()?.let { return it }
            }
            return null
        }
        val protein = value(listOf(NUMBER + """\s*(g|grams?)?\s*(of\s+)?protein""", """protein\s*(of|at least|over|above|>)?\s*""" + NUMBER))
        if (protein != null) {
            query = query.copy(protein = protein); said += Field.PROTEIN
        } else if (lower.contains("high protein") || lower.contains("most protein") || lower.contains("lots of protein")) {
            query = query.copy(sort = "protein"); said += Field.SORT
        }
        val kj = value(listOf(NUMBER + """\s*kj\b"""))
        val calories = if (kj == null) value(listOf(NUMBER + """\s*(k?cals?|calories|kcal)\b""")) else null
        val bare = if (kj == null && calories == null)
            value(listOf("""\b(under|below|less than|up to|max|maximum|no more than)\s+""" + NUMBER + """(?!\s*(g|grams?)\b)""")) else null
        when {
            kj != null -> { query = query.copy(calories = (kj / 4.184).rounded()); said += Field.CALORIES }
            calories != null -> { query = query.copy(calories = calories); said += Field.CALORIES }
            // "under 600" with no unit is calories; grams come with a "g".
            bare != null && bare >= 100 -> { query = query.copy(calories = bare); said += Field.CALORIES }
        }
        val carbs = value(listOf(NUMBER + """\s*(g|grams?)?\s*(of\s+)?carbs?""", """carbs?\s*(under|below|less than|up to)?\s*""" + NUMBER))
        if (carbs != null) { query = query.copy(carbs = carbs); said += Field.CARBS }
        else if (lower.contains("low carb") || lower.contains("keto")) { query = query.copy(carbs = 30.0); said += Field.CARBS }
        val fat = value(listOf(NUMBER + """\s*(g|grams?)?\s*(of\s+)?fat\b""", """\bfat\s*(under|below|less than|up to)?\s*""" + NUMBER))
        if (fat != null) { query = query.copy(fat = fat); said += Field.FAT }
        else if (lower.contains("low fat")) { query = query.copy(fat = 15.0); said += Field.FAT }
        if (lower.contains("lightest") || lower.contains("lowest cal") || lower.contains("fewest cal")) { query = query.copy(sort = "lean"); said += Field.SORT }

        // How many items.
        val words = mapOf("one" to 1, "1" to 1, "single" to 1, "two" to 2, "2" to 2, "three" to 3, "3" to 3)
        for ((word, count) in words) {
            if (Regex("""\b""" + word + """\s+items?\b""").containsMatchIn(lower)) { query = query.copy(maxItems = count); said += Field.ITEMS }
        }
        if (lower.contains("just one thing") || lower.contains("one thing") || lower.contains("single item")) { query = query.copy(maxItems = 1); said += Field.ITEMS }
        if (lower.contains("with a side") || lower.contains("and a side") || lower.contains("with sides")) { query = query.copy(maxItems = maxOf(query.maxItems, 2)); said += Field.ITEMS }

        // Restaurants: the menu's own names and the names people say.
        val chains = mutableSetOf<String>()
        for ((id, name) in chainNames) {
            if (id == "mine" || id == Food.EVERYDAY || id == Food.COMMUNITY) continue
            val plain = name.lowercase().replace("’", "'").replace("-", " ")
            val variants = listOf(plain, plain.replace("'", ""), plain.replace(" ", ""))
            // Whole words, so "coleslaw" isn't Coles.
            if (variants.any { Regex("""\s""" + Regex.escape(it) + """(?:'s)?\b""").containsMatchIn(lower) }) chains += id
        }
        for ((nickname, written) in Assistant.nicknames) {
            val id = MenuRegion.chain(written, chainNames) ?: continue
            if (Regex("""\b""" + Regex.escape(nickname) + """\b""").containsMatchIn(lower)) chains += id
        }
        query = query.copy(chains = chains)
        if (lower.contains("supermarket") || lower.contains("ready meal")) query = query.copy(supermarket = true)
        if (query.chains.isNotEmpty() || query.supermarket) said += Field.CHAINS

        // Dietary needs, added to any already set.
        val needs: List<Pair<String, List<DietOption>>> = listOf(
            """\bvegan\b|plant based""" to listOf(DietOption.VEGAN),
            """vegetarian|\bveggie\b|meat free|no meat|without meat|meatless""" to listOf(DietOption.VEGETARIAN),
            """no beef|without beef|beef free|don't eat beef""" to listOf(DietOption.NO_BEEF),
            """no pork|without pork|pork free|don't eat pork|halal""" to listOf(DietOption.NO_PORK),
            """gluten|coeliac|celiac""" to listOf(DietOption.GLUTEN),
            """dairy|lactose|no milk|milk free|milk allergy""" to listOf(DietOption.MILK),
            """no eggs?\b|egg free|eggs? allergy""" to listOf(DietOption.EGG),
            """\bnut free|no nuts|nut allergy|tree nut""" to listOf(DietOption.PEANUT, DietOption.TREENUT),
            "peanut" to listOf(DietOption.PEANUT), """\bsoy\b|soya""" to listOf(DietOption.SOY), "sesame" to listOf(DietOption.SESAME),
            """no fish|fish allergy|fish free""" to listOf(DietOption.FISH),
            """shellfish|crustacean|mollusc|no seafood|seafood allergy""" to listOf(DietOption.SHELLFISH),
            "wheat" to listOf(DietOption.WHEAT), "lupin" to listOf(DietOption.LUPIN), """sulph|sulfite|sulfur""" to listOf(DietOption.SULPHITES),
        )
        var diet = query.diet.options
        for ((pattern, options) in needs) {
            if (Regex(pattern).containsMatchIn(lower)) { diet = diet + options; said += Field.DIET }
        }
        query = query.copy(diet = DietFilter(diet))

        val remaining = lower.contains("left today") || lower.contains("what's left") || lower.contains("whats left") ||
            lower.contains("remaining") || lower.contains("rest of my day") || lower.contains("rest of today")
        var request = Request(query, emptyList(), remaining && Field.CALORIES !in said, said)
        var understood = summary(request, chainNames)
        // Leanrrr knows what's in an item, not how it was prepared or certified.
        if (lower.contains("halal")) understood = understood + "Halal isn't checked, only no pork"
        request = request.copy(understood = understood)
        return request
    }

    /** "Up to 600 Cal", "40 g protein", "Nando's", "Vegetarian"… */
    fun summary(request: Request, chainNames: Map<String, String>): List<String> {
        val q = request.query
        val parts = mutableListOf<String>()
        parts += if (request.usesRemaining) "What's left today" else "Up to ${q.calories.rounded().number} Cal"
        parts += if (q.sort == "protein" && Field.PROTEIN !in request.said) "Most protein" else "${q.protein.rounded().number} g protein"
        if (q.sort == "lean") parts += "Lowest calories"
        q.carbs?.let { parts += "Carbs up to ${it.number} g" }
        q.fat?.let { parts += "Fat up to ${it.number} g" }
        if (Field.ITEMS in request.said) parts += if (q.maxItems == 1) "One item" else "Up to ${q.maxItems} items"
        parts += q.chains.mapNotNull { chainNames[it] }.sorted()
        if (q.supermarket && q.chains.isEmpty()) parts += "Coles and Woolworths"
        if (!q.diet.isEmpty) parts += q.diet.summary
        return parts
    }
}
