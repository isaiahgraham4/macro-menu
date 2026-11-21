package com.isaiahgraham.leanrrr.feature.scan

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.QuickLog
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.data.rememberBoolPref
import com.isaiahgraham.leanrrr.data.rememberStringPref
import com.isaiahgraham.leanrrr.data.tenth
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.components.NumberField
import com.isaiahgraham.leanrrr.ui.components.NutritionView
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.abs

/** What the scan screen can do in one tap, without opening the editor (BarcodeQuickActions.Mode). */
sealed interface BarcodeQuick {
    /** Logging, e.g. from Today: hands back the portion to log. */
    data class Log(val log: (Portion) -> Boolean) : BarcodeQuick
    /** Adding to My foods. */
    data object Save : BarcodeQuick
}

/** Remembered, so "Save to My foods" stays how you left it (same key as iOS). */
const val KEEP_IN_MY_FOODS_KEY = "barcode.saveToMyFoods"

/**
 * Scan a product barcode (BarcodeScanView.swift). The camera reads EAN-13, UPC-A, EAN-8 and ITF-14 on the phone; the code is
 * looked up in your own foods first, then Leanrrr's supermarket foods, then Open Food Facts (only the barcode is sent).
 * Choosing a product hands its Food to `onFound` for review; with `quick` it can be logged or saved straight from here.
 * `onManualEntry` gets the barcode that wasn't found (or null), so a food can be entered by hand and keep it.
 */
