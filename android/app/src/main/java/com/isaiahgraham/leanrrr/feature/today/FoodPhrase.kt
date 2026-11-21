package com.isaiahgraham.leanrrr.feature.today

import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.MenuRegion
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.newId
import java.text.Normalizer
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * A food named in words (FoodPhrase.swift): typed or spoken ("two eggs", "200 g chicken breast", "a flat white from Maccas"),
 * or an ingredient line from a recipe ("2 cups (300 g) plain flour, sifted"). Only what and how much; the figures always come
 * from Leanrrr's own foods.
 */
data class FoodPhrase(
    /** What to search for, without amounts or preparation. */
    val name: String,
    /** The number given, or null when none was. */
    val amount: Double? = null,
    val unit: Unit? = null,
    /** A restaurant or brand the words named ("from KFC", "Maccas"). */
    val brand: String? = null,
    /** The line as written, for showing beside the match. */
    val original: String = name,
    /** Other names a food list might use. */
    val alternatives: List<String> = emptyList(),
) {
    enum class Unit { GRAM, MILLILITRE, CUP, TABLESPOON, TEASPOON, /** Counted things: a slice, a can, a bowl. Each is taken as one serving. */ EACH }

    /**
     * How many of `food`'s servings this is, and whether that came from the words or was a guess (an amount Leanrrr
     * couldn't relate to the food's serving, which the screen asks to be checked).
     */
    fun servings(food: Food): Pair<Double, Boolean> {
        val amount = this.amount ?: 1.0
        val unit = this.unit
        if (unit == null || amount <= 0) return Pair(max(amount, 0.25), this.amount != null || unit == null)
        val serve = food.serve.lowercase()
        val sameMeasure = (unit == Unit.CUP && "cup" in serve) ||
            (unit == Unit.TABLESPOON && ("tbsp" in serve || "tablespoon" in serve)) ||
            (unit == Unit.TEASPOON && ("tsp" in serve || "teaspoon" in serve))
        return when {
            unit == Unit.EACH -> Pair(amount, true)
            sameMeasure -> Pair(amount / max(leadingNumber(serve) ?: 1.0, 0.01), true)
            else -> {
                val grams = amount * when (unit) { Unit.CUP -> 250.0; Unit.TABLESPOON -> 15.0; Unit.TEASPOON -> 5.0; else -> 1.0 }
                val weight = food.servingWeight?.first?.takeIf { it > 0 } ?: return Pair(1.0, false)
                Pair(rounded(grams / weight), unit == Unit.GRAM || unit == Unit.MILLILITRE)
            }
        }
    }

    /** The phrase as something to look up, the way a photo's foods are: the name, then the name without size words. */
    val seen: SeenFood
        get() {
            val count = if (unit == null || unit == Unit.EACH) max(1, (amount ?: 1.0).roundToInt()) else 1
            if (brand == null) USUAL_NAMES[name]?.let { usual -> return SeenFood(usual, listOf(name) + alternatives, null, count) }
            val words = name.split(" ").filter { it.isNotEmpty() }
            val plain = words.filter { it !in SIZES }.joinToString(" ")
            // Last, the name without its first word: "light soy sauce" finds "Soy sauce". Only when what's left is still two
            // words or the first was just a description, so "baking soda" never becomes "soda".
            val rest = words.drop(1)
            val shorter = if (words.size >= 2 && (rest.size >= 2 || words[0] in DESCRIBING)) rest.joinToString(" ") else ""
            val others = ((if (plain != name && plain.isNotEmpty()) listOf(plain) else emptyList()) + alternatives + listOf(shorter))
                .filter { it.isNotEmpty() && it != name }.distinct()
            return SeenFood(name, others, brand, count)
        }

    companion object {
        /** Servings to a sensible step: quarters, or tenths for small amounts. */
        fun rounded(value: Double): Double = if (value < 1) max(0.1, Math.round(value * 10) / 10.0) else Math.round(value * 4) / 4.0

        fun leadingNumber(text: String): Double? = quantity(words(text).toMutableList())

        /** Size words that a restaurant's menu uses ("Large Fries") but a list of everyday foods doesn't. */
        private val SIZES = setOf("large", "medium", "small", "regular", "big", "little", "mini", "whole", "plain", "homemade", "fresh", "hot", "cold", "iced")

        /** What people usually mean by a word that also starts a dish's name: "toast" is bread, not French toast. */
        val USUAL_NAMES = mapOf(
            "toast" to "white bread", "slice of toast" to "white bread", "white toast" to "white bread", "wholemeal toast" to "wholemeal bread",
            "sourdough toast" to "sourdough bread", "multigrain toast" to "multigrain bread", "rye toast" to "rye bread",
            "vegetable oil" to "canola oil", "cooking oil" to "canola oil", "oil" to "olive oil", "extra virgin olive oil" to "olive oil", "virgin olive oil" to "olive oil",
            "coffee" to "black coffee", "long black" to "black coffee", "short black" to "black coffee", "espresso" to "black coffee",
        )

        /** Words that describe a food rather than name it. */
        private val DESCRIBING = setOf(
            "light", "lite", "plain", "dark", "raw", "unsalted", "salted", "reduced", "low", "full", "whole", "brown", "white", "red", "green",
            "yellow", "dried", "frozen", "canned", "tinned", "natural", "greek", "baby", "free", "lean", "smoked", "toasted", "cooked", "boneless", "skinless",
        )

        /**
         * The match to tick: the brand's item when one was named, an everyday food, or the only restaurant that has it
         * ("big mac" is only at McDonald's). A "cheeseburger" from no particular place is left for the person to choose.
         */
        fun preselected(matches: List<Food>, phrase: FoodPhrase, chainNames: Map<String, String>): Food? {
            FoodMatching.preselected(matches, phrase.seen, chainNames)?.let { return it }
            val first = matches.firstOrNull() ?: return null
            if (phrase.brand != null || !matches.all { it.chain == first.chain }) return null
            return first
        }

        // Meals in words

        /**
         * The foods in a sentence: "two eggs, toast with butter and a flat white". `known` says whether some words are one food
         * ("fish and chips", "mac and cheese"), so those aren't split.
         */
        fun meal(text: String, known: (String) -> Boolean = { false }): List<FoodPhrase> {
            var cleaned = " " + text.lowercase()
                .replace("’", "'").replace("&", " and ").replace("+", ",").replace(";", ",").replace("\n", ",").replace(".", ",") + " "
            // Numbers with a decimal point lost their point above; put it back ("1,5 kg" from "1.5 kg").
            cleaned = cleaned.replace(Regex("""(\d),(\d)"""), "$1.$2")
            for (filler in listOf(
                """\bi(?:'ve| have)? (?:just )?(?:had|ate|eaten)\b""",
                """\bfor (?:breakfast|brekkie|lunch|dinner|tea|supper|a snack|snack|snacks|morning tea|afternoon tea|dessert)\b""",
                """\b(?:today|tonight|this morning|this arvo|this afternoon|this evening|just now|earlier)\b""",
                """^\s*(?:had|ate)\b""",
            )) cleaned = cleaned.replace(Regex(filler), " ")
            val phrases = mutableListOf<FoodPhrase>()
            for (part in cleaned.split(",")) {
                for (piece in joinKnown(split(part), known)) phrase(piece, recipe = false)?.let { phrases += it }
            }
            // "A Big Mac and large fries from Maccas": the brand covers everything that names no other.
            val brand = phrases.firstNotNullOfOrNull { it.brand }
            return if (brand == null) phrases else phrases.map { if (it.brand == null) it.copy(brand = brand) else it }
        }

        /** One food's words, not split on "and": "2 slices of raisin toast". */
        fun food(text: String): FoodPhrase? = phrase(text.lowercase(), recipe = false)

        private val JOINERS = listOf("and", "with", "plus", "then", "n")

        /** Splits on "and", "with" and "plus", keeping each joining word so known pairs can be put back. */
        private fun split(text: String): List<Pair<String, String?>> {
            val pieces = mutableListOf<Pair<String, String?>>()
            val current = mutableListOf<String>()
            var joiner: String? = null
            for (word in text.split(" ").filter { it.isNotEmpty() }) {
                if (word in JOINERS && current.isNotEmpty()) {
                    pieces += current.joinToString(" ") to joiner; current.clear(); joiner = word
                } else current += word
            }
            if (current.isNotEmpty()) pieces += current.joinToString(" ") to joiner
            return pieces
        }

        /** Puts back pairs that name one food, like "fish and chips". */
        private fun joinKnown(pieces: List<Pair<String, String?>>, known: (String) -> Boolean): List<String> {
            val result = mutableListOf<String>()
            var index = 0
            while (index < pieces.size) {
                var text = pieces[index].first
                while (index + 1 < pieces.size) {
                    val joiner = pieces[index + 1].second ?: break
                    val joined = text + " " + (if (joiner == "n") "and" else joiner) + " " + pieces[index + 1].first
                    if (!known(bare(joined))) break
                    text = joined; index += 1
                }
                result += text; index += 1
            }
            return result
        }

        /** The words without amounts or brand, as `known` sees them. */
        private fun bare(text: String): String = phrase(text, recipe = false)?.name ?: text

        // Recipe ingredients

        /** One ingredient line from a recipe. Null for lines that aren't a food (an empty line or a heading). */
        fun ingredient(line: String): FoodPhrase? {
            var text = line.lowercase().replace("’", "'")
            // A weight in brackets is more exact than cups or a count: "1 cup (150 g) flour", "2 x 400g cans tomatoes".
            var bracket: Pair<Double, Unit>? = null
            Regex("""\((?:about |approx\.? )?(\d+(?:\.\d+)?)\s*(g|kg|ml|l)\b[^)]*\)""").find(text)?.let { m ->
                val value = m.groupValues[1].toDoubleOrNull() ?: 0.0
                val unit = m.groupValues[2]
                bracket = Pair(value * (if (unit == "kg" || unit == "l") 1000 else 1), if (unit == "g" || unit == "kg") Unit.GRAM else Unit.MILLILITRE)
            }
            text = text.replace(Regex("""\([^)]*\)"""), " ")
            // Preparation notes come after a comma or a dash: "onion, finely chopped".
            val cut = text.indexOfFirst { it == ',' || it == '—' }
            if (cut >= 0) text = text.substring(0, cut)
            text = text.replace(Regex("""(?<!\d)\s?–\s?(?!\d).*$"""), "")
            text = text.replace(Regex("""(?<!\d)\s-\s(?!\d).*$"""), "")
            var phrase = phrase(text, recipe = true) ?: return null
            phrase = phrase.copy(original = line.trim())
            // "cornflour / corn starch", "butter or margarine": the first is the name, the rest are other names for it.
            val names = phrase.name.split("/").flatMap { it.split(" or ") }.map { it.trim { ch -> !ch.isLetterOrDigit() } }.filter { n -> n.any { it.isLetter() } }
            if (names.size > 1) phrase = phrase.copy(name = names[0], alternatives = names.drop(1))
            bracket?.let { (grams, unit) ->
                if (phrase.unit != Unit.GRAM && phrase.unit != Unit.MILLILITRE) {
                    phrase = phrase.copy(amount = grams * (if (phrase.unit == Unit.EACH || phrase.unit == null) phrase.amount ?: 1.0 else 1.0), unit = unit)
                }
            }
            return phrase
        }

        /** Words a recipe uses for how something's prepared, which a food list doesn't. */
        private val PREPARATION = setOf(
            "chopped", "diced", "sliced", "minced", "grated", "shredded", "crushed", "peeled", "trimmed", "halved", "quartered",
            "finely", "roughly", "thinly", "coarsely", "freshly", "fresh", "packed", "heaped", "level", "softened", "melted",
            "beaten", "lightly", "sifted", "drained", "rinsed", "cubed", "torn", "picked", "deseeded", "seeded", "large", "medium", "small",
            "extra", "good", "quality", "organic", "plus", "optional", "about", "approximately", "approx",
        )

        // Parsing one food

        private val NUMBERS = mapOf(
            "a" to 1.0, "an" to 1.0, "one" to 1.0, "two" to 2.0, "three" to 3.0, "four" to 4.0, "five" to 5.0, "six" to 6.0, "seven" to 7.0,
            "eight" to 8.0, "nine" to 9.0, "ten" to 10.0, "eleven" to 11.0, "twelve" to 12.0, "half" to 0.5, "quarter" to 0.25, "couple" to 2.0,
            "few" to 3.0, "dozen" to 12.0,
        )
        private val FRACTIONS = mapOf('½' to 0.5, '¼' to 0.25, '¾' to 0.75, '⅓' to 1.0 / 3, '⅔' to 2.0 / 3, '⅛' to 0.125)
        private val UNITS: Map<String, Pair<Unit, Double>> = buildMap {
            fun add(unit: Unit, scale: Double, vararg names: String) = names.forEach { put(it, unit to scale) }
            add(Unit.GRAM, 1.0, "g", "gram", "grams", "gm")
            add(Unit.GRAM, 1000.0, "kg", "kgs", "kilo", "kilos")
            add(Unit.GRAM, 28.35, "oz", "ounce", "ounces")
            add(Unit.GRAM, 453.6, "lb", "lbs", "pound", "pounds")
            add(Unit.MILLILITRE, 1.0, "ml", "mls", "millilitre", "millilitres", "milliliter", "milliliters")
            add(Unit.MILLILITRE, 1000.0, "l", "litre", "litres", "liter", "liters")
            add(Unit.CUP, 1.0, "cup", "cups")
            add(Unit.TABLESPOON, 1.0, "tbsp", "tbs", "tablespoon", "tablespoons")
            add(Unit.TEASPOON, 1.0, "tsp", "teaspoon", "teaspoons")
            add(Unit.EACH, 1.0, "slice", "slices", "piece", "pieces", "serve", "serves", "serving", "servings", "portion", "portions", "can", "cans",
                "tin", "tins", "bottle", "bottles", "glass", "glasses", "bowl", "bowls", "plate", "plates", "handful", "handfuls",
                "scoop", "scoops", "packet", "packets", "bar", "bars", "clove", "cloves", "stem", "stems", "bunch", "bunches",
                "head", "heads", "leaf", "leaves", "stalk", "stalks", "pinch", "dash", "sprig", "sprigs")
        }
        private val FILLERS = setOf("of", "the", "some", "my", "x", "×", "bit", "little", "lot", "lots", "about", "around", "like", "maybe", "approx")
        private val PLAIN_NUMBER = Regex("""^\d*\.?\d+$""")
        private val RANGE = Regex("""^(\d+(?:\.\d+)?)[-–](\d+(?:\.\d+)?)$""")

        private fun numberOf(text: String): Double? = if (PLAIN_NUMBER.matches(text)) text.toDoubleOrNull() else null
        private fun isNumeral(ch: Char) = ch.isDigit() || ch in FRACTIONS

        /** Words, with numbers parted from units ("200g" to "200 g", "x2" to "x 2"). */
        private fun words(text: String): List<String> {
            val spaced = StringBuilder()
            var previous: Char? = null
            for (ch in text) {
                if (previous != null && ((isNumeral(previous) && ch.isLetter()) || (previous.isLetter() && isNumeral(ch)) || ch in FRACTIONS)) spaced.append(' ')
                spaced.append(ch); previous = ch
            }
            return spaced.split(' ', '\t').filter { it.isNotEmpty() }
        }

        /** Takes a quantity off the front of the words: "2", "1.5", "1 1/2", "½", "two", "a couple of", "half a". */
        private fun quantity(tokens: MutableList<String>): Double? {
            var total: Double? = null
            while (tokens.isNotEmpty()) {
                val first = tokens[0]
                val value = numberOf(first)
                val range = RANGE.find(first)
                when {
                    value != null -> {
                        total = (total ?: 0.0) + value; tokens.removeAt(0)
                        // "2 to 3", "2 or 3": take the first.
                        if (tokens.size > 1 && tokens[0] in listOf("to", "or", "-", "–") && numberOf(tokens[1]) != null) { tokens.removeAt(0); tokens.removeAt(0) }
                    }
                    range != null -> { total = (total ?: 0.0) + (range.groupValues[1].toDoubleOrNull() ?: 0.0); tokens.removeAt(0) }
                    '/' in first && fraction(first) != null -> { total = (total ?: 0.0) + fraction(first)!!; tokens.removeAt(0) }
                    first.length == 1 && FRACTIONS[first[0]] != null -> { total = (total ?: 0.0) + FRACTIONS[first[0]]!!; tokens.removeAt(0) }
                    total == null && NUMBERS[first] != null -> {
                        val word = NUMBERS[first]!!
                        tokens.removeAt(0)
                        // "half a sandwich", "a couple of eggs", "a dozen eggs", "a half".
                        if ((word == 0.5 || word == 0.25) && tokens.firstOrNull() in listOf("a", "an")) tokens.removeAt(0)
                        val next = tokens.firstOrNull()
                        total = if ((first == "a" || first == "an") && next != null && NUMBERS[next] != null && next !in listOf("a", "an")) {
                            tokens.removeAt(0); NUMBERS[next]
                        } else word
                        return total
                    }
                    else -> return total
                }
            }
            return total
        }

        private fun fraction(text: String): Double? {
            val parts = text.split("/")
            if (parts.size != 2) return null
            val top = numberOf(parts[0]) ?: return null
            val bottom = numberOf(parts[1])?.takeIf { it > 0 } ?: return null
            return top / bottom
        }

        /** One food's words to a phrase. Null when nothing's left to search for. */
        private fun phrase(text: String, recipe: Boolean): FoodPhrase? {
            val original = text.trim()
            var working = " $original "
            var brand: String? = null
            Regex("""\s(?:from|at)\s+(.+?)\s*$""").find(working)?.let { m ->
                brand = m.groupValues[1].trim(); working = working.substring(0, m.range.first)
            }
            val tokens = words(working).toMutableList()
            // "Maccas cheeseburger", "a KFC zinger": a known nickname at the start is the brand.
            if (brand == null) {
                loop@ for (skip in listOf(0, 1)) {
                    if (tokens.size <= skip + 1) continue
                    if (skip == 1 && tokens[0] !in listOf("a", "an", "some", "the", "my") && numberOf(tokens[0]) == null && NUMBERS[tokens[0]] == null) continue
                    for (length in listOf(3, 2, 1)) {
                        if (tokens.size <= skip + length) continue
                        val candidate = tokens.subList(skip, skip + length).joinToString(" ")
                        if (FoodMatching.BRAND_ALIASES[candidate.filter { it.isLetter() || it == ' ' }] != null) {
                            brand = candidate
                            repeat(length) { tokens.removeAt(skip) }
                            break@loop
                        }
                    }
                }
            }
            var amount = quantity(tokens)
            var unit: Unit? = null
            fun takeUnit() {
                val first = tokens.firstOrNull()?.trim('.') ?: return
                val (found, scale) = UNITS[first] ?: return
                // "a can of coke" counts; "glass" in "glass noodles" with nothing before it doesn't.
                if (amount == null && !(tokens.size > 1 && tokens[1] == "of")) return
                tokens.removeAt(0); unit = found; amount = (amount ?: 1.0) * scale
            }
            takeUnit()
            // "1 x 400 g can of tomatoes": a count, then a size.
            if ((tokens.firstOrNull() == "x" || tokens.firstOrNull() == "×") && tokens.size > 1 && numberOf(tokens[1]) != null) {
                tokens.removeAt(0)
                val count = amount ?: 1.0
                amount = quantity(tokens); unit = null; takeUnit()
                amount = (amount ?: 1.0) * count
                if (unit == null) unit = Unit.EACH
                tokens.firstOrNull()?.let { next -> if (UNITS[next]?.first == Unit.EACH) tokens.removeAt(0) }
            }
            while (tokens.isNotEmpty() && (tokens[0] in FILLERS || (recipe && tokens[0] in PREPARATION))) tokens.removeAt(0)
            // A count after the name: "eggs x2", "coffee × 2".
            if (amount == null && tokens.size >= 2 && tokens[tokens.size - 2] in listOf("x", "×") && numberOf(tokens.last()) != null) {
                amount = numberOf(tokens.last()); tokens.removeAt(tokens.size - 1); tokens.removeAt(tokens.size - 1)
            } else if (amount == null && tokens.lastOrNull()?.startsWith("x") == true && numberOf(tokens.last().drop(1)) != null) {
                amount = numberOf(tokens.last().drop(1)); tokens.removeAt(tokens.size - 1)
            }
            var final: List<String> = tokens
            if (recipe) {
                final = final.filter { it !in PREPARATION }
                for (ending in listOf(listOf("to", "taste"), listOf("to", "serve"), listOf("for", "serving"), listOf("for", "garnish"), listOf("to", "garnish"), listOf("if", "needed"))) {
                    val start = final.indices.firstOrNull { i -> final.drop(i).take(ending.size) == ending }
                    if (start != null) final = final.take(start)
                }
            }
            val name = final.filter { it !in FILLERS || final.size == 1 }.joinToString(" ").trim { !it.isLetterOrDigit() }
            if (name.none { it.isLetter() }) return null
            return FoodPhrase(name, amount, unit, brand, original)
        }
    }
}

