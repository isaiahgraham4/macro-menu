package com.isaiahgraham.leanrrr.feature.meal

import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.tenth
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import kotlin.math.roundToLong

// A port of RecipeImport.swift.

/**
 * A recipe read from a web page. Most recipe sites describe the recipe for search engines in a schema.org block, which
 * lists the name, how many it serves, the ingredients and often nutrition per serving. Only that block is read.
 */
data class ImportedRecipe(
    val name: String,
    val servings: Double?,
    val ingredients: List<String>,
    /** Per serving, when the page lists it: "cal", "p", "c", "f", and others under Leanrrr's nutrient keys. */
    val nutrition: Map<String, Double>,
    val source: String? = null,
) {
    val host: String? get() = source?.let { runCatching { URI(it).host }.getOrNull() }?.replace("www.", "")

    /** The page's own figures as a food, when it lists at least calories and protein. */
    val food: Food?
        get() {
            val cal = nutrition["cal"] ?: return null
            val p = nutrition["p"] ?: return null
            if (cal <= 0) return null
            val nut = nutrition.filterKeys { it !in listOf("cal", "p", "c", "f") }.mapValues { it.value.tenth }
            return Food(name = name, kj = (cal * 4.184).roundToLong().toDouble(), cal = cal.roundToLong().toDouble(), p = p.tenth,
                c = nutrition["c"]?.tenth, f = nutrition["f"]?.tenth, serve = "1 serving", nut = nut.ifEmpty { null }, note = host?.let { "From $it" })
        }
}

object RecipeImport {
    enum class Failure(val message: String) {
        NOT_A_LINK("That isn't a web link. Copy the recipe page's address from your browser and paste it here."),
        COULD_NOT_LOAD("The page couldn't be loaded. Check you're online and the link opens in your browser."),
        NO_RECIPE("No recipe was found on that page. Leanrrr reads the recipe details most recipe sites include, and this page doesn't have them."),
    }

    class ImportException(val failure: Failure) : Exception(failure.message)

    private val linkPattern = Regex("""(?i)\bhttps?://[^\s<>"']+""")

    /** A web address from pasted text: the first http or https link in it, or else the first bare address ("taste.com.au/..."). */
    fun link(text: String): String? {
        val trimmed = text.trim()
        // A real link wins over something earlier that only looks like an address, like "recipe." ending a sentence.
        for (match in linkPattern.findAll(trimmed)) {
            secure(match.value.trimEnd('.', ',', ')', ';', '!', '?'))?.let { return it }
        }
        val candidates = listOf(trimmed) + trimmed.split(Regex("\\s+"))
        for (candidate in candidates) {
            var value = candidate
            if (!value.lowercase().startsWith("http") && value.contains(".") && !value.contains(" ")) value = "https://$value"
            secure(value)?.let { return it }
        }
        return null
    }

    /** The address over HTTPS, if it has a real host ("recipe." isn't one). */
    private fun secure(address: String): String? {
        var value = address
        // Leanrrr only connects over HTTPS, and nearly every recipe site has it.
        if (value.lowercase().startsWith("http://")) value = "https://" + value.drop(7)
        val uri = runCatching { URI(value) }.getOrNull() ?: return null
        val host = uri.host ?: return null
        if (uri.scheme?.lowercase() != "https" || !host.contains(".") || host.endsWith(".")) return null
        return value
    }

    const val LARGEST_PAGE = 5_000_000

    /** Loads the page straight from the site and reads its recipe. */
    suspend fun load(url: String): ImportedRecipe = withContext(Dispatchers.IO) {
        val (html, finalURL) = try {
            val connection = URL(url).openConnection() as HttpURLConnection
            connection.connectTimeout = 20_000; connection.readTimeout = 20_000
            connection.instanceFollowRedirects = true
            connection.setRequestProperty("User-Agent",
                "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36")
            connection.setRequestProperty("Accept", "text/html")
            try {
                if (connection.responseCode !in 200..299) throw ImportException(Failure.COULD_NOT_LOAD)
                val bytes = connection.inputStream.use { input ->
                    val out = java.io.ByteArrayOutputStream()
                    val buffer = ByteArray(16_384)
                    while (true) {
                        val n = input.read(buffer); if (n < 0) break
                        out.write(buffer, 0, n)
                        if (out.size() > LARGEST_PAGE) throw ImportException(Failure.COULD_NOT_LOAD)
                    }
                    out.toByteArray()
                }
                String(bytes, Charsets.UTF_8) to connection.url.toString()
            } finally { connection.disconnect() }
        } catch (e: ImportException) { throw e } catch (e: Exception) { throw ImportException(Failure.COULD_NOT_LOAD) }
        val recipe = recipes(html).firstOrNull() ?: throw ImportException(Failure.NO_RECIPE)
        recipe.copy(source = finalURL)
    }

