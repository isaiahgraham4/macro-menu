package com.isaiahgraham.leanrrr.find

import com.isaiahgraham.leanrrr.data.AppData
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.Goals
import com.isaiahgraham.leanrrr.data.LeanrJson
import com.isaiahgraham.leanrrr.data.LogEntry
import com.isaiahgraham.leanrrr.data.MenuCatalog
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.dayKey
import com.isaiahgraham.leanrrr.feature.find.AskLeanr
import com.isaiahgraham.leanrrr.feature.find.CopycatBook
import com.isaiahgraham.leanrrr.feature.find.DietFilter
import com.isaiahgraham.leanrrr.feature.find.DietGuess
import com.isaiahgraham.leanrrr.feature.find.DietOption
import com.isaiahgraham.leanrrr.feature.find.FindQuery
import com.isaiahgraham.leanrrr.feature.find.FoodSearch
import com.isaiahgraham.leanrrr.feature.find.MealFinder
import com.isaiahgraham.leanrrr.feature.find.MealMatch
import com.isaiahgraham.leanrrr.feature.find.MealSwaps
import com.isaiahgraham.leanrrr.feature.find.RecentSearches
import com.isaiahgraham.leanrrr.feature.find.Roulette
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.time.Instant
import kotlin.math.abs
import kotlin.math.roundToLong

/** The Find checks from ios/Tests/AppChecks.swift, run against the same bundled menu files. */
class FindChecksTest {
    companion object {
        private fun dataFile(name: String): File {
            var dir: File? = File("").absoluteFile
            while (dir != null) {
                val candidate = File(dir, "ios/MacroMenu/$name")
                if (candidate.exists()) return candidate
                dir = dir.parentFile
            }
            error("Couldn't find $name")
        }
        val catalog: MenuCatalog by lazy { LeanrJson.decodeFromString<MenuCatalog>(dataFile("MenuData.json").readText()) }
        val shops: MenuCatalog by lazy { LeanrJson.decodeFromString<MenuCatalog>(dataFile("SupermarketFoods.json").readText()) }
        val byID: Map<String, Food> by lazy { catalog.foods.associateBy { it.id } }
        val chainNames: Map<String, String> by lazy { catalog.chains.associate { it.id to it.name } }
    }

    @Test fun forgivingSearch() {
        assertNotNull(FoodSearch.score("McChicken", "mchicken"))
        assertEquals(0, FoodSearch.score("McChicken", "mc chicken"))
        assertNotNull(FoodSearch.score("Chicken Nuggets 10 pack", "nugets"))
        assertNull(FoodSearch.score("Big Mac", "whopper"))
        assertEquals(0, FoodSearch.score("Hungry Jack’s Whopper", "hungry jacks"))
        assertNull(FoodSearch.score("Fries", "frz"))
        assertEquals(listOf("Double McChicken", "McChicken"), FoodSearch.filter(listOf("Double McChicken", "McChicken", "Big Mac"), "mcchicken") { it })
        assertEquals(listOf("McChicken"), FoodSearch.filter(listOf("Big Mac", "McChicken"), "mchiken") { it })
        assertNull(FoodSearch.score("Chicken McWings 3 pc", "mchiken"))
        assertEquals(listOf("Wrap", "fries"), RecentSearches.list(RecentSearches.adding("Wrap", RecentSearches.adding("wrap", "fries"))))
    }

    @Test fun communityFoodsComeAfterPublishedOnes() {
        val shared = Food(id = "community:food-x", chain = Food.COMMUNITY, name = "Chicken wrap", kj = 1500.0, cal = 358.0, p = 30.0)
        val official = Food(id = "kfc:wrap", chain = "kfc", name = "Chicken wrap", kj = 1500.0, cal = 358.0, p = 30.0)
        val names = mapOf("kfc" to "KFC", Food.COMMUNITY to "Community")
        assertEquals(listOf("kfc:wrap", "community:food-x"), FoodSearch.browse(listOf(shared, official), names, FoodSearch.Browse(search = "chicken wrap")).map { it.id })
        assertEquals(listOf("community:food-x"), FoodSearch.browse(listOf(shared, official), names, FoodSearch.Browse(search = "community")).map { it.id })
    }

