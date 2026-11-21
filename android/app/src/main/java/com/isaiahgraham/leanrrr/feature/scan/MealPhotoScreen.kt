package com.isaiahgraham.leanrrr.feature.scan

import android.graphics.Bitmap
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowCircleUp
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
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
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.LeanrJson
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.Prefs
import com.isaiahgraham.leanrrr.data.newId
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.ui.components.BottomActionBar
import com.isaiahgraham.leanrrr.ui.components.Chip
import com.isaiahgraham.leanrrr.ui.components.ChipRow
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.components.LogTargetPicker
import com.isaiahgraham.leanrrr.ui.components.NumberField
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import java.time.LocalDate

/** PhotoMemory's choices in preferences, on this device only. */
internal object PhotoMemoryStore {
    private val serializer = MapSerializer(String.serializer(), PhotoMemory.Choice.serializer())
    fun load(): Map<String, PhotoMemory.Choice> =
        runCatching { LeanrJson.decodeFromString(serializer, Prefs.string(PhotoMemory.STORAGE_KEY) ?: "") }.getOrNull() ?: emptyMap()
    fun save(choices: Map<String, PhotoMemory.Choice>) = Prefs.set(PhotoMemory.STORAGE_KEY, LeanrJson.encodeToString(serializer, choices))
}

/** One food named for the photo, and what to log for it (MealPhotoView.Row). */
private data class PhotoRow(
    val seen: SeenFood,
    val matches: List<Food>,
    /** The match to log, or null to leave it out. */
    val chosen: String?,
    val quantity: Double,
    /** For everyday and your own foods: how big each one was. Changing it sets the servings. */
    val size: PortionSize,
    /** Why a match was ticked for you, when it wasn't the usual first match. */
    val note: String? = null,
    val id: String = newId(),
) {
    val food: Food? get() = matches.firstOrNull { it.id == chosen }
    /** Servings for the chosen food: the count, scaled by the portion size where sizes apply. */
    fun servings(food: Food?): Double = seen.count * (if (food != null && PortionSize.applies(food)) size.factor else 1.0)
}

/**
 * Photo of your meal (MealPhotoView.swift). On iOS Apple's image classifier names the foods in the photo; ML Kit has no
 * food classifier here, so that part is left out. What stays: the photo, a barcode in shot opening the product scanner,
 * brand names and words read off packaging (text recognition on the phone), and what you write naming the foods. Leanrrr
 * finds each in its own foods, ticks what you logged for it last time (PhotoMemory), and you check each before logging.
 */
