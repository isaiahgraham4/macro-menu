package com.isaiahgraham.leanrrr.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToLong

// A port of ios/MacroMenu/Models.swift. Field names match the Swift ones so the JSON is the same on both platforms.

@Serializable
data class Chain(
    val id: String,
    val name: String,
    val url: String? = null,
    val src: String? = null,
    val psrc: String? = null,
    /** How the nutrition figures were collected, e.g. "Official nutrition guide". */
    val how: String? = null,
)

@Serializable
data class Modifier(
    val key: String,
    val id: String,
    val kind: String,
    val name: String,
    val kj: Double,
    val p: Double,
    val c: Double? = null,
    val f: Double? = null,
    val nut: Map<String, Double>? = null,
    val price: Double? = null,
    /** True when protein, carbs and fat are estimated (McDonald's publishes only each ingredient's energy). */
    val est: Boolean? = null,
) {
    val group: String?
        get() {
            if (kind != "r" && kind != "s") return null
            // Grill'd: one bun and one patty at a time.
            if (key.startsWith("s:bun-")) return "bun"
            if (key.startsWith("s:patty-")) return "patty"
            return listOf("rice", "beans", "cheese", "caesar-dressing", "fries", "sour-cream", "guacamole", "pico", "lettuce",
                "tomatillo", "corn-chips", "jalapeno").firstOrNull { id.contains(it) } ?: id
        }
}

/** The meats and allergens in a food (see `DietInfo` in Diet.swift). */
@Serializable
data class DietInfo(
    val meat: List<String>? = null,
    val al: List<String>? = null,
    val may: List<String>? = null,
    val unk: List<String>? = null,
    val vg: String? = null,
    val src: String? = null,
) {
    val isVegetarian: Boolean get() = meat?.isEmpty() == true
    val isVegan: Boolean get() = vg == "vegan"
}

