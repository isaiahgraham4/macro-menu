package com.isaiahgraham.leanrrr.feature.progress

import com.isaiahgraham.leanrrr.data.AppData
import com.isaiahgraham.leanrrr.data.Goals
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.dayKey
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.data.parseDayKey
import com.isaiahgraham.leanrrr.data.tenth
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max

// Ports of WeeklyReview.swift, YearReview.swift, ProgressBreakdown.swift, Insights.swift (as used by Progress) and
// TrackingStreak from WidgetCalories.swift.

private val shortDayFormat = DateTimeFormatter.ofPattern("d MMM")
/** "14 Oct". */
fun shortDay(date: LocalDate): String = date.format(shortDayFormat.withLocale(Locale.getDefault()))

/** Logging streaks: one missed day doesn't end a streak, as long as six logged days sit between missed ones. */
object TrackingStreak {
    const val LOGGED_DAYS_BETWEEN_MISSES = 6

    /** Days with something logged. */
    fun days(data: AppData): Set<String> = data.logs.filter { day -> day.value.flatMap { it.items }.isNotEmpty() }.keys

    /** The logged days in the streak running up to `date`, and the missed days it has carried. Today never counts against it. */
    fun walk(days: Set<String>, on: LocalDate): Pair<Int, Set<String>> {
        var cursor = on
        if (dayKey(cursor) !in days) cursor = cursor.minusDays(1)
        var count = 0; val missed = mutableSetOf<String>(); var sinceMiss = LOGGED_DAYS_BETWEEN_MISSES
        while (true) {
            if (dayKey(cursor) in days) {
                count += 1; sinceMiss += 1
            } else {
                if (sinceMiss < LOGGED_DAYS_BETWEEN_MISSES || dayKey(cursor.minusDays(1)) !in days) break
                missed += dayKey(cursor); sinceMiss = 0
            }
            cursor = cursor.minusDays(1)
        }
        return Pair(count, missed)
    }

    fun count(days: Set<String>, on: LocalDate): Int = walk(days, on).first

    /** The longest streak in these days, by the same rules. */
    fun best(days: Set<String>): Int {
        var best = 0; var run = 0; var sinceMiss = LOGGED_DAYS_BETWEEN_MISSES; var last: Long? = null
        for (day in days.mapNotNull { parseDayKey(it)?.toEpochDay() }.sorted()) {
            val gap = last?.let { day - it } ?: 1L
            if (gap == 1L) {
                run += 1; sinceMiss += 1
            } else if (gap == 2L && sinceMiss >= LOGGED_DAYS_BETWEEN_MISSES) {
                run += 1; sinceMiss = 1
            } else {
                run = 1; sinceMiss = LOGGED_DAYS_BETWEEN_MISSES
            }
            best = max(best, run); last = day
        }
        return best
    }
}

/**
 * A look back over the seven days ending on a given day: how much you logged, averages against target, how many days hit
 * protein, the weight trend and your most-logged meals.
 */
