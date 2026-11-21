package com.isaiahgraham.leanrrr.feature.find

import androidx.activity.compose.BackHandler
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BookmarkBorder
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.nutrientNames
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.data.tenth
import com.isaiahgraham.leanrrr.ui.components.Chip
import com.isaiahgraham.leanrrr.ui.components.ChipRow
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlin.math.abs

private const val COPYCAT_NOTES = "Shop figures are each chain's published ones. Home figures add up every ingredient by weight from USDA FoodData Central, so your own products will differ a little. These are unofficial recipes, not made or approved by any chain named here."

private fun copycatChange(value: Int): String = if (value == 0) "level" else "${if (value > 0) "+" else "−"}${abs(value)}%"

/** Copycat Kitchen (CopycatKitchenView): home versions of takeaway items, ranked against the chains' own figures. */
@Composable
fun CopycatKitchenScreen(onBack: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    var sort by remember { mutableStateOf(CopycatSort.SAVING) }
    var open by remember { mutableStateOf<CopycatComparison?>(null) }
    val items = remember(store.catalog) { CopycatBook.bundled.comparisons(store.catalog.foods) }
    open?.let { CopycatRecipeScreen(it, onBack = { open = null }); return }
    BackHandler(onBack = onBack)
    LeanrScreen("Copycat Kitchen", onBack = onBack) {
        item {
            LeanrSection {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("${items.count { it.verdict == CopycatVerdict.HOME_LIGHTER }} of ${items.size} beat the shop", style = LeanrType.title3.copy(fontWeight = FontWeight.Bold), color = c.text)
                    Text("Cooked as written. With every swap on, ${items.count { CopycatVerdict.of(it.change(it.lean)) == CopycatVerdict.HOME_LIGHTER }} do.", style = LeanrType.subheadline, color = c.secondaryText)
                }
            }
        }
        item { ChipRow(Modifier.padding(bottom = 16.dp)) { CopycatSort.entries.forEach { option -> Chip(option.title, sort == option) { sort = option } } } }
        item {
            LeanrSection(footer = COPYCAT_NOTES) {
                val sorted = sort.sorted(items)
                sorted.forEachIndexed { i, item ->
                    CopycatListRow(item) { open = item }
                    if (i < sorted.size - 1) RowDivider()
                }
            }
        }
    }
}

@Composable
private fun CopycatListRow(item: CopycatComparison, onClick: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    Column(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(item.shopName, style = LeanrType.headline, color = c.text, modifier = Modifier.weight(1f))
            Spacer(Modifier.width(4.dp))
            VerdictPill(item.verdict)
        }
        Text("${store.chainName(item.shopFood.chain)} · ${item.recipe.name}", style = LeanrType.caption, color = c.secondaryText)
        Row {
            CopycatColumn("Shop", item.shop, null, Modifier.weight(1f))
            CopycatColumn("Home", item.home, item.change(item.home), Modifier.weight(1f))
            CopycatColumn("Swaps", item.lean, item.change(item.lean), Modifier.weight(1f))
        }
    }
}

@Composable
private fun CopycatColumn(title: String, total: Nutrition, change: Int?, modifier: Modifier) {
    val c = Leanr.colours
    Column(modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(title, style = LeanrType.caption, color = c.secondaryText)
        Text(total.cal.rounded().number, style = LeanrType.headline, color = c.text)
        Text(change?.let(::copycatChange) ?: "Cal", style = LeanrType.caption, color = c.secondaryText)
    }
}

@Composable
private fun VerdictPill(verdict: CopycatVerdict) {
    val c = Leanr.colours
    val colour = when (verdict) {
        CopycatVerdict.HOME_LIGHTER -> c.accent
        CopycatVerdict.SHOP_LIGHTER -> Leanr.orange
        CopycatVerdict.LEVEL -> c.secondaryText
    }
    Pill(verdict.title, colour, background = c.text.copy(alpha = 0.06f))
}

