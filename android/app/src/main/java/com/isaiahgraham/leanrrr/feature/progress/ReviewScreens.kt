package com.isaiahgraham.leanrrr.feature.progress

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Eco
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.Achievement
import com.isaiahgraham.leanrrr.data.Moment
import com.isaiahgraham.leanrrr.data.achievements
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.data.rememberStringPref
import com.isaiahgraham.leanrrr.ui.components.LeanrRow
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrBackground
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlinx.coroutines.launch
import java.time.LocalDate

// Ports of WeeklyReviewView.swift, YearReviewView.swift and AchievementsView.swift.

@Composable
fun WeeklyReviewScreen(onBack: () -> Unit) {
    val store = AppServices.store
    var weeksBack by remember { mutableIntStateOf(0) }
    var sharing by remember { mutableStateOf(false) }
    val review = WeeklyReview.make(store.data, store.goals, ending = LocalDate.now().minusDays(7L * weeksBack))
    LeanrScreen("Your week", onBack = onBack) {
        item {
            LeanrSection {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { weeksBack += 1 }) { Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, "Previous week", tint = Leanr.colours.accent) }
                    Text(review.range, style = LeanrType.headline, color = Leanr.colours.text, modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                    IconButton(onClick = { weeksBack -= 1 }, enabled = weeksBack > 0) {
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, "Next week", tint = if (weeksBack > 0) Leanr.colours.accent else Leanr.colours.tertiaryText)
                    }
                }
            }
        }
        if (review.loggedDays == 0) {
            item { LeanrSection { EmptyState(Icons.Filled.CalendarMonth, "Nothing logged this week", "Log a few days and your review fills in here.") } }
        } else {
            item {
                Column(Modifier.padding(bottom = 20.dp)) {
                    StatGrid(review)
                    Text("Averages count only the days you logged, so they aren't pulled down by days you skipped.", style = LeanrType.footnote,
                        color = Leanr.colours.secondaryText, modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp))
                }
            }
            if (review.nudges.isNotEmpty()) item {
                LeanrSection("Fibre and sodium", footer = "Counts only days where every food you logged lists the nutrient (fibre on ${review.fibre.countedDays} of ${review.loggedDays} logged days, sodium on ${review.sodium.countedDays}). A guide isn't a diagnosis: if you have a medical reason to watch either, follow your doctor or dietitian.") {
                    review.nudges.forEach { SectionText(it, colour = Leanr.colours.text) }
                }
            }
            if (review.topMeals.isNotEmpty()) item {
                LeanrSection("Most logged") {
                    review.topMeals.forEachIndexed { i, meal -> ValueRow(meal.name, "${meal.count} times", divider = i < review.topMeals.size - 1) }
                }
            }
            item {
                LeanrSection {
                    LeanrRow("Share this week", divider = false, titleColour = Leanr.colours.accent, leading = { Icon(Icons.Filled.Share, null, tint = Leanr.colours.accent) },
                        onClick = { sharing = true })
                }
            }
        }
    }
    if (sharing) ShareCardSheet("My week in Leanrrr", { sharing = false }, designs = false) { WeeklyReviewCard(review) }
}

