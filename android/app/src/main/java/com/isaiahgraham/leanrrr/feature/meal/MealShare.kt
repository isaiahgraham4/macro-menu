package com.isaiahgraham.leanrrr.feature.meal

import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Eco
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.SubcomposeLayout
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.isaiahgraham.leanrrr.billing.Premium
import com.isaiahgraham.leanrrr.data.LogEntry
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.mealLines
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.data.rememberStringPref
import com.isaiahgraham.leanrrr.ui.theme.AppAccent
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import com.isaiahgraham.leanrrr.ui.theme.MacroColours
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToLong

// A port of MealShare.swift: a 9:16 story card for a meal, a meal time or a day, previewed before sharing, with Share,
// Save to Photos and Copy. The card is drawn by Compose at 360 × 640 dp with a density of 3, so the image is 1080 × 1920.

private val Double.rounded: Double get() = roundToLong().toDouble()

/** One meal time on a whole-day card: "Lunch" and what was logged to it. */
data class MealShareGroup(val title: String, val items: List<Portion>)

/** What a share-image screen should draw: one meal, one meal time, or a whole day split by meal. */
data class MealShareRequest(
    val name: String,
    val items: List<Portion>,
    val subtitle: String? = null,
    val groups: List<MealShareGroup> = emptyList(),
) {
    companion object {
        private val au = Locale.forLanguageTag("en-AU")

        /** A day's log as a card: every meal time with something in it, then anything not given one. */
        fun day(entries: List<LogEntry>, date: LocalDate): MealShareRequest {
            val groups = MealTime.entries.mapNotNull { time ->
                val items = entries.filter { it.mealTime == time }.flatMap { it.items }
                if (items.isEmpty()) null else MealShareGroup(time.title, items)
            }.toMutableList()
            val other = entries.filter { it.mealTime == null }.flatMap { it.items }
            if (other.isNotEmpty()) groups += MealShareGroup("Other", other)
            return MealShareRequest(date.format(DateTimeFormatter.ofPattern("EEEE", au)), entries.flatMap { it.items },
                date.format(DateTimeFormatter.ofPattern("d MMMM yyyy", au)), groups)
        }

        /** Everything logged to one meal time, such as the day's lunch. */
        fun meal(time: MealTime, entries: List<LogEntry>, date: LocalDate): MealShareRequest {
            val logged = entries.filter { it.mealTime == time }
            return MealShareRequest(if (logged.size == 1) logged[0].name else time.title, logged.flatMap { it.items },
                "${time.title} · ${date.format(DateTimeFormatter.ofPattern("d MMM", au))}")
        }
    }
}

/** A recipe's ingredients as rows: what it is, how much, and its calories and protein. */
@Composable
fun IngredientRows(ingredients: List<Portion>) {
    val c = Leanr.colours
    ingredients.forEachIndexed { i, item ->
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = Alignment.Bottom) {
                Text(item.food.name, style = LeanrType.body, color = c.text, modifier = Modifier.weight(1f))
                Spacer(Modifier.width(8.dp))
                Text(item.amountText, style = LeanrType.subheadline, color = c.secondaryText)
            }
            Text("${(item.food.cal * item.quantity).rounded.number} Cal · ${(item.food.p * item.quantity).number} g protein", style = LeanrType.caption, color = c.secondaryText)
        }
        if (i < ingredients.lastIndex) androidx.compose.material3.HorizontalDivider(Modifier.padding(start = 16.dp), color = c.separator, thickness = 0.5.dp)
    }
}

/** The card's size in dp; drawn with a density of 3 it's a story's own 1080 × 1920 pixels. */
const val CARD_WIDTH = 360
const val CARD_HEIGHT = 640
private const val CARD_SCALE = 3f

/**
 * A 9:16 card for an Instagram or TikTok story: the meal's name, calories and macros, and what's in it.
 * Draw it inside [StoryFrame] (or anywhere with room for 360 × 640 dp).
 */