@Serializable
data class Food(
    val id: String = newId(),
    val chain: String = "mine",
    val name: String,
    val cat: String = "main",
    val kj: Double,
    val cal: Double,
    val p: Double,
    val c: Double? = null,
    val f: Double? = null,
    val serve: String = "1 serving",
    val nut: Map<String, Double>? = null,
    val price: Double? = null,
    val pf: Boolean? = null,
    val modifiers: List<Modifier>? = null,
    val ingredients: List<Portion>? = null,
    val recipeYield: Double? = null,
    val note: String? = null,
    /** The product barcode, so scanning it again finds this food. */
    val barcode: String? = null,
    val diet: DietInfo? = null,
    /** One of your own foods that you chose to share with other Leanrrr users. */
    val shared: Boolean? = null,
    /** For a food someone else shared: their anonymous ID, so you can hide their foods. */
    val contributor: String? = null,
) {
    val isAnchor: Boolean get() = chain == "mine" || cat == "main" || cat == "breakfast"
    val isEveryday: Boolean get() = chain == EVERYDAY
    /** One of the thousands of USDA survey foods: searchable, but ranked after Leanrrr's own and never suggested. */
    val isSurvey: Boolean get() = isEveryday && diet?.src == "usda"
    val everydaySource: String?
        get() = if (isEveryday && id.startsWith("usda-")) "https://fdc.nal.usda.gov/food-details/${id.drop(5)}/nutrients" else null
    val isSupermarket: Boolean get() = chain in SUPERMARKETS
    val isCommunity: Boolean get() = chain == COMMUNITY
    val productSource: String?
        get() = if (isSupermarket) id.split(":").lastOrNull()?.let { "https://world.openfoodfacts.org/product/$it" } else null

    val isValid: Boolean
        get() = id.isNotEmpty() && name.isNotBlank() &&
            listOfNotNull(kj, cal, p, c, f, price).all { it.isFinite() && it >= 0 } &&
            (nut ?: emptyMap()).values.all { it.isFinite() && it >= 0 } &&
            (ingredients ?: emptyList()).all { it.isValid } &&
            (recipeYield?.let { it.isFinite() && it > 0 } ?: true)

    /** Published energy more than 15% off 4/4/9 of the macros. */
    val mismatch: Boolean
        get() {
            if (isEveryday) return false
            val c = c ?: return false
            val f = f ?: return false
            if (cal <= 40) return false
            return abs(p * 4 + c * 4 + f * 9 - cal) > max(25.0, cal * 0.15)
        }

    /** The weight or volume in the serve text, in g or mL: "244 g" is (244, "g"). */
    val servingWeight: Pair<Double, String>?
        get() {
            val match = Regex("""(\d+(?:\.\d+)?)\s*(ml|mL|kg|g|L|l)\b""").findAll(serve).lastOrNull() ?: return null
            val amount = match.groupValues[1].toDoubleOrNull()?.takeIf { it > 0 } ?: return null
            val unit = match.groupValues[2].lowercase()
            return Pair(amount * (if (unit == "kg" || unit == "l") 1000 else 1), if (unit == "g" || unit == "kg") "g" else "mL")
        }

    /**
     * This food with modifiers applied (how many of each, by key) and optionally something else added or taken off.
     * Energy and macros change by each part's figures, and it's renamed "Big Mac · No Big Mac Sauce". Unchanged when nothing is selected.
     */
    fun customised(changes: Map<String, Double>, adding: Food? = null, subtract: Boolean = false, name: String = ""): Food {
        var kj = this.kj; var p = this.p; var c = this.c; var f = this.f; var price = this.price
        val nut = this.nut?.toMutableMap()
        val names = mutableListOf<String>()
        for (mod in (modifiers ?: emptyList()).filter { (changes[it.key] ?: 0.0) > 0 }) {
            val q = changes[mod.key] ?: 0.0
            kj += mod.kj * q; p += mod.p * q
            c = if (c != null && mod.c != null) c + mod.c * q else null
            f = if (f != null && mod.f != null) f + mod.f * q else null
            nut?.keys?.toList()?.forEach { key ->
                val delta = mod.nut?.get(key)
                if (delta != null) nut[key] = (nut[key] ?: 0.0) + delta * q
                // Estimated removals leave other nutrients as listed rather than hiding them.
                else if (mod.est != true) nut.remove(key)
            }
            price = if (price != null && mod.price != null) max(0.0, price + mod.price * q) else null
            names += (if (q > 1) q.number + " × " else "") + mod.name
        }
        if (adding != null) {
            val sign = if (subtract) -1.0 else 1.0
            kj += adding.kj * sign; p += adding.p * sign
            c = if (c != null && adding.c != null) c + adding.c * sign else null
            f = if (f != null && adding.f != null) f + adding.f * sign else null
            nut?.keys?.toList()?.forEach { key ->
                val delta = adding.nut?.get(key)
                if (delta != null) nut[key] = (nut[key] ?: 0.0) + delta * sign else nut.remove(key)
            }
            price = if (price != null && adding.price != null) max(0.0, price + adding.price * sign) else null
            names += (if (subtract) "Without " else "Extra ") + adding.name
        }
        if (names.isEmpty()) return this
        val finalKj = max(0.0, kj)
        return copy(
            kj = finalKj, cal = (finalKj / 4.184).roundToLong().toDouble(), p = max(0.0, p),
            c = c?.let { max(0.0, it) }, f = f?.let { max(0.0, it) },
            nut = nut?.mapValues { max(0.0, it.value) }, price = price,
            name = name.ifEmpty { this.name + " · " + names.joinToString(", ") },
            note = "Based on ${this.name}. " + names.joinToString(", "),
            modifiers = null,
        )
    }

    /** This recipe with any recipe among its ingredients swapped for that recipe's own. Its figures stay as they are. */
    val brokenIntoIngredients: Food get() = ingredients?.let { copy(ingredients = recipesBrokenUp(it)) } ?: this

    companion object {
        /** Everyday foods such as bananas and chicken breast, from USDA FoodData Central. */
        const val EVERYDAY = "generic"
        /** Ready meals and snacks from SupermarketFoods.json. */
        val SUPERMARKETS = setOf("coles", "woolworths")
        /** Foods other Leanrrr users shared. */
        const val COMMUNITY = "community"
    }
}

