package com.isaiahgraham.leanrrr.feature.settings

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.Calculate
import androidx.compose.material.icons.outlined.ConfirmationNumber
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.automirrored.outlined.DirectionsWalk
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.PanTool
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.TrackChanges
import androidx.compose.material.icons.outlined.Verified
import androidx.compose.material.icons.outlined.WaterDrop
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.draw.clip
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.BuildConfig
import com.isaiahgraham.leanrrr.billing.Premium
import com.isaiahgraham.leanrrr.billing.PremiumAccess
import com.isaiahgraham.leanrrr.billing.Purchases
import com.isaiahgraham.leanrrr.data.Goals
import com.isaiahgraham.leanrrr.data.MenuRegion
import com.isaiahgraham.leanrrr.data.Prefs
import com.isaiahgraham.leanrrr.data.rememberBoolPref
import com.isaiahgraham.leanrrr.data.rememberStringPref
import com.isaiahgraham.leanrrr.feature.health.HealthConnectSettings
import com.isaiahgraham.leanrrr.feature.onboarding.OnboardingScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.theme.AppAccent
import com.isaiahgraham.leanrrr.ui.theme.AppAppearance
import com.isaiahgraham.leanrrr.ui.theme.AppIconTheme
import com.isaiahgraham.leanrrr.ui.theme.ColourPack
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import com.isaiahgraham.leanrrr.ui.theme.MacroColours
import com.isaiahgraham.leanrrr.ui.theme.PaperTint
import com.isaiahgraham.leanrrr.ui.theme.ThemeColour
import kotlinx.coroutines.launch
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** The pages Settings can push. */
private sealed interface Route {
    data object Targets : Route
    data class GoalEditor(val goal: Goals) : Route
    data object Calculator : Route
    data object Water : Route
    data object Steps : Route
    data object MacroColours : Route
    data object Reminders : Route
    data object Sources : Route
    data class Legal(val document: LegalDocument) : Route
    data object Acknowledgements : Route
    data object Delete : Route
}

/** Settings (SettingsView.swift), a sheet over the tabs with its own stack of pages. */
@Composable
fun SettingsSheet(onDismiss: () -> Unit) {
    val stack = remember { mutableStateListOf<Route>() }
    var showPremium by remember { mutableStateOf(false) }
    var showQuiz by remember { mutableStateOf(false) }
    fun push(route: Route) { stack += route }
    fun pop() { if (stack.isNotEmpty()) stack.removeAt(stack.lastIndex) }

    FullScreenSheet(onDismiss) {
        when (val route = stack.lastOrNull()) {
            null -> SettingsHome(onDismiss, ::push, openPremium = { showPremium = true }, openQuiz = { showQuiz = true })
            Route.Targets -> TargetsScreen(::pop, edit = { push(Route.GoalEditor(it)) })
            is Route.GoalEditor -> GoalEditorScreen(route.goal, ::pop)
            Route.Calculator -> TargetCalculatorScreen(::pop) { values ->
                val store = AppServices.store
                if (store.applyEstimatedTargets(values)) { pop(); store.notice = "Targets updated" }
            }
            Route.Water -> WaterSettingsScreen(::pop)
            Route.Steps -> StepsSettingsScreen(::pop)
            Route.MacroColours -> MacroColourScreen(::pop)
            Route.Reminders -> ReminderSettingsScreen(::pop)
            Route.Sources -> SourcesScreen(::pop)
            is Route.Legal -> LegalDocumentScreen(route.document, ::pop)
            Route.Acknowledgements -> AcknowledgementsScreen(::pop)
            Route.Delete -> DeleteDataScreen(::pop, onDeleted = { stack.clear(); onDismiss() })
        }
    }
    if (showPremium) PremiumSheet(onDismiss = { showPremium = false })
    if (showQuiz) FullScreenSheet(onDismiss = { showQuiz = false }, dismissOnBack = true) {
        OnboardingScreen(finished = { showQuiz = false }, askCountry = false)
    }
}

private val menuDateFormat = DateTimeFormatter.ofPattern("d MMM yyyy", Locale.forLanguageTag("en-AU"))