@Composable
fun BarcodeScan(
    onFound: (Food) -> Unit,
    onDismiss: () -> Unit,
    quick: BarcodeQuick? = null,
    actionTitle: String = "Log",
    dismissAfterUse: Boolean = true,
    onManualEntry: ((String?) -> Unit)? = null,
    initialCode: String? = null,
) {
    val store = AppServices.store
    val context = LocalContext.current
    val uri = LocalUriHandler.current
    val camera = rememberCameraAccess(askNow = true)
    var digits by remember { mutableStateOf("") }
    var pending by remember { mutableStateOf<String?>(null) }
    var product by remember { mutableStateOf<BarcodeProduct?>(null) }
    var saved by remember { mutableStateOf<Pair<String, Food>?>(null) }
    var missing by remember { mutableStateOf<String?>(null) }
    var message by remember { mutableStateOf<String?>(null) }
    var cameraMessage by remember { mutableStateOf<String?>(null) }
    var recentData by rememberStringPref(RecentBarcodes.STORAGE_KEY, "")
    BackHandler(onBack = onDismiss)

    fun reset() { product = null; saved = null; message = null; missing = null; pending = null; digits = "" }
    fun lookup(input: String) {
        if (pending != null) return
        try {
            val code = BarcodeLookup.validatedCode(input)
            digits = code; message = null; missing = null
            // Barcodes you've added to your own foods win over the online database; Leanrrr's supermarket foods are next.
            val mine = BarcodeLookup.match(code, store.data.foods)
            val known = if (mine == null) BarcodeLookup.matchAny(code, store.searchFoods.filter { it.chain != "mine" }) else null
            when {
                mine != null -> saved = code to mine
                known != null -> product = BarcodeProduct(known, per100 = false, unit = known.servingWeight?.second ?: "g",
                    sourceURL = known.productSource ?: "leanr://barcode/$code")
                else -> pending = code
            }
        } catch (e: BarcodeLookupException) { message = e.message }
    }

    LaunchedEffect(initialCode) { if (initialCode != null) lookup(initialCode) }

    LaunchedEffect(pending) {
        val code = pending ?: return@LaunchedEffect
        try {
            val found = withContext(Dispatchers.IO) { BarcodeLookup.fetch(code, checked = true) }
            if (pending != code) return@LaunchedEffect
            product = found; pending = null
            recentData = RecentBarcodes.recording(found, recentData)
        } catch (e: Exception) {
            if (pending != code) return@LaunchedEffect
            val lookupError = e as? BarcodeLookupException
            message = lookupError?.message ?: "Couldn't connect to the food database. Check your internet connection and try again."
            if (lookupError?.reason == BarcodeLookupException.Reason.NOT_FOUND || lookupError?.reason == BarcodeLookupException.Reason.INCOMPLETE) missing = code
            pending = null
        }
    }

    val analyzer = remember(camera.granted, pending, message, product, saved) {
        if (camera.granted && pending == null && message == null && product == null && saved == null) BarcodeAnalyzer { lookup(it) } else null
    }
    DisposableEffect(analyzer) { onDispose { analyzer?.stop() } }

    LeanrScreen("Scan barcode", onBack = onDismiss) {
        val savedFood = saved
        val found = product
        if (savedFood != null) {
            val (code, food) = savedFood
            item {
                LeanrSection("In My foods", footer = "You saved barcode $code with this food. Change it from the food's editor in My foods.") {
                    Body(food.name, headline = true)
                    Body("Nutrition per ${food.serve}", secondary = true)
                    if (quick != null) {
                        BarcodeQuickActions(food, per100 = food.serve.startsWith("100 "), inMyFoods = true, mode = quick, actionTitle = actionTitle,
                            nutrition = NutritionStyle.COMPACT) { onDismiss() }
                    } else NutritionView(Nutrition(listOf(Portion(food = food))), details = true)
                    if (quick == null || quick is BarcodeQuick.Log) {
                        BorderedButton(if (quick == null) "Use this food" else "Change details first") {
                            onFound(food); if (dismissAfterUse) onDismiss()
                        }
                    }
                    ActionRow("Scan another product") { reset() }
                }
            }
        } else if (found != null) {
            item {
                LeanrSection("Product found") {
                    Body(found.food.name, headline = true)
                    Body(if (found.per100) "Nutrition per 100 ${found.unit}" else "Nutrition per ${found.food.serve}", secondary = true)
                    if (quick != null) {
                        // Logging comes first, so it's reachable without scrolling; the full panel is a tap away.
                        BarcodeQuickActions(found.food, found.per100, inMyFoods = false, mode = quick, actionTitle = actionTitle, nutrition = NutritionStyle.SUMMARY) { onDismiss() }
                        BorderedButton("Edit details first") { onFound(found.food) }
                        Caption("Check this matches your package before logging.")
                    } else {
                        NutritionView(Nutrition(listOf(Portion(food = found.food))))
                        Caption("Check this matches your package. You'll choose your serving and review the numbers before saving.")
                        ProminentButton("Use nutrition & choose serving") { onFound(found.food); if (dismissAfterUse) onDismiss() }
                    }
                    when {
                        found.food.isCommunity -> Caption("Shared by a Leanrrr user. Leanrrr hasn't checked these figures.")
                        found.sourceURL.startsWith("https://world.openfoodfacts.org") && !found.food.isSupermarket ->
                            ActionRow("Source: Open Food Facts · ODbL") { uri.openUri(found.sourceURL) }
                        found.food.isSupermarket -> Caption("From Leanrrr's ${store.chainName(found.food.chain)} foods.")
                    }
                    ActionRow("Scan another product") { reset() }
                }
            }
        } else {
            item {
                LeanrSection {
                    when {
                        pending != null -> ProgressRow("Looking up product…")
                        analyzer != null -> {
                            CameraPreview(Modifier.fillMaxWidth().height(260.dp).padding(12.dp).clip(RoundedCornerShape(16.dp)), analyzer = analyzer) {
                                cameraMessage = it
                            }
                            Caption("Point at the product barcode. Keep it steady; the scan starts automatically. Pinch to zoom.")
                        }
                    }
                    cameraMessage?.let { Caption(it) }
                    if (!camera.granted && message == null && pending == null) {
                        if (camera.denied) {
                            Caption("Camera scanning is unavailable. You can enter the barcode below.")
                            ActionRow("Allow camera in Settings") { openAppSettings(context) }
                        } else ActionRow("Use the camera") { camera.request() }
                    }
                    message?.let { text ->
                        Body(text, secondary = true)
                        missing?.let { code ->
                            ProminentButton("Add barcode to a new food") { if (onManualEntry != null) onManualEntry(code) else onDismiss() }
                        }
                        ActionRow("Try scanning again") { reset() }
                    }
                }
            }
            item {
                RecentBarcodeSection(recentData, onRecord = { recentData = it }) { selected ->
                    pending = null; message = null
                    // A recent scan you've since saved opens from My foods.
                    val code = selected.food.barcode
                    val mine = code?.let { BarcodeLookup.match(it, store.data.foods) }
                    if (code != null && mine != null) saved = code to mine else product = selected
                }
            }
            item {
                LeanrSection("Or enter the barcode") {
                    FieldRow(digits, { digits = it }, "Barcode number", number = true)
                    SectionDivider()
                    ActionRow("Look up barcode", enabled = digits.isNotEmpty() && pending == null) { lookup(digits) }
                }
            }
            item {
                LeanrSection(footer = "Product data by Open Food Facts (ODbL). Internet required. Only the barcode is sent for lookup; camera images stay on your phone. Product coverage and nutrition completeness vary.") {
                    ActionRow("Use nutrition label or manual entry") { if (onManualEntry != null) onManualEntry(null) else onDismiss() }
                }
            }
        }
    }
}