    @Test fun finderBuildsOrdersFromOneRestaurant() {
        val query = FindQuery(calories = 700.0, protein = 35.0, maxItems = 3)
        val matches = MealFinder.find(catalog.foods, query)
        assertTrue(matches.isNotEmpty())
        for (match in matches) {
            assertTrue(match.items.size <= 3 && match.total.cal <= 700)
            assertEquals(1, match.items.map { it.food.chain }.toSet().size)
        }
        assertTrue(MealFinder.find(catalog.foods, query.copy(chains = setOf("spud"), carbs = 100.0)).isEmpty())
        val tiny = listOf(
            Food(id = "main", chain = "test", name = "Main", kj = 800.0, cal = 200.0, p = 20.0, c = 10.0, f = 5.0, price = 5.0),
            Food(id = "side", chain = "test", name = "Side", cat = "side", kj = 400.0, cal = 100.0, p = 5.0, c = 10.0, f = 3.0, price = 2.0),
        )
        val simple = MealFinder.find(tiny, FindQuery(calories = 300.0, protein = 25.0, maxItems = 2))
        assertEquals(300.0, simple.first().total.cal, 0.0)
        assertEquals(25.0, simple.first().total.p, 0.0)
        assertTrue(MealFinder.variants(tiny[0]).isEmpty())
        // A juice bar has no mains, so its drinks are the order.
        val juice = MealFinder.find(catalog.foods, FindQuery(chains = setOf("boost"), calories = 700.0, protein = 25.0, maxItems = 1))
        assertTrue(juice.isNotEmpty() && juice.all { it.chain == "boost" && it.total.cal <= 700 } && juice[0].total.p >= 20)
        val schnitz = MealFinder.find(catalog.foods, FindQuery(chains = setOf("schnitz"), calories = 900.0, protein = 45.0, maxItems = 2))
        assertTrue(schnitz.isNotEmpty() && schnitz.all { m -> m.items.all { it.food.chain == "schnitz" } && m.total.cal <= 900 })
        val burrito = MealFinder.find(catalog.foods, FindQuery(chains = setOf("zam"), calories = 900.0, protein = 40.0, maxItems = 2))
        assertTrue(burrito.isNotEmpty() && burrito.all { it.items[0].food.cat == "main" })
    }

    @Test fun customisedOrders() {
        val bigMac = byID.getValue("mcd:big-mac")
        val custom = MealFinder.variants(bigMac)
        val changes = custom.map { it.name.replace("Big Mac · ", "") }
        assertTrue(changes.toString(), "No Big Mac Sauce" in changes && "Extra Beef Patty" in changes && "No Big Mac Sauce, Extra Beef Patty" in changes)
        assertFalse(changes.any { it.contains("Bun") || it.contains("No Beef") || it.contains("Lettuce") || it.contains("Pickles") })
        assertTrue(custom.all { MealFinder.isVariant(it) && MealFinder.baseID(it) == "mcd:big-mac" && it.modifiers == null && it.isValid })
        val noSauce = custom.first { it.name == "Big Mac · No Big Mac Sauce" }
        assertTrue(abs(noSauce.kj - (bigMac.kj - 376)) < 0.01)
        assertEquals(((bigMac.kj - 376) / 4.184).roundToLong().toDouble(), noSauce.cal, 0.0)
        assertEquals("Based on Big Mac. No Big Mac Sauce", noSauce.note)
        assertEquals(custom.size, custom.map { it.id }.toSet().size)
        for (id in listOf("mcd:cheeseburger", "mcd:bacon-egg-mcmuffin")) {
            val item = byID[id] ?: continue
            val names = MealFinder.variants(item).map { it.name }
            assertFalse(names.toString(), names.any { (it.contains("No Cheese") && id.contains("cheese")) || (it.contains("No Bacon") && id.contains("bacon")) })
        }
        // A Big Mac is 621 Cal; without its sauce it fits a 540 Cal limit, and the finder suggests that.
        val bigMacQuery = FindQuery(chains = setOf("mcd"), calories = 540.0, protein = 25.0, maxItems = 1)
        assertEquals(listOf(noSauce.id), MealFinder.find(listOf(bigMac), bigMacQuery).first().items.map { it.food.id })
        assertTrue(MealFinder.find(listOf(bigMac), bigMacQuery.copy(customise = false)).isEmpty())
        // An order that already fits comes first as it's sold; with more room, another patty adds protein.
        assertEquals(bigMac.id, MealFinder.find(listOf(bigMac), FindQuery(chains = setOf("mcd"), calories = 650.0, protein = 20.0, maxItems = 1)).first().items[0].food.id)
        assertEquals("Big Mac · Extra Beef Patty", MealFinder.find(listOf(bigMac), FindQuery(chains = setOf("mcd"), calories = 800.0, protein = 38.0, maxItems = 1)).first().items[0].food.name)
    }

