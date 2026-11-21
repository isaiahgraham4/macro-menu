package com.isaiahgraham.leanrrr.feature.onboarding

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Eco
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Fastfood
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.TrackChanges
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.MenuRegion
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.feature.health.HealthConnectSettings
import com.isaiahgraham.leanrrr.feature.health.HealthSync
import com.isaiahgraham.leanrrr.feature.settings.FullScreenSheet
import com.isaiahgraham.leanrrr.feature.settings.TargetCalculatorScreen
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.roundToInt

/** The dark brown the cutting board's words are written in. */
val BOARD_INK = Color(0.23f, 0.17f, 0.10f)

/** A wooden board with a light grain, under the quiz, the tour of the tabs and the moment cards. Flat colour, no gradient. */
@Composable
fun CuttingBoard(modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    val shape = RoundedCornerShape(28.dp)
    Box(modifier.clip(shape).background(Color(0.89f, 0.77f, 0.59f))) {
        Canvas(Modifier.matchParentSize()) {
            for (line in 0 until 32) {
                val y = line * size.height / 31
                val path = Path().apply {
                    moveTo(0f, y)
                    cubicTo(size.width * 0.3f, y - 9.dp.toPx(), size.width * 0.7f, y + 12.dp.toPx(), size.width, y + 6.dp.toPx())
                }
                drawPath(path, Color(0.6f, 0.4f, 0.2f).copy(alpha = if (line % 3 == 0) 0.13f else 0.06f), style = Stroke(1.dp.toPx()))
            }
        }
        Box(Modifier.matchParentSize().padding(7.dp).border(1.dp, Color(0.6f, 0.4f, 0.2f).copy(alpha = 0.18f), RoundedCornerShape(22.dp)))
        content()
    }
}

/**
 * First-run setup (LeanrOnboarding.swift): the country, a guess-the-calories quiz with that country's meals, then the optional
 * target, location and Health Connect steps. Settings replays the quiz with `askCountry` off.
 */
