package com.isaiahgraham.leanrrr.feature.meal

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import java.text.Normalizer
import kotlin.math.max
import kotlin.math.roundToLong

// A port of SharingRules.swift (SharingRules, ContentFilter, record names) and OffensiveTextNote from Components.swift.

/**
 * What a food needs before it can be shared. Checked when saving and again on every food read back,
 * so a record written some other way still has to pass.
 */
object SharingRules {
    /** Several people reporting a food hides it for everyone until it's looked at. */
    const val REPORTS_TO_HIDE = 3

    /** The foods enough different people have reported to hide them for everyone. One person reporting twice counts once. */
    fun hiddenByReports(reports: List<Pair<String, String>>): Set<String> {
        val reporters = mutableMapOf<String, MutableSet<String>>()
        for ((record, reporter) in reports) reporters.getOrPut(record) { mutableSetOf() } += reporter
        return reporters.filterValues { it.size >= REPORTS_TO_HIDE }.keys
    }

    /** The most one serving could plausibly have of each extra nutrient: grams for the fats, sugars and fibre, milligrams for the rest. */
    val nutrientLimits: Map<String, Double> = mapOf(
        "sat" to 300.0, "trans" to 100.0, "sugar" to 500.0, "fibre" to 200.0, "sodium" to 20_000.0, "potassium" to 10_000.0,
        "calcium" to 5_000.0, "iron" to 200.0, "chol" to 5_000.0, "caffeine" to 1_000.0,
    )
    /** The longest `nut` text a shared record may carry; ten nutrients take about 200 characters. */
    const val LONGEST_NUTRIENT_TEXT = 1_000

    /** Only the nutrients Leanrrr knows, so a shared food can't carry anything else along. */
    fun knownNutrients(nut: Map<String, Double>?): Map<String, Double>? = nut?.filterKeys { it in nutrientLimits }?.takeIf { it.isNotEmpty() }

    /** Why this food can't be shared, or null when it can. */
    fun problem(food: Food): String? {
        val name = food.name.trim()
        val serve = food.serve.trim()
        if (food.ingredients != null || food.modifiers != null) return "Recipes and custom orders can't be shared."
        if (name.length < 3) return "Give it a name of at least 3 letters."
        if (name.length > 80) return "Shorten the name to 80 characters or fewer."
        if (serve.isEmpty() || serve.length > 40) return "Add a serving size, like 150 g or 1 bar."
        if (!ContentFilter.isAcceptable("$name $serve")) return "Take out the strong language before sharing."
        if (ContentFilter.hasContactDetails("$name $serve")) return "Leave links and contact details out of the name and serving."
        if (!food.isValid || food.cal <= 0) return "Add the energy first."
        val c = food.c; val f = food.f
        if (c == null || f == null) return "Add carbs and fat too, so others can see the numbers add up."
        if (food.cal > 3000 || food.p > 250 || c > 500 || f > 300 ||
            (food.nut ?: emptyMap()).any { it.value > (nutrientLimits[it.key] ?: Double.POSITIVE_INFINITY) }) {
            return "These numbers are more than one serving would have. Check them, or enter one serving."
        }
        food.barcode?.let { barcode ->
            if (barcode.length !in 6..14 || !barcode.all { it in '0'..'9' }) return "The barcode should be 6 to 14 digits."
        }
        if (food.cat.isEmpty() || food.cat.length > 20 || !food.cat.all { it in 'a'..'z' }) return "This kind of food can't be shared."
        food.servingWeight?.let { (weight, _) ->
            if (food.p + c + f > weight * 1.02) return "Protein, carbs and fat add up to more than the serving weighs. Check the label."
        }
        val fromMacros = food.p * 4 + c * 4 + f * 9
        val allowed = max(25.0, food.cal * 0.15)
        // Alcohol has energy that isn't a macro, so drinks with it may list more energy than their macros explain.
        if (fromMacros - food.cal > allowed || (food.cal - fromMacros > allowed && !mentionsAlcohol(name))) {
            return "The energy doesn't match the protein, carbs and fat (${fromMacros.roundToLong().toDouble().number} Cal from them, " +
                "${food.cal.roundToLong().toDouble().number} Cal entered). Check the label."
        }
        return null
    }

