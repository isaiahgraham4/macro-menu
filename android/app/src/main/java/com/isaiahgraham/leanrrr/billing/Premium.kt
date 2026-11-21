package com.isaiahgraham.leanrrr.billing

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.isaiahgraham.leanrrr.BuildConfig
import com.isaiahgraham.leanrrr.data.LeanrJson
import com.isaiahgraham.leanrrr.data.Prefs
import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Even Leanrrr (called Premium in code): custom app colours, colour packs, background tints and icons, separate macro colours,
 * the Calories & macros and All targets widgets, choosing which meal reminders you get, menu scan and Plan ahead.
 * Locked users fall back to the defaults; nothing they've logged is affected. Observable, so screens redraw when it changes.
 */
object Premium {
    /** While false nothing is locked, the Even Leanrrr screens are hidden and Google Play is never contacted. */
    const val SUBSCRIPTIONS_ENABLED = true
    /** Set by [Purchases] from Google Play (or the remembered entitlement until Play answers). */
    var unlockedState by mutableStateOf(false)
    /** Debug builds only: the "Force Even Leanrrr on" switch in Settings, for testing the unlocked screens without buying. */
    var forcedState by mutableStateOf(false)
    val isUnlocked: Boolean get() = !SUBSCRIPTIONS_ENABLED || unlockedState || (BuildConfig.DEBUG && forcedState)

    const val FORCE_KEY = "debug.forcePremium"
}

/**
 * The rules for who has Even Leanrrr, kept free of Play Billing so they can be checked on their own (PremiumAccess.swift).
 * The product IDs must match the products created in Google Play Console.
 */
object PremiumAccess {
    const val YEARLY = "premium_yearly"
    const val MONTHLY = "premium_monthly"
    const val WEEKLY = "premium_weekly"
    /** A one-off purchase that never ends. Also given away free with Google Play promo codes. */
    const val LIFETIME = "premium_lifetime"
    /** The auto-renewing plans, longest first, so it's listed first on the Even Leanrrr screen. */
    val subscriptionIDs = listOf(YEARLY, MONTHLY, WEEKLY)
    /** Everything that gives Premium. */
    val productIDs = subscriptionIDs + LIFETIME

    /**
     * A paid-up purchase as of the last time Google Play was asked, remembered so Premium doesn't flicker off at launch or
     * offline while Play is still answering. Play doesn't tell apps when a subscription period ends, so `expires` is usually
     * null and `checked` (when Play last confirmed it) decides how long it's believed.
     */
    @Serializable
    data class Entitlement(
        val productID: String,
        val expires: Long? = null,
        val renews: Boolean? = null,
        val trial: Boolean? = null,
        val checked: Long? = null,
    )

    /** How long a remembered subscription is still believed while Google Play can't be reached. */
    const val REMEMBERED_GRACE: Long = 7L * 24 * 3600

    fun isRemembered(entitlement: Entitlement?, now: Instant = Instant.now()): Boolean {
        if (entitlement == null || entitlement.productID !in productIDs) return false
        if (entitlement.productID == LIFETIME) return true
        entitlement.expires?.let { return it + REMEMBERED_GRACE > now.epochSecond }
        val checked = entitlement.checked ?: return false
        return checked + REMEMBERED_GRACE > now.epochSecond
    }

    /** The entitlement that lasts longest when more than one is active: a lifetime first, then a yearly, monthly, weekly. */
    fun best(entitlements: List<Entitlement>): Entitlement? = entitlements.minByOrNull { productIDs.indexOf(it.productID).let { i -> if (it.productID == LIFETIME) -1 else i } }

    const val CACHE_KEY = "leanr.premium.entitlement"

    fun load(): Entitlement? = Prefs.string(CACHE_KEY)?.let { runCatching { LeanrJson.decodeFromString<Entitlement>(it) }.getOrNull() }

    fun save(entitlement: Entitlement?) {
        if (entitlement == null) Prefs.remove(CACHE_KEY) else Prefs.set(CACHE_KEY, LeanrJson.encodeToString(Entitlement.serializer(), entitlement))
    }

    private val dateFormat = DateTimeFormatter.ofPattern("d MMM yyyy", Locale.forLanguageTag("en-AU"))

    /** "Lifetime", "Renews automatically" or "Ends 3 Nov 2026" for the Even Leanrrr row in Settings. */
    fun statusText(entitlement: Entitlement?): String {
        if (entitlement?.productID == LIFETIME) return "Lifetime"
        if (entitlement == null) return "Active"
        val expires = entitlement.expires?.let { Instant.ofEpochSecond(it).atZone(ZoneId.systemDefault()).format(dateFormat) }
        if (expires != null) return if (entitlement.renews != false) "Renews $expires" else "Ends $expires"
        return when (entitlement.renews) {
            true -> "Renews automatically"
            false -> "Ends when this period does"
            null -> "Active"
        }
    }
}

/** What Premium includes. Kept in one place so the paywall and the locked screens say the same thing. */
object PremiumFeatures {
    data class Feature(val key: String, val title: String, val detail: String)

    val all = listOf(
        Feature("menu", "Scan a menu", "Photograph any menu and see estimated calories and macros for each dish, then log it."),
        Feature("plan", "Plan ahead", "Plan tomorrow's meals now and tick them off with one tap when you eat them."),
        Feature("colours", "App colours", "Pick a preset or any colour you like for buttons, tabs and progress bars."),
        Feature("packs", "Colour packs", "Matching sets of app icon, app colour, macro colours and background tint, from Warm to Ocean."),
        Feature("icons", "App icons", "More icon packs for your Home screen."),
        Feature("macros", "Macro colours", "Pick any colour for protein, carbs and fat, in the app and widgets."),
        Feature("widgets", "Two more widgets", "Calories & macros, and All targets."),
        Feature("reminders", "Meal and water reminders", "Choose which meals remind you, and when, pick when your weekly review arrives, and get nudged to drink water."),
    )
}
