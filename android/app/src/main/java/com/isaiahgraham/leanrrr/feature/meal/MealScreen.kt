package com.isaiahgraham.leanrrr.feature.meal

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.QuickLog
import com.isaiahgraham.leanrrr.data.SavedMeal
import com.isaiahgraham.leanrrr.data.combined
import com.isaiahgraham.leanrrr.data.isToday
import com.isaiahgraham.leanrrr.data.mealText
import com.isaiahgraham.leanrrr.data.newId
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.feature.scan.BarcodeScanScreen
import com.isaiahgraham.leanrrr.ui.components.ActionTile
import com.isaiahgraham.leanrrr.ui.components.LeanrRow
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.components.NutritionView
import com.isaiahgraham.leanrrr.ui.components.TileRow
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import java.time.LocalDate
import java.time.ZoneId

// A port of MealView.swift: the meal being built (the tray), its totals, logging it, saving it and sharing it,
// one-tap "Log again", and saved meals with their editor (SavedMealEditor).

private sealed interface MealRoute {
    data object MyFoods : MealRoute
    data object Picking : MealRoute
    data object Scanning : MealRoute
    data class ScannedEditor(val food: Food) : MealRoute
    data object MakingImage : MealRoute
    data class EditMeal(val meal: SavedMeal) : MealRoute
}

