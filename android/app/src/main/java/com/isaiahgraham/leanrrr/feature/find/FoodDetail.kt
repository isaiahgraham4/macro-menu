package com.isaiahgraham.leanrrr.feature.find

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.AddCircleOutline
import androidx.compose.material.icons.filled.BookmarkBorder
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.OutdoorGrill
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.RemoveCircleOutline
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.billing.Premium
import com.isaiahgraham.leanrrr.data.Chain
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.Modifier as FoodModifier
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.mealText
import com.isaiahgraham.leanrrr.data.newId
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.data.recipesBrokenUp
import com.isaiahgraham.leanrrr.data.tenth
import com.isaiahgraham.leanrrr.feature.meal.ContentFilter
import com.isaiahgraham.leanrrr.feature.meal.FoodEditorScreen
import com.isaiahgraham.leanrrr.feature.meal.OffensiveTextNote
import com.isaiahgraham.leanrrr.feature.meal.RecipeEditorScreen
import com.isaiahgraham.leanrrr.feature.settings.PremiumSheet
import com.isaiahgraham.leanrrr.feature.today.plan
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.components.NumberField
import com.isaiahgraham.leanrrr.ui.components.NutritionView
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/**
 * One food's details (FoodDetailView.swift): nutrition for your portion, servings or grams, removals, extras and swaps, pinning,
 * logging, adding to the meal and planning ahead. Other features open foods with this.
 *
 * With `pick`, the button hands the portion back instead (titled `pickTitle`). `logYesterday` and `logMeal` set where the log
 * button goes by default.
 */