/** Reads a barcode with the camera and hands back the digits, without looking the product up (BarcodeCaptureView). */
@Composable
fun BarcodeCaptureScreen(onCode: (String) -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val camera = rememberCameraAccess(askNow = true)
    var message by remember { mutableStateOf<String?>(null) }
    BackHandler(onBack = onDismiss)
    val analyzer = remember(camera.granted) { if (camera.granted) BarcodeAnalyzer { onCode(it); onDismiss() } else null }
    DisposableEffect(analyzer) { onDispose { analyzer?.stop() } }
    LeanrScreen("Add barcode", onBack = onDismiss) {
        item {
            LeanrSection {
                if (analyzer != null && message == null) {
                    CameraPreview(Modifier.fillMaxWidth().height(260.dp).padding(12.dp).clip(RoundedCornerShape(16.dp)), analyzer = analyzer) { message = it }
                    Caption("Point at the product barcode. It's added as soon as it's read.")
                }
                message?.let { Body(it, secondary = true) }
                if (camera.denied) {
                    Body("The camera is unavailable. Close this and type the barcode digits instead.", secondary = true)
                    ActionRow("Allow camera in Settings") { openAppSettings(context) }
                }
            }
        }
    }
}

enum class NutritionStyle {
    /** Calories and macros only. */
    COMPACT,
    /** Calories and macros, with the full panel a tap away. */
    SUMMARY,
    /** The whole panel. */
    FULL,
}

