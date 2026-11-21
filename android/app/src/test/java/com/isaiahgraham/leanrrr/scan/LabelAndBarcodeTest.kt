package com.isaiahgraham.leanrrr.scan

import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.LeanrJson
import com.isaiahgraham.leanrrr.data.MenuRegion
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.feature.scan.BarcodeLookup
import com.isaiahgraham.leanrrr.feature.scan.BarcodeLookupException
import com.isaiahgraham.leanrrr.feature.scan.BarcodeProduct
import com.isaiahgraham.leanrrr.feature.scan.LabelParser
import com.isaiahgraham.leanrrr.feature.scan.ProductSearch
import com.isaiahgraham.leanrrr.feature.scan.RecentBarcodes
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/** LabelParser and BarcodeLookup, with the expected results from ios/Tests/AppChecks.swift and BarcodeChecks.swift. */
class LabelAndBarcodeTest {
    private fun near(a: Double?, b: Double, tolerance: Double = 0.01) = assertTrue("$a ≠ $b", a != null && abs(a - b) < tolerance)

    @Test fun labelColumnsAndUnits() {
        val label = "Energy 840 kJ 1680 kJ\nProtein 10 g 20 g\nTotal Fat 5 g 10 g\nSaturated fat 1 g 2 g\nSodium 100 mg 200 mg\nSugars <1 g"
        val s = LabelParser.suggestions(label, 1)
        assertEquals(20.0, s["p"]); assertEquals(10.0, s["f"]); assertEquals(2.0, s["sat"]); assertEquals(200.0, s["sodium"]); assertNull(s["sugar"])
        near(s["cal"], 1680 / 4.184)
        val scan = LabelParser.suggestions("Energy (kJ) 1,200 2,400\nTotal carbohydrate 12g 4% 24g 8%\nDietary fibre 2g 4g\n– Saturated fat 1g 2g", 1)
        near(scan["cal"], 2400 / 4.184)
        assertEquals(24.0, scan["c"]); assertEquals(4.0, scan["fibre"]); assertEquals(2.0, scan["sat"])
    }

    @Test fun labelEnergy() {
        near(LabelParser.suggestions("Energy 836.8 kJ", 0)["cal"], 200.0)
        assertEquals(205.0, LabelParser.suggestions("Calories 205\nEnergy 836.8 kJ", 0)["cal"])
        assertEquals(205.0, LabelParser.suggestions("Energy 836.8 kJ\nCalories 205", 0)["cal"])
        near(LabelParser.suggestions("Kilojoules 836.8 1673.6", 1)["cal"], 400.0)
        near(LabelParser.suggestions("836.8 kJ 1673.6 kJ", 0)["cal"], 200.0)
        near(LabelParser.suggestions("Energy (kJ)\n836.8 1673.6", 1)["cal"], 400.0)
        near(LabelParser.suggestions("Energy 836.8 k J", 0)["cal"], 200.0)
    }

    @Test fun zeroReadAsLetterO() {
        // A zero read as the letter O still counts as a column, so the next value isn't taken for it.
        val misread = LabelParser.suggestions("Trans fat Og 0.1g\nProtein O.5g 2g\nSodium 5mg Omg", 0)
        assertEquals(0.0, misread["trans"]); assertEquals(0.5, misread["p"]); assertEquals(5.0, misread["sodium"])
        assertEquals(mapOf("sodium" to 0.0, "p" to 6.0), LabelParser.suggestions("Sodium 5mg Omg\nProtein 3 g 6 g", 1))
    }

    @Test fun perHundredConvertedToServing() {
        val converted = LabelParser.servingSuggestions("Serving size: 30g\nAvg qty per 100g\nEnergy 1500 kJ\nProtein 10g\nFat, total 20g", 0)
        assertEquals(3.0, converted["p"]!!, 1e-9); assertEquals(6.0, converted["f"]!!, 1e-9); near(converted["cal"], 450 / 4.184)
    }

