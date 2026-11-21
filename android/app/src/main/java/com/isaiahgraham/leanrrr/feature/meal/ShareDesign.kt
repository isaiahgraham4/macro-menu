package com.isaiahgraham.leanrrr.feature.meal

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.isaiahgraham.leanrrr.ui.theme.BebasNeue
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType

// A port of ShareDesign.swift: the looks a share image can take, their colours, and the picker under the preview.

/** The looks a share image can take. The last one picked is used next time. */
enum class ShareDesign(val raw: String, val title: String) {
    NIGHT("night", "Night"), CLEAR("clear", "Clear"), PAPER("paper", "Paper"), COLOUR("colour", "Colour"), DOCKET("docket", "Docket");

    /** No background at all: white type with a soft shadow, to lay over your own photo in a story. */
    val isTransparent: Boolean get() = this == CLEAR

    /** Whether the card is drawn in dark appearance, so the accent and macro colours pick their dark shades. */
    val drawsDark: Boolean get() = this == NIGHT || this == CLEAR

    /** The palette with the accent stored under `accentRaw`, in this design's appearance. */
    fun palette(accentRaw: String): SharePalette = palette(com.isaiahgraham.leanrrr.ui.theme.AppAccent.resolvedColor(accentRaw, drawsDark))

    /** What to say under the buttons when the usual hint doesn't fit the design. */
    val hint: String? get() = if (isTransparent) "It's see-through. Copy it, then paste it onto your own photo in a story." else null

    fun palette(accent: Color): SharePalette = when (this) {
        NIGHT -> SharePalette(Color(0.07f, 0.07f, 0.08f), Color.White, Color.White.copy(alpha = 0.6f), Color.White.copy(alpha = 0.45f), accent, dark = true)
        // Brighter secondary text than Night, since it sits on whatever photo it's pasted over.
        CLEAR -> SharePalette(null, Color.White, Color.White.copy(alpha = 0.85f), Color.White.copy(alpha = 0.75f), Color.White, dark = true, shadow = true)
        PAPER -> {
            val ink = Color(0.11f, 0.12f, 0.11f)
            SharePalette(Color(0xFFF6F2EA), ink, ink.copy(alpha = 0.62f), ink.copy(alpha = 0.5f), accent, dark = false, dots = true)
        }
        // The light-mode shade of the accent, which is dark enough for white text on it.
        COLOUR -> SharePalette(accent, Color.White, Color.White.copy(alpha = 0.78f), Color.White.copy(alpha = 0.62f), Color.White, dark = false, plainBars = true)
        DOCKET -> {
            val ink = Color(0.10f, 0.10f, 0.10f)
            SharePalette(Color(0.985f, 0.98f, 0.965f), ink, ink.copy(alpha = 0.6f), ink.copy(alpha = 0.45f), ink, dark = false)
        }
    }

    companion object {
        const val STORAGE_KEY = "shareDesign"
        /** A milestone card has no food list, so the receipt-style docket is for meals only. */
        val forMoments = listOf(NIGHT, CLEAR, PAPER, COLOUR)
        fun fromRaw(raw: String?): ShareDesign? = entries.firstOrNull { it.raw == raw }
    }
}

/** The colours one design draws with. */
data class SharePalette(
    /** Null for a see-through card. */
    val background: Color?,
    val ink: Color,
    val dim: Color,
    val faint: Color,
    /** The LEANRRR mark and other accents. */
    val brand: Color,
    /** The appearance the card is drawn in, so the accent and macro colours pick the matching shade. */
    val dark: Boolean,
    /** A soft shadow under the type, so it reads over a photo. */
    val shadow: Boolean = false,
    /** The app's order-pad dot grid behind the card. */
    val dots: Boolean = false,
    /** Macro bars in the ink colour: on a coloured card the macro colours would clash with it. */
    val plainBars: Boolean = false,
) {
    /** Card type: Roboto (or a given family) at a fixed size, never scaled by the sharer's text size, with the shadow when there is one. */
    fun text(size: Float, weight: FontWeight = FontWeight.Normal, colour: Color = ink, family: FontFamily = com.isaiahgraham.leanrrr.ui.theme.Roboto) = TextStyle(
        fontFamily = family, fontSize = size.sp, fontWeight = weight, color = colour,
        shadow = if (shadow) Shadow(Color.Black.copy(alpha = 0.55f), Offset(0f, 3f), 18f) else null,
    )
    fun display(size: Float, colour: Color = ink) = text(size, colour = colour, family = BebasNeue)
    fun mono(size: Float, weight: FontWeight = FontWeight.Normal, colour: Color = ink) = text(size, weight, colour, FontFamily.Monospace)
}

