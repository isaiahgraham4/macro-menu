package com.isaiahgraham.leanrrr.ui.theme

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.isaiahgraham.leanrrr.R
import com.isaiahgraham.leanrrr.billing.Premium
import com.isaiahgraham.leanrrr.data.rememberStringPref

// Fonts (AppFonts.swift): Bebas Neue for big titles, Roboto for everything else.
val BebasNeue = FontFamily(Font(R.font.bebas_neue))
val Roboto = FontFamily(
    Font(R.font.roboto_thin, FontWeight.Thin),
    Font(R.font.roboto_light, FontWeight.Light),
    Font(R.font.roboto_regular, FontWeight.Normal),
    Font(R.font.roboto_medium, FontWeight.Medium),
    Font(R.font.roboto_medium, FontWeight.SemiBold),
    Font(R.font.roboto_bold, FontWeight.Bold),
    Font(R.font.roboto_black, FontWeight.Black),
)

/** Bebas Neue is condensed, so titles are drawn this much larger than the system sizes. */
const val DISPLAY_SCALE = 1.35f

/** Text styles named after the iOS ones the app uses, at their default Dynamic Type sizes (sp scale with the user's font size). */
object LeanrType {
    fun roboto(size: Float, weight: FontWeight = FontWeight.Normal) = TextStyle(fontFamily = Roboto, fontSize = size.sp, fontWeight = weight)
    fun display(size: Float) = TextStyle(fontFamily = BebasNeue, fontSize = (size * DISPLAY_SCALE).sp, fontWeight = FontWeight.Normal)

    val largeTitle = display(34f)
    val title = display(28f)
    val title2Display = display(22f)
    val statHero = roboto(34f, FontWeight.Bold)
    val stat = roboto(22f, FontWeight.Bold)
    val title3 = roboto(20f, FontWeight.Medium)
    val headline = roboto(17f, FontWeight.Medium)
    val body = roboto(17f)
    val callout = roboto(16f)
    val subheadline = roboto(15f)
    val footnote = roboto(13f)
    val caption = roboto(12f)
    val label = roboto(12f, FontWeight.Medium)
    val caption2 = roboto(11f)
    val tabLabel = roboto(10f, FontWeight.Medium)
}

/** The colours every screen draws with: the chosen accent, the macro colours and the paper, resolved for light or dark. */
@Immutable
data class LeanrColours(
    val dark: Boolean,
    val accent: Color,
    val protein: Color,
    val carbs: Color,
    val fat: Color,
    val paper: Color,
    /** Grouped cards and list rows on top of the paper (iOS secondarySystemGroupedBackground). */
    val card: Color,
    val text: Color,
    val secondaryText: Color,
    val tertiaryText: Color,
    val separator: Color,
    val ink: Color,
) {
    /** Colour for a nutrient: macros use their own colours, everything else the app colour. */
    fun nutrient(key: String): Color = when (key) { "p" -> protein; "c" -> carbs; "f" -> fat; else -> accent }
    val reached: Color get() = TargetStatus.REACHED.colour(dark)!!
    val over: Color get() = TargetStatus.OVER.colour(dark)!!
}

val LocalLeanr = compositionLocalOf<LeanrColours> { error("LeanrTheme missing") }

/** Shortcut for the current colours: `Leanr.colours.accent`. */
object Leanr {
    val colours: LeanrColours @Composable get() = LocalLeanr.current
}