@Composable
fun MealShareCard(name: String, items: List<Portion>, subtitle: String? = null, groups: List<MealShareGroup> = emptyList(), design: ShareDesign = ShareDesign.NIGHT) {
    val accentRaw by rememberStringPref(AppAccent.STORAGE_KEY, AppAccent.standard.raw)
    val proteinRaw by rememberStringPref(MacroColours.PROTEIN_KEY, "blue")
    val carbsRaw by rememberStringPref(MacroColours.CARBS_KEY, "orange")
    val fatRaw by rememberStringPref(MacroColours.FAT_KEY, "red")
    val palette = design.palette(accentRaw)
    val choices = if (Premium.isUnlocked) mapOf("p" to proteinRaw, "c" to carbsRaw, "f" to fatRaw) else emptyMap()
    val colour = { key: String -> MacroColours.colour(key, choices, palette.dark) }
    ShareSurface(palette) {
        // The card is a fixed 9:16, so it tries fewer ingredient rows until the name, macros and rows all fit above the footer.
        if (design == ShareDesign.DOCKET) {
            FitRows(listOf(10, 8, 6, 5, 4, 3, 2, 1)) { rows, fill -> Docket(name, items, subtitle, groups, palette, rows, fill) }
        } else {
            FitRows(listOf(9, 7, 6, 5, 4, 3, 2, 1)) { rows, fill -> CardBody(name, items, subtitle, groups, palette, colour, rows, fill) }
        }
    }
}

/** Fits a card to the 9:16 story size and paints its design around it. */
@Composable
fun ShareSurface(palette: SharePalette, content: @Composable () -> Unit) {
    Box(Modifier.size(CARD_WIDTH.dp, CARD_HEIGHT.dp)) {
        palette.background?.let { Box(Modifier.fillMaxSize().background(it)) }
        if (palette.dots) OrderPadDots(Color(0.40f, 0.31f, 0.20f).copy(alpha = 0.16f))
        Box(Modifier.fillMaxSize().padding(horizontal = 28.dp, vertical = 36.dp)) { content() }
    }
}

/** SwiftUI's ViewThatFits: the first row count whose content fits the height, then drawn filling it. */
@Composable
private fun FitRows(candidates: List<Int>, content: @Composable (rows: Int, fill: Boolean) -> Unit) {
    SubcomposeLayout(Modifier.fillMaxSize()) { constraints ->
        val maxH = constraints.maxHeight
        val loose = Constraints(maxWidth = constraints.maxWidth, maxHeight = Constraints.Infinity)
        var chosen = candidates.last()
        for (rows in candidates) {
            val height = subcompose("try-$rows") { content(rows, false) }.maxOfOrNull { it.measure(loose).height } ?: 0
            if (height <= maxH) { chosen = rows; break }
        }
        val placeables = subcompose("final") { content(chosen, true) }.map { it.measure(Constraints.fixed(constraints.maxWidth, maxH)) }
        layout(constraints.maxWidth, maxH) { placeables.forEach { it.place(0, 0) } }
    }
}

@Composable
private fun ColumnScope.Gap(fill: Boolean, min: Int) {
    Spacer(Modifier.height(min.dp))
    if (fill) Spacer(Modifier.weight(1f))
}