@Serializable
data class Portion(
    val id: String = newId(),
    val food: Food,
    val quantity: Double = 1.0,
) {
    val isValid: Boolean get() = food.isValid && quantity.isFinite() && quantity > 0 && quantity <= 10000

    /** For a recipe, its ingredients scaled to this portion. Null for anything that isn't a recipe. */
    val ingredientPortions: List<Portion>?
        get() {
            val ingredients = food.ingredients?.takeIf { it.isNotEmpty() } ?: return null
            val share = quantity / max(food.recipeYield ?: 1.0, 0.001)
            return ingredients.map { it.copy(quantity = it.quantity * share) }
        }
}

/** What a meal is made of, for listing: a recipe's ingredients in place of the recipe, anything else as it is. */
fun mealLines(items: List<Portion>): List<Portion> = items.flatMap { item -> item.ingredientPortions?.let(::mealLines) ?: listOf(item) }

/** A list of foods with any recipe in it swapped for its ingredients, and a food that then appears twice made into one line. */
fun recipesBrokenUp(items: List<Portion>): List<Portion> {
    if (items.none { it.ingredientPortions != null }) return items
    val lines = mutableListOf<Portion>()
    for (line in QuickLog.copies(mealLines(items))) {
        val i = lines.indexOfFirst { it.food == line.food }
        if (i >= 0) lines[i] = lines[i].copy(quantity = lines[i].quantity + line.quantity) else lines += line
    }
    return lines
}

/** Foods put together in one meal, listing every ingredient rather than a recipe they started from. A recipe on its own stays a recipe. */
fun combined(items: List<Portion>): List<Portion> = if (items.size > 1) recipesBrokenUp(items) else items

class Nutrition(portions: List<Portion>) {
    var cal = 0.0; var kj = 0.0; var p = 0.0; var c = 0.0; var f = 0.0; var price = 0.0
    var missingCarbs = false; var missingFat = false; var missingPrice = false; var fromPrice = false
    val nut = mutableMapOf<String, Double>()
    val partial = mutableSetOf<String>()

    init {
        val keys = portions.flatMap { (it.food.nut ?: emptyMap()).keys }.toSet()
        for (portion in portions) {
            val food = portion.food; val q = portion.quantity
            cal += food.cal * q; kj += food.kj * q; p += food.p * q
            c += (food.c ?: 0.0) * q; f += (food.f ?: 0.0) * q; price += (food.price ?: 0.0) * q
            missingCarbs = missingCarbs || food.c == null
            missingFat = missingFat || food.f == null
            missingPrice = missingPrice || food.price == null
            fromPrice = fromPrice || food.pf == true
            for (key in keys) {
                val value = food.nut?.get(key)
                if (value != null) nut[key] = (nut[key] ?: 0.0) + value * q else partial += key
            }
        }
    }

    fun value(key: String): Double = when (key) { "cal" -> cal; "p" -> p; "c" -> c; "f" -> f; else -> nut[key] ?: 0.0 }
    fun isPartial(key: String): Boolean = when (key) { "c" -> missingCarbs; "f" -> missingFat; else -> key in partial }

    val text: String
        get() = "${cal.number} Cal (${kj.number} kJ) · Protein ${p.number} g · Carbs ${c.number}${if (missingCarbs) "+" else ""} g · " +
            "Fat ${f.number}${if (missingFat) "+" else ""} g"

    val priceText: String
        get() {
            if (price == 0.0 && missingPrice) return "Price unavailable"
            return (if (fromPrice) "From " else "") + price.aud() + (if (missingPrice) "+ (partial)" else "")
        }

    fun food(name: String, servings: Double, ingredients: List<Portion>? = null): Food = Food(
        name = name, kj = kj / servings, cal = cal / servings, p = p / servings,
        c = if (missingCarbs) null else c / servings, f = if (missingFat) null else f / servings,
        nut = nut.filterKeys { it !in partial }.mapValues { it.value / servings },
        price = if (missingPrice) null else price / servings, pf = fromPrice,
        ingredients = ingredients, recipeYield = if (ingredients == null) null else servings,
    )
}

@Serializable
data class SavedMeal(
    val id: String = newId(),
    val name: String,
    val items: List<Portion>,
) {
    val isValid: Boolean get() = name.isNotEmpty() && items.isNotEmpty() && items.all { it.isValid }
}

@Serializable
enum class MealTime {
    @SerialName("breakfast") BREAKFAST,
    @SerialName("lunch") LUNCH,
    @SerialName("dinner") DINNER,
    @SerialName("snacks") SNACKS;

