package com.isaiahgraham.leanrrr.scan

import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.LeanrJson
import com.isaiahgraham.leanrrr.data.MenuCatalog
import com.isaiahgraham.leanrrr.feature.scan.MealPhoto
import com.isaiahgraham.leanrrr.feature.scan.MenuCookbook
import com.isaiahgraham.leanrrr.feature.scan.MenuDish
import com.isaiahgraham.leanrrr.feature.scan.MenuEstimate
import com.isaiahgraham.leanrrr.feature.scan.MenuEstimator
import com.isaiahgraham.leanrrr.feature.scan.MenuLine
import com.isaiahgraham.leanrrr.feature.scan.MenuParser
import com.isaiahgraham.leanrrr.feature.scan.PhotoMemory
import com.isaiahgraham.leanrrr.feature.scan.PortionSize
import com.isaiahgraham.leanrrr.feature.scan.SeenFood
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import java.time.Instant
import kotlin.math.abs

/** Food data shared with iOS (ios/MacroMenu), read straight from the repo; the data-dependent tests skip without it. */
object TestFoods {
    private val dir = listOf(File("../../ios/MacroMenu"), File("../ios/MacroMenu"), File("ios/MacroMenu")).firstOrNull { File(it, "GenericFoods.json").exists() }
    val available: Boolean get() = dir != null
    val catalog: MenuCatalog by lazy { LeanrJson.decodeFromString(MenuCatalog.serializer(), File(dir, "MenuData.json").readText()) }
    val everyday: List<Food> by lazy { foods("GenericFoods.json") }
    val survey: List<Food> by lazy { foods("SurveyFoods.json") }
    private fun foods(name: String) = LeanrJson.decodeFromString<List<Food>>(File(dir, name).readText()).filter { it.isValid && it.isEveryday }
    /** Restaurant menu and everyday foods (iOS's `everydayStore.foods`). */
    val menuAndEveryday: List<Food> by lazy { catalog.foods + everyday }
    /** With the USDA survey foods too (the menu scanner's `store.foods`). */
    val all: List<Food> by lazy { catalog.foods + everyday + survey }
    val chainNames: Map<String, String> by lazy { catalog.chains.associate { it.id to it.name } }
    val photoNames: Map<String, String> by lazy { chainNames + (Food.EVERYDAY to "Everyday foods") }
}

/** MenuParser and MenuEstimator, with the expected results from ios/Tests/MenuScanChecks.swift. */
class MenuScanTest {
    private fun line(text: String, x: Double, y: Double, width: Double = 0.34, height: Double = 0.016) = MenuLine(text, x, y, width, height)

    @Test fun wordsOnALine() {
        assertEquals(28.5, MenuParser.splitPrice("Chicken Parma $28.50").price)
        assertEquals("Margherita", MenuParser.splitPrice("Margherita 22").words)
        assertEquals(12.0, MenuParser.splitPrice("House red 12 / 48").price)
        assertEquals(9.0, MenuParser.splitPrice("Chips ........ 9").price)
        assertEquals(24.0, MenuParser.splitPrice("Chicken parma S24").price)
        assertNull(MenuParser.splitPrice("Top 2").price)
        assertEquals(5.5, MenuParser.splitPrice("5-5").price); assertEquals(12.0, MenuParser.splitPrice("12-18").price)
        assertEquals("Margherita", MenuParser.clean("Margherita (V)"))
        assertEquals("Pad Thai", MenuParser.clean("Pad Thai GF, DF"))
        assertEquals("Mixed veg", MenuParser.clean("12. Mixed veg"))
        assertEquals("ROAST VEG", MenuParser.clean("ROAST VEG")); assertEquals("CHICKEN & VEG", MenuParser.clean("CHICKEN & VEG"))
        assertEquals("Mushroom Risotto", MenuParser.clean("Mushroom Risotto (VEG)")); assertEquals("Pad Thai", MenuParser.clean("Pad Thai GF, VEG"))
        // Text cut off by the page edge can be placed a little outside it.
        val cutOff = (0 until 8).map { line("Dish $it", if (it % 2 == 0) -0.03 else 0.55, it * 0.1, 0.3) }
        assertEquals(cutOff.size, MenuParser.columns(cutOff).flatten().size)
    }

