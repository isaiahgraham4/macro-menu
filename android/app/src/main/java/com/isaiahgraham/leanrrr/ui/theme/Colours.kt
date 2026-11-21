package com.isaiahgraham.leanrrr.ui.theme

import androidx.compose.ui.graphics.Color
import com.isaiahgraham.leanrrr.billing.Premium
import kotlin.math.pow

// A port of Shared/AppAccent.swift and Theme.swift: the accent presets, custom colours kept readable,
// paper tints, macro colours and colour packs. Stored values match iOS ("green", "#RRGGBB", "cream").

data class Rgb(val r: Double, val g: Double, val b: Double) {
    fun color(): Color = Color(r.toFloat(), g.toFloat(), b.toFloat())
    companion object {
        fun hex(v: Long) = Rgb(((v shr 16) and 0xFF) / 255.0, ((v shr 8) and 0xFF) / 255.0, (v and 0xFF) / 255.0)
    }
}

/** A stored colour choice: a preset name such as "blue", or a custom colour as "#RRGGBB". */
object ThemeColour {
    /** Light mode: the darkest page tint (Oat). Dark mode: grouped cards. The strictest backgrounds in each. */
    val lightBackground = Rgb.hex(0xF3ECE2)
    val darkBackground = Rgb.hex(0x1C1C1E)
    const val MINIMUM_CONTRAST = 4.5

    fun color(raw: String?, fallback: AppAccent, dark: Boolean): Color {
        if (raw == null) return fallback.color(dark)
        AppAccent.fromRaw(raw)?.let { return it.color(dark) }
        rgb(raw)?.let { return readable(it, dark).color() }
        return fallback.color(dark)
    }

    /** The same hue, darkened (light mode) or lightened (dark mode) only as far as needed for 4.5:1. */
    fun readable(c: Rgb, dark: Boolean): Rgb {
        val background = if (dark) darkBackground else lightBackground
        val target = if (dark) 1.0 else 0.0
        var out = c
        var step = 0
        while (contrast(out, background) < MINIMUM_CONTRAST && step < 40) {
            out = Rgb(out.r + (target - out.r) * 0.05, out.g + (target - out.g) * 0.05, out.b + (target - out.b) * 0.05)
            step++
        }
        return out
    }

    fun isAdjusted(raw: String): Boolean {
        if (!isCustom(raw)) return false
        val c = rgb(raw) ?: return false
        return contrast(c, lightBackground) < MINIMUM_CONTRAST || contrast(c, darkBackground) < MINIMUM_CONTRAST
    }

    fun contrast(a: Rgb, b: Rgb): Double {
        val la = luminance(a); val lb = luminance(b)
        return (maxOf(la, lb) + 0.05) / (minOf(la, lb) + 0.05)
    }

    fun luminance(c: Rgb): Double {
        fun lin(x: Double) = if (x <= 0.04045) x / 12.92 else ((x + 0.055) / 1.055).pow(2.4)
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    fun isValid(raw: String) = AppAccent.fromRaw(raw) != null || rgb(raw) != null
    fun isCustom(raw: String) = AppAccent.fromRaw(raw) == null && rgb(raw) != null

    fun rgb(raw: String): Rgb? {
        if (raw.length != 7 || raw[0] != '#') return null
        val v = raw.drop(1).toLongOrNull(16) ?: return null
        return Rgb.hex(v)
    }

    fun hex(r: Double, g: Double, b: Double): String {
        fun byte(x: Double) = Math.round(x.coerceIn(0.0, 1.0) * 255).toInt()
        return "#%02X%02X%02X".format(byte(r), byte(g), byte(b))
    }

    fun hex(color: Color): String = hex(color.red.toDouble(), color.green.toDouble(), color.blue.toDouble())
}

/** One palette for the app and its widgets. Light mode uses darker shades so text stays readable; dark mode the system colours made readable. */
enum class AppAccent(val raw: String, private val light: Long, private val darkSystem: Long) {
    GREEN("green", 0x01714C, 0x2BC47A),
    MINT("mint", 0x006D63, 0x63E6E2),
    TEAL("teal", 0x006B79, 0x40CBE0),
    CYAN("cyan", 0x00698B, 0x64D2FF),
    BLUE("blue", 0x005DC2, 0x0A84FF),
    INDIGO("indigo", 0x4B45D1, 0x5E5CE6),
    PURPLE("purple", 0x8A2FB0, 0xBF5AF2),
    PINK("pink", 0xB71756, 0xFF375F),
    RED("red", 0xB52525, 0xFF453A),
    ORANGE("orange", 0x9D4900, 0xFF9F0A),
    BROWN("brown", 0x7A5634, 0xAC8E68),
    GRAPHITE("graphite", 0x5E5E63, 0x8E8E93);