@Composable
fun MealPhoto(onDismiss: () -> Unit, mealTime: MealTime = MealTime.suggested()) {
    val store = AppServices.store
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var image by remember { mutableStateOf<Bitmap?>(null) }
    var looking by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<String?>(null) }
    var camera by remember { mutableStateOf(false) }
    var barcodeScan by remember { mutableStateOf<String?>(null) }
    var photoBarcode by remember { mutableStateOf<String?>(null) }
    var packagingBrand by remember { mutableStateOf<String?>(null) }
    val packagingWords = remember { mutableStateListOf<String>() }
    val rows = remember { mutableStateListOf<PhotoRow>() }
    var noteText by remember { mutableStateOf("") }
    var readingNote by remember { mutableStateOf(false) }
    var applied by remember { mutableStateOf(false) }
    var searching by remember { mutableStateOf<String?>(null) }
    var failed by remember { mutableStateOf(false) }
    var meal by remember { mutableStateOf(mealTime) }
    var yesterday by remember { mutableStateOf(false) }
    val portions = rows.mapNotNull { row -> row.food?.let { Portion(food = it, quantity = row.quantity) } }
    val chainNames = store.catalog.chains.associate { it.id to it.name } + (Food.EVERYDAY to store.chainName(Food.EVERYDAY))

    fun reset() { image = null; rows.clear(); noteText = ""; failure = null; photoBarcode = null; packagingBrand = null; packagingWords.clear(); applied = false }

    fun look(picked: Bitmap) {
        reset(); image = picked; looking = true
        val foods = store.foods
        scope.launch {
            try {
                val small = withContext(Dispatchers.Default) { picked.scaledDown(1600) }
                photoBarcode = barcodesIn(small).firstOrNull()
                val text = TextReader.recognise(small)
                val lines = text.textBlocks.flatMap { block -> block.lines.map { it.text.trim() } }.filter { line -> line.any { it.isLetter() } }
                val found = withContext(Dispatchers.Default) {
                    // A restaurant's name on a wrapper, cup or box. Only short lines, so a sentence isn't taken for a brand.
                    val brand = lines.filter { spaceWords(it).size <= 4 }.firstNotNullOfOrNull { line -> MealPhoto.chain(line, chainNames)?.let { line to it } }
                    val words = lines.filter { spaceWords(it).size in 1..5 && it != brand?.first }.distinct()
                        .filter { MealPhoto.matches(SeenFood(it), foods, chainNames, limit = 1).isNotEmpty() }.take(4)
                    brand to words
                }
                packagingBrand = found.first?.second
                packagingWords.addAll(found.second)
                looking = false
            } catch (e: Exception) {
                looking = false
                failure = "Couldn't look at this photo. Try another, or search for the food instead."
            }
        }
    }

    /** Reads what you wrote and lists those foods, ticked as you logged them last time, or as the usual pick. */
    fun applyNote() {
        val words = noteText.trim()
        if (words.isEmpty() || readingNote || looking) return
        readingNote = true
        val foods = store.foods
        val brand = packagingBrand?.let { chainNames[it] }
        val choices = PhotoMemoryStore.load()
        scope.launch {
            val made = withContext(Dispatchers.Default) {
                val known = foods.map { " " + ScanSearch.tokens(it.name).filter { w -> w !in setOf("and", "with", "n") }.joinToString(" ") + " " }.toHashSet()
                val phrases = NoteFoods.read(words) { candidate ->
                    val wanted = " " + ScanSearch.tokens(candidate).filter { it !in setOf("and", "with", "n") }.joinToString(" ") + " "
                    known.any { it.contains(wanted) }
                }.map { if (it.brand == null && brand != null) it.copy(brand = brand) else it }
                phrases.map { seen ->
                    val matches = MealPhoto.matches(seen, foods, chainNames)
                    val remembered = PhotoMemory.choice(seen, choices)
                    val rememberedFood = remembered?.let { r -> matches.firstOrNull { it.id == r.foodID } ?: foods.firstOrNull { it.id == r.foodID } }
                    if (remembered != null && rememberedFood != null) {
                        PhotoRow(seen, listOf(rememberedFood) + matches.filter { it.id != rememberedFood.id }.take(3), rememberedFood.id,
                            remembered.perItem * seen.count, PortionSize.REGULAR, note = "Ticked as what you logged for this last time")
                    } else {
                        // The brand's item, an everyday food, or the only restaurant that has it ("big mac" is only at McDonald's).
                        val pick = MealPhoto.preselected(matches, seen, chainNames)
                            ?: matches.firstOrNull()?.takeIf { first -> seen.brand == null && matches.all { it.chain == first.chain } }
                        val row = PhotoRow(seen, matches, pick?.id, 0.0, seen.size)
                        row.copy(quantity = row.servings(pick))
                    }
                }
            }
            rows.clear(); rows.addAll(made)
            applied = true
            readingNote = false
        }
    }

    val picker = rememberPhotoPicker { uri ->
        scope.launch {
            val bitmap = loadPhoto(context, uri, 1600)
            if (bitmap == null) failure = "That photo couldn't be opened. Try another." else look(bitmap)
        }
    }

    // A packet in shot: the product scanner finds its exact figures, then logs it like any other way in.
    barcodeScan?.let { code ->
        BarcodeScan(
            onFound = { food -> if (store.log(listOf(Portion(food = food)), food.name, logDate(yesterday), mealTime = meal)) onDismiss() },
            onDismiss = { barcodeScan = null },
            quick = BarcodeQuick.Log { portion ->
                val ok = store.log(listOf(portion), portion.food.name, logDate(yesterday), mealTime = meal)
                if (ok) onDismiss()
                ok
            },
            dismissAfterUse = false,
            initialCode = code.ifEmpty { null },
        )
        return
    }
    if (camera) {
        PhotoCamera("From above, with the food filling the square", onCancel = { camera = false },
            onPhotos = { photos -> camera = false; photos.firstOrNull()?.let(::look) },
            onBarcode = { camera = false; barcodeScan = "" })
        return
    }
    searching?.let { target ->
        ScanFoodSearch(rows.firstOrNull { it.id == target }?.seen?.name ?: "", onDismiss = { searching = null }, onPick = { portion ->
            val index = rows.indexOfFirst { it.id == target }
            if (index >= 0) {
                val row = rows[index]
                rows[index] = row.copy(matches = listOf(portion.food) + row.matches.filter { it.id != portion.food.id }, chosen = portion.food.id,
                    quantity = portion.quantity, note = null)
            }
            searching = null
        })
        return
    }

    BackHandler(onBack = onDismiss)
    LeanrScreen("Photo of your meal", onBack = onDismiss, bottomBar = {
        if (portions.isNotEmpty()) {
            BottomActionBar("Log ${portions.size} to ${meal.title} · ${Nutrition(portions).cal.roundedAway().number} Cal", enabled = portions.all { it.isValid }) {
                if (store.log(portions, portions.joinToString(" + ") { it.food.name }, logDate(yesterday), mealTime = meal)) {
                    store.notice = "Logged to ${if (yesterday) "yesterday’s " else ""}${meal.title.lowercase()}"
                    val logged = rows.mapNotNull { row -> row.food?.let { PhotoMemory.Logged(row.seen, it, row.quantity) } }
                    PhotoMemoryStore.save(PhotoMemory.remembering(logged, PhotoMemoryStore.load()))
                    onDismiss()
                } else failed = true
            }
        }
    }) {
        val picture = image
        if (picture == null) {
            item {
                LeanrSection(footer = "Your phone reads any barcode and words on packaging in the photo. Nothing is saved or sent anywhere. " +
                    "The figures are Leanrrr's own, so check each match and how much you had.") {
                    ActionRow("Take a photo", icon = Icons.Filled.CameraAlt, divider = true) { camera = true }
                    ActionRow("Choose from Photos", icon = Icons.Filled.PhotoLibrary) { picker.launch(imagesOnly) }
                    failure?.let { Body(it, secondary = true) }
                }
            }
        } else {
            item {
                LeanrSection {
                    Image(picture.asImageBitmap(), "Your photo", contentScale = ContentScale.Fit,
                        modifier = Modifier.fillMaxWidth().heightIn(max = 220.dp).padding(12.dp).clip(RoundedCornerShape(12.dp)))
                    if (looking) ProgressRow("Looking at your photo…")
                    failure?.let { Body(it, secondary = true) }
                    packagingBrand?.let { Caption("The packaging says ${store.chainName(it)}, so its menu is searched first.") }
                    if (!looking) ActionRow("Use a different photo", icon = Icons.Filled.Refresh) { reset() }
                }
            }
            photoBarcode?.let { code ->
                item {
                    LeanrSection(footer = "A packet's barcode gives its exact figures.") {
                        ActionRow("Barcode in shot · Scan the product", icon = Icons.Filled.QrCodeScanner) { barcodeScan = code }
                    }
                }
            }
            // What you write is what's looked up: the photo can't tell tofu from chicken, or a bowl from soup.
            item {
                LeanrSection(footer = if (readingNote) "Reading what you wrote…" else
                    "Name the foods and Leanrrr finds them in its own foods. Telling what's on a plate from the picture alone isn't available on Android yet.") {
                    FieldRow(noteText, { noteText = it }, "What's in it? e.g. tofu, rice and salad", trailing = {
                        if (noteText.isNotBlank()) IconButton(onClick = { applyNote() }, enabled = !readingNote && !looking) {
                            Icon(Icons.Filled.ArrowCircleUp, "Use what you wrote", tint = Leanr.colours.accent)
                        }
                    })
                }
            }
            if (packagingWords.isNotEmpty()) item {
                Text("Words on the packaging", style = LeanrType.footnote, color = Leanr.colours.secondaryText, modifier = Modifier.padding(start = 16.dp))
                ChipRow(Modifier.padding(bottom = 16.dp)) {
                    packagingWords.forEach { word ->
                        Chip(word, selected = false) { noteText = listOf(noteText.trim(), word).filter { it.isNotEmpty() }.joinToString(", ") }
                    }
                }
            }
        }
        if (applied) {
            if (rows.isEmpty()) item { LeanrSection { Body("No food found in what you wrote. Try plainer names, or search for it instead.", secondary = true) } }
            else item {
                LeanrSection {
                    LogTargetPicker(yesterday, { yesterday = it }, meal, { meal = it }, Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
                    Caption("Found from what you wrote. Check each match and how much you had.")
                }
            }
            rows.forEachIndexed { index, row ->
                item(key = row.id) {
                    PhotoRowSection(row, onChange = { rows[index] = it }, onSearch = { searching = row.id })
                }
            }
        }
    }
    if (failed) AlertDialog(onDismissRequest = { failed = false }, confirmButton = { TextButton({ failed = false }) { Text("OK") } },
        title = { Text("Couldn’t log that") }, text = { Text("Your data was not changed. Check available storage and try again.") })
}

