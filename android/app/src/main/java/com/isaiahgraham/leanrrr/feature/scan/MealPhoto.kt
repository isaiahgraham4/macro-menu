package com.isaiahgraham.leanrrr.feature.scan

import com.isaiahgraham.leanrrr.data.AppleInstant
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.MenuRegion
import kotlinx.serialization.Serializable
import java.time.Instant

// Pure Kotlin (no Android classes), so the JUnit tests run it on the JVM. A port of MealPhoto.swift and PhotoMemory.swift,
// without the parts that need Apple's image classifier or Apple Intelligence (see MealPhotoScreen).

/** A food named for a photo: just what it is and how many. The figures always come from Leanrrr's own data. */
data class SeenFood(
    val name: String,
    /** Other names a food list might use ("chicken drumstick" for "chicken leg"), most specific first. */
    val alternatives: List<String> = emptyList(),
    /** The restaurant or brand, when packaging shows it. */
    val brand: String? = null,
    val count: Int = 1,
    /** False when it shouldn't be ticked for the user without them choosing it. */
    val agreed: Boolean = true,
    val size: PortionSize = PortionSize.REGULAR,
    /** Why it isn't ticked, when that's known. */
    val reason: String? = null,
)

/** A rough portion size for an everyday food, as a share of one serving. */
enum class PortionSize(val factor: Double) {
    SMALL(0.6), REGULAR(1.0), LARGE(1.5);

    val title: String get() = name.lowercase().replaceFirstChar { it.uppercase() }

    companion object {
        /** Portion sizes apply to everyday and your own foods. A restaurant's item is already one size. */
        fun applies(food: Food): Boolean = food.isEveryday || food.chain == "mine"
    }
}

object MealPhoto {
    /** A word without its plural, so "strawberry" finds "Strawberries" and "eggs" finds "Egg". */
    fun stem(word: String): String {
        if (word.endsWith("ies") && word.length > 4) return word.dropLast(3) + "y"
        for (ending in listOf("ches", "shes", "sses", "xes", "oes")) if (word.endsWith(ending) && word.length > 4) return word.dropLast(2)
        if (word.endsWith("s") && !word.endsWith("ss") && word.length > 3) return word.dropLast(1)
        return word
    }

    /** Whether two names mean the same food: one inside the other ("burger", "hamburger"), or a shared whole word. */
    fun same(a: SeenFood, b: SeenFood): Boolean {
        fun forms(food: SeenFood) = (listOf(food.name) + food.alternatives).map { it.lowercase() }
        for (x in forms(a)) for (y in forms(b)) {
            if (x.length >= 4 && y.length >= 4 && (x.contains(y) || y.contains(x))) return true
            val shared = ScanSearch.tokens(x).map(::stem).toSet().intersect(ScanSearch.tokens(y).map(::stem).toSet())
            if (shared.any { it.length >= 4 }) return true
        }
        return false
    }

    /** The version most people mean when a photo just says "rice" or "bread". */
    private val usual = setOf("White rice, cooked", "White bread", "Pasta, cooked", "Milk, full cream", "Garden salad, no dressing")

    /**
     * Matches in the order a person would expect: the food named exactly that, then foods whose main name ends with it,
     * then those that start with it; Leanrrr's own everyday foods before USDA survey foods; cooked before raw or dry;
     * plainer names first. Each source stays together, in the order the sources were found.
     */
    fun ordered(foods: List<Food>, words: List<String>): List<Food> {
        val stemmed = words.map(::stem)
        fun key(food: Food): IntArray {
            val all = ScanSearch.tokens(food.name).map(::stem)
            val main = ScanSearch.tokens(food.name.takeWhile { it != ',' }).map(::stem)
            val bucket = when {
                all == stemmed -> 0
                main.size >= stemmed.size && main.takeLast(stemmed.size) == stemmed -> 1
                main.size >= stemmed.size && main.take(stemmed.size) == stemmed -> 2
                else -> 3
            }
            val uncooked = if (all.any { it in setOf("raw", "dry", "uncooked", "powder", "canned") }) 1 else 0
            // "Rice, cooked" and "Egg" are the ingredient; "Spanish rice" and "Egg noodles" are dishes made with it.
            val dish = if (food.name.contains(",") || all.size == 1) 0 else 1
            return intArrayOf(bucket, if (food.isSurvey) 1 else 0, uncooked, dish, if (food.name in usual) 0 else 1, main.size)
        }
        val sources = LinkedHashSet<String>()
        foods.forEach { sources += it.chain }
        return sources.flatMap { source ->
            foods.filter { it.chain == source }.map { it to key(it) }.sortedWith { (a, ka), (b, kb) ->
                for (i in ka.indices) if (ka[i] != kb[i]) return@sortedWith ka[i].compareTo(kb[i])
                a.name.compareTo(b.name)
            }.map { it.first }
        }
    }