data class WeeklyReview(
    val start: LocalDate,
    val end: LocalDate,
    val loggedDays: Int,
    val totalCalories: Double,
    val totalCalorieTarget: Double?,
    /** Averages over the days you logged, not all seven. */
    val averageCalories: Double?,
    val averageProtein: Double?,
    val calorieTarget: Double?,
    val proteinTarget: Double?,
    /** Logged days with protein at or above target, and with calories at or under target. */
    val proteinDays: Int,
    val calorieDays: Int,
    /** Change in the smoothed weight trend across the week, in kg. */
    val weightChange: Double?,
    val trendWeight: Double?,
    val topMeals: List<Meal>,
    val fibre: NutrientWeek,
    val sodium: NutrientWeek,
) {
    data class Meal(val name: String, val count: Int)

    /** One nutrient across the week. Only days where every food logged lists the nutrient are counted. */
    data class NutrientWeek(
        val average: Double?,
        val target: Double,
        /** True when the person hasn't set a target, so `target` is the general guide. */
        val targetIsGuide: Boolean,
        /** True for a goal to reach (fibre), false for a limit to stay under (sodium). */
        val isMinimum: Boolean,
        val countedDays: Int,
        val daysMet: Int,
        val loggedDays: Int,
    ) {
        /** How far the average is from the target as a fraction of it: positive is on the good side. */
        val margin: Double? get() = average?.let { if (isMinimum) it / target - 1 else 1 - it / target }
        val onTarget: Boolean get() = (margin ?: -1.0) >= 0
    }

    /** One line for the Sunday notification. */
    val summary: String
        get() {
            if (loggedDays <= 0) return "Nothing logged this week yet."
            val parts = mutableListOf("Logged $loggedDays of 7 days")
            parts += "${totalCalories.rounded().number} Cal in total"
            averageCalories?.let { parts += "avg ${it.rounded().number}" }
            if (proteinTarget != null) parts += "protein target hit $proteinDays ${if (proteinDays == 1) "day" else "days"}"
            weightChange?.let { parts += "trend ${signed(it)} kg" }
            return parts.joinToString(" · ") + "."
        }

    /** Gentle notes on fibre and sodium, once at least two days have complete figures. */
    val nudges: List<String>
        get() {
            val notes = mutableListOf<String>()
            val fibreAverage = fibre.average
            if (fibreAverage != null && fibre.countedDays >= 2) {
                val target = fibre.target.rounded().number; val got = fibreAverage.rounded().number
                notes += if (fibre.onTarget) {
                    "Fibre averaged $got g a day, at or above ${if (fibre.targetIsGuide) "the $target g guide" else "your $target g target"}. Keep it up."
                } else if ((fibre.margin ?: -1.0) >= -0.2) {
                    "Fibre averaged $got g a day, a little under ${if (fibre.targetIsGuide) "the $target g guide" else "your $target g target"}. Beans, lentils, oats or an extra piece of fruit would close the gap."
                } else {
                    "Fibre averaged $got g a day against ${if (fibre.targetIsGuide) "a guide of" else "your target of"} $target g. Beans, lentils, oats, wholegrain bread, vegetables and fruit with the skin on are the easy additions."
                }
            }
            val sodiumAverage = sodium.average
            if (sodiumAverage != null && sodium.countedDays >= 2) {
                val target = sodium.target.rounded().number; val got = sodiumAverage.rounded().number
                val limit = if (sodium.targetIsGuide) "the $target mg guide" else "your $target mg target"
                notes += if (sodium.onTarget) {
                    "Sodium averaged $got mg a day, ${if (sodium.isMinimum) "at or above" else "within"} $limit."
                } else if (sodium.isMinimum) {
                    "Sodium averaged $got mg a day, under $limit."
                } else {
                    val over = sodium.countedDays - sodium.daysMet
                    "Sodium averaged $got mg a day, above $limit, and over it on $over of ${sodium.countedDays} days. Sauces, processed meats, bread and takeaway are the usual sources, so a lower-salt swap or smaller portion of those is the easy place to start."
                }
            }
            return notes
        }

    /** "14 Oct – 20 Oct". */
    val range: String get() = "${shortDay(start)} – ${shortDay(end)}"

    companion object {
        /** Reference amounts used when no target is set: about 25 g of fibre and no more than 2,000 mg of sodium a day. */
        const val FIBRE_GUIDE = 25.0
        const val SODIUM_GUIDE = 2000.0

        fun signed(value: Double): String {
            val rounded = (value * 10).rounded() / 10
            return (if (rounded > 0) "+" else if (rounded < 0) "−" else "") + abs(rounded).number
        }

        fun make(data: AppData, goals: Goals, ending: LocalDate = LocalDate.now(), zone: ZoneId = ZoneId.systemDefault()): WeeklyReview {
            val last = ending
            val first = last.minusDays(6)
            val days = (0 until 7L).map { dayKey(first.plusDays(it)) }
            val calories = mutableListOf<Double>(); val protein = mutableListOf<Double>()
            val calorieTargets = mutableListOf<Double>(); val proteinTargets = mutableListOf<Double>()
            var proteinDays = 0; var calorieDays = 0
            val counts = LinkedHashMap<String, Meal>()
            val fibreDays = mutableListOf<Double>(); val sodiumDays = mutableListOf<Double>()
            val fibreTargets = mutableListOf<Double>(); val sodiumTargets = mutableListOf<Double>()
            var fibreMinimum = true; var sodiumMinimum = false
            var fibreMet = 0; var sodiumMet = 0
            for (key in days) {
                val entries = data.logs[key] ?: emptyList()
                if (entries.isEmpty()) continue
                val total = Nutrition(entries.flatMap { it.items }); val target = data.dayGoals[key] ?: goals
                calories += total.cal; protein += total.p
                target.values["cal"]?.let { cal -> calorieTargets += cal; if (total.cal <= cal) calorieDays += 1 }
                target.values["p"]?.let { p -> proteinTargets += p; if (total.p >= p) proteinDays += 1 }
                for (entry in entries) {
                    val k = entry.name.lowercase()
                    val existing = counts[k]
                    counts[k] = existing?.copy(count = existing.count + 1) ?: Meal(entry.name, 1)
                }
                fun counted(nutrient: String): Double? {
                    val value = total.nut[nutrient] ?: return null
                    return if (total.isPartial(nutrient)) null else value
                }
                counted("fibre")?.let { fibre ->
                    fibreDays += fibre
                    val wanted = target.values["fibre"]
                    if (wanted != null) { fibreTargets += wanted; fibreMinimum = "fibre" in target.minimums }
                    val goal = wanted ?: FIBRE_GUIDE
                    if (if (wanted == null || "fibre" in target.minimums) fibre >= goal else fibre <= goal) fibreMet += 1
                }
                counted("sodium")?.let { sodium ->
                    sodiumDays += sodium
                    val wanted = target.values["sodium"]
                    if (wanted != null) { sodiumTargets += wanted; sodiumMinimum = "sodium" in target.minimums }
                    val goal = wanted ?: SODIUM_GUIDE
                    if (if (wanted == null || "sodium" !in target.minimums) sodium <= goal else sodium >= goal) sodiumMet += 1
                }
            }
            fun average(values: List<Double>): Double? = if (values.isEmpty()) null else values.sum() / values.size

            // The trend on the last weigh-in before the week, against the last one in it.
            val points = WeightTrend.points(data.weightLog, zone)
            val inWeek = points.lastOrNull { !it.date.isBefore(first) && !it.date.isAfter(last) }
            val before = points.lastOrNull { it.date.isBefore(first) }
            val meals = counts.values.filter { it.count >= 2 }
                .sortedWith(compareByDescending<Meal> { it.count }.thenBy { it.name }).take(3)

            return WeeklyReview(
                start = first, end = last, loggedDays = calories.size,
                totalCalories = calories.sum(),
                totalCalorieTarget = if (calorieTargets.isEmpty()) null else calorieTargets.sum(),
                averageCalories = average(calories), averageProtein = average(protein),
                calorieTarget = average(calorieTargets), proteinTarget = average(proteinTargets),
                proteinDays = proteinDays, calorieDays = calorieDays,
                weightChange = if (inWeek != null && before != null) inWeek.trend - before.trend else null, trendWeight = inWeek?.trend,
                topMeals = meals,
                fibre = NutrientWeek(average(fibreDays), average(fibreTargets) ?: FIBRE_GUIDE, fibreTargets.isEmpty(),
                    fibreTargets.isEmpty() || fibreMinimum, fibreDays.size, fibreMet, calories.size),
                sodium = NutrientWeek(average(sodiumDays), average(sodiumTargets) ?: SODIUM_GUIDE, sodiumTargets.isEmpty(),
                    sodiumTargets.isNotEmpty() && sodiumMinimum, sodiumDays.size, sodiumMet, calories.size),
            )
        }
    }
}