    @Test fun labelLayouts() {
        val label = "Serving size: 1 bar (40 g)\nPer 100 g  Per serving\nEnergy 2092 kJ 836.8 kJ\nProtein 37.5 g 15 g\nSodium 250 mg 100 mg"
        val layout = LabelParser.layout(label)
        assertEquals(1, layout.servingColumn); assertEquals(0, layout.per100Column); assertEquals(40.0, layout.amount)
        near(LabelParser.servingSuggestions(label, 1)["cal"], 200.0, 0.001)
        near(LabelParser.servingSuggestions(label, 0)["cal"], 200.0, 0.001)
        assertEquals(100.0, LabelParser.servingSuggestions(label, 0)["sodium"]!!, 1e-9)
        val reversed = "Serving size 250 mL\nPer serving Per 100 mL\nEnergy 523 kJ 209.2 kJ\nProtein 7.5 g 3 g"
        assertEquals(0, LabelParser.layout(reversed).servingColumn)
        assertEquals("mL", LabelParser.layout(reversed).unit)
        near(LabelParser.servingSuggestions(reversed, 1)["cal"], 125.0, 0.001)
        val only100 = "Serving size:\n30g\nPer 100g\nEnergy 1673.6 kJ\nProtein 10g"
        assertNull(LabelParser.layout(only100).servingColumn)
        near(LabelParser.servingSuggestions(only100, 0)["cal"], 120.0, 0.001)
        assertNull(LabelParser.layout("Energy 500kJ").per100Column)
        assertNull(LabelParser.layout("Per 100g\nEnergy 500kJ").amount)
    }

    @Test fun barcodeChecksums() {
        assertEquals("3017620422003", BarcodeLookup.validatedCode("3017 6204 22003"))
        assertEquals("036000291452", BarcodeLookup.validatedCode("036000291452"))
        for (bad in listOf("3017620422004", "00000000", "abc3017620422003")) assertFalse(bad, BarcodeLookup.isValid(bad))
    }

    private fun parse(json: String) = BarcodeLookup.parse(json, "3017620422003")
    private fun fails(json: String) = runCatching { parse(json) }.exceptionOrNull() is BarcodeLookupException

    @Test fun openFoodFactsParsing() {
        val kj = parse("""{"status":1,"product":{"product_name":"Test food","nutriments":{"energy_100g":418.4,"proteins_100g":"8","carbohydrates_100g":20,"sodium_100g":0.12}}}""")
        assertTrue(kj.per100); near(kj.food.cal, 100.0, 0.001); assertEquals(8.0, kj.food.p, 0.0)
        assertNull(kj.food.f); assertEquals(120.0, kj.food.nut?.get("sodium")!!, 1e-9)
        val kcal = parse("""{"status":1,"product":{"product_name":"Drink","product_quantity_unit":"ml","nutriments":{"energy-kcal_100g":50,"energy_100g":999,"proteins_100g":0}}}""")
        assertEquals(50.0, kcal.food.cal, 0.0); assertEquals("mL", kcal.unit); assertEquals("100 mL", kcal.food.serve)
        val serving = parse("""{"status":1,"product":{"product_name":"Bar","serving_size":"1 bar (40 g)","nutriments":{"energy-kcal_serving":200,"proteins_serving":15,"fat_serving":7,"carbohydrates_100g":80}}}""")
        assertFalse(serving.per100); assertEquals(200.0, serving.food.cal, 0.0); assertNull(serving.food.c); assertEquals(7.0, serving.food.f!!, 0.0)
        assertTrue(serving.food.barcode != null)
        val both = parse("""{"status":1,"product":{"product_name":"Bar","serving_size":"1 bar (40 g)","nutriments":{"energy-kcal_serving":200,"proteins_serving":15,"energy-kcal_100g":500,"proteins_100g":37.5}}}""")
        assertFalse(both.per100); assertEquals(200.0, both.food.cal, 0.0); assertEquals(15.0, both.food.p, 0.0)
        val derived = parse("""{"status":1,"product":{"product_name":"Milk","serving_size":"1 glass (250 ml)","nutriments":{"energy_100g":209.2,"proteins_100g":3,"fat_100g":2,"sodium_100g":0.04}}}""")
        assertFalse(derived.per100); assertEquals("mL", derived.unit); near(derived.food.cal, 125.0, 0.001)
        assertEquals(7.5, derived.food.p, 1e-9); assertEquals(5.0, derived.food.f!!, 1e-9); assertEquals(100.0, derived.food.nut?.get("sodium")!!, 1e-9)
        val double = Nutrition(listOf(Portion(food = derived.food, quantity = 2.0)))
        near(double.cal, 250.0, 0.001); assertEquals(15.0, double.p, 1e-9); assertEquals(200.0, double.nut["sodium"]!!, 1e-9)
        assertTrue(fails("""{"status":0}"""))
        assertTrue(fails("""{"status":1,"product":{"product_name":"Missing protein","nutriments":{"energy-kcal_100g":200}}}"""))
        assertTrue(fails("""{"status":1,"product":{"product_name":"Mixed basis","nutriments":{"energy-kcal_100g":200,"proteins_serving":15}}}"""))
        assertTrue(fails("""{"status":1,"product":{"product_name":"Invalid","nutriments":{"energy-kcal_100g":-5,"proteins_100g":15}}}"""))
    }

