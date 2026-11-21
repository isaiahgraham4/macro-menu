package com.isaiahgraham.leanrrr.feature.today

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.QuickLog
import com.isaiahgraham.leanrrr.feature.find.FoodDetailScreen
import com.isaiahgraham.leanrrr.feature.find.FoodSearch
import com.isaiahgraham.leanrrr.ui.components.FoodRow
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.components.NumberField
import com.isaiahgraham.leanrrr.ui.components.SearchField
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/**
 * Choose a food to log, plan or add (the part of BrowseView that Today uses): search every food, or pick from pinned, recent
 * and your own foods. The + takes one serving (or what you had last time); tapping a food asks how many servings first.
 */
@Composable
internal fun FoodPickerScreen(
    title: String,
    pickTitle: String,
    onPick: (Portion) -> Unit,
    onBack: () -> Unit,
    quickAddLabel: String = "Log",
    initialSearch: String = "",
) {
    val store = AppServices.store
    val c = Leanr.colours
    var query by rememberSaveable { mutableStateOf(initialSearch) }
    var results by remember { mutableStateOf(emptyList<Food>()) }
    var asking by remember { mutableStateOf<Food?>(null) }
    var details by remember { mutableStateOf<Food?>(null) }

    LaunchedEffect(query, store.foodsLoaded, store.communityRevision) {
        if (query.isBlank()) { results = emptyList(); return@LaunchedEffect }
        delay(200)
        val foods = store.searchFoods
        val names = store.searchChainNames
        results = withContext(Dispatchers.Default) { FoodSearch.search(query, foods, names) }
    }

    details?.let { food ->
        BackTo { details = null }
        FoodDetailScreen(food, onBack = { details = null })
        return
    }
    BackTo(onBack = onBack)

    fun quick(food: Food) = onPick(Portion(food = food, quantity = QuickLog.lastQuantity(food.id, store.data.logs) ?: 1.0))

    LeanrScreen(title, onBack = onBack) {
        item { SearchField(query, { query = it }, "Search foods and restaurants", Modifier.padding(bottom = 16.dp)) }
        if (query.isBlank()) {
            val pinned = store.pinnedFoods
            val recent = QuickLog.recentFoods(store.data.logs)
            val mine = store.data.foods.filter { it.isValid }.sortedBy { it.name.lowercase() }
            if (pinned.isEmpty() && recent.isEmpty() && mine.isEmpty()) {
                item { LeanrSection { SectionText("Search for a food, a menu item or a restaurant.") } }
            }
            listOf("Pinned" to pinned, "Recent" to recent, "My foods" to mine).forEach { (header, foods) ->
                if (foods.isNotEmpty()) item(key = "picker-$header") {
                    LeanrSection(header) {
                        foods.forEachIndexed { i, food ->
                            FoodRow(food, quickAddLabel = quickAddLabel, divider = i < foods.size - 1, onQuickAdd = { quick(food) }, onClick = { asking = food })
                        }
                    }
                }
            }
        } else {
            item(key = "picker-results") {
                LeanrSection {
                    if (results.isEmpty()) SectionText(if (store.foodsLoaded) "No foods match “${query.trim()}”." else "Loading foods…")
                    results.forEachIndexed { i, food ->
                        FoodRow(food, quickAddLabel = quickAddLabel, divider = i < results.size - 1, onQuickAdd = { quick(food) }, onClick = { asking = food })
                    }
                }
            }
        }
    }

    asking?.let { food ->
        ServingsDialog(food, pickTitle, onDetails = { details = food; asking = null }, onDismiss = { asking = null }) { onPick(it) }
    }
}

/** How many servings of a food, with its figures, before logging, planning or adding it. */
@Composable
internal fun ServingsDialog(food: Food, actionTitle: String, onDetails: (() -> Unit)? = null, onDismiss: () -> Unit, onConfirm: (Portion) -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    var servings by remember(food.id) { mutableStateOf(QuickLog.lastQuantity(food.id, store.data.logs) ?: 1.0) }
    val valid = servings.isFinite() && servings > 0 && servings <= 10000
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(food.name, style = LeanrType.headline) },
        text = {
            Column {
                Text("${store.chainName(food.chain)} · ${food.serve}", style = LeanrType.caption, color = c.secondaryText)
                NumberField("Servings", servings, { servings = it }, divider = false)
                Text(Nutrition(listOf(Portion(food = food, quantity = servings))).text, style = LeanrType.caption, color = c.secondaryText)
                if (onDetails != null) TextButton(onClick = onDetails) { Text("Nutrition details", color = c.accent) }
            }
        },
        confirmButton = {
            TextButton(enabled = valid, onClick = { onDismiss(); onConfirm(Portion(food = food, quantity = servings)) }) {
                Text(actionTitle, color = if (valid) c.accent else c.tertiaryText)
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
