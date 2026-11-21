package com.isaiahgraham.leanrrr.feature.progress

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Eco
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.Moment
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.data.rememberStringPref
import com.isaiahgraham.leanrrr.ui.theme.BebasNeue
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import com.isaiahgraham.leanrrr.ui.theme.Roboto
import kotlinx.coroutines.launch
import java.io.File
import java.time.LocalDate

// A port of MilestoneShare.swift (the 9:16 story card behind milestones and the year in review) and the image sharing it needs.

/** The designs a milestone card can take (ShareDesign.forMoments, less the see-through one). */
enum class StoryDesign(val raw: String, val title: String) {
    NIGHT("night", "Night"), PAPER("paper", "Paper"), COLOUR("colour", "Colour");

    data class Palette(val background: Color, val ink: Color, val dim: Color, val faint: Color, val brand: Color)

    fun palette(accent: Color): Palette = when (this) {
        NIGHT -> Palette(Color(0.07f, 0.07f, 0.08f), Color.White, Color.White.copy(alpha = 0.6f), Color.White.copy(alpha = 0.45f), accent)
        PAPER -> Color(0.11f, 0.12f, 0.11f).let { ink -> Palette(Color(0xFFF6F2EA), ink, ink.copy(alpha = 0.62f), ink.copy(alpha = 0.5f), accent) }
        COLOUR -> Palette(accent, Color.White, Color.White.copy(alpha = 0.78f), Color.White.copy(alpha = 0.62f), Color.White)
    }

    companion object {
        /** The same key the meal card uses, so a design chosen there carries over. */
        const val STORAGE_KEY = "shareDesign"
        fun fromRaw(raw: String) = entries.firstOrNull { it.raw == raw } ?: NIGHT
    }
}

/** What a story card says: an icon, a title, a big figure and a line about it. */
data class StoryCardContent(
    val icon: String,
    val title: String,
    val figure: Pair<String, String>?,
    val detail: String,
    val progress: Double?,
    val footnote: String,
)

/** The moment as a story card. */
fun Moment.storyCard(): StoryCardContent {
    val copy = copy
    return StoryCardContent(copy.icon, copy.title, copy.figure?.let { Pair(it.value.number, it.unit) },
        copy.detail.replace(" Tap for your review.", ""), copy.progress, longDate(LocalDate.now()))
}

/** The 9:16 story card. Drawn to the width it's given; type scales with it, as the iOS card is drawn at 360 × 640 and scaled. */
@Composable
fun StoryCard(card: StoryCardContent, design: StoryDesign, modifier: Modifier = Modifier) {
    val accent = Leanr.colours.accent
    val palette = design.palette(if (design == StoryDesign.COLOUR) com.isaiahgraham.leanrrr.ui.theme.AppAccent.resolvedColor(
        rememberStringPref(com.isaiahgraham.leanrrr.ui.theme.AppAccent.STORAGE_KEY, com.isaiahgraham.leanrrr.ui.theme.AppAccent.standard.raw).value, false) else accent)
    BoxWithConstraints(modifier.fillMaxWidth().aspectRatio(9f / 16f).background(palette.background)) {
        val s = maxWidth.value / 360f
        Column(Modifier.fillMaxSize().padding(horizontal = (32 * s).dp, vertical = (40 * s).dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Eco, null, tint = palette.brand, modifier = Modifier.size((14 * s).dp))
                Spacer(Modifier.width((4 * s).dp))
                Text("LEANRRR", style = TextStyle(fontFamily = Roboto, fontWeight = FontWeight.Bold, fontSize = (12 * s).sp), color = palette.brand)
            }
            Spacer(Modifier.weight(1f))
            Icon(symbolIcon(card.icon), null, tint = palette.brand, modifier = Modifier.size((48 * s).dp))
            Spacer(Modifier.height((22 * s).dp))
            Text(card.title, style = TextStyle(fontFamily = BebasNeue, fontSize = ((if (card.figure == null) 64 else 40) * s).sp,
                lineHeight = ((if (card.figure == null) 62 else 40) * s).sp), color = palette.ink, maxLines = 3)
            card.figure?.let { (value, unit) ->
                Row(verticalAlignment = Alignment.Bottom, modifier = Modifier.padding(top = (6 * s).dp)) {
                    Text(value, style = TextStyle(fontFamily = BebasNeue, fontSize = (96 * s).sp, lineHeight = (90 * s).sp), color = palette.ink, maxLines = 1)
                    Spacer(Modifier.width((8 * s).dp))
                    Text(unit, style = TextStyle(fontFamily = Roboto, fontSize = (22 * s).sp), color = palette.dim, modifier = Modifier.padding(bottom = (14 * s).dp))
                }
            }
            Text(card.detail, style = TextStyle(fontFamily = Roboto, fontSize = (20 * s).sp, lineHeight = (26 * s).sp), color = palette.ink.copy(alpha = 0.8f),
                modifier = Modifier.padding(top = (14 * s).dp))
            card.progress?.let { progress ->
                Box(Modifier.padding(top = (24 * s).dp).fillMaxWidth().height((8 * s).dp).clip(CircleShape).background(palette.ink.copy(alpha = 0.15f))) {
                    Box(Modifier.fillMaxWidth(progress.coerceIn(0.0, 1.0).toFloat()).height((8 * s).dp).clip(CircleShape).background(palette.brand))
                }
            }
            Spacer(Modifier.weight(1f))
            Text(card.footnote, style = TextStyle(fontFamily = Roboto, fontSize = (15 * s).sp), color = palette.dim)
            Text("Tracked with Leanrrr", style = TextStyle(fontFamily = Roboto, fontSize = (11 * s).sp), color = palette.faint, modifier = Modifier.padding(top = (6 * s).dp))
        }
        if (design == StoryDesign.PAPER) {
            // The order-pad dot grid behind the paper card.
            Canvas(Modifier.fillMaxSize()) {
                val step = 20 * s * density; var x = step / 2
                while (x < size.width) { var y = step / 2; while (y < size.height) { drawCircle(palette.ink.copy(alpha = 0.08f), 0.8f * density, Offset(x, y)); y += step }; x += step }
            }
        }
    }
}

