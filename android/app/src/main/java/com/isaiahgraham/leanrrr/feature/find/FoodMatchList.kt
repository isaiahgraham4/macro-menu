package com.isaiahgraham.leanrrr.feature.find

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.newId
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.components.NumberField
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType

/**
 * One food named by a photo, a sentence or a recipe line, the Leanrrr foods that match it, and how much to use (FoodMatchList.swift).
 * Matching words to foods and working out amounts belong to the features that read the words (FoodPhrase in Today, MealPhoto in
 * Scan), so they build rows with the matches already found and pass `amount` to work the servings out for another match.
 */
data class FoodMatchRow(
    val id: String = newId(),
    /** What was seen or written, for the header. */
    val title: String,
    val matches: List<Food>,
    /** The match to use, or null to leave this one out. */
    val chosen: String? = null,
    val quantity: Double = 1.0,
    /** False when the amount is a guess that should be checked. */
    val sure: Boolean = true,
    /** Said above the picker when nothing is chosen. */
    val unchosenNote: String? = null,
    /** The words as written, for "Check the amount" and as the search to start from. */
    val original: String = title,
    /** Servings of a food and whether they're sure, from the words; null keeps the amount as it is. */
    val amount: ((Food) -> Pair<Double, Boolean>)? = null,
) {
    val food: Food? get() = matches.firstOrNull { it.id == chosen }
    val portion: Portion? get() = food?.let { Portion(food = it, quantity = quantity) }

    /** This row with another match chosen, its amount worked out again from the words. */
    fun choosing(id: String?): FoodMatchRow {
        val next = copy(chosen = id)
        val food = next.food ?: return next
        val worked = amount?.invoke(food) ?: return next
        return next.copy(quantity = worked.first, sure = worked.second)
    }

    /** This row with a food found by searching, put first and chosen. */
    fun picking(portion: Portion): FoodMatchRow =
        copy(matches = listOf(portion.food) + matches.filter { it.id != portion.food.id }, chosen = portion.food.id, quantity = portion.quantity, sure = true)
}

/**
 * A section per row: pick the match (or leave it out), set the servings, or search for something else. `onSearch` should open
 * [BrowseScreen] with a `pick` that calls `onChange(index, row.picking(portion))`, starting from `row.original`.
 */
fun LazyListScope.foodMatchSections(rows: List<FoodMatchRow>, onChange: (Int, FoodMatchRow) -> Unit, onSearch: (Int) -> Unit) {
    rows.forEachIndexed { index, row ->
        item(key = "match:" + row.id) {
            LeanrSection(row.title) { FoodMatchSection(row, { onChange(index, it) }, { onSearch(index) }) }
        }
    }
}

@Composable
fun FoodMatchSection(row: FoodMatchRow, onChange: (FoodMatchRow) -> Unit, onSearch: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    if (row.matches.isEmpty()) {
        SectionText("Not in Leanrrr yet. Search for something close, or leave it out.", c.secondaryText)
    } else {
        if (row.chosen == null && row.unchosenNote != null) SectionText(row.unchosenNote, c.secondaryText, style = LeanrType.caption)
        (row.matches.map { it.id to it.name } + (null to "Leave it out")).forEach { (id, name) ->
            Row(Modifier.fillMaxWidth().clickable { onChange(row.choosing(id)) }.padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(if (row.chosen == id) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked, null, tint = if (row.chosen == id) c.accent else c.tertiaryText)
                Spacer(Modifier.width(12.dp))
                Text(name, style = LeanrType.body, color = c.text)
            }
        }
        RowDivider()
        row.food?.let { food ->
            key(row.chosen, row.quantity) { NumberField("Servings", row.quantity, { onChange(row.copy(quantity = it)) }) }
            Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                Text("${store.chainName(food.chain)} · ${food.serve.ifEmpty { "1 serving" }} each · ${Nutrition(listOf(Portion(food = food, quantity = row.quantity))).cal.rounded().number} Cal",
                    style = LeanrType.caption, color = c.secondaryText)
                if (!row.sure) Text("Check the amount: Leanrrr couldn't turn \"${row.original}\" into servings of this food.", style = LeanrType.caption, color = Leanr.orange)
            }
            RowDivider()
        }
    }
    ActionRow("Search for it instead", Icons.Filled.Search, divider = false, onClick = onSearch)
}