/** The card's contents, listing up to `rows` ingredient lines (the last of them "and N more" when there are too many). */
@Composable
private fun CardBody(name: String, items: List<Portion>, subtitle: String?, groups: List<MealShareGroup>, palette: SharePalette,
                     colour: (String) -> Color, rows: Int, fill: Boolean) {
    val total = Nutrition(items)
    val lines = mealLines(items)
    val isRecipe = items.any { it.ingredientPortions != null }
    Column(if (fill) Modifier.fillMaxSize() else Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            Icon(Icons.Filled.Eco, null, tint = palette.brand, modifier = Modifier.size(14.dp))
            Text("LEANRRR", style = palette.text(12f, FontWeight.Bold, palette.brand))
        }
        BasicText(name, style = palette.display(54f), maxLines = 3, overflow = TextOverflow.Ellipsis,
            autoSize = TextAutoSize.StepBased(27.sp, 54.sp, 1.sp), modifier = Modifier.padding(top = 18.dp))
        if (subtitle != null) Text(subtitle, style = palette.text(15f, colour = palette.dim))
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.padding(top = 20.dp)) {
            Text(total.cal.rounded.number, style = palette.display(72f).copy(lineHeight = 72.sp))
            Text("Cal", style = palette.text(20f, colour = palette.dim), modifier = Modifier.padding(bottom = 12.dp))
        }
        Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            CardMacro("Protein", total.p, false, if (palette.plainBars) palette.ink else colour("p"), palette, Modifier.weight(1f))
            CardMacro("Carbs", total.c, total.missingCarbs, if (palette.plainBars) palette.ink else colour("c"), palette, Modifier.weight(1f))
            CardMacro("Fat", total.f, total.missingFat, if (palette.plainBars) palette.ink else colour("f"), palette, Modifier.weight(1f))
        }
        if (groups.isNotEmpty()) {
            Text("BY MEAL", style = palette.text(12f, FontWeight.Bold, palette.dim), modifier = Modifier.padding(top = 26.dp, bottom = 8.dp))
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                groups.forEach { group ->
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Row(verticalAlignment = Alignment.Bottom) {
                            Text(group.title, style = palette.text(15f, FontWeight.SemiBold), modifier = Modifier.weight(1f))
                            Text("${Nutrition(group.items).cal.rounded.number} Cal", style = palette.text(15f, colour = palette.dim))
                        }
                        // Fewer rows to fit means fewer food names under each meal, down to just the totals.
                        if (rows > 2) Text(mealLines(group.items).joinToString(", ") { it.food.name }, style = palette.text(12f, colour = palette.dim),
                            maxLines = if (rows > 5) 2 else 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        } else if (lines.isNotEmpty()) {
            Text(if (isRecipe) "INGREDIENTS" else "IN THIS MEAL", style = palette.text(12f, FontWeight.Bold, palette.dim),
                modifier = Modifier.padding(top = 26.dp, bottom = 8.dp))
            val shown = if (lines.size > rows) maxOf(rows - 1, 0) else rows
            Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                lines.take(shown).forEach { line ->
                    Row(verticalAlignment = Alignment.Bottom) {
                        Text(line.food.name, style = palette.text(15f), maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                        Spacer(Modifier.width(8.dp))
                        Text(line.amountText, style = palette.text(15f, colour = palette.dim), maxLines = 1)
                    }
                }
                if (lines.size > shown) Text("and ${lines.size - shown} more", style = palette.text(15f, colour = palette.dim))
            }
        }
        Gap(fill, 12)
        Text("Tracked with Leanrrr · Nutrition may vary", style = palette.text(11f, colour = palette.faint))
    }
}

@Composable
private fun CardMacro(label: String, value: Double, missing: Boolean, bar: Color, palette: SharePalette, modifier: Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(Modifier.fillMaxWidth().height(4.dp).clip(CircleShape).background(bar))
        Text("${value.rounded.number}${if (missing) "+" else ""} g", style = palette.text(20f, FontWeight.SemiBold))
        Text(label, style = palette.text(12f, colour = palette.dim))
    }
}

