package com.isaiahgraham.leanrrr.feature.today

import com.isaiahgraham.leanrrr.data.AppData
import com.isaiahgraham.leanrrr.data.AppStore
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.WaterLimits
import com.isaiahgraham.leanrrr.data.WaterSip
import com.isaiahgraham.leanrrr.data.dayKey
import com.isaiahgraham.leanrrr.data.hundredth
import com.isaiahgraham.leanrrr.data.isDayKey
import com.isaiahgraham.leanrrr.data.kgText
import com.isaiahgraham.leanrrr.data.number
import java.time.Instant
import java.time.LocalDate
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt

// Ports of Water.swift, WaterWeight.swift and the water/plan parts of AppStore.swift.

/** Water drunk each day, in millilitres, against a daily target. Kept apart from food so it never touches calories or macros. */
object Water {
    const val DEFAULT_TARGET = 2000.0
    const val DEFAULT_GLASS = 250.0
    val TARGET_RANGE = WaterLimits.TARGET_RANGE
    val GLASS_RANGE = WaterLimits.GLASS_RANGE
    /** The most one day can hold, so a slip of the finger can't leave an absurd total. */
    const val DAY_LIMIT = WaterLimits.DAY_LIMIT

    fun target(data: AppData): Double = data.waterTarget ?: DEFAULT_TARGET
    fun glass(data: AppData): Double = data.waterGlass ?: DEFAULT_GLASS
    fun total(data: AppData, day: String): Double = data.water?.get(day) ?: 0.0

    /**
     * Adds water to a day, or with a negative amount takes some off. A day never goes below nothing or above the limit,
     * and a day back at nothing is removed rather than kept as a zero.
     */
    fun adding(millilitres: Double, day: String, data: AppData): AppData {
        if (!millilitres.isFinite() || !isDayKey(day)) return data
        val updated = min(DAY_LIMIT, max(0.0, total(data, day) + millilitres))
        val water = (data.water ?: emptyMap()).toMutableMap()
        if (updated > 0) water[day] = updated else water.remove(day)
        return data.copy(water = water.ifEmpty { null })
    }

    /** "750 mL" or "1.25 L". */
    fun text(millilitres: Double): String =
        if (millilitres < 1000) "${millilitres.roundToInt()} mL" else "${(millilitres / 1000).kgText} L"

    /** How full the day is against the target, from 0 to 1. */
    fun progress(total: Double, target: Double): Double = if (target > 0) min(1.0, max(0.0, total / target)) else 0.0

    /** The quick amounts offered besides a glass. */
    val BOTTLE_SIZES = listOf(500.0, 750.0)

    /**
     * The four amounts shown as chips on Today: the glass, the usual bottles, then the last other amount added, or a litre
     * until there is one. Each appears once.
     */
    fun quickAmounts(glass: Double, recent: Double? = null): List<Double> {
        val amounts = mutableListOf(glass)
        for (size in BOTTLE_SIZES) if (size !in amounts) amounts += size
        for (size in listOfNotNull(recent, 1000.0)) if (size > 0 && size !in amounts && amounts.size < 4) amounts += size
        return amounts
    }

    /** The custom amount picker moves in steps of this many millilitres. */
    const val PICKER_STEP = 50.0
    val PICKER_RANGE = 50.0..2000.0

    /** The most one amount may add at once. */
    const val SINGLE_LIMIT = 5000.0

    /** "Logged 250 mL of water. 1.25 L of 2 L today." and, once the target is reached, "That's your 2 L target." */
    fun loggedAnswer(added: Double, total: Double, target: Double): String {
        var text = "Logged ${text(added)} of water. ${text(total)} of ${text(target)} today."
        if (total >= target && target > 0) text += " That’s your ${text(target)} target."
        return text
    }

