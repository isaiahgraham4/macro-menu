package com.isaiahgraham.leanrrr.feature.find

import com.isaiahgraham.leanrrr.data.Food
import java.text.Normalizer
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.max
import kotlin.math.min

/**
 * Forgiving food search (FoodSearch.swift): every word must appear in the text, allowing a typo or two
 * ("mchicken" finds "McChicken", "nugets" finds "Nuggets"). Lower scores are closer matches.
 */
object FoodSearch {
    /** A food's searchable words, worked out once so each keystroke only compares. */
    class Prepared(text: String) {
        val candidates: List<String>
        val letters: List<IntArray>
        init {
            val parts = tokens(text)
            // Adjacent pairs let "mc chicken" and "mcchicken" find each other.
            candidates = parts + (0 until max(0, parts.size - 1)).map { parts[it] + parts[it + 1] }
            letters = candidates.map(::letters)
        }
    }

    class Query(text: String) {
        val words: List<String> = tokens(text)
        val letters: List<IntArray> = words.map(::letters)
        val isEmpty: Boolean get() = words.isEmpty()
    }

    /** One number per character, so comparing words is quick. */
    fun letters(word: String): IntArray = word.codePoints().toArray()

    private val cache = ConcurrentHashMap<String, Prepared>()
    fun prepared(text: String): Prepared = cache.getOrPut(text) { Prepared(text) }

    fun score(text: String, query: String): Int? = score(Prepared(text), Query(query))

    fun score(item: Prepared, query: Query): Int? {
        var total = 0
        for ((index, word) in query.words.withIndex()) {
            val letters = query.letters[index]
            if (item.candidates.any { it.contains(word) }) continue
            val allowed = if (letters.size >= 7) 2 else if (letters.size >= 4) 1 else 0
            if (allowed <= 0) return null
            var best = allowed + 1
            for (candidate in item.letters) {
                // People rarely mistype the first letter, so a different first letter costs extra.
                val penalty = if (candidate.firstOrNull() == letters.firstOrNull()) 0 else 1
                val limit = best - 1 - penalty
                if (limit < 0) continue
                val found = closeness(letters, candidate, limit) ?: continue
                best = found + penalty
            }
            if (best > allowed) return null
            total += best
        }
        return total
    }

    /**
     * The fewest edits between the word and the candidate, or the start of the candidate, so a half-typed word still matches.
     * Null when that's more than the limit.
     */
    fun closeness(word: IntArray, candidate: IntArray, limit: Int): Int? {
        if (word.isEmpty() || candidate.isEmpty()) {
            val m = max(word.size, candidate.size)
            return if (m <= limit) m else null
        }
        val row = IntArray(candidate.size + 1) { it }
        for (i in 1..word.size) {
            var previous = row[0]; row[0] = i
            var smallest = i
            for (j in 1..candidate.size) {
                val current = row[j]
                row[j] = if (word[i - 1] == candidate[j - 1]) previous else min(min(previous, row[j]), row[j - 1]) + 1
                smallest = min(smallest, row[j])
                previous = current
            }
            // Later rows never get smaller than this one's smallest value.
            if (smallest > limit) return null
        }
        // The last row holds the distance to each prefix of the candidate.
        val lengths = (max(1, word.size - 1)..(word.size + 1)).map { min(it, candidate.size) } + candidate.size
        val best = lengths.minOf { row[it] }
        return if (best <= limit) best else null
    }

    /** What the Best choices list is showing. */
    data class Browse(
        val search: String = "",
        val chain: String = "all",
        val category: String = "all",
        val sort: String = "density",
        /** Your own foods before everything else, however close a menu item matches. */
        val mineFirst: Boolean = false,
    )

