package com.isaiahgraham.leanrrr.feature.meal

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DocumentScanner
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.QrCode
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.outlined.AddBox
import androidx.compose.material.icons.outlined.Eco
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.Prefs
import com.isaiahgraham.leanrrr.data.newId
import com.isaiahgraham.leanrrr.data.nutrientNames
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.data.tenth
import com.isaiahgraham.leanrrr.feature.find.FoodDetailScreen
import com.isaiahgraham.leanrrr.feature.find.FoodSearch
import com.isaiahgraham.leanrrr.feature.scan.BarcodeScanScreen
import com.isaiahgraham.leanrrr.feature.scan.LabelScanScreen
import com.isaiahgraham.leanrrr.ui.AppTab
import com.isaiahgraham.leanrrr.ui.components.ActionTile
import com.isaiahgraham.leanrrr.ui.components.FoodRow
import com.isaiahgraham.leanrrr.ui.components.LeanrRow
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.components.NumberField
import com.isaiahgraham.leanrrr.ui.components.NutritionView
import com.isaiahgraham.leanrrr.ui.components.OptionalNumberField
import com.isaiahgraham.leanrrr.ui.components.SearchField
import com.isaiahgraham.leanrrr.ui.components.TileRow
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlinx.coroutines.launch

// A port of MyFoodsView.swift: My foods and the food editor. RecipeEditor is in RecipeScreens.kt.

/** What My foods is showing over its list. */
private sealed interface MyFoodsRoute {
    data class Editor(val food: Food?) : MyFoodsRoute
    data class Recipe(val food: Food?) : MyFoodsRoute
    data class Detail(val food: Food) : MyFoodsRoute
    data object Import : MyFoodsRoute
    data object Barcode : MyFoodsRoute
}

