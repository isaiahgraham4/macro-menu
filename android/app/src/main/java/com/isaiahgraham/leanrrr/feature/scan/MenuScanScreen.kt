package com.isaiahgraham.leanrrr.feature.scan

import android.graphics.Bitmap
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.billing.Premium
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.feature.settings.PremiumSheet
import com.isaiahgraham.leanrrr.ui.components.BottomActionBar
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.components.LogTargetPicker
import com.isaiahgraham.leanrrr.ui.components.NutritionView
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.LocalDate

/** One dish on the menu and what's been decided about it (MenuScanView.Row). */
internal data class MenuRow(
    val dish: MenuDish,
    val estimate: MenuEstimate?,
    val size: PortionSize = PortionSize.REGULAR,
    val picked: Boolean = false,
) {
    val id: String get() = dish.id
    val total: Nutrition? get() = estimate?.total(size)
    val portion get() = estimate?.portion(dish.name, size)
}

private enum class MenuOrder(val title: String) { MENU("Menu"), PROTEIN("Protein"), LIGHTEST("Lightest") }

/**
 * Scan a menu (MenuScanView.swift): photograph any restaurant's menu, up to six pages, and Leanrrr estimates each dish from
 * its own foods. The phone reads the photo and nothing is sent anywhere. Figures are typical-serve estimates unless the
 * restaurant's own item was found, and say so. Part of Even Leanrrr: without it, the Even Leanrrr screen opens instead.
 * The iOS "Apple Intelligence suggests ingredients" pass for dishes it can't place is left out on Android.
 */
