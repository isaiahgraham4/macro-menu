package com.isaiahgraham.leanrrr.feature.scan

import com.isaiahgraham.leanrrr.data.newId
import kotlin.math.abs

// Pure Kotlin (no Android classes), so the JUnit tests run it on the JVM. A port of MenuParser.swift.

/** One run of text read from a menu photo. Positions are fractions of the page, measured from its top left. */
data class MenuLine(
    val text: String,
    val x: Double,
    val y: Double,
    val width: Double,
    val height: Double,
    val page: Int = 0,
) {
    val maxX: Double get() = x + width
    val midY: Double get() = y + height / 2
}

/** A dish as a menu words it. Only what was read; the figures are worked out separately (`MenuEstimator`). */
data class MenuDish(
    val name: String,
    val details: String = "",
    val price: Double? = null,
    /** The menu's heading above it, such as "Entrees". */
    val section: String? = null,
    val id: String = newId(),
)

/**
 * Turns the text on a menu photo into dishes. Menus have no fixed layout, so this goes by what menus usually do: columns,
 * a price at the end of a dish's line, a smaller description underneath, headings in larger or capital letters.
 */
object MenuParser {
    data class Result(
        /** The big name at the top of the first page, when there is one. */
        val restaurant: String?,
        val dishes: List<MenuDish>,
    )

    private data class Row(val text: String, val y: Double, val height: Double, val price: Double? = null)

    fun read(lines: List<MenuLine>): Result {
        val readable = lines.filter { line -> line.text.any { it.isLetterOrDigit() } }
        val body = median(readable.map { it.height })
        val title = restaurantLine(readable, body)
        val dishes = mutableListOf<MenuDish>()
        val section = arrayOfNulls<String>(1)
        for (page in readable.map { it.page }.toSortedSet()) {
            val text = readable.filter { it.page == page && it != title }
            for (column in columns(text)) parse(rows(column), body, section, dishes)
        }
        val trimmed = dishes.map { it.copy(name = it.name.trim { c -> c == ',' || c == ' ' }, details = it.details.trim { c -> c == ',' || c == ' ' }) }
        return Result(title?.let { titled(clean(it.text)) }, trimmed)
    }

    // Page layout

    /** The largest words near the top of the first page, unless they only say what kind of menu it is. */
    private fun restaurantLine(lines: List<MenuLine>, body: Double): MenuLine? {
        val top = lines.filter { it.page == 0 && it.y < 0.25 && it.height >= body * 1.4 && splitPrice(it.text).price == null }
        val line = top.maxByOrNull { it.height } ?: return null
        val words = spaceWords(line.text)
        if (words.size !in 1..5 || isKnownHeading(clean(line.text))) return null
        return line
    }

    /** The page's columns, left to right: a gap running down the page that text starts on both sides of. */
    fun columns(lines: List<MenuLine>): List<List<MenuLine>> {
        val prices = lines.filter(::isOnlyPrice)
        val words = lines.filter { !isOnlyPrice(it) }
        val parts = split(words).map { it.toMutableList() }.toMutableList()
        // Lone prices go with the column they're at the right of, going by where its lines usually start.
        val starts = parts.map { part -> median(part.map { it.x }) }
        for (price in prices) {
            val index = starts.indexOfLast { it < price.x }.let { if (it < 0) 0 else it }
            if (index in parts.indices) parts[index].add(price) else parts.add(mutableListOf(price))
        }
        return parts
    }

    private fun split(lines: List<MenuLine>, depth: Int = 0): List<List<MenuLine>> {
        // A title or footer centred across the columns isn't part of either.
        val top = lines.minOfOrNull { it.y } ?: 0.0
        val bottom = lines.maxOfOrNull { it.y } ?: 1.0
        fun isBanner(line: MenuLine) = abs(line.x + line.width / 2 - 0.5) < 0.06 &&
            (line.y < top + (bottom - top) * 0.15 || line.y > bottom - (bottom - top) * 0.12)
        val narrow = lines.filter { it.width < 0.6 && !isBanner(it) }
        if (depth >= 3 || narrow.size < 6) return listOf(lines)
        val gap = columnGap(narrow) ?: return listOf(lines)
        val left = lines.filter { it.x < gap }
        val right = lines.filter { it.x >= gap }
        return split(left, depth + 1) + split(right, depth + 1)
    }

