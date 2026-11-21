package com.isaiahgraham.leanrrr.feature.today

import android.content.Intent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.EditCalendar
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.outlined.AddCircleOutline
import androidx.compose.material.icons.outlined.CameraAlt
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.outlined.LocalFireDepartment
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material.icons.outlined.Exposure
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.billing.Premium
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.LogEntry
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.dayKey
import com.isaiahgraham.leanrrr.data.mealText
import com.isaiahgraham.leanrrr.data.newId
import com.isaiahgraham.leanrrr.data.nutrientNames
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.feature.meal.FoodEditorScreen
import com.isaiahgraham.leanrrr.feature.meal.MealSharePreview
import com.isaiahgraham.leanrrr.feature.meal.MealShareRequest
import com.isaiahgraham.leanrrr.feature.scan.BarcodeScanScreen
import com.isaiahgraham.leanrrr.feature.scan.MealPhotoScreen
import com.isaiahgraham.leanrrr.feature.scan.MenuScanScreen
import com.isaiahgraham.leanrrr.feature.settings.PremiumSheet
import com.isaiahgraham.leanrrr.ui.components.ActionTile
import com.isaiahgraham.leanrrr.ui.components.CalorieRing
import com.isaiahgraham.leanrrr.ui.components.LeanrRow
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.components.TargetBar
import com.isaiahgraham.leanrrr.ui.components.TileRow
import com.isaiahgraham.leanrrr.ui.components.countingValue
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.LocalDate

/** Screens Today pushes over itself. */
private sealed interface TodayRoute {
    data object Breakdown : TodayRoute
    data object Calendar : TodayRoute
    data object Targets : TodayRoute
    data object Plan : TodayRoute
    data object QuickAdd : TodayRoute
    data object EnterFood : TodayRoute
    data object Barcode : TodayRoute
    data object Photo : TodayRoute
    data object Describe : TodayRoute
    data object MenuScan : TodayRoute
    data object Choose : TodayRoute
    data class MealDetail(val mealTime: MealTime) : TodayRoute
    data class EditLog(val entry: LogEntry, val day: String) : TodayRoute
    data class Share(val request: MealShareRequest) : TodayRoute
}