/** Something to look up: a food named by a photo or in words (SeenFood in MealPhoto.swift). */
data class SeenFood(
    val name: String,
    /** Other names a food list might use, most specific first. */
    val alternatives: List<String> = emptyList(),
    /** The restaurant or brand, when one was named. */
    val brand: String? = null,
    val count: Int = 1,
)

/**
 * Finding Leanrrr foods for words (the matching half of MealPhoto.swift, which the Scan feature owns; a private copy here so
 * Describe your meal works on its own).
 */
object FoodMatching {
    /** Other names people use for a chain, as lower-case letters only, to its id in the menu. */
    val BRAND_ALIASES = mapOf(
        "maccas" to "mcd", "macca" to "mcd", "mcdonalds" to "mcd", "mcdonald" to "mcd", "golden arches" to "mcd",
        "hungryjacks" to "hj", "hungry jacks" to "hj", "hj" to "hj", "burgerking" to "hj", "burger king" to "hj",
        "kfc" to "kfc", "kentuckyfriedchicken" to "kfc", "kentucky fried chicken" to "kfc",
        "gyg" to "gyg", "guzman" to "gyg", "guzmanygomez" to "gyg", "guzman y gomez" to "gyg",
        "nandos" to "nandos", "dominos" to "dominos", "dominospizza" to "dominos", "redrooster" to "rr", "red rooster" to "rr",
        "subway" to "sub", "oporto" to "oporto", "zambrero" to "zam", "boost" to "boost", "boostjuice" to "boost", "boost juice" to "boost",
        "schnitz" to "schnitz", "grilld" to "grilld",
        "bettys" to "betty", "bettys burgers" to "betty", "betty's burgers" to "betty", "fiveguys" to "fiveguys", "five guys" to "fiveguys",
        "crust" to "crust", "crust pizza" to "crust",
        "donutking" to "donutking", "donut king" to "donutking", "michels" to "michels", "michel's" to "michels", "michels patisserie" to "michels",
        "brumbys" to "brumbys", "brumby's" to "brumbys", "soulorigin" to "soul", "soul origin" to "soul", "rolld" to "rolld", "roll'd" to "rolld",
        "thisbowl" to "thisbowl", "fishbowl" to "thisbowl",
        "chickfila" to "us-cfa", "chick fil a" to "us-cfa", "wendys" to "us-wendys", "taco bell" to "us-tacobell", "tacobell" to "us-tacobell",
        "panda express" to "us-panda", "pandaexpress" to "us-panda", "popeyes" to "us-popeyes",
        "tim hortons" to "ca-tims", "timhortons" to "ca-tims", "tims" to "ca-tims", "greggs" to "uk-greggs",
        "wimpy" to "za-wimpy", "debonairs" to "za-debonairs", "debonairs pizza" to "za-debonairs", "kauai" to "za-kauai",
        "pizza hut" to "in-pizzahut", "pizzahut" to "in-pizzahut",
    )
    private val USUAL = setOf("White rice, cooked", "White bread", "Pasta, cooked", "Milk, full cream", "Garden salad, no dressing")
    private val COMBINING = Regex("""\p{Mn}+""")