    /** "You've had 1.25 L of water today, 750 mL to go." */
    fun todayAnswer(total: Double, target: Double): String {
        if (total <= 0) return "You haven’t logged any water today. Your target is ${text(target)}."
        if (total >= target) return "You’ve had ${text(total)} of water today, which reaches your ${text(target)} target."
        return "You’ve had ${text(total)} of water today, ${text(target - total)} to go."
    }
}

/**
 * How much of a weigh-in is water drunk in the hours before it, so a reading taken after a bottle of water isn't mistaken
 * for real weight gain.
 *
 * A rough model, not a measurement. A drink sits in the stomach and is absorbed over about half an hour. Once it's in the
 * blood, water beyond what you need is passed by the kidneys, with the excess halving about every 75 minutes. Meanwhile you
 * keep losing water through breath, sweat and a minimum of urine, so a drink after a few dry hours first makes up that
 * shortfall and only the rest is extra. The simulation starts at the first drink in the eight hours before the weigh-in,
 * taking you as normally hydrated then, and 1 mL of water weighs 1 g. Weighing first thing, before drinking, gives nothing
 * to take off, which is why morning weigh-ins are the most reliable.
 */
object WaterWeight {
    private const val ABSORB_HALF_LIFE = 0.25 * 3600
    private const val EXCRETE_HALF_LIFE = 1.25 * 3600
    /** Millilitres an hour lost whatever you drink. */
    private const val BASELINE_LOSS = 50.0
    /** Drinks further back than this have long been passed. */
    private const val WINDOW = 8L * 3600
    /** Simulation step, in seconds. */
    private const val STEP = 60L
    /** Below this many kilograms the estimate isn't worth showing or taking off. */
    const val SMALLEST = 0.05
    /** How long sips are kept, in seconds. */
    private const val KEEP = 48L * 3600

    /** Kilograms of a weigh-in at `time` estimated to be water drunk in the hours before and not yet passed. */
    fun kilograms(at: Instant, data: AppData): Double = kilograms(at, data.waterSips ?: emptyList())

    fun kilograms(at: Instant, sips: List<WaterSip>): Double {
        val start = at.minusSeconds(WINDOW)
        val recent = sips.filter { it.isValid && it.time > start && it.time <= at }.sortedBy { it.time }
        val first = recent.firstOrNull() ?: return 0.0
        val absorb = 1 - 0.5.pow(STEP / ABSORB_HALF_LIFE)
        val excrete = 1 - 0.5.pow(STEP / EXCRETE_HALF_LIFE)
        val loss = BASELINE_LOSS * STEP / 3600
        // Millilitres in the stomach, and millilitres above (or below, when negative) normal hydration in the body.
        var stomach = 0.0
        var body = 0.0
        var next = 0
        var now = first.time
        while (true) {
            while (next < recent.size && recent[next].time <= now) { stomach += recent[next].millilitres; next += 1 }
            if (now >= at) break
            val absorbed = stomach * absorb
            stomach -= absorbed
            body += absorbed - loss - max(0.0, body) * excrete
            now = minOf(at, now.plusSeconds(STEP))
        }
        val kg = max(0.0, stomach + body) / 1000
        return if (kg >= SMALLEST) kg.hundredth else 0.0
    }

    /** "About 0.4 kg of this is probably water from the 750 mL you had in the 2 hours before." */
    fun explanation(kg: Double, at: Instant, sips: List<WaterSip>): String {
        val recent = sips.filter { it.isValid && it.time <= at && it.time > at.minusSeconds(WINDOW) }
        val total = recent.sumOf { it.millilitres }
        val earliest = recent.minOfOrNull { it.time } ?: at
        val hours = max(1, ceil((at.epochSecond - earliest.epochSecond) / 3600.0).toInt())
        return "About ${kg.number} kg of this is probably water you haven’t passed yet, from the ${Water.text(total)} you logged " +
            "in the ${if (hours == 1) "hour" else "$hours hours"} before. Your trend uses ${kg.number} kg less. Weighing before you drink in the morning avoids this."
    }