/** The Today tab (TodayView.swift): the day's targets, ways to log food, the meals logged, water and steps. */
@Composable
fun TodayScreen() {
    val store = AppServices.store
    val nav = AppServices.nav
    val c = Leanr.colours
    val context = LocalContext.current
    var dateKey by rememberSaveable { mutableStateOf(dayKey(LocalDate.now())) }
    val date = LocalDate.parse(dateKey)
    var now by remember { mutableStateOf(LocalDate.now()) }
    var mealTime by rememberSaveable { mutableStateOf(MealTime.suggested()) }
    val stack = remember { mutableStateListOf<TodayRoute>() }
    var showPremium by remember { mutableStateOf(false) }
    var choosingDay by remember { mutableStateOf(false) }
    var scanned by remember { mutableStateOf<Food?>(null) }

    val key = dayKey(date)
    val isToday = date == now
    val entries = store.data.logs[key] ?: emptyList()
    val total = Nutrition(entries.flatMap { it.items })
    val goals = if (isToday) store.goals else store.data.dayGoals[key] ?: store.goals

    fun push(route: TodayRoute) { stack += route }
    fun pop() { if (stack.isNotEmpty()) stack.removeAt(stack.size - 1) }
    fun setDate(day: LocalDate) { dateKey = dayKey(minOf(day, LocalDate.now())) }
    fun logged(time: MealTime) { store.notice = "Logged to ${time.title.lowercase()}" }
    /** Menu scanning is part of Even Leanrrr: without it, the button opens the Even Leanrrr screen instead. */
    fun scanMenu() { if (Premium.isUnlocked) push(TodayRoute.MenuScan) else showPremium = true }
    /** Plan ahead is part of Even Leanrrr too. Meals already planned still show on Today and can be ticked off. */
    fun planAhead() { if (Premium.isUnlocked) push(TodayRoute.Plan) else showPremium = true }

    // Follows the clock: at midnight a day that was today moves on to the new today.
    LaunchedEffect(Unit) {
        while (true) {
            delay(30_000)
            val following = dateKey == dayKey(now)
            now = LocalDate.now()
            if (following) dateKey = dayKey(now)
        }
    }
    // From the Scan shortcut: log to today, at the meal time it is now. A short wait lets launch settle first.
    LaunchedEffect(nav.scanRequested) {
        if (!nav.scanRequested) return@LaunchedEffect
        dateKey = dayKey(LocalDate.now()); mealTime = MealTime.suggested()
        delay(500)
        stack.clear(); push(TodayRoute.Barcode)
        nav.scanRequested = false
    }

    // The figures wait while another screen is up, so a new meal rolls in once you're back, where you can see it.
    val covered = stack.isNotEmpty() || showPremium || scanned != null
    var shown by remember { mutableStateOf(total) }
    var shownDay by remember { mutableStateOf(key) }
    var gained by remember { mutableStateOf<Pair<String, Double>?>(null) }
    LaunchedEffect(covered, entries, key) {
        if (covered) return@LaunchedEffect
        if (shownDay == key && total.cal > shown.cal) {
            delay(400)
            gained = newId() to (total.cal - shown.cal)
        }
        shown = total; shownDay = key
    }

    scanned?.let { food ->
        ServingsDialog(food, "Log to ${mealTime.title}", onDismiss = { scanned = null }) { portion ->
            if (store.log(listOf(portion), food.name, date, mealTime = mealTime)) logged(mealTime)
        }
    }
    if (showPremium) PremiumSheet(onDismiss = { showPremium = false })

    when (val route = stack.lastOrNull()) {
        TodayRoute.Breakdown -> { DayBreakdownScreen(date, goals, ::pop); return }
        TodayRoute.Calendar -> { TrackingCalendarScreen(date, onSelect = ::setDate, onBack = ::pop); return }
        TodayRoute.Targets -> { TodayTargetsScreen(::pop); return }
        TodayRoute.Plan -> { PlanScreen(::pop); return }
        TodayRoute.QuickAdd -> {
            QuickAddScreen(mealTime, ::pop) { portion, time ->
                if (!store.log(listOf(portion), portion.food.name, date, mealTime = time)) false else { logged(time); true }
            }
            return
        }
        TodayRoute.EnterFood -> {
            BackTo(onBack = ::pop)
            FoodEditorScreen(
                null, onDone = { pop() },
                save = { food -> store.log(listOf(Portion(food = food)), food.name, date, mealTime = mealTime).also { if (it) logged(mealTime) } },
                savePortion = { portion -> store.log(listOf(portion), portion.food.name, date, mealTime = mealTime).also { if (it) logged(mealTime) } },
            )
            return
        }
        TodayRoute.Barcode -> {
            BackTo(onBack = ::pop)
            BarcodeScanScreen(onFound = { food -> pop(); scanned = food }, onDismiss = ::pop)
            return
        }
        TodayRoute.Photo -> { BackTo(onBack = ::pop); MealPhotoScreen(onDismiss = ::pop); return }
        TodayRoute.MenuScan -> { BackTo(onBack = ::pop); MenuScanScreen(onDismiss = ::pop); return }
        TodayRoute.Describe -> {
            MealTextScreen(mealTime, ::pop) { portions, name ->
                if (!store.log(portions, name, date, mealTime = mealTime)) false else { logged(mealTime); true }
            }
            return
        }
        TodayRoute.Choose -> {
            FoodPickerScreen("Choose menu item", "Log to ${mealTime.title}", onBack = ::pop, onPick = { portion ->
                if (store.log(listOf(portion), portion.food.name, date, mealTime = mealTime)) { pop(); logged(mealTime) }
            })
            return
        }
        is TodayRoute.MealDetail -> { MealTimeDetailScreen(route.mealTime, date, ::pop); return }
        is TodayRoute.EditLog -> { LogEditorScreen(route.entry, route.day, ::pop); return }
        is TodayRoute.Share -> { BackTo(onBack = ::pop); MealSharePreview(route.request, onDismiss = ::pop); return }
        null -> {}
    }

    val streak = TrackingStreak.streak(store.data, now)
    LeanrScreen(if (isToday) "Today" else "Daily log", actions = {
        Row(Modifier.clip(RoundedCornerShape(50)).clickable(onClickLabel = "Tracking calendar") { push(TodayRoute.Calendar) }
            .padding(horizontal = 10.dp, vertical = 8.dp).semantics { contentDescription = "Tracking calendar, $streak day streak" },
            verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.CalendarMonth, null, tint = c.accent, modifier = Modifier.size(22.dp))
            Spacer(Modifier.width(4.dp))
            Text("$streak", style = LeanrType.headline, color = c.accent)
        }
    }) {
        // The day sits straight on the background, under the title.
        item(key = "day") {
            Column(Modifier.fillMaxWidth().padding(bottom = 8.dp)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { setDate(date.minusDays(1)) }) { Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, "Previous day", tint = c.accent) }
                    Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                        TextButton(onClick = { choosingDay = true }) { Text(abbreviatedDate(date), style = LeanrType.subheadline.copy(fontWeight = FontWeight.Medium), color = c.text) }
                    }
                    IconButton(onClick = { setDate(date.plusDays(1)) }, enabled = !isToday) {
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, "Next day", tint = if (isToday) c.tertiaryText else c.accent)
                    }
                }
                if (!isToday) TextButton(onClick = { setDate(LocalDate.now()) }, modifier = Modifier.align(Alignment.CenterHorizontally)) {
                    Text("Jump to today", style = LeanrType.subheadline.copy(fontWeight = FontWeight.Medium), color = c.accent)
                }
            }
        }
        item(key = "targets") { TargetsCard(goals, shown, total, entries, gained, onEdit = { push(TodayRoute.Targets) }, onOpen = { push(TodayRoute.Breakdown) }) }
        item(key = "log") {
            LeanrSection("Log food") {
                MealTimeRow("Log to", mealTime) { mealTime = it }
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    LogMethodButton("Scan", "Scan product barcode", Icons.Filled.QrCodeScanner, Modifier.weight(1f)) { push(TodayRoute.Barcode) }
                    LogMethodButton("Photo", "Photo of your meal", Icons.Outlined.CameraAlt, Modifier.weight(1f)) { push(TodayRoute.Photo) }
                    LogMethodButton("Describe", "Describe your meal", Icons.Outlined.ChatBubbleOutline, Modifier.weight(1f)) { push(TodayRoute.Describe) }
                    LogMethodButton("Quick add", "Quick add calories and macros", Icons.Outlined.Exposure, Modifier.weight(1f)) { push(TodayRoute.QuickAdd) }
                }
                HorizontalDivider(Modifier.padding(start = 16.dp), color = c.separator, thickness = 0.5.dp)
                LeanrRow("Scan a menu", titleColour = c.accent, leading = { Icon(Icons.Filled.MenuBook, null, tint = c.accent) }, trailing = {
                    if (!Premium.isUnlocked) Icon(Icons.Filled.Lock, "Even Leanrrr", tint = c.secondaryText, modifier = Modifier.size(16.dp))
                }) { scanMenu() }
                LeanrRow("Plan ahead", titleColour = c.accent, divider = false, leading = { Icon(Icons.Filled.EditCalendar, null, tint = c.accent) }, trailing = {
                    if (Premium.isUnlocked) Icon(Icons.Filled.ChevronRight, null, tint = c.tertiaryText)
                    else Icon(Icons.Filled.Lock, "Even Leanrrr", tint = c.secondaryText, modifier = Modifier.size(16.dp))
                }) { planAhead() }
            }
        }
        item(key = "planned") { PlannedSection(date) }
        MealTime.entries.forEach { category ->
            item(key = "meal-${category.raw}") {
                val meals = entries.filter { it.mealTime == category }
                MealSection(category, meals, key,
                    onOpen = { push(TodayRoute.MealDetail(category)) },
                    onEdit = { push(TodayRoute.EditLog(it, key)) },
                    onChoose = { mealTime = category; push(TodayRoute.Choose) },
                    onAction = { action ->
                        mealTime = category
                        when (action) {
                            AddAction.SCAN -> push(TodayRoute.Barcode)
                            AddAction.PHOTO -> push(TodayRoute.Photo)
                            AddAction.DESCRIBE -> push(TodayRoute.Describe)
                            AddAction.MENU -> scanMenu()
                            AddAction.QUICK -> push(TodayRoute.QuickAdd)
                            AddAction.ENTER -> push(TodayRoute.EnterFood)
                            AddAction.CHOOSE -> push(TodayRoute.Choose)
                        }
                    },
                    onPinned = { food -> if (store.log(listOf(Portion(food = food)), food.name, date, mealTime = category)) logged(category) },
                )
            }
        }
        val unassigned = entries.filter { it.mealTime == null }
        if (unassigned.isNotEmpty()) item(key = "unassigned") {
            LeanrSection("Unassigned", footer = "Tap an earlier entry to assign it to a meal time.") {
                unassigned.forEachIndexed { i, entry -> LogRow(entry, key, i < unassigned.size - 1) { push(TodayRoute.EditLog(entry, key)) } }
            }
        }
        item(key = "body") {
            LeanrSection {
                WaterRow(date)
                ActivityRows(date)
            }
        }
        item(key = "tiles") {
            TileRow(Modifier.padding(bottom = 20.dp)) {
                ActionTile("Log a menu item", Icons.Filled.Restaurant, Modifier.weight(1f).heightIn(min = 78.dp)) { push(TodayRoute.Choose) }
                ActionTile("Enter a food", Icons.Outlined.EditNote, Modifier.weight(1f)) { push(TodayRoute.EnterFood) }
                if (entries.isNotEmpty()) Box(Modifier.weight(1f)) {
                    var menu by remember { mutableStateOf(false) }
                    ActionTile("Share day", Icons.Outlined.Share, Modifier.fillMaxWidth()) { menu = true }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        DropdownMenuItem(text = { Text("Whole day as image") }, onClick = { menu = false; push(TodayRoute.Share(MealShareRequest.day(entries, date))) })
                        val times = MealTime.entries.filter { time -> entries.any { it.mealTime == time } }
                        if (times.isNotEmpty()) {
                            HorizontalDivider()
                            Text("One meal as image", style = LeanrType.caption, color = c.secondaryText, modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp))
                            times.forEach { time ->
                                DropdownMenuItem(text = { Text(time.title) }, onClick = { menu = false; push(TodayRoute.Share(MealShareRequest.meal(time, entries, date))) })
                            }
                            HorizontalDivider()
                        }
                        DropdownMenuItem(text = { Text("Day as text") }, onClick = {
                            menu = false
                            val text = mealText(longDate(date), entries.flatMap { it.items })
                            val send = Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, text) }
                            context.startActivity(Intent.createChooser(send, null))
                        })
                    }
                }
            }
        }
    }
    if (choosingDay) DayPickerDialog(date, ::setDate) { choosingDay = false }
}

