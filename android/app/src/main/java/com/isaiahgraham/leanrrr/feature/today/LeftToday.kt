package com.isaiahgraham.leanrrr.feature.today

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.AppData
import com.isaiahgraham.leanrrr.data.AppStore
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.Goals
import com.isaiahgraham.leanrrr.data.LogEntry
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.QuickLog
import com.isaiahgraham.leanrrr.data.dayKey
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.data.rememberBoolPref
import com.isaiahgraham.leanrrr.feature.find.DietFilter
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlin.math.max
import kotlin.math.min

/** The "Left today" ideas setting (TodaySuggestions in LeftToday.swift). Settings turns it off. */
object TodaySuggestions {
    const val STORAGE_KEY = "today.suggestions"
    const val OPEN_KEY = "today.suggestions.open"
}

/**
 * Ideas for what fits what's left of today (the parts of Assistant.swift that Today and Plan ahead use; Find owns the full
 * assistant). Foods you pinned, ate lately, saved or made yourself come first, then everyday foods to fill any gap, ranked by
 * how much of a meal's protein they cover per calorie. The one-restaurant-order idea is left to Find's assistant.
 */
object LeftToday {
    data class Suggestion(val id: String, val name: String, val items: List<Portion>, val sourceText: String, val calories: Double, val protein: Double)

    /** Your usual meal at a meal time over the last 30 days. */
    fun usual(mealTime: MealTime, logs: Map<String, List<LogEntry>>, now: Instant = Instant.now()): LogEntry? =
        QuickLog.frequent(logs.mapValues { (_, entries) -> entries.filter { it.mealTime == mealTime } }, now, limit = 1).firstOrNull()

    /** Today's targets less what's been logged today. Null for a target that isn't set. */
    fun remaining(data: AppData, goals: Goals, now: Instant = Instant.now()): Pair<Double?, Double?> {
        val key = dayKey(now)
        val eaten = Nutrition((data.logs[key] ?: emptyList()).flatMap { it.items })
        val target = data.dayGoals[key] ?: goals
        return Pair(target.values["cal"]?.let { it - eaten.cal }, target.values["p"]?.let { it - eaten.p })
    }

    /** What's left to fill today, in words: "62 g protein · 630 Cal". Null when there's nothing left or no target. */
    fun leftText(data: AppData, goals: Goals, now: Instant = Instant.now()): String? {
        val (calories, protein) = remaining(data, goals, now)
        val parts = mutableListOf<String>()
        if (protein != null && protein > 0) parts += "${protein.whole.number} g protein"
        if (calories != null && calories > 0) parts += "${calories.whole.number} Cal"
        return parts.takeIf { it.isNotEmpty() }?.joinToString(" · ")
    }

    /** Up to `limit` things that fit what's left of today. Nothing when today's calories are used up or protein is met. */
    fun suggestions(data: AppData, goals: Goals, pinned: List<Food>, everyday: List<Food>, diet: DietFilter, now: Instant = Instant.now(), limit: Int = 3): List<Suggestion> {
        val (leftCalories, leftProtein) = remaining(data, goals, now)
        if (leftCalories != null && leftCalories < 100) return emptyList()
        if (leftProtein != null && leftProtein <= 0) return emptyList()
        // A suggestion is one meal, so it's held to your typical meal (a half more after 4 pm, when fewer meals are left to come),
        // and counts protein only up to a typical meal's worth, so a huge platter doesn't outrank a sensible one.
        val lastMeal = now.atZone(ZoneId.systemDefault()).hour >= 16
        val mealCap = if (lastMeal) goals.mealCal * 1.5 else goals.mealCal
        val budget = leftCalories?.let { min(it, mealCap) } ?: mealCap
        val want = leftProtein ?: goals.mealProtein
        val useful = if (goals.mealProtein > 0) min(want, goals.mealProtein) else want
        val floor = max(3.0, min(useful, 10.0))

        fun suggestion(name: String, items: List<Portion>, source: String, id: String): Suggestion? {
            val total = Nutrition(items)
            if (items.isEmpty() || !(diet.isEmpty || items.all { diet.allows(it.food) }) || !items.all { it.isValid } ||
                total.cal < 30 || total.cal > budget || total.p < floor) return null
            return Suggestion(id, name, items, source, total.cal, total.p)
        }
        fun score(item: Suggestion) = min(item.protein, useful) / item.calories
        fun ranked(list: List<Suggestion>) = list.sortedWith(
            compareByDescending<Suggestion> { score(it) }.thenByDescending { min(it.protein, useful) }.thenBy { it.name },
        )
        val seen = mutableSetOf<String>()
        fun fresh(s: Suggestion?): Suggestion? = s?.takeIf { seen.add(it.name.lowercase()) }

        val usual = mutableListOf<Suggestion>()
        pinned.forEach { food -> fresh(suggestion(food.name, listOf(Portion(food = food)), "Pinned", "food:${food.id}"))?.let { usual += it } }
        QuickLog.recentFoods(data.logs, now, limit = 60).forEach { food -> fresh(suggestion(food.name, listOf(Portion(food = food)), "Eaten lately", "food:${food.id}"))?.let { usual += it } }
        data.foods.forEach { food -> fresh(suggestion(food.name, listOf(Portion(food = food)), "Your food", "food:${food.id}"))?.let { usual += it } }
        data.meals.forEach { meal -> fresh(suggestion(meal.name, QuickLog.copies(meal.items), "Your meal", "meal:${meal.id}"))?.let { usual += it } }
        val chosen = ranked(usual).take(limit).toMutableList()
        if (chosen.size < limit) {
            val names = chosen.map { it.name.lowercase() }.toSet()
            val staples = everyday.filter { it.cat in listOf("food", "breakfast") && !it.name.lowercase().contains("raw") && it.name.lowercase() !in names }
            chosen += ranked(staples.mapNotNull { fresh(suggestion(it.name, listOf(Portion(food = it)), "Everyday food", "food:${it.id}")) }).take(limit - chosen.size)
        }
        return chosen.take(limit)
    }