/** The order-pad dot grid from the app's background, for the Paper card. */
@Composable
fun OrderPadDots(ink: Color, modifier: Modifier = Modifier, step: Float = 20f) {
    Canvas(modifier.fillMaxSize()) {
        val s = step.dp.toPx(); val r = 0.8.dp.toPx()
        var x = s / 2
        while (x <= size.width) { var y = s / 2; while (y <= size.height) { drawCircle(ink, r, Offset(x, y)); y += s }; x += s }
    }
}

/** Grey squares behind a see-through card in the preview, so you can see it's clear. Not part of the image. */
@Composable
fun Checkerboard(modifier: Modifier = Modifier, square: Float = 12f) {
    Canvas(modifier.fillMaxSize()) {
        drawRect(Color(0.32f, 0.32f, 0.32f))
        val s = square.dp.toPx()
        var row = 0; var y = 0f
        while (y < size.height) {
            var col = 0; var x = 0f
            while (x < size.width) { if ((row + col) % 2 == 0) drawRect(Color(0.24f, 0.24f, 0.24f), Offset(x, y), Size(s, s)); x += s; col++ }
            y += s; row++
        }
    }
}

/** A dashed line across a docket, like the tear lines on a receipt. */
@Composable
fun DashedRule(colour: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.fillMaxWidth().height(1.dp)) {
        drawLine(colour, Offset(0f, size.height / 2), Offset(size.width, size.height / 2), strokeWidth = 1.dp.toPx(),
            pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 3.dp.toPx())))
    }
}

/** The row of designs under a share image's preview. */
@Composable
fun ShareDesignPicker(designs: List<ShareDesign>, selection: ShareDesign, onSelect: (ShareDesign) -> Unit, modifier: Modifier = Modifier) {
    val c = Leanr.colours
    val accentRaw = com.isaiahgraham.leanrrr.data.rememberStringPref(com.isaiahgraham.leanrrr.ui.theme.AppAccent.STORAGE_KEY,
        com.isaiahgraham.leanrrr.ui.theme.AppAccent.standard.raw).value
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        designs.forEach { design ->
            val selected = design == selection
            val palette = design.palette(accentRaw)
            Column(Modifier.weight(1f).clickable { onSelect(design) }.semantics { contentDescription = "${design.title} design"; this.selected = selected },
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Box(Modifier.size(40.dp, 56.dp).clip(RoundedCornerShape(8.dp))
                    .border(if (selected) 2.5.dp else 1.dp, if (selected) c.accent else c.text.copy(alpha = 0.15f), RoundedCornerShape(8.dp)),
                    contentAlignment = Alignment.Center) {
                    if (palette.background != null) Box(Modifier.fillMaxSize().background(palette.background)) else Checkerboard(square = 5f)
                    if (palette.dots) OrderPadDots(Color(0.40f, 0.31f, 0.20f).copy(alpha = 0.25f), step = 8f)
                    Text("Aa", style = if (design == ShareDesign.DOCKET) palette.mono(15f, FontWeight.Bold) else palette.display(20f).copy(shadow =
                        if (palette.shadow) Shadow(Color.Black.copy(alpha = 0.6f), Offset.Zero, 4f) else null))
                }
                Text(design.title, style = LeanrType.caption.copy(fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal),
                    color = if (selected) c.text else c.secondaryText)
            }
        }
    }
}
