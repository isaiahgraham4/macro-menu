package com.isaiahgraham.leanrrr.feature.scan

import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.LeanrJson
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

// Pure Kotlin (no Android classes), so the JUnit tests run it on the JVM. A port of BarcodeProduct.swift.

@Serializable
data class BarcodeProduct(
    val food: Food,
    val per100: Boolean,
    val unit: String,
    val sourceURL: String,
)

/** The last few products scanned, kept on this device only (preferences key [STORAGE_KEY]). */
object RecentBarcodes {
    const val STORAGE_KEY = "recentBarcodeProducts"
    /** How many scans are remembered and offered. */
    const val LIMIT = 10
    private val serializer = ListSerializer(BarcodeProduct.serializer())

    fun products(stored: String?): List<BarcodeProduct> =
        (runCatching { LeanrJson.decodeFromString(serializer, stored ?: "") }.getOrNull() ?: emptyList())
            .filter { it.food.isValid }.take(LIMIT)

    fun recording(product: BarcodeProduct, stored: String?): String {
        val recent = listOf(product) + products(stored).filter { it.sourceURL != product.sourceURL }
        return LeanrJson.encodeToString(serializer, recent.take(LIMIT))
    }
}

class BarcodeLookupException(val reason: Reason) : Exception() {
    enum class Reason { INVALID_CODE, NOT_FOUND, INCOMPLETE, UNAVAILABLE }

    override val message: String
        get() = when (reason) {
            Reason.INVALID_CODE -> "Check the barcode digits and try again. Enter an 8, 12, 13 or 14 digit product barcode."
            Reason.NOT_FOUND -> "This product isn't in Open Food Facts yet. Add its barcode to a food you enter yourself, and scanning it next time will find that food."
            Reason.INCOMPLETE -> "This product doesn't have complete energy and protein data. Add its barcode to a food you enter yourself, and scanning it next time will find that food."
            Reason.UNAVAILABLE -> "The food database is unavailable right now. Try again shortly, or scan the nutrition label."
        }
}

object BarcodeLookup {
    private const val USER_AGENT = "Leanrrr/1.0 (Android; com.isaiahgraham.leanrrr)"

    /** The digits of a checksum-valid GTIN-8/12/13/14, or throws. Spaces and dashes are ignored. */
    fun validatedCode(input: String): String {
        val code = input.filter { !it.isWhitespace() && it != '-' }
        if (code.length !in setOf(8, 12, 13, 14) || !code.all { it in '0'..'9' }) throw BarcodeLookupException(BarcodeLookupException.Reason.INVALID_CODE)
        val digits = code.map { it - '0' }
        val sum = digits.dropLast(1).reversed().withIndex().sumOf { (offset, digit) -> digit * (if (offset % 2 == 0) 3 else 1) }
        if ((10 - sum % 10) % 10 != digits.last() || digits.all { it == 0 }) throw BarcodeLookupException(BarcodeLookupException.Reason.INVALID_CODE)
        return code
    }

    fun isValid(input: String): Boolean = runCatching { validatedCode(input) }.isSuccess

    /** The first saved food with this barcode. Leading zeros are ignored, so a 12-digit UPC matches its 13-digit EAN. */
    fun match(code: String, foods: List<Food>): Food? {
        val key = code.trimStart('0')
        return foods.firstOrNull { food -> food.barcode?.trimStart('0') == key }
    }

    /**
     * Any food Leanrrr has for this barcode: a food with that barcode, or a supermarket product whose id ends with it
     * (Coles and Woolworths foods are keyed by their barcode). Found offline, before Open Food Facts is asked.
     */
    fun matchAny(code: String, foods: List<Food>): Food? {
        val key = code.trimStart('0')
        return foods.firstOrNull { food ->
            food.barcode?.trimStart('0') == key || (food.isSupermarket && food.id.substringAfterLast(':').trimStart('0') == key)
        }
    }

    fun fetch(input: String): BarcodeProduct = fetch(code = validatedCode(input), checked = true)