    private val scriptPattern = Regex("""(?is)<script[^>]*type\s*=\s*["']?application/ld\+json["']?[^>]*>(.*?)</script>""")

    /** Every schema.org Recipe in the page's JSON-LD blocks. */
    fun recipes(html: String): List<ImportedRecipe> {
        val found = mutableListOf<ImportedRecipe>()
        for (match in scriptPattern.findAll(html)) {
            val body = match.groupValues[1].trim()
            val json = runCatching { JSONTokener(body).nextValue() }.getOrNull() ?: continue
            for (obj in recipeObjects(json)) recipe(obj)?.let { found += it }
        }
        return found
    }

    private fun recipeObjects(json: Any?): List<JSONObject> {
        if (json is JSONArray) return (0 until json.length()).flatMap { recipeObjects(json.opt(it)) }
        if (json !is JSONObject) return emptyList()
        val result = mutableListOf<JSONObject>()
        val type = json.opt("@type")
        val types = when (type) { is String -> listOf(type); is JSONArray -> (0 until type.length()).mapNotNull { type.opt(it) as? String }; else -> emptyList() }
        if (types.any { it.equals("Recipe", ignoreCase = true) }) result += json
        for (key in listOf("@graph", "mainEntity", "mainEntityOfPage", "itemListElement", "item")) json.opt(key)?.let { result += recipeObjects(it) }
        return result
    }

    private fun recipe(obj: JSONObject): ImportedRecipe? {
        val name = clean((obj.opt("name") as? String) ?: (obj.opt("headline") as? String) ?: "")
        val list = (obj.opt("recipeIngredient") ?: obj.opt("ingredients")) as? JSONArray
        val lines = list?.let { arr -> (0 until arr.length()).mapNotNull { arr.opt(it) as? String }.map(::clean).filter { it.isNotEmpty() } } ?: emptyList()
        if (name.isEmpty() || (lines.isEmpty() && obj.opt("nutrition") == null)) return null
        val nutrition = mutableMapOf<String, Double>()
        (obj.opt("nutrition") as? JSONObject)?.let { facts ->
            for ((key, field) in listOf("cal" to "calories", "p" to "proteinContent", "c" to "carbohydrateContent", "f" to "fatContent",
                "sat" to "saturatedFatContent", "trans" to "transFatContent", "sugar" to "sugarContent", "fibre" to "fiberContent",
                "sodium" to "sodiumContent", "chol" to "cholesterolContent")) {
                amount(facts.opt(field), key)?.let { nutrition[key] = it }
            }
        }
        return ImportedRecipe(name, servings(obj.opt("recipeYield") ?: obj.opt("yield")), lines, nutrition)
    }

    /** "4", "4 servings", "Serves 6", ["4", "4 servings"], or a number. */
    fun servings(value: Any?): Double? {
        if (value is Number) return value.toDouble().takeIf { it > 0 }
        if (value is JSONArray) return (0 until value.length()).firstNotNullOfOrNull { servings(value.opt(it)) }
        val text = value as? String ?: return null
        val number = Regex("""(\d+(?:\.\d+)?)""").find(text)?.groupValues?.get(1)?.toDoubleOrNull() ?: return null
        return number.takeIf { it > 0 && it <= 100 }
    }

    /** A nutrient figure in Leanrrr's units: Cal for energy (kJ converted), grams, and milligrams for sodium and cholesterol. */
    fun amount(value: Any?, key: String): Double? {
        var number: Double? = null; var unit = ""
        when (value) {
            is Number -> number = value.toDouble()
            is String -> Regex("""(\d+(?:\.\d+)?)\s*([a-zA-Zµ]*)""").find(value.replace(",", ""))?.let {
                number = it.groupValues[1].toDoubleOrNull(); unit = it.groupValues[2].lowercase()
            }
        }
        var result = number ?: return null
        if (!result.isFinite() || result < 0) return null
        when (key) {
            "cal" -> if (unit == "kj") result /= 4.184
            "sodium", "chol" -> if (unit == "g") result *= 1000 else if (unit == "µg" || unit == "mcg") result /= 1000
            else -> if (unit == "mg") result /= 1000
        }
        return result
    }

    private val entities = mapOf("&amp;" to "&", "&quot;" to "\"", "&#39;" to "'", "&#039;" to "'", "&apos;" to "'", "&lt;" to "<", "&gt;" to ">",
        "&nbsp;" to " ", "&frac12;" to "½", "&frac14;" to "¼", "&frac34;" to "¾", "&#8217;" to "’", "&#8211;" to "–", "&ndash;" to "–", "&rsquo;" to "’")

    /** Text without HTML tags, entities or extra spaces. */
    fun clean(text: String): String {
        var value = text.replace(Regex("<[^>]+>"), " ")
        for ((entity, character) in entities) value = value.replace(entity, character)
        value = value.replace(Regex("&#(\\d+);"), " ")
        return value.split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
    }
}