    @Test fun recentScans() {
        val kj = parse("""{"status":1,"product":{"product_name":"Test food","nutriments":{"energy_100g":418.4,"proteins_100g":"8"}}}""")
        val saved = RecentBarcodes.recording(kj, "")
        val restored = RecentBarcodes.products(saved)
        assertEquals(1, restored.size); assertTrue(restored[0].per100); assertEquals(kj.food.cal, restored[0].food.cal, 0.0); assertEquals(kj.unit, restored[0].unit)
        assertEquals(1, RecentBarcodes.products(RecentBarcodes.recording(kj, saved)).size)
        assertTrue(RecentBarcodes.products("invalid").isEmpty())
        var history = saved
        for (index in 0 until 25) history = RecentBarcodes.recording(kj.copy(sourceURL = "https://world.openfoodfacts.org/product/$index"), history)
        assertEquals(10, RecentBarcodes.products(history).size)
        assertTrue(RecentBarcodes.products(history).first().sourceURL.endsWith("/24"))
    }

    @Test fun barcodesOnYourFoods() {
        var mine = Food(name = "Corner store wrap", kj = 1500.0, cal = 358.5, p = 20.0, barcode = "9300000000009")
        assertEquals("Corner store wrap", BarcodeLookup.match("9300000000009", listOf(mine))?.name)
        mine = mine.copy(barcode = "036000291452")
        assertTrue(BarcodeLookup.match("0036000291452", listOf(mine)) != null)
        assertNull(BarcodeLookup.match("9300000000009", listOf(mine)))
        assertEquals("036000291452", LeanrJson.decodeFromString(Food.serializer(), LeanrJson.encodeToString(Food.serializer(), mine)).barcode)
        // Leanrrr's supermarket foods are keyed by barcode, so they're found offline too.
        val shelf = Food(id = "coles:9310434006013", chain = "coles", name = "Snakes", kj = 349.0, cal = 83.0, p = 1.0)
        assertEquals(shelf.id, BarcodeLookup.matchAny("9310434006013", listOf(shelf))?.id)
        assertNull(BarcodeLookup.match("9310434006013", listOf(shelf)))
    }

    @Test fun productSearch() {
        assertEquals("tim tam dark or", ProductSearch.terms("  Tim Tam: \"dark\" OR * "))
        assertTrue(ProductSearch.terms("!!!").isEmpty())
        val url = ProductSearch.url("tim tam", "en:australia")
        assertTrue(url.startsWith("https://search.openfoodfacts.org/search?") && url.contains("en%3Aaustralia"))
        assertFalse(ProductSearch.url("tim tam", null).contains("australia"))
        assertTrue(ProductSearch.url("oreo", MenuRegion.UNITED_STATES.openFoodFactsCountry).contains("en%3Aunited-states"))
        val hits = ProductSearch.parse("""
            {"hits":[
              {"code":"9310072000817","product_name":"Tim Tam","brands":["Arnott's"],"quantity":"200 g","nutriments":{"energy-kj_100g":2180,"proteins_100g":4.4,"fat_100g":26}},
              {"code":"9310072000824","product_name":"Tim Tam","brands":["Arnott's"],"nutriments":{"energy-kj_100g":2180,"proteins_100g":4.4}},
              {"code":"9300000000001","product_name":"Protein milk","brands":"Brand","quantity":"1 L","nutriments":{"energy-kcal_100g":60,"proteins_100g":6}},
              {"code":"9300000000002","product_name":"No protein listed","nutriments":{"energy-kcal_100g":60}},
              {"code":"9300000000003","product_name":"Typo","nutriments":{"energy-kcal_100g":6000,"proteins_100g":6}},
              {"code":"abc","product_name":"Bad code","nutriments":{"energy-kcal_100g":60,"proteins_100g":6}},
              {"product_name":"No code","nutriments":{"energy-kcal_100g":60,"proteins_100g":6}}
            ]}
        """.trimIndent())
        assertEquals(listOf("9310072000817", "9300000000001"), hits.map { it.code })
        assertTrue(hits[0].product.per100); assertEquals("Tim Tam · Arnott's", hits[0].product.food.name); near(hits[0].product.food.cal, 521.0, 0.1)
        assertEquals("mL", hits[1].product.unit); assertEquals("100 mL", hits[1].product.food.serve); assertEquals("9300000000001", hits[1].product.food.barcode)
        assertTrue(runCatching { ProductSearch.parse("{}") }.isFailure)
    }

    @Suppress("unused") private fun typeCheck(p: BarcodeProduct) = p
}
