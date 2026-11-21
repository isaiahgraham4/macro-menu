package com.isaiahgraham.leanrrr.data

import java.util.Locale

/**
 * The country whose restaurant menus Leanrrr shows, chosen in setup and in Settings. Each has its own bundled menu file;
 * supermarket ready meals (Coles and Woolworths) and Copycat Kitchen exist only for Australia. A port of Region.swift.
 */
enum class MenuRegion(val raw: String, val title: String, val menuLabel: String, val chainPrefix: String, val openFoodFactsCountry: String) {
    AUSTRALIA("AU", "Australia", "Australian", "", "en:australia"),
    NEW_ZEALAND("NZ", "New Zealand", "New Zealand", "nz-", "en:new-zealand"),
    UNITED_STATES("US", "United States", "US", "us-", "en:united-states"),
    CANADA("CA", "Canada", "Canadian", "ca-", "en:canada"),
    UNITED_KINGDOM("GB", "United Kingdom", "UK", "uk-", "en:united-kingdom"),
    SOUTH_AFRICA("ZA", "South Africa", "South African", "za-", "en:south-africa"),
    INDIA("IN", "India", "Indian", "in-", "en:india");

    /** Bundled menu asset: MenuData.json for Australia, MenuData-US.json and so on for the rest. */
    val menuFile: String get() = if (this == AUSTRALIA) "MenuData.json" else "MenuData-$raw.json"
    val hasSupermarkets: Boolean get() = this == AUSTRALIA
    val supermarketFile: String? get() = if (hasSupermarkets) "SupermarketFoods.json" else null
    /** Copycat Kitchen compares home recipes with Australian menu items. */
    val hasCopycatKitchen: Boolean get() = this == AUSTRALIA
    /** The Play Store country chains' ordering apps are linked in. */
    val storeCountry: String get() = if (this == UNITED_KINGDOM) "gb" else raw.lowercase()

    val menuNote: String
        get() = when (this) {
            AUSTRALIA -> "Bundled Australian menu snapshot from 24 September 2026."
            UNITED_STATES -> "Bundled US menu snapshot from 12–14 November 2026, from each chain’s own published nutrition."
            NEW_ZEALAND, CANADA, UNITED_KINGDOM -> "Bundled $menuLabel menu snapshot from 14 November 2026, from each chain’s own published nutrition."
            SOUTH_AFRICA, INDIA -> "Bundled $menuLabel menu snapshot from 20 November 2026, from each chain’s own published nutrition."
        }

    /** The example under Find's Ask box. */
    val askExample: String
        get() = when (this) {
            AUSTRALIA -> "Ask Leanrrr: 40 g protein at Nando's"
            NEW_ZEALAND -> "Ask Leanrrr: 40 g protein at McDonald's"
            UNITED_STATES -> "Ask Leanrrr: 40 g protein at Chick-fil-A"
            CANADA -> "Ask Leanrrr: 40 g protein at Tim Hortons"
            UNITED_KINGDOM -> "Ask Leanrrr: 30 g protein at Greggs"
            SOUTH_AFRICA -> "Ask Leanrrr: 40 g protein at Nando's"
            INDIA -> "Ask Leanrrr: 30 g protein at KFC"
        }

    /** The three meals setup asks people to guess, with what the serve leaves out. */
    val quiz: List<Pair<String, String>>
        get() = when (this) {
            AUSTRALIA -> listOf("kfc:10-wicked-wings" to "10 wings · no sides or drink",
                "mcd:cheesy-double-quarter-pounder" to "Burger only · no sides or drink",
                "hj:triple-whopper-with-cheese" to "Burger only · no sides or drink")
            UNITED_STATES -> listOf("us-wendys:baconator" to "Burger only · no sides or drink",
                "us-mcd:double-quarter-pounder-with-cheese" to "Burger only · no sides or drink",
                "us-panda:the-original-orange-chicken" to "One entrée serve · no rice, noodles or drink")
            CANADA -> listOf("ca-bk:triple-whopper" to "Burger only · no sides or drink",
                "ca-mcd:poutine-large" to "Large poutine · no burger or drink",
                "ca-mcd:big-mac" to "Burger only · no sides or drink")
            UNITED_KINGDOM -> listOf("uk-mcd:double-quarter-pounder-with-cheese" to "Burger only · no sides or drink",
                "uk-greggs:steak-bake" to "One bake · no drink",
                "uk-mcd:chicken-selects-5-pc" to "5 pieces · no sauce, sides or drink")
            NEW_ZEALAND -> listOf("nz-mcd:double-quarter-pounder-w-cheese" to "Burger only · no sides or drink",
                "nz-dominos:mega-meatlovers-classic-crust-slice" to "One slice of a large classic crust",
                "nz-mcd:chicken-mcnuggets-20-pc" to "20 nuggets · no sauce, sides or drink")
            SOUTH_AFRICA -> listOf("za-nandos:1-2-chicken" to "Half chicken · no sides or drink",
                "za-mcd:mcfeast" to "Burger only · no sides or drink",
                "za-wimpy:mega-breakfast" to "As plated · no drink")
            INDIA -> listOf("in-mcd:veg-maharaja-mac" to "Burger only · no sides or drink",
                "in-kfc:hot-crispy-chicken-2-pc" to "2 pieces · no sides or drink",
                "in-pizzahut:margherita-pizza-medium-pan" to "A whole medium pan pizza, 6 slices")
        }

    companion object {
        const val KEY = "leanr.region"
        fun fromRaw(raw: String?): MenuRegion? = entries.firstOrNull { it.raw == raw }
        /** The country chosen, or Australia for anyone who set up before there was a choice. */
        val saved: MenuRegion get() = fromRaw(Prefs.string(KEY)) ?: AUSTRALIA
        /** What setup offers first: the phone's own region when it's one Leanrrr has menus for. */
        val suggested: MenuRegion
            get() = when (Locale.getDefault().country) {
                "US" -> UNITED_STATES; "NZ" -> NEW_ZEALAND; "CA" -> CANADA; "GB" -> UNITED_KINGDOM
                "ZA" -> SOUTH_AFRICA; "IN" -> INDIA; else -> AUSTRALIA
            }

        /** A chain id from the nickname tables (written with Australian ids) in the menu in use. Hungry Jack's is Burger King elsewhere. */
        fun chain(id: String, chainNames: Map<String, String>): String? {
            if (chainNames.containsKey(id)) return id
            val prefixes = entries.map { it.chainPrefix }.filter { it.isNotEmpty() }
            val bare = prefixes.fold(id) { acc, p -> if (acc.startsWith(p)) acc.drop(p.length) else acc }
            for (prefix in prefixes) {
                for (candidate in if (bare == "hj") listOf("hj", "bk") else listOf(bare)) {
                    if (chainNames.containsKey(prefix + candidate)) return prefix + candidate
                }
            }
            return null
        }
    }
}