/** The review's numbers as tiles. `onCard` draws them in the light card's colours. */
@Composable
private fun StatGrid(review: WeeklyReview, onCard: Boolean = false) {
    fun nutrientDetail(week: WeeklyReview.NutrientWeek, unit: String): String {
        if (week.average == null) return "Not every food you logged lists it"
        val label = if (week.targetIsGuide) "Guide" else "Target"
        return "$label ${if (week.isMinimum) "" else "≤ "}${week.target.rounded().number} $unit · ${week.countedDays} of ${week.loggedDays} ${if (week.loggedDays == 1) "day" else "days"}"
    }
    val total = review.totalCalorieTarget?.let {
        "Target ${it.rounded().number} Cal over ${when (review.loggedDays) { 7 -> "the week"; 1 -> "the day you logged"; else -> "the ${review.loggedDays} days you logged" }}"
    }
    val tiles = listOf(
        Triple("Days logged", "${review.loggedDays} of 7", null),
        Triple("Avg calories", review.averageCalories?.let { it.rounded().number } ?: "–", review.calorieTarget?.let { "Target ${it.rounded().number} Cal" }),
        Triple("Avg protein", review.averageProtein?.let { "${it.rounded().number} g" } ?: "–", review.proteinTarget?.let { "Target ${it.rounded().number} g" }),
        Triple("Protein hit", if (review.proteinTarget == null) "–" else "${review.proteinDays} ${if (review.proteinDays == 1) "day" else "days"}", "At or above target"),
        Triple("Calories on target", if (review.calorieTarget == null) "–" else "${review.calorieDays} ${if (review.calorieDays == 1) "day" else "days"}", "At or under target"),
        Triple("Avg fibre", review.fibre.average?.let { "${it.rounded().number} g" } ?: "–", nutrientDetail(review.fibre, "g")),
        Triple("Avg sodium", review.sodium.average?.let { "${it.rounded().number} mg" } ?: "–", nutrientDetail(review.sodium, "mg")),
        Triple("Weight trend", review.weightChange?.let { "${WeeklyReview.signed(it)} kg" } ?: "–", review.trendWeight?.let { "Now ${it.number} kg" } ?: "Weigh in to see it"),
    )
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        StatTile("Total calories", "${review.totalCalories.rounded().number} Cal", total, onCard, Modifier.fillMaxWidth())
        tiles.chunked(2).forEach { pair ->
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Max), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                pair.forEach { (title, value, detail) -> StatTile(title, value, detail, onCard, Modifier.weight(1f).fillMaxHeight()) }
            }
        }
    }
}

@Composable
private fun StatTile(title: String, value: String, detail: String?, onCard: Boolean, modifier: Modifier) {
    val c = Leanr.colours
    val ink = if (onCard) Color.Black else c.text
    val dim = if (onCard) Color(0x993C3C43) else c.secondaryText
    Column(modifier.heightIn(min = 78.dp).clip(RoundedCornerShape(14.dp)).background(if (onCard) Color(0x14000000) else c.card).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(title, style = LeanrType.caption, color = dim)
        Text(value, style = LeanrType.roboto(22f, FontWeight.Bold), color = ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
        detail?.let { Text(it, style = LeanrType.caption, color = dim, maxLines = 2) }
    }
}

/** An always-light card to share, matching the meal card. */
@Composable
fun WeeklyReviewCard(review: WeeklyReview) {
    val accent = com.isaiahgraham.leanrrr.ui.theme.AppAccent.resolvedColor(
        rememberStringPref(com.isaiahgraham.leanrrr.ui.theme.AppAccent.STORAGE_KEY, com.isaiahgraham.leanrrr.ui.theme.AppAccent.standard.raw).value, false)
    Column(Modifier.background(Color.White).padding(22.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Eco, null, tint = accent, modifier = Modifier.size(14.dp)); Spacer(Modifier.width(4.dp))
            Text("LEANRRR", style = LeanrType.caption.copy(fontWeight = FontWeight.Bold), color = accent)
        }
        Column {
            Text("My week", style = LeanrType.largeTitle, color = Color.Black)
            Text(review.range, style = LeanrType.subheadline, color = Color(0x993C3C43))
        }
        StatGrid(review, onCard = true)
        if (review.topMeals.isNotEmpty()) Text("Most logged: " + review.topMeals.joinToString(", ") { it.name }, style = LeanrType.subheadline, color = Color.Black)
    }
}

/** The review as story cards, one for each thing there is to say. */
fun YearReview.cards(chainName: (String) -> String): List<StoryCardContent> {
    val name = year.toString(); val footnote = name
    val cards = mutableListOf(StoryCardContent("calendar", "$name in Leanrrr", Pair(meals.grouped(), "meals logged"),
        "Across ${days.grouped()} ${if (days == 1) "day" else "days"}.", null, footnote))
    val meal = topMeal; val chain = topChain
    if (meal != null) {
        val chainLine = chain?.let { " ${chainName(it.first)} was your most logged restaurant." } ?: ""
        cards += StoryCardContent("fork.knife", meal.first, null, "Your most logged meal, ${meal.second} ${if (meal.second == 1) "time" else "times"}.$chainLine", null, footnote)
    } else if (chain != null) {
        cards += StoryCardContent("fork.knife", chainName(chain.first), null, "Your most logged restaurant, ${chain.second} ${if (chain.second == 1) "item" else "items"}.", null, footnote)
    }
    cards += StoryCardContent("flame.fill", "Longest streak", Pair(bestStreak.grouped(), if (bestStreak == 1) "day" else "days"),
        if (proteinDays > 0) "And you hit your protein target on ${proteinDays.grouped()} ${if (proteinDays == 1) "day" else "days"}." else "That's how habits start.", null, footnote)
    weight?.let { cards += StoryCardContent("scalemass.fill", if (it.losing) "You lost" else "You gained", Pair(it.moved.number, "kg"), "On your way to ${it.goal.number} kg.", null, footnote) }
    return cards
}

