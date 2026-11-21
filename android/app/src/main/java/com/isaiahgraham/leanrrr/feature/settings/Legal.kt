package com.isaiahgraham.leanrrr.feature.settings

import android.app.NotificationManager
import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.Prefs
import com.isaiahgraham.leanrrr.ui.components.LeanrRow
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlinx.coroutines.launch
import java.io.File

/** Who makes Leanrrr, for the About screen and the policies. */
object AppInfo {
    const val DEVELOPER = "Isaiah Graham"
    const val LOCATION = "Victoria, Australia"
    /** The support address shown in the policies and Settings. */
    val contactEmail: String? = "isaiahgraham.app@gmail.com"
    val contactText: String get() = contactEmail ?: "the contact details on Leanrrr's Google Play page"
}

/** The privacy policy or terms, read from the Markdown files bundled as assets (the same text as the iOS app). */
enum class LegalDocument(val file: String, val title: String) {
    PRIVACY("PrivacyPolicy.md", "Privacy policy"),
    TERMS("Terms.md", "Terms of use"),
}

private sealed interface Block {
    data class Heading(val text: String) : Block
    data class Paragraph(val text: String) : Block
    data class Bullet(val text: String) : Block
}

/** Headings (`##`), bullets (`- `) and paragraphs. The `#` title line is left out; the screen has its own. */
private fun parse(text: String): List<Block> = text.lines().mapNotNull { raw ->
    val line = raw.trim()
    when {
        line.isEmpty() || line.startsWith("# ") -> null
        line.startsWith("## ") -> Block.Heading(line.drop(3))
        line.startsWith("- ") -> Block.Bullet(line.drop(2))
        else -> Block.Paragraph(line)
    }
}

/** **Bold**, *italic* and [links](https://...) inside a line, the inline Markdown the policies use. */
private fun inline(text: String, link: Color): AnnotatedString = buildAnnotatedString {
    val pattern = Regex("""\*\*(.+?)\*\*|\*(.+?)\*|\[(.+?)]\((.+?)\)""")
    var last = 0
    for (match in pattern.findAll(text)) {
        append(text.substring(last, match.range.first))
        val (bold, italic, label, url) = match.destructured
        when {
            bold.isNotEmpty() -> withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(bold) }
            italic.isNotEmpty() -> withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { append(italic) }
            else -> withLink(LinkAnnotation.Url(url, TextLinkStyles(SpanStyle(color = link)))) { append(label) }
        }
        last = match.range.last + 1
    }
    append(text.substring(last))
}

@Composable
internal fun LegalDocumentScreen(document: LegalDocument, onBack: () -> Unit) {
    val context = LocalContext.current
    val c = Leanr.colours
    val blocks = remember(document) {
        val text = runCatching { context.assets.open(document.file).bufferedReader().use { it.readText() } }.getOrNull()
        if (text == null) listOf(Block.Paragraph("This document couldn't be loaded."))
        else parse(text.replace("{{CONTACT}}", AppInfo.contactText).replace("{{DEVICE}}", "phone"))
    }
    SettingsPage(document.title, onBack) {
        item {
            SelectionContainer {
                Column(Modifier.widthIn(max = 640.dp).padding(horizontal = 4.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    blocks.forEach { block ->
                        when (block) {
                            is Block.Heading -> Text(block.text, style = LeanrType.headline.copy(fontWeight = FontWeight.Bold), color = c.text, modifier = Modifier.padding(top = 10.dp))
                            is Block.Paragraph -> Text(inline(block.text, c.accent), style = LeanrType.body, color = c.text)
                            is Block.Bullet -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text("•", style = LeanrType.body, color = c.text)
                                Text(inline(block.text, c.accent), style = LeanrType.body, color = c.text)
                            }
                        }
                    }
                }
            }
        }
    }
}

/** Fonts, data sources and trademarks, with the licence texts the fonts require. */
@Composable
internal fun AcknowledgementsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val c = Leanr.colours
    var licence by remember { mutableStateOf<Pair<String, String>?>(null) }
    licence?.let { (name, file) -> LicenceScreen(name, file, onBack = { licence = null }); return }
    SettingsPage("Acknowledgements", onBack) {
        item {
            SettingsSection("Restaurants") {
                NoteRow("Leanrrr isn't affiliated with, endorsed by or sponsored by any restaurant, supermarket or delivery service. Restaurant, supermarket and product names and brands belong to their owners and are used only to identify their food.", primary = true)
            }
        }
        item {
            SettingsSection("Data") {
                Credit("Restaurant nutrition", "Each chain's published nutrition information. See Settings → Menu sources.")
                Credit("Product data", "Open Food Facts, available under the Open Database License (ODbL).") { openUrl(context, "https://world.openfoodfacts.org/terms-of-use") }
                Credit("Everyday foods", "U.S. Department of Agriculture, Agricultural Research Service. FoodData Central (SR Legacy), public domain.") { openUrl(context, "https://fdc.nal.usda.gov") }
                Credit("Maps and places", "© OpenStreetMap contributors, available under the Open Database License (ODbL).", divider = false) { openUrl(context, "https://www.openstreetmap.org/copyright") }
            }
        }
        item {
            SettingsSection("Fonts") {
                LeanrRow("Roboto", "Copyright 2011 Google Inc. Apache License, Version 2.0.", onClick = { licence = "Roboto" to "Apache-2.0.txt" })
                LeanrRow("Bebas Neue", "Copyright 2019 The Bebas Neue Project Authors. SIL Open Font License, Version 1.1.", divider = false,
                    onClick = { licence = "Bebas Neue" to "OFL-BebasNeue.txt" })
            }
        }
        item {
            SettingsSection("Icons") {
                NoteRow("Leanrrr's icons are Google's Material Symbols, available under the Apache License, Version 2.0.", primary = true)
            }
        }
    }
}