    /** Lower-case words without accents or apostrophes (FoodSearch.tokens). */
    fun tokens(text: String): List<String> =
        Normalizer.normalize(text.lowercase(), Normalizer.Form.NFD).replace(COMBINING, "").replace("'", "").replace("’", "")
            .split(Regex("""[^\p{L}\p{N}]+""")).filter { it.isNotEmpty() }

    fun stem(word: String): String {
        if (word.endsWith("ies") && word.length > 4) return word.dropLast(3) + "y"
        for (ending in listOf("ches", "shes", "sses", "xes", "oes")) if (word.endsWith(ending) && word.length > 4) return word.dropLast(2)
        if (word.endsWith("s") && !word.endsWith("ss") && word.length > 3) return word.dropLast(1)
        return word
    }

    /** The restaurant a brand names, if it's one Leanrrr has: a known nickname first, then a close match to the chain's name. */
    fun chain(brand: String?, chainNames: Map<String, String>): String? {
        if (brand.isNullOrBlank()) return null
        val letters = brand.lowercase().filter { it.isLetter() || it == ' ' }.trim()
        val written = BRAND_ALIASES[letters] ?: BRAND_ALIASES[letters.replace(" ", "")]
        if (written != null && written != Food.EVERYDAY) MenuRegion.chain(written, chainNames)?.let { return it }
        val wanted = tokens(brand)
        return chainNames.entries.sortedBy { it.key }.firstOrNull { (id, name) ->
            val words = tokens(name)
            id != Food.EVERYDAY && wanted.isNotEmpty() && (words == wanted || words.joinToString("") == wanted.joinToString(""))
        }?.key
    }