    /** The middle of the widest stretch little text crosses, with a good share of the lines starting on each side. */
    private fun columnGap(lines: List<MenuLine>): Double? {
        val steps = 100
        val cover = IntArray(steps)
        for (line in lines) {
            val start = maxOf(0, (line.x * steps).toInt())
            val end = minOf(steps - 1, (line.maxX * steps).toInt())
            if (start <= end) for (index in start..end) cover[index] += 1
        }
        val allowed = maxOf(1, lines.size / 12)
        val low = maxOf(0, ((lines.minOfOrNull { it.x } ?: 0.0) * steps).toInt())
        val high = ((lines.maxOfOrNull { it.x } ?: 1.0) * steps).toInt()
        var bestStart = 0; var bestLength = 0
        var index = low + 1
        while (index <= minOf(steps - 1, high)) {
            if (cover[index] > allowed) { index += 1; continue }
            var end = index
            while (end + 1 < steps && cover[end + 1] <= allowed) end += 1
            if (end - index + 1 > bestLength) { bestStart = index; bestLength = end - index + 1 }
            index = end + 1
        }
        if (bestLength < 3) return null
        val middle = (bestStart.toDouble() + bestLength.toDouble() / 2) / steps
        val share = maxOf(3, lines.size / 5)
        if (lines.count { it.x < middle } < share || lines.count { it.x >= middle } < share) return null
        return middle
    }

    private fun isOnlyPrice(line: MenuLine): Boolean {
        val split = splitPrice(line.text)
        return split.price != null && split.words.none { it.isLetter() }
    }

    /** One column's lines from top to bottom, with a price printed apart on the same level joined to its line. */
    private fun rows(lines: List<MenuLine>): List<Row> {
        val words = lines.filter { !isOnlyPrice(it) }.sortedBy { it.y }
        val rows = words.map { Row(it.text, it.y, it.height) }.toMutableList()
        for (price in lines.filter(::isOnlyPrice).sortedBy { it.y }) {
            val level = rows.indices.filter { rows[it].price == null && abs(rows[it].y + rows[it].height / 2 - price.midY) < maxOf(rows[it].height, price.height) * 0.75 }
            val row = level.minByOrNull { abs(rows[it].y - price.y) }
            if (row != null) {
                rows[row] = rows[row].copy(price = splitPrice(price.text).price)
            } else {
                // A price on its own line, as centred menus print them: it stays in place and goes with the dish above.
                rows.add(Row(price.text, price.y, price.height))
                rows.sortBy { it.y }
            }
        }
        return rows
    }

    // Reading the lines

    private fun parse(all: List<Row>, body: Double, section: Array<String?>, dishes: MutableList<MenuDish>) {
        val rows = all.filter { !isNoise(it.text) }
        var nameHeight = body
        var startedHere = false
        for ((index, row) in rows.withIndex()) {
            val split = splitPrice(row.text)
            val price = row.price ?: split.price
            val words = clean(split.words)
            if (words.none { it.isLetter() }) {
                if (price != null && startedHere && dishes.last().price == null) dishes[dishes.size - 1] = dishes.last().copy(price = price)
                continue
            }
            if (isExtra(words)) continue
            val next = rows.getOrNull(index + 1)
            val last = if (startedHere) dishes.lastOrNull() else null
            val describes = last?.let { isDescription(words, row.height, nameHeight, it, price != null) } ?: false
            if (price == null && !describes && isHeading(words, row.height, body, next)) {
                section[0] = titled(words); startedHere = false
                continue
            }
            if (describes) {
                val at = dishes.size - 1
                val dish = dishes[at]
                dishes[at] = dish.copy(details = if (dish.details.isEmpty()) words else dish.details + " " + words, price = dish.price ?: price)
                continue
            }
            if (spaceWords(words).size > 14) continue
            dishes += named(words).copy(price = price, section = section[0])
            nameHeight = row.height; startedHere = true
        }
    }

    /** Whether a line carries on from the dish above rather than starting a new one. */
    private fun isDescription(words: String, height: Double, nameHeight: Double, dish: MenuDish, priced: Boolean): Boolean {
        val lower = words.firstOrNull()?.isLowerCase() == true
        val wrapped = listOf("and", "with", "or", "of", "in", "on", "a", "&").any { dish.details.lowercase().endsWith(" $it") } || dish.details.endsWith(",")
        if (priced) {
            // The price can be on the description's line instead of the name's.
            return dish.price == null && dish.details.isEmpty() && (lower || words.contains(",") || height < nameHeight * 0.88)
        }
        val joining = listOf("served", "comes", "choice of", "choose", "topped", "includes", "your choice").any { words.lowercase().startsWith(it) }
        return lower || wrapped || joining || words.contains(",") || height < nameHeight * 0.88 || words.endsWith(".") || spaceWords(words).size > 7
    }