    /** Suggestions for the store as it is now, worked out off the main thread. */
    suspend fun suggestions(store: AppStore, data: AppData = store.data, now: Instant = Instant.now(), limit: Int = 3): List<Suggestion> {
        val goals = store.goals
        val pinned = store.pinnedFoods
        val diet = DietFilter.saved
        val everyday = if (diet.isEmpty) store.everyday else store.everyday.filter { diet.allows(it) }
        return withContext(Dispatchers.Default) { suggestions(data, goals, pinned, everyday, diet, now, limit) }
    }
}

/**
 * "Left today: 62 g protein · 630 Cal", folded away until opened, with a few one-meal ideas that fit what's left (LeftTodaySection).
 * Each + logs one serving to today under `mealTime`. Settings turns it off. Meal shows this above the tray.
 */
@Composable
fun LeftTodaySection(mealTime: MealTime) {
    val store = AppServices.store
    val c = Leanr.colours
    val enabled by rememberBoolPref(TodaySuggestions.STORAGE_KEY, true)
    var open by rememberBoolPref(TodaySuggestions.OPEN_KEY, false)
    var ideas by remember { mutableStateOf(emptyList<LeftToday.Suggestion>()) }
    val today = dayKey(LocalDate.now())
    val (calories, protein) = LeftToday.remaining(store.data, store.goals)
    LaunchedEffect(enabled, today, store.data.logs[today]?.size, calories?.toInt(), protein?.toInt(), store.data.pinned?.size, store.data.meals.size, store.foodsLoaded) {
        ideas = if (enabled) LeftToday.suggestions(store) else emptyList()
    }
    if (!enabled || ideas.isEmpty()) return
    LeanrSection {
        Disclosure(divider = false, expanded = open, onExpandedChange = { open = it }, label = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.Lightbulb, null, tint = c.accent, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(10.dp))
                Text(LeftToday.leftText(store.data, store.goals)?.let { "Left today: $it" } ?: "What fits",
                    style = LeanrType.subheadline.copy(fontWeight = FontWeight.Medium), color = c.text)
            }
        }) {
            ideas.forEach { item -> SuggestionRow(item, "Log ${item.name} to ${mealTime.title}") {
                if (store.log(QuickLog.copies(item.items), item.name, LocalDate.now(), mealTime = mealTime)) store.notice = "Logged to ${mealTime.title.lowercase()}"
            } }
            Text("Tap + to log one serving to ${mealTime.title}. Check the portion. You can turn these off in Settings.", style = LeanrType.caption, color = c.secondaryText)
        }
    }
}

/** An idea with its figures and a + (shared by Left today and Plan ahead). */
@Composable
internal fun SuggestionRow(item: LeftToday.Suggestion, label: String, modifier: Modifier = Modifier, onAdd: () -> Unit) {
    val c = Leanr.colours
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(item.name, style = LeanrType.headline, color = c.text)
            Text("${item.calories.whole.number} Cal · ${item.protein.number} g protein · ${item.sourceText}", style = LeanrType.caption, color = c.secondaryText)
        }
        IconButton(onClick = onAdd) { Icon(Icons.Filled.AddCircle, label, tint = c.accent, modifier = Modifier.size(28.dp)) }
    }
}