/** The meal as a takeaway receipt: each line with its calories, then the total and macros. Up to `rows` lines. */
@Composable
private fun Docket(name: String, items: List<Portion>, subtitle: String?, groups: List<MealShareGroup>, palette: SharePalette, rows: Int, fill: Boolean) {
    val total = Nutrition(items)
    val lines = mealLines(items)
    Column(if (fill) Modifier.fillMaxSize() else Modifier.fillMaxWidth()) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("LEANRRR", style = palette.mono(15f, FontWeight.Bold).copy(letterSpacing = 4.sp))
            Text(subtitle ?: LocalDate.now().abbreviated(), style = palette.mono(12f, colour = palette.dim))
        }
        DashedRule(palette.faint, Modifier.padding(vertical = 14.dp))
        BasicText(name.uppercase(), style = palette.mono(22f, FontWeight.Bold), maxLines = 2, overflow = TextOverflow.Ellipsis,
            autoSize = TextAutoSize.StepBased(13.sp, 22.sp, 1.sp))
        DashedRule(palette.faint, Modifier.padding(vertical = 14.dp))
        Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
            if (groups.isNotEmpty()) {
                groups.forEach { group ->
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        DocketLine(group.title.uppercase(), Nutrition(group.items).cal.rounded.number, palette, bold = true)
                        if (rows > 3) Text(mealLines(group.items).joinToString(", ") { it.food.name }, style = palette.mono(11f, colour = palette.dim),
                            maxLines = if (rows > 6) 2 else 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            } else {
                val shown = if (lines.size > rows) maxOf(rows - 1, 0) else rows
                lines.take(shown).forEach { line ->
                    Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                        DocketLine(line.food.name, (line.food.cal * line.quantity).rounded.number, palette)
                        if (rows > 4) Text(line.amountText, style = palette.mono(11f, colour = palette.dim), maxLines = 1)
                    }
                }
                if (lines.size > shown) Text("+ ${lines.size - shown} more", style = palette.mono(13f, colour = palette.dim))
            }
        }
        DashedRule(palette.faint, Modifier.padding(vertical = 14.dp))
        Row(verticalAlignment = Alignment.Bottom) {
            Text("TOTAL", style = palette.mono(20f, FontWeight.Bold), modifier = Modifier.weight(1f))
            Text("${total.cal.rounded.number} Cal", style = palette.mono(20f, FontWeight.Bold))
        }
        Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            DocketLine("Protein", "${total.p.rounded.number} g", palette)
            DocketLine("Carbs", "${total.c.rounded.number}${if (total.missingCarbs) "+" else ""} g", palette)
            DocketLine("Fat", "${total.f.rounded.number}${if (total.missingFat) "+" else ""} g", palette)
        }
        Gap(fill, 12)
        DashedRule(palette.faint, Modifier.padding(bottom = 10.dp))
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text("THANK YOU · TRACKED WITH LEANRRR", style = palette.mono(10f, FontWeight.SemiBold))
            Text("Nutrition may vary", style = palette.mono(10f, colour = palette.faint))
        }
    }
}

/** "Big Mac ........ 563" style: the name on the left, the figure on the right. */
@Composable
private fun DocketLine(label: String, value: String, palette: SharePalette, bold: Boolean = false) {
    Row(verticalAlignment = Alignment.Bottom) {
        Text(label, style = palette.mono(13f, if (bold) FontWeight.Bold else FontWeight.Normal), maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        Spacer(Modifier.width(8.dp))
        Text(value, style = palette.mono(13f, if (bold) FontWeight.Bold else FontWeight.Normal), maxLines = 1)
    }
}

/**
 * Your photo filling a story with the card on it: the Clear card's words straight across the photo, any other design as a
 * small card in the bottom corner so the food stays in view.
 */
@Composable
fun PhotoStory(photo: ImageBitmap, design: ShareDesign, card: @Composable () -> Unit) {
    Box(Modifier.size(CARD_WIDTH.dp, CARD_HEIGHT.dp)) {
        Image(photo, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        if (design.isTransparent) {
            // A flat dim, so white words read over a bright plate.
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.3f)))
            card()
        } else {
            Box(Modifier.align(Alignment.BottomStart).padding(18.dp).size((CARD_WIDTH / 2).dp, (CARD_HEIGHT / 2).dp)
                .shadow(10.dp, RoundedCornerShape(12.dp)).clip(RoundedCornerShape(12.dp))) {
                Box(Modifier.layout { m, _ ->
                    val p = m.measure(Constraints.fixed(CARD_WIDTH.dp.roundToPx(), CARD_HEIGHT.dp.roundToPx()))
                    layout(p.width / 2, p.height / 2) { p.placeWithLayer(0, 0) { scaleX = 0.5f; scaleY = 0.5f; transformOrigin = TransformOrigin(0f, 0f) } }
                }) { card() }
            }
        }
    }
}