    /** The match to tick by default: the named brand's item, otherwise the first everyday food. */
    fun preselected(matches: List<Food>, seen: SeenFood, chainNames: Map<String, String>): Food? {
        chain(seen.brand, chainNames)?.let { chain -> matches.firstOrNull { it.chain == chain }?.let { return it } }
        return matches.firstOrNull { it.isEveryday }
    }

    /** A food with its words worked out once, so many phrases can be matched quickly. */
    class Indexed(val food: Food, val words: List<String>)

    fun index(foods: List<Food>, chainNames: Map<String, String>): List<Indexed> =
        foods.map { Indexed(it, tokens(it.name + " " + (chainNames[it.chain] ?: ""))) }

    /**
     * Leanrrr foods that match what was seen, closest first. Every word must start a word of the food's name (no typo matching,
     * so "chair" never finds "Chai"). With a brand, its restaurant comes first; without one, everyday foods. The other names are
     * tried when the first finds nothing.
     */
    fun matches(seen: SeenFood, foods: List<Indexed>, chainNames: Map<String, String>, limit: Int = 4): List<Food> {
        val brand = chain(seen.brand, chainNames)
        for (search in listOf(seen.name) + seen.alternatives) {
            val query = tokens(search)
            if (query.isEmpty()) continue
            val stems = query.map(::stem)
            fun hits(item: Indexed) = query.indices.all { i ->
                val word = query[i]
                item.words.any { (it.startsWith(word) && it.length - word.length <= 2) || stem(it) == stems[i] }
            }
            val place = brand ?: Food.EVERYDAY
            val found = foods.filter { it.food.chain == place && hits(it) }.map { it.food }.toMutableList()
            val ids = found.map { it.id }.toMutableSet()
            for (item in foods) if (item.food.id !in ids && hits(item)) { found += item.food; ids += item.food.id }
            if (found.isNotEmpty()) return ordered(found, query).take(limit)
        }
        return emptyList()
    }