    val raw: String get() = name.lowercase()
    val title: String get() = raw.replaceFirstChar { it.uppercase() }

    companion object {
        /** By the clock, using the same hours as the Log again widget. */
        fun suggested(at: Instant = Instant.now()): MealTime = when (at.atZone(ZoneId.systemDefault()).hour) {
            in 5..10 -> BREAKFAST
            in 11..15 -> LUNCH
            in 16..21 -> DINNER
            else -> SNACKS
        }
        fun fromRaw(raw: String): MealTime? = entries.firstOrNull { it.raw == raw }
    }
}

@Serializable
data class LogEntry(
    val id: String = newId(),
    val name: String,
    val items: List<Portion>,
    val time: AppleInstant = Instant.now(),
    // Optional keeps logs and backups created before meal times readable.
    val mealTime: MealTime? = null,
) {
    val isValid: Boolean get() = name.isNotEmpty() && items.isNotEmpty() && items.all { it.isValid }
}

@Serializable
data class Goals(
    val id: String = newId(),
    val name: String = "Every day",
    val values: Map<String, Double> = mapOf("cal" to 2200.0, "p" to 150.0),
    val minimums: Set<String> = setOf("p", "fibre"),
    val mealCal: Double = 500.0,
    val mealProtein: Double = 40.0,
) {
    val isValid: Boolean
        get() = name.isNotEmpty() && values.values.all { it.isFinite() && it > 0 } && mealCal.isFinite() && mealCal > 0 &&
            mealProtein.isFinite() && mealProtein >= 0
}

@Serializable
data class WeightEntry(
    val id: String = newId(),
    val date: AppleInstant,
    val kg: Double,
    /** Set when the weight came from Health Connect / Apple Health, so it isn't imported twice or written back. */
    val healthID: String? = null,
    /** Kilograms of this reading estimated to be water drunk in the hours before (see WaterWeight). */
    val waterKG: Double? = null,
) {
    val adjustedKG: Double get() = kg - (waterKG ?: 0.0)
    val isValid: Boolean get() = kg.isFinite() && kg in 20.0..400.0 && (waterKG?.let { it.isFinite() && it in 0.0..5.0 } ?: true)
}

@Serializable
data class WeightGoal(
    val kg: Double,
    /** Your trend weight when the goal was set. */
    val startKg: Double,
    val set: AppleInstant,
    /** When a weigh-in first took the trend here, so reaching it is only celebrated once. */
    val reached: AppleInstant? = null,
) {
    val isValid: Boolean get() = kg in 20.0..400.0 && startKg in 20.0..400.0
}

@Serializable
data class BodyMeasurement(
    val id: String = newId(),
    val date: AppleInstant,
    val values: Map<String, Double>,
) {
    val isValid: Boolean get() = values.isNotEmpty() && values.values.all { it.isFinite() && it in 5.0..300.0 }
}

@Serializable
data class WaterSip(
    val id: String = newId(),
    val time: AppleInstant,
    val millilitres: Double,
) {
    val isValid: Boolean get() = millilitres.isFinite() && millilitres > 0 && millilitres <= WaterLimits.DAY_LIMIT
}

@Serializable
data class CheckInRecord(
    val id: String = newId(),
    val date: AppleInstant,
    /** Trend change per week at the time, in kg (negative is losing). */
    val weeklyChange: Double? = null,
    /** Measured maintenance at the time. */
    val maintenance: Double,
    /** The pace asked for, in kg a week. */
    val pace: Double,
    val previousCalories: Double? = null,
    val calories: Double,
    /** False when the suggestion was looked at and the old targets kept. */
    val accepted: Boolean,
) {
    val isValid: Boolean
        get() = listOf(maintenance, pace, calories).all { it.isFinite() } && (weeklyChange?.isFinite() ?: true) &&
            (previousCalories?.isFinite() ?: true) && pace in CheckInLimits.PACE_RANGE && calories in CheckInLimits.CALORIE_RANGE
}

object WaterLimits {
    val TARGET_RANGE = 250.0..10000.0
    val GLASS_RANGE = 50.0..2000.0
    const val DAY_LIMIT = 20000.0
}