/** The day's ring, figures and target bars; the whole card opens the breakdown. */
@Composable
private fun TargetsCard(
    goals: com.isaiahgraham.leanrrr.data.Goals, shown: Nutrition, total: Nutrition, entries: List<LogEntry>, gained: Pair<String, Double>?,
    onEdit: () -> Unit, onOpen: () -> Unit,
) {
    val c = Leanr.colours
    val macroKeys = listOf("p", "c", "f").filter { goals.values[it] != null }
    val otherKeys = nutrientNames.map { it.key }.filter { it !in listOf("cal", "p", "c", "f") && goals.values[it] != null }
    val partialNames = if (entries.isEmpty()) emptyList() else nutrientNames.filter { n ->
        goals.values[n.key] != null && (total.isPartial(n.key) || (n.key !in listOf("cal", "p", "c", "f") && total.nut[n.key] == null))
    }.map { it.label }
    val cal = goals.values["cal"]
    /** The link fills the space under the bars beside the ring, unless more rows follow below the ring. */
    val linkBesideRing = cal != null && otherKeys.isEmpty() && partialNames.isEmpty()
    val name = goals.name.trim()
    val title = if (name.lowercase().endsWith("targets")) goals.name else "${goals.name} targets"

    Column(Modifier.fillMaxWidth().padding(bottom = 20.dp)) {
        Row(Modifier.fillMaxWidth().padding(start = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(title.uppercase(), style = LeanrType.footnote, color = c.secondaryText, modifier = Modifier.weight(1f))
            TextButton(onClick = onEdit) { Text("Edit", style = LeanrType.subheadline.copy(fontWeight = FontWeight.Medium), color = c.accent) }
        }
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(c.card)
            .clickable(onClickLabel = "Shows everything logged on this day, with micronutrients.", onClick = onOpen)
            .padding(16.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(20.dp), verticalAlignment = Alignment.CenterVertically) {
                if (cal != null) Box(contentAlignment = Alignment.TopCenter) {
                    CalorieRing(shown.cal, cal)
                    gained?.let { (id, amount) -> GainedFigure(id, amount) }
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    if (cal != null) {
                        // Eaten and target beside the ring, so the ring's "left" figure has its working.
                        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                            RingStat("Eaten", shown.cal, Modifier.weight(1f))
                            RingStat("Target", cal, Modifier.weight(1f))
                        }
                    } else if (macroKeys.isEmpty()) {
                        Text("${countingValue(shown.cal).number} Cal eaten", style = LeanrType.roboto(20f, FontWeight.Bold), color = c.text)
                    }
                    macroKeys.forEach { Bar(it, goals, shown) }
                    if (linkBesideRing) BreakdownLink()
                }
            }
            if (otherKeys.isNotEmpty()) {
                otherKeys.chunked(2).forEach { pair ->
                    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        pair.forEach { Box(Modifier.weight(1f)) { Bar(it, goals, shown) } }
                        if (pair.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
            }
            if (partialNames.isNotEmpty()) {
                Text("Partial data for ${partialNames.joinToString(", ")}: some logged items don’t list them.", style = LeanrType.caption, color = c.secondaryText)
            }
            if (!linkBesideRing) BreakdownLink()
        }
    }
}

@Composable
private fun RingStat(title: String, value: Double, modifier: Modifier) {
    val c = Leanr.colours
    Column(modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(title, style = LeanrType.caption, color = c.secondaryText)
        Text("${countingValue(value).number} Cal", style = LeanrType.roboto(17f, FontWeight.Bold), color = c.text, maxLines = 1)
    }
}

@Composable
private fun Bar(key: String, goals: com.isaiahgraham.leanrrr.data.Goals, shown: Nutrition) {
    val n = nutrientNames.first { it.key == key }
    TargetBar(n.label, shown.value(key), goals.values[key] ?: 0.0, n.unit, key in goals.minimums, Leanr.colours.nutrient(key))
}

@Composable
private fun BreakdownLink() {
    val c = Leanr.colours
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically) {
        Text("Full breakdown", style = LeanrType.label, color = c.accent)
        Icon(Icons.Filled.ChevronRight, null, tint = c.accent, modifier = Modifier.size(16.dp))
    }
}

