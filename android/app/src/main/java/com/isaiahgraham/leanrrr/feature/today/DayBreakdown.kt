package com.isaiahgraham.leanrrr.feature.today

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.Goals
import com.isaiahgraham.leanrrr.data.LogEntry
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.dayKey
import com.isaiahgraham.leanrrr.data.nutrientNames
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.ui.components.LabeledValue
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.components.NutritionView
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import java.text.DecimalFormat
import java.time.LocalDate
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Everything logged on one day, taken apart for the breakdown that opens from Today's targets (DayBreakdown.swift):
 * the macros and their share of energy, every nutrient any food listed, and which foods it came from.
 * A nutrient is "partial" when some logged foods don't list it, and the total counts only the ones that do.
 */
class DayBreakdown(entries: List<LogEntry>, goals: Goals) {
    /** One logged food, as it was logged (a recipe stays one line). */
    data class Line(val id: String, val name: String, val amount: String, val mealTime: MealTime?, val nutrition: Nutrition)
    /** One food's part in a nutrient's total. */
    data class Source(val id: String, val name: String, val value: Double)
    data class Macro(
        val key: String, val label: String, val grams: Double,
        /** Share of the energy from protein, carbs and fat (4/4/9), from 0 to 1. */
        val share: Double,
        val target: Double?, val minimum: Boolean, val partial: Boolean, val sources: List<Source>,
    )
    data class Nutrient(
        val key: String, val label: String, val unit: String, val value: Double, val target: Double?, val minimum: Boolean,
        /** How many of the day's foods list it. */
        val listedBy: Int, val sources: List<Source>,
    )

    val lines: List<Line> = entries.flatMap { entry ->
        entry.items.map { Line(it.id, it.food.name, amount(it), entry.mealTime, Nutrition(listOf(it))) }
    }
    val total = Nutrition(entries.flatMap { it.items })
    val macros: List<Macro>
    /** Nutrients at least one food listed, in the usual order, then any others by name. */
    val nutrients: List<Nutrient>
    /** Nutrients with a target that none of the day's foods listed. */
    val unlisted: List<String>

    private fun sources(value: (Nutrition) -> Double?): List<Source> =
        lines.mapNotNull { line -> value(line.nutrition)?.let { Source(line.id, line.name, it) } }.filter { it.value > 0 }.sortedByDescending { it.value }

    init {
        val energy = total.p * 4 + total.c * 4 + total.f * 9
        macros = listOf(Triple("p", "Protein", total.p), Triple("c", "Carbs", total.c), Triple("f", "Fat", total.f)).map { (key, label, grams) ->
            val factor = if (key == "f") 9.0 else 4.0
            Macro(key, label, grams, if (energy > 0) grams * factor / energy else 0.0, goals.values[key], key in goals.minimums,
                total.isPartial(key), sources { it.value(key) })
        }
        val known = nutrientNames.drop(4).map { it.key }
        val extra = (lines.flatMap { it.nutrition.nut.keys }.toSet() - known.toSet()).sorted()
        nutrients = (known + extra).mapNotNull { key ->
            val listing = lines.filter { it.nutrition.nut[key] != null }
            if (listing.isEmpty()) return@mapNotNull null
            val name = nutrientNames.firstOrNull { it.key == key }
            Nutrient(key, name?.label ?: key.replaceFirstChar { it.uppercase() }, name?.unit ?: "", total.nut[key] ?: 0.0, goals.values[key],
                key in goals.minimums, listing.size, sources { it.nut[key] })
        }
        unlisted = nutrientNames.drop(4).filter { n -> goals.values[n.key] != null && nutrients.none { it.key == n.key } }.map { it.label }
    }

    /** How many foods were logged, for "listed by 3 of 5 foods". */
    val foodCount: Int get() = lines.size

    /** True when some of the day's foods don't list this nutrient, so its total is only what's known. */
    fun isPartial(nutrient: Nutrient): Boolean = nutrient.listedBy < foodCount

    companion object {
        private val upToTwo = DecimalFormat("#,##0.##")

        /** "2 × 1 serving", or just the serve for one. */
        fun amount(portion: Portion): String {
            val serve = portion.food.serve
            return if (portion.quantity == 1.0) serve else "${upToTwo.format(portion.quantity)} × $serve"
        }

        /** "32% of 150 g goal", "52% of 2,300 mg limit", for a figure against its target. */
        fun progress(value: Double, target: Double?, minimum: Boolean, unit: String): String? {
            if (target == null || target <= 0) return null
            val percent = (value / target * 100).roundToInt()
            return if (minimum) "$percent% of ${target.number} $unit goal" else "$percent% of ${target.number} $unit limit"
        }
    }
}

/** "a, b and c", like ListFormatter. */
internal fun joinedList(items: List<String>): String = when (items.size) {
    0 -> ""
    1 -> items[0]
    else -> items.dropLast(1).joinToString(", ") + " and " + items.last()
}