object StepLimits {
    val GOAL_RANGE = 1000.0..100_000.0
}

object CheckInLimits {
    val PACE_RANGE = -1.0..0.5
    val CALORIE_RANGE = 1200.0..6000.0
}

private val DAY_KEY = Regex("""^\d{4}-\d{2}-\d{2}$""")
fun isDayKey(key: String): Boolean = DAY_KEY.matches(key)

@Serializable
data class AppData(
    val version: Int = 2,
    val foods: List<Food> = emptyList(),
    val meals: List<SavedMeal> = emptyList(),
    val tray: List<Portion> = emptyList(),
    val logs: Map<String, List<LogEntry>> = emptyMap(),
    val goalSets: List<Goals> = listOf(Goals()),
    val activeGoal: String? = null,
    val dayGoals: Map<String, Goals> = emptyMap(),
    val weights: List<WeightEntry>? = null,
    val weightGoal: WeightGoal? = null,
    val measurements: List<BodyMeasurement>? = null,
    /** Millilitres of water by day, with the daily target and glass size. */
    val water: Map<String, Double>? = null,
    val waterTarget: Double? = null,
    val waterGlass: Double? = null,
    /** When the last two days' water was drunk, for telling how much of a weigh-in is water. */
    val waterSips: List<WaterSip>? = null,
    /** The daily step goal. The step counts themselves stay in Health Connect. */
    val stepGoal: Double? = null,
    val checkIns: List<CheckInRecord>? = null,
    val checkInPace: Double? = null,
    /** Meals planned ahead, by day. They count towards nothing until they're logged. */
    val plans: Map<String, List<LogEntry>>? = null,
    /** Foods pinned to the top of the "+" menu and the Log again widget. */
    val pinned: List<Food>? = null,
    /** Milestones already marked, and targets marked today. */
    val celebrated: Set<String>? = null,
) {
    val weightLog: List<WeightEntry> get() = weights ?: emptyList()
    val measurementLog: List<BodyMeasurement> get() = measurements ?: emptyList()

    val isValid: Boolean
        get() {
            if (version != 2 || goalSets.isEmpty()) return false
            val contents = foods.all { it.isValid } && meals.all { it.isValid } && tray.all { it.isValid } && (pinned ?: emptyList()).all { it.isValid }
            val history = logs.values.flatten().all { it.isValid } && logs.keys.all(::isDayKey)
            val targets = goalSets.all { it.isValid } && dayGoals.values.all { it.isValid }
            val waterOk = (water ?: emptyMap()).all { isDayKey(it.key) && it.value.isFinite() && it.value in 0.0..WaterLimits.DAY_LIMIT } &&
                (waterTarget?.let { it.isFinite() && it in WaterLimits.TARGET_RANGE } ?: true) &&
                (waterGlass?.let { it.isFinite() && it in WaterLimits.GLASS_RANGE } ?: true) &&
                (waterSips ?: emptyList()).all { it.isValid }
            val stepsOk = stepGoal?.let { it.isFinite() && it in StepLimits.GOAL_RANGE } ?: true
            val body = weightLog.all { it.isValid } && (weightGoal?.isValid ?: true) && measurementLog.all { it.isValid } && waterOk && stepsOk
            val checkInsOk = (checkIns ?: emptyList()).all { it.isValid } && (checkIns ?: emptyList()).map { it.id }.toSet().size == (checkIns?.size ?: 0) &&
                (checkInPace?.let { it.isFinite() && it in CheckInLimits.PACE_RANGE } ?: true)
            val plansOk = plans?.let { p -> p.keys.all(::isDayKey) && p.values.all { day -> day.all { it.isValid } } } ?: true
            val unique = foods.map { it.id }.toSet().size == foods.size && meals.map { it.id }.toSet().size == meals.size &&
                goalSets.map { it.id }.toSet().size == goalSets.size && measurementLog.map { it.id }.toSet().size == measurementLog.size
            return contents && history && targets && body && checkInsOk && plansOk && unique
        }
}

@Serializable
data class MenuCatalog(
    /** Which layout this file uses, a fingerprint of its contents, and when it was published (ISO 8601). */
    val format: Int? = null,
    val revision: String? = null,
    val published: String? = null,
    val chains: List<Chain> = emptyList(),
    val foods: List<Food> = emptyList(),
)