    /** Looks up a code on Open Food Facts. Only the barcode goes out; no cookies are kept or sent. Blocking: call off the main thread. */
    fun fetch(code: String, checked: Boolean): BarcodeProduct {
        val fields = "product_name,product_name_en,brands,serving_size,serving_quantity_unit,product_quantity_unit,nutriments"
        val url = URL("https://world.openfoodfacts.org/api/v2/product/$code.json?fields=" + URLEncoder.encode(fields, "UTF-8"))
        val connection = try { url.openConnection() as HttpURLConnection } catch (e: IOException) { throw BarcodeLookupException(BarcodeLookupException.Reason.UNAVAILABLE) }
        try {
            connection.connectTimeout = 20_000; connection.readTimeout = 20_000
            connection.useCaches = false
            connection.setRequestProperty("User-Agent", USER_AGENT)
            val status = connection.responseCode
            if (status == 404) throw BarcodeLookupException(BarcodeLookupException.Reason.NOT_FOUND)
            if (status != 200) throw BarcodeLookupException(BarcodeLookupException.Reason.UNAVAILABLE)
            val body = connection.inputStream.bufferedReader().use { it.readText() }
            return parse(body, code)
        } finally {
            connection.disconnect()
        }
    }

    private fun number(nutrients: JsonObject, key: String): Double? {
        val primitive = nutrients[key] as? JsonPrimitive ?: return null
        if (primitive is JsonNull) return null
        val value = if (primitive.isString) primitive.content.trim().toDoubleOrNull()
            else if (primitive.content == "true" || primitive.content == "false") null else primitive.doubleOrNull
        return value?.takeIf { it.isFinite() && it >= 0 }
    }

    fun parse(json: String, code: String): BarcodeProduct {
        val root = runCatching { LeanrJson.parseToJsonElement(json).jsonObject }.getOrNull()
            ?: throw BarcodeLookupException(BarcodeLookupException.Reason.UNAVAILABLE)
        return parse(root, code)
    }

    fun parse(root: JsonObject, code: String): BarcodeProduct {
        val incomplete = BarcodeLookupException(BarcodeLookupException.Reason.INCOMPLETE)
        val status = (root["status"] as? JsonPrimitive)?.takeIf { !it.isString }?.intOrNull
        val product = root["product"] as? JsonObject
        if (status != 1 || product == null) throw BarcodeLookupException(BarcodeLookupException.Reason.NOT_FOUND)
        val nutrients = product["nutriments"] as? JsonObject ?: JsonObject(emptyMap())
        fun number(key: String) = number(nutrients, key)
        fun calories(suffix: String): Double? =
            number("energy-kcal_$suffix") ?: (number("energy-kj_$suffix") ?: number("energy_$suffix"))?.let { it / 4.184 }
        fun text(key: String): String = ((product[key] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: "").trim()
        // Keep all nutrients on one basis. Never mix per-serving and per-100 values.
        val hasServing = text("serving_size").isNotEmpty() && calories("serving") != null && number("proteins_serving") != null
        val per100 = !hasServing && calories("100g") != null && number("proteins_100g") != null
        val suffix = if (per100) "100g" else "serving"
        val cal = calories(suffix) ?: throw incomplete
        val protein = number("proteins_$suffix") ?: throw incomplete
        if (!per100 && text("serving_size").isEmpty()) throw incomplete
        val name = text("product_name_en").ifEmpty { text("product_name") }
        if (name.isEmpty()) throw incomplete
        val servingMeasure = LabelParser.measure(text("serving_size"))
        val unit = servingMeasure?.unit
            ?: if (listOf(text("serving_quantity_unit"), text("product_quantity_unit")).any { it.lowercase() == "ml" }) "mL" else "g"
        val source = "https://world.openfoodfacts.org/product/$code"
        val extras = LinkedHashMap<String, Double>()
        for ((local, remote) in listOf("sat" to "saturated-fat", "sugar" to "sugars", "fibre" to "fiber")) {
            number("${remote}_$suffix")?.let { extras[local] = it }
        }
        // Open Food Facts' normalised sodium values are grams; Leanrrr stores sodium in milligrams.
        number("sodium_$suffix")?.let { extras["sodium"] = it * 1000 }
        val brand = text("brands")
        var food = Food(
            name = if (brand.isEmpty()) name else "$name · $brand", kj = cal * 4.184, cal = cal,
            p = protein, c = number("carbohydrates_$suffix"), f = number("fat_$suffix"),
            serve = if (per100) "100 $unit" else text("serving_size"), nut = extras,
            note = "Source: Open Food Facts (ODbL) · $source. Check against the package label.",
            barcode = code,
        )
        if (!food.isValid) throw incomplete
        if (per100 && servingMeasure != null) {
            val ratio = servingMeasure.amount / 100
            food = food.copy(cal = food.cal * ratio, kj = food.kj * ratio, p = food.p * ratio, c = food.c?.let { it * ratio },
                f = food.f?.let { it * ratio }, nut = food.nut?.mapValues { it.value * ratio }, serve = text("serving_size"))
            return BarcodeProduct(food, per100 = false, unit = unit, sourceURL = source)
        }
        return BarcodeProduct(food, per100 = per100, unit = unit, sourceURL = source)
    }
}

/** A product found by searching Open Food Facts by name: per 100 g or mL, from the search index. */
data class ProductHit(val product: BarcodeProduct, val code: String)

/**
 * Finds packaged foods by name in Open Food Facts. Only runs when asked (Open Food Facts doesn't allow search-as-you-type),
 * and only letters and numbers go out.
 */
object ProductSearch {
    const val LIMIT = 20

