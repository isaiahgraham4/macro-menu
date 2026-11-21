package com.isaiahgraham.leanrrr.feature.find

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Search
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.DietInfo
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.data.rememberStringPref
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.max

/** Find → Dietary needs (DietNeedsView): what to leave out of orders, Best choices, search and suggestions. */
@Composable
fun DietNeedsScreen(onBack: () -> Unit) {
    val store = AppServices.store
    var raw by rememberStringPref(DietFilter.STORAGE_KEY, "")
    val filter = DietFilter.fromRaw(raw)
    BackHandler(onBack = onBack)

    fun set(option: DietOption, on: Boolean) { raw = DietFilter(if (on) filter.options + option else filter.options - option).raw }

    /** For each restaurant: the share of its items with known meat, and with published allergens. */
    data class Coverage(val name: String, val meat: Int, val allergens: Int)
    val coverage = store.catalog.chains.filter { it.id != "mine" }.mapNotNull { chain ->
        val foods = store.catalog.foods.filter { it.chain == chain.id }
        if (foods.isEmpty()) return@mapNotNull null
        val meat = foods.count { it.diet?.meat != null }; val allergens = foods.count { it.diet?.al != null }
        Coverage(chain.name, (meat.toDouble() / foods.size * 100).rounded().toInt(), (allergens.toDouble() / foods.size * 100).rounded().toInt())
    }.sortedWith(compareByDescending<Coverage> { it.allergens }.thenByDescending { it.meat }.thenBy { it.name })

    LeanrScreen("Dietary needs", onBack = onBack) {
        item {
            LeanrSection("What you eat", footer = "No beef and No pork also leave out gelatine, which is made from either.") {
                DietOption.meatOptions.forEachIndexed { i, option -> SwitchRow(option.title, option in filter.options, { set(option, it) }, divider = i < DietOption.meatOptions.size - 1) }
            }
        }
        item {
            LeanrSection("Allergens to avoid", footer = "Items that \"may contain\" an allergen are left out too, and so are items whose restaurant doesn't say either way. Shellfish covers crustaceans and molluscs.") {
                DietOption.allergenOptions.forEachIndexed { i, option ->
                    SwitchRow("No ${option.title.lowercase()}", option in filter.options, { set(option, it) }, divider = i < DietOption.allergenOptions.size - 1)
                }
            }
        }
        item {
            LeanrSection("What each restaurant says", footer = "Leanrrr only offers an item when the restaurant's own ingredient lists, descriptions, labels or allergen guides show it fits. Items they don't cover are left out rather than guessed. Kitchens are shared, so always tell the restaurant about an allergy. Your own foods are never filtered.") {
                coverage.forEachIndexed { i, row ->
                    ValueRow(row.name, if (row.allergens > 0) "What's in it ${row.meat}% · allergens ${row.allergens}%" else "What's in it ${row.meat}%", divider = i < coverage.size - 1)
                }
            }
        }
        if (!filter.isEmpty) item { LeanrSection { ActionRow("Clear all", colour = Leanr.colours.over, divider = false) { raw = "" } } }
    }
}

private val String.capitalizedFirst: String get() = take(1).uppercase() + drop(1)

/** On a restaurant item's details: what meats and allergens are in it, and where that comes from (DietSection). */
@Composable
fun DietSection(food: Food) {
    val store = AppServices.store
    // Supermarket products have no dietary section: the source's allergen fields are volunteer-entered.
    if (food.chain == "mine" || food.isSupermarket || food.isEveryday) return
    val info = food.diet ?: DietInfo()
    val owner = store.chainName(food.chain)
    val source = when (info.src) {
        "ingredients" -> "From ${owner.possessive} ingredient list."
        "description" -> "From ${owner.possessive} description of the item."
        "labels" -> "From ${owner.possessive} own vegetarian and allergen labels."
        "name" -> "Worked out from the item's name, which names what's in it."
        else -> "$owner doesn't say what's in this item, so dietary needs leave it out."
    }
    val footer = source + (if (info.al != null) " Allergens are from ${owner.possessive} own allergen information." else "") +
        " Kitchens are shared, so check with the restaurant about an allergy."
    LeanrSection("Dietary", footer = footer) {
        val meat = info.meat
        if (meat != null) {
            val words = meat.map { if (it == "other") "other meat" else it }
            ValueRow("Meat", if (meat.isEmpty()) (if (info.isVegan) "None · vegan" else "None · vegetarian") else words.joinToString(", ").capitalizedFirst)
        } else ValueRow("Meat", "Not listed")
        val al = info.al
        if (al != null) {
            val may = info.may ?: emptyList(); val unk = info.unk ?: emptyList()
            ValueRow("Contains", if (al.isEmpty()) (if (unk.isEmpty()) "None of the major allergens" else "None listed") else al.joinToString(", ") { DietOption.allergenName(it) }.capitalizedFirst,
                divider = may.isNotEmpty() || unk.isNotEmpty())
            if (may.isNotEmpty()) ValueRow("May contain", may.joinToString(", ") { DietOption.allergenName(it) }.capitalizedFirst, divider = unk.isNotEmpty())
            if (unk.isNotEmpty()) ValueRow("Not stated", unk.joinToString(", ") { DietOption.allergenName(it) }.capitalizedFirst, divider = false)
        } else ValueRow("Allergens", "Not published", divider = false)
    }
}