    val title: String get() = raw.replaceFirstChar { it.uppercase() }

    fun color(dark: Boolean): Color = when {
        this == GREEN -> if (dark) Color(0xFF2BC47A) else Color(0xFF01714C)
        dark -> ThemeColour.readable(Rgb.hex(darkSystem), dark = true).color()
        else -> Rgb.hex(light).color()
    }

    companion object {
        const val STORAGE_KEY = "accent"
        val standard = GREEN
        fun fromRaw(raw: String?): AppAccent? = entries.firstOrNull { it.raw == raw }

        /** The colour to use for a stored choice, honouring the Premium lock. */
        fun resolved(raw: String): AppAccent = if (!Premium.isUnlocked) standard else fromRaw(raw) ?: standard
        /** The colour to draw with, including a custom "#RRGGBB" choice, honouring the Premium lock. */
        fun resolvedColor(raw: String, dark: Boolean): Color =
            if (Premium.isUnlocked) ThemeColour.color(raw, standard, dark) else standard.color(dark)
        fun resolvedRaw(raw: String): String = if (Premium.isUnlocked && ThemeColour.isValid(raw)) raw else standard.raw
    }
}

/** The page colour behind every screen: the order-pad cream, or a faint wash of a pack's colour. Flat colours only. */
enum class PaperTint(val raw: String, private val light: Long, private val dark: Long) {
    CREAM("cream", 0xF6F2EA, 0x121714),
    PEACH("peach", 0xF8EDE2, 0x1A1410),
    BLUSH("blush", 0xF8ECEC, 0x1B1113),
    LILAC("lilac", 0xF4ECF3, 0x181119),
    MOSS("moss", 0xEDF1E8, 0x0F1610),
    MIST("mist", 0xE9F1F3, 0x0D151A),
    SAGE("sage", 0xEEF1EA, 0x121612),
    OAT("oat", 0xF3ECE2, 0x17130F),
    FOG("fog", 0xEDEFF1, 0x121418);

    val title: String get() = raw.replaceFirstChar { it.uppercase() }
    fun color(dark: Boolean): Color = Rgb.hex(if (dark) this.dark else light).color()

    companion object {
        const val STORAGE_KEY = "paperTint"
        fun fromRaw(raw: String?): PaperTint? = entries.firstOrNull { it.raw == raw }
        /** Cream when Premium is locked or the value is unknown. */
        fun resolved(raw: String): PaperTint = if (Premium.isUnlocked) fromRaw(raw) ?: CREAM else CREAM
    }
}

object MacroColours {
    const val PROTEIN_KEY = "macroColour.protein"
    const val CARBS_KEY = "macroColour.carbs"
    const val FAT_KEY = "macroColour.fat"
    fun colour(key: String, choices: Map<String, String>, dark: Boolean): Color {
        val fallback = when (key) { "p" -> AppAccent.BLUE; "c" -> AppAccent.ORANGE; else -> AppAccent.RED }
        return ThemeColour.color(choices[key], fallback, dark)
    }
}

enum class AppAppearance(val raw: String) {
    SYSTEM("system"), LIGHT("light"), DARK("dark");
    val title: String get() = raw.replaceFirstChar { it.uppercase() }
    companion object {
        const val STORAGE_KEY = "appearance"
        fun fromRaw(raw: String?) = entries.firstOrNull { it.raw == raw } ?: SYSTEM
    }
}

/** Launcher icon themes (activity-alias names on Android). The raw value "black" is the default, as on iOS. */
enum class AppIconTheme(val raw: String) {
    STANDARD("black"), BERRY("berry"), CREAM("cream"), CRIMSON("crimson"), FOREST("forest"), LATTE("latte"), MIDNIGHT("midnight"),
    OCEAN("ocean"), PLUM("plum"), SAGE("sage"), SLATE("slate"), TERRACOTTA("terracotta"), WARM("warm");