    @Test fun twoColumnMenu() {
        val menu = MenuParser.read(listOf(
            line("THE CORNER HOTEL", 0.2, 0.04, 0.58, 0.05),
            line("Lunch & Dinner", 0.43, 0.1, 0.1, 0.012),
            line("ENTREES", 0.06, 0.14, 0.16, 0.024),
            line("Garlic Bread", 0.06, 0.18, 0.2), line("9", 0.44, 0.18, 0.02),
            line("Salt & Pepper Squid", 0.06, 0.21, 0.28), line("18", 0.43, 0.21, 0.03),
            line("lemon, aioli, rocket", 0.06, 0.232, 0.26, 0.012),
            line("MAINS", 0.06, 0.29, 0.12, 0.024),
            line("Chicken Parma", 0.06, 0.33, 0.22), line("28", 0.43, 0.33, 0.03),
            line("crumbed chicken, napoli, ham, mozzarella,", 0.06, 0.352, 0.36, 0.012),
            line("chips and salad", 0.06, 0.368, 0.2, 0.012),
            line("Add chicken 6", 0.06, 0.39, 0.18, 0.012),
            line("PIZZAS", 0.55, 0.14, 0.14, 0.024),
            line("The Hawaiian", 0.55, 0.18, 0.2), line("24", 0.92, 0.18, 0.03),
            line("ham, pineapple, mozzarella", 0.55, 0.202, 0.3, 0.012),
            line("Margherita (V)", 0.55, 0.24, 0.2), line("$22", 0.92, 0.24, 0.03),
            line("tomato, basil, fior di latte", 0.55, 0.262, 0.3, 0.012),
            line("DESSERTS", 0.55, 0.31, 0.16, 0.024),
            line("Tiramisu", 0.55, 0.35, 0.14), line("14", 0.92, 0.35, 0.03),
            line("15% surcharge on public holidays. Please tell us about allergies.", 0.33, 0.95, 0.38, 0.012),
            line("(03) 9555 0100  www.thecorner.com.au", 0.33, 0.97, 0.38, 0.012),
        ))
        assertEquals("The Corner Hotel", menu.restaurant)
        assertEquals(listOf("Garlic Bread", "Salt & Pepper Squid", "Chicken Parma", "The Hawaiian", "Margherita", "Tiramisu"), menu.dishes.map { it.name })
        assertEquals(listOf("Entrees", "Entrees", "Mains", "Pizzas", "Pizzas", "Desserts"), menu.dishes.map { it.section })
        assertEquals(28.0, menu.dishes[2].price)
        assertEquals("crumbed chicken, napoli, ham, mozzarella, chips and salad", menu.dishes[2].details)
        assertEquals("lemon, aioli, rocket", menu.dishes[1].details)
    }

    @Test fun oneColumnMenu() {
        val menu = MenuParser.read(listOf(
            line("Pumpkin Soup - roast pumpkin, cream, sourdough 16", 0.1, 0.1, 0.75),
            line("GRILLED BARRAMUNDI", 0.1, 0.14, 0.3),
            line("crushed potato, beans, lemon butter  36", 0.1, 0.16, 0.5, 0.012),
            line("Steak Frites", 0.1, 0.2, 0.2),
            line("300g scotch fillet, shoestring fries, cafe de paris butter", 0.1, 0.22, 0.6, 0.012),
            line("44", 0.8, 0.2, 0.03),
        ))
        assertEquals(listOf("Pumpkin Soup", "Grilled Barramundi", "Steak Frites"), menu.dishes.map { it.name })
        assertEquals(16.0, menu.dishes[0].price); assertEquals("roast pumpkin, cream, sourdough", menu.dishes[0].details)
        assertEquals(36.0, menu.dishes[1].price); assertEquals(44.0, menu.dishes[2].price)
    }

    @Test fun centredMenuIsOneColumn() {
        val centred = MenuParser.read((0 until 12).map { index ->
            val wide = index % 2 == 0
            line(if (wide) "Dish number $index with a long name 20" else "Short dish $index 18", if (wide) 0.2 else 0.35, 0.1 + index * 0.05, if (wide) 0.6 else 0.3)
        })
        assertEquals("Dish number 0 with a long name", centred.dishes.first().name)
        assertEquals(12, centred.dishes.size)
    }

    private val estimator by lazy { MenuEstimator(TestFoods.all, TestFoods.chainNames) }
    private fun estimate(name: String, details: String = "", section: String? = "Mains"): MenuEstimate =
        estimator.estimate(MenuDish(name = name, details = details, section = section)) ?: throw AssertionError("No estimate for $name")
    private fun calories(result: MenuEstimate) = result.total().cal
    private fun uses(result: MenuEstimate, food: String) = result.components.any { it.food.name == food }