/** A year in Leanrrr, for the cards in December: what was logged, the favourites, the longest streak and the way weight moved. */
data class YearReview(
    val year: Int,
    val meals: Int,
    val days: Int,
    val topMeal: Pair<String, Int>?,
    /** The restaurant logged from most. */
    val topChain: Pair<String, Int>?,
    val bestStreak: Int,
    val proteinDays: Int,
    /** Towards the goal weight only, and null with no goal: this isn't the place to point out a step back. */
    val weight: Weight?,
) {
    data class Weight(val moved: Double, val losing: Boolean, val goal: Double)

    companion object {
        /** Fewer logged days than this isn't much of a year to look back on. */
        const val FEWEST_DAYS = 14

        /** The year whose review is open on `now`: all of December, and January for the year just gone. */
        fun showing(on: LocalDate): Int? = when (on.monthValue) { 12 -> on.year; 1 -> on.year - 1; else -> null }

        private fun top(counts: Map<String, Int>): Pair<String, Int>? =
            counts.entries.sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key }).firstOrNull()?.let { Pair(it.key, it.value) }

        /** `restaurants` are the chains to count, so your own foods and everyday foods don't win. */
        fun make(data: AppData, year: Int, restaurants: Set<String> = emptySet()): YearReview {
            val prefix = "$year-"
            val logged = data.logs.filter { it.key.startsWith(prefix) && it.value.isNotEmpty() }
            val entries = logged.values.flatten()
            val current = data.goalSets.firstOrNull { it.id == data.activeGoal } ?: data.goalSets[0]
            val meals = entries.filter { it.name != "Quick add" }.groupingBy { it.name }.eachCount()
            val chains = entries.flatMap { it.items }.filter { it.food.chain in restaurants }.groupingBy { it.food.chain }.eachCount()
            val proteinDays = logged.count { (key, day) ->
                (data.dayGoals[key] ?: current).values["p"]?.let { Nutrition(day.flatMap { it.items }).p >= it } ?: false
            }
            var weight: Weight? = null
            val points = WeightTrend.points(data.weightLog).filter { dayKey(it.date).startsWith(prefix) }
            val goal = data.weightGoal
            if (goal != null && points.isNotEmpty()) {
                val losing = goal.kg < goal.startKg
                val moved = ((points.first().trend - points.last().trend) * (if (losing) 1 else -1)).tenth
                if (moved > 0) weight = Weight(moved, losing, goal.kg)
            }
            return YearReview(year, entries.size, logged.size, top(meals), top(chains), TrackingStreak.best(logged.keys), proteinDays, weight)
        }
    }
}