@Composable
fun OnboardingScreen(finished: () -> Unit, askCountry: Boolean = true) {
    val store = AppServices.store
    val c = Leanr.colours
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var round by remember { mutableIntStateOf(0) }
    var guess by remember { mutableFloatStateOf(600f) }
    var revealed by remember { mutableStateOf(false) }
    var countingUp by remember { mutableStateOf(false) }
    var quizDone by remember { mutableStateOf(false) }
    val guesses = remember { mutableStateMapOf<String, Double>() }
    var targetPrompt by remember { mutableStateOf(false) }
    var estimatingTargets by remember { mutableStateOf(false) }
    var targetSaveFailed by remember { mutableStateOf(false) }
    /** After the quiz: 0 targets, 1 location, 2 Health Connect. Steps already answered are skipped. */
    var setupStep by remember { mutableIntStateOf(0) }
    var countryPicked by remember { mutableStateOf(!askCountry) }
    var countryFailed by remember { mutableStateOf(false) }

    fun locationGranted() = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
    fun advance() {
        var next = setupStep + 1
        if (next == 1 && locationGranted()) next += 1
        if (next == 2 && (HealthSync.enabled || !HealthSync.available)) next += 1
        if (next > 2) finished() else setupStep = next
    }
    val locationAsk = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { advance() }

    val meals: List<Food> = store.region.quiz.mapNotNull { (id, _) -> store.catalog.foods.firstOrNull { it.id == id } }
    fun note(meal: Food) = store.region.quiz.firstOrNull { it.first == meal.id }?.second ?: "No sides or drink"
    val meal = meals.getOrNull(round)
    val answeredMeals = meals.filter { guesses[it.id] != null }
    val guessedTotal = guesses.values.sum()
    val actualTotal = answeredMeals.sumOf { it.cal }
    val calorieGap = actualTotal - guessedTotal

    Column(Modifier.fillMaxSize().statusBarsPadding().verticalScroll(rememberScrollState()).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Column(Modifier.widthIn(max = 600.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(26.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Eco, null, tint = c.accent, modifier = Modifier.size(26.dp))
                Spacer(Modifier.width(8.dp))
                Text("LEANRRR", style = LeanrType.title2Display, color = c.text, modifier = Modifier.weight(1f))
                if (countryPicked) TextButton(onClick = { if (targetPrompt) finished() else targetPrompt = true }, modifier = Modifier.heightIn(min = 44.dp)) {
                    Text("Skip", color = c.secondaryText)
                }
            }
            AnimatedContent(Triple(countryPicked, targetPrompt, quizDone), transitionSpec = { fadeIn(tween(350)) togetherWith fadeOut(tween(350)) }, label = "onboarding") { (picked, prompt, done) ->
                Column(verticalArrangement = Arrangement.spacedBy(26.dp)) {
                    when {
                        !picked -> CountryCard { region ->
                            scope.launch { if (store.useRegion(region)) countryPicked = true else countryFailed = true }
                        }
                        prompt -> {
                            Progress(3, setupStep, "Setup step ${setupStep + 1} of 3")
                            when (setupStep) {
                                1 -> SetupCard(Icons.Filled.LocationOn, "Find food near you",
                                    "See the closest restaurants on the map and how far away each order is. Leanrrr only uses your location while it’s open, to find nearby restaurants on OpenStreetMap.",
                                    "Allow location", onNotNow = ::advance) {
                                    locationAsk.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION))
                                }
                                2 -> Column(Modifier.padding(vertical = 24.dp), verticalArrangement = Arrangement.spacedBy(22.dp)) {
                                    Icon(Icons.Filled.Favorite, null, tint = c.accent, modifier = Modifier.size(48.dp))
                                    Text("Connect Health Connect", style = LeanrType.title, color = c.text)
                                    Text("Save the food you log to Health Connect, and bring in your weight and active energy for a smarter calorie target. You choose exactly what to share on the next screen.",
                                        style = LeanrType.body, color = c.secondaryText)
                                    Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(c.card)) { Column { HealthConnectSettings() } }
                                    PrimaryButton("Continue", onClick = ::advance)
                                }
                                else -> Column(Modifier.padding(vertical = 24.dp), verticalArrangement = Arrangement.spacedBy(22.dp)) {
                                    Icon(Icons.Outlined.TrackChanges, null, tint = c.accent, modifier = Modifier.size(48.dp))
                                    Text("Want to find your targets?", style = LeanrType.title, color = c.text)
                                    Text("Estimate your maintenance calories and daily protein, carbs and fat from your age, height, weight and activity level. Choose whether you want to maintain, lose or gain weight.",
                                        style = LeanrType.body, color = c.secondaryText)
                                    Text("This is optional. You can review the estimate before applying it, and change your targets later in Settings.",
                                        style = LeanrType.subheadline, color = c.secondaryText)
                                    PrimaryButton("Find my targets") { estimatingTargets = true }
                                    TextButton(onClick = ::advance, modifier = Modifier.fillMaxWidth().heightIn(min = 44.dp)) { Text("Not now", color = c.accent) }
                                }
                            }
                        }
                        !done && meal == null && !store.foodsLoaded -> Box(Modifier.fillMaxWidth().padding(48.dp), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(color = c.accent)
                        }
                        !done && meal != null -> {
                            Progress(meals.size, round, "Question ${round + 1} of ${meals.size}")
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text("Guess the calories", style = LeanrType.title, color = c.text)
                                Text("How many do you think are in this?", style = LeanrType.body, color = c.secondaryText)
                            }
                            CuttingBoard(Modifier.fillMaxWidth()) {
                                Column(Modifier.fillMaxWidth().padding(28.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                        Text("ON THE BOARD", style = LeanrType.caption.copy(fontWeight = FontWeight.Bold, letterSpacing = 2.sp), color = BOARD_INK, modifier = Modifier.weight(1f))
                                        Text(if (meal.chain == "mcd") "Macca’s" else store.chainName(meal.chain), style = LeanrType.headline, color = BOARD_INK)
                                    }
                                    Icon(Icons.Filled.Fastfood, null, tint = BOARD_INK, modifier = Modifier.padding(vertical = 8.dp).size(60.dp))
                                    Text(meal.name, style = LeanrType.title2Display, color = BOARD_INK, textAlign = TextAlign.Center)
                                    Text(note(meal), style = LeanrType.caption, color = BOARD_INK, textAlign = TextAlign.Center)
                                    if (meal.serve.isNotEmpty()) Text(meal.serve, style = LeanrType.caption, color = BOARD_INK, textAlign = TextAlign.Center)
                                }
                            }
                            if (revealed) {
                                val shown by animateFloatAsState(if (countingUp) meal.cal.toFloat() else guess, tween(1000), label = "reveal")
                                androidx.compose.runtime.LaunchedEffect(round) { countingUp = true }
                                Column(Modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                    Text("${shown.toDouble().roundToInt().toDouble().number} calories", style = LeanrType.roboto(34f, FontWeight.Bold), color = c.text)
                                    Text(if (abs(guess - meal.cal) <= 50) "Close guess! You were within 50 calories."
                                        else "Your guess: ${guess.toInt()} Cal · about ${abs(guess - meal.cal).roundToInt()} Cal away.", style = LeanrType.body, color = c.text)
                                    Text("Leanrrr shows the calories and protein for each item, so you can compare options and build a meal around them.",
                                        style = LeanrType.body, color = c.secondaryText)
                                    Text("${meal.p.number} g protein · Bundled ${store.chainName(meal.chain)} ${store.region.menuLabel} menu data. Servings and recipes may vary.",
                                        style = LeanrType.caption, color = c.secondaryText)
                                }
                            } else {
                                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                    Text("${guess.toInt()} Cal", style = LeanrType.roboto(34f, FontWeight.Bold), color = c.text)
                                    Slider(guess, { guess = (it / 25).roundToInt() * 25f }, valueRange = 100f..1600f, steps = 59,
                                        colors = SliderDefaults.colors(thumbColor = c.accent, activeTrackColor = c.accent),
                                        modifier = Modifier.semantics { contentDescription = "Your calorie guess, ${guess.toInt()} calories" })
                                    Row(Modifier.fillMaxWidth()) {
                                        Text("100 Cal", style = LeanrType.caption, color = c.secondaryText, modifier = Modifier.weight(1f))
                                        Text("1,600 Cal", style = LeanrType.caption, color = c.secondaryText)
                                    }
                                }
                            }
                            PrimaryButton(if (revealed) (if (round + 1 < meals.size) "Try another meal" else "See my total") else "Reveal the calories") {
                                when {
                                    !revealed -> { guesses[meal.id] = guess.toDouble(); revealed = true }
                                    round + 1 < meals.size -> { round += 1; revealed = false; countingUp = false; guess = 600f }
                                    else -> { countingUp = false; quizDone = true }
                                }
                            }
                        }
                        else -> Column(Modifier.padding(vertical = 24.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
                            if (answeredMeals.isNotEmpty()) {
                                Text(if (calorieGap > 0) "You guessed low." else if (calorieGap < 0) "You guessed high." else "Spot on.", style = LeanrType.title, color = c.text)
                                var started by remember { mutableStateOf(false) }
                                androidx.compose.runtime.LaunchedEffect(Unit) { started = true }
                                val gapShown by animateFloatAsState(if (started) abs(calorieGap).toFloat() else 0f, tween(1200), label = "gap")
                                CuttingBoard(Modifier.fillMaxWidth()) {
                                    Column(Modifier.fillMaxWidth().padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                                        Text("${gapShown.roundToInt().toDouble().number} Cal", style = LeanrType.roboto(34f, FontWeight.Bold), color = BOARD_INK)
                                        Text(if (calorieGap > 0) "more than you guessed" else if (calorieGap < 0) "less than you guessed" else "difference from the menu total",
                                            style = LeanrType.headline, color = BOARD_INK)
                                        HorizontalDivider(color = BOARD_INK.copy(alpha = 0.2f))
                                        BoardValue("Your guesses", "${guessedTotal.number} Cal")
                                        BoardValue("Menu total", "${actualTotal.number} Cal")
                                        Text("Across ${answeredMeals.size} quiz items combined. Overestimates offset underestimates in this total.", style = LeanrType.caption, color = BOARD_INK)
                                    }
                                }
                                if (calorieGap > 0) {
                                    Text("If you ate these items and logged your guesses, you’d count ${calorieGap.number} fewer calories than the menu lists. If those guesses brought you to your target, that gap would put you ${calorieGap.number} calories above it across those meals.",
                                        style = LeanrType.body, color = c.text)
                                    Text("Small guessing gaps add up. Leanrrr shows what’s in each meal so you can plan around the real numbers.", style = LeanrType.body, color = c.secondaryText)
                                } else {
                                    Text(if (calorieGap < 0) "Your combined guesses were above the menu total, so you’d have counted more calories than the meals contain. Checking the numbers avoids that."
                                        else "You matched the combined menu total. Leanrrr keeps the numbers handy so you don’t need to guess.", style = LeanrType.body, color = c.secondaryText)
                                }
                            } else {
                                Text("Know what’s in\nyour favourites.", style = LeanrType.title, color = c.text)
                            }
                            Feature(Icons.Filled.Search, "Compare restaurant meals")
                            Feature(Icons.Filled.Restaurant, "Build a meal around your targets")
                            Feature(Icons.Filled.CalendarMonth, "Keep track of your day")
                            Text("Start with the foods you enjoy.", style = LeanrType.body, color = c.secondaryText)
                            PrimaryButton("Continue") { if (askCountry) targetPrompt = true else finished() }
                        }
                    }
                }
            }
        }
    }
    if (estimatingTargets) FullScreenSheet(onDismiss = { estimatingTargets = false }) {
        TargetCalculatorScreen(onCancel = { estimatingTargets = false }) { values ->
            if (store.applyEstimatedTargets(values)) { estimatingTargets = false; advance() } else targetSaveFailed = true
        }
    }
    if (targetSaveFailed) androidx.compose.material3.AlertDialog(
        onDismissRequest = { targetSaveFailed = false },
        confirmButton = { TextButton(onClick = { targetSaveFailed = false }) { Text("OK") } },
        title = { Text("Couldn’t save targets", style = LeanrType.headline) },
        text = { Text("Your targets haven’t changed. Try again or cancel to skip this step.", style = LeanrType.subheadline) },
    )
    if (countryFailed) androidx.compose.material3.AlertDialog(
        onDismissRequest = { countryFailed = false },
        confirmButton = { TextButton(onClick = { countryFailed = false }) { Text("OK") } },
        title = { Text("Couldn’t load that menu", style = LeanrType.headline) },
        text = { Text("Try again, or choose another country and change it later in Settings.", style = LeanrType.subheadline) },
    )
}