@Composable
private fun Credit(title: String, detail: String, divider: Boolean = true, link: (() -> Unit)? = null) {
    val c = Leanr.colours
    Column {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 11.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = LeanrType.subheadline.copy(fontWeight = FontWeight.SemiBold), color = c.text)
            Text(detail, style = LeanrType.subheadline, color = c.secondaryText)
            if (link != null) TextButton(onClick = link, contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp)) { Text("Licence", style = LeanrType.subheadline, color = c.accent) }
        }
        if (divider) androidx.compose.material3.HorizontalDivider(Modifier.padding(start = 16.dp), color = c.separator, thickness = 0.5.dp)
    }
}

@Composable
private fun LicenceScreen(name: String, file: String, onBack: () -> Unit) {
    val context = LocalContext.current
    val text = remember(file) { runCatching { context.assets.open(file).bufferedReader().use { it.readText() } }.getOrDefault("") }
    SettingsPage(name, onBack) {
        item {
            SelectionContainer {
                Text(text, style = LeanrType.footnote.copy(fontFamily = FontFamily.Monospace), color = Leanr.colours.text,
                    modifier = Modifier.horizontalScroll(rememberScrollState()).padding(4.dp))
            }
        }
    }
}

/** Deletes everything Leanrrr keeps on this phone, and (if chosen) what it saved to Health Connect. */
@Composable
internal fun DeleteDataScreen(onBack: () -> Unit, onDeleted: () -> Unit) {
    val context = LocalContext.current
    val c = Leanr.colours
    val scope = rememberCoroutineScope()
    var confirming by remember { mutableStateOf(false) }
    var working by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf<String?>(null) }
    SettingsPage("Delete all my data", onBack) {
        item {
            SettingsSection {
                NoteRow("This deletes your foods, recipes, saved meals, food log, meal plans, check-ins, weigh-ins, measurements, water, progress photos, targets, reminders and settings from this phone. It can't be undone.", divider = true, primary = true)
                NoteRow("Want a copy first? Export a backup in Settings.")
            }
        }
        item {
            SettingsSection(footerText = "Leanrrr's copy in your Google account backup is replaced the next time your phone backs up. Anything Leanrrr wrote to Health Connect stays there; remove it in Health Connect → App permissions → Leanrrr. I don't hold any of your data, so there's nothing else to delete.") {
                LeanrRow("Delete all my data", titleColour = if (working) c.tertiaryText else Color(0xFFD70015), divider = false,
                    leading = { Icon(Icons.Outlined.Delete, null, tint = Color(0xFFD70015)) },
                    trailing = { if (working) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) },
                    onClick = if (working) null else ({ confirming = true }))
            }
        }
    }
    if (confirming) AlertDialog(
        onDismissRequest = { confirming = false },
        title = { Text("Delete everything?", style = LeanrType.headline) },
        text = { Text("Your Leanrrr data on this phone will be deleted.", style = LeanrType.subheadline) },
        confirmButton = {
            TextButton(onClick = {
                confirming = false; working = true
                scope.launch {
                    val ok = DataDeletion.deleteEverything(context)
                    working = false
                    if (ok) result = "Leanrrr has started fresh."
                }
            }) { Text("Delete", color = Color(0xFFD70015)) }
        },
        dismissButton = { TextButton(onClick = { confirming = false }) { Text("Cancel") } },
    )
    result?.let { MessageAlert("Your data is deleted", it) { result = null; onDeleted() } }
}

object DataDeletion {
    /** Cancels reminders, clears settings and files, then starts the store again empty. False if the store couldn't be emptied. */
    suspend fun deleteEverything(context: Context): Boolean {
        MealReminders.cancelAll(context)
        runCatching { (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancelAll() }
        clearSettings(context)
        val ok = AppServices.store.eraseEverything()
        AppServices.store.refreshWidgets()
        return ok
    }

    /** Clears saved settings and files, keeping only that onboarding was seen. Downloaded menus stay; they aren't yours. */
    fun clearSettings(context: Context) {
        Prefs.shared.edit().clear().apply()
        Prefs.set("leanr.onboarding.completed", true)
        Prefs.set(com.isaiahgraham.leanrrr.feature.settings.TabTour.SEEN_KEY, true)
        com.isaiahgraham.leanrrr.billing.Purchases.entitlement?.let { com.isaiahgraham.leanrrr.billing.PremiumAccess.save(it) }
        context.filesDir.listFiles()?.filter { it.name != "MacroMenu" && it.name != "Updates" }?.forEach { it.deleteRecursively() }
        File(context.cacheDir, "").listFiles()?.forEach { it.deleteRecursively() }
    }
}