/** My foods (MyFoodsView.swift): your own foods, recipes, saved meals and custom orders. */
@Composable
fun MyFoodsScreen(onBack: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    var route by remember { mutableStateOf<MyFoodsRoute?>(null) }
    var search by remember { mutableStateOf("") }

    when (val r = route) {
        is MyFoodsRoute.Editor -> { FoodEditorScreen(r.food, onDone = { route = null }); return }
        is MyFoodsRoute.Recipe -> { RecipeEditorScreen(r.food, onClose = { route = null }); return }
        is MyFoodsRoute.Detail -> { BackHandler { route = null }; FoodDetailScreen(r.food, onBack = { route = null }); return }
        MyFoodsRoute.Import -> { RecipeImportScreen(onClose = { route = null }); return }
        MyFoodsRoute.Barcode -> {
            BarcodeScanScreen(onFound = { route = MyFoodsRoute.Editor(it) }, onDismiss = { route = null }); return
        }
        null -> {}
    }
    BackHandler(onBack = onBack)

    val rows = run {
        val digits = search.filter { it.isDigit() }
        if (digits.length >= 4 && digits.length == search.count { !it.isWhitespace() }) store.data.foods.filter { it.barcode?.contains(digits) == true }
        else if (search.isBlank()) store.data.foods
        else FoodSearch.search(search, store.data.foods, store.searchChainNames, limit = 1000)
    }
    val edit = { food: Food -> route = if (food.ingredients != null) MyFoodsRoute.Recipe(food) else MyFoodsRoute.Editor(food) }

    LeanrScreen("My foods", onBack = onBack, showSettings = false) {
        item { SearchField(search, { search = it }, "Search", Modifier.padding(bottom = 12.dp)) }
        item {
            TileRow(Modifier.padding(bottom = 16.dp)) {
                ActionTile("Add or scan food", Icons.Outlined.AddBox, Modifier.weight(1f)) { route = MyFoodsRoute.Editor(null) }
                ActionTile("Build a recipe", Icons.Outlined.Eco, Modifier.weight(1f)) { route = MyFoodsRoute.Recipe(null) }
                ActionTile("Customise an order", Icons.Filled.Tune, Modifier.weight(1f)) { AppServices.nav.tab = AppTab.FIND }
            }
        }
        // Its own group, as on iOS.
        item {
            LeanrSection {
                ActionRow("Scan product barcode", Icons.Filled.QrCodeScanner) { route = MyFoodsRoute.Barcode }
                ActionRow("Import a recipe from a link", Icons.Filled.Link, divider = false) { route = MyFoodsRoute.Import }
            }
        }
        item { Text("SAVED FOODS & RECIPES", style = LeanrType.footnote, color = c.secondaryText, modifier = Modifier.padding(start = 16.dp, bottom = 6.dp)) }
        if (rows.isEmpty()) {
            item {
                LeanrSection {
                    Column(Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally) {
                        Icon(Icons.Filled.Bookmark, null, tint = c.secondaryText, modifier = Modifier.size(36.dp))
                        Spacer(Modifier.height(8.dp))
                        Text("Your own menu", style = LeanrType.title3, color = c.text)
                        Text("Save foods, recipes and custom orders. They appear throughout the app.", style = LeanrType.subheadline, color = c.secondaryText,
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                    }
                }
            }
        }
        items(rows, key = { it.id }) { food -> MyFoodRow(food, onOpen = { route = MyFoodsRoute.Detail(food) }, onEdit = { edit(food) }) }
        item { Spacer(Modifier.height(20.dp)) }
    }
}

/** A saved food: tap to open, "+" to log one serving, swipe to delete, long-press for Edit, Pin and yesterday's meals. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MyFoodRow(food: Food, onOpen: () -> Unit, onEdit: () -> Unit) {
    val store = AppServices.store
    var menu by remember { mutableStateOf(false) }
    SwipeToDelete(onDelete = { store.deleteFood(food) }) {
        Box {
            FoodRow(food, modifier = Modifier.combinedClickable(onClick = onOpen, onLongClick = { menu = true }),
                onQuickAdd = { store.logNow(listOf(Portion(food = food)), food.name) })
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(text = { Text("Edit") }, leadingIcon = { Icon(Icons.Filled.Edit, null) }, onClick = { menu = false; onEdit() })
                val pinned = store.isPinned(food)
                DropdownMenuItem(text = { Text(if (pinned) "Unpin" else "Pin to top") }, leadingIcon = { Icon(Icons.Filled.PushPin, null) },
                    onClick = { menu = false; store.togglePin(food) })
                HorizontalDivider()
                Text("Forgot it yesterday?", style = LeanrType.caption, color = Leanr.colours.secondaryText, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
                MealTime.entries.forEach { meal ->
                    DropdownMenuItem(text = { Text("Yesterday’s ${meal.title.lowercase()}") }, onClick = {
                        menu = false; store.logNow(listOf(Portion(food = food)), food.name, meal, yesterday = true)
                    })
                }
            }
        }
    }
}

/** Which scanner the food editor has open. */
private enum class EditorScan { LOOKUP, CAPTURE, LABEL }

private const val KEEP_KEY = "barcode.saveToMyFoods"

/**
 * Add or edit one of your own foods (FoodEditor in MyFoodsView.swift). `onDone(null)` when cancelled, otherwise with the food
 * saved. By default it's saved to My foods; pass `save` to do something else with it (returning false shows "Couldn't save"),
 * or `save = null` to only hand it back. With `savePortion`, the button logs an amount instead (titled `logTitle`).
 */
@Composable
fun FoodEditorScreen(
    initial: Food?,
    onDone: (Food?) -> Unit,
    save: ((Food) -> Boolean)? = { AppServices.store.saveFood(it) },
    savePortion: ((Portion) -> Boolean)? = null,
    logTitle: String = "Log food",
    per100Initially: Boolean = false,
) {
    val store = AppServices.store
    val c = Leanr.colours
    val scope = rememberCoroutineScope()
    var draft by remember {
        var food = initial ?: Food(name = "", kj = 0.0, cal = 0.0, p = 0.0)
        // A food someone shared is edited as your own copy.
        if (food.isCommunity) food = food.copy(chain = "mine", id = newId(), contributor = null)
        mutableStateOf(food)
    }
    var energy by remember { mutableDoubleStateOf(draft.cal) }
    var energyUnit by remember { mutableStateOf("Cal") }
    var per100 by remember { mutableStateOf(per100Initially) }
    var servingSize by remember { mutableDoubleStateOf(100.0) }
    var servingUnit by remember { mutableStateOf(draft.servingWeight?.second ?: "g") }
    var servings by remember { mutableDoubleStateOf(1.0) }
    // Per-100 figures with no pack serving: log by weight, so the grams eaten can be typed straight in.
    var byWeight by remember { mutableStateOf(per100Initially && savePortion != null) }
    var weight by remember { mutableDoubleStateOf(100.0) }
    var keepInMyFoods by remember { mutableStateOf(draft.barcode != null && Prefs.bool(KEEP_KEY, true)) }
    var customNutrient by remember { mutableStateOf("") }
    var customUnit by remember { mutableStateOf("mg") }
    var customValue by remember { mutableDoubleStateOf(0.0) }
    var customOpen by remember { mutableStateOf(false) }
    var askingToShare by remember { mutableStateOf(false) }
    var checkingShare by remember { mutableStateOf(false) }
    var shareCheck by remember { mutableStateOf<String?>(null) }
    var saveFailed by remember { mutableStateOf(false) }
    var labelRead by remember { mutableStateOf(false) }
    var scan by remember { mutableStateOf<EditorScan?>(null) }
    /** Goes up whenever figures are replaced from outside the fields, so the number fields show the new values. */
    var formVersion by remember { mutableIntStateOf(0) }

    val inMyFoods = store.data.foods.any { it.id == draft.id }
    val servingWeight: Pair<Double, String>? =
        if (per100) (if (servingSize.isFinite() && servingSize > 0) servingSize to servingUnit else null) else draft.servingWeight
    val quantity = if (byWeight && servingWeight != null) weight / servingWeight.first else servings
    val barcodeCode = draft.barcode?.let { BarcodeCheck.validated(it) }
    val barcodeInvalid = !draft.barcode.isNullOrEmpty() && barcodeCode == null
    val result = run {
        val ratio = if (per100) servingSize / 100 else 1.0
        val cal = ((if (energyUnit == "kJ") energy / 4.184 else energy) * ratio).tenth
        // Saved foods keep one decimal place, like everywhere they're shown.
        draft.copy(
            name = draft.name.trim(), cal = cal, kj = cal * 4.184, p = (draft.p * ratio).tenth, c = draft.c?.let { (it * ratio).tenth },
            f = draft.f?.let { (it * ratio).tenth }, nut = draft.nut?.mapValues { (it.value * ratio).tenth },
            serve = if (per100) "${servingSize.number} $servingUnit" else draft.serve, barcode = barcodeCode,
        )
    }
    /** Everything typed into this food that others could read: its name, serving and any nutrient you named. */
    val namedTexts = listOf(draft.name, draft.serve) + (draft.nut ?: emptyMap()).keys
    val canSave = result.isValid && !ContentFilter.flags(namedTexts) && !barcodeInvalid && servingSize > 0 &&
        quantity.isFinite() && quantity > 0 && quantity <= 10000

    /** Fills the editor from a scanned product, keeping this food's ID, sharing and barcode. */
    fun applyProduct(product: Food) {
        val wasShared = draft.shared; val existingBarcode = draft.barcode; val id = draft.id
        var food = product.copy(id = id, shared = wasShared)
        if (product.isCommunity) food = food.copy(chain = "mine", contributor = null)
        if (food.barcode == null) food = food.copy(barcode = existingBarcode)
        if (food.chain != "mine") food = food.copy(chain = "mine", modifiers = null)
        draft = food
        per100 = false; servingSize = 100.0; servingUnit = food.servingWeight?.second ?: "g"
        servings = 1.0; byWeight = false; weight = 100.0
        if (draft.barcode != null) keepInMyFoods = Prefs.bool(KEEP_KEY, true)
        energyUnit = "Cal"; energy = product.cal; labelRead = false
        formVersion++
    }

    /** Fills the figures from a nutrition label, keeping the name if the label didn't give one. */
    fun applyLabel(label: Food) {
        draft = draft.copy(name = draft.name.ifBlank { label.name }, serve = label.serve.ifBlank { draft.serve }, p = label.p, c = label.c, f = label.f,
            nut = label.nut, barcode = draft.barcode ?: label.barcode)
        per100 = false; servingUnit = label.servingWeight?.second ?: "g"; servings = 1.0
        energyUnit = "Cal"; energy = label.cal; labelRead = true
        formVersion++
    }

    /** The food to save: still marked shared only if it passes the sharing rules, with a notice saying why when it doesn't. */
    fun sharable(food: Food): Food {
        val problem = if (food.shared == true) SharingRules.problem(food) else null
        if (problem == null) return food
        store.notice = "Saved, but not shared. $problem"
        return food.copy(shared = null)
    }

    fun confirm() {
        if (savePortion != null) {
            var item = result
            if (keepInMyFoods && !inMyFoods) store.saveToMyFoods(item)?.let { item = it }
            if (savePortion(Portion(food = item, quantity = quantity))) onDone(item) else saveFailed = true
        } else {
            val value = sharable(result)
            if (save == null || save(value)) onDone(value) else saveFailed = true
        }
    }

    when (scan) {
        EditorScan.LOOKUP -> { BarcodeScanScreen(onFound = { applyProduct(it); scan = null }, onDismiss = { scan = null }); return }
        EditorScan.CAPTURE -> { BarcodeScanScreen(onFound = { f -> f.barcode?.let { draft = draft.copy(barcode = it) }; scan = null }, onDismiss = { scan = null }); return }
        EditorScan.LABEL -> { LabelScanScreen(onFood = { applyLabel(it); scan = null }, onDismiss = { scan = null }); return }
        null -> {}
    }
    BackHandler { onDone(null) }

    LeanrScreen("Food details", onBack = { onDone(null) }, showSettings = false, actions = {
        TextButton(onClick = { confirm() }, enabled = canSave) {
            Text(if (savePortion == null) "Save" else logTitle, style = LeanrType.headline, color = if (canSave) c.accent else c.tertiaryText)
        }
    }) {
        item {
            key(formVersion) {
                LeanrSection("Food") {
                    TextRow(draft.name, { draft = draft.copy(name = it) }, "Name")
                    if (!per100) TextRow(draft.serve, { draft = draft.copy(serve = it) }, "Serving size (e.g. 150 g)")
                    OffensiveTextNote(namedTexts)
                    // Per-100 figures are logged by the weight eaten unless you switch back to servings.
                    ToggleRow("Enter nutrition per 100 g / mL", per100, { per100 = it; if (savePortion != null) byWeight = it }, divider = per100)
                    if (per100) {
                        NumberField("Size of one serving", servingSize, { servingSize = it })
                        SegmentedRow(listOf("g" to "g", "mL" to "mL"), servingUnit, { servingUnit = it }, divider = false)
                        SectionNote("Leave this at 100 to keep the label's figures, or enter the pack's serving size.")
                        ActionRow("Convert to per serving", enabled = servingSize.isFinite() && servingSize > 0, divider = false) {
                            val converted = result
                            draft = converted
                            energy = if (energyUnit == "kJ") converted.kj else converted.cal
                            per100 = false
                            formVersion++
                        }
                    }
                }
            }
        }
        if (savePortion != null) {
            item {
                key(formVersion) {
                    LeanrSection("How much you had") {
                        if (servingWeight != null) {
                            SegmentedRow(listOf(false to "Servings", true to (if (servingWeight.second == "g") "Grams" else "mL")), byWeight, { byWeight = it })
                            if (byWeight) {
                                NumberField("Amount (${servingWeight.second})", weight, { weight = it })
                                SectionNote("${weight.number} ${servingWeight.second} is ${twoPlaces(quantity)} × the ${servingWeight.first.number} ${servingWeight.second} serving.")
                            }
                        }
                        if (!byWeight || servingWeight == null) {
                            NumberField("Number of servings", servings, { servings = it })
                            SectionNote(if (servingWeight == null) "Add a weight to the serving size, like 150 g, to enter grams instead." else "For example, 0.5 for half a serving or 2 for two servings.")
                        }
                        if (!inMyFoods) ToggleRow("Save to My foods", keepInMyFoods, { value ->
                            keepInMyFoods = value
                            if (draft.barcode != null) Prefs.set(KEEP_KEY, value)
                        }, divider = false)
                    }
                }
            }
        }
        item {
            LeanrSection("Barcode", footer = "Add the barcode when scanning doesn't find this product. Next time you scan it, Leanrrr opens this food.") {
                TextRow(draft.barcode ?: "", { v -> draft = draft.copy(barcode = v.ifEmpty { null }) }, "Barcode number", keyboard = KeyboardType.Number,
                    leading = Icons.Filled.QrCode, divider = barcodeInvalid || barcodeCode != null) {
                    if (draft.barcode != null) IconButton(onClick = { draft = draft.copy(barcode = null) }) { Icon(Icons.Filled.Close, "Remove barcode", tint = c.secondaryText) }
                    IconButton(onClick = { scan = EditorScan.CAPTURE }) { Icon(Icons.Filled.QrCodeScanner, "Scan barcode", tint = c.accent) }
                }
                if (barcodeInvalid) {
                    SectionNote("Check the digits. Product barcodes have 8, 12, 13 or 14 digits.", warningColour)
                } else if (barcodeCode != null) {
                    BarcodeCheck.match(barcodeCode, store.data.foods.filter { it.id != draft.id })?.let { other ->
                        SectionNote("${other.name} already has this barcode. Scanning it will open that food.", warningColour)
                    }
                }
            }
        }
        item {
            LeanrSection("Find a packaged food") {
                ActionRow("Scan product barcode", Icons.Filled.QrCodeScanner, divider = draft.note?.startsWith("Source: Open Food Facts") == true) { scan = EditorScan.LOOKUP }
                draft.note?.takeIf { it.startsWith("Source: Open Food Facts") }?.let { note ->
                    SectionNote(note)
                    SectionNote("Confirm the nutrition basis and serving amount below before saving.")
                }
            }
        }
        item {
            LeanrSection("Read a nutrition label") {
                Button(onClick = { scan = EditorScan.LABEL }, modifier = Modifier.fillMaxWidth().padding(16.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = c.accent, contentColor = if (c.dark) Color.Black else Color.White)) {
                    Icon(Icons.Filled.DocumentScanner, null); Spacer(Modifier.size(8.dp)); Text("Scan nutrition label")
                }
                SectionNote("Fit the nutrition panel in the frame, then check the figures it fills in.")
                SectionNote("When calories aren’t listed, Leanrrr converts kilojoules to calories automatically (kJ ÷ 4.184).")
                if (labelRead) SectionNote("Check every number and whether the column is per serving or per 100 g before saving. Text recognition can misread labels.", warningColour)
                else SectionNote("Reads text on your device. No image upload or account is needed.")
            }
        }
        item {
            key(formVersion) {
                LeanrSection(if (per100) "Nutrition per 100 $servingUnit" else "Nutrition per serving") {
                    MenuRow("Energy unit", listOf("Cal" to "Calories", "kJ" to "Kilojoules"), energyUnit, { new ->
                        if (new != energyUnit) {
                            energy = if (new == "kJ") energy * 4.184 else energy / 4.184
                            energyUnit = new
                            formVersion++
                        }
                    })
                    NumberField("Energy ($energyUnit)", energy, { energy = it })
                    NumberField("Protein (g)", draft.p, { draft = draft.copy(p = it) })
                    OptionalNumberField("Carbs (g)", draft.c, { draft = draft.copy(c = it) })
                    OptionalNumberField("Fat (g)", draft.f, { draft = draft.copy(f = it) }, divider = false)
                }
            }
        }
        item {
            key(formVersion) {
                LeanrSection("Optional nutrients") {
                    fun setNut(key: String, value: Double?) {
                        val nut = (draft.nut ?: emptyMap()).toMutableMap()
                        if (value == null) nut.remove(key) else nut[key] = value
                        draft = draft.copy(nut = nut.ifEmpty { null })
                    }
                    nutrientNames.drop(4).forEach { n -> OptionalNumberField("${n.label} (${n.unit})", draft.nut?.get(n.key), { setNut(n.key, it) }) }
                    (draft.nut ?: emptyMap()).keys.filter { key -> nutrientNames.none { it.key == key } }.sorted().forEach { key ->
                        OptionalNumberField(key, draft.nut?.get(key), { setNut(key, it) })
                    }
                    LeanrRow("Another nutrient", divider = customOpen, onClick = { customOpen = !customOpen }, titleColour = c.accent, trailing = {
                        Icon(if (customOpen) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, null, tint = c.accent)
                    })
                    AnimatedVisibility(customOpen) {
                        Column {
                            TextRow(customNutrient, { customNutrient = it }, "Nutrient name")
                            MenuRow("Unit", listOf("g", "mg", "µg", "%").map { it to it }, customUnit, { customUnit = it })
                            key(customValue == 0.0 && customNutrient.isEmpty()) { NumberField("Amount", customValue, { customValue = it }) }
                            OffensiveTextNote(customNutrient)
                            ActionRow("Add nutrient", enabled = customNutrient.isNotBlank() && customValue >= 0 && !ContentFilter.flags(customNutrient), divider = false) {
                                setNut("$customNutrient ($customUnit)", customValue)
                                customNutrient = ""; customValue = 0.0
                                formVersion++
                            }
                        }
                    }
                }
            }
        }
        item { LeanrSection("Per-serving preview") { NutritionView(Nutrition(listOf(Portion(food = result)))) } }
        if (savePortion == null) {
            item {
                LeanrSection("Sharing", footer = "Others find shared foods in search and when they scan the barcode. Your name isn't shown. Turn this off or delete the food to take it down.") {
                    ToggleRow("Share with other Leanrrr users", draft.shared == true, { on ->
                        if (on) scope.launch {
                            checkingShare = true
                            val problem = CommunityFoods.canShare()
                            checkingShare = false
                            if (problem != null) { shareCheck = problem; return@launch }
                            shareCheck = null
                            if (CommunityFoods.agreed) draft = draft.copy(shared = true) else askingToShare = true
                        } else { draft = draft.copy(shared = null); shareCheck = null }
                    }, enabled = !checkingShare, divider = false, leading = Icons.Filled.People)
                    if (draft.shared == true) SharingRules.problem(result)?.let { SectionNote("Can't be shared yet. $it", warningColour) }
                    shareCheck?.let { SectionNote(it, warningColour) }
                }
            }
        } else {
            item {
                val title = if (byWeight && servingWeight != null) "Total for ${weight.number} ${servingWeight.second}" else "Total for ${servings.number} servings"
                LeanrSection(title) {
                    NutritionView(Nutrition(listOf(Portion(food = result, quantity = if (quantity.isFinite() && quantity > 0) quantity else 0.0))))
                }
            }
        }
    }

    if (askingToShare) {
        AlertDialog(onDismissRequest = { askingToShare = false }, title = { Text("Share this food with everyone?") },
            text = { Text("Anyone using Leanrrr can see foods you share, without your name. Only share real figures from the label or another trusted source, and nothing offensive. Foods that break the terms of use are taken down.") },
            confirmButton = { TextButton(onClick = { CommunityFoods.agree(); draft = draft.copy(shared = true); askingToShare = false }) { Text("Share") } },
            dismissButton = { TextButton(onClick = { askingToShare = false }) { Text("Cancel") } })
    }
    if (saveFailed) {
        AlertDialog(onDismissRequest = { saveFailed = false }, title = { Text("Couldn’t save food") },
            text = { Text("Your data was not changed. Check available storage and any data recovery message in the app.") },
            confirmButton = { TextButton(onClick = { saveFailed = false }) { Text("OK") } })
    }
}

private fun twoPlaces(value: Double): String =
    if (!value.isFinite()) "–" else java.text.DecimalFormat("#,##0.##", java.text.DecimalFormatSymbols(java.util.Locale.US)).format(value)