@Composable
fun MealScreen() {
    val store = AppServices.store
    val c = Leanr.colours
    val context = LocalContext.current
    var route by remember { mutableStateOf<MealRoute?>(null) }
    var name by remember { mutableStateOf("") }
    var date by remember { mutableStateOf(LocalDate.now()) }
    var mealTime by remember { mutableStateOf(MealTime.suggested()) }
    var clearing by remember { mutableStateOf(false) }
    val tray = store.data.tray
    /** What's in the meal, customisations included, e.g. "McChicken · No McChicken Sauce, 2 × Small Fries". */
    val suggestedName = tray.joinToString(", ") { (if (it.quantity == 1.0) "" else "${it.quantity.number} × ") + it.food.name }.ifEmpty { "My meal" }
    val title = name.trim().ifEmpty { suggestedName }

    when (val r = route) {
        MealRoute.MyFoods -> { MyFoodsScreen(onBack = { route = null }); return }
        MealRoute.Picking -> { FoodPickerScreen("Add to meal", onPick = { store.add(listOf(it)); route = null }, onDone = { route = null }); return }
        // A packet's barcode goes straight into the meal; the editor is there if the serving needs changing.
        MealRoute.Scanning -> {
            BarcodeScanScreen(onFound = { route = MealRoute.ScannedEditor(it) }, onDismiss = { route = null }); return
        }
        is MealRoute.ScannedEditor -> {
            FoodEditorScreen(r.food, onDone = { route = null }, savePortion = { store.add(listOf(it)) }, logTitle = "Add to meal"); return
        }
        MealRoute.MakingImage -> { MealSharePreview(title, tray, onDismiss = { route = null }); return }
        is MealRoute.EditMeal -> { SavedMealEditor(r.meal, onClose = { route = null }); return }
        null -> {}
    }

    LeanrScreen("This meal", actions = {
        if (tray.isNotEmpty()) TextButton(onClick = { clearing = true }) { Text("Clear", color = if (c.dark) Color(0xFFFF453A) else Color(0xFFD70015)) }
    }) {
        item {
            LeanrSection {
                LeanrRow("My foods", divider = false, leading = { Icon(Icons.Outlined.BookmarkBorder, null, tint = c.accent) }, onClick = { route = MealRoute.MyFoods },
                    trailing = { if (store.data.foods.isNotEmpty()) Text("${store.data.foods.size}", style = LeanrType.subheadline, color = c.secondaryText) })
            }
        }
        // A short prompt rather than a full-height empty state, so the log shortcuts below stay on screen.
        if (tray.isEmpty()) {
            item {
                Box(Modifier.clip(RoundedCornerShape(topStart = 12.dp, topEnd = 12.dp)).background(c.card)) {
                    LeanrRow("Build your meal", "Add foods here, or send an order from Find.", leading = { Icon(Icons.Filled.Restaurant, null, tint = c.secondaryText) })
                }
            }
        } else {
            item { Spacer(Modifier.clip(RoundedCornerShape(topStart = 12.dp, topEnd = 12.dp)).background(c.card).fillMaxWidth().padding(top = 4.dp)) }
        }
        items(tray, key = { it.id }) { item ->
            SwipeToDelete(onDelete = { store.removeFromTray(item.id) }) {
                Column {
                    Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp, top = 8.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(item.food.name, style = LeanrType.headline, color = c.text)
                            Text("${(item.food.cal * item.quantity).number} Cal · ${(item.food.p * item.quantity).number} g protein", style = LeanrType.caption, color = c.secondaryText)
                        }
                        QuantityStepper(item.quantity, { store.setTrayQuantity(item.id, it) }, item.food.name)
                    }
                    androidx.compose.material3.HorizontalDivider(Modifier.padding(start = 16.dp), color = c.separator, thickness = 0.5.dp)
                }
            }
        }
        item {
            Box(Modifier.padding(bottom = 20.dp).clip(RoundedCornerShape(bottomStart = 12.dp, bottomEnd = 12.dp)).background(c.card)) {
                Column {
                    ActionRow("Add food", Icons.Filled.AddCircle) { route = MealRoute.Picking }
                    ActionRow("Scan barcode", Icons.Filled.QrCodeScanner, divider = false) { route = MealRoute.Scanning }
                }
            }
        }
        if (tray.isNotEmpty()) {
            item { LeanrSection("Meal totals") { NutritionView(Nutrition(tray)) } }
            item {
                LeanrSection("Log it") {
                    TextRow(name, { name = it }, suggestedName, singleLine = false)
                    OffensiveTextNote(name)
                    DateRow("Log date", date, { date = it })
                    MealTimeRow("Meal time", mealTime, { mealTime = it })
                    Button(
                        onClick = {
                            if (store.log(tray, title, date, clearTray = true, mealTime = mealTime)) {
                                store.notice = "Logged to ${date.abbreviated()}"; name = ""
                            }
                        },
                        enabled = !ContentFilter.flags(name),
                        colors = ButtonDefaults.buttonColors(containerColor = c.accent, contentColor = if (c.dark) Color.Black else Color.White),
                        shape = RoundedCornerShape(12.dp),
                        modifier = Modifier.fillMaxWidth().padding(16.dp).heightIn(min = 50.dp),
                    ) { Text("Log meal", style = LeanrType.headline) }
                }
            }
            item {
                TileRow(Modifier.padding(bottom = 20.dp)) {
                    val flagged = ContentFilter.flags(name)
                    ActionTile("Save for later", Icons.Outlined.BookmarkBorder, Modifier.weight(1f)) {
                        if (flagged) store.refuse(ContentFilter.FLAG_MESSAGE)
                        else if (store.saveMeal(title, tray)) store.notice = "Meal saved"
                    }
                    ActionTile("Share text", Icons.Filled.Share, Modifier.weight(1f)) {
                        val send = Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, mealText(title, tray)) }
                        context.startActivity(Intent.createChooser(send, null))
                    }
                    ActionTile("Copy", Icons.Filled.ContentCopy, Modifier.weight(1f)) {
                        context.getSystemService(ClipboardManager::class.java)?.setPrimaryClip(ClipData.newPlainText(title, mealText(title, tray)))
                        store.notice = "Meal copied"
                    }
                    ActionTile("Make image", Icons.Filled.Image, Modifier.weight(1f)) { route = MealRoute.MakingImage }
                }
            }
        }
        quickLog(this, mealTime, { mealTime = it }, date, tray.isEmpty())
        if (store.data.meals.isNotEmpty()) {
            item { Text("SAVED MEALS", style = LeanrType.footnote, color = c.secondaryText, modifier = Modifier.padding(start = 16.dp, bottom = 6.dp)) }
            items(store.data.meals, key = { "meal-" + it.id }) { meal ->
                SwipeToDelete(onDelete = { store.deleteMeal(meal.id) }) {
                    Column {
                        Row(Modifier.fillMaxWidth().clickable { route = MealRoute.EditMeal(meal) }.padding(start = 16.dp, end = 12.dp, top = 10.dp, bottom = 10.dp),
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text(meal.name, style = LeanrType.headline, color = c.text)
                                Text(Nutrition(meal.items).text, style = LeanrType.caption, color = c.secondaryText)
                            }
                            OutlinedButton(onClick = { store.add(meal.items) }) { Text("Add", style = LeanrType.subheadline.copy(fontWeight = FontWeight.Medium), color = c.accent) }
                        }
                        androidx.compose.material3.HorizontalDivider(Modifier.padding(start = 16.dp), color = c.separator, thickness = 0.5.dp)
                    }
                }
            }
            item { Spacer(Modifier.padding(bottom = 20.dp)) }
        }
        // "Left today" ideas (LeftToday.swift, owned by Today).
        item(key = "left-today") { com.isaiahgraham.leanrrr.feature.today.LeftTodaySection(mealTime) }
    }
    if (clearing) ConfirmDialog("Clear this meal?", "Clear meal", onConfirm = { store.clearTray() }, onDismiss = { clearing = false })
}