private fun logDate(yesterday: Boolean): LocalDate = if (yesterday) LocalDate.now().minusDays(1) else LocalDate.now()

@Composable
private fun PhotoRowSection(row: PhotoRow, onChange: (PhotoRow) -> Unit, onSearch: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    val header = (if (row.seen.count > 1) "${row.seen.count} × " else "") + row.seen.name + (row.seen.brand?.let { " · $it" } ?: "")
    LeanrSection(header) {
        if (row.matches.isEmpty()) {
            Body("Not in Leanrrr yet.", secondary = true)
        } else {
            if (row.chosen == null) Caption(row.seen.reason ?: "No everyday food matched. These restaurant items have similar names. Pick one only if that's what you had.")
            if (row.note != null && row.chosen != null) {
                Row(Modifier.padding(horizontal = 16.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.CheckCircle, null, tint = c.secondaryText, modifier = Modifier.size(14.dp)); Spacer(Modifier.width(6.dp))
                    Text(row.note, style = LeanrType.caption, color = c.secondaryText)
                }
            }
            // Picking here resets the amount; a food picked from search keeps the amount chosen there.
            var open by remember { mutableStateOf(false) }
            Box {
                com.isaiahgraham.leanrrr.ui.components.LeanrRow("Log as", trailing = {
                    Text(row.food?.name ?: "Don't log this", style = LeanrType.body, color = c.accent, maxLines = 1)
                }, onClick = { open = true })
                DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                    row.matches.forEach { food ->
                        DropdownMenuItem(text = { Text(food.name) }, onClick = {
                            open = false
                            val changed = row.copy(chosen = food.id, note = null)
                            onChange(changed.copy(quantity = changed.servings(food)))
                        })
                    }
                    DropdownMenuItem(text = { Text("Don't log this") }, onClick = { open = false; onChange(row.copy(chosen = null, note = null)) })
                }
            }
            row.food?.let { food ->
                if (PortionSize.applies(food)) {
                    Segmented(PortionSize.entries.map { it to it.title }, row.size) { size ->
                        val changed = row.copy(size = size); onChange(changed.copy(quantity = changed.servings(food)))
                    }
                }
                key(row.chosen, row.size, row.quantity == row.servings(food)) {
                    NumberField("Servings", row.quantity, { onChange(row.copy(quantity = it)) })
                }
                Caption(detail(food, row.quantity, store.chainName(food.chain)))
            }
        }
        ActionRow("Search for it instead", icon = Icons.Filled.Search) { onSearch() }
    }
}

/** Where it's from, the serving, roughly how much that is by weight when the serving says, and the calories. */
internal fun detail(food: Food, quantity: Double, chainName: String): String {
    val parts = mutableListOf("$chainName · ${food.serve.ifEmpty { "1 serving" }} each")
    food.servingWeight?.let { weight -> if (quantity != 1.0) parts += "about ${(weight.first * quantity).roundedAway().number} ${weight.second}" }
    parts += "${Nutrition(listOf(Portion(food = food, quantity = quantity))).cal.roundedAway().number} Cal"
    return parts.joinToString(" · ")
}