/** The year's cards to swipe through, each one shareable as a story image. Full screen, over whatever opened it. */
@Composable
fun YearReviewScreen(review: YearReview, onDismiss: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val cards = review.cards(store::chainName)
    val pager = rememberPagerState { cards.size }
    var designRaw by rememberStringPref(StoryDesign.STORAGE_KEY, StoryDesign.NIGHT.raw)
    val design = StoryDesign.fromRaw(designRaw)
    val layers = cards.map { rememberGraphicsLayer() }
    BackHandler(onBack = onDismiss)
    LeanrBackground {
        Column(Modifier.fillMaxSize().statusBarsPadding().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("Your ${review.year}", style = LeanrType.title, color = c.text, modifier = Modifier.weight(1f))
                TextButton(onClick = onDismiss) { Text("Done", color = c.accent, fontWeight = FontWeight.Bold) }
            }
            HorizontalPager(pager, Modifier.weight(1f)) { page ->
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Box(Modifier.widthIn(max = 320.dp).clip(RoundedCornerShape(18.dp)).capturing(layers[page])) { StoryCard(cards[page], design) }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                cards.indices.forEach { Box(Modifier.size(7.dp).clip(CircleShape).background(if (it == pager.currentPage) c.accent else c.text.copy(alpha = 0.2f))) }
            }
            Segmented(StoryDesign.entries.map { it to it.title }, design, { designRaw = it.raw })
            Button(
                onClick = { scope.launch { shareBitmap(context, layers[pager.currentPage].captureBitmap(), "My ${review.year} in Leanrrr") } },
                colors = ButtonDefaults.buttonColors(containerColor = c.accent, contentColor = if (c.dark) Color.Black else Color.White),
                shape = RoundedCornerShape(14.dp), modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp),
            ) { Icon(Icons.Filled.Share, null); Spacer(Modifier.width(8.dp)); Text("Share this card", style = LeanrType.headline) }
        }
    }
}

/** Every milestone reached so far, and the next of each kind to aim for. */
@Composable
fun AchievementsScreen(onBack: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    val shelf = store.data.achievements()
    var sharing by remember { mutableStateOf<Moment?>(null) }
    LeanrScreen("Achievements", onBack = onBack) {
        Achievement.Group.entries.forEach { group ->
            val rows = shelf.filter { it.group == group }
            if (rows.isNotEmpty()) item {
                LeanrSection(group.title) {
                    rows.forEachIndexed { i, achievement ->
                        val copy = achievement.moment.copy
                        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(symbolIcon(copy.icon), null, tint = if (achievement.earned) c.accent else c.tertiaryText, modifier = Modifier.size(28.dp))
                            Spacer(Modifier.width(14.dp))
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text(copy.title, style = LeanrType.headline, color = if (achievement.earned) c.text else c.secondaryText)
                                achievement.left?.let { Text(it, style = LeanrType.caption, color = c.secondaryText) }
                                achievement.progress?.let { ThinBar(it) }
                            }
                            if (achievement.earned && copy.shareable) IconButton(onClick = { sharing = achievement.moment }) {
                                Icon(Icons.Filled.Share, "Share ${copy.title} as an image", tint = c.accent)
                            }
                        }
                        if (i < rows.size - 1) androidx.compose.material3.HorizontalDivider(Modifier.padding(start = 58.dp), color = c.separator, thickness = 0.5.dp)
                    }
                }
            }
        }
    }
    sharing?.let { MomentShareSheet(it) { sharing = null } }
}
