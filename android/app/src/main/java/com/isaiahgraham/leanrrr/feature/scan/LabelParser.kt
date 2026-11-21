package com.isaiahgraham.leanrrr.feature.scan

import com.isaiahgraham.leanrrr.data.nutrientNames

// Pure Kotlin (no Android classes), so the JUnit tests run it on the JVM. A port of LabelParser.swift.

/**
 * Conservative suggestions from a nutrition panel's text: only explicitly labelled lines with numeric values are used.
 * People choose the column and review the result before saving.
 */
object LabelParser {
    data class Layout(
        val servingColumn: Int? = null,
        val per100Column: Int? = null,
        val amount: Double? = null,
        val unit: String = "g",
        val servingDescription: String? = null,
    )

    data class Measure(val amount: Double, val unit: String)

    private val measureRegex = Regex("""(\d+(?:[.,]\d+)?)\s*(kg|ml|g|l)\b""", RegexOption.IGNORE_CASE)
    private val headerRegex = Regex("""per\s*(100\s*(?:g|ml)|serving|serve)\b""", RegexOption.IGNORE_CASE)
    private val servingSizeRegex = Regex("""\bserv(?:ing|e)\s*size\b""", RegexOption.IGNORE_CASE)
    private val servingPrefix = Regex("""(?i)^.*?serv(?:ing|e)\s*size\s*[:\-]?\s*""")
    private val tokenRegex = Regex("""(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:[.,]\d+)?)\s*(kcal|kj|cal|mg|µg|g|%)?""", RegexOption.IGNORE_CASE)
    private val groupedRegex = Regex("""^\d{1,3}(,\d{3})+(\.\d+)?$""")
    private val kjSpaced = Regex("""k\s+j\b""")
    private val kcalSpaced = Regex("""k\s+cal\b""")
    /** A zero is often read as the letter O ("Og"); left alone it drops out and shifts the columns. */
    private val letterO = Regex("""(?<![a-z0-9.])o(?=(?:\.\d+)?\s?(?:mg|g)\b)""")

    /** The weight or volume in a serving description: "1 bar (40 g)" is 40 g, "1 L" is 1000 mL. */
    fun measure(description: String): Measure? {
        val match = measureRegex.find(description) ?: return null
        val amount = match.groupValues[1].replace(",", ".").toDoubleOrNull()?.takeIf { it > 0 } ?: return null
        val unit = match.groupValues[2].lowercase()
        return Measure(amount * (if (unit == "kg" || unit == "l") 1000 else 1), if (unit == "ml" || unit == "l") "mL" else "g")
    }

    fun layout(text: String): Layout {
        val columns = mutableListOf<Boolean>()
        for (match in headerRegex.findAll(text)) {
            val hundred = match.groupValues[1].startsWith("100")
            if (hundred !in columns) columns += hundred
        }
        var result = Layout(
            servingColumn = columns.indexOf(false).takeIf { it >= 0 },
            per100Column = columns.indexOf(true).takeIf { it >= 0 },
        )
        val lines = text.lines()
        for ((index, line) in lines.withIndex()) {
            if (!servingSizeRegex.containsMatchIn(line)) continue
            val description = line.replaceFirst(servingPrefix, "")
            val candidate = description.ifEmpty { lines.getOrNull(index + 1) ?: "" }
            if (candidate.isNotEmpty()) result = result.copy(servingDescription = candidate.trim())
            val value = measure(candidate)
            if (value != null) {
                result = result.copy(amount = value.amount, unit = value.unit, servingDescription = candidate.trim())
                break
            }
        }
        return result
    }

    /** The column's figures for one serving: a per-100 column is converted when the label gives a serving size. */
    fun servingSuggestions(text: String, column: Int): Map<String, Double> {
        val info = layout(text)
        val ratio = if (info.per100Column == column) (info.amount?.let { it / 100 } ?: 1.0) else 1.0
        return suggestions(text, column).mapValues { it.value * ratio }
    }

