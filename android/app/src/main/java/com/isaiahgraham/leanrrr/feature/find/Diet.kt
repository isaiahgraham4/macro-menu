package com.isaiahgraham.leanrrr.feature.find

import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.DietInfo
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.Prefs

// A port of Diet.swift: dietary needs set on Find, which leave items out of orders, Best choices, search and suggestions.

enum class DietOption(val raw: String, val title: String) {
    VEGETARIAN("vegetarian", "Vegetarian"), VEGAN("vegan", "Vegan"), NO_BEEF("nobeef", "No beef"), NO_PORK("nopork", "No pork"),
    GLUTEN("gluten", "Gluten"), WHEAT("wheat", "Wheat"), MILK("milk", "Milk"), EGG("egg", "Eggs"), SOY("soy", "Soy"),
    SESAME("sesame", "Sesame"), PEANUT("peanut", "Peanuts"), TREENUT("treenut", "Tree nuts"), FISH("fish", "Fish"),
    SHELLFISH("shellfish", "Shellfish"), LUPIN("lupin", "Lupin"), SULPHITES("sulphites", "Sulphites");

    val isAllergen: Boolean get() = this in allergenOptions
    /** Short words for a summary: "Vegetarian · No gluten". */
    val short: String get() = if (isAllergen) "No ${title.lowercase()}" else title

    companion object {
        val meatOptions = listOf(VEGETARIAN, VEGAN, NO_BEEF, NO_PORK)
        val allergenOptions = listOf(GLUTEN, WHEAT, MILK, EGG, SOY, SESAME, PEANUT, TREENUT, FISH, SHELLFISH, LUPIN, SULPHITES)
        val allergenKeys: Set<String> = allergenOptions.map { it.raw }.toSet()
        fun fromRaw(raw: String): DietOption? = entries.firstOrNull { it.raw == raw }

        /** An allergen's name in a sentence: "Contains gluten, milk". */
        fun allergenName(key: String): String = fromRaw(key)?.title?.lowercase() ?: key

        const val FISH_WORDS = """fish|salmon|tuna|\bcod\b|sardine|anchov|barramundi|snapper|trout|tilapia|mackerel|sea bass|flounder|\bsole\b"""
        const val SHELLFISH_WORDS = """prawn|shrimp|crab|lobster|oyster|mussel|scallop|squid|calamari|octopus"""
        val meatWords: Map<String, String> = mapOf(
            "beef" to """\bbeef|steak|\bmince|veal|brisket|hamburger|cheeseburger|meatball""",
            "pork" to """\bpork|bacon|\bham\b|salami|prosciutto|chorizo|pepperoni|bratwurst|italian sausage""",
            "chicken" to """chicken|turkey|\bduck""", "lamb" to """\blamb\b|mutton""", "fish" to FISH_WORDS,
            "seafood" to SHELLFISH_WORDS, "gelatine" to """gelatin|jelly""", "other" to """\bmeat\b|sausage|wonton|egg rolls?\b""",
        )
        /** Plain single foods with no allergens, named only with how they're prepared: "Banana", "Chicken breast, cooked". */
        const val PLAIN_FOODS = """^(banana|apple|orange|mandarin|pear|strawberries|blueberries|raspberries|blackberries|grapes|watermelon|rockmelon|honeydew melon|pineapple|mango|avocado|kiwifruit|peach|plum|cherries|lemon|lime|apricot|nectarine|papaya|passionfruit|grapefruit|figs|pomegranate|lychees|broccoli|carrot|spinach|cos lettuce|iceberg lettuce|green leaf lettuce|tomato|cucumber|onion|red capsicum|green capsicum|mushrooms|corn|sweet corn|peas|green beans|cauliflower|zucchini|cabbage|red cabbage|pumpkin|butternut pumpkin|asparagus|kale|celery|beetroot|eggplant|garlic|ginger|red chilli|potato|sweet potato|bok choy|brussels sprouts|snow peas|bean sprouts|leek|spring onion|rocket|radish|silverbeet|parsnip|white rice|brown rice|wild rice|quinoa|chicken breast|chicken thigh|chicken drumstick|chicken mince|turkey breast|turkey mince|beef mince|sirloin steak|eye fillet|pork tenderloin|pork chop|pork mince|pork belly|lamb loin|lamb mince|black beans|kidney beans|chickpeas|lentils|red lentils|cannellini beans|pinto beans|navy beans|lima beans|olive oil|canola oil|coconut oil|avocado oil|sugar|brown sugar|maple syrup|black coffee|espresso|black tea|green tea|coconut water)(, (raw|cooked|boiled|baked|roasted|fresh|canned|lean|uncooked|\d+% fat))*$"""
        val allergenWords: Map<String, String> = mapOf(
            "gluten" to """bread|wheat|pasta|spaghetti|noodle|flour|toast|cereal|\boats?\b|barley|\brye\b|beer|biscuit|cake|cracker|muffin|pizza|couscous|bagel|croissant|tortilla|wrap|weet|bran|crumpet|pastry|pie\b""",
            "milk" to """\bmilk|cheese|yog|butter|cream|latte|cappuccino|flat white|whey|custard|ice cream|ricotta|feta|mozzarella|parmesan""",
            "wheat" to """bread|wheat|pasta|spaghetti|noodle|flour|toast|cereal|\boats?\b|biscuit|cake|cracker|muffin|pizza|couscous|bagel|croissant|tortilla|wrap|weet|bran|crumpet|pastry|pie\b|semolina|spelt""",
            "egg" to """\beggs?\b|mayo|omelette|frittata""", "soy" to """\bsoy|tofu|edamame|tempeh|miso""", "sesame" to """sesame|tahini|hummus""",
            "peanut" to "peanut", "treenut" to """almond|cashew|walnut|pecan|pistachio|hazelnut|macadamia|brazil nut|\bnuts?\b""",
            "fish" to FISH_WORDS, "shellfish" to SHELLFISH_WORDS, "lupin" to "lupin",
            // Sulphites keep dried fruit, wine, cordial and sausages.
            "sulphites" to """\bwine|beer|cider|dried|sultana|raisin|prune|cordial|sausage|\bham\b|salami|vinegar|pickle""",
        )
    }
}