    /** Other names people and photos use for a chain, as lower-case letters only, to its id in the menu. */
    val brandAliases: Map<String, String> = mapOf(
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

    /** The restaurant a brand names, if it's one Leanrrr has: a known nickname first, then a close match to the chain's name. */
    fun chain(brand: String?, chainNames: Map<String, String>): String? {
        if (brand == null || brand.isBlank()) return null
        val letters = brand.lowercase().filter { it.isLetter() || it == ' ' }.trim()
        val written = brandAliases[letters] ?: brandAliases[letters.replace(" ", "")]
        if (written != null && written != Food.EVERYDAY) MenuRegion.chain(written, chainNames)?.let { return it }
        return chainNames.entries.sortedBy { it.key }.firstOrNull {
            it.key != Food.EVERYDAY && (ScanSearch.score(it.value, brand) == 0 || ScanSearch.score(brand, it.value) == 0)
        }?.key
    }

    /**
     * The match to tick by default. A restaurant's item is only ticked when the brand was shown or named, or when you're at
     * one of its restaurants (`nearby`); otherwise the first everyday food is ticked.
     */
    fun preselected(matches: List<Food>, seen: SeenFood, chainNames: Map<String, String>, nearby: String? = null): Food? {
        if (!seen.agreed) return null
        chain(seen.brand, chainNames)?.let { chain -> matches.firstOrNull { it.chain == chain }?.let { return it } }
        if (nearby != null) {
            val hit = matches.firstOrNull { it.chain == nearby }
            if (hit != null && matches.none { it.isEveryday && plainly(it, seen) }) return hit
        }
        return matches.firstOrNull { it.isEveryday }
    }

    /** Whether a food is plainly the thing seen: its name before any comma is the same words ("Banana, raw" for "banana"). */
    fun plainly(food: Food, seen: SeenFood): Boolean {
        val main = ScanSearch.tokens(food.name.takeWhile { it != ',' }).map(::stem)
        return (listOf(seen.name) + seen.alternatives).any { name -> ScanSearch.tokens(name).map(::stem) == main }
    }

    /**
     * Leanrrr foods that match what was seen, closest first. Every word must start a word of the food's name (no typo matching,
     * so "chair" never finds "Chai"). With a brand, its restaurant comes first; without one, everyday foods. The other names
     * are tried when the first finds nothing. `nearby` is a restaurant you're at: its two closest items go first.
     */
    fun matches(seen: SeenFood, foods: List<Food>, chainNames: Map<String, String>, limit: Int = 4, nearby: String? = null): List<Food> {
        val brand = chain(seen.brand, chainNames)
        val usual = lookUp(seen, foods, chainNames, brand, limit)
        if (brand != null || nearby == null || chainNames[nearby] == null) return usual
        val local = lookUp(seen, foods, chainNames, nearby, limit).filter { it.chain == nearby }.take(2)
        return (local + usual.filter { food -> local.none { it.id == food.id } }).take(limit)
    }

    private fun lookUp(seen: SeenFood, foods: List<Food>, chainNames: Map<String, String>, chain: String?, limit: Int): List<Food> {
        for (search in listOf(seen.name) + seen.alternatives) {
            val query = ScanSearch.Query(search)
            if (query.isEmpty) continue
            fun exact(place: String): List<Food> = ScanSearch.browse(foods, chainNames, search, place).filter { food ->
                // Each word starts a word of the name, with a couple of extra letters at most ("egg" finds "Eggs", "pepper" never "Pepperoni").
                val words = ScanSearch.tokens(food.name + " " + (chainNames[food.chain] ?: ""))
                query.words.all { word -> words.any { (it.startsWith(word) && it.length - word.length <= 2) || stem(it) == stem(word) } }
            }
            val found = exact(chain ?: Food.EVERYDAY).toMutableList()
            for (food in exact("all")) if (found.none { it.id == food.id }) found += food
            if (found.isNotEmpty()) return ordered(found, query.words).take(limit)
        }
        return emptyList()
    }
}

/**
 * What you logged for each food a photo named, so the next photo of it is ticked as that food and amount straight away.
 * Kept on this device only (preferences), never in your data or backups; "Delete all my data" should clear [STORAGE_KEY].
 */
object PhotoMemory {
    @Serializable
    data class Choice(
        val foodID: String,
        /** Servings for each one counted in the photo. */
        val perItem: Double,
        val used: AppleInstant,
    )

    const val STORAGE_KEY = "photo.choices"
    /** The most foods remembered; the ones used longest ago go first. */
    const val LIMIT = 200