    @Test fun cookbookUsesFoodsLeanrrrHas() {
        assumeTrue(TestFoods.available)
        for (name in MenuCookbook.foodNames) {
            val food = estimator.food(name) ?: throw AssertionError("MenuCookbook names a food Leanrrr doesn't have: $name")
            assertTrue("No weight for $name", (food.servingWeight?.first ?: 0.0) > 0)
        }
    }

    @Test fun wholeDishesLandWhereARestaurantServeDoes() {
        assumeTrue(TestFoods.available)
        for ((name, details, range) in listOf(
            Triple("Chicken Parma", "crumbed chicken, napoli, ham, mozzarella, chips and salad", 950.0..1500.0),
            Triple("Spaghetti Bolognese", "beef ragu, parmesan", 550.0..900.0), Triple("Fish and Chips", "beer battered flathead, tartare", 900.0..1500.0),
            Triple("Cheeseburger", "beef patty, cheddar, pickles, milk bun", 550.0..950.0), Triple("Butter Chicken", "basmati rice, naan", 750.0..1300.0),
            Triple("Margherita", "tomato, basil, fior di latte", 950.0..1400.0), Triple("Caesar Salad", "cos, bacon, egg, parmesan, croutons", 300.0..700.0),
            Triple("Flat White", "", 100.0..200.0), Triple("Pad Thai", "rice noodles, prawns, tamarind, peanuts", 500.0..900.0),
        )) {
            val cal = calories(estimate(name, details))
            assertTrue("$name: $cal Cal", cal in range)
        }
    }

    @Test fun ingredientsSwapAndCount() {
        assumeTrue(TestFoods.available)
        val chicken = estimate("Chicken Burger", "grilled chicken, slaw, aioli")
        assertTrue(uses(chicken, "Chicken thigh, cooked") && !uses(chicken, "Beef patty, 15% fat, cooked"))
        val either = estimate("Green Curry", "chicken or tofu, thai basil, jasmine rice")
        assertTrue(uses(either, "Chicken thigh, cooked") && !uses(either, "Tofu, firm"))
        // Words that only look like foods.
        val sauce = estimate("Grilled Barramundi", "fish sauce caramel, crushed potato, beans, lemon butter")
        assertTrue(uses(sauce, "White fish (cod), cooked") && uses(sauce, "Potato, baked"))
        assertFalse("egg noodles aren't eggs", uses(estimate("Stir Fried Egg Noodles", "bok choy, tofu"), "Egg, poached"))
        val leftOut = estimate("Chicken Salad", "tomato, cucumber, no onion, add bacon")
        assertTrue(!uses(leftOut, "Onion") && !uses(leftOut, "Bacon, cooked"))
        // Rice or noodles named on a dish made with them don't count twice, and a named side replaces the usual one.
        assertFalse(uses(estimate("Pad Thai", "rice noodles, prawns"), "Rice noodles, cooked"))
        assertFalse(uses(estimate("Spaghetti Bolognese", "spaghetti, beef ragu"), "Pasta, cooked"))
        assertFalse(uses(estimate("Egg Fried Rice", "egg, spring onion"), "White rice, cooked"))
        val mash = estimate("Chicken Parma", "with mash")
        assertTrue(uses(mash, "Mashed potato") && !uses(mash, "French fries, takeaway"))
        val hokkien = estimate("Beef Stir Fry", "hokkien noodles, bok choy")
        assertTrue(uses(hokkien, "Egg noodles, cooked") && !uses(hokkien, "White rice, cooked"))
    }

    @Test fun weightsSectionsAndSides() {
        assumeTrue(TestFoods.available)
        val steak = estimate("Steak Frites", "400g scotch fillet, shoestring fries")
        assertEquals(400.0, steak.components.first { it.food.name == "Top sirloin (rump) steak, cooked" }.grams ?: 0.0, 1.0)
        assertTrue(calories(estimate("Salt & Pepper Squid", section = "Entrees")) < calories(estimate("Salt & Pepper Squid", section = "Mains")) * 0.7)
        assertEquals(calories(estimate("Tiramisu", section = "Desserts")), calories(estimate("Tiramisu", section = "Entrees")), 1e-9)
        assertTrue(uses(estimate("Lamb Shank", "with naan"), "Naan"))
        val diavola = estimate("The Diavola", "napoli, salami, mozzarella", section = "Pizzas")
        assertTrue(uses(diavola, "Salami") && !uses(diavola, "Mozzarella") && !uses(diavola, "Pasta sauce"))
        val hawaiian = estimate("The Hawaiian", "ham, pineapple, mozzarella", section = "Pizzas")
        assertTrue(uses(hawaiian, "Cheese pizza, frozen") && uses(hawaiian, "Ham, lean"))
        assertTrue(uses(estimate("Barossa Valley 2021", section = "Wines"), "Red wine"))
    }