/**
 * A look back over the last 7, 30 or 90 days for the Progress tab: how much you logged, averages against target, the macro
 * split, where the day's calories go, what contributed most, water and weight change.
 */
data class ProgressBreakdown(
    val days: Int,
    val start: LocalDate,
    val end: LocalDate,
    val loggedDays: Int,
    val points: List<DayPoint>,
    val averageCalories: Double?,
    val averageProtein: Double?,
    val calorieTarget: Double?,
    val proteinTarget: Double?,
    val calorieDays: Int,
    val proteinDays: Int,
    val carbs: Average,
    val fat: Average,
    val fibre: Average,
    val sodium: Average,
    /** Share of the calories from protein, carbs and fat, over everything logged. Null with nothing logged. */
    val share: MacroShare?,
    /** False when some logged foods list no carbs or fat, which makes the shares approximate. */
    val shareComplete: Boolean,
    val mealTimes: List<MealShare>,
    val topFoods: List<FoodTotal>,
    val water: Average,
    val startTrend: Double?,
    val endTrend: Double?,
) {
    data class DayPoint(val key: String, val date: LocalDate, val calories: Double?, val protein: Double?, val calorieTarget: Double?)
    data class Average(val value: Double?, val countedDays: Int)
    data class MacroShare(val protein: Double, val carbs: Double, val fat: Double)
    data class MealShare(val mealTime: MealTime?, val averageCalories: Double) {
        val title: String get() = mealTime?.title ?: "Unassigned"
    }
    data class FoodTotal(val name: String, val servings: Double, val calories: Double, val protein: Double)

    val weightChange: Double? get() = if (startTrend != null && endTrend != null) endTrend - startTrend else null

    companion object {
        val ranges = listOf(7, 30, 90)

        fun make(data: AppData, goals: Goals, days: Int, ending: LocalDate = LocalDate.now(), zone: ZoneId = ZoneId.systemDefault()): ProgressBreakdown {
            val last = ending
            val first = last.minusDays((days - 1).toLong())
            val points = mutableListOf<DayPoint>()
            val calories = mutableListOf<Double>(); val protein = mutableListOf<Double>()
            val calorieTargets = mutableListOf<Double>(); val proteinTargets = mutableListOf<Double>()
            var calorieDays = 0; var proteinDays = 0
            val carbs = mutableListOf<Double>(); val fat = mutableListOf<Double>(); val fibre = mutableListOf<Double>(); val sodium = mutableListOf<Double>()
            var sp = 0.0; var sc = 0.0; var sf = 0.0; var shareComplete = true
            val mealTotals = mutableMapOf<MealTime?, Double>()
            val foods = mutableMapOf<String, FoodTotal>()
            val water = mutableListOf<Double>()

            for (offset in 0 until days) {
                val date = first.plusDays(offset.toLong())
                val key = dayKey(date)
                val target = data.dayGoals[key] ?: goals
                data.water?.get(key)?.let { if (it > 0) water += it }
                val entries = data.logs[key] ?: emptyList()
                if (entries.isEmpty()) {
                    points += DayPoint(key, date, null, null, target.values["cal"])
                    continue
                }
                val items = entries.flatMap { it.items }; val total = Nutrition(items)
                points += DayPoint(key, date, total.cal, total.p, target.values["cal"])
                calories += total.cal; protein += total.p
                target.values["cal"]?.let { cal -> calorieTargets += cal; if (total.cal <= cal) calorieDays += 1 }
                target.values["p"]?.let { p -> proteinTargets += p; if (total.p >= p) proteinDays += 1 }
                if (!total.missingCarbs) carbs += total.c
                if (!total.missingFat) fat += total.f
                total.nut["fibre"]?.let { if (!total.isPartial("fibre")) fibre += it }
                total.nut["sodium"]?.let { if (!total.isPartial("sodium")) sodium += it }
                sp += total.p * 4; sc += total.c * 4; sf += total.f * 9
                if (total.missingCarbs || total.missingFat) shareComplete = false
                for (entry in entries) mealTotals[entry.mealTime] = (mealTotals[entry.mealTime] ?: 0.0) + Nutrition(entry.items).cal
                for (item in items) {
                    val name = item.food.name; val id = item.food.chain + "|" + name.lowercase()
                    val row = foods[id] ?: FoodTotal(name, 0.0, 0.0, 0.0)
                    foods[id] = row.copy(servings = row.servings + item.quantity, calories = row.calories + item.food.cal * item.quantity,
                        protein = row.protein + item.food.p * item.quantity)
                }
            }
            fun average(values: List<Double>): Double? = if (values.isEmpty()) null else values.sum() / values.size
            fun counted(values: List<Double>) = Average(average(values), values.size)

            val shareSum = sp + sc + sf
            val share = if (shareSum > 0) MacroShare(sp / shareSum, sc / shareSum, sf / shareSum) else null
            val logged = max(1, calories.size).toDouble()
            val order: List<MealTime?> = MealTime.entries + listOf(null)
            val mealTimes = order.mapNotNull { time -> mealTotals[time]?.let { MealShare(time, it / logged) } }
            val top = foods.values.sortedWith(compareByDescending<FoodTotal> { it.calories }.thenBy { it.name }).take(5)

            // The trend on the last weigh-in before the range, or the first inside it, against the last inside it.
            val trend = WeightTrend.points(data.weightLog, zone)
            val inRange = trend.filter { !it.date.isBefore(first) && !it.date.isAfter(last) }
            val baseline = trend.lastOrNull { it.date.isBefore(first) } ?: inRange.firstOrNull()
            val endPoint = inRange.lastOrNull()
            val usable = baseline != null && endPoint != null && baseline != endPoint

            return ProgressBreakdown(
                days, first, last, calories.size, points, average(calories), average(protein), average(calorieTargets), average(proteinTargets),
                calorieDays, proteinDays, counted(carbs), counted(fat), counted(fibre), counted(sodium), share, shareComplete, mealTimes, top,
                counted(water), if (usable) baseline?.trend else null, endPoint?.trend,
            )
        }
    }
}