    private val headingWords = setOf(
        "entree", "entrees", "entrée", "entrées", "starter", "starters", "appetisers", "appetizers", "main", "mains", "side", "sides", "dessert", "desserts", "sweet", "sweets",
        "drink", "drinks", "beverages", "beers", "wines", "cocktails", "spirits", "coffee", "tea", "kids", "children", "breakfast", "brunch", "lunch", "dinner", "menu",
        "pizzas", "pastas", "burgers", "salads", "soups", "curries", "sandwiches", "wraps", "tacos", "sushi", "grill", "seafood", "vegetarian", "specials", "snacks", "share",
        "sharing", "banquet", "noodles", "rice", "extras", "sauces", "plates", "tapas", "antipasti", "steaks", "toasties", "bowls",
    )

    private fun isKnownHeading(words: String): Boolean {
        val parts = splitWords(words.lowercase()) { !it.isLetter() && it != 'é' }.filter { it != "and" }
        if (parts.size !in 1..4) return false
        if (parts.all { it in headingWords }) return true
        return if (parts.size == 1) parts[0] in headingWords || parts[0] in setOf("pizza", "pasta", "salad", "soup", "wine", "beer")
            else parts.any { it in headingWords } && parts.any { it.endsWith("s") || it in setOf("from", "the", "to", "small", "large") }
    }

    private fun isHeading(words: String, height: Double, body: Double, next: Row?): Boolean {
        if (isKnownHeading(words)) return true
        if (spaceWords(words).size > 5 || words.contains(",")) return false
        // A dish printed big or in capitals has its description next; a heading has the next dish.
        val nextDescribes = next?.let { row ->
            val text = clean(splitPrice(row.text).words)
            text.firstOrNull()?.isLowerCase() == true || text.contains(",") || (row.height < height * 0.8 && height < body * 1.2)
        } ?: false
        if (nextDescribes) return false
        if (height >= body * 1.25) return true
        val letters = words.filter { it.isLetter() }
        return letters.isNotEmpty() && letters.all { it.isUpperCase() } && (next?.let { splitPrice(it.text).price != null || it.price != null } ?: false)
    }

    private val extraRegex = Regex("""(?i)^(\+|add\b|extra\b|upgrade\b|make it\b|swap\b)""")

    /** Add-ons offered under a dish: "Add chicken 6", "+ extra cheese". */
    private fun isExtra(words: String): Boolean = extraRegex.containsMatchIn(words)

    /** Text on a menu that isn't food: contact details, surcharges, keys to the dietary letters. */
    private val noise = Regex(
        "(?iU)" +
            """\b0\d[\d\s-]{7,}|\b1[38]00\b|\d{4}\s\d{4}\b|www\.|https?|@|\.com|\.au\b|""" +
            """surcharge|public holiday|prices? (include|are|subject)|\bgst\b|\bbyo\b|corkage|allerg|intoleran|""" +
            """please|ask (our|your|the)|wait ?staff|our staff|bookings?|book now|opening hours|\bopen\s(mon|tue|wed|thu|fri|sat|sun|daily|7)|""" +
            """follow us|instagram|facebook|gift (voucher|card)|split bills?|eftpos|fully licensed|\b(vic|nsw|qld|sa|wa|tas|act)\s\d{4}\b|""" +
            """^\W*(v|gf|vg|df|n)\W*(=|-|:)\W*(vegetarian|vegan|gluten|dairy|nut)|^page\s\d|^\W*\w\W*$""",
    )

    private fun isNoise(text: String): Boolean = noise.containsMatchIn(text)

    // Words on a line

    private val priceRegex = Regex("""(?:^|\s)((?:[$£€]\s?|S(?=\d))?)(\d{1,3}(?:[.,:\-–]\d{1,2})?)(?:\s*(?:ea|each|pp|p/p))?\s*[-–/|+]?\s*$""", RegexOption.IGNORE_CASE)
    private val leaders = Regex("""[.…_·]{2,}""")