    @Test fun howSureAndNothingRatherThanAGuess() {
        assumeTrue(TestFoods.available)
        assertEquals(MenuEstimate.Basis.TYPICAL_DISH, estimate("Tiramisu", section = "Desserts").basis)
        assertEquals(MenuEstimate.Basis.INGREDIENTS, estimate("The Forager", "mushroom, spinach, poached egg, sourdough").basis)
        assertEquals(MenuEstimate.Basis.ROUGH, estimate("Barramundi", "", section = "Seafood").basis)
        assertNull(estimator.estimate(MenuDish(name = "Chef's Surprise", section = "Mains")))
    }

    @Test fun restaurantsOwnItemBeatsAnySum() {
        assumeTrue(TestFoods.available)
        TestFoods.all.firstOrNull { it.chain == "kfc" }?.let { kfc ->
            val result = estimator.estimate(MenuDish(name = kfc.name), chain = "kfc")
            assertEquals(kfc.name, MenuEstimate.Basis.OFFICIAL, result?.basis)
            assertEquals(kfc.id, result?.food(kfc.name)?.id)
        }
        assertEquals("kfc", estimator.chain("KFC"))
        for (name in listOf("The Corner Hotel", "Lygon St Trattoria", "Thai Orchid", "Chin Chin")) assertNull(name, estimator.chain(name))
    }

    @Test fun loggingSaysItsAnEstimate() {
        assumeTrue(TestFoods.available)
        var dish = estimate("Chicken Parma", "chips and salad")
        val whole = dish.food("Chicken Parma") ?: throw AssertionError("Nothing to log")
        assertTrue(whole.serve == "1 dish, estimated" && whole.chain == "mine" && whole.isValid && whole.cal % 10 == 0.0)
        dish = dish.copy(components = dish.components.mapIndexed { i, c -> if (i == 1) c.copy(isOn = false) else c })
        assertTrue((dish.food("Chicken Parma")?.cal ?: 0.0) < whole.cal)
        assertTrue(abs(dish.total(PortionSize.LARGE).cal - dish.total().cal * 1.5) < 0.01)
        dish = dish.copy(components = dish.components.map { it.copy(isOn = false) })
        assertNull(dish.food("Chicken Parma"))
    }
}

/** Matching what a photo or note names to Leanrrr's foods, and PhotoMemory (ios/Tests/AppChecks.swift). */
class PhotoMatchingTest {
    private fun item(name: String, others: List<String> = emptyList(), brand: String? = null, count: Int = 1) = SeenFood(name, others, brand, count)
    private fun seen(name: String, others: List<String> = emptyList(), brand: String? = null) =
        MealPhoto.matches(item(name, others, brand), TestFoods.menuAndEveryday, TestFoods.photoNames).map { it.name }
    private fun ticked(name: String, brand: String? = null): Food? {
        val it = item(name, brand = brand)
        return MealPhoto.preselected(MealPhoto.matches(it, TestFoods.menuAndEveryday, TestFoods.photoNames), it, TestFoods.photoNames)
    }

    @Test fun stems() {
        assertEquals(MealPhoto.stem("strawberries"), MealPhoto.stem("strawberry"))
        assertTrue(MealPhoto.stem("peas") != MealPhoto.stem("peach"))
    }

    @Test fun matchesExactlyEverydayFirst() {
        assumeTrue(TestFoods.available)
        assertEquals("Banana", seen("banana").first())
        assertTrue(seen("rice").take(2).all { it.endsWith("rice, cooked") })
        assertEquals("White rice, cooked", seen("rice").first()); assertEquals("Chicken breast, cooked", seen("chicken breast").first())
        assertEquals("Egg", seen("egg").first()); assertEquals("Potato, baked", seen("potato").first())
        assertEquals(listOf("Chicken drumstick, cooked"), seen("chicken leg", listOf("chicken drumstick")))
        assertTrue(seen("chair").isEmpty() && seen("bananna").isEmpty())
        assertEquals("Strawberries", seen("strawberry").first()); assertEquals("Egg", seen("eggs").first()); assertEquals("Tomato", seen("tomatoes").first())
    }