/**
 * Short observations from your own log over the Progress range: "Weekends average 600 Cal more than weekdays". Each only
 * appears when there's enough to go on and the difference is big enough to matter, strongest first (Insights.swift).
 */
object ProgressInsights {
    /** `icon` names the SF Symbol; the screen maps it to a Material icon. */
    data class Insight(val id: String, val icon: String, val text: String, val strength: Double)

    private class Day(val date: LocalDate, val calories: Double, val protein: Double, val calorieTarget: Double?, val proteinTarget: Double?,
                      val entries: List<com.isaiahgraham.leanrrr.data.LogEntry>) {
        val hitProtein: Boolean? get() = proteinTarget?.let { protein >= it }
        val overCalories: Boolean? get() = calorieTarget?.let { calories > it }
    }

    fun make(data: AppData, goals: Goals, days: Int, ending: LocalDate = LocalDate.now(), zone: ZoneId = ZoneId.systemDefault(), limit: Int = 4): List<Insight> {
        val logged = (0 until days).mapNotNull { offset ->
            val date = ending.minusDays(offset.toLong()); val key = dayKey(date)
            val entries = data.logs[key]
            if (entries.isNullOrEmpty()) return@mapNotNull null
            val total = Nutrition(entries.flatMap { it.items }); val target = data.dayGoals[key] ?: goals
            Day(date, total.cal, total.p, target.values["cal"], target.values["p"], entries)
        }
        if (logged.size < 5) return emptyList()
        val found = listOfNotNull(weekends(logged), breakfast(logged), biggestDay(logged), lateEating(logged, zone), takeaway(logged),
            overTargetFood(logged), lowProteinMeal(logged))
        return found.sortedByDescending { it.strength }.take(limit)
    }