@Composable
fun FoodDetailScreen(
    food: Food,
    onBack: () -> Unit,
    pick: ((Portion) -> Unit)? = null,
    pickTitle: String = "Use this portion",
    logYesterday: Boolean = false,
    logMeal: MealTime? = null,
) {
    val store = AppServices.store
    val c = Leanr.colours
    val context = LocalContext.current
    // One of your own foods or recipes shows its latest figures, so an edit appears here at once.
    val current = if (food.chain == "mine") store.data.foods.firstOrNull { it.id == food.id } ?: food else food
    val editable = current.chain == "mine" && store.data.foods.any { it.id == current.id }

    var quantity by remember { mutableDoubleStateOf(1.0) }
    var useWeight by remember { mutableStateOf(false) }
    var weight by remember { mutableDoubleStateOf(100.0) }
    var portionFields by remember { mutableStateOf(0) }
    var changes by remember { mutableStateOf(emptyMap<String, Double>()) }
    var customName by remember { mutableStateOf("") }
    var ownAdjustment by remember { mutableStateOf<Food?>(null) }
    var subtract by remember { mutableStateOf(false) }
    var pinnedCustom by remember { mutableStateOf<Food?>(null) }
    var editing by remember { mutableStateOf(false) }
    var editingAdjustment by remember { mutableStateOf(false) }
    var copycat by remember { mutableStateOf<CopycatComparison?>(null) }
    var premium by remember { mutableStateOf(false) }
    var moreMenu by remember { mutableStateOf(false) }
    var shareMenu by remember { mutableStateOf(false) }
    val open = remember { mutableStateOf(emptySet<String>()) }

    val adjusted = current.customised(changes, ownAdjustment, subtract, customName)
    val amount = if (useWeight) weight / (current.servingWeight?.first ?: 100.0) else quantity
    val portion = Portion(food = adjusted, quantity = amount)
    val customized = changes.values.any { it > 0 } || ownAdjustment != null
    val nameFlagged = ContentFilter.flags(listOf(customName))
    /** "McDonald's", "Hungry Jack's" or "KFC's", for "… energy" and "… figures". */
    val owner = store.chainName(current.chain).possessive
    val portionCal = Nutrition(listOf(portion)).cal

    fun pinnable(): Food {
        val pinned = pinnedCustom
        if (pinned != null && pinned.name == adjusted.name && pinned.kj == adjusted.kj) return pinned
        return adjusted.copy(id = newId())
    }
    fun value(): Portion = if (customized) portion.copy(food = portion.food.copy(id = newId())) else portion
    fun addPortion() {
        val v = value()
        if (pick != null) pick(v) else { store.add(listOf(v)); onBack() }
    }
    fun logPortion(meal: MealTime, yesterday: Boolean) {
        val v = value()
        if (store.logNow(listOf(v), v.food.name, meal, yesterday)) onBack()
    }
    fun planPortion(meal: MealTime) {
        // Plan ahead is part of Even Leanrrr.
        if (!Premium.isUnlocked) { premium = true; return }
        val v = value()
        if (store.plan(listOf(v), v.food.name, meal, LocalDate.now().plusDays(1))) store.notice = "Planned for tomorrow’s ${meal.title.lowercase()}"
    }
    fun saveCustom() {
        if (store.saveFood(adjusted.copy(id = newId(), chain = "mine"))) store.notice = "Custom order saved"
    }
    /** On/off options (removals and swaps); turning one on clears others in the same group. */
    fun select(mod: FoodModifier, enabled: Boolean) {
        val next = changes.toMutableMap()
        if (enabled && mod.group != null) for (other in current.modifiers ?: emptyList()) if (other.group == mod.group) next[other.key] = 0.0
        next[mod.key] = if (enabled) 1.0 else 0.0
        changes = next
    }

    if (editing) {
        if (current.ingredients != null) RecipeEditorScreen(current, onClose = { editing = false })
        else FoodEditorScreen(current, onDone = { editing = false })
        return
    }
    if (editingAdjustment) {
        FoodEditorScreen(null, onDone = { result -> if (result != null) ownAdjustment = result; editingAdjustment = false }, save = null)
        return
    }
    copycat?.let { CopycatRecipeScreen(it, onBack = { copycat = null }); return }
    BackHandler(onBack = onBack)

    LeanrScreen("Food details", onBack = onBack, actions = {
        if (editable) TextButton(onClick = { editing = true }) { Text(if (current.ingredients != null) "Edit recipe" else "Edit", color = c.accent) }
        // A custom order is pinned as it's set up now, as its own food.
        val target = if (customized) pinnable() else current
        val pinned = store.isPinned(target)
        IconButton(onClick = { store.togglePin(target); if (customized) pinnedCustom = if (pinned) null else target }) {
            Icon(if (pinned) Icons.Filled.PushPin else Icons.Outlined.PushPin, if (pinned) "Unpin" else "Pin to top", tint = c.accent)
        }
        Box {
            IconButton(onClick = { shareMenu = true }) { Icon(Icons.Filled.Share, "Share", tint = c.accent) }
            DropdownMenu(expanded = shareMenu, onDismissRequest = { shareMenu = false }) {
                DropdownMenuItem(text = { Text("Share as text") }, onClick = { shareMenu = false; shareText(context, mealText(adjusted.name, listOf(portion))) })
            }
        }
    }, bottomBar = {
        ActionBar {
            val enabled = portion.isValid && !nameFlagged
            if (pick != null) {
                ProminentButton("$pickTitle · ${portionCal.number} Cal", Modifier.weight(1f), enabled) { addPortion() }
            } else {
                val suggested = logMeal ?: MealTime.suggested()
                ProminentButton("Log to ${if (logYesterday) "yesterday’s ${suggested.title.lowercase()}" else suggested.title} · ${portionCal.number} Cal", Modifier.weight(1f), enabled) {
                    logPortion(suggested, logYesterday)
                }
                Box {
                    IconButton(onClick = { moreMenu = true }, enabled = enabled) { Icon(Icons.Filled.MoreHoriz, "More ways to add", tint = if (enabled) c.accent else c.tertiaryText) }
                    DropdownMenu(expanded = moreMenu, onDismissRequest = { moreMenu = false }) {
                        Text("Today", style = LeanrType.caption, color = c.secondaryText, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
                        MealTime.entries.filter { logYesterday || it != suggested }.forEach { meal ->
                            DropdownMenuItem(text = { Text(meal.title) }, onClick = { moreMenu = false; logPortion(meal, false) })
                        }
                        HorizontalDivider()
                        YesterdayMenuItems({ logPortion(it, true) }) { moreMenu = false }
                        HorizontalDivider()
                        Text("Plan ahead", style = LeanrType.caption, color = c.secondaryText, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
                        MealTime.entries.forEach { meal ->
                            DropdownMenuItem(text = { Text("Tomorrow’s ${meal.title.lowercase()}") }, leadingIcon = { Icon(Icons.Filled.CalendarMonth, null) },
                                onClick = { moreMenu = false; planPortion(meal) })
                        }
                        HorizontalDivider()
                        DropdownMenuItem(text = { Text("Add to the meal I'm building") }, leadingIcon = { Icon(Icons.Filled.Restaurant, null) },
                            onClick = { moreMenu = false; addPortion() })
                    }
                }
            }
        }
    }) {
        item {
            LeanrSection {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(current.name, style = LeanrType.title2Display, color = c.text)
                    val chain = store.chainName(current.chain)
                    Text(if (current.serve.isEmpty()) chain else "$chain · ${current.serve}", style = LeanrType.body, color = c.secondaryText)
                    current.note?.let { Text(it, style = LeanrType.caption, color = c.text, modifier = Modifier.padding(top = 4.dp)) }
                    if (current.mismatch) Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 4.dp)) {
                        Icon(Icons.Filled.Warning, null, tint = Leanr.orange, modifier = Modifier.size(14.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Published energy doesn’t match the listed macros.", style = LeanrType.caption, color = Leanr.orange)
                    }
                }
            }
        }
        if (current.isCommunity) {
            item {
                LeanrSection("Shared by a Leanrrr user", footer = "Leanrrr hasn't checked these figures. Compare them with the label before relying on them.") {
                    ActionRow("Save a copy to My foods", Icons.Filled.BookmarkBorder, divider = false) {
                        if (store.saveToMyFoods(current) != null) store.notice = "Saved to My foods"
                    }
                }
            }
        } else if (editable && current.shared == true) {
            item {
                LeanrSection(footer = "Edit the food to stop sharing it. Deleting it takes it down too.") {
                    Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.People, null, tint = c.accent, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text("Shared with other Leanrrr users", style = LeanrType.subheadline, color = c.text)
                    }
                }
            }
        }
        item { LeanrSection("Nutrition for your portion") { NutritionView(Nutrition(listOf(portion))) } }
        portion.ingredientPortions?.let { ingredients ->
            item {
                val servings = current.recipeYield
                LeanrSection("Ingredients in your portion", footer = if (servings != null && servings != 1.0) "The whole recipe makes ${servings.number} servings." else null) {
                    IngredientRows(recipesBrokenUp(ingredients))
                }
            }
        }
        item {
            LeanrSection("Portion") {
                val serving = current.servingWeight
                if (serving != null) {
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp)) {
                        listOf(false to "Servings", true to (if (serving.second == "g") "Grams" else "mL")).forEachIndexed { i, (byWeight, label) ->
                            SegmentedButton(selected = useWeight == byWeight, shape = SegmentedButtonDefaults.itemShape(i, 2),
                                colors = SegmentedButtonDefaults.colors(activeContainerColor = c.accent.copy(alpha = 0.16f), activeContentColor = c.text),
                                onClick = {
                                    if (byWeight == useWeight) return@SegmentedButton
                                    // Start from one serving's weight, so switching doesn't change the portion.
                                    if (byWeight) weight = (serving.first * quantity).tenth else quantity = ((weight / serving.first) * 100).rounded() / 100
                                    useWeight = byWeight; portionFields++
                                }) { Text(label, style = LeanrType.subheadline) }
                        }
                    }
                }
                key(portionFields, useWeight) {
                    if (serving != null && useWeight) NumberField("Amount (${serving.second})", weight, { weight = it })
                    else NumberField("Servings", quantity, { quantity = it })
                }
                Text("${amount.number} × ${current.serve}", style = LeanrType.caption, color = c.secondaryText, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
            }
        }
        if (current.chain != "mine" && !current.isEveryday && !current.isCommunity) {
            val mods = current.modifiers ?: emptyList()
            val removals = mods.filter { it.kind == "r" }
            if (removals.isNotEmpty()) {
                item {
                    val footer = when {
                        current.chain == "grilld" -> "Sauce removals are estimates: Grill'd's own figures for that sauce sold as a dip, for about 15 g, since Grill'd doesn't publish how much goes on each burger. Other removals are the difference between burgers Grill'd publishes."
                        removals.any { it.est == true } -> "Calories for each ingredient are from ${store.chainName(current.chain)}. For parts it doesn't sell on their own, protein, carbs and fat are estimated from the ingredient type and other nutrients stay as listed."
                        current.chain in listOf("hj", "kfc", "rr", "oporto") -> "Worked out from $owner figures for the same item with and without it."
                        else -> "Nutrition for each ingredient is from $owner published figures."
                    }
                    LeanrSection("Remove ingredients", footer = footer) {
                        removals.forEachIndexed { i, mod ->
                            SwitchRow(mod.name, (changes[mod.key] ?: 0.0) > 0, { select(mod, it) }, trailingText = "${(mod.kj / 4.184).rounded().number} Cal", divider = i < removals.size - 1)
                        }
                    }
                }
            }
            val additions = mods.filter { it.kind == "f" || it.kind == "a" }
            item {
                val footer = when {
                    additions.any { it.est == true } -> "Extras use $owner energy for that ingredient. For parts it doesn't sell on their own, protein, carbs and fat are estimated from the ingredient type."
                    current.chain == "grilld" && mods.any { it.kind == "s" } -> "Bun and patty swaps and extras are the difference between burgers Grill'd publishes. Grill'd doesn't publish single ingredients, so use Remove something else for anything else."
                    current.chain == "nandos" && mods.any { it.kind == "s" } -> "Swaps are the difference between Nando's own figures for this item with each protein and style. Extras use Nando's figures for each one."
                    current.chain in listOf("hj", "kfc", "rr", "oporto") && additions.any { !it.key.startsWith("item:") } -> "Extras are the difference between two ${store.chainName(current.chain)} items sold with and without them."
                    additions.any { it.key.startsWith("item:") && it.kind == "f" } -> "Extra fillets use $owner figures for the fillet sold on its own."
                    else -> null
                }
                LeanrSection("Customise your order", footer = footer) {
                    for ((kind, label) in listOf("f" to "Extra filling", "a" to "Extras", "s" to "Swaps")) {
                        val group = mods.filter { it.kind == kind }
                        if (group.isEmpty()) continue
                        val expanded = kind in open.value
                        DisclosureRow(label, expanded, { open.value = if (expanded) open.value - kind else open.value + kind })
                        if (expanded) group.forEach { mod ->
                            if (kind == "s") SwitchRow(mod.name, (changes[mod.key] ?: 0.0) > 0, { select(mod, it) })
                            else {
                                val count = (changes[mod.key] ?: 0.0).toInt()
                                StepperRow("${mod.name} · ${count.toDouble().number}", count, 0..5, { changes = changes + (mod.key to it.toDouble()) },
                                    subtitle = "+${(mod.kj / 4.184).rounded().number} Cal each")
                            }
                        }
                    }
                    val adjustment = ownAdjustment
                    if (adjustment != null) {
                        Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp, top = 4.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text((if (subtract) "Without " else "Extra ") + adjustment.name, style = LeanrType.body, color = c.text, modifier = Modifier.weight(1f))
                            TextButton(onClick = { ownAdjustment = null }) { Text("Undo", color = c.over) }
                        }
                    } else {
                        ActionRow("Remove something else", Icons.Filled.RemoveCircleOutline) { subtract = true; editingAdjustment = true }
                        ActionRow("Add something else", Icons.Filled.AddCircleOutline, divider = customized) { subtract = false; editingAdjustment = true }
                    }
                    if (customized) {
                        TextField(customName, { customName = it }, singleLine = true, placeholder = { Text("Name this custom order", color = c.tertiaryText) },
                            textStyle = LeanrType.body, shape = RoundedCornerShape(0.dp),
                            colors = TextFieldDefaults.colors(focusedContainerColor = c.card, unfocusedContainerColor = c.card, focusedIndicatorColor = Color.Transparent,
                                unfocusedIndicatorColor = Color.Transparent, cursorColor = c.accent),
                            modifier = Modifier.fillMaxWidth())
                        OffensiveTextNote(customName)
                    }
                }
            }
        }
        if (pick == null) {
            CopycatBook.bundled.comparisons(listOf(current)).firstOrNull()?.let { item ->
                item {
                    LeanrSection {
                        Row(Modifier.fillMaxWidth().clickable { copycat = item }.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Filled.OutdoorGrill, null, tint = c.accent)
                            Spacer(Modifier.width(12.dp))
                            Column(Modifier.weight(1f)) {
                                Text("Make it at home", style = LeanrType.body, color = c.text)
                                Text("${item.recipe.name} · ${item.home.cal.rounded().number} Cal for ${item.recipe.serving}", style = LeanrType.caption, color = c.secondaryText)
                            }
                            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = c.tertiaryText)
                        }
                    }
                }
            }
        }
        item { DietSection(current) }
        if (pick == null) item { NearestPlaceSection(current.chain) }
        store.chain(current.chain)?.let { chain -> if (chain.id != "mine") item { FoodSourceSection(chain) } }
        if (current.isEveryday) item { EverydaySourceSection(current) }
        if (current.isSupermarket) item { SupermarketSourceSection(current) }
        if (customized) {
            item {
                LeanrSection {
                    ActionRow("Save custom order to My foods", Icons.Filled.BookmarkBorder, enabled = adjusted.isValid && !nameFlagged, divider = false) { saveCustom() }
                }
            }
        }
    }
    if (premium) PremiumSheet(onDismiss = { premium = false })
}