object DietGuess {
    private val compiled = HashMap<String, Regex>()
    private fun regex(pattern: String): Regex = synchronized(compiled) { compiled.getOrPut(pattern) { Regex(pattern) } }
    private const val ANIMAL = """honey|\bmilk|cheese|yog|butter|cream|egg|whey"""

    /**
     * The fallback for an everyday food without its own diet data, from the name. A name with no allergen word only counts as
     * allergen-free when it's a plain single food; anything else has unknown allergens, so it's left out when one is avoided.
     */
    fun guess(name: String): DietInfo {
        val lower = name.lowercase()
        val meat = DietOption.meatWords.filter { regex(it.value).containsMatchIn(lower) }.keys.sorted()
        val al = DietOption.allergenWords.filter { regex(it.value).containsMatchIn(lower) }.keys.sorted()
        val plain = regex(DietOption.PLAIN_FOODS).containsMatchIn(lower)
        val animal = regex(ANIMAL).containsMatchIn(lower)
        return DietInfo(meat = meat, al = if (al.isEmpty() && !plain) null else al,
            vg = if (meat.isEmpty()) (if (animal) "vegetarian" else "vegan") else null, src = "name")
    }

    /** Everyday foods' own diet data by ID, for copies saved in logs and meals before foods carried it. */
    @Volatile private var everydayCache: Pair<Int, Map<String, DietInfo>>? = null
    fun everyday(id: String): DietInfo? {
        val foods = runCatching { AppServices.store.everyday }.getOrNull() ?: return null
        val cached = everydayCache
        val map = if (cached != null && cached.first == System.identityHashCode(foods)) cached.second
            else foods.mapNotNull { f -> f.diet?.let { f.id to it } }.toMap().also { everydayCache = System.identityHashCode(foods) to it }
        return map[id]
    }
}

/**
 * The dietary needs set on Find. An item is only offered when the restaurant's own words show it fits; anything unknown is left out.
 */
data class DietFilter(val options: Set<DietOption> = emptySet()) {
    val isEmpty: Boolean get() = options.isEmpty()
    val raw: String get() = options.map { it.raw }.sorted().joinToString(",")
    val allergens: Set<String> get() = options.filter { it.isAllergen }.map { it.raw }.toSet()

    /** "Vegetarian · No gluten", in the order the options are listed. */
    val summary: String
        get() {
            // Vegan covers vegetarian, and either covers no beef and no pork.
            val shown = options.toMutableSet()
            if (DietOption.VEGAN in shown) shown.remove(DietOption.VEGETARIAN)
            if (DietOption.VEGAN in shown || DietOption.VEGETARIAN in shown) shown.removeAll(setOf(DietOption.NO_BEEF, DietOption.NO_PORK))
            return DietOption.entries.filter { it in shown }.joinToString(" · ") { it.short }
        }

    /** Whether an item fits. Your own foods always do: you know what's in them. */
    fun allows(food: Food): Boolean {
        if (isEmpty || food.chain == "mine") return true
        val info = (if (food.isEveryday) food.diet ?: DietGuess.everyday(food.id) ?: DietGuess.guess(food.name) else food.diet) ?: return false
        if (options.any { !it.isAllergen }) {
            val meat = info.meat ?: return false
            if (DietOption.VEGETARIAN in options && meat.isNotEmpty()) return false
            if (DietOption.VEGAN in options && !info.isVegan) return false
            // Gelatine is made from pork or beef, so it counts against both.
            if (DietOption.NO_BEEF in options && ("beef" in meat || "gelatine" in meat)) return false
            if (DietOption.NO_PORK in options && ("pork" in meat || "gelatine" in meat)) return false
        }
        val avoid = allergens
        if (avoid.isNotEmpty()) {
            // "May contain" counts too, and so does one it doesn't say either way about.
            val al = info.al ?: return false
            val listed = (al + (info.may ?: emptyList()) + (info.unk ?: emptyList())).toSet()
            // An allergen named some other way can't be shown to fit, so the item is left out.
            if (!DietOption.allergenKeys.containsAll(listed)) return false
            if (avoid.any { it in listed }) return false
            // Wheat is gluten too, wherever a menu says so without saying gluten.
            if ("gluten" in avoid && ("wheat" in al || info.may?.contains("wheat") == true)) return false
        }
        return true
    }

    companion object {
        const val STORAGE_KEY = "diet.filter"
        fun fromRaw(raw: String): DietFilter = DietFilter(raw.split(",").mapNotNull { DietOption.fromRaw(it) }.toSet())
        /** What's set on this device. */
        val saved: DietFilter get() = fromRaw(runCatching { Prefs.string(STORAGE_KEY) }.getOrNull() ?: "")
    }
}

/** "KFC's", but "Nando's" and "McDonald's" stay as they are. */
val String.possessive: String get() = if (endsWith("'s") || endsWith("’s")) this else "$this's"