@Composable
fun MenuScan(onDismiss: () -> Unit, mealTime: MealTime = MealTime.suggested()) {
    if (!Premium.isUnlocked) { MenuScanLocked(onDismiss); return }
    val store = AppServices.store
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val pages = remember { mutableStateListOf<Bitmap>() }
    var reading by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<String?>(null) }
    var done by remember { mutableStateOf(false) }
    var camera by remember { mutableStateOf(false) }
    val rows = remember { mutableStateListOf<MenuRow>() }
    var restaurant by remember { mutableStateOf<String?>(null) }
    var chain by remember { mutableStateOf<String?>(null) }
    var estimator by remember { mutableStateOf<MenuEstimator?>(null) }
    var order by remember { mutableStateOf(MenuOrder.MENU) }
    var opened by remember { mutableStateOf<String?>(null) }
    var failed by remember { mutableStateOf(false) }
    var meal by remember { mutableStateOf(mealTime) }
    var yesterday by remember { mutableStateOf(false) }
    val portions = rows.filter { it.picked }.mapNotNull { it.portion }
    val left = caloriesLeft()

    fun reset() { pages.clear(); rows.clear(); restaurant = null; chain = null; order = MenuOrder.MENU; done = false; failure = null }

    fun read(scanned: List<Bitmap>) {
        pages.clear(); pages.addAll(scanned.take(TextReader.PAGE_LIMIT)); rows.clear(); reading = true; done = false; failure = null
        val foods = store.foods
        val names = store.catalog.chains.associate { it.id to it.name } + (com.isaiahgraham.leanrrr.data.Food.EVERYDAY to store.chainName(com.isaiahgraham.leanrrr.data.Food.EVERYDAY))
        scope.launch {
            try {
                val menu = TextReader.readMenu(pages.toList())
                val worked = withContext(Dispatchers.Default) {
                    val made = MenuEstimator(foods, names)
                    val found = made.chain(menu.restaurant)
                    Triple(made, found, menu.dishes.map { MenuRow(it, made.estimate(it, found)) })
                }
                estimator = worked.first; chain = worked.second
                rows.addAll(worked.third)
                restaurant = menu.restaurant
                reading = false; done = true
            } catch (e: Exception) {
                reading = false
                failure = "Couldn't read this menu. Try another photo."
            }
        }
    }

    val picker = rememberPhotosPicker(TextReader.PAGE_LIMIT) { uris ->
        reading = true
        scope.launch {
            val picked = uris.take(TextReader.PAGE_LIMIT).mapNotNull { loadPhoto(context, it) }
            if (picked.isEmpty()) { reading = false; failure = "Those photos couldn't be opened. Try others."; pages.clear() } else read(picked)
        }
    }

    if (camera) {
        PhotoCamera("Fit one page in the frame. Take each page, then tap Done.", square = false, pages = TextReader.PAGE_LIMIT,
            onCancel = { camera = false }, onPhotos = { photos -> camera = false; if (photos.isNotEmpty()) read(photos) })
        return
    }
    opened?.let { id ->
        val index = rows.indexOfFirst { it.id == id }
        if (index >= 0) {
            MenuDishDetail(rows[index], left, onChange = { rows[index] = it }, estimate = { dish -> estimator?.estimate(dish, chain) }, onDone = { opened = null })
            return
        }
    }

    BackHandler(onBack = onDismiss)
    LeanrScreen("Scan a menu", onBack = onDismiss, bottomBar = {
        if (portions.isNotEmpty()) {
            BottomActionBar("Log ${portions.size} to ${meal.title} · ${Nutrition(portions).cal.roundedAway().number} Cal", enabled = portions.all { it.isValid }) {
                val date = if (yesterday) LocalDate.now().minusDays(1) else LocalDate.now()
                if (store.log(portions, portions.joinToString(" + ") { it.food.name }, date, mealTime = meal)) {
                    store.notice = "Logged to ${if (yesterday) "yesterday’s " else ""}${meal.title.lowercase()}"
                    onDismiss()
                } else failed = true
            }
        }
    }) {
        if (pages.isEmpty()) {
            item {
                LeanrSection(footer = "Works with any restaurant, up to ${TextReader.PAGE_LIMIT} pages. Your phone reads the menu, and nothing is saved or sent anywhere.") {
                    ActionRow("Photograph the menu", icon = Icons.Filled.CameraAlt, divider = true) { camera = true }
                    ActionRow("Choose from Photos", icon = Icons.Filled.PhotoLibrary) { picker.launch(imagesOnly) }
                    if (reading) ProgressRow("Reading the menu…")
                    failure?.let { Body(it, secondary = true) }
                }
            }
        } else {
            item {
                LeanrSection {
                    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        pages.forEachIndexed { index, page ->
                            Image(page.asImageBitmap(), "Menu page ${index + 1}", contentScale = ContentScale.Fit,
                                modifier = Modifier.height(120.dp).clip(RoundedCornerShape(8.dp)))
                        }
                    }
                    if (reading) ProgressRow("Reading the menu…")
                    failure?.let { Body(it, secondary = true) }
                    if (!reading) ActionRow("Scan a different menu", icon = Icons.Filled.Refresh) { reset() }
                }
            }
        }
        if (done) {
            if (rows.isEmpty()) {
                item { LeanrSection { Body("No dishes found in this photo. Try again with the menu flat, in good light and filling the frame.", secondary = true) } }
            } else {
                item {
                    LeanrSection(footer = summary(rows, restaurant)) {
                        Segmented(MenuOrder.entries.map { it to it.title }, order) { order = it }
                        leftText()?.let { text ->
                            Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Filled.Restaurant, null, tint = Leanr.colours.accent, modifier = Modifier.size(16.dp)); Spacer(Modifier.width(8.dp))
                                Text("Left today: $text", style = LeanrType.subheadline, color = Leanr.colours.text)
                            }
                        }
                        LogTargetPicker(yesterday, { yesterday = it }, meal, { meal = it }, Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
                    }
                }
                for ((title, group) in groups(rows, order)) {
                    item(key = title) {
                        LeanrSection(title) {
                            group.forEachIndexed { i, row ->
                                MenuRowView(row, left, divider = i < group.size - 1,
                                    onToggle = { val index = rows.indexOfFirst { it.id == row.id }; if (index >= 0) rows[index] = rows[index].copy(picked = !rows[index].picked) },
                                    onOpen = { opened = row.id })
                            }
                        }
                    }
                }
            }
        }
    }
    if (failed) AlertDialog(onDismissRequest = { failed = false }, confirmButton = { TextButton({ failed = false }) { Text("OK") } },
        title = { Text("Couldn’t log that") }, text = { Text("Your data was not changed. Check available storage and try again.") })
}