    @Test fun supermarkets() {
        val meals = MealFinder.find(shops.foods, FindQuery(chains = setOf("woolworths"), calories = 600.0, protein = 30.0, supermarket = true))
        assertTrue(meals.isNotEmpty() && meals.all { it.chain == "woolworths" && it.total.cal <= 600 })
        val snacks = MealFinder.find(shops.foods, FindQuery(calories = 200.0, protein = 15.0, maxItems = 1, supermarket = true))
        assertTrue(snacks.all { it.items.size == 1 } && snacks.any { it.items[0].food.cat == "snack" })
        assertTrue(MealFinder.find(shops.foods, FindQuery(calories = 600.0, protein = 30.0, supermarket = true, diet = DietFilter(setOf(DietOption.PEANUT)))).isEmpty())
        val names = mapOf("woolworths" to "Woolworths", "coles" to "Coles", "kfc" to "KFC")
        val asked = AskLeanr.parse("40 g protein at woolies", names, FindQuery())
        assertTrue(asked.query.chains == setOf("woolworths") && asked.query.usesSupermarkets)
        val general = AskLeanr.parse("ready meal under 500 calories", names, FindQuery())
        assertTrue(general.query.chains.isEmpty() && general.query.usesSupermarkets && "Coles and Woolworths" in general.understood)
        assertFalse(AskLeanr.parse("40 g protein at KFC", names, FindQuery()).query.usesSupermarkets)
        assertEquals(setOf("kfc"), AskLeanr.parse("coleslaw at KFC under 300 calories", names, FindQuery()).query.chains)
        assertEquals(setOf("kfc"), AskLeanr.parse("40 g protein at KFC's", names, FindQuery()).query.chains)
        assertEquals(setOf("coles"), AskLeanr.parse("coles chicken", names, FindQuery()).query.chains)
    }

    @Test fun dietaryNeeds() {
        val vegetarian = DietFilter(setOf(DietOption.VEGETARIAN)); val noPork = DietFilter(setOf(DietOption.NO_PORK)); val noBeef = DietFilter(setOf(DietOption.NO_BEEF))
        val whopper = byID.getValue("hj:whopper")
        assertTrue(whopper.diet?.meat == listOf("beef") && !vegetarian.allows(whopper) && noPork.allows(whopper))
        assertTrue(vegetarian.allows(byID.getValue("hj:plant-based-whopper")) && vegetarian.allows(byID.getValue("grilld:garden-goodness")))
        assertTrue(!noPork.allows(byID.getValue("dominos:hawaiian-1-slice-")) && !noBeef.allows(byID.getValue("dominos:pepperoni-1-slice-")))
        val glutenFree = DietFilter(setOf(DietOption.GLUTEN))
        assertTrue(!glutenFree.allows(byID.getValue("grilld:simply-grill-d")) && !glutenFree.allows(byID.getValue("mcd:big-mac")))
        assertTrue(glutenFree.allows(byID.getValue("nandos:1-2-peri-peri-chicken")))
        assertEquals(setOf(DietOption.WHEAT, DietOption.LUPIN, DietOption.SULPHITES), DietFilter.fromRaw("wheat,lupin,sulphites").options)
        assertTrue(vegetarian.allows(byID.getValue("kfc:coleslaw-regular-")))
        assertTrue(DietFilter(setOf(DietOption.VEGAN, DietOption.GLUTEN)).allows(Food(chain = "mine", name = "My chicken wrap", kj = 1000.0, cal = 239.0, p = 20.0)))
        // Names of everyday foods.
        assertEquals(listOf("sulphites"), DietGuess.guess("Sultanas").al)
        assertEquals(listOf("chicken"), DietGuess.guess("Chicken breast, cooked").meat)
        assertTrue(DietGuess.guess("Banana").isVegan && DietGuess.guess("Banana").al == emptyList<String>())
        assertEquals(emptyList<String>(), DietGuess.guess("Sirloin steak, lean, raw").al)
        assertNull(DietGuess.guess("Hash browns").al)
        assertNull(DietGuess.guess("Pesto").al)
        assertFalse(glutenFree.allows(Food(chain = Food.EVERYDAY, name = "Falafel", kj = 950.0, cal = 227.0, p = 6.0)))
        assertTrue(glutenFree.allows(Food(chain = Food.EVERYDAY, name = "Banana", kj = 438.0, cal = 105.0, p = 1.3)))
        assertFalse(DietGuess.guess("Spaghetti with meat sauce").isVegetarian)
        // An old menu that names the nut is left out rather than trusted.
        val cookie = Food(chain = "sub", name = "Old cookie", kj = 900.0, cal = 215.0, p = 3.0,
            diet = com.isaiahgraham.leanrrr.data.DietInfo(meat = emptyList(), al = listOf("egg", "macadamia"), vg = "vegetarian", src = "guide"))
        assertFalse(DietFilter(setOf(DietOption.TREENUT)).allows(cookie))
        assertFalse(DietFilter(setOf(DietOption.MILK)).allows(cookie))
        // With needs set, the finder only orders items that fit.
        val vegOrders = MealFinder.find(catalog.foods, FindQuery(calories = 900.0, protein = 25.0, maxItems = 2, diet = vegetarian))
        assertTrue(vegOrders.isNotEmpty() && vegOrders.all { m -> m.items.all { it.food.diet?.meat == emptyList<String>() } })
    }