@Composable
private fun CountryCard(choose: (MenuRegion) -> Unit) {
    val c = Leanr.colours
    Column(Modifier.padding(vertical = 24.dp), verticalArrangement = Arrangement.spacedBy(22.dp)) {
        Icon(Icons.Filled.Public, null, tint = c.accent, modifier = Modifier.size(48.dp))
        Text("Where will you be eating?", style = LeanrType.title, color = c.text)
        Text("Leanrrr shows the menus of restaurants in your country. You can change this later in Settings.", style = LeanrType.body, color = c.secondaryText)
        val suggested = MenuRegion.suggested
        (listOf(suggested) + MenuRegion.entries.filter { it != suggested }).forEach { region ->
            OutlinedButton(onClick = { choose(region) }, shape = RoundedCornerShape(12.dp), modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)
                .semantics { contentDescription = "${region.title}. Shows ${region.title} restaurant menus" }) {
                Text(region.title, style = LeanrType.headline, color = c.accent, modifier = Modifier.weight(1f))
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = c.accent)
            }
        }
    }
}

@Composable
private fun SetupCard(icon: ImageVector, title: String, text: String, action: String, onNotNow: () -> Unit, perform: () -> Unit) {
    val c = Leanr.colours
    Column(Modifier.padding(vertical = 24.dp), verticalArrangement = Arrangement.spacedBy(22.dp)) {
        Icon(icon, null, tint = c.accent, modifier = Modifier.size(48.dp))
        Text(title, style = LeanrType.title, color = c.text)
        Text(text, style = LeanrType.body, color = c.secondaryText)
        PrimaryButton(action, onClick = perform)
        TextButton(onClick = onNotNow, modifier = Modifier.fillMaxWidth().heightIn(min = 44.dp)) { Text("Not now", color = c.accent) }
    }
}