/** Menu scanning is part of Even Leanrrr: without it, the Even Leanrrr screen opens instead. */
@Composable
private fun MenuScanLocked(onDismiss: () -> Unit) {
    var showPremium by remember { mutableStateOf(true) }
    BackHandler(onBack = onDismiss)
    LeanrScreen("Scan a menu", onBack = onDismiss) {
        item {
            LeanrSection(footer = "Photograph any restaurant's menu and Leanrrr estimates each dish from its own foods.") {
                ActionRow("Scan a menu is part of Even Leanrrr", icon = Icons.Filled.Lock) { showPremium = true }
            }
        }
    }
    if (showPremium) PremiumSheet(onDismiss = { showPremium = false })
}

/** How many dishes, from where, and how far to trust them. */
private fun summary(rows: List<MenuRow>, restaurant: String?): String {
    val place = restaurant?.let { " at $it" } ?: ""
    val count = "${rows.size} ${if (rows.size == 1) "dish" else "dishes"}$place."
    if (rows.any { it.estimate?.basis == MenuEstimate.Basis.OFFICIAL } && rows.all { it.estimate == null || it.estimate.basis == MenuEstimate.Basis.OFFICIAL }) {
        return "$count These are the restaurant's own figures."
    }
    return "$count Figures are estimates of a typical serve and can be well off, so tap a dish to see what's counted. Allergens aren't checked: ask the restaurant."
}

private fun groups(rows: List<MenuRow>, order: MenuOrder): List<Pair<String, List<MenuRow>>> {
    if (order != MenuOrder.MENU) {
        val known = rows.filter { it.estimate != null }
        val sorted = if (order == MenuOrder.PROTEIN) known.sortedByDescending { it.total?.p ?: 0.0 } else known.sortedBy { it.total?.cal ?: 0.0 }
        val title = if (order == MenuOrder.PROTEIN) "Most protein" else "Fewest calories"
        return listOf(title to sorted) + (if (rows.size > known.size) listOf("No estimate" to rows.filter { it.estimate == null }) else emptyList())
    }
    val titles = LinkedHashSet<String>()
    rows.forEach { titles += it.dish.section ?: "Menu" }
    return titles.map { title -> title to rows.filter { (it.dish.section ?: "Menu") == title } }
}

@Composable
private fun MenuRowView(row: MenuRow, left: Double?, divider: Boolean, onToggle: () -> Unit, onOpen: () -> Unit) {
    val c = Leanr.colours
    Column {
        Row(Modifier.fillMaxWidth().padding(start = 4.dp, end = 16.dp, top = 6.dp, bottom = 6.dp), verticalAlignment = Alignment.Top) {
            IconButton(onClick = onToggle, enabled = row.estimate != null) {
                Icon(if (row.picked) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
                    if (row.picked) "Leave out ${row.dish.name}" else "Choose ${row.dish.name}",
                    tint = if (row.picked) c.accent else c.secondaryText)
            }
            Column(Modifier.weight(1f).clickable(onClick = onOpen).padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Row(verticalAlignment = Alignment.Top) {
                    Text(row.dish.name, style = LeanrType.headline, color = c.text, modifier = Modifier.weight(1f))
                    row.dish.price?.let { Spacer(Modifier.width(8.dp)); Text("$${it.number}", style = LeanrType.subheadline, color = c.secondaryText) }
                }
                val total = row.total; val estimate = row.estimate
                if (total != null && estimate != null) {
                    Text("${if (estimate.isExact) "" else "≈ "}${total.cal.roundedAway().number} Cal · ${total.p.roundedAway().number} g protein",
                        style = LeanrType.subheadline.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold), color = c.text)
                    Text("${total.c.roundedAway().number} g carbs · ${total.f.roundedAway().number} g fat · ${estimate.label}", style = LeanrType.caption, color = c.secondaryText)
                    if (left != null && left > 0 && total.cal <= left) Text("Fits what's left today", style = LeanrType.caption, color = c.accent)
                } else {
                    Text("No estimate. Tap to fix the wording or search for it.", style = LeanrType.caption, color = c.secondaryText)
                }
            }
        }
        if (divider) HorizontalDivider(Modifier.padding(start = 52.dp), color = c.separator, thickness = 0.5.dp)
    }
}