    /**
     * Foods for the Best choices list: exact matches first, then typos from closest to furthest; each group in the chosen order.
     * With `mineFirst`, your own foods come before all of that. Gives up early, returning nothing, if cancelled.
     */
    fun browse(foods: List<Food>, chainNames: Map<String, String>, request: Browse, isCancelled: () -> Boolean = { false }): List<Food> {
        val query = Query(request.search)
        val scores = HashMap<String, Int>()
        var rows = foods.filter { food ->
            if (isCancelled()) return@filter false
            if (!(request.chain == "all" || food.chain == request.chain) || !(request.category == "all" || food.cat == request.category) || food.cat == "swap") return@filter false
            if (query.isEmpty) return@filter true
            val score = score(prepared(food.name + " " + (chainNames[food.chain] ?: "My foods")), query) ?: return@filter false
            // Among equally close matches, the food named exactly that comes first, then names whose main part ends with it,
            // then names that start with it, then the rest.
            val name = tokens(food.name)
            val bonus = if (name == query.words) 3 else if (endsWith(food.name, query.words)) 2 else if (startsWith(food.name, query.words)) 1 else 0
            scores[food.id] = score * 4 - bonus
            true
        }
        if (isCancelled()) return emptyList()
        if (request.sort == "value") rows = rows.filter { (it.price ?: 0.0) > 0 }
        rows = rows.sortedWith { a, b ->
            val sa = scores[a.id] ?: 0; val sb = scores[b.id] ?: 0
            if (sa != sb) return@sortedWith sa.compareTo(sb)
            // Foods other people shared come after published figures that match as well.
            if (a.isCommunity != b.isCommunity) return@sortedWith if (b.isCommunity) -1 else 1
            when (request.sort) {
                "protein" -> b.p.compareTo(a.p)
                "calories" -> a.cal.compareTo(b.cal)
                "value" -> (b.p / (b.price ?: 1.0)).compareTo(a.p / (a.price ?: 1.0))
                "name" -> a.name.compareTo(b.name)
                else -> (b.p / max(b.cal, 1.0)).compareTo(a.p / max(a.cal, 1.0))
            }
        }
        if (request.mineFirst) rows = rows.filter { it.chain == "mine" } + rows.filter { it.chain != "mine" }
        return rows
    }

    /**
     * The closest foods for typed words (Today, Meal and My foods search with it): `browse` for the words, at most `limit`.
     * Nothing for an empty search.
     */
    fun search(query: String, foods: List<Food>, chainNames: Map<String, String>, limit: Int = 60): List<Food> {
        if (Query(query).isEmpty) return emptyList()
        return browse(foods, chainNames, Browse(search = query)).take(limit)
    }

    /** Whether the name begins with the searched words, the last of which may still be half typed. */
    fun startsWith(name: String, words: List<String>): Boolean {
        val names = tokens(name)
        val last = words.lastOrNull() ?: return false
        if (names.size < words.size) return false
        return names.take(words.size - 1) == words.dropLast(1) && names[words.size - 1].startsWith(last)
    }

    /** Whether the name's main part (before any comma) ends with the searched words: the thing itself, not something made with it. */
    fun endsWith(name: String, words: List<String>): Boolean {
        val main = tokens(name.substringBefore(','))
        return words.isNotEmpty() && main.size >= words.size && main.takeLast(words.size) == words
    }

    /** Items that match, closest first; ties keep their original order. */
    fun <T> filter(items: List<T>, query: String, text: (T) -> String): List<T> {
        val q = Query(query)
        if (q.isEmpty) return items
        return items.mapIndexedNotNull { index, item -> score(Prepared(text(item)), q)?.let { Triple(index, it, item) } }
            .sortedWith(compareBy<Triple<Int, Int, T>> { it.second }.thenBy { it.first })
            .map { it.third }
    }

    private val combining = Regex("\\p{Mn}+")

    fun tokens(text: String): List<String> {
        val folded = combining.replace(Normalizer.normalize(text, Normalizer.Form.NFD), "").lowercase()
            .replace("'", "").replace("’", "")
        val out = mutableListOf<String>()
        val current = StringBuilder()
        for (ch in folded) {
            if (ch.isLetterOrDigit()) current.append(ch)
            else if (current.isNotEmpty()) { out += current.toString(); current.clear() }
        }
        if (current.isNotEmpty()) out += current.toString()
        return out
    }
}

/** The last few searches, newest first. */
object RecentSearches {
    const val STORAGE_KEY = "recentFoodSearches"
    fun list(stored: String): List<String> = stored.split("\n").filter { it.isNotEmpty() }
    fun adding(query: String, stored: String): String {
        val trimmed = query.trim()
        if (trimmed.length < 2) return stored
        val rest = list(stored).filter { !it.equals(trimmed, ignoreCase = true) }
        return (listOf(trimmed) + rest).take(8).joinToString("\n")
    }
}
