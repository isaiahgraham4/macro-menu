package com.isaiahgraham.leanrrr.feature.find

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowCircleDown
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlin.math.abs

/** Lower-calorie swaps for an item in the meal being built (MealSwaps.swift). */
object MealSwaps {
    fun options(portion: Portion, foods: List<Food>): List<Food> {
        if (!portion.isValid || portion.food.chain == "mine" || portion.food.isEveryday) return emptyList()
        val original = portion.food
        return foods.filter {
            it.isValid && it.id != original.id && it.chain == original.chain && it.cat == original.cat && (original.cal - it.cal) * portion.quantity >= 20
        }.sortedWith { a, b ->
            // Prefer alternatives that retain protein, then compare calorie savings.
            val ra = a.p >= original.p * 0.8; val rb = b.p >= original.p * 0.8
            when {
                ra != rb -> if (ra) -1 else 1
                a.cal != b.cal -> a.cal.compareTo(b.cal)
                else -> a.id.compareTo(b.id)
            }
        }.take(12)
    }
}

/** Smarter swaps (MealSwapsView): lower-calorie alternatives for one item in the meal being built, by its portion ID. */
@Composable
fun MealSwapsScreen(portionId: String, onBack: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    BackHandler(onBack = onBack)
    val portion = store.data.tray.firstOrNull { it.id == portionId }
    LeanrScreen("Smarter swaps", onBack = onBack) {
        if (portion == null) {
            item { LeanrSection { EmptyState("Meal item removed", "Return to your meal to choose another item.", Icons.Filled.Restaurant) } }
            return@LeanrScreen
        }
        item {
            LeanrSection("Your current choice") {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(portion.food.name, style = LeanrType.headline, color = c.text)
                    Text("${(portion.food.cal * portion.quantity).number} Cal · ${(portion.food.p * portion.quantity).number} g protein", style = LeanrType.body, color = c.text)
                    Text("${store.chainName(portion.food.chain)} · × ${portion.quantity.number}", style = LeanrType.caption, color = c.secondaryText)
                }
            }
        }
        val options = MealSwaps.options(portion, store.catalog.foods)
        if (options.isEmpty()) {
            item {
                LeanrSection {
                    EmptyState("No lower-calorie swaps", "We couldn't find an alternative with at least 20 fewer calories in this restaurant's menu category.", Icons.Filled.SwapHoriz)
                }
            }
        } else {
            item {
                LeanrSection("Lower-calorie alternatives", footer = "Same restaurant and menu category. Your quantity stays the same; serving sizes and ingredients may differ. Alternatives retaining at least 80% of the original protein appear first. Customisations aren't carried over.") {
                    options.forEachIndexed { i, food ->
                        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(food.name, style = LeanrType.headline, color = c.text)
                            Text("× ${portion.quantity.number} · ${food.serve} each", style = LeanrType.caption, color = c.secondaryText)
                            Text("${(food.cal * portion.quantity).number} Cal · ${(food.p * portion.quantity).number} g protein", style = LeanrType.body, color = c.text)
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Filled.ArrowCircleDown, null, tint = c.accent, modifier = Modifier.size(18.dp))
                                Spacer(Modifier.width(6.dp))
                                Text("${((portion.food.cal - food.cal) * portion.quantity).number} fewer Cal", style = LeanrType.body, color = c.accent)
                            }
                            val proteinChange = (food.p - portion.food.p) * portion.quantity
                            Text(if (proteinChange == 0.0) "Same protein" else "${abs(proteinChange).number} g ${if (proteinChange > 0) "more" else "less"} protein",
                                style = LeanrType.subheadline, color = c.secondaryText)
                            BorderedButton("Use this swap") {
                                val swapped = store.change { state ->
                                    state.copy(tray = state.tray.map { if (it.id == portionId) it.copy(food = food) else it })
                                }
                                if (swapped) { store.notice = "Swapped to ${food.name}"; onBack() }
                            }
                        }
                        if (i < options.size - 1) RowDivider()
                    }
                }
            }
        }
    }
}