/** Opened by tapping the targets on Today: the day's totals, each macro and micronutrient with the foods it came from, and every food logged. */
@Composable
fun DayBreakdownScreen(date: LocalDate, goals: Goals, onBack: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    val day = DayBreakdown(store.data.logs[dayKey(date)] ?: emptyList(), goals)
    LeanrScreen("Breakdown", onBack = onBack) {
        item {
            LeanrSection {
                Column(Modifier.padding(top = 12.dp, start = 16.dp, end = 16.dp)) {
                    Text(longDate(date), style = LeanrType.subheadline, color = c.secondaryText)
                }
                NutritionView(day.total, details = false)
                Column(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    goals.values["cal"]?.let { cal ->
                        LabeledValue("Calorie target", "${cal.number} Cal")
                        val over = day.total.cal > cal
                        Row(Modifier.fillMaxWidth()) {
                            Text(if (over) "Over by" else "Left", style = LeanrType.subheadline, color = if (over) c.over else c.text, modifier = Modifier.weight(1f))
                            Text("${abs(cal - day.total.cal).number} Cal", style = LeanrType.subheadline, color = if (over) c.over else c.secondaryText)
                        }
                    }
                    LabeledValue("Energy", "${day.total.kj.number} kJ")
                }
            }
        }
        if (day.lines.isEmpty()) {
            item { LeanrSection { Text("Nothing logged on this day yet.", style = LeanrType.body, color = c.secondaryText, modifier = Modifier.padding(16.dp)) } }
        } else {
            item {
                LeanrSection("Macros", footer = "Share is each macro’s part of the energy from protein, carbs and fat. Open one to see where it came from.") {
                    day.macros.forEachIndexed { i, macro -> MacroRow(macro, divider = i < day.macros.size - 1) }
                }
            }
            item {
                val footer = if (day.unlisted.isEmpty()) null else
                    "No food logged on this day lists ${joinedList(day.unlisted.map { it.lowercase() })}, so ${if (day.unlisted.size == 1) "it isn’t" else "they aren’t"} shown."
                LeanrSection("Micronutrients", footer = footer) {
                    if (day.nutrients.isEmpty()) {
                        Text("None of the food logged on this day lists micronutrients. Restaurant items usually list sodium, sugars and saturated fat, and foods you add yourself can list more.",
                            style = LeanrType.subheadline, color = c.secondaryText, modifier = Modifier.padding(16.dp))
                    }
                    day.nutrients.forEachIndexed { i, n -> NutrientRow(n, day, divider = i < day.nutrients.size - 1) }
                }
            }
            groups(day.lines).forEach { (title, lines) ->
                item(key = "group-$title") {
                    LeanrSection(title) { lines.forEachIndexed { i, line -> FoodLineRow(line, divider = i < lines.size - 1) } }
                }
            }
        }
    }
}

/** The day's food under its meal times, in the usual order, with anything unassigned last. */
private fun groups(lines: List<DayBreakdown.Line>): List<Pair<String, List<DayBreakdown.Line>>> {
    val result = MealTime.entries.mapNotNull { time -> lines.filter { it.mealTime == time }.takeIf { it.isNotEmpty() }?.let { time.title to it } }.toMutableList()
    val unassigned = lines.filter { it.mealTime == null }
    if (unassigned.isNotEmpty()) result += "Unassigned" to unassigned
    return result
}

private fun isOver(value: Double, target: Double?, minimum: Boolean): Boolean = target != null && !minimum && value > target

/** A row that opens to show more underneath (DisclosureGroup). */
@Composable
internal fun Disclosure(
    divider: Boolean,
    expanded: Boolean? = null,
    onExpandedChange: ((Boolean) -> Unit)? = null,
    label: @Composable () -> Unit,
    content: @Composable () -> Unit,
) {
    val c = Leanr.colours
    var own by rememberSaveable { mutableStateOf(false) }
    val open = expanded ?: own
    Column {
        Row(Modifier.fillMaxWidth().clickable { if (onExpandedChange != null) onExpandedChange(!open) else own = !open }.padding(horizontal = 16.dp, vertical = 11.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) { label() }
            Spacer(Modifier.size(8.dp))
            Icon(if (open) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, if (open) "Hide" else "Show", tint = c.accent)
        }
        if (open) Column(Modifier.padding(start = 28.dp, end = 16.dp, bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) { content() }
        if (divider) HorizontalDivider(Modifier.padding(start = 16.dp), color = c.separator, thickness = 0.5.dp)
    }
}

@Composable
private fun ProgressBar(value: Double, target: Double, colour: Color, over: Boolean) {
    val c = Leanr.colours
    val fraction = (value / target).coerceIn(0.0, 1.0).toFloat()
    Box(Modifier.fillMaxWidth().height(6.dp).clip(CircleShape).background(c.text.copy(alpha = 0.08f))) {
        Box(Modifier.fillMaxWidth(fraction).fillMaxHeight().clip(CircleShape).background(if (over) c.over else colour))
    }
}

@Composable
private fun MacroRow(macro: DayBreakdown.Macro, divider: Boolean) {
    val c = Leanr.colours
    val colour = c.nutrient(macro.key)
    Disclosure(divider, label = {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(9.dp).clip(CircleShape).background(colour))
                Spacer(Modifier.size(8.dp))
                Text(macro.label, style = LeanrType.headline, color = c.text, modifier = Modifier.weight(1f))
                Text("${macro.grams.number}${if (macro.partial) "+" else ""} g", style = LeanrType.headline, color = c.text)
            }
            Row {
                Text("${(macro.share * 100).roundToInt()}% of energy", style = LeanrType.caption, color = c.secondaryText, modifier = Modifier.weight(1f))
                DayBreakdown.progress(macro.grams, macro.target, macro.minimum, "g")?.let {
                    Text(it, style = LeanrType.caption, color = if (isOver(macro.grams, macro.target, macro.minimum)) c.over else c.secondaryText)
                }
            }
            macro.target?.takeIf { it > 0 }?.let { ProgressBar(macro.grams, it, colour, isOver(macro.grams, it, macro.minimum)) }
        }
    }) { SourceList(macro.sources, "g") }
}