    /**
     * Matches in the order a person would expect: the food named exactly that, then foods whose main name ends with it, then
     * those that start with it; everyday foods before survey foods; cooked before raw; plainer names first. Each source stays together.
     */
    private fun ordered(foods: List<Food>, words: List<String>): List<Food> {
        val wanted = words.map(::stem)
        fun key(food: Food): List<Int> {
            val all = tokens(food.name).map(::stem)
            val main = tokens(food.name.substringBefore(",")).map(::stem)
            val bucket = when {
                all == wanted -> 0
                main.size >= wanted.size && main.takeLast(wanted.size) == wanted -> 1
                main.take(wanted.size) == wanted -> 2
                else -> 3
            }
            val uncooked = if (all.any { it in listOf("raw", "dry", "uncooked", "powder", "canned") }) 1 else 0
            val dish = if (food.name.contains(",") || all.size == 1) 0 else 1
            return listOf(bucket, if (food.isSurvey) 1 else 0, uncooked, dish, if (food.name in USUAL) 0 else 1, main.size)
        }
        val comparator = Comparator<Food> { a, b ->
            val ka = key(a); val kb = key(b)
            ka.indices.firstOrNull { ka[it] != kb[it] }?.let { ka[it].compareTo(kb[it]) } ?: a.name.compareTo(b.name)
        }
        val sources = foods.map { it.chain }.distinct()
        return sources.flatMap { source -> foods.filter { it.chain == source }.sortedWith(comparator) }
    }
}

