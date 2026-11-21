package com.isaiahgraham.leanrrr.feature.scan

import android.graphics.Bitmap
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Photo
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.data.nutrientNames
import com.isaiahgraham.leanrrr.ui.components.LabeledValue
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.components.OptionalNumberField
import kotlinx.coroutines.launch

/** Orange for "check this", as iOS uses `.orange` on the label scanner's warnings. */
private val Warning = Color(0xFFE08A00)

/** What reading a label gives: the figures for one serving (or per 100 when no serving size is printed) as a new Food. */
internal fun labelFood(text: String, column: Int, name: String, energyKJ: Double? = null, protein: Double? = null): Food? {
    val layout = LabelParser.layout(text)
    val values = LabelParser.servingSuggestions(text, column)
    val hundred = layout.per100Column == column
    // Per-100 figures with no serving size on the label: keep them per 100, and log by the weight eaten.
    val per100 = hundred && layout.amount == null
    val cal = values["cal"] ?: energyKJ?.let { it / 4.184 } ?: return null
    val p = values["p"] ?: protein ?: return null
    val others = values.filterKeys { it !in setOf("cal", "p", "c", "f") }
    return Food(
        name = name.trim().ifEmpty { "Food from a label" }, kj = cal * 4.184, cal = cal, p = p, c = values["c"], f = values["f"],
        serve = layout.servingDescription ?: if (per100) "100 ${layout.unit}" else "1 serving", nut = others.ifEmpty { null },
    )
}

/**
 * Read a nutrition label (the label part of MyFoodsView.swift's food editor, with LabelParser.swift): a photo of the panel,
 * text recognition on the phone, then the figures for the column chosen, per serving or per 100 g exactly as iOS reads them.
 * Hands the new Food to `onFood` for review; nothing is saved here.
 */
@Composable
fun LabelScan(onFood: (Food) -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var camera by remember { mutableStateOf(false) }
    var scanning by remember { mutableStateOf(false) }
    var scanError by remember { mutableStateOf<String?>(null) }
    var scannedText by remember { mutableStateOf("") }
    var preview by remember { mutableStateOf<Bitmap?>(null) }
    var column by remember { mutableIntStateOf(0) }
    var basisConfirmed by remember { mutableStateOf(true) }
    var showText by remember { mutableStateOf(false) }
    var name by remember { mutableStateOf("") }
    var energyKJ by remember { mutableStateOf<Double?>(null) }
    var protein by remember { mutableStateOf<Double?>(null) }

    fun fill() {
        val layout = LabelParser.layout(scannedText)
        val values = LabelParser.servingSuggestions(scannedText, column)
        basisConfirmed = layout.servingColumn == column || layout.per100Column == column
        scanError = if (values["cal"] == null) "Energy wasn't recognised. Check the column or enter the label's energy manually." else null
    }

    fun scan(bitmap: Bitmap) {
        preview = bitmap; scanning = true; scanError = null; scannedText = ""; column = 0
        scope.launch {
            try {
                val text = TextReader.labelText(bitmap)
                scanning = false
                scannedText = text
                val layout = LabelParser.layout(text)
                column = layout.servingColumn ?: layout.per100Column ?: 0
                fill()
                if (text.isEmpty()) scanError = "No text found. Try a sharper, better-lit photo."
            } catch (e: Exception) {
                scanning = false
                scanError = "Couldn’t read this image. Try a sharper, better-lit photo."
            }
        }
    }

    val picker = rememberPhotoPicker { uri ->
        scope.launch {
            val bitmap = loadPhoto(context, uri)
            if (bitmap == null) scanError = "Couldn’t read this image. Try another photo." else scan(bitmap)
        }
    }

    if (camera) {
        PhotoCamera("Fit the nutrition panel in the frame", square = false, onCancel = { camera = false },
            onPhotos = { photos -> camera = false; photos.firstOrNull()?.let(::scan) })
        return
    }

    BackHandler(onBack = onDismiss)
    LeanrScreen("Scan a label", onBack = onDismiss) {
        item {
            LeanrSection("Read a nutrition label") {
                ProminentButton("Take photo", enabled = !scanning, icon = Icons.Filled.CameraAlt) { camera = true }
                Caption("Fit the nutrition panel in the frame, then take the photo. Hold the phone flat and close enough to read the small print.")
                ActionRow("Choose existing photo", icon = Icons.Filled.Photo, enabled = !scanning) { picker.launch(imagesOnly) }
                Caption("When calories aren’t listed, Leanrrr converts kilojoules to calories automatically (kJ ÷ 4.184).")
                if (scanning) ProgressRow("Reading label…")
                scanError?.let { Caption(it, colour = Color(0xFFD70015)) }
                if (scannedText.isEmpty()) Caption("Reads text on your phone. No image upload or account is needed.")
            }
        }
        if (scannedText.isNotEmpty()) {
            val layout = LabelParser.layout(scannedText)
            val recognised = LabelParser.servingSuggestions(scannedText, column)
            val per100 = layout.per100Column == column && layout.amount == null
            item {
                LeanrSection {
                    preview?.let { bitmap ->
                        Image(bitmap.asImageBitmap(), "Your photo", contentScale = ContentScale.Fit,
                            modifier = Modifier.fillMaxWidth().heightIn(max = 180.dp).padding(12.dp).clip(RoundedCornerShape(12.dp)))
                    }
                    Caption("Check every number and whether the column is per serving or per 100 g before saving. Text recognition can misread labels.", colour = Warning)
                    ActionRow(if (showText) "Hide recognised text" else "Recognised text") { showText = !showText }
                    if (showText) Caption(scannedText)
                    Segmented(listOf(0 to "First", 1 to "Second"), column) { column = it; fill() }
                    if (!basisConfirmed) {
                        Caption("The column heading wasn't recognised. Check the selected column and whether it's per 100 before confirming.", colour = Warning)
                        ActionRow("I've checked the nutrition basis") { basisConfirmed = true }
                    }
                    // The same figures the button uses, so what's listed is what you get.
                    val basis = if (per100) "Per 100 ${layout.unit}" else "Per serving" + (layout.amount?.let { " (${it.number} ${layout.unit})" } ?: "")
                    Caption(basis)
                    androidx.compose.foundation.layout.Column(Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) {
                        nutrientNames.filter { recognised[it.key] != null }.forEach { n ->
                            LabeledValue(n.label, "${recognised[n.key]!!.number} ${n.unit}")
                        }
                    }
                    if (recognised.isEmpty()) Caption("No nutrition values found in this column. Try the other column or scan again closer to the label.")
                }
            }
            item {
                LeanrSection("Food", footer = "You'll review the numbers before anything is saved.") {
                    FieldRow(name, { name = it }, "Name, e.g. Greek yoghurt")
                    if (recognised["cal"] == null) OptionalNumberField("Energy (kJ)", energyKJ, { energyKJ = it }, placeholder = "From the label")
                    if (recognised["p"] == null) OptionalNumberField("Protein (g)", protein, { protein = it }, placeholder = "From the label", divider = false)
                    val food = labelFood(scannedText, column, name, energyKJ, protein)
                    ProminentButton("Fill recognised numbers for review", enabled = food != null && food.isValid && basisConfirmed && !scanning) {
                        food?.let(onFood)
                    }
                }
            }
        }
    }
}
