package com.isaiahgraham.leanrrr.feature.find

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.ArrowCircleUp
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Casino
import androidx.compose.material.icons.filled.Eco
import androidx.compose.material.icons.filled.OutdoorGrill
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.SouthEast
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.dayKey
import com.isaiahgraham.leanrrr.data.rememberStringPref
import com.isaiahgraham.leanrrr.ui.components.ActionPill
import com.isaiahgraham.leanrrr.ui.components.Chip
import com.isaiahgraham.leanrrr.ui.components.ChipRow
import com.isaiahgraham.leanrrr.ui.components.LeanrRow
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.components.OptionalNumberField
import com.isaiahgraham.leanrrr.ui.components.StatField
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import java.time.Instant
import kotlin.math.max

/** The screens Find pushes over itself. */
private sealed interface FindRoute {
    data class Browse(val startSearching: Boolean) : FindRoute
    data object Roulette : FindRoute
    data object Copycat : FindRoute
    data class Ask(val question: String) : FindRoute
    data object Sources : FindRoute
    data object Diet : FindRoute
    data class Order(val match: MealMatch) : FindRoute
}

/** The Find tab (FindView.swift): build and rank whole orders from a restaurant against what's left today. */
@Composable
fun FindScreen() {
    val store = AppServices.store
    val nav = AppServices.nav
    val c = Leanr.colours
    var route by remember { mutableStateOf<FindRoute?>(null) }
    var query by remember { mutableStateOf(FindQuery(calories = store.goals.mealCal, protein = store.goals.mealProtein, diet = DietFilter.saved)) }
    /** Bumped when the numbers change from outside the fields, so the fields show the new values. */
    var fields by remember { mutableIntStateOf(0) }
    var matches by remember { mutableStateOf(emptyList<MealMatch>()) }
    var searching by remember { mutableStateOf(true) }
    var question by remember { mutableStateOf("") }
    var moreOpen by remember { mutableStateOf(false) }
    var region by remember { mutableStateOf(store.region) }
    val dietRaw by rememberStringPref(DietFilter.STORAGE_KEY, "")

    LaunchedEffect(dietRaw) { query = query.copy(diet = DietFilter.fromRaw(dietRaw)) }
    // A restaurant opened from elsewhere (the Map, a shortcut). An empty one just returns to the main screen.
    LaunchedEffect(nav.findChain) {
        val chain = nav.findChain ?: return@LaunchedEffect
        if (chain.isNotEmpty()) query = query.copy(supermarket = false, chains = setOf(chain))
        nav.findChain = null
    }
    // Another country's menus: restaurants picked from the old ones no longer exist.
    LaunchedEffect(store.region) { if (store.region != region) { region = store.region; query = query.copy(supermarket = false, chains = emptySet()) } }
    LaunchedEffect(query, store.data.foods, store.catalog, store.supermarket) {
        searching = true
        delay(150)   // a pause in typing, so each keystroke doesn't start a search
        val request = query
        val foods = store.orderFoods(request)
        val result = withContext(Dispatchers.Default) { val scope = this; MealFinder.find(foods, request) { !scope.isActive } }
        matches = result
        searching = false
    }

    when (val r = route) {
        is FindRoute.Browse -> { BrowseScreen(startSearching = r.startSearching, onBack = { route = null }); return }
        FindRoute.Roulette -> { RouletteScreen(onBack = { route = null }); return }
        FindRoute.Copycat -> { CopycatKitchenScreen(onBack = { route = null }); return }
        is FindRoute.Ask -> { AskLeanrScreen(r.question, onBack = { route = null }); return }
        FindRoute.Sources -> { SourcesScreen(onBack = { route = null }); return }
        FindRoute.Diet -> { DietNeedsScreen(onBack = { route = null }); return }
        is FindRoute.Order -> { OrderDetailScreen(r.match, onBack = { route = null }); return }
        null -> {}
    }

    fun ask() {
        val text = question.trim()
        if (text.isNotEmpty()) route = FindRoute.Ask(text)
    }
    fun useRemaining() {
        val total = Nutrition((store.data.logs[dayKey(Instant.now())] ?: emptyList()).flatMap { it.items })
        query = query.copy(calories = max(0.0, (store.goals.values["cal"] ?: 2200.0) - total.cal), protein = max(0.0, (store.goals.values["p"] ?: 150.0) - total.p))
        fields++
    }
    val emptyMessage = if (query.supermarket) {
        if (query.diet.isEmpty) "Try more calories or a lower protein target." else "Supermarket products aren't checked against dietary needs, so turn those off in More options to see them."
    } else if (query.diet.isEmpty) "Try more calories or different restaurants."
    else "Try more calories or different restaurants. Dietary needs leave out items whose restaurant doesn't say what's in them."
    // What is set inside "More options", so a closed section still tells you when a filter is on.
    val moreSummary = buildList {
        if (!query.customise && !query.supermarket) add("No customising")
        if (query.carbs != null || query.fat != null) add("Macro limits")
        if (!query.diet.isEmpty) add("Dietary needs")
    }.let { if (it.isEmpty()) (if (query.supermarket) "None" else "Customising") else it.joinToString(", ") }

    LeanrScreen("Find a meal", actions = {
        IconButton(onClick = { route = FindRoute.Sources }) { Icon(Icons.Outlined.Info, "Menu sources", tint = c.accent) }
    }) {
        item {
            // Ask Leanrrr: a question in plain words, answered by the order finder.
            LeanrSection {
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.AutoAwesome, null, tint = c.accent)
                    Spacer(Modifier.width(10.dp))
                    Box(Modifier.weight(1f)) {
                        if (question.isEmpty()) Text(store.region.askExample, style = LeanrType.body, color = c.tertiaryText)
                        BasicTextField(question, { question = it }, textStyle = LeanrType.body.copy(color = c.text), maxLines = 3,
                            cursorBrush = SolidColor(c.accent), keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                            keyboardActions = KeyboardActions(onSearch = { ask() }), modifier = Modifier.fillMaxWidth())
                    }
                    if (question.isNotBlank()) IconButton(onClick = { ask() }) { Icon(Icons.Filled.ArrowCircleUp, "Ask", tint = c.accent, modifier = Modifier.size(30.dp)) }
                }
            }
        }
        item {
            // One scrolling line of shortcuts instead of tiles, so the order finder starts higher up the screen.
            ChipRow(Modifier.padding(bottom = 16.dp)) {
                ActionPill("Search foods", Icons.Filled.Search) { route = FindRoute.Browse(true) }
                ActionPill("Best choices", Icons.Filled.BarChart) { route = FindRoute.Browse(false) }
                ActionPill("Takeaway roulette", Icons.Filled.Casino) { route = FindRoute.Roulette }
                if (store.region.hasCopycatKitchen) ActionPill("Copycat Kitchen", Icons.Filled.OutdoorGrill) { route = FindRoute.Copycat }
            }
        }
        item {
            Row(Modifier.fillMaxWidth().padding(start = 16.dp, bottom = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                Text((if (query.supermarket) "Ready meals and snacks that fit" else "An order that fits").uppercase(), style = LeanrType.footnote, color = c.secondaryText, modifier = Modifier.weight(1f))
                TextButton(onClick = { useRemaining() }) {
                    Icon(Icons.Filled.SouthEast, null, tint = c.accent, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("Use what's left today", style = LeanrType.subheadline.copy(fontWeight = FontWeight.Medium), color = c.accent)
                }
            }
            LeanrSection {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (store.supermarketChains.isNotEmpty()) {
                        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                            listOf(false to "Takeaway", true to "Supermarket").forEachIndexed { i, (value, label) ->
                                SegmentedButton(selected = query.supermarket == value, onClick = { query = query.copy(supermarket = value, chains = emptySet()) },
                                    shape = SegmentedButtonDefaults.itemShape(i, 2),
                                    colors = SegmentedButtonDefaults.colors(activeContainerColor = c.accent.copy(alpha = 0.16f), activeContentColor = c.text)) { Text(label, style = LeanrType.subheadline) }
                            }
                        }
                    }
                    key(fields) {
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            StatField("Calories up to", "Cal", query.calories, { query = query.copy(calories = it) }, Modifier.weight(1f))
                            StatField("Protein target", "g", query.protein, { query = query.copy(protein = it) }, Modifier.weight(1f))
                        }
                    }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        MenuPicker((1..3).map { it to "Up to $it item${if (it == 1) "" else "s"}" }, query.maxItems, { query = query.copy(maxItems = it) })
                        Spacer(Modifier.weight(1f))
                        MenuPicker(listOf("fit" to "Closest fit", "lean" to "Lowest calories", "protein" to "Most protein"), query.sort, { query = query.copy(sort = it) })
                    }
                }
                RowDivider()
                DisclosureRow("More options", moreOpen, { moreOpen = !moreOpen }, value = moreSummary, divider = moreOpen)
                if (moreOpen) {
                    if (!query.supermarket) SwitchRow("Customise items to fit", query.customise, { query = query.copy(customise = it) },
                        subtitle = "Take off sauce or cheese, or add another patty or fillet")
                    key(fields) {
                        OptionalNumberField("Carbs up to (g)", query.carbs, { query = query.copy(carbs = it) })
                        OptionalNumberField("Fat up to (g)", query.fat, { query = query.copy(fat = it) })
                    }
                    Text("Macro limits leave out items with missing values.", style = LeanrType.caption, color = c.secondaryText, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
                    RowDivider()
                    LeanrRow("Dietary needs", leading = { Icon(Icons.Filled.Eco, null, tint = c.accent) }, divider = false, onClick = { route = FindRoute.Diet }, trailing = {
                        Text(if (query.diet.isEmpty) "None" else query.diet.summary, style = LeanrType.subheadline, color = c.secondaryText, maxLines = 2)
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = c.tertiaryText)
                    })
                }
            }
        }
        item {
            Text((if (query.supermarket) "Supermarkets" else "Restaurants").uppercase(), style = LeanrType.footnote, color = c.secondaryText, modifier = Modifier.padding(start = 16.dp, bottom = 2.dp))
            ChipRow(Modifier.padding(bottom = 16.dp)) {
                Chip("All", query.chains.isEmpty()) { query = query.copy(chains = emptySet()) }
                (if (query.supermarket) store.supermarketChains else store.catalog.chains).forEach { chain ->
                    Chip(chain.name, chain.id in query.chains) {
                        query = query.copy(chains = if (chain.id in query.chains) query.chains - chain.id else query.chains + chain.id)
                    }
                }
            }
        }
        if (searching) {
            item { LeanrSection("Finding combinations…") { Working("Finding orders") } }
        } else if (matches.isEmpty()) {
            item { LeanrSection("No suggestions") { EmptyState("No matching orders", emptyMessage, Icons.Filled.Search) } }
        } else {
            matches.forEachIndexed { index, match ->
                item(key = match.id) {
                    LeanrSection(if (index == 0) "${matches.size} suggested orders" else null) {
                        OrderMatchCard(match, query.protein, onOpen = { route = FindRoute.Order(match) })
                    }
                }
            }
        }
    }
}