/** A recipe's ingredients as rows: what it is, how much, and its calories and protein (IngredientRows). */
@Composable
fun IngredientRows(ingredients: List<Portion>) {
    val c = Leanr.colours
    ingredients.forEachIndexed { i, item ->
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 9.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = Alignment.Bottom) {
                Text(item.food.name, style = LeanrType.body, color = c.text, modifier = Modifier.weight(1f))
                Spacer(Modifier.width(8.dp))
                Text(amountText(item), style = LeanrType.subheadline, color = c.secondaryText)
            }
            Text("${(item.food.cal * item.quantity).rounded().number} Cal · ${(item.food.p * item.quantity).number} g protein", style = LeanrType.caption, color = c.secondaryText)
        }
        if (i < ingredients.size - 1) RowDivider()
    }
}

/** Where an everyday food's figures come from. */
@Composable
fun EverydaySourceSection(food: Food) {
    val uri = LocalUriHandler.current
    LeanrSection("Source", footer = "Average figures for this kind of food from the U.S. Department of Agriculture (public domain). Brands, varieties and cooking change them, so use the label when there is one.") {
        val url = food.everydaySource
        ValueRow("From", "USDA FoodData Central", divider = url != null)
        if (url != null) ActionRow("View this food at FoodData Central", divider = false) { runCatching { uri.openUri(url) } }
    }
}

