package com.isaiahgraham.leanrrr.feature.find

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Eco
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.QuickLog
import com.isaiahgraham.leanrrr.data.rememberStringPref
import com.isaiahgraham.leanrrr.ui.components.Chip
import com.isaiahgraham.leanrrr.ui.components.ChipRow
import com.isaiahgraham.leanrrr.ui.components.FoodRow
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.components.LogTargetPicker
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext

private val browseCategories = listOf("all" to "All items", "main" to "Mains", "breakfast" to "Breakfast", "side" to "Sides", "snack" to "Snacks",
    "drink" to "Drinks", "sweet" to "Desserts", "extra" to "Extras")

/** The shape of row `index` of `count` drawn as one card: rounded at the top of the first and the bottom of the last. */
fun cardShape(index: Int, count: Int): Shape {
    val top = if (index == 0) 12.dp else 0.dp
    val bottom = if (index == count - 1) 12.dp else 0.dp
    return RoundedCornerShape(topStart = top, topEnd = top, bottomStart = bottom, bottomEnd = bottom)
}

/**
 * Search foods and Best choices (BrowseView): every food ranked by protein per calorie or searched for, with one-tap logging.
 * With `pick`, choosing a food hands its portion back instead of logging it ("Choose a food"), for other screens to use.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun BrowseScreen(
    pick: ((Portion) -> Unit)? = null,
    /** What choosing a food does, for the button on its details, e.g. "Log to Lunch". */
    pickTitle: String = "Use this portion",
    /** What the "+" on a row does, for screen readers. */
    quickAddLabel: String = "Log",
    /** Opens with the keyboard up, for the Search foods row. */
    startSearching: Boolean = false,
    /** Words to search for straight away, such as a food seen in a photo. */
    initialSearch: String = "",
    onBack: (() -> Unit)? = null,
) {
    val store = AppServices.store
    val c = Leanr.colours
    var search by remember { mutableStateOf(initialSearch) }
    var chain by remember { mutableStateOf("all") }
    var category by remember { mutableStateOf("all") }
    var sort by remember { mutableStateOf("density") }
    var recent by rememberStringPref(RecentSearches.STORAGE_KEY, "")
    val dietRaw by rememberStringPref(DietFilter.STORAGE_KEY, "")
    var yesterday by remember { mutableStateOf(false) }
    var meal by remember { mutableStateOf(MealTime.suggested()) }
    var rows by remember { mutableStateOf(emptyList<Food>()) }
    /** Matches left out by the dietary needs, when none are left. */
    var hidden by remember { mutableIntStateOf(0) }
    /** The request the rows were worked out for; null until the first list is ready. */
    var shown by remember { mutableStateOf<FoodSearch.Browse?>(null) }
    var detail by remember { mutableStateOf<Food?>(null) }
    var dietOpen by remember { mutableStateOf(false) }
    var sourcesOpen by remember { mutableStateOf(false) }
    val focus = remember { FocusRequester() }
    val request = FoodSearch.Browse(search, chain, category, sort, mineFirst = true)

    LaunchedEffect(request, store.data.foods, store.catalog, dietRaw, store.communityRevision, store.foodsLoaded) {
        // Wait for a pause in typing so each keystroke doesn't start a new search.
        val last = shown
        if (last != null && last.search != request.search && request.search.isNotEmpty()) delay(120)
        // Dietary needs from Find leave out items that don't fit, or whose restaurant doesn't say.
        val diet = DietFilter.fromRaw(dietRaw)
        val all = store.searchFoods
        val names = store.searchChainNames
        val (found, hiddenCount) = withContext(Dispatchers.Default) {
            val scope = this
            val foods = if (diet.isEmpty) all else all.filter { diet.allows(it) }
            val found = FoodSearch.browse(foods, names, request) { !scope.isActive }
            // When the needs leave nothing, say so, rather than suggest a spelling mistake.
            val hiddenCount = if (found.isEmpty() && !diet.isEmpty && request.search.isNotEmpty()) FoodSearch.browse(all, names, request).size else 0
            found to hiddenCount
        }
        rows = found; shown = request; hidden = hiddenCount
    }
    LaunchedEffect(Unit) { if (startSearching && search.isEmpty()) runCatching { focus.requestFocus() } }

    fun noteSearch() { recent = RecentSearches.adding(shown?.search ?: search, recent) }
    /** One serving, without opening the food: handed to whoever is choosing, or logged to today. */
    fun quickAdd(food: Food) {
        noteSearch()
        if (pick != null) pick(Portion(food = food)) else store.logNow(listOf(Portion(food = food)), food.name, meal, yesterday)
    }

    detail?.let { food ->
        FoodDetailScreen(food, onBack = { detail = null }, pick = pick, pickTitle = pickTitle, logYesterday = yesterday, logMeal = if (pick == null) meal else null)
        return
    }
    if (dietOpen) { DietNeedsScreen(onBack = { dietOpen = false }); return }
    if (sourcesOpen) { SourcesScreen(onBack = { sourcesOpen = false }); return }
    if (onBack != null) BackHandler(onBack = onBack)

    val title = if (pick == null) (if (startSearching) "Search foods" else "Best choices") else "Choose a food"
    LeanrScreen(title, onBack = onBack, actions = {
        if (pick == null) IconButton(onClick = { sourcesOpen = true }) { Icon(Icons.Outlined.Info, "Menu sources", tint = c.accent) }
    }) {
        if (pick == null) {
            item {
                LeanrSection(footer = "Tap + on a food to log it there. Pick Yesterday for something you forgot.") {
                    LogTargetPicker(yesterday, { yesterday = it }, meal, { meal = it }, Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
                }
            }
        }
        item {
            TextField(
                value = search, onValueChange = { search = it }, singleLine = true,
                placeholder = { Text("Food, product or restaurant", style = LeanrType.body, color = c.secondaryText) },
                leadingIcon = { Icon(Icons.Filled.Search, null, tint = c.secondaryText) },
                trailingIcon = { if (search.isNotEmpty()) IconButton(onClick = { search = "" }) { Icon(Icons.Filled.Clear, "Clear search", tint = c.secondaryText) } },
                textStyle = LeanrType.body, shape = RoundedCornerShape(12.dp),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(onSearch = { recent = RecentSearches.adding(search, recent) }),
                colors = TextFieldDefaults.colors(focusedContainerColor = c.card, unfocusedContainerColor = c.card, focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent, cursorColor = c.accent),
                modifier = Modifier.fillMaxWidth().focusRequester(focus).padding(bottom = 8.dp),
            )
        }
        if (search.isEmpty() && recent.isNotEmpty()) {
            item {
                LeanrSection("Recent searches") {
                    RecentSearches.list(recent).forEach { text ->
                        ActionRow(text, Icons.Filled.History, colour = c.text) { search = text }
                    }
                    ActionRow("Clear recent searches", colour = c.over, divider = false) { recent = "" }
                }
            }
        }
        item {
            ChipRow {
                Chip("All", chain == "all") { chain = "all" }
                Chip("Everyday foods", chain == Food.EVERYDAY) { chain = if (chain == Food.EVERYDAY) "all" else Food.EVERYDAY }
                if (store.community.isNotEmpty()) Chip("Community", chain == Food.COMMUNITY) { chain = if (chain == Food.COMMUNITY) "all" else Food.COMMUNITY }
                (store.supermarketChains + store.catalog.chains).forEach { item -> Chip(item.name, chain == item.id) { chain = if (chain == item.id) "all" else item.id } }
            }
            ChipRow(Modifier.padding(bottom = 16.dp)) {
                browseCategories.forEach { (tag, label) -> Chip(label, category == tag) { category = tag } }
            }
        }
        if (search.isEmpty() && chain == "all" && category == "all") {
            val pinned = store.pinnedFoods
            if (pinned.isNotEmpty()) {
                foodRows("Pinned", pinned, header = { PinnedHeader() }, onOpen = { detail = it }, onQuickAdd = ::quickAdd, quickAddLabel = quickAddLabel)
            }
            // Pinned foods already sit above, so they don't repeat here.
            val recentFoods = QuickLog.recentFoods(store.data.logs).filter { food -> pinned.none { it.id == food.id } }
            if (recentFoods.isNotEmpty()) {
                foodRows("Recently logged", recentFoods, onOpen = { detail = it }, onQuickAdd = ::quickAdd, quickAddLabel = quickAddLabel,
                    footer = if (pinned.isEmpty()) "Touch and hold a food to pin it here, so your regulars stay at the top." else null)
            }
        }
        item {
            Row(Modifier.fillMaxWidth().padding(start = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(if (shown != null) "${rows.size} food${if (rows.size == 1) "" else "s"}".uppercase() else "", style = LeanrType.footnote, color = c.secondaryText, modifier = Modifier.weight(1f))
                MenuPicker(listOf("density" to "Protein per calorie", "protein" to "Most protein", "calories" to "Lowest calories", "name" to "Name"), sort, { sort = it })
            }
        }
        if (shown == request && rows.isEmpty()) {
            item {
                LeanrSection {
                    if (hidden > 0) EmptyState("Nothing that fits",
                        "$hidden match${if (hidden == 1) "" else "es"} left out by your dietary needs (${DietFilter.fromRaw(dietRaw).summary}). Change them in Find → Dietary needs.", Icons.Filled.Eco)
                    else EmptyState("No menu matches", "Check the spelling, or try another word.", Icons.Filled.Search)
                }
            }
        } else if (shown == null) {
            item { LeanrSection { Working("Loading foods") } }
        }
        itemsIndexed(rows, key = { index, food -> "row:" + food.id + ":" + index }) { index, food ->
            run {
                Box(Modifier.clip(cardShape(index, rows.size)).background(c.card)) {
                    PinnableFoodRow(food, index < rows.size - 1, quickAddLabel, onQuickAdd = { quickAdd(food) }) { noteSearch(); detail = food }
                }
            }
        }
        if (dietRaw.isNotEmpty()) {
            item {
                TextButton(onClick = { dietOpen = true }, modifier = Modifier.padding(start = 4.dp, top = 4.dp)) {
                    Text("Showing what fits: ${DietFilter.fromRaw(dietRaw).summary}. Change in Dietary needs.", style = LeanrType.caption, color = c.accent)
                }
            }
        }
    }
}

@Composable
private fun PinnedHeader() {
    val c = Leanr.colours
    Row(Modifier.padding(start = 16.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Filled.PushPin, null, tint = c.secondaryText, modifier = Modifier.size(13.dp))
        Spacer(Modifier.width(4.dp))
        Text("PINNED", style = LeanrType.footnote, color = c.secondaryText)
    }
}

/** A section of food rows, each a lazy item so long lists stay quick. */
private fun LazyListScope.foodRows(
    title: String, foods: List<Food>, header: (@Composable () -> Unit)? = null, footer: String? = null,
    onOpen: (Food) -> Unit, onQuickAdd: (Food) -> Unit, quickAddLabel: String,
) {
    item(key = "header:$title") {
        if (header != null) header() else Text(title.uppercase(), style = LeanrType.footnote, color = Leanr.colours.secondaryText, modifier = Modifier.padding(start = 16.dp, bottom = 6.dp))
    }
    foods.forEachIndexed { index, food ->
        item(key = "$title:${food.id}:$index") {
            Box(Modifier.clip(cardShape(index, foods.size)).background(Leanr.colours.card)) {
                PinnableFoodRow(food, index < foods.size - 1, quickAddLabel, onQuickAdd = { onQuickAdd(food) }) { onOpen(food) }
            }
        }
    }
    item(key = "footer:$title") {
        Column(Modifier.padding(bottom = 20.dp)) {
            if (footer != null) Text(footer, style = LeanrType.footnote, color = Leanr.colours.secondaryText, modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp))
        }
    }
}

/** A food row; touch and hold to pin it or unpin it (PinButton in a context menu). */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun PinnableFoodRow(food: Food, divider: Boolean, quickAddLabel: String = "Log", onQuickAdd: (() -> Unit)?, onOpen: () -> Unit) {
    val store = AppServices.store
    var menu by remember { mutableStateOf(false) }
    Box {
        FoodRow(food, modifier = Modifier.combinedClickable(onClick = onOpen, onLongClick = { menu = true }), quickAddLabel = quickAddLabel,
            divider = divider, onQuickAdd = onQuickAdd)
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            val pinned = store.isPinned(food)
            DropdownMenuItem(text = { Text(if (pinned) "Unpin" else "Pin to top") }, leadingIcon = { Icon(Icons.Filled.PushPin, null) },
                onClick = { menu = false; store.togglePin(food) })
        }
    }
}