/**
 * Shows a story card before sharing it, so you see what you're posting, with ways to share, save or copy it, a choice of
 * designs when the card has them, and an optional photo of the food to put it on. `card` draws the card in a design.
 */
@Composable
fun StoryImagePreview(name: String, onDismiss: () -> Unit, designs: List<ShareDesign> = ShareDesign.entries, card: @Composable (ShareDesign) -> Unit) {
    val c = Leanr.colours
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var designRaw by rememberStringPref(ShareDesign.STORAGE_KEY, ShareDesign.NIGHT.raw)
    var photo by remember { mutableStateOf<ImageBitmap?>(null) }
    var photoProblem by remember { mutableStateOf(false) }
    val design = designs.firstOrNull()?.let { first -> ShareDesign.fromRaw(designRaw)?.takeIf { it in designs } ?: first } ?: ShareDesign.NIGHT
    val transparent = design.isTransparent && photo == null
    val layer = rememberGraphicsLayer()
    BackHandler(onBack = onDismiss)

    val pick = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch { photo = ShareImages.loadPhoto(context, uri)?.asImageBitmap(); if (photo == null) photoProblem = true }
    }
    var cameraFile by remember { mutableStateOf<Pair<File, Uri>?>(null) }
    val take = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        val target = cameraFile
        if (ok && target != null) scope.launch { photo = ShareImages.loadPhoto(context, target.second)?.asImageBitmap(); if (photo == null) photoProblem = true }
    }
    val launchCamera = {
        ShareImages.cameraTarget(context)?.let { cameraFile = it; take.launch(it.second) }
    }
    val cameraPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted -> if (granted) launchCamera() }
    val canTakePhoto = remember { ShareImages.cameraTarget(context) != null && context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY) }

    Column(Modifier.fillMaxSize().background(c.paper).statusBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onDismiss) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = c.accent) }
            Text("Share image", style = LeanrType.headline, color = c.text, modifier = Modifier.weight(1f))
            TextButton(onClick = onDismiss) { Text("Done", color = c.accent) }
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp)) {
            BoxWithConstraints(Modifier.widthIn(max = 280.dp).fillMaxWidth().aspectRatio(9f / 16f).clip(RoundedCornerShape(18.dp))
                .semantics { contentDescription = "Share image: $name, ${design.title} design${if (photo == null) "" else ", on your photo"}" }) {
                val scale = constraints.maxWidth / (CARD_WIDTH * CARD_SCALE)
                if (transparent) Checkerboard()
                Box(Modifier
                    .layout { m, cs ->
                        val p = m.measure(Constraints.fixed((CARD_WIDTH * CARD_SCALE).toInt(), (CARD_HEIGHT * CARD_SCALE).toInt()))
                        layout(cs.maxWidth, cs.maxHeight) { p.placeWithLayer(0, 0) { scaleX = scale; scaleY = scale; transformOrigin = TransformOrigin(0f, 0f) } }
                    }
                    .drawWithContent { layer.record { this@drawWithContent.drawContent() }; drawLayer(layer) }) {
                    StoryFrame {
                        val current = photo
                        if (current != null) PhotoStory(current, design) { card(design) } else card(design)
                    }
                }
            }
            if (designs.isNotEmpty()) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    if (canTakePhoto) SmallButton(if (photo == null) "Take photo" else "Retake", Icons.Filled.CameraAlt) {
                        if (ShareImages.needsCameraPermission(context)) cameraPermission.launch(Manifest.permission.CAMERA) else launchCamera()
                    }
                    SmallButton(if (photo == null) "Choose photo" else "Change", Icons.Filled.PhotoLibrary) {
                        pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                    }
                    if (photo != null) SmallButton("No photo", Icons.Filled.Close) { photo = null }
                }
            }
            if (designs.size > 1) ShareDesignPicker(designs, design, { designRaw = it.raw })
            val hint = when {
                photo != null -> "Your photo with the card on it. Share it to a story or save it."
                else -> design.hint ?: ShareHints.STANDARD
            }
            ShareCardActions(layer = layer, hint = hint, transparent = transparent)
            if (photoProblem) Text("That photo couldn't be opened.", style = LeanrType.caption, color = warningColour)
        }
    }
}