/** Records what a composable draws, so it can be saved as an image ([captureBitmap]). */
fun Modifier.capturing(layer: GraphicsLayer): Modifier = drawWithContent {
    layer.record { this@drawWithContent.drawContent() }
    drawLayer(layer)
}

suspend fun GraphicsLayer.captureBitmap(): Bitmap = toImageBitmap().asAndroidBitmap()

/**
 * A preview of a card to share, so you see what you're posting, with the designs to choose from and a Share button
 * (StoryImagePreview / ShareCardActions on iOS).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ShareCardSheet(name: String, onDismiss: () -> Unit, designs: Boolean = true, card: @Composable (StoryDesign) -> Unit) {
    val context = LocalContext.current
    val c = Leanr.colours
    val scope = rememberCoroutineScope()
    val layer = rememberGraphicsLayer()
    var designRaw by rememberStringPref(StoryDesign.STORAGE_KEY, StoryDesign.NIGHT.raw)
    val design = StoryDesign.fromRaw(designRaw)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = c.paper) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 20.dp, vertical = 8.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(name, style = LeanrType.headline, color = c.text, textAlign = TextAlign.Center)
            Box(Modifier.widthIn(max = 280.dp).clip(RoundedCornerShape(18.dp)).capturing(layer)) { card(design) }
            if (designs) Segmented(StoryDesign.entries.map { it to it.title }, design, { designRaw = it.raw })
            Button(
                onClick = { scope.launch { shareBitmap(context, layer.captureBitmap(), name) } },
                colors = ButtonDefaults.buttonColors(containerColor = c.accent, contentColor = if (c.dark) Color.Black else Color.White),
                shape = RoundedCornerShape(14.dp), modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp),
            ) {
                Icon(Icons.Filled.Share, null); Spacer(Modifier.width(8.dp)); Text("Share as an image", style = LeanrType.headline)
            }
            Text("Post it to a story or send it to a friend.", style = LeanrType.caption, color = c.secondaryText, textAlign = TextAlign.Center)
        }
    }
}

/** A milestone's story card before sharing it (MomentSharePreview). */
@Composable
fun MomentShareSheet(moment: Moment, onDismiss: () -> Unit) {
    val card = moment.storyCard()
    ShareCardSheet(moment.copy.title, onDismiss) { design -> StoryCard(card, design) }
}

/**
 * Shares a picture through the system share sheet. Uses Progress's FileProvider (authority `<package>.progress.files`);
 * if that isn't declared yet, the picture goes to Pictures/Leanrrr and is shared from there.
 */
fun shareBitmap(context: Context, bitmap: Bitmap, name: String) {
    val safe = name.replace(Regex("[^A-Za-z0-9 ]"), "").trim().ifEmpty { "Leanrrr" }
    val uri: Uri? = runCatching {
        val dir = File(context.cacheDir, "progress_share").apply { mkdirs() }
        val file = File(dir, "$safe.png")
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        FileProvider.getUriForFile(context, "${context.packageName}.progress.files", file)
    }.getOrNull() ?: savedToPictures(context, bitmap, safe)
    if (uri == null) { AppServices.store.refuse("Couldn’t prepare the image to share."); return }
    val send = Intent(Intent.ACTION_SEND).setType("image/png").putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    context.startActivity(Intent.createChooser(send, name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}

private fun savedToPictures(context: Context, bitmap: Bitmap, name: String): Uri? {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
    return runCatching {
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, "$name.png")
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Leanrrr")
        }
        val uri = context.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: return null
        context.contentResolver.openOutputStream(uri)?.use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        uri
    }.getOrNull()
}

/** A file in the app's cache the camera can write a progress photo to, through Progress's FileProvider. Null if it isn't declared. */
fun cameraTarget(context: Context): Pair<File, Uri>? = runCatching {
    val dir = File(context.cacheDir, "progress_camera").apply { mkdirs() }
    val file = File(dir, "photo.jpg").apply { delete() }
    Pair(file, FileProvider.getUriForFile(context, "${context.packageName}.progress.files", file))
}.getOrNull()