/** One food named in a sentence, the Leanrrr foods that match it, and how much to use (FoodMatchRow in FoodMatchList.swift). */
data class FoodMatchRow(
    val id: String = newId(),
    /** What was written, for the header. */
    val title: String,
    val matches: List<Food>,
    /** The match to use, or null to leave this one out. */
    val chosen: String?,
    val quantity: Double,
    /** The words, so the amount can be worked out again when another match is chosen. */
    val phrase: FoodPhrase? = null,
    /** False when the amount is a guess that should be checked. */
    val sure: Boolean = true,
    /** Said above the picker when nothing is chosen. */
    val unchosenNote: String? = null,
) {
    val food: Food? get() = matches.firstOrNull { it.id == chosen }
    val portion: Portion? get() = food?.let { Portion(food = it, quantity = quantity) }

    /** Sets the amount from the words for the chosen match. */
    fun withAmount(): FoodMatchRow {
        val phrase = phrase ?: return this
        val food = food ?: return this
        val (servings, sure) = phrase.servings(food)
        return copy(quantity = servings, sure = sure)
    }

    companion object {
        /** A row for typed words, with the likely match ticked and its amount worked out. */
        fun make(phrase: FoodPhrase, title: String, foods: List<FoodMatching.Indexed>, chainNames: Map<String, String>, preselect: Boolean = true): FoodMatchRow {
            val matches = FoodMatching.matches(phrase.seen, foods, chainNames, 4)
            val chosen = if (preselect) FoodPhrase.preselected(matches, phrase, chainNames) else null
            return FoodMatchRow(
                title = title.take(1).uppercase() + title.drop(1), matches = matches, chosen = chosen?.id, quantity = 1.0, phrase = phrase,
                unchosenNote = if (phrase.brand == null) "Several places have this. Pick the one you had."
                else "Nothing from ${phrase.brand} matched. Pick the closest, or search for it.",
            ).withAmount()
        }
    }
}