    private val alcohol = setOf("beer", "lager", "ale", "cider", "wine", "vodka", "gin", "rum", "whisky", "whiskey", "tequila", "seltzer",
        "spritz", "prosecco", "champagne", "cocktail", "sake", "soju", "bourbon", "liqueur")

    fun mentionsAlcohol(name: String): Boolean =
        name.lowercase().split(Regex("[^\\p{L}\\p{N}]+")).any { it in alcohol }
}

/**
 * Keeps strong language and abuse out of the foods and meals people name, and out of shared foods.
 * Whole words only, so "Scunthorpe" or "cocktail" pass, but disguised spellings like "sh1t", "f*ck", "f u c k" and "fuuuck" are caught.
 */
object ContentFilter {
    private val words: Set<String> = setOf(
        "fuck", "fucks", "fucked", "fucking", "fucker", "fuckers", "motherfucker", "fuk", "fuks", "fukin", "fuking", "fuq", "fck", "fcking", "fking", "fkn",
        "phuck", "phuk", "cunt", "cunts", "shit", "shits", "shitty", "shite", "bullshit", "shyt",
        "bitch", "bitches", "biatch", "bastard", "bastards", "wanker", "wankers", "twat", "twats", "dickhead", "dickheads", "arsehole", "arseholes", "asshole", "assholes",
        "cock", "cocks", "dick", "dicks", "pussy", "slut", "sluts", "whore", "whores", "porn", "cum", "jizz", "dildo", "blowjob", "handjob",
        "nazi", "nazis", "hitler", "rape", "raped", "rapist",
        "nigger", "niggers", "nigga", "niggas", "faggot", "faggots", "fag", "fags", "retard", "retards", "retarded", "spastic", "tranny",
        "kike", "chink", "coon", "paki", "abo", "abos", "gook", "spic", "wetback", "raghead", "towelhead",
        "kys", "killyourself",
    )
    /** Caught even inside another word, because no food name contains them. */
    private val roots = listOf("fuck", "nigger", "nigga", "faggot")
    /** Real foods that would otherwise trip a word above. */
    private val allowedPhrases = listOf("spotted dick", "dick smith", "cock a leekie", "cockaleekie", "coon cheese", "rape seed oil",
        "faggots and peas", "faggots in gravy")
    /** Symbols and digits standing in for letters, as in "sh1t" or "$hit". */
    private val lookalikes: Map<Char, Char> = mapOf('0' to 'o', '1' to 'i', '3' to 'e', '4' to 'a', '5' to 's', '7' to 't', '@' to 'a',
        '$' to 's', '!' to 'i', '|' to 'i')

    const val FLAG_MESSAGE = "Take out the offensive language to save this."

    fun isAcceptable(text: String): Boolean {
        var tokens = pieces(text)
        val padded = " " + tokens.joinToString(" ") + " "
        allowedPhrases.firstOrNull { padded.contains(" $it ") }?.let { allowed ->
            return isAcceptable(padded.replace(" $allowed ", " "))
        }
        tokens = tokens.map(::unmasked)
        // Spaced-out letters ("f u c k") and words split in two or three ("fu ck", "kill your self").
        val joined = mutableListOf<String>()
        for (i in 0 until tokens.size - 1) joined += tokens[i] + tokens[i + 1]
        for (i in 0 until tokens.size - 2) joined += tokens[i] + tokens[i + 1] + tokens[i + 2]
        val run = mutableListOf<String>()
        for (token in tokens + "") {
            if (token.length == 1) { run += token; continue }
            if (run.size >= 3) joined += run.joinToString("")
            run.clear()
        }
        return (tokens + joined).all { token ->
            variants(token).none { word -> word in words || roots.any { word.contains(it) } || matchesMasked(word) }
        }
    }