    /** The same photo food however it was worded: "Strawberries" and "strawberry" share a key. */
    fun key(seen: SeenFood): String = ScanSearch.tokens(seen.name).map(MealPhoto::stem).joinToString(" ")

    fun choice(seen: SeenFood, choices: Map<String, Choice>): Choice? {
        val key = key(seen)
        return if (key.isEmpty()) null else choices[key]
    }

    data class Logged(val seen: SeenFood, val food: Food, val quantity: Double)

    /** The choices with what was just logged added: each food's pick and its amount per item seen. */
    fun remembering(logged: List<Logged>, choices: Map<String, Choice>, now: Instant = Instant.now()): Map<String, Choice> {
        val updated = choices.toMutableMap()
        for (item in logged) {
            val key = key(item.seen)
            val perItem = item.quantity / maxOf(item.seen.count, 1).toDouble()
            if (key.isEmpty() || !perItem.isFinite() || perItem <= 0) continue
            updated[key] = Choice(item.food.id, perItem, now)
        }
        if (updated.size > LIMIT) {
            updated.entries.sortedBy { it.value.used }.take(updated.size - LIMIT).map { it.key }.forEach { updated.remove(it) }
        }
        return updated
    }
}

/**
 * The foods named in words for a photo ("two eggs, toast and a flat white from Maccas"). A simple reading of the note:
 * split at commas and joining words, a leading count, and "from" a restaurant. Pairs that name one food in Leanrrr
 * ("fish and chips") are kept together when `known` says so.
 */
object NoteFoods {
    private val numbers = mapOf("a" to 1, "an" to 1, "one" to 1, "two" to 2, "three" to 3, "four" to 4, "five" to 5, "six" to 6,
        "seven" to 7, "eight" to 8, "nine" to 9, "ten" to 10, "eleven" to 11, "twelve" to 12, "some" to 1)
    private val joiners = setOf("and", "with", "plus", "then", "n")
    private val fillers = listOf(
        Regex("""\bi(?:'ve| have)? (?:just )?(?:had|ate|eaten)\b"""),
        Regex("""\bfor (?:breakfast|brekkie|lunch|dinner|tea|supper|a snack|snack|snacks|morning tea|afternoon tea|dessert)\b"""),
        Regex("""\b(?:today|tonight|this morning|this arvo|this afternoon|this evening|just now|earlier)\b"""),
    )

    fun read(text: String, known: (String) -> Boolean = { false }): List<SeenFood> {
        var cleaned = " " + text.lowercase().replace("’", "'").replace("&", " and ").replace("+", ",").replace(";", ",")
            .replace("\n", ",") + " "
        fillers.forEach { cleaned = cleaned.replace(it, " ") }
        val found = mutableListOf<SeenFood>()
        for (part in cleaned.split(",")) {
            val pieces = mutableListOf<Pair<String, String?>>()
            var current = mutableListOf<String>(); var joiner: String? = null
            for (word in spaceWords(part)) {
                if (word in joiners && current.isNotEmpty()) { pieces += current.joinToString(" ") to joiner; current = mutableListOf(); joiner = word }
                else current += word
            }
            if (current.isNotEmpty()) pieces += current.joinToString(" ") to joiner
            var i = 0
            while (i < pieces.size) {
                var piece = pieces[i].first
                while (i + 1 < pieces.size) {
                    val next = pieces[i + 1]
                    val joined = piece + " " + (if (next.second == "n") "and" else next.second) + " " + next.first
                    if (!known(phrase(joined)?.name ?: joined)) break
                    piece = joined; i += 1
                }
                phrase(piece)?.let { found += it }
                i += 1
            }
        }
        // "A burger and fries from Maccas": the brand covers everything that names no other.
        val brand = found.firstNotNullOfOrNull { it.brand }
        return if (brand == null) found else found.map { if (it.brand == null) it.copy(brand = brand) else it }
    }

    private fun phrase(text: String): SeenFood? {
        var words = spaceWords(text.trim()).toMutableList()
        var brand: String? = null
        val from = words.indexOfFirst { it == "from" || it == "at" }
        if (from >= 0 && from < words.size - 1) { brand = words.drop(from + 1).joinToString(" "); words = words.take(from).toMutableList() }
        var count = 1
        words.firstOrNull()?.let { first ->
            val n = first.toIntOrNull() ?: numbers[first]
            if (n != null) { count = n.coerceIn(1, 12); words.removeAt(0) }
        }
        if (words.firstOrNull() == "x") words.removeAt(0)
        val name = words.filter { it.any(Char::isLetterOrDigit) }.joinToString(" ").trim()
        if (name.isEmpty()) return null
        return SeenFood(name = name, brand = brand, count = count)
    }
}