@Composable
fun LeanrTheme(content: @Composable () -> Unit) {
    val appearance by rememberStringPref(AppAppearance.STORAGE_KEY, AppAppearance.SYSTEM.raw)
    val accentRaw by rememberStringPref(AppAccent.STORAGE_KEY, AppAccent.standard.raw)
    val proteinRaw by rememberStringPref(MacroColours.PROTEIN_KEY, "blue")
    val carbsRaw by rememberStringPref(MacroColours.CARBS_KEY, "orange")
    val fatRaw by rememberStringPref(MacroColours.FAT_KEY, "red")
    val paperRaw by rememberStringPref(PaperTint.STORAGE_KEY, PaperTint.CREAM.raw)
    val unlocked = Premium.isUnlocked
    val dark = when (AppAppearance.fromRaw(appearance)) {
        AppAppearance.SYSTEM -> isSystemInDarkTheme()
        AppAppearance.LIGHT -> false
        AppAppearance.DARK -> true
    }
    val choices = if (unlocked) mapOf("p" to proteinRaw, "c" to carbsRaw, "f" to fatRaw) else emptyMap()
    val colours = LeanrColours(
        dark = dark,
        accent = AppAccent.resolvedColor(accentRaw, dark),
        protein = MacroColours.colour("p", choices, dark),
        carbs = MacroColours.colour("c", choices, dark),
        fat = MacroColours.colour("f", choices, dark),
        paper = PaperTint.resolved(paperRaw).color(dark),
        card = if (dark) Color(0xFF1C1C1E) else Color.White,
        text = if (dark) Color.White else Color.Black,
        secondaryText = if (dark) Color(0x99EBEBF5) else Color(0x993C3C43),
        tertiaryText = if (dark) Color(0x4DEBEBF5) else Color(0x4D3C3C43),
        separator = if (dark) Color(0x5C545458) else Color(0x4A3C3C43),
        ink = if (dark) Color.White else Color(0xFF664F33),
    )
    val scheme: ColorScheme = if (dark) darkColorScheme(
        primary = colours.accent, onPrimary = Color.Black, secondary = colours.accent, background = colours.paper, surface = colours.paper,
        surfaceContainer = colours.card, surfaceContainerLow = colours.card, surfaceContainerHigh = Color(0xFF2C2C2E),
        surfaceContainerHighest = Color(0xFF3A3A3C), onBackground = colours.text, onSurface = colours.text,
        onSurfaceVariant = colours.secondaryText, outlineVariant = colours.separator, error = Color(0xFFFF453A),
    ) else lightColorScheme(
        primary = colours.accent, onPrimary = Color.White, secondary = colours.accent, background = colours.paper, surface = colours.paper,
        surfaceContainer = colours.card, surfaceContainerLow = colours.card, surfaceContainerHigh = Color(0xFFF2F2F7),
        surfaceContainerHighest = Color(0xFFE5E5EA), onBackground = colours.text, onSurface = colours.text,
        onSurfaceVariant = colours.secondaryText, outlineVariant = colours.separator, error = Color(0xFFD70015),
    )
    val typography = Typography(
        displayLarge = LeanrType.largeTitle, displayMedium = LeanrType.title, displaySmall = LeanrType.title2Display,
        headlineLarge = LeanrType.title, headlineMedium = LeanrType.title2Display, headlineSmall = LeanrType.title3,
        titleLarge = LeanrType.display(22f), titleMedium = LeanrType.headline, titleSmall = LeanrType.subheadline.copy(fontWeight = FontWeight.Medium),
        bodyLarge = LeanrType.body, bodyMedium = LeanrType.subheadline, bodySmall = LeanrType.caption,
        labelLarge = LeanrType.headline.copy(fontSize = 15.sp), labelMedium = LeanrType.label, labelSmall = LeanrType.tabLabel,
    )
    CompositionLocalProvider(LocalLeanr provides colours) {
        MaterialTheme(colorScheme = scheme, typography = typography, content = content)
    }
}

/** The order-pad paper behind every screen: flat cream (or a pack's tint) with a fine grid of dots 20 dp apart. */
@Composable
fun LeanrBackground(modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit = {}) {
    val c = Leanr.colours
    Box(modifier.fillMaxSize().background(c.paper)) {
        val dot = c.ink.copy(alpha = if (c.dark) 0.13f else 0.16f)
        Canvas(Modifier.fillMaxSize()) {
            val step = 20.dp.toPx(); val radius = 0.8.dp.toPx()
            var x = step / 2
            while (x <= size.width) {
                var y = step / 2
                while (y <= size.height) { drawCircle(dot, radius, Offset(x, y)); y += step }
                x += step
            }
        }
        content()
    }
}