    /** The words searched for: letters and numbers only, so typed punctuation can't change the query. */
    fun terms(text: String): String = ScanSearch.tokens(text).take(8).joinToString(" ") { it.take(30) }

    /** `country` is an Open Food Facts country tag ("en:australia"); null searches every country. */
    fun url(terms: String, country: String?): String {
        fun enc(s: String) = URLEncoder.encode(s, "UTF-8").replace("+", "%20")
        val q = if (country != null) "$terms countries_tags:\"$country\"" else terms
        return "https://search.openfoodfacts.org/search?q=${enc(q)}&langs=en&page_size=${LIMIT * 2}" +
            "&fields=${enc("code,product_name,product_name_en,brands,quantity,nutriments")}"
    }

    /** Products sold in the country chosen for menus first; the rest of the world only if none match. Blocking. */
    fun search(text: String, country: String): List<ProductHit> {
        val terms = terms(text)
        if (terms.isEmpty()) return emptyList()
        val local = fetch(url(terms, country))
        return local.ifEmpty { fetch(url(terms, null)) }
    }

    private fun fetch(url: String): List<ProductHit> {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 20_000; connection.readTimeout = 20_000; connection.useCaches = false
            connection.setRequestProperty("User-Agent", "Leanrrr/1.0 (Android; com.isaiahgraham.leanrrr)")
            if (connection.responseCode != 200) throw BarcodeLookupException(BarcodeLookupException.Reason.UNAVAILABLE)
            return parse(connection.inputStream.bufferedReader().use { it.readText() })
        } catch (e: IOException) {
            throw BarcodeLookupException(BarcodeLookupException.Reason.UNAVAILABLE)
        } finally { connection.disconnect() }
    }

    /** Products with energy and protein, without repeats, in the order Open Food Facts ranked them. */
    fun parse(json: String): List<ProductHit> {
        val root = runCatching { LeanrJson.parseToJsonElement(json).jsonObject }.getOrNull()
        val hits = root?.get("hits") as? JsonArray ?: throw BarcodeLookupException(BarcodeLookupException.Reason.UNAVAILABLE)
        val seen = HashSet<String>()
        val results = mutableListOf<ProductHit>()
        for (element in hits) {
            val hit = element as? JsonObject ?: continue
            val code = (hit["code"] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: continue
            if (code.length !in 4..14 || !code.all { it in '0'..'9' }) continue
            val fields = hit.toMutableMap<String, JsonElement>()
            // The index lists brands as a list; the product page as text.
            (hit["brands"] as? JsonArray)?.let { list -> fields["brands"] = JsonPrimitive(list.mapNotNull { (it as? JsonPrimitive)?.content }.joinToString(", ")) }
            val quantity = (hit["quantity"] as? JsonPrimitive)?.takeIf { it.isString }?.content
            if (quantity != null && LabelParser.measure(quantity)?.unit == "mL") fields["product_quantity_unit"] = JsonPrimitive("ml")
            fields.remove("serving_size")
            val wrapped = buildJsonObject { put("status", 1); put("product", JsonObject(fields)) }
            val product = runCatching { BarcodeLookup.parse(wrapped, code) }.getOrNull() ?: continue
            if (!product.per100 || product.food.cal > 950 || product.food.p > 100) continue
            val key = "${product.food.name.lowercase()}|${Math.round(product.food.cal)}|${Math.round(product.food.p)}"
            if (!seen.add(key)) continue
            results += ProductHit(product, code)
            if (results.size == LIMIT) break
        }
        return results
    }
}