/** One-tap logging: the same meal as yesterday, or a meal you log often. */
private fun quickLog(scope: androidx.compose.foundation.lazy.LazyListScope, mealTime: MealTime, setMealTime: (MealTime) -> Unit, date: LocalDate, trayEmpty: Boolean) {
    scope.item(key = "quick-log") {
        val store = AppServices.store
        val c = Leanr.colours
        val before = date.atTime(java.time.LocalTime.now()).atZone(ZoneId.systemDefault()).toInstant()
        val yesterday = QuickLog.previous(mealTime, before, store.data.logs)
        val frequent = QuickLog.frequent(store.data.logs, before)
        if (yesterday.isEmpty() && frequent.isEmpty()) return@item
        val day = if (date.isToday()) "today" else "on " + date.abbreviated()
        LeanrSection("Log again", footer = "Logs straight to ${mealTime.title.lowercase()} $day, without changing the meal you're building.") {
            if (trayEmpty) MealTimeRow("Log to", mealTime, setMealTime)
            if (yesterday.isNotEmpty()) {
                val items = yesterday.flatMap { it.items }
                LeanrRow("Same as yesterday’s ${mealTime.title.lowercase()}", yesterday.joinToString(", ") { it.name },
                    divider = frequent.isNotEmpty(),
                    leading = { Icon(Icons.Filled.Replay, null, tint = c.accent) },
                    trailing = { Text("${Nutrition(items).cal.number} Cal", style = LeanrType.subheadline, color = c.secondaryText) },
                    onClick = {
                        val name = if (yesterday.size == 1) yesterday[0].name else "Yesterday’s ${mealTime.title.lowercase()}"
                        if (store.log(QuickLog.copies(items), name, date, mealTime = mealTime)) store.notice = "Logged $name"
                    })
            }
            if (frequent.isNotEmpty()) {
                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    frequent.forEach { entry ->
                        val total = Nutrition(entry.items)
                        Column(Modifier.width(150.dp).heightIn(min = 76.dp).clip(RoundedCornerShape(14.dp)).background(c.text.copy(alpha = 0.06f))
                            .clickable { if (store.log(QuickLog.copies(entry.items), entry.name, date, mealTime = mealTime)) store.notice = "Logged ${entry.name}" }
                            .padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(entry.name, style = LeanrType.subheadline.copy(fontWeight = FontWeight.Medium), color = c.text, maxLines = 2, overflow = TextOverflow.Ellipsis)
                            Spacer(Modifier.weight(1f, fill = false))
                            Text("${total.cal.number} Cal · ${total.p.number} g protein", style = LeanrType.caption, color = c.secondaryText)
                        }
                    }
                }
            }
        }
    }
}

