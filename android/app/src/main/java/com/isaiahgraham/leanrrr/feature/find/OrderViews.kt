package com.isaiahgraham.leanrrr.feature.find

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.mealText
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.ui.AppTab
import com.isaiahgraham.leanrrr.ui.components.FoodRow
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.components.NutritionView
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType

/** A filled accent button for the bottom bars and cards (borderedProminent). */
@Composable
fun ProminentButton(title: String, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    val c = Leanr.colours
    Button(onClick = onClick, enabled = enabled, modifier = modifier.heightIn(min = 44.dp), shape = RoundedCornerShape(12.dp),
        colors = ButtonDefaults.buttonColors(containerColor = c.accent, contentColor = if (c.dark) Color.Black else Color.White)) {
        Text(title, style = LeanrType.headline, maxLines = 1)
    }
}

/** An outlined accent button (bordered). */
@Composable
fun BorderedButton(title: String, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    val c = Leanr.colours
    OutlinedButton(onClick = onClick, enabled = enabled, modifier = modifier.heightIn(min = 44.dp), shape = RoundedCornerShape(12.dp),
        colors = ButtonDefaults.outlinedButtonColors(contentColor = c.accent)) {
        Text(title, style = LeanrType.headline, maxLines = 1)
    }
}

/** The bar pinned under a screen's list, for its main action (safeAreaInset + BottomActionBar). */
@Composable
fun ActionBar(content: @Composable RowScope.() -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp), content = content)
}

/** "Forgot it yesterday?" choices in a menu, for a meal that was forgotten (YesterdayMenu). */
@Composable
fun YesterdayMenuItems(onLog: (MealTime) -> Unit, dismiss: () -> Unit) {
    Text("Forgot it yesterday?", style = LeanrType.caption, color = Leanr.colours.secondaryText, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
    MealTime.entries.forEach { meal ->
        DropdownMenuItem(text = { Text("Yesterday’s ${meal.title.lowercase()}") }, onClick = { dismiss(); onLog(meal) })
    }
}

/** One suggested order: where, what, whether it meets protein, and buttons to log or share it. */
@Composable
fun OrderMatchCard(match: MealMatch, protein: Double?, mealTime: MealTime? = null, onOpen: (() -> Unit)? = null) {
    val store = AppServices.store
    val c = Leanr.colours
    val context = LocalContext.current
    var more by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().padding(top = 14.dp, bottom = 10.dp)) {
        Row(Modifier.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(store.chainName(match.chain).uppercase(), style = LeanrType.caption.copy(fontWeight = FontWeight.SemiBold), color = c.secondaryText, modifier = Modifier.weight(1f))
            if (protein != null) {
                val met = match.total.p >= protein
                Pill(if (met) "Protein target met" else "${(protein - match.total.p).number} g short", if (met) c.reached else Leanr.orange)
            }
        }
        Row(Modifier.fillMaxWidth().then(if (onOpen != null) Modifier.clickable(onClick = onOpen) else Modifier).padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Text(match.name, style = LeanrType.headline, color = c.text, modifier = Modifier.weight(1f))
            if (onOpen != null) Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, "Order details", tint = c.tertiaryText)
        }
        if (match.customised > 0) {
            Row(Modifier.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Tune, null, tint = c.secondaryText, modifier = Modifier.size(14.dp))
                Spacer(Modifier.width(6.dp))
                Text("Ask for these changes when you order", style = LeanrType.caption, color = c.secondaryText)
            }
        }
        NutritionView(match.total, details = false)
        Row(Modifier.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ProminentButton("Log it") { store.logNow(match.items, match.name, mealTime ?: MealTime.suggested()) }
            BorderedButton("Add to meal") { store.add(match.items) }
            IconButton(onClick = { shareText(context, mealText("Suggested order", match.items)) }) { Icon(Icons.Filled.Share, "Share order", tint = c.accent) }
            Box {
                IconButton(onClick = { more = true }) { Icon(Icons.Filled.MoreVert, "More ways to log", tint = c.accent) }
                DropdownMenu(expanded = more, onDismissRequest = { more = false }) {
                    YesterdayMenuItems({ store.logNow(match.items, match.name, it, yesterday = true) }) { more = false }
                }
            }
        }
    }
}

/** A suggested order from Find: its items, nutrition and where to get it (OrderDetailView). */
@Composable
fun OrderDetailScreen(match: MealMatch, onBack: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    val context = LocalContext.current
    var food by remember { mutableStateOf<Food?>(null) }
    food?.let { FoodDetailScreen(it, onBack = { food = null }); return }
    BackHandler(onBack = onBack)
    LeanrScreen("Order", onBack = onBack, actions = {
        IconButton(onClick = { shareText(context, mealText("Suggested order", match.items)) }) { Icon(Icons.Filled.Share, "Share order", tint = c.accent) }
    }, bottomBar = {
        ActionBar {
            ProminentButton("Log it · ${match.total.cal.number} Cal", Modifier.weight(1f)) { store.logNow(match.items, match.name) }
            BorderedButton("Add to meal") { store.add(match.items) }
        }
    }) {
        item {
            LeanrSection {
                Column(Modifier.padding(16.dp)) {
                    Text(match.name, style = LeanrType.title2Display, color = c.text)
                    Text(store.chainName(match.chain), style = LeanrType.body, color = c.secondaryText)
                }
            }
        }
        item { LeanrSection("Nutrition") { NutritionView(match.total) } }
        item { NearestPlaceSection(match.chain) }
        item {
            LeanrSection("Items", footer = if (match.customised > 0) "Ask for the changes listed after each item’s name when you order. They use ${store.chainName(match.chain).possessive} own figures for each part, so check the food's details for how each was worked out." else null) {
                match.items.forEachIndexed { i, item -> FoodRow(item.food, divider = i < match.items.size - 1, onClick = { food = item.food }) }
            }
        }
    }
}

/**
 * The closest restaurant of a chain. Finding places belongs to the Map tab, so this hands over to it (NearestPlaceSection).
 */
@Composable
fun NearestPlaceSection(chain: String) {
    val store = AppServices.store
    if (chain == "mine" || chain == Food.EVERYDAY || chain == Food.COMMUNITY || store.chain(chain) == null) return
    val name = store.chainName(chain)
    LeanrSection("Nearest $name") {
        ActionRow("Find the nearest $name", Icons.Filled.LocationOn, divider = false) {
            AppServices.nav.tab = AppTab.MAP
        }
    }
}

/** A thin divider between rows, inset like a list's. */
@Composable
fun RowDivider() = HorizontalDivider(Modifier.padding(start = 16.dp), color = Leanr.colours.separator, thickness = 0.5.dp)
