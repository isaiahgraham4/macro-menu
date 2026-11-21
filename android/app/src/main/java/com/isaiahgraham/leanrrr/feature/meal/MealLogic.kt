package com.isaiahgraham.leanrrr.feature.meal

import com.isaiahgraham.leanrrr.data.AppStore
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.QuickLog
import com.isaiahgraham.leanrrr.data.SavedMeal
import com.isaiahgraham.leanrrr.data.mealLines
import com.isaiahgraham.leanrrr.data.number
import kotlin.math.max
import kotlin.math.roundToLong

// Store mutations for the Meal tab and My foods, and small model helpers from MealShare.swift and BarcodeProduct.swift.

/** Changes how many of one item the meal has. */
fun AppStore.setTrayQuantity(id: String, quantity: Double): Boolean {
    if (!quantity.isFinite() || quantity <= 0) return false
    return change { s -> s.copy(tray = s.tray.map { if (it.id == id) it.copy(quantity = quantity) else it }) }
}

fun AppStore.removeFromTray(id: String): Boolean = change(undo = "Removed from your meal") { s -> s.copy(tray = s.tray.filter { it.id != id }) }

fun AppStore.clearTray(): Boolean = change(undo = "Cleared your meal") { it.copy(tray = emptyList()) }

/** Keeps the meal being built as a saved meal. */
fun AppStore.saveMeal(name: String, items: List<Portion>): Boolean = change { s -> s.copy(meals = s.meals + SavedMeal(name = name, items = items)) }

fun AppStore.deleteMeal(id: String): Boolean = change(undo = "Deleted saved meal") { s -> s.copy(meals = s.meals.filter { it.id != id }) }

fun AppStore.deleteFood(food: Food): Boolean = change(undo = "Deleted ${food.name}") { s -> s.copy(foods = s.foods.filter { it.id != food.id }) }

/** "150 g" when the food is weighed, otherwise "2 × 1 wrap" (or just "1 wrap" for one). */
val Portion.amountText: String
    get() {
        food.servingWeight?.let { (grams, unit) -> return "${(grams * quantity).roundToLong().toDouble().number} $unit" }
        return if (quantity == 1.0) food.serve else "${quantity.number} × ${food.serve}"
    }

/** This recipe made with different ingredients, its figures worked out again from them. Everything else, the ID included, stays. */
fun Food.withIngredients(ingredients: List<Portion>): Food {
    val fresh = Nutrition(ingredients).food(name, max(recipeYield ?: 1.0, 0.001), ingredients)
    return copy(kj = fresh.kj, cal = fresh.cal, p = fresh.p, c = fresh.c, f = fresh.f, nut = fresh.nut, price = fresh.price, pf = fresh.pf,
        ingredients = ingredients)
}

/** A new recipe made of these foods, one serving, with any recipe among them broken into its ingredients. */
fun recipeDraft(name: String, items: List<Portion>): Food =
    Food(name = name, kj = 0.0, cal = 0.0, p = 0.0, ingredients = QuickLog.copies(mealLines(items)), recipeYield = 1.0)

/** Product barcode checks (BarcodeLookup.validatedCode / match in BarcodeProduct.swift). */
object BarcodeCheck {
    /** The barcode's digits when it's a valid 8, 12, 13 or 14 digit product code with a correct check digit, else null. */
    fun validated(input: String): String? {
        val code = input.filter { !it.isWhitespace() && it != '-' }
        if (code.length !in listOf(8, 12, 13, 14) || !code.all { it in '0'..'9' }) return null
        val digits = code.map { it - '0' }
        val sum = digits.dropLast(1).reversed().withIndex().sumOf { (i, d) -> d * (if (i % 2 == 0) 3 else 1) }
        if ((10 - sum % 10) % 10 != digits.last() || digits.toSet() == setOf(0)) return null
        return code
    }

    /** The first saved food with this barcode. Leading zeros are ignored, so a 12-digit UPC matches its 13-digit EAN. */
    fun match(code: String, foods: List<Food>): Food? {
        val key = code.trimStart('0')
        return foods.firstOrNull { food -> food.barcode?.trimStart('0') == key }
    }
}