/** Logs or saves a scanned product in one tap: how much you had, whether to keep it in My foods, then Log (BarcodeQuickActions). */
@Composable
fun BarcodeQuickActions(
    food: Food,
    per100: Boolean,
    inMyFoods: Boolean,
    mode: BarcodeQuick,
    actionTitle: String = "Log",
    nutrition: NutritionStyle? = null,
    done: () -> Unit,
) {
    val store = AppServices.store
    val c = Leanr.colours
    var keep by rememberBoolPref(KEEP_IN_MY_FOODS_KEY, true)
    val serving = food.servingWeight
    // Per-100 figures are logged by weight, so the grams eaten can be typed straight in.
    var byWeight by remember(food.id) { mutableStateOf(per100 && serving != null) }
    var servings by remember(food.id) { mutableDoubleStateOf(1.0) }
    var weight by remember(food.id) { mutableDoubleStateOf(serving?.first ?: 100.0) }
    var failed by remember { mutableStateOf(false) }
    var fullOpen by remember { mutableStateOf(false) }
    var fieldKey by remember { mutableStateOf(0) }
    val quantity = if (byWeight && serving != null) weight / serving.first else servings
    val valid = quantity.isFinite() && quantity > 0 && quantity <= 10000
    val amountText = if (byWeight && serving != null) "${weight.number} ${serving.second}" else "${servings.number} ${if (servings == 1.0) "serving" else "servings"}"
    val total = Nutrition(listOf(Portion(food = food, quantity = if (valid) quantity else 0.0)))

    // A food you've logged before starts at the amount you had last time.
    LaunchedEffect(food.id) {
        if (mode is BarcodeQuick.Log && inMyFoods) {
            QuickLog.lastQuantity(food.id, store.data.logs)?.let { last ->
                if (byWeight && serving != null) weight = (last * serving.first).tenth else servings = last
                fieldKey += 1
            }
        }
    }

    Column {
        if (nutrition != null) {
            if (abs(quantity - 1) > 0.0001) Text("Total for $amountText", style = LeanrType.subheadline, color = c.secondaryText,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
            NutritionView(total, details = nutrition == NutritionStyle.FULL)
        }
        when (mode) {
            is BarcodeQuick.Log -> {
                if (serving != null) {
                    Segmented(listOf(false to "Servings", true to if (serving.second == "g") "Grams" else "mL"), byWeight) { byWeight = it; fieldKey += 1 }
                }
                androidx.compose.runtime.key(fieldKey, byWeight) {
                    if (byWeight && serving != null) NumberField("Amount (${serving.second})", weight, { weight = it })
                    else NumberField("Servings", servings, { servings = it })
                }
                if (!inMyFoods) {
                    Row(Modifier.fillMaxWidth().clickable { keep = !keep }.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text("Save to My foods", style = LeanrType.body, color = c.text)
                            Text("Log it again with one tap, and scanning it opens it straight away.", style = LeanrType.caption, color = c.secondaryText)
                        }
                        Spacer(Modifier.width(12.dp))
                        Switch(keep, { keep = it }, colors = SwitchDefaults.colors(checkedTrackColor = c.accent))
                    }
                }
                ProminentButton("$actionTitle · ${total.cal.roundedAway().number} Cal", enabled = valid) {
                    var item = food; var kept = false
                    if (keep && !inMyFoods) store.saveToMyFoods(food)?.let { item = it; kept = true }
                    if (!mode.log(Portion(food = item, quantity = quantity))) { failed = true; return@ProminentButton }
                    if (kept) store.notice = if (actionTitle.startsWith("Log")) "Logged and saved to My foods" else "Saved to My foods"
                    done()
                }
            }
            BarcodeQuick.Save -> {
                if (inMyFoods) {
                    Row(Modifier.padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.CheckCircle, null, tint = c.secondaryText, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text("Already in My foods", style = LeanrType.body, color = c.secondaryText)
                    }
                } else {
                    ProminentButton("Save to My foods") {
                        val kept = store.saveToMyFoods(food)
                        if (kept != null) { store.notice = "Saved ${kept.name} to My foods"; done() } else failed = true
                    }
                }
            }
        }
        if (nutrition == NutritionStyle.SUMMARY) {
            ActionRow(if (fullOpen) "Hide full nutrition" else "Full nutrition") { fullOpen = !fullOpen }
            if (fullOpen) NutritionView(total)
        }
    }
    if (failed) AlertDialog(onDismissRequest = { failed = false }, confirmButton = { TextButton({ failed = false }) { Text("OK") } },
        title = { Text("Couldn’t save food") },
        text = { Text("Your data was not changed. Check available storage and any data recovery message in the app.") })
}

/** The last ten scans in a dropdown, so they don't push the rest of the screen down. Ones you saved open from My foods. */
@Composable
private fun RecentBarcodeSection(recentData: String, onRecord: (String) -> Unit, use: (BarcodeProduct) -> Unit) {
    val products = RecentBarcodes.products(recentData)
    if (products.isEmpty()) return
    val c = Leanr.colours
    var open by remember { mutableStateOf(false) }
    LeanrSection(footer = "Reuse one of your last ${RecentBarcodes.LIMIT} scans. Ones you saved open from My foods.") {
        androidx.compose.foundation.layout.Box {
            Row(Modifier.fillMaxWidth().clickable { open = true }.padding(horizontal = 16.dp, vertical = 13.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.History, null, tint = c.accent, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(12.dp))
                Text("Recently scanned", style = LeanrType.body, color = c.accent, modifier = Modifier.weight(1f))
                Text("${products.size}", style = LeanrType.body, color = c.secondaryText)
                Icon(Icons.Filled.UnfoldMore, null, tint = c.secondaryText, modifier = Modifier.size(16.dp))
            }
            DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                products.forEach { product ->
                    DropdownMenuItem(
                        text = {
                            Column {
                                Text(product.food.name, style = LeanrType.body)
                                Text("${product.food.cal.number} Cals · ${product.food.serve}", style = LeanrType.caption, color = c.secondaryText)
                            }
                        },
                        onClick = { open = false; onRecord(RecentBarcodes.recording(product, recentData)); use(product) },
                    )
                }
            }
        }
    }
}