    @Test fun askLeanrrrRules() {
        val asked = AskLeanr.parse("40 g protein under 600 Cal at Nando's", chainNames, FindQuery())
        assertTrue(asked.query.protein == 40.0 && asked.query.calories == 600.0 && asked.query.chains == setOf("nandos") && asked.query.diet.isEmpty)
        val veggie = AskLeanr.parse("vegetarian, gluten free dinner from maccas or hungry jacks under 2500 kJ, one item", chainNames, FindQuery())
        assertEquals(setOf(DietOption.VEGETARIAN, DietOption.GLUTEN), veggie.query.diet.options)
        assertEquals(setOf("mcd", "hj"), veggie.query.chains)
        assertEquals(598.0, veggie.query.calories, 0.0)
        assertEquals(1, veggie.query.maxItems)
        val halal = AskLeanr.parse("halal high protein lunch at KFC with a side", chainNames, FindQuery(calories = 700.0, protein = 40.0))
        assertTrue(halal.query.diet.options == setOf(DietOption.NO_PORK) && halal.query.sort == "protein" && halal.query.chains == setOf("kfc") && halal.query.maxItems == 2)
        assertTrue(halal.understood.last() == "Halal isn't checked, only no pork" && halal.query.calories == 700.0)
        val left = AskLeanr.parse("what's left today at grill'd, no beef, under 30g carbs", chainNames, FindQuery())
        assertTrue(left.usesRemaining && left.query.chains == setOf("grilld") && left.query.diet.options == setOf(DietOption.NO_BEEF) && left.query.carbs == 30.0)
        assertEquals(700.0, AskLeanr.parse("under 700 at guzman", chainNames, FindQuery()).query.calories, 0.0)
    }