/** Ask Leanrrr's answers (AskLeanrView): the question as an order search, what was understood, and the orders that fit. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun AskLeanrScreen(question: String, onBack: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    var text by remember { mutableStateOf(question) }
    var asked by remember { mutableStateOf(question) }
    var request by remember { mutableStateOf<AskLeanr.Request?>(null) }
    var matches by remember { mutableStateOf(emptyList<MealMatch>()) }
    var searching by remember { mutableStateOf(true) }
    var order by remember { mutableStateOf<MealMatch?>(null) }

    LaunchedEffect(asked) {
        if (asked.isBlank()) return@LaunchedEffect
        searching = true
        val names = store.searchChainNames
        val defaults = FindQuery(calories = store.goals.mealCal, protein = store.goals.mealProtein, diet = DietFilter.saved)
        var parsed = AskLeanr.parse(asked, names, defaults)
        if (parsed.usesRemaining) {
            val left = Assistant.remaining(store.data, store.goals)
            val q = parsed.query.copy(calories = max(0.0, left.calories ?: parsed.query.calories), protein = max(0.0, left.protein ?: parsed.query.protein))
            parsed = parsed.copy(query = q, understood = listOf("What's left today: ${q.calories.rounded().number} Cal") + parsed.understood.drop(1))
        }
        request = parsed
        val query = parsed.query
        val foods = store.orderFoods(query)
        matches = withContext(Dispatchers.Default) { MealFinder.find(foods, query) }
        searching = false
    }

    order?.let { OrderDetailScreen(it, onBack = { order = null }); return }
    BackHandler(onBack = onBack)
    LeanrScreen("Ask Leanrrr", onBack = onBack) {
        item {
            LeanrSection(footer = "The orders come from Leanrrr's menus and the restaurants' published figures.") {
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.AutoAwesome, null, tint = c.accent)
                    Spacer(Modifier.width(10.dp))
                    Box(Modifier.weight(1f)) {
                        if (text.isEmpty()) Text("Ask Leanrrr", style = LeanrType.body, color = c.tertiaryText)
                        BasicTextField(text, { text = it }, textStyle = LeanrType.body.copy(color = c.text), maxLines = 3, cursorBrush = SolidColor(c.accent),
                            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search), keyboardActions = KeyboardActions(onSearch = { asked = text }),
                            modifier = Modifier.fillMaxWidth())
                    }
                    if (text.isNotBlank() && text != asked) IconButton(onClick = { asked = text }) { Icon(Icons.Filled.Search, "Ask", tint = c.accent) }
                }
                request?.let { r ->
                    // What was understood, so a misreading is easy to spot and fix by rewording.
                    FlowRow(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 12.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        r.understood.forEach { part ->
                            Text(part, style = LeanrType.label, color = c.text,
                                modifier = Modifier.clip(CircleShape).background(c.accent.copy(alpha = 0.12f)).padding(horizontal = 10.dp, vertical = 5.dp))
                        }
                    }
                }
            }
        }
        if (searching) {
            item { LeanrSection { Working("Finding orders") } }
        } else if (matches.isEmpty()) {
            item { LeanrSection { EmptyState("No orders fit", "Try more calories, less protein or another restaurant.", Icons.Filled.Search) } }
        } else {
            val shown = matches.take(10)
            shown.forEachIndexed { index, match ->
                item(key = match.id) {
                    LeanrSection(if (index == 0) "${shown.size} orders" else null) {
                        // When protein wasn't asked for, there's no target to be short of.
                        val protein = request?.let { if (AskLeanr.Field.PROTEIN in it.said || it.query.sort != "protein") it.query.protein else null }
                        OrderMatchCard(match, protein, onOpen = { order = match })
                    }
                }
            }
        }
    }
}

/** Where every restaurant's figures come from (SourcesView). */
@Composable
fun SourcesScreen(onBack: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    val uri = androidx.compose.ui.platform.LocalUriHandler.current
    BackHandler(onBack = onBack)
    LeanrScreen("Menu sources", onBack = onBack) {
        item { LeanrSection { SectionText("${store.region.menuNote} Missing nutrients stay unknown. Custom orders and recipes are estimates based on their ingredients.") } }
        (store.catalog.chains.filter { it.id != "mine" } + store.supermarketChains).forEach { chain ->
            item(key = "source:" + chain.id) {
                LeanrSection(chain.name) {
                    SectionText(chain.src ?: "", style = LeanrType.subheadline, colour = c.text)
                    chain.url?.let { url -> ActionRow("View source", divider = false) { runCatching { uri.openUri(url) } } }
                }
            }
        }
    }
}