@Composable
private fun SettingsHome(onDismiss: () -> Unit, push: (Route) -> Unit, openPremium: () -> Unit, openQuiz: () -> Unit) {
    val store = AppServices.store
    val nav = AppServices.nav
    val c = Leanr.colours
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val unlocked = Premium.isUnlocked

    var appearance by rememberStringPref(AppAppearance.STORAGE_KEY, AppAppearance.SYSTEM.raw)
    var accentRaw by rememberStringPref(AppAccent.STORAGE_KEY, AppAccent.standard.raw)
    var iconRaw by rememberStringPref(AppIconTheme.STORAGE_KEY, AppIconTheme.STANDARD.raw)
    var proteinRaw by rememberStringPref(MacroColours.PROTEIN_KEY, "blue")
    var carbsRaw by rememberStringPref(MacroColours.CARBS_KEY, "orange")
    var fatRaw by rememberStringPref(MacroColours.FAT_KEY, "red")
    var paperRaw by rememberStringPref(PaperTint.STORAGE_KEY, PaperTint.CREAM.raw)
    var suggestFoods by rememberBoolPref("today.suggestions", true)
    var liveDay by rememberBoolPref("liveDay", false)
    var featureTips by rememberBoolPref(FeatureTips.ENABLED_KEY, true)
    var countryFailed by remember { mutableStateOf(false) }
    var checking by remember { mutableStateOf(false) }

    val current = AppAccent.resolved(accentRaw)
    val isCustomAccent = unlocked && ThemeColour.isCustom(accentRaw)
    val currentIcon = AppIconTheme.fromRaw(iconRaw)
    val currentPaper = PaperTint.resolved(paperRaw)
    val currentPack = ColourPack.matching(accentRaw, proteinRaw, carbsRaw, fatRaw, iconRaw, if (Prefs.string(PaperTint.STORAGE_KEY) != null) paperRaw else null)

    fun applyPack(pack: ColourPack) {
        accentRaw = pack.accent.raw; proteinRaw = pack.protein.raw; carbsRaw = pack.carbs.raw; fatRaw = pack.fat.raw; paperRaw = pack.paper.raw
        if (currentIcon != pack.icon) AppIcons.select(context, pack.icon) else iconRaw = pack.icon.raw
        store.refreshWidgets()
    }

    LeanrScreen("Settings", showSettings = false, actions = { TextButton(onClick = onDismiss) { Text("Done", style = LeanrType.headline, color = c.accent) } }) {
        if (Premium.SUBSCRIPTIONS_ENABLED) item {
            SettingsSection {
                LinkRow("Even Leanrrr", if (unlocked) Icons.Outlined.Verified else Icons.Outlined.AutoAwesome, divider = false, chevron = false,
                    trailingText = if (unlocked) (if (Premium.unlockedState) PremiumAccess.statusText(Purchases.entitlement) else "Turned on for testing") else "See what's included",
                    onClick = openPremium)
            }
        }
        item {
            SettingsSection("Appearance") {
                MenuPickerRow("Theme", AppAppearance.entries, AppAppearance.fromRaw(appearance), { it.title }, { appearance = it.raw })
                NoteRow("System follows your device’s appearance and changes automatically with it.")
            }
        }
        item {
            SettingsSection("Colour packs", footer = {
                if (unlocked) Text("${currentPack?.name ?: "Your own mix"} · Sets the app icon, app colour, macro colours and background together. You can still change any of them below.",
                    style = LeanrType.footnote, color = c.secondaryText, modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp))
                else LockedFooter("Colour packs come with Even Leanrrr.")
            }) {
                ColourPack.all.forEachIndexed { i, pack ->
                    val locked = !unlocked && !pack.isFree
                    ColourPackRow(pack, selected = pack == currentPack, locked = locked, divider = i < ColourPack.all.lastIndex) {
                        if (locked) openPremium() else applyPack(pack)
                    }
                }
            }
        }
        item {
            SettingsSection("App colour", footer = {
                if (unlocked) Text("${if (isCustomAccent) "Custom" else current.title} · Changes buttons, tabs, links and progress bars." + (lightWarning(accentRaw)?.let { " $it" } ?: ""),
                    style = LeanrType.footnote, color = c.secondaryText, modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp))
                else LockedFooter("More colours come with Even Leanrrr.")
            }) {
                SwatchGrid(count = AppAccent.entries.size) { i ->
                    val accent = AppAccent.entries[i]
                    val locked = !unlocked && accent != AppAccent.standard
                    // A locked colour opens Even Leanrrr instead of doing nothing.
                    AccentSwatch(accent.color(c.dark), chosen = !isCustomAccent && accent == current, locked = locked,
                        label = if (locked) "${accent.title}, needs Even Leanrrr" else accent.title) {
                        if (locked) openPremium() else { accentRaw = accent.raw; store.refreshWidgets() }
                    }
                }
                CustomColourRow("Custom colour", accentRaw, { accentRaw = it; store.refreshWidgets() }, AppAccent.standard, onLocked = openPremium)
            }
        }
        item {
            SettingsSection("Background", footer = {
                if (unlocked) Text("${currentPaper.title} · A faint tint behind every screen, in light and dark mode.", style = LeanrType.footnote,
                    color = c.secondaryText, modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp))
                else LockedFooter("Tinted backgrounds come with Even Leanrrr.")
            }) {
                SwatchGrid(columns = 3, count = PaperTint.entries.size) { i ->
                    val tint = PaperTint.entries[i]
                    val locked = !unlocked && tint != PaperTint.CREAM
                    ChoiceTile(tint.title, tint == currentPaper, locked, 80.dp, 58.dp, 10.dp,
                        if (locked) "${tint.title} background, needs Even Leanrrr" else "${tint.title} background",
                        onClick = { if (locked) openPremium() else paperRaw = tint.raw }) { m -> PaperSwatch(tint, m) }
                }
            }
        }
        item {
            SettingsSection("App icon", footerText = if (unlocked) currentIcon.title else "${currentIcon.title} · More icon packs come with Even Leanrrr.") {
                SwatchGrid(columns = 3, count = AppIconTheme.entries.size) { i ->
                    val icon = AppIconTheme.entries[i]
                    val locked = !unlocked && icon != AppIconTheme.STANDARD
                    ChoiceTile(icon.title, icon == currentIcon, locked, 72.dp, 72.dp, 15.dp,
                        if (locked) "${icon.title} app icon, needs Even Leanrrr" else "${icon.title} app icon",
                        onClick = { if (locked) openPremium() else AppIcons.select(context, icon) }) { m ->
                        Image(painterResource(AppIcons.preview(icon)), null, contentScale = ContentScale.Crop, modifier = m.clip(RoundedCornerShape(15.dp)))
                    }
                }
            }
        }
        item {
            SettingsSection("Restaurant menus", footerText = "Changes which restaurants Leanrrr shows. Foods you’ve logged or saved keep their numbers. Supermarket ready meals and Copycat Kitchen are only in Australia.") {
                MenuPickerRow("Country", MenuRegion.entries, store.region, { it.title }, { region ->
                    if (region != store.region) scope.launch {
                        if (store.useRegion(region)) runCatching { store.checkForUpdates() } else countryFailed = true
                    }
                }, icon = Icons.Outlined.Language, divider = false)
            }
        }
        item {
            SettingsSection("Targets") {
                LinkRow("Targets & target sets", Icons.Outlined.TrackChanges) { push(Route.Targets) }
                LinkRow("Calculate my macros", Icons.Outlined.Calculate, chevron = false) { push(Route.Calculator) }
                LinkRow("Water target", Icons.Outlined.WaterDrop) { push(Route.Water) }
                LinkRow("Steps", Icons.AutoMirrored.Outlined.DirectionsWalk) { push(Route.Steps) }
                SwitchRow("Suggest foods for what's left", suggestFoods, { suggestFoods = it }, icon = Icons.Outlined.Lightbulb)
                SwitchRow("Show tips for features I haven't tried", featureTips, { featureTips = it }, icon = Icons.Outlined.AutoAwesome)
                LinkRow("Target colours", Icons.Outlined.Palette) { push(Route.MacroColours) }
                LinkRow("Reminders", Icons.Outlined.Notifications, divider = false) { push(Route.Reminders) }
            }
        }
        item {
            SettingsSection(footerText = "Shows the calories you have left in an ongoing notification, so you can see them from the lock screen and the notification shade. It updates as you log.") {
                SwitchRow("Calories in an ongoing notification", liveDay, { liveDay = it; store.refreshWidgets() }, icon = Icons.Outlined.NotificationsActive, divider = false)
            }
        }
        item {
            SettingsSection("Health Connect", footerText = "Saves the food and water you log and your weigh-ins to Health Connect, and reads your weight, active energy and steps. To choose exactly what Leanrrr can read or write, open Health Connect → App permissions → Leanrrr.") {
                HealthConnectSettings()
            }
        }
        item {
            SettingsSection("Backup", footerText = "Android keeps a copy of your foods, logs, targets and weigh-ins in your Google account backup, and puts it back when you set up a new phone. Your current meal and settings like colours stay on each phone.") {
                NoteRow("Backed up with your Google account", primary = true)
            }
        }
        item { BackupSection() }
        item {
            SettingsSection("About") {
                ValueRow("App", "Leanrrr")
                ValueRow("Developer", AppInfo.DEVELOPER)
                AppInfo.contactEmail?.let { email -> ValueRow("Contact", email) { openUrl(context, "mailto:$email") } }
                ButtonRow("Play the calorie quiz", onClick = openQuiz)
                ButtonRow("Take the tour of the tabs") { nav.tourRequested = true }
                LinkRow("Menu sources", Icons.Outlined.Info) { push(Route.Sources) }
                ValueRow("Menu updated", store.menuDate?.atZone(ZoneId.systemDefault())?.format(menuDateFormat) ?: "Built in")
                LinkRow(if (checking) "Checking for updated menus…" else "Check for updated menus", Icons.Outlined.Refresh, chevron = false) {
                    if (checking) return@LinkRow
                    checking = true
                    scope.launch {
                        val before = store.catalog.revision to store.listVersions
                        val ok = runCatching { store.checkForUpdates(force = true) }.isSuccess
                        checking = false
                        store.notice = when {
                            !ok -> "Couldn’t check for updates. Try again later."
                            before != (store.catalog.revision to store.listVersions) -> "Food data updated"
                            else -> "Your food data is up to date"
                        }
                    }
                }
                ValueRow("Version", BuildConfig.VERSION_NAME, divider = false)
            }
        }
        item {
            SettingsSection("Privacy and legal") {
                LinkRow("Privacy policy", Icons.Outlined.PanTool) { push(Route.Legal(LegalDocument.PRIVACY)) }
                LinkRow("Terms of use", Icons.Outlined.Description) { push(Route.Legal(LegalDocument.TERMS)) }
                LinkRow("Acknowledgements", Icons.AutoMirrored.Outlined.MenuBook) { push(Route.Acknowledgements) }
                LinkRow("Delete all my data", Icons.Outlined.Delete, titleColour = Color(0xFFD70015), divider = false) { push(Route.Delete) }
            }
        }
        if (Premium.SUBSCRIPTIONS_ENABLED && !unlocked) item {
            // Last in Settings. Google Play's own page for promo codes made in Play Console.
            SettingsSection(footerText = "Got a code for Even Leanrrr? Enter it in Google Play to start it free.") {
                LinkRow("Redeem a code", Icons.Outlined.ConfirmationNumber, divider = false, chevron = false) { Purchases.redeemCode(context) }
            }
        }
        if (BuildConfig.DEBUG) item {
            SettingsSection("Debug", footerText = "Debug builds only. Unlocks every Even Leanrrr feature without buying, for testing.") {
                SwitchRow("Force Even Leanrrr on", Premium.forcedState, { Purchases.force(it) }, divider = false)
            }
        }
    }
    if (countryFailed) MessageAlert("Couldn’t load that menu", "Your restaurant menus haven’t changed.") { countryFailed = false }
}

/** Where each chain's figures come from (SourcesView in Components.swift). */
@Composable
private fun SourcesScreen(onBack: () -> Unit) {
    val store = AppServices.store
    val context = LocalContext.current
    SettingsPage("Menu sources", onBack) {
        item {
            SettingsSection {
                NoteRow("${store.region.menuNote} Missing nutrients stay unknown. Custom orders and recipes are estimates based on their ingredients.", primary = true)
            }
        }
        (store.catalog.chains.filter { it.id != "mine" } + store.supermarketChains).forEach { chain ->
            item(key = chain.id) {
                SettingsSection(chain.name) {
                    NoteRow(chain.src ?: "", divider = chain.url != null)
                    chain.url?.let { url -> ButtonRow("View source", divider = false) { openUrl(context, url) } }
                }
            }
        }
    }
}