data class NutrientName(val key: String, val label: String, val unit: String)

val nutrientNames = listOf(
    NutrientName("cal", "Calories", "Cal"), NutrientName("p", "Protein", "g"), NutrientName("c", "Carbs", "g"),
    NutrientName("f", "Fat", "g"), NutrientName("sat", "Saturated fat", "g"), NutrientName("trans", "Trans fat", "g"),
    NutrientName("sugar", "Sugars", "g"), NutrientName("fibre", "Fibre", "g"), NutrientName("sodium", "Sodium", "mg"),
    NutrientName("potassium", "Potassium", "mg"), NutrientName("calcium", "Calcium", "mg"), NutrientName("iron", "Iron", "mg"),
    NutrientName("chol", "Cholesterol", "mg"), NutrientName("caffeine", "Caffeine", "mg"),
)

fun mealText(name: String, items: List<Portion>): String =
    name + "\n" + items.joinToString("\n") { "${it.quantity.number} × ${it.food.name}" } + "\n" + Nutrition(items).text

/** Past meals to log again in one tap. */
object QuickLog {
    /** Copies of logged items with new IDs, so a new entry is independent of the old one. */
    fun copies(items: List<Portion>): List<Portion> = items.map { it.copy(id = newId()) }

    /** What was logged to `mealTime` the day before `date`. */
    fun previous(mealTime: MealTime, before: Instant, logs: Map<String, List<LogEntry>>): List<LogEntry> {
        val yesterday = before.atZone(ZoneId.systemDefault()).toLocalDate().minusDays(1)
        return (logs[dayKey(yesterday)] ?: emptyList()).filter { it.mealTime == mealTime }
    }

    /** How many servings of a food were logged most recently, if it's been logged at all. */
    fun lastQuantity(foodID: String, logs: Map<String, List<LogEntry>>): Double? {
        for (day in logs.keys.sortedDescending()) {
            for (entry in (logs[day] ?: emptyList()).sortedByDescending { it.time }) {
                entry.items.firstOrNull { it.food.id == foodID }?.let { return it.quantity }
            }
        }
        return null
    }

    /** Foods logged in the last `days` days, newest first, each listed once. */
    fun recentFoods(logs: Map<String, List<LogEntry>>, now: Instant = Instant.now(), days: Long = 30, limit: Int = 8): List<Food> {
        val startKey = dayKey(now.atZone(ZoneId.systemDefault()).toLocalDate().minusDays(days))
        val seen = mutableSetOf<String>(); val foods = mutableListOf<Food>()
        for (day in logs.keys.filter { it >= startKey }.sortedDescending()) {
            for (entry in (logs[day] ?: emptyList()).sortedByDescending { it.time }) {
                for (item in entry.items) {
                    if (seen.add(item.food.chain + "|" + item.food.name.lowercase())) {
                        foods += item.food
                        if (foods.size == limit) return foods
                    }
                }
            }
        }
        return foods
    }

    /** Meals logged most often in the last `days` days, newest copy of each; ties go to the most recent. */
    fun frequent(logs: Map<String, List<LogEntry>>, now: Instant = Instant.now(), days: Long = 30, limit: Int = 6): List<LogEntry> {
        val startKey = dayKey(now.atZone(ZoneId.systemDefault()).toLocalDate().minusDays(days))
        val groups = mutableMapOf<String, Pair<Int, LogEntry>>()
        for ((day, entries) in logs) {
            if (day < startKey) continue
            for (entry in entries) {
                if (entry.items.isEmpty()) continue
                val key = entry.name.lowercase() + "|" + entry.items.map { "${it.food.id}×${it.quantity}" }.sorted().joinToString(",")
                val current = groups[key]
                val latest = current?.let { if (it.second.time > entry.time) it.second else entry } ?: entry
                groups[key] = Pair((current?.first ?: 0) + 1, latest)
            }
        }
        return groups.values.sortedWith(compareByDescending<Pair<Int, LogEntry>> { it.first }.thenByDescending { it.second.time })
            .take(limit).map { it.second }
    }
}

fun Instant.daysUntil(other: Instant): Long = ChronoUnit.DAYS.between(this, other)