/** The calories just logged, rising off the ring and fading. */
@Composable
private fun GainedFigure(id: String, amount: Double) {
    val rise = remember(id) { Animatable(0f) }
    LaunchedEffect(id) { rise.animateTo(1f, tween(1100)) }
    Text("+${amount.number}", style = LeanrType.headline.copy(fontWeight = FontWeight.Bold), color = Leanr.colours.accent,
        modifier = Modifier.offset(y = (6 - 36 * rise.value).dp).alpha(1 - rise.value))
}

/** One way to add food: an icon over a short word, filling its share of the row. */
@Composable
private fun LogMethodButton(title: String, label: String, icon: ImageVector, modifier: Modifier, onClick: () -> Unit) {
    val c = Leanr.colours
    Column(
        modifier.heightIn(min = 64.dp).clip(RoundedCornerShape(14.dp)).background(c.text.copy(alpha = 0.06f))
            .clickable(onClickLabel = label, onClick = onClick).padding(vertical = 8.dp).semantics { contentDescription = label },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterVertically),
    ) {
        Icon(icon, null, tint = c.accent, modifier = Modifier.size(26.dp))
        Text(title, style = LeanrType.subheadline.copy(fontWeight = FontWeight.Medium), color = c.text, maxLines = 1)
    }
}