    @Test fun brandsAndTicking() {
        assumeTrue(TestFoods.available)
        val names = TestFoods.photoNames
        assertEquals("mcd", MealPhoto.chain("Macca's", names)); assertEquals("mcd", MealPhoto.chain("McDonald's", names))
        assertEquals("hj", MealPhoto.chain("Burger King", names)); assertEquals("gyg", MealPhoto.chain("Guzman y Gomez", names))
        assertNull(MealPhoto.chain("", names)); assertNull(MealPhoto.chain("Acme Burgers", names))
        assertTrue(ticked("banana")?.isEveryday == true)
        assertNull(ticked("Big Mac")); assertTrue(seen("Big Mac").isNotEmpty())
        assertEquals("Big Mac", ticked("Big Mac", brand = "McDonald's")?.name)
        assertEquals("Big Mac", seen("Big Mac", brand = "McDonald's").first())
        assertTrue(seen("fries", brand = "macca's").first().contains("Fries"))
        val untrusted = item("strawberry").copy(agreed = false)
        assertNull(MealPhoto.preselected(MealPhoto.matches(untrusted, TestFoods.menuAndEveryday, names), untrusted, names))
        // At a McDonald's, a Big Mac with no logo is ticked as McDonald's; a banana stays everyday.
        val bigMac = item("Big Mac")
        assertEquals("mcd", MealPhoto.preselected(MealPhoto.matches(bigMac, TestFoods.menuAndEveryday, names, nearby = "mcd"), bigMac, names, nearby = "mcd")?.chain)
        val banana = item("banana")
        val bananaPick = MealPhoto.preselected(MealPhoto.matches(banana, TestFoods.menuAndEveryday, names, nearby = "mcd"), banana, names, nearby = "mcd")
        assertTrue(bananaPick?.isEveryday == true)
        val maccas = TestFoods.menuAndEveryday.first { it.chain == "mcd" }
        assertTrue(PortionSize.applies(bananaPick!!) && !PortionSize.applies(maccas) && PortionSize.LARGE.factor > PortionSize.SMALL.factor)
    }

    @Test fun surveyFoodsRankAfterLeanrrrs() {
        assumeTrue(TestFoods.available)
        assertEquals("Garden salad, no dressing", MealPhoto.matches(item("salad"), TestFoods.all, TestFoods.photoNames).first().name)
        assertFalse(MealPhoto.matches(item("tofu"), TestFoods.all, TestFoods.photoNames).first().isSurvey)
    }

    @Test fun notesNameFoods() {
        val foods = com.isaiahgraham.leanrrr.feature.scan.NoteFoods.read("I had two eggs, toast and a flat white from Maccas for breakfast")
        assertEquals(listOf("eggs", "toast", "flat white"), foods.map { it.name })
        assertEquals(2, foods[0].count)
        assertTrue(foods.all { it.brand == "maccas" })
        val kept = com.isaiahgraham.leanrrr.feature.scan.NoteFoods.read("fish and chips with salad") { it == "fish and chips" }
        assertEquals(listOf("fish and chips", "salad"), kept.map { it.name })
    }

    @Test fun photoMemory() {
        val food = Food(id = "mcd:fries", chain = "mcd", name = "Fries (medium)", kj = 1400.0, cal = 335.0, p = 4.0)
        val fries = SeenFood(name = "Fries", count = 2)
        val remembered = PhotoMemory.remembering(listOf(PhotoMemory.Logged(fries, food, 3.0)), emptyMap())
        assertEquals(food.id, PhotoMemory.choice(item("fry"), remembered)?.foodID)
        assertEquals(1.5, PhotoMemory.choice(fries, remembered)?.perItem)
        assertNull(PhotoMemory.choice(item("chips"), remembered))
        val many = (0 until PhotoMemory.LIMIT).associate { "food $it" to PhotoMemory.Choice("x", 1.0, Instant.ofEpochSecond(it + 10L)) }
        val trimmed = PhotoMemory.remembering(listOf(PhotoMemory.Logged(fries, food, 3.0)), many)
        assertTrue(trimmed.size == PhotoMemory.LIMIT && trimmed["food 0"] == null && trimmed["fry"] != null)
    }
}