/**
 * Changes a saved meal in place: rename it, change amounts, add foods and take them out.
 * Nothing is saved until Save, so backing out leaves the meal as it was.
 */
@Composable
fun SavedMealEditor(meal: SavedMeal, onClose: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    // A meal saved with a recipe beside other foods lists its ingredients, as a meal built today does.
    val original = remember(meal.id) { meal.copy(items = combined(meal.items)) }
    var draft by remember(meal.id) { mutableStateOf(original) }
    var picking by remember { mutableStateOf(false) }
    var confirmingDelete by remember { mutableStateOf(false) }
    val trimmedName = draft.name.trim()
    val changed = draft != original

    if (picking) {
        FoodPickerScreen("Add to ${trimmedName.ifEmpty { "meal" }}", onPick = { portion ->
            val fresh = portion.copy(id = newId())
            val i = draft.items.indexOfFirst { it.food == fresh.food }
            val items = if (i >= 0) draft.items.mapIndexed { j, it -> if (j == i) it.copy(quantity = it.quantity + fresh.quantity) else it } else draft.items + fresh
            draft = draft.copy(items = combined(items))
            picking = false
        }, onDone = { picking = false })
        return
    }
    BackHandler(onBack = onClose)
    val canSave = changed && trimmedName.isNotEmpty() && draft.items.isNotEmpty() && !ContentFilter.flags(trimmedName)
    LeanrScreen("Edit meal", onBack = onClose, showSettings = false, actions = {
        TextButton(onClick = {
            val updated = draft.copy(name = trimmedName)
            if (store.updateMeal(updated)) { store.notice = "Saved ${updated.name}"; onClose() }
        }, enabled = canSave) { Text("Save", style = LeanrType.headline, color = if (canSave) c.accent else c.tertiaryText) }
    }) {
        item {
            LeanrSection("Name") {
                TextRow(draft.name, { draft = draft.copy(name = it) }, "Meal name", singleLine = false, divider = false)
                OffensiveTextNote(draft.name)
            }
        }
        item { Text("ITEMS", style = LeanrType.footnote, color = c.secondaryText, modifier = Modifier.padding(start = 16.dp, bottom = 6.dp)) }
        if (draft.items.isEmpty()) item { Box(Modifier.background(c.card)) { LeanrRow("Add at least one food to keep this meal.", titleColour = c.secondaryText) } }
        items(draft.items, key = { it.id }) { item ->
            SwipeToDelete(onDelete = { draft = draft.copy(items = draft.items.filter { it.id != item.id }) }) {
                Column {
                    Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp, top = 8.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(item.food.name, style = LeanrType.headline, color = c.text)
                            Text("${(item.food.cal * item.quantity).number} Cal · ${(item.food.p * item.quantity).number} g protein", style = LeanrType.caption, color = c.secondaryText)
                        }
                        QuantityStepper(item.quantity, { q -> draft = draft.copy(items = draft.items.map { if (it.id == item.id) it.copy(quantity = q) else it }) },
                            "${item.food.name} amount")
                    }
                    androidx.compose.material3.HorizontalDivider(Modifier.padding(start = 16.dp), color = c.separator, thickness = 0.5.dp)
                }
            }
        }
        item {
            LeanrSection(footer = "Swipe an item to remove it.") { ActionRow("Add food", Icons.Filled.AddCircle, divider = false) { picking = true } }
        }
        if (draft.items.isNotEmpty()) item { LeanrSection("Totals") { NutritionView(Nutrition(draft.items)) } }
        item { LeanrSection { ActionRow("Delete saved meal", destructive = true, divider = false) { confirmingDelete = true } } }
    }
    if (confirmingDelete) ConfirmDialog("Delete ${original.name}?", "Delete saved meal", onConfirm = {
        if (store.deleteMeal(original.id)) onClose()
    }, onDismiss = { confirmingDelete = false })
}