@Composable
private fun SmallButton(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, onClick: () -> Unit) {
    val c = Leanr.colours
    OutlinedButton(onClick = onClick, contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 12.dp, vertical = 6.dp)) {
        Icon(icon, null, tint = c.accent, modifier = Modifier.size(16.dp)); Spacer(Modifier.width(6.dp))
        Text(title, style = LeanrType.subheadline, color = c.accent)
    }
}

/** Draws its content as a 360 × 640 dp story at a density of 3, whatever the screen, so the picture is always 1080 × 1920. */
@Composable
fun StoryFrame(content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalDensity provides Density(CARD_SCALE, 1f)) {
        Box(Modifier.size(CARD_WIDTH.dp, CARD_HEIGHT.dp)) { content() }
    }
}

/** Share, Save to Photos and Copy for a rendered story card, each handing over the full 1080 × 1920 picture. */
@Composable
fun ShareCardActions(layer: GraphicsLayer, hint: String = ShareHints.STANDARD, transparent: Boolean = false, shareTitle: String = "Share image") {
    val c = Leanr.colours
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var status by remember { mutableStateOf<String?>(null) }
    var failed by remember { mutableStateOf(false) }
    val onAccent = if (c.dark) Color.Black else Color.White
    // A software copy of the 1080 × 1920 picture (the layer may hand back a hardware bitmap); opaque unless it's the Clear card on its own.
    suspend fun bitmap(): Bitmap = layer.toImageBitmap().asAndroidBitmap().copy(Bitmap.Config.ARGB_8888, true).also { if (!transparent) it.setHasAlpha(false) }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Button(onClick = { scope.launch { ShareImages.share(context, bitmap()) } }, modifier = Modifier.fillMaxWidth().height(50.dp),
            colors = ButtonDefaults.buttonColors(containerColor = c.accent, contentColor = onAccent), shape = RoundedCornerShape(14.dp)) {
            Icon(Icons.Filled.Share, null); Spacer(Modifier.width(8.dp)); Text(shareTitle, style = LeanrType.headline)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            OutlinedButton(onClick = {
                scope.launch {
                    val ok = ShareImages.saveToPhotos(context, bitmap())
                    failed = !ok
                    status = if (ok) "Saved to Photos." else "Couldn't save. Let Leanrrr add photos in Settings."
                }
            }, modifier = Modifier.weight(1f).height(48.dp), shape = RoundedCornerShape(14.dp)) {
                Icon(Icons.Filled.Download, null, tint = c.accent); Spacer(Modifier.width(6.dp)); Text("Save to Photos", color = c.accent, maxLines = 1)
            }
            OutlinedButton(onClick = {
                scope.launch {
                    val ok = ShareImages.copy(context, bitmap())
                    failed = !ok
                    status = if (ok) "Copied. Paste it into a story or chat." else "Couldn't copy this picture."
                }
            }, modifier = Modifier.weight(1f).height(48.dp), shape = RoundedCornerShape(14.dp)) {
                Icon(Icons.Filled.ContentCopy, null, tint = c.accent); Spacer(Modifier.width(6.dp)); Text("Copy", color = c.accent)
            }
        }
        Text(status ?: hint, style = LeanrType.caption, color = if (failed) warningColour else c.secondaryText, textAlign = TextAlign.Center)
    }
}

object ShareHints {
    const val STANDARD = "Post it to an Instagram or TikTok story, or paste it into a chat."
}