private enum class AddAction { SCAN, PHOTO, DESCRIBE, MENU, QUICK, ENTER, CHOOSE }

/** A meal time: its header (opening the meal's totals), a + that opens the menu (hold for other ways to add), and what's logged. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MealSection(
    category: MealTime, meals: List<LogEntry>, day: String,
    onOpen: () -> Unit, onEdit: (LogEntry) -> Unit, onChoose: () -> Unit, onAction: (AddAction) -> Unit, onPinned: (Food) -> Unit,
) {
    val store = AppServices.store
    val c = Leanr.colours
    var menu by remember { mutableStateOf(false) }
    val calories = Nutrition(meals.flatMap { it.items }).cal
    Column(Modifier.fillMaxWidth().padding(bottom = if (meals.isEmpty()) 0.dp else 16.dp)) {
        Row(Modifier.fillMaxWidth().heightIn(min = 44.dp), verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.weight(1f).heightIn(min = 44.dp).clip(RoundedCornerShape(8.dp)).clickable(onClickLabel = "View ${category.title} calories and macros", onClick = onOpen)
                .padding(start = 16.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(category.title, style = LeanrType.headline, color = c.text, modifier = Modifier.weight(1f))
                Text(if (meals.isEmpty()) "Nothing yet" else "${countingValue(calories).number} Cals", style = LeanrType.subheadline,
                    color = if (meals.isEmpty()) c.secondaryText else c.text)
                Icon(Icons.Filled.ChevronRight, null, tint = c.secondaryText, modifier = Modifier.size(18.dp))
            }
            Box {
                Box(Modifier.size(44.dp).clip(RoundedCornerShape(50))
                    .combinedClickable(onClickLabel = "Add to ${category.title}", onLongClickLabel = "Other ways to add", onClick = onChoose, onLongClick = { menu = true })
                    .semantics { contentDescription = "Add to ${category.title}" }, contentAlignment = Alignment.Center) {
                    Icon(Icons.Outlined.AddCircleOutline, null, tint = c.accent, modifier = Modifier.size(26.dp))
                }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    val pinned = store.pinnedFoods
                    if (pinned.isNotEmpty()) {
                        Text("Pinned", style = LeanrType.caption, color = c.secondaryText, modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp))
                        pinned.forEach { food ->
                            DropdownMenuItem(text = { Text("${food.name} · ${food.cal.number} Cal") }, leadingIcon = { Icon(Icons.Outlined.PushPin, null) },
                                onClick = { menu = false; onPinned(food) })
                        }
                        HorizontalDivider()
                    }
                    fun item(title: String, action: AddAction, locked: Boolean = false) = Pair(title, action) to locked
                    listOf(
                        item("Scan barcode", AddAction.SCAN), item("Photo of your meal", AddAction.PHOTO), item("Describe your meal", AddAction.DESCRIBE),
                        item("Scan a menu", AddAction.MENU, !Premium.isUnlocked), item("Quick add calories and macros", AddAction.QUICK),
                        item("Enter a food / scan label", AddAction.ENTER), item("Choose menu item", AddAction.CHOOSE),
                    ).forEach { (entry, locked) ->
                        DropdownMenuItem(text = { Text(entry.first) }, trailingIcon = if (locked) ({ Icon(Icons.Filled.Lock, "Even Leanrrr", Modifier.size(16.dp)) }) else null,
                            onClick = { menu = false; onAction(entry.second) })
                    }
                }
            }
        }
        if (meals.isNotEmpty()) {
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(c.card)) {
                meals.forEachIndexed { i, entry -> LogRow(entry, day, i < meals.size - 1) { onEdit(entry) } }
            }
        }
    }
}

/** A logged meal: name, figures and time. Tap to edit; hold to copy it to today or delete it. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun LogRow(entry: LogEntry, day: String, divider: Boolean, onEdit: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    var menu by remember { mutableStateOf(false) }
    Box {
        Column {
            Row(Modifier.fillMaxWidth().combinedClickable(onLongClickLabel = "More", onClick = onEdit, onLongClick = { menu = true })
                .padding(horizontal = 16.dp, vertical = 11.dp), verticalAlignment = Alignment.Top) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(entry.name, style = LeanrType.headline, color = c.text)
                    Text(Nutrition(entry.items).text, style = LeanrType.caption, color = c.secondaryText)
                }
                Spacer(Modifier.width(8.dp))
                Text(clockTime(entry.time), style = LeanrType.caption, color = c.secondaryText)
            }
            if (divider) HorizontalDivider(Modifier.padding(start = 16.dp), color = c.separator, thickness = 0.5.dp)
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(text = { Text("Copy to today") }, onClick = {
                menu = false
                if (store.log(entry.items, entry.name, LocalDate.now(), mealTime = entry.mealTime)) store.notice = "Copied to today"
            })
            DropdownMenuItem(text = { Text("Delete", color = c.over) }, onClick = { menu = false; store.deleteLog(entry, day) })
        }
    }
}

/**
 * Steps and calories burnt from Health Connect, when it has sent any this week (StepsRow and ActiveEnergyRow; the connect
 * buttons live in Progress and Settings).
 */