    /** The number in a price as printed or misread: "5-5" is 5.50, but "12-18" is two sizes, so the first. */
    private fun amount(digits: String): Double? {
        val parts = splitWords(digits) { it == '-' || it == '–' }
        if (parts.size == 2) return if (parts[1].length == 1) "${parts[0]}.${parts[1]}".toDoubleOrNull() else parts[0].toDoubleOrNull()
        return digits.replace(",", ".").replace(":", ".").toDoubleOrNull()
    }

    data class PriceSplit(val words: String, val price: Double?)

    /** A line's words and the price at its end. With two prices ("12 / 18") the first, the smaller size, is kept. */
    fun splitPrice(text: String): PriceSplit {
        var words = text.replace(leaders, " ").trim()
        var found: Double? = null
        while (true) {
            val match = priceRegex.find(words) ?: break
            val sign = match.groups[1]?.value ?: ""
            val digits = match.groups[2]?.value ?: break
            val value = amount(digits) ?: break
            // Without a currency sign, a small lone number is more likely part of the name.
            if (sign.isEmpty() && value < 3) break
            if (value <= 0 || value > 500) break
            found = value
            words = words.substring(0, match.range.first).trim()
        }
        return PriceSplit(words, found)
    }

    private val spaces = Regex("""\s+""")
    private val marketPrice = Regex("""(?i)\b(market price|mp)\s*$""")
    private val numbering = Regex("""^(?:[•*\-–—]\s*|\d{1,3}[.)]\s+)""")
    private const val LETTERS = "(?:GFO?|DFO?|VGN?|VO|VE|NF|GFA|DFA|NGCI|V|N)"
    private const val MARKED = "(?:GFO?|DFO?|VGN?|VEG|VO|VE|NF|GFA|DFA|NGCI|V|N)"
    /** "Margherita (v)", "Pad Thai GF, DF": letters in capitals or brackets. VEG needs a bracket or a comma, since "ROAST VEG" is a dish. */
    private val dietary = Regex(
        """(?:[\s,/|]+""" + LETTERS + """|\s*[,/|][\s,/|]*VEG|\s*[\(\[](?i:""" + MARKED + """)(?:[\s,/]+(?i:""" + MARKED + """))*[\)\]])[\s,/|]*$""",
    )

    /** The line without leaders, numbering or dietary letters. */
    fun clean(text: String): String {
        var words = text.replace("’", "'").replace(spaces, " ").replace(leaders, " ").replace(marketPrice, "").trim()
        words = words.replaceFirst(numbering, "")
        while (true) {
            val match = dietary.find(words) ?: break
            words = words.substring(0, match.range.first)
        }
        // A comma at the end stays: it says the description carries on to the next line.
        return words.trim { it.isWhitespace() || it in "-–—:|" }
    }

    /** A line as a dish: "Margherita - tomato, basil" splits at the dash, and a long line at its first comma. */
    private fun named(words: String): MenuDish {
        for (mark in listOf(" - ", " – ", " — ", ": ", " | ")) {
            val at = words.indexOf(mark)
            if (at >= 0) {
                val name = words.substring(0, at); val rest = words.substring(at + mark.length)
                if (name.any { it.isLetter() } && rest.any { it.isLetter() }) return MenuDish(name = titled(name), details = rest)
            }
        }
        val comma = words.indexOf(',')
        if (spaceWords(words).size > 7 && comma >= 0) {
            return MenuDish(name = titled(words.substring(0, comma)), details = words.substring(comma + 1).trim())
        }
        return MenuDish(name = titled(words))
    }

    private val keptCaps = setOf("BBQ", "BLT", "KFC", "IPA", "XO", "NY")

    /** All-capital names in ordinary title case, so they read like the rest of the app. */
    private fun titled(text: String): String {
        val letters = text.filter { it.isLetter() }
        if (letters.isEmpty() || !letters.all { it.isUpperCase() }) return text
        return spaceWords(text).mapIndexed { index, word ->
            if (word in keptCaps) return@mapIndexed word
            val lower = word.lowercase()
            if (index > 0 && lower in setOf("and", "with", "of", "the", "in", "on", "or")) lower else lower.take(1).uppercase() + lower.drop(1)
        }.joinToString(" ")
    }

    private fun median(values: List<Double>): Double = if (values.isEmpty()) 0.0 else values.sorted()[values.size / 2]
}