    /** Whether any of these is unacceptable. */
    fun flags(texts: List<String>): Boolean = !texts.all(::isAcceptable)
    fun flags(vararg texts: String): Boolean = flags(texts.toList())

    /** Lowercased words without accents, keeping the symbols people swap in for letters. */
    private fun pieces(text: String): List<String> {
        val folded = Normalizer.normalize(text, Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "").lowercase()
            .replace("'", "").replace("’", "")
        val out = mutableListOf<String>()
        val current = StringBuilder()
        fun flush() {
            val piece = current.toString().trim('!', '|', '*')
            if (piece.isNotEmpty()) out += piece
            current.clear()
        }
        for (ch in folded) {
            if (ch.isLetter() || ch.isDigit() || ch in "*@$!|") current.append(ch) else flush()
        }
        flush()
        return out
    }

    /** "sh1t" as "shit". Plain numbers like "100" or "7" are left alone. */
    private fun unmasked(token: String): String {
        if (token.none { it.isLetter() }) return token
        return token.map { lookalikes[it] ?: it }.joinToString("")
    }

    /** The word with long runs of one letter shortened, so "fuuuck" and "shiiit" are checked as well. */
    private fun variants(token: String): List<String> {
        val single = StringBuilder(); val double = StringBuilder()
        var last: Char? = null; var count = 0
        for (ch in token) {
            count = if (ch == last) count + 1 else 1
            last = ch
            if (count == 1) single.append(ch)
            if (count <= 2) double.append(ch)
        }
        return listOf(token, single.toString(), double.toString())
    }

    /** "f*ck" or "c**t": each star stands for one letter of a listed word. */
    private fun matchesMasked(token: String): Boolean {
        if (!token.contains('*') || token.none { it.isLetter() }) return false
        return words.any { word -> word.length == token.length && word.indices.all { word[it] == token[it] || token[it] == '*' } }
    }

    fun hasContactDetails(text: String): Boolean {
        val lower = text.lowercase()
        if (lower.contains("http") || lower.contains("www.") || lower.contains("@")) return true
        if (listOf(".com", ".net", ".org", ".io", ".au", ".ly").any { lower.contains(it) }) return true
        // Eight or more digits in a row looks like a phone number.
        return text.count { it.isDigit() } >= 8 && text.split(Regex("[^0-9 ]+")).any { piece -> piece.count { it.isDigit() } >= 8 }
    }
}

/** The shared record for one of your foods: "food-" and its ID, kept to the characters the record store allows. */
fun sharedRecordName(foodID: String): String =
    "food-" + foodID.filter { it.isLetterOrDigit() || it == '-' || it == '_' }.take(200)

/** Whether a record name is one this app writes: "food-" and up to 200 letters, digits, hyphens or underscores. */
fun isSharedRecordName(name: String): Boolean {
    if (!name.startsWith("food-")) return false
    val rest = name.drop(5)
    return rest.length in 1..200 && rest.all { it.isLetterOrDigit() || it == '-' || it == '_' }
}

/** One report per person per food. The reporter comes first so a long food name can never push it off the end. */
fun reportRecordName(recordName: String, reporter: String): String {
    val plain = "report-$recordName-$reporter"
    if (plain.length <= 255) return plain
    return "report-${reporter.take(100)}-$recordName".take(255)
}

/** Shown under a food or meal name with offensive language in it. Saving stays off until it's changed. */
@Composable
fun OffensiveTextNote(texts: List<String>, modifier: Modifier = Modifier) {
    if (!ContentFilter.flags(texts)) return
    val red = if (Leanr.colours.dark) Color(0xFFFF453A) else Color(0xFFD70015)
    Row(modifier.padding(horizontal = 16.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(Icons.Filled.Warning, null, tint = red, modifier = Modifier.size(14.dp))
        Text(ContentFilter.FLAG_MESSAGE, style = LeanrType.caption, color = red)
    }
}

@Composable
fun OffensiveTextNote(vararg texts: String, modifier: Modifier = Modifier) = OffensiveTextNote(texts.toList(), modifier)