@Composable
private fun NutrientRow(nutrient: DayBreakdown.Nutrient, day: DayBreakdown, divider: Boolean) {
    val c = Leanr.colours
    Disclosure(divider, label = {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row {
                Text(nutrient.label, style = LeanrType.subheadline.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Medium), color = c.text, modifier = Modifier.weight(1f))
                Text("${nutrient.value.number}${if (day.isPartial(nutrient)) "+" else ""} ${nutrient.unit}", style = LeanrType.subheadline.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Medium), color = c.text)
            }
            val progress = DayBreakdown.progress(nutrient.value, nutrient.target, nutrient.minimum, nutrient.unit)
            if (progress != null || day.isPartial(nutrient)) {
                Row {
                    Text(if (day.isPartial(nutrient)) "Listed by ${nutrient.listedBy} of ${day.foodCount} foods" else "", style = LeanrType.caption, color = c.secondaryText, modifier = Modifier.weight(1f))
                    if (progress != null) Text(progress, style = LeanrType.caption, color = if (isOver(nutrient.value, nutrient.target, nutrient.minimum)) c.over else c.secondaryText)
                }
            }
            nutrient.target?.takeIf { it > 0 }?.let { ProgressBar(nutrient.value, it, c.accent, isOver(nutrient.value, it, nutrient.minimum)) }
        }
    }) { SourceList(nutrient.sources, nutrient.unit) }
}

@Composable
private fun FoodLineRow(line: DayBreakdown.Line, divider: Boolean) {
    val c = Leanr.colours
    val n = line.nutrition
    Disclosure(divider, label = {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row {
                Text(line.name, style = LeanrType.headline, color = c.text, maxLines = 2, modifier = Modifier.weight(1f))
                Text("${n.cal.number} Cal", style = LeanrType.subheadline, color = c.text)
            }
            Text(line.amount, style = LeanrType.caption, color = c.secondaryText)
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                MacroFigure("P", n.p, false, "p")
                MacroFigure("C", n.c, n.missingCarbs, "c")
                MacroFigure("F", n.f, n.missingFat, "f")
            }
        }
    }) {
        LabeledValue("Energy", "${n.kj.number} kJ")
        nutrientNames.drop(4).forEach { name -> n.nut[name.key]?.let { LabeledValue(name.label, "${it.number} ${name.unit}") } }
        n.nut.keys.filter { key -> nutrientNames.none { it.key == key } }.sorted().forEach { key ->
            LabeledValue(key.replaceFirstChar { it.uppercase() }, (n.nut[key] ?: 0.0).number)
        }
        if (n.nut.isEmpty()) Text("No micronutrients listed for this food.", style = LeanrType.subheadline, color = c.secondaryText)
    }
}

@Composable
private fun MacroFigure(letter: String, grams: Double, partial: Boolean, key: String) {
    Text(if (partial && grams == 0.0) "$letter –" else "$letter ${grams.number} g", style = LeanrType.label, color = Leanr.colours.nutrient(key))
}

@Composable
private fun SourceList(sources: List<DayBreakdown.Source>, unit: String) {
    val c = Leanr.colours
    if (sources.isEmpty()) Text("Nothing logged on this day lists it.", style = LeanrType.subheadline, color = c.secondaryText)
    val total = sources.sumOf { it.value }
    sources.forEach { source ->
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(source.name, style = LeanrType.subheadline, color = c.text, maxLines = 2, modifier = Modifier.weight(1f))
            Text("${source.value.number} $unit", style = LeanrType.subheadline, color = c.text)
            if (total > 0) Text("${(source.value / total * 100).roundToInt()}%", style = LeanrType.caption, color = c.secondaryText,
                textAlign = TextAlign.End, modifier = Modifier.widthIn(min = 40.dp))
        }
    }
}

private val longDateFormat = java.time.format.DateTimeFormatter.ofPattern("EEEE d MMMM yyyy", java.util.Locale.forLanguageTag("en-AU"))
/** "Saturday 21 November 2026", like `.formatted(date: .complete, time: .omitted)`. */
internal fun longDate(date: LocalDate): String = date.format(longDateFormat)