    /**
     * Records water added to `day` (or taken off, when negative). Added water gets a sip only when the day is today, since a
     * time is only known for water logged as it's drunk; taking water off removes the latest sips that day first.
     */
    fun record(millilitres: Double, day: String, at: Instant, data: AppData): AppData {
        val sips = (data.waterSips ?: emptyList()).toMutableList()
        if (millilitres > 0) {
            if (dayKey(at) == day) sips += WaterSip(time = at, millilitres = millilitres)
        } else {
            var left = -millilitres
            for (i in sips.indices.reversed()) {
                if (left <= 0) break
                if (dayKey(sips[i].time) != day) continue
                val taken = min(left, sips[i].millilitres)
                sips[i] = sips[i].copy(millilitres = sips[i].millilitres - taken)
                left -= taken
            }
            sips.removeAll { it.millilitres <= 0 }
        }
        return tidy(data.copy(waterSips = sips), at)
    }

    /**
     * Drops sips older than two days, and the oldest sips of any day whose sips add up to more than its total
     * (after water was taken off on another device, say).
     */
    fun tidy(data: AppData, now: Instant = Instant.now()): AppData {
        val cutoff = now.minusSeconds(KEEP)
        val sips = (data.waterSips ?: emptyList()).filter { it.isValid && it.time > cutoff }.sortedBy { it.time }.toMutableList()
        val byDay = sips.indices.groupBy { dayKey(sips[it].time) }
        val drop = mutableSetOf<String>()
        for ((day, indices) in byDay) {
            var over = indices.sumOf { sips[it].millilitres } - Water.total(data, day)
            for (i in indices) {
                if (over <= 0) break
                val taken = min(over, sips[i].millilitres)
                sips[i] = sips[i].copy(millilitres = sips[i].millilitres - taken)
                over -= taken
                if (sips[i].millilitres <= 0) drop += sips[i].id
            }
        }
        val kept = sips.filter { it.id !in drop }
        return data.copy(waterSips = kept.ifEmpty { null })
    }
}

/** Adds water to a day (negative takes some off). With `undoable`, the toast offers Undo. */
fun AppStore.addWater(millilitres: Double, date: LocalDate = LocalDate.now(), at: Instant = Instant.now(), undoable: Boolean = false): Boolean {
    val key = dayKey(date)
    if (!millilitres.isFinite() || millilitres == 0.0 || abs(millilitres) > Water.DAY_LIMIT) return false
    val label = if (!undoable) null else if (millilitres > 0) "Added ${Water.text(millilitres)} of water" else "Took off ${Water.text(-millilitres)} of water"
    return change(undo = label) { state -> WaterWeight.record(millilitres, key, at, Water.adding(millilitres, key, state)) }
}

/** Saves the daily water target and glass size, each only if it's within range. */
fun AppStore.setWater(target: Double, glass: Double): Boolean {
    if (target !in Water.TARGET_RANGE || glass !in Water.GLASS_RANGE) return false
    return change { it.copy(waterTarget = target, waterGlass = glass) }
}

/** Adds a meal to a day's plan (Plan ahead, Premium). */
fun AppStore.plan(items: List<Portion>, name: String, mealTime: MealTime, date: LocalDate): Boolean =
    change { state -> MealPlan.add(items, name, mealTime, dayKey(date), MealPlan.pruned(state)) }

fun AppStore.removePlanned(id: String, date: LocalDate): Boolean =
    change(undo = "Removed from your plan") { MealPlan.remove(id, dayKey(date), it) }

/** Logs planned meals for a day: now if it's today, otherwise at midday that day. */
fun AppStore.logPlanned(ids: Set<String>, date: LocalDate): Boolean {
    val key = dayKey(date)
    val currentGoals = goals
    val time = if (date == LocalDate.now()) Instant.now() else date.atTime(12, 0).atZone(java.time.ZoneId.systemDefault()).toInstant()
    return change(undo = if (ids.size == 1) "Logged from your plan" else "Logged your plan") { MealPlan.log(ids, key, time, currentGoals, it) }
}