/** Where a supermarket product's figures come from. They're read off the pack by volunteers, not published by the supermarket. */
@Composable
fun SupermarketSourceSection(food: Food) {
    val uri = LocalUriHandler.current
    LeanrSection("Source", footer = "Label figures entered by Open Food Facts volunteers, available under the Open Database License (ODbL). Recipes change and stores vary, so check the pack. Leanrrr isn't affiliated with Coles or Woolworths.") {
        val url = food.productSource
        ValueRow("From", "Open Food Facts", divider = url != null)
        if (url != null) ActionRow("View this product at Open Food Facts", divider = false) { runCatching { uri.openUri(url) } }
    }
}

/** The support address, as the iOS app's AppInfo.contactText gives it. */
const val CONTACT_TEXT = "isaiahgraham.app@gmail.com"

/** Where a restaurant food's figures come from, so every number can be traced to the chain's own information. */
@Composable
fun FoodSourceSection(chain: Chain) {
    val store = AppServices.store
    val c = Leanr.colours
    val uri = LocalUriHandler.current
    LeanrSection("Source", footer = "Figures are ${chain.name.possessive} own published information, as at the snapshot date. Leanrrr isn't affiliated with ${chain.name}. Spot something wrong? Let me know through $CONTACT_TEXT.") {
        chain.how?.let { ValueRow("From", it) }
        chain.src?.let { Text(it, style = LeanrType.caption, color = c.secondaryText, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) }
        store.menuDate?.let { date ->
            ValueRow("Menu snapshot", date.atZone(ZoneId.systemDefault()).toLocalDate().format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)), divider = chain.url != null)
        }
        chain.url?.let { url -> ActionRow("View ${chain.name.possessive} nutrition information", divider = false) { runCatching { uri.openUri(url) } } }
    }
}