@Composable
private fun ActivityRows(date: LocalDate) {
    val store = AppServices.store
    val c = Leanr.colours
    val key = dayKey(date)
    if (store.widgetSteps.isNotEmpty()) {
        HorizontalDivider(Modifier.padding(start = 16.dp), color = c.separator, thickness = 0.5.dp)
        val steps = store.widgetSteps[key] ?: 0.0
        val goal = store.data.stepGoal ?: com.isaiahgraham.leanrrr.data.AppStore.DEFAULT_STEP_GOAL
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.AutoMirrored.Filled.DirectionsWalk, null, tint = c.accent, modifier = Modifier.width(32.dp).size(26.dp))
                Spacer(Modifier.width(14.dp))
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text("Steps", style = LeanrType.headline, color = c.text)
                    Text("${steps.whole.number} of ${goal.whole.number}", style = LeanrType.caption, color = c.secondaryText)
                }
            }
            val share = (steps / maxOf(goal, 1.0)).coerceIn(0.0, 1.0).toFloat()
            Box(Modifier.fillMaxWidth().heightIn(min = 6.dp, max = 6.dp).clip(RoundedCornerShape(50)).background(c.accent.copy(alpha = 0.16f))) {
                Box(Modifier.fillMaxWidth(share).heightIn(min = 6.dp, max = 6.dp).clip(RoundedCornerShape(50)).background(c.accent))
            }
        }
    }
    if (store.widgetEnergy.isNotEmpty()) {
        HorizontalDivider(Modifier.padding(start = 16.dp), color = c.separator, thickness = 0.5.dp)
        val burnt = store.widgetEnergy[key] ?: 0.0
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Outlined.LocalFireDepartment, null, tint = c.over, modifier = Modifier.width(32.dp).size(26.dp))
            Spacer(Modifier.width(14.dp))
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("Calories burnt", style = LeanrType.headline, color = c.text)
                Text(if (burnt > 0) "${burnt.whole.number} Cal active" else "None recorded", style = LeanrType.caption, color = c.secondaryText)
            }
        }
    }
}