    @Test fun takeawayRoulette() {
        val tonight = FindQuery(calories = 750.0, protein = 40.0, carbs = 90.0, customise = false)
        val wheel = Roulette.slices(catalog.foods, tonight)
        assertTrue(wheel.size >= 8 && wheel.none { it.chain in Roulette.notDinner || it.chain == "mine" })
        for (order in wheel.flatMap { it.orders }) {
            assertTrue(order.total.cal <= 750 && order.total.cal >= 375 && order.total.p >= 40 && order.total.c <= 90 && !order.total.missingCarbs)
            assertTrue(order.items.all { it.food.cat in listOf("main", "side") && !MealFinder.isVariant(it.food) })
            assertTrue(order.items.size <= 2 && order.items.none { it.food.name.contains("Kids") || it.food.name.contains("Hash Brown") })
            assertTrue(order.items[0].food.id != order.items.last().food.id || order.items.size == 1 || order.items[0].food.cal <= Roulette.LARGEST_DOUBLED)
        }
        assertTrue(Roulette.slices(catalog.foods, tonight.copy(calories = 0.0)).isEmpty())
        // Every restaurant gets the same chance, and the last one doesn't come up twice running.
        val landed = HashMap<String, Int>()
        var previous: MealMatch? = null
        repeat(2000) {
            val (slice, order) = Roulette.spin(wheel, previous)!!
            assertTrue(order.chain == wheel[slice].chain && order.chain != previous?.chain)
            landed[order.chain] = (landed[order.chain] ?: 0) + 1
            previous = order
        }
        assertTrue(landed.size == wheel.size && landed.values.all { it > 2000 / wheel.size / 2 })
        assertNull(Roulette.spin(emptyList(), null))
        val every = listOf("kfc", "mcd", "nandos")
        assertEquals(setOf("kfc", "mcd"), Roulette.onWheel(every, emptySet(), setOf("nandos")))
        assertEquals(setOf("nandos"), Roulette.onWheel(every, setOf("nandos"), setOf("nandos")))
        assertEquals(every.toSet(), Roulette.onWheel(every, setOf("gone"), emptySet()))
        val lone = listOf(Roulette.Slice(wheel[0].chain, listOf(wheel[0].orders[0])))
        assertEquals(wheel[0].orders[0].id, Roulette.spin(lone, wheel[0].orders[0])?.second?.id)
        for (count in listOf(1, 2, 7, 18)) for (slice in 0 until count) for (offset in listOf(-0.35, 0.0, 0.35)) {
            val start = (slice * 47 + count).toDouble()
            val stop = Roulette.landing(start, slice, count, 6, offset)
            assertTrue(stop >= start + 6 * 360 && stop < start + 7 * 360 && Roulette.sliceAt(stop, count) == slice)
        }
        // Limits come from what's left today, capped at one and a half typical meals.
        val goals = Goals(values = mapOf("cal" to 2000.0, "p" to 150.0, "c" to 200.0, "f" to 60.0, "fibre" to 30.0))
        val time = Instant.ofEpochSecond(1_780_000_000)
        val spent = Food(id = "spent", chain = "mine", name = "Lunch", cat = "main", kj = 5230.0, cal = 1250.0, p = 120.0, c = 150.0, f = 45.0)
        var day = AppData(goalSets = listOf(goals), logs = mapOf(dayKey(time) to listOf(LogEntry(name = "Lunch", items = listOf(Portion(food = spent)), time = time))))
        val limits = Roulette.limits(day, goals, now = time)!!
        assertTrue(limits.toString(), limits.calories == 750.0 && limits.protein == 30.0 && limits.carbs == 50.0 && limits.fat == 15.0 && !limits.customise)
        day = day.copy(logs = mapOf(dayKey(time) to listOf(LogEntry(name = "Lunch", items = listOf(Portion(food = spent.copy(cal = 1950.0))), time = time))))
        assertNull(Roulette.limits(day, goals, now = time))
    }

    @Test fun mealSwaps() {
        val original = Food(id = "original", chain = "kfc", name = "Burger", kj = 2500.0, cal = 600.0, p = 30.0)
        val retained = Food(id = "retained", chain = "kfc", name = "Alternative", kj = 2000.0, cal = 480.0, p = 26.0)
        val foods = listOf(original, retained.copy(id = "low", cal = 300.0, p = 10.0), retained.copy(id = "other", chain = "mcd"),
            retained.copy(id = "side", cat = "side"), retained.copy(id = "invalid", cal = Double.NaN), retained)
        assertEquals(listOf("retained", "low"), MealSwaps.options(Portion(food = original, quantity = 2.0), foods).map { it.id })
        assertTrue(MealSwaps.options(Portion(food = original, quantity = 0.0), foods).isEmpty())
        assertTrue(MealSwaps.options(Portion(food = original, quantity = 0.01), foods).isEmpty())
    }

    @Test fun copycatKitchen() {
        val book = LeanrJson.decodeFromString<CopycatBook>(dataFile("CopycatKitchen.json").readText())
        assertTrue(book.recipes.isNotEmpty())
        val items = book.comparisons(catalog.foods)
        assertTrue(items.isNotEmpty())
        for (item in items) {
            val food = book.food(item.recipe, shopName = item.shopName)
            assertTrue(food.isValid && food.id == "copycat:${item.recipe.id}" && food.ingredients!!.isNotEmpty())
            assertTrue(item.lean.cal <= item.home.cal + 0.001)
        }
    }
}