    private fun average(values: List<Double>): Double? = if (values.isEmpty()) null else values.sum() / values.size
    /** To the nearest 10. */
    fun calories(value: Double): String = ((value / 10).rounded() * 10).number
    /** To the nearest 5%. */
    fun percent(value: Double): String = "${((value * 20).rounded() * 5).toInt()}%"
    private fun isWeekend(date: LocalDate) = date.dayOfWeek == DayOfWeek.SATURDAY || date.dayOfWeek == DayOfWeek.SUNDAY
    /** Sunday is 1, as in Foundation's calendar, so ties break the same way. */
    private fun weekdayNumber(date: LocalDate) = date.dayOfWeek.value % 7 + 1

    private const val WEEKEND_GAP = 150.0
    private fun weekends(days: List<Day>): Insight? {
        val weekend = days.filter { isWeekend(it.date) }.map { it.calories }
        val weekday = days.filter { !isWeekend(it.date) }.map { it.calories }
        if (weekend.size < 2 || weekday.size < 3) return null
        val a = average(weekend)!!; val b = average(weekday)!!
        if (abs(a - b) < WEEKEND_GAP) return null
        return Insight("weekends", "calendar", "Weekends average ${calories(abs(a - b))} Cal ${if (a > b) "more" else "less"} than weekdays.", abs(a - b) / 100)
    }

    private fun breakfast(days: List<Day>): Insight? {
        val counted = days.filter { it.hitProtein != null }
        val with = counted.filter { d -> d.entries.any { it.mealTime == MealTime.BREAKFAST } }
        val without = counted.filter { d -> d.entries.none { it.mealTime == MealTime.BREAKFAST } }
        if (with.size < 3 || without.size < 3) return null
        val a = with.count { it.hitProtein == true }.toDouble() / with.size
        val b = without.count { it.hitProtein == true }.toDouble() / without.size
        if (abs(a - b) < 0.2) return null
        return Insight("breakfast", "sunrise", "Days you log breakfast, you hit your protein target ${percent(a)} of the time, against ${percent(b)} without.", abs(a - b) * 10)
    }