/** One dish: what's counted, how sure the figure is, and the ways to put it right (MenuDishDetail). */
@Composable
private fun MenuDishDetail(row: MenuRow, caloriesLeft: Double?, onChange: (MenuRow) -> Unit, estimate: (MenuDish) -> MenuEstimate?, onDone: () -> Unit) {
    val c = Leanr.colours
    var name by remember(row.id) { mutableStateOf(row.dish.name) }
    var details by remember(row.id) { mutableStateOf(row.dish.details) }
    var searching by remember { mutableStateOf(false) }
    val edited = name != row.dish.name || details != row.dish.details
    if (searching) {
        ScanFoodSearch(row.dish.name, onDismiss = { searching = false }, onPick = { portion ->
            onChange(row.copy(estimate = MenuEstimate(listOf(MenuComponent(portion.food, portion.quantity)), MenuEstimate.Basis.CHOSEN), size = PortionSize.REGULAR))
            searching = false
        })
        return
    }
    BackHandler(onBack = onDone)
    LeanrScreen(row.dish.name, onBack = onDone, actions = { TextButton(onClick = onDone) { Text("Done", color = c.accent) } }) {
        val total = row.total; val current = row.estimate
        if (total != null && current != null) {
            item { LeanrSection(footer = rangeText(total, current)) { NutritionView(total, details = false) } }
            if (!current.isExact) {
                item { LeanrSection("Serve size") { Segmented(PortionSize.entries.map { it to it.title }, row.size) { onChange(row.copy(size = it)) } } }
                if (current.components.isNotEmpty()) item {
                    LeanrSection("What's counted", footer = "Turn off anything that isn't in your dish.") {
                        current.components.forEachIndexed { index, component ->
                            val scale = row.size.factor
                            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                                Column(Modifier.weight(1f)) {
                                    Text(component.food.name, style = LeanrType.subheadline, color = c.text)
                                    Text((component.grams?.let { "${(it * scale).roundedAway().number} g · " } ?: "") +
                                        "${(component.food.cal * component.quantity * scale).roundedAway().number} Cal", style = LeanrType.caption, color = c.secondaryText)
                                }
                                Switch(component.isOn, { on ->
                                    val list = current.components.toMutableList(); list[index] = component.copy(isOn = on)
                                    onChange(row.copy(estimate = current.copy(components = list)))
                                }, colors = SwitchDefaults.colors(checkedTrackColor = c.accent))
                            }
                        }
                    }
                }
            }
        } else {
            item { LeanrSection { Body("Leanrrr can't tell what's in this from the words on the menu. Fix the wording below if it misread them, or search for something close.", secondary = true) } }
        }
        item {
            LeanrSection("What the menu says", footer = "Check this against the menu. Photos can be misread.") {
                FieldRow(name, { name = it }, "Dish")
                SectionDivider()
                FieldRow(details, { details = it }, "What the menu says is in it", singleLine = false)
                if (edited) ActionRow("Work it out again", icon = Icons.Filled.Refresh) {
                    val dish = row.dish.copy(name = name.trim(), details = details.trim())
                    val worked = estimate(dish)
                    onChange(row.copy(dish = dish, estimate = worked, size = PortionSize.REGULAR, picked = if (worked == null) false else row.picked))
                }
            }
        }
        item { LeanrSection { ActionRow("Search for it instead", icon = Icons.Filled.Search) { searching = true } } }
        if (caloriesLeft != null && total != null && caloriesLeft > 0 && total.cal <= caloriesLeft) item { Caption("Fits what's left today.", colour = c.accent) }
    }
}

/** "Typical serve. Could be about 640 to 960 Cal, depending on the kitchen." */
internal fun rangeText(total: Nutrition, estimate: MenuEstimate): String {
    if (estimate.spread <= 0) return estimate.label + "."
    fun nearest(value: Double) = ((value / 10).roundedAway() * 10).number
    return "${estimate.label}. Could be about ${nearest(total.cal * (1 - estimate.spread))} to ${nearest(total.cal * (1 + estimate.spread))} Cal, depending on the kitchen."
}