@Composable
private fun Progress(count: Int, current: Int, label: String) {
    val c = Leanr.colours
    Row(Modifier.fillMaxWidth().semantics { contentDescription = label }, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        repeat(count) { i -> Box(Modifier.weight(1f).height(4.dp).clip(CircleShape).background(if (i <= current) c.accent else c.secondaryText.copy(alpha = 0.2f))) }
    }
}

@Composable
private fun PrimaryButton(title: String, onClick: () -> Unit) {
    val c = Leanr.colours
    Button(onClick = onClick, colors = ButtonDefaults.buttonColors(containerColor = c.accent, contentColor = if (c.dark) Color.Black else Color.White),
        shape = RoundedCornerShape(14.dp), modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)) { Text(title, style = LeanrType.headline) }
}

@Composable
private fun Feature(icon: ImageVector, title: String) {
    val c = Leanr.colours
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = c.accent)
        Spacer(Modifier.width(12.dp))
        Text(title, style = LeanrType.body, color = c.text)
    }
}

@Composable
private fun BoardValue(label: String, value: String) {
    Row(Modifier.fillMaxWidth()) {
        Text(label, style = LeanrType.body, color = BOARD_INK, modifier = Modifier.weight(1f))
        Text(value, style = LeanrType.body, color = BOARD_INK)
    }
}

