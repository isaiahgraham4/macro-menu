package com.isaiahgraham.leanrrr.feature.find

import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.LeanrJson
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.tenth
import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient

/**
 * Copycat Kitchen (Copycat.swift): home versions of takeaway items, added up from their ingredients and put next to the chain's
 * own figures. The shop side is read from the menu, so a menu update reaches it. Australia only.
 */
@Serializable
data class CopycatBook(val ingredients: Map<String, CopycatIngredient> = emptyMap(), val recipes: List<CopycatRecipe> = emptyList()) {

    /** The one-serve total of a recipe with these swaps on. */
    fun nutrition(recipe: CopycatRecipe, swaps: Set<String> = emptySet()): Nutrition = Nutrition(portions(recipe, swaps))

    /** Every ingredient as a portion of its per-100 g figures, so saving a recipe keeps it editable like one built by hand. */
    fun portions(recipe: CopycatRecipe, swaps: Set<String> = emptySet()): List<Portion> =
        recipe.rows(swaps).mapNotNull { row -> ingredients[row.key]?.let { Portion(food = it.food(row.key, row.label), quantity = row.g / 100) } }

    /** One serve as a food to log or save. The ID follows the recipe and its swaps, so saving it again updates the same food. */
    fun food(recipe: CopycatRecipe, swaps: Set<String> = emptySet(), shopName: String): Food {
        val items = portions(recipe, swaps)
        val value = Nutrition(items).food(if (swaps.isEmpty()) recipe.name else "${recipe.name}, lighter", 1.0, items)
        // Whole calories and tenths of a gram: these are sums of averages, and finer digits would claim more than they know.
        val cal = value.cal.rounded()
        return value.copy(
            cal = cal, kj = cal * 4.184, p = value.p.tenth, c = value.c?.tenth, f = value.f?.tenth,
            nut = value.nut?.mapValues { (key, v) -> if (key == "sodium") v.rounded() else v.tenth },
            id = (listOf("copycat", recipe.id) + swaps.sorted()).joinToString(":"),
            serve = recipe.serving,
            note = "Home version of $shopName, added up from its ingredients.",
        )
    }

    /** Recipes with a shop item still on the menu, each beside that item at the size the recipe is compared with. */
    fun comparisons(menu: List<Food>): List<CopycatComparison> {
        val ids = recipes.map { it.shop }.toSet()
        val shop = LinkedHashMap<String, Food>()
        menu.filter { it.id in ids }.forEach { shop.putIfAbsent(it.id, it) }
        return recipes.mapNotNull { recipe ->
            val food = shop[recipe.shop] ?: return@mapNotNull null
            CopycatComparison(recipe, food, Nutrition(listOf(Portion(food = food, quantity = recipe.quantity))),
                nutrition(recipe), nutrition(recipe, recipe.swaps.map { it.id }.toSet()))
        }
    }

    companion object {
        /** The bundled recipes (CopycatKitchen.json in the assets). Empty if they can't be read. */
        val bundled: CopycatBook by lazy {
            runCatching {
                val text = AppServices.app.assets.open("CopycatKitchen.json").bufferedReader().use { it.readText() }
                LeanrJson.decodeFromString<CopycatBook>(text)
            }.getOrDefault(CopycatBook())
        }
    }
}

@Serializable
data class CopycatIngredient(val kj: Double, val p: Double, val c: Double, val f: Double, val nut: Map<String, Double> = emptyMap()) {
    fun food(key: String, name: String): Food =
        Food(id = "copycat:$key", chain = Food.EVERYDAY, name = name, cat = "food", kj = kj, cal = kj / 4.184, p = p, c = c, f = f, serve = "100 g", nut = nut)
}

@Serializable
data class CopycatRow(
    val slot: String, val key: String, val g: Double, val label: String, val measure: String,
    /** True once a swap has changed this row. Not stored in the recipe file. */
    @Transient val swapped: Boolean = false,
)

@Serializable
data class CopycatSwap(val id: String, val label: String, val why: String, val changes: List<Change>) {
    @Serializable
    data class Change(val slot: String, val key: String? = null, val g: Double? = null, val label: String? = null, val measure: String? = null)
}

@Serializable
data class CopycatRecipe(
    val id: String,
    val name: String,
    /** The menu item it copies, and how many of it make the compared size (three slices of a pizza). */
    val shop: String,
    val quantity: Double,
    val unit: String,
    val serves: Int,
    val time: String,
    val hook: String,
    val verdict: String,
    val method: List<String>,
    val rows: List<CopycatRow>,
    val swaps: List<CopycatSwap>,
) {
    /** "1 burger", or the unit as it stands when it already has a number ("3 large slices"). */
    val serving: String get() = if (unit.firstOrNull()?.isDigit() == true) unit else "1 $unit"

    fun rows(on: Set<String>): List<CopycatRow> {
        val result = rows.toMutableList()
        for (swap in swaps) {
            if (swap.id !in on) continue
            for (change in swap.changes) {
                val i = result.indexOfFirst { it.slot == change.slot }
                if (i < 0) continue
                val r = result[i]
                result[i] = r.copy(key = change.key ?: r.key, g = change.g ?: r.g, label = change.label ?: r.label, measure = change.measure ?: r.measure, swapped = true)
            }
        }
        return result
    }
}

data class CopycatComparison(val recipe: CopycatRecipe, val shopFood: Food, val shop: Nutrition, val home: Nutrition, val lean: Nutrition) {
    val id: String get() = recipe.id
    /** The menu name, without the slice count of an item sold by the slice. */
    val shopName: String get() = shopFood.name.replace(" (1 slice)", "")

    /** Percent change in energy from the shop's figure. */
    fun change(total: Nutrition): Int = if (shop.kj > 0) ((total.kj - shop.kj) / shop.kj * 100).rounded().toInt() else 0
    val verdict: CopycatVerdict get() = CopycatVerdict.of(change(home))
}

/** Within 2% either way is too close to call, given the ingredient figures are averages. */
enum class CopycatVerdict(val title: String) {
    HOME_LIGHTER("Home lighter"), LEVEL("About level"), SHOP_LIGHTER("Shop lighter");
    companion object { fun of(change: Int) = if (change < -2) HOME_LIGHTER else if (change > 2) SHOP_LIGHTER else LEVEL }
}

enum class CopycatSort(val title: String) {
    SAVING("Biggest saving"), PROTEIN("Most extra protein"), FAT("Most fat cut");

    fun sorted(list: List<CopycatComparison>): List<CopycatComparison> = when (this) {
        SAVING -> list.sortedBy { it.change(it.home) }
        PROTEIN -> list.sortedByDescending { it.home.p - it.shop.p }
        FAT -> list.sortedBy { it.home.f - it.shop.f }
    }
}