    private fun biggestDay(days: List<Day>): Insight? {
        val overall = average(days.map { it.calories }) ?: return null
        val byWeekday = days.groupBy { weekdayNumber(it.date) }.filter { it.value.size >= 2 }
        if (byWeekday.size < 3) return null
        val top = byWeekday.mapValues { e -> average(e.value.map { it.calories })!! }.entries
            .sortedWith(compareByDescending<Map.Entry<Int, Double>> { it.value }.thenBy { it.key }).first()
        if (top.value - overall < 250) return null
        val dow = DayOfWeek.of(if (top.key == 1) 7 else top.key - 1)
        val name = dow.getDisplayName(TextStyle.FULL_STANDALONE, Locale.getDefault())
        return Insight("weekday", "chart.bar", "${name}s are your biggest day, averaging ${calories(top.value)} Cal.", (top.value - overall) / 120)
    }

    private fun lateEating(days: List<Day>, zone: ZoneId): Insight? {
        val entries = days.flatMap { it.entries }
        val total = entries.sumOf { Nutrition(it.items).cal }
        if (total <= 0) return null
        val late = entries.filter { it.time.atZone(zone).hour >= 20 }.sumOf { Nutrition(it.items).cal }
        val share = late / total
        if (share < 0.25) return null
        return Insight("late", "moon", "${percent(share)} of your calories come after 8 pm.", share * 8)
    }

    private fun takeaway(days: List<Day>): Insight? {
        fun fromRestaurant(day: Day) = day.entries.flatMap { it.items }.any { it.food.chain != "mine" && !it.food.isEveryday && !it.food.isSupermarket }
        val with = days.filter(::fromRestaurant).map { it.calories }; val without = days.filter { !fromRestaurant(it) }.map { it.calories }
        if (with.size < 3 || without.size < 3) return null
        val a = average(with)!!; val b = average(without)!!
        if (abs(a - b) < 200) return null
        return Insight("takeaway", "takeoutbag.and.cup.and.straw", "Days with takeaway average ${calories(abs(a - b))} Cal ${if (a > b) "more" else "less"} than days without.", abs(a - b) / 100)
    }

    private fun overTargetFood(days: List<Day>): Insight? {
        val over = days.filter { it.overCalories == true }; val under = days.filter { it.overCalories == false }
        if (over.size < 3 || under.size < 3) return null
        fun share(name: String, group: List<Day>) = group.count { d -> d.entries.flatMap { it.items }.any { it.food.name.lowercase() == name } }.toDouble() / group.size
        val names = over.flatMap { d -> d.entries.flatMap { it.items }.map { it.food.name.lowercase() } }.toSet()
        data class Scored(val name: String, val over: Double, val under: Double)
        val scored = names.map { Scored(it, share(it, over), share(it, under)) }.filter { it.over >= 0.5 && it.over - it.under >= 0.3 }
        val best = scored.sortedWith(compareByDescending<Scored> { it.over - it.under }.thenBy { it.name }).firstOrNull() ?: return null
        val display = over.flatMap { d -> d.entries.flatMap { it.items } }.firstOrNull { it.food.name.lowercase() == best.name }?.food?.name ?: return null
        val count = over.count { d -> d.entries.flatMap { it.items }.any { it.food.name.lowercase() == best.name } }
        return Insight("over-food", "exclamationmark.circle", "$display is on $count of the ${over.size} days you went over your calories.", (best.over - best.under) * 9)
    }

    private fun lowProteinMeal(days: List<Day>): Insight? {
        if (days.none { it.proteinTarget != null }) return null
        val meals = MealTime.entries.filter { it != MealTime.SNACKS }.mapNotNull { meal ->
            val amounts = days.mapNotNull { day ->
                val entries = day.entries.filter { it.mealTime == meal }
                if (entries.isEmpty()) null else Nutrition(entries.flatMap { it.items }).p
            }
            if (amounts.size >= 3) Pair(meal, average(amounts)!!) else null
        }
        if (meals.size < 2) return null
        val low = meals.minBy { it.second }
        if (low.second >= 20) return null
        return Insight("low-protein", "fork.knife", "${low.first.title} brings you ${low.second.rounded().number} g of protein on average, your lowest meal.", (20 - low.second) / 4)
    }
}