    val title: String get() = if (this == STANDARD) "Default" else raw.replaceFirstChar { it.uppercase() }
    companion object {
        const val STORAGE_KEY = "appIcon"
        fun fromRaw(raw: String?) = entries.firstOrNull { it.raw == raw } ?: STANDARD
    }
}

/** A matching set: icon, app colour, the three macro colours and a paper tint. Classic is free; the rest need Even Leanrrr. */
data class ColourPack(
    val id: String, val name: String, val detail: String, val icon: AppIconTheme, val accent: AppAccent,
    val protein: AppAccent, val carbs: AppAccent, val fat: AppAccent, val paper: PaperTint,
) {
    val isFree: Boolean get() = id == "classic"

    companion object {
        val all = listOf(
            ColourPack("classic", "Classic", "Emerald with blue, orange and red", AppIconTheme.STANDARD, AppAccent.GREEN, AppAccent.BLUE, AppAccent.ORANGE, AppAccent.RED, PaperTint.CREAM),
            ColourPack("warm", "Warm", "Terracotta, ember and toast", AppIconTheme.WARM, AppAccent.ORANGE, AppAccent.RED, AppAccent.ORANGE, AppAccent.BROWN, PaperTint.PEACH),
            ColourPack("crimson", "Crimson", "Deep red with pink and plum", AppIconTheme.CRIMSON, AppAccent.RED, AppAccent.PINK, AppAccent.ORANGE, AppAccent.PURPLE, PaperTint.BLUSH),
            ColourPack("berry", "Berry", "Plum, raspberry and blackcurrant", AppIconTheme.BERRY, AppAccent.PURPLE, AppAccent.INDIGO, AppAccent.PINK, AppAccent.PURPLE, PaperTint.LILAC),
            ColourPack("forest", "Forest", "Pine, bark and autumn leaves", AppIconTheme.FOREST, AppAccent.GREEN, AppAccent.TEAL, AppAccent.BROWN, AppAccent.ORANGE, PaperTint.MOSS),
            ColourPack("ocean", "Ocean", "Deep blue, sea glass and dusk", AppIconTheme.OCEAN, AppAccent.BLUE, AppAccent.BLUE, AppAccent.TEAL, AppAccent.PURPLE, PaperTint.MIST),
            ColourPack("sage", "Sage", "Soft mint, clay and stone", AppIconTheme.SAGE, AppAccent.MINT, AppAccent.INDIGO, AppAccent.BROWN, AppAccent.GRAPHITE, PaperTint.SAGE),
            ColourPack("latte", "Latte", "Coffee, caramel and steel", AppIconTheme.LATTE, AppAccent.BROWN, AppAccent.BROWN, AppAccent.ORANGE, AppAccent.GRAPHITE, PaperTint.OAT),
            ColourPack("slate", "Slate", "Quiet grey with the classic macro colours", AppIconTheme.SLATE, AppAccent.GRAPHITE, AppAccent.BLUE, AppAccent.ORANGE, AppAccent.RED, PaperTint.FOG),
        )

        fun matching(accent: String, protein: String, carbs: String, fat: String, icon: String, paper: String?): ColourPack? = all.firstOrNull {
            it.accent.raw == accent && it.protein.raw == protein && it.carbs.raw == carbs && it.fat.raw == fat && it.icon.raw == icon &&
                (paper == null || it.paper.raw == paper)
        }
    }
}

/** Green when the protein goal is reached, orange when carbs or fat are over (TargetStatus in DesignKit.swift). */
enum class TargetStatus {
    NONE, REACHED, OVER;
    fun colour(dark: Boolean): Color? = when (this) {
        NONE -> null
        REACHED -> if (dark) Color(0xFF34D36B) else Color(0xFF0B7A2E)
        OVER -> if (dark) Color(0xFFFFA02E) else Color(0xFFB85400)
    }
}
