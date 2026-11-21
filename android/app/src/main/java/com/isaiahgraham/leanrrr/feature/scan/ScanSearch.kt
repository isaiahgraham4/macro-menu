package com.isaiahgraham.leanrrr.feature.scan

import com.isaiahgraham.leanrrr.data.Food
import java.text.Normalizer
import java.util.concurrent.ConcurrentHashMap

// Pure Kotlin (no Android classes), so the JUnit tests run it on the JVM.

/**
 * The parts of FoodSearch.swift the scanners match with: forgiving word scoring (a typo or two), the Best choices ordering,
 * and the word splitting. Kept here so photo and menu matching behave exactly as on iOS whatever Find's search does.
 */
internal object ScanSearch {
    class Prepared(text: String) {
        val candidates: List<String>
        val letters: List<IntArray>
        init {
            val parts = tokens(text)
            // Adjacent pairs let "mc chicken" and "mcchicken" find each other.
            candidates = parts + (0 until maxOf(0, parts.size - 1)).map { parts[it] + parts[it + 1] }
            letters = candidates.map(::letters)
        }
    }

    class Query(text: String) {
        val words: List<String> = tokens(text)
        val letters: List<IntArray> = words.map(::letters)
        val isEmpty: Boolean get() = words.isEmpty()
    }

    fun letters(word: String): IntArray = IntArray(word.length) { word[it].code }

    private val cache = ConcurrentHashMap<String, Prepared>()
    fun prepared(text: String): Prepared = cache.getOrPut(text) { Prepared(text) }

    fun score(text: String, query: String): Int? = score(Prepared(text), Query(query))

    fun score(item: Prepared, query: Query): Int? {
        var total = 0
        for ((word, letters) in query.words.zip(query.letters)) {
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

    /** The fewest edits between the word and the candidate or the start of it; null when that's more than the limit. */
    fun closeness(word: IntArray, candidate: IntArray, limit: Int): Int? {
        if (word.isEmpty() || candidate.isEmpty()) {
            val m = maxOf(word.size, candidate.size)
            return if (m <= limit) m else null
        }
        val row = IntArray(candidate.size + 1) { it }
        for (i in 1..word.size) {
            var previous = row[0]; row[0] = i
            var smallest = i
            for (j in 1..candidate.size) {
                val current = row[j]
                row[j] = if (word[i - 1] == candidate[j - 1]) previous else minOf(previous, row[j], row[j - 1]) + 1
                smallest = minOf(smallest, row[j])
                previous = current
            }
            if (smallest > limit) return null
        }
        val lengths = (maxOf(1, word.size - 1)..(word.size + 1)).map { minOf(it, candidate.size) } + candidate.size
        val best = lengths.minOf { row[it] }
        return if (best <= limit) best else null
    }

    /** Foods for a search: exact matches first, then typos from closest to furthest; each group by protein per calorie. */
    fun browse(foods: List<Food>, chainNames: Map<String, String>, search: String, chain: String = "all"): List<Food> {
        val query = Query(search)
        val scores = HashMap<String, Int>()
        val rows = foods.filter { food ->
            if (chain != "all" && food.chain != chain) return@filter false
            if (food.cat == "swap") return@filter false
            if (query.isEmpty) return@filter true
            val score = score(prepared(food.name + " " + (chainNames[food.chain] ?: "My foods")), query) ?: return@filter false
            val name = tokens(food.name)
            val bonus = if (name == query.words) 3 else if (endsWith(food.name, query.words)) 2 else if (startsWith(food.name, query.words)) 1 else 0
            scores[food.id] = score * 4 - bonus
            true
        }
        return rows.sortedWith { a, b ->
            val sa = scores[a.id] ?: 0; val sb = scores[b.id] ?: 0
            when {
                sa != sb -> sa.compareTo(sb)
                a.isCommunity != b.isCommunity -> if (b.isCommunity) -1 else 1
                else -> (b.p / maxOf(b.cal, 1.0)).compareTo(a.p / maxOf(a.cal, 1.0))
            }
        }
    }

    fun startsWith(name: String, words: List<String>): Boolean {
        val names = tokens(name)
        val last = words.lastOrNull() ?: return false
        if (names.size < words.size) return false
        return names.take(words.size - 1) == words.dropLast(1) && names[words.size - 1].startsWith(last)
    }

    fun endsWith(name: String, words: List<String>): Boolean {
        val main = tokens(name.takeWhile { it != ',' })
        return words.isNotEmpty() && main.size >= words.size && main.takeLast(words.size) == words
    }

    /** Lower case, without accents or apostrophes, split at anything that isn't a letter or digit. */
    fun tokens(text: String): List<String> =
        splitWords(fold(text).replace("'", "").replace("’", "")) { !it.isLetterOrDigit() }

    fun fold(text: String): String =
        Normalizer.normalize(text, Normalizer.Form.NFD).replace(COMBINING, "").lowercase()

    private val COMBINING = Regex("\\p{Mn}+")
}

/** Splits at characters matching `separator`, leaving out empty pieces (Swift's `split(whereSeparator:)`). */
internal inline fun splitWords(text: String, separator: (Char) -> Boolean): List<String> {
    val out = ArrayList<String>()
    val current = StringBuilder()
    for (ch in text) {
        if (separator(ch)) { if (current.isNotEmpty()) { out += current.toString(); current.clear() } } else current.append(ch)
    }
    if (current.isNotEmpty()) out += current.toString()
    return out
}

/** Words separated by spaces, without empty ones. */
internal fun spaceWords(text: String): List<String> = text.split(' ').filter { it.isNotEmpty() }