/** A meal's story card, previewed before sharing. */
@Composable
fun MealSharePreview(name: String, items: List<Portion>, onDismiss: () -> Unit, subtitle: String? = null, groups: List<MealShareGroup> = emptyList()) {
    StoryImagePreview(name, onDismiss) { design -> MealShareCard(name, items, subtitle, groups, design) }
}

@Composable
fun MealSharePreview(request: MealShareRequest, onDismiss: () -> Unit) =
    MealSharePreview(request.name, request.items, onDismiss, request.subtitle, request.groups)

/**
 * Handing pictures to other apps. Images are written to `cache/meal_share/` and offered through a FileProvider with the
 * authority "<applicationId>.mealshare" (see res/xml/meal_share_paths.xml; the provider must be declared in the manifest).
 * Without it, sharing falls back to a copy in Pictures/Leanrrr.
 */
object ShareImages {
    fun authority(context: Context) = "${context.packageName}.mealshare"

    private fun cacheFile(context: Context, name: String): File = File(context.cacheDir, "meal_share").apply { mkdirs() }.let { File(it, name) }

    private suspend fun providerUri(context: Context, bitmap: Bitmap): Uri? = withContext(Dispatchers.IO) {
        val file = cacheFile(context, "Leanrrr.png")
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        try { FileProvider.getUriForFile(context, authority(context), file) } catch (e: IllegalArgumentException) { null }
    }

    private suspend fun shareableUri(context: Context, bitmap: Bitmap): Uri? = providerUri(context, bitmap) ?: insertIntoPictures(context, bitmap)

    suspend fun share(context: Context, bitmap: Bitmap) {
        val uri = shareableUri(context, bitmap) ?: return
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "image/png"
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = ClipData.newRawUri("Leanrrr", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    suspend fun copy(context: Context, bitmap: Bitmap): Boolean {
        val uri = shareableUri(context, bitmap) ?: return false
        val clipboard = context.getSystemService(ClipboardManager::class.java) ?: return false
        clipboard.setPrimaryClip(ClipData.newUri(context.contentResolver, "Leanrrr", uri))
        return true
    }

    suspend fun saveToPhotos(context: Context, bitmap: Bitmap): Boolean = insertIntoPictures(context, bitmap) != null

    /** Adds the PNG to Pictures/Leanrrr. Needs no permission from Android 10; on Android 9 it needs storage access. */
    private suspend fun insertIntoPictures(context: Context, bitmap: Bitmap): Uri? = withContext(Dispatchers.IO) {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, "Leanrrr-${System.currentTimeMillis()}.png")
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Leanrrr")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
        }
        try {
            val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: return@withContext null
            resolver.openOutputStream(uri)?.use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                resolver.update(uri, ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }, null, null)
            }
            uri
        } catch (e: Exception) { null }
    }

    /** Where the camera should save a photo of the food, when the FileProvider is there. Never kept by the app. */
    fun cameraTarget(context: Context): Pair<File, Uri>? {
        val file = cacheFile(context, "photo.jpg")
        return try { file to FileProvider.getUriForFile(context, authority(context), file) } catch (e: IllegalArgumentException) { null }
    }

    /** The camera app can be used without permission unless this app declares CAMERA, in which case it must be granted first. */
    fun needsCameraPermission(context: Context): Boolean {
        val declared = try {
            context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS).requestedPermissions?.contains(Manifest.permission.CAMERA) == true
        } catch (e: Exception) { false }
        return declared && ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED
    }

    /** Opens a picked or taken photo upright, no larger than the story needs. */
    suspend fun loadPhoto(context: Context, uri: Uri): Bitmap? = withContext(Dispatchers.IO) {
        try {
            ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri)) { decoder, info, _ ->
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                val longest = maxOf(info.size.width, info.size.height)
                if (longest > 2400) {
                    val ratio = 2400f / longest
                    decoder.setTargetSize((info.size.width * ratio).toInt(), (info.size.height * ratio).toInt())
                }
            }
        } catch (e: Exception) { null }
    }
}