/** One home recipe beside the shop's figures, with swaps that change the numbers as you tick them (CopycatRecipeView). */
@Composable
fun CopycatRecipeScreen(item: CopycatComparison, onBack: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    val context = LocalContext.current
    val book = CopycatBook.bundled
    val recipe = item.recipe
    var swaps by remember { mutableStateOf(emptySet<String>()) }
    var serves by remember { mutableIntStateOf(recipe.serves) }
    var logging by remember { mutableStateOf<Food?>(null) }
    val total = book.nutrition(recipe, swaps)
    val food = book.food(recipe, swaps, item.shopName)
    val rows = recipe.rows(swaps)
    fun gramText(grams: Double) = "${if (grams < 10) grams.tenth.number else grams.rounded().number} g"
    val shoppingList = (listOf("${recipe.name}, $serves ${if (serves == 1) "serve" else "serves"}") + rows.map { "${it.label}: ${gramText(it.g * serves)}" }).joinToString("\n")

    logging?.let { FoodDetailScreen(it, onBack = { logging = null }); return }
    BackHandler(onBack = onBack)
    LeanrScreen(recipe.name, onBack = onBack, actions = {
        IconButton(onClick = { store.saveToMyFoods(food)?.let { store.notice = "Saved ${it.name} to My foods" } }) {
            Icon(Icons.Filled.BookmarkBorder, "Save to My foods", tint = c.accent)
        }
    }, bottomBar = {
        ActionBar { ProminentButton("Log it · ${total.cal.rounded().number} Cal", Modifier.weight(1f)) { logging = food } }
    }) {
        item {
            LeanrSection {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Home version of ${store.chainName(item.shopFood.chain)} ${item.shopName} · ${recipe.time}", style = LeanrType.caption, color = c.secondaryText)
                    Text(recipe.hook, style = LeanrType.body, color = c.text)
                    Text(recipe.verdict, style = LeanrType.subheadline, color = c.secondaryText)
                }
            }
        }
        item {
            LeanrSection("Shop vs home, ${recipe.serving}") {
                CopycatComparisonView(item.shop, total)
                if (item.shopFood.mismatch) Row(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Warning, null, tint = Leanr.orange, modifier = Modifier.size(14.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("${store.chainName(item.shopFood.chain)} publishes an energy figure that doesn’t match its own macros, so compare the macros here.", style = LeanrType.caption, color = Leanr.orange)
                }
            }
        }
        item {
            LeanrSection("Make it lighter") {
                recipe.swaps.forEachIndexed { i, swap ->
                    SwitchRow(swap.label, swap.id in swaps, { on -> swaps = if (on) swaps + swap.id else swaps - swap.id }, subtitle = swap.why, divider = i < recipe.swaps.size - 1)
                }
            }
        }
        item {
            LeanrSection("Ingredients", footer = "Weights are raw and for all serves; measures are for one. Flour and crumbs count what sticks to the food, not what's left in the bowl.") {
                StepperRow("$serves ${if (serves == 1) "serve" else "serves"}", serves, 1..12, { serves = it })
                rows.forEach { row ->
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 9.dp), verticalAlignment = Alignment.Top) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(row.label, style = LeanrType.subheadline.copy(fontWeight = FontWeight.Medium), color = if (row.swapped) c.accent else c.text)
                            Text(row.measure, style = LeanrType.caption, color = c.secondaryText)
                        }
                        Spacer(Modifier.width(8.dp))
                        Text(gramText(row.g * serves), style = LeanrType.subheadline, color = c.text)
                    }
                    RowDivider()
                }
                ActionRow("Share shopping list", Icons.Filled.ShoppingCart, divider = false) { shareText(context, shoppingList) }
            }
        }
        item {
            LeanrSection("Method", footer = "Take chicken to 75°C and mince to 71°C in the centre. Fat that renders out of mince isn't taken off, so burger figures run slightly high.") {
                recipe.method.forEachIndexed { index, step ->
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 9.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text("${index + 1}", style = LeanrType.display(20f), color = c.accent)
                        Text(step, style = LeanrType.body, color = c.text, modifier = Modifier.weight(1f))
                    }
                    if (index < recipe.method.size - 1) RowDivider()
                }
            }
        }
    }
}

/** Shop and home side by side: a grey bar for the shop, the macro's own colour for home. */
@Composable
private fun CopycatComparisonView(shop: Nutrition, home: Nutrition) {
    val c = Leanr.colours
    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        CopycatBar("Calories", shop.cal, home.cal, "Cal", false, c.accent)
        CopycatBar("Protein", shop.p, home.p, "g", true, c.protein)
        CopycatBar("Carbs", shop.c, home.c, "g", null, c.carbs)
        CopycatBar("Fat", shop.f, home.f, "g", false, c.fat)
        androidx.compose.material3.HorizontalDivider(color = c.separator, thickness = 0.5.dp)
        Row {
            Spacer(Modifier.weight(1f))
            Text("Shop", style = LeanrType.caption, color = c.secondaryText, textAlign = TextAlign.End, modifier = Modifier.width(88.dp))
            Text("Home", style = LeanrType.caption, color = c.secondaryText, textAlign = TextAlign.End, modifier = Modifier.width(88.dp))
        }
        nutrientNames.drop(4).filter { it.key in listOf("sat", "sugar", "fibre", "sodium") }.forEach { n ->
            Row {
                Text(n.label, style = LeanrType.caption, color = c.text, modifier = Modifier.weight(1f))
                val s = shop.nut[n.key]
                Text(s?.let { "${it.number} ${n.unit}" } ?: "Not published", style = LeanrType.caption, color = if (s == null) c.secondaryText else c.text,
                    textAlign = TextAlign.End, maxLines = 1, modifier = Modifier.width(88.dp))
                val h = home.nut[n.key] ?: 0.0
                Text("${if (n.key == "sodium") h.rounded().number else h.number}${if (n.key in home.partial) "+" else ""} ${n.unit}", style = LeanrType.caption, color = c.text,
                    textAlign = TextAlign.End, maxLines = 1, modifier = Modifier.width(88.dp))
            }
        }
    }
}

/** One nutrient: shop bar, home bar, and the gap, coloured by whether home is better (`higherBetter`; null for neither). */
@Composable
private fun CopycatBar(title: String, shop: Double, home: Double, unit: String, higherBetter: Boolean?, fill: Color) {
    val c = Leanr.colours
    val close = abs(home - shop) < maxOf(shop, home) * 0.02
    val gapColour = if (higherBetter == null || close) c.secondaryText else if (higherBetter == (home > shop)) c.accent else Leanr.orange
    val gapText = if (close) "level" else "${if (home > shop) "+" else "−"}${abs(home - shop).rounded().number} $unit"
    val top = maxOf(shop, home, 1.0)
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row {
            Text(title, style = LeanrType.subheadline.copy(fontWeight = FontWeight.Medium), color = c.text, modifier = Modifier.weight(1f))
            Text(gapText, style = LeanrType.label, color = gapColour)
        }
        for ((value, colour) in listOf(shop to c.text.copy(alpha = 0.18f), home to fill)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.weight(1f).height(6.dp)) {
                    Box(Modifier.fillMaxWidth((value / top).toFloat().coerceIn(0f, 1f)).fillMaxHeight().clip(CircleShape).background(colour))
                }
                Text("${value.rounded().number} $unit", style = LeanrType.caption, color = c.text, textAlign = TextAlign.End, maxLines = 1, modifier = Modifier.widthIn(min = 72.dp))
            }
        }
    }
}