    private val aliases: List<Pair<String, List<String>>> = listOf(
        "sat" to listOf("saturated"), "trans" to listOf("trans fat"), "sugar" to listOf("sugars", "sugar"),
        "fibre" to listOf("dietary fibre", "dietary fiber", "fibre", "fiber"),
        "sodium" to listOf("sodium"), "potassium" to listOf("potassium"), "calcium" to listOf("calcium"), "iron" to listOf("iron"),
        "chol" to listOf("cholesterol"), "caffeine" to listOf("caffeine"), "p" to listOf("protein"),
        "c" to listOf("total carbohydrate", "carbohydrate", "carbs"), "f" to listOf("total fat", "fat"),
    )

    private val energyWords = listOf("energy", "calories", "kilojoules", "kj", "kcal")

    fun suggestions(text: String, column: Int): Map<String, Double> {
        val result = LinkedHashMap<String, Double>()
        var statedCalories: Double? = null
        var statedKilojoules: Double? = null
        var pendingEnergyLabel: String? = null
        for (line in text.lines()) {
            var lower = line.lowercase().trim { it.isWhitespace() || it in "-–—•" }
                .replace(kjSpaced, "kj").replace(kcalSpaced, "kcal").replace(letterO, "0")
            // OCR may put the energy heading on the line before its values.
            val heading = pendingEnergyLabel
            if (heading != null && lower.firstOrNull()?.isDigit() == true) lower = "$heading $lower"
            pendingEnergyLabel = null
            val isEnergyLabel = energyWords.any { lower.startsWith(it) }
            if (isEnergyLabel && lower.none { it.isDigit() }) { pendingEnergyLabel = lower; continue }
            // Values preceded by less-than signs are bounds, not measured values.
            if (lower.contains("<") || lower.contains("less than")) continue
            val tokens = tokenRegex.findAll(lower).mapNotNull { match ->
                val raw = match.groupValues[1]
                val grouped = groupedRegex.matches(raw)
                val value = raw.replace(",", if (grouped) "" else ".").toDoubleOrNull() ?: return@mapNotNull null
                val unit = match.groupValues[2].lowercase()
                if (unit == "%") null else value to unit
            }.toList()
            val isStandaloneEnergy = lower.firstOrNull()?.isDigit() == true && tokens.any { it.second in setOf("kj", "kcal", "cal") }
            if (isEnergyLabel || isStandaloneEnergy) {
                val calories = tokens.filter { it.second == "cal" || it.second == "kcal" }
                val joules = tokens.filter { it.second == "kj" }
                if (column in calories.indices) statedCalories = calories[column].first
                if (column in joules.indices) statedKilojoules = joules[column].first
                if (calories.isEmpty() && joules.isEmpty() && column in tokens.indices) {
                    if (lower.startsWith("calories") || lower.contains("kcal")) statedCalories = tokens[column].first
                    else if (lower.contains("kj") || lower.contains("kilojoules")) statedKilojoules = tokens[column].first
                }
            } else {
                val key = aliases.firstOrNull { (_, names) -> names.any { lower.startsWith(it) || lower.startsWith("- $it") } }?.first
                if (key != null && column in tokens.indices) {
                    val (value, unit) = tokens[column]
                    val wanted = nutrientNames.firstOrNull { it.key == key }?.unit ?: "g"
                    when {
                        unit.isEmpty() || unit == wanted.lowercase() -> result[key] = value
                        unit == "g" && wanted == "mg" -> result[key] = value * 1000
                        unit == "mg" && wanted == "g" -> result[key] = value / 1000
                    }
                }
            }
        }
        // Prefer explicitly printed calories regardless of the order of energy rows.
        val cal = statedCalories ?: statedKilojoules?.let { it / 4.184 }
        if (cal != null) result["cal"] = cal else result.remove("cal")
        return result
    }
}
