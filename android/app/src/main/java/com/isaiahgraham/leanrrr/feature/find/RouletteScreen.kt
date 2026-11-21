package com.isaiahgraham.leanrrr.feature.find

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Eco
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.Vibration
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.dayKey
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.data.rememberStringPref
import com.isaiahgraham.leanrrr.ui.components.Chip
import com.isaiahgraham.leanrrr.ui.components.LeanrRow
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.components.OptionalNumberField
import com.isaiahgraham.leanrrr.ui.components.StatField
import com.isaiahgraham.leanrrr.ui.theme.BebasNeue
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import kotlin.random.Random

private const val SPIN_MILLIS = 4000
private const val TURNS = 6
/** A moment to see the slice under the pointer, before the list moves to the order. */
private const val HOLD_MILLIS = 700L

/** Takeaway roulette (RouletteView.swift): spin a wheel of restaurants and it picks a dinner that fits what's left today. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun RouletteScreen(onBack: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    val haptics = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    val dietRaw by rememberStringPref(DietFilter.STORAGE_KEY, "")
    /** Restaurants chosen for the wheel, kept between visits. None chosen is every restaurant. */
    var chosenRaw by rememberStringPref(Roulette.STORAGE_KEY, "")
    var query by remember { mutableStateOf(FindQuery(calories = 0.0, protein = 0.0, customise = false)) }
    var fields by remember { mutableIntStateOf(0) }
    var slices by remember { mutableStateOf(emptyList<Roulette.Slice>()) }
    var ready by remember { mutableStateOf(false) }
    val angle = remember { Animatable(0f) }
    var spinning by remember { mutableStateOf(false) }
    var winner by remember { mutableStateOf<MealMatch?>(null) }
    /** The order last landed on, which stays after `winner` clears, so a new spin can go elsewhere. */
    var last by remember { mutableStateOf<MealMatch?>(null) }
    var dietOpen by remember { mutableStateOf(false) }
    var order by remember { mutableStateOf<MealMatch?>(null) }

    /** The menus' restaurants only, since your own foods aren't a restaurant to go to. */
    val chains = store.catalog.chains.filter { it.id != "mine" && it.id !in Roulette.notDinner }
    val loggedToday = store.data.logs[dayKey(Instant.now())]?.size ?: 0
    val chosen = chosenRaw.split(",").filter { it.isNotEmpty() }.toSet().intersect(chains.map { it.id }.toSet())
    // Places out of reach come from the Map; without it every restaurant counts as in reach.
    val onWheel = Roulette.onWheel(chains.map { it.id }, chosen, emptySet())
    val held = spinning || winner != null

    /** Sets the limits from what's left today, on opening and after anything is logged. */
    LaunchedEffect(loggedToday) {
        val diet = DietFilter.fromRaw(dietRaw)
        query = Roulette.limits(store.data, store.goals, diet) ?: FindQuery(calories = 0.0, protein = 0.0, customise = false, diet = diet)
        winner = null; fields++
    }
    LaunchedEffect(dietRaw) { query = query.copy(diet = DietFilter.fromRaw(dietRaw)) }
    LaunchedEffect(query, chosenRaw) { if (!spinning) winner = null }
    LaunchedEffect(query, onWheel, store.catalog.foods.size, held) {
        if (held) return@LaunchedEffect
        // Empty chains in a query means every restaurant, so a wheel with none on it is settled here.
        if (onWheel.isEmpty()) { slices = emptyList(); ready = true; return@LaunchedEffect }
        delay(150)
        val request = query.copy(chains = onWheel)
        val foods = store.catalog.foods
        slices = withContext(Dispatchers.Default) { val s = this; Roulette.slices(foods, request) { !s.isActive } }
        ready = true
    }
    // A tap on the selection haptic for each slice that passes the pointer.
    val under by remember { derivedStateOf { Roulette.sliceAt(angle.value.toDouble(), slices.size) } }
    LaunchedEffect(under) { if (spinning) haptics.performHapticFeedback(HapticFeedbackType.SegmentTick) }

    fun land(pick: MealMatch) {
        spinning = false
        winner = pick
        haptics.performHapticFeedback(HapticFeedbackType.Confirm)
    }
    fun spin() {
        if (spinning) return
        val (slice, pick) = Roulette.spin(slices, last) ?: return
        // Lands anywhere on the slice but its edges, so the pointer never sits on the line between two.
        val stop = Roulette.landing(angle.value.toDouble(), slice, slices.size, TURNS, Random.nextDouble(-0.35, 0.35))
        last = pick
        winner = null
        spinning = true
        scope.launch {
            angle.animateTo(stop.toFloat(), tween(SPIN_MILLIS, easing = CubicBezierEasing(0.12f, 0.7f, 0.12f, 1f)))
            delay(HOLD_MILLIS)
            land(pick)
        }
    }
    ShakeDetector { if (order == null && !dietOpen) spin() }

    if (dietOpen) { DietNeedsScreen(onBack = { dietOpen = false }); return }
    order?.let { OrderDetailScreen(it, onBack = { order = null }); return }
    BackHandler(onBack = onBack)

    val summary = buildList {
        add("Up to ${query.calories.number} Cal"); add("at least ${query.protein.number} g protein")
        query.carbs?.let { add("${it.number} g carbs") }
        query.fat?.let { add("${it.number} g fat") }
    }.joinToString(" · ")
    val landed = slices.map { it.chain }.toSet()
    val noneFit = if (ready && !spinning) chains.filter { it.id in chosen && it.id !in landed }.map { it.name } else emptyList()

    LeanrScreen("Takeaway roulette", onBack = onBack, bottomBar = {
        ActionBar {
            ProminentButton(if (spinning) "Spinning…" else if (winner == null) "Spin" else "Spin again", Modifier.weight(1f), enabled = !spinning && slices.isNotEmpty()) { spin() }
        }
    }) {
        item {
            if (ready && slices.isEmpty()) {
                LeanrSection {
                    EmptyState("No dinners fit", if (query.calories > 0) "Try more calories, less protein or more restaurants."
                        else "Today's calories are used up. Raise the limit below to spin anyway.", Icons.Filled.Restaurant)
                }
            } else {
                Column(Modifier.fillMaxWidth().padding(bottom = 20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(summary, style = LeanrType.subheadline, color = c.text, textAlign = TextAlign.Center)
                    Box(Modifier.widthIn(max = 340.dp).fillMaxWidth().aspectRatio(1f)
                        .clickable(remember { MutableInteractionSource() }, null) { spin() }
                        .semantics { contentDescription = "Wheel of ${slices.size} restaurant${if (slices.size == 1) "" else "s"}" }) {
                        RouletteWheel(angle.value, slices.map { store.chainName(it.chain) })
                    }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.Vibration, null, tint = c.secondaryText, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Shake your phone to spin, or tap the wheel", style = LeanrType.subheadline, color = c.secondaryText)
                    }
                }
            }
        }
        winner?.let { w ->
            item(key = "winner:" + w.id) {
                LeanrSection("Tonight's dinner") { OrderMatchCard(w, query.protein, MealTime.DINNER, onOpen = { order = w }) }
            }
        }
        item {
            Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 6.dp)) {
                Text("RESTAURANTS", style = LeanrType.footnote, color = c.secondaryText, modifier = Modifier.weight(1f))
                if (chosen.isNotEmpty()) Text("${chosen.size} of ${chains.size} on the wheel", style = LeanrType.footnote, color = c.secondaryText)
            }
            // Every restaurant in view at once, so choosing a few takes a tap each and no scrolling.
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Chip("All", chosen.isEmpty()) { if (!spinning) chosenRaw = "" }
                chains.forEach { chain ->
                    Chip(chain.name, chain.id in chosen) {
                        if (!spinning) chosenRaw = (if (chain.id in chosen) chosen - chain.id else chosen + chain.id).sorted().joinToString(",")
                    }
                }
            }
            Column(Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp, bottom = 20.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(if (chosen.isEmpty()) "Every restaurant is on the wheel. Choose some to spin between just those."
                    else "Only the restaurants you choose are on the wheel, and they stay chosen next time.", style = LeanrType.footnote, color = c.secondaryText)
                if (noneFit.isNotEmpty()) Text("Nothing at ${orList(noneFit)} fits these limits.", style = LeanrType.footnote, color = c.secondaryText)
            }
        }
        item {
            LeanrSection("Limits for tonight", footer = "Starts from what's left today, up to one and a half typical meals. Limits leave out items with missing values.") {
                key(fields) {
                    Row(Modifier.padding(16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        StatField("Calories up to", "Cal", query.calories, { if (!spinning) query = query.copy(calories = it) }, Modifier.weight(1f))
                        StatField("Protein at least", "g", query.protein, { if (!spinning) query = query.copy(protein = it) }, Modifier.weight(1f))
                    }
                    OptionalNumberField("Carbs up to (g)", query.carbs, { if (!spinning) query = query.copy(carbs = it) })
                    OptionalNumberField("Fat up to (g)", query.fat, { if (!spinning) query = query.copy(fat = it) })
                }
                LeanrRow("Dietary needs", leading = { Icon(Icons.Filled.Eco, null, tint = c.accent) }, divider = false, onClick = { if (!spinning) dietOpen = true }, trailing = {
                    Text(if (query.diet.isEmpty) "None" else query.diet.summary, style = LeanrType.subheadline, color = c.secondaryText, maxLines = 2)
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = c.tertiaryText)
                })
            }
        }
    }
}

/** "KFC, Nando's or Subway". */
private fun orList(names: List<String>): String = when (names.size) {
    0 -> ""; 1 -> names[0]; 2 -> "${names[0]} or ${names[1]}"
    else -> names.dropLast(1).joinToString(", ") + " or " + names.last()
}

private val board = Color(0xFFE3C496)
private val paper = Color(0xFFF7F2E3)
private val boardInk = Color(0xFF664F33)

/** The wheel, turned to `angle`, with the pointer at the top. The app colour takes turns with the timber. */
@Composable
private fun RouletteWheel(angle: Float, names: List<String>) {
    val c = Leanr.colours
    val measurer = rememberTextMeasurer()
    val accentInk = if (c.accent.luminance() <= 0.24f) Color.White else boardInk
    val pointer = c.text
    val hub = c.card
    Canvas(Modifier.fillMaxWidth().aspectRatio(1f)) {
        val side = size.minDimension
        val radius = side / 2 - 6.dp.toPx()
        val centre = Offset(size.width / 2, size.height / 2)
        val count = names.size.coerceAtLeast(1)
        val sweep = 360f / count
        // An odd number of slices ends on paper, so the same colours never meet at the top.
        fun isPaper(i: Int) = names.size % 2 == 1 && i == names.size - 1
        rotate(angle, centre) {
            names.forEachIndexed { i, name ->
                val fill = if (isPaper(i)) paper else if (i % 2 == 0) c.accent else board
                drawArc(fill, i * sweep - 90f, sweep, true, Offset(centre.x - radius, centre.y - radius), Size(radius * 2, radius * 2))
                val ink = if (i % 2 == 0 && !isPaper(i)) accentInk else boardInk
                val style = TextStyle(fontFamily = BebasNeue, fontSize = (side * (if (names.size > 12) 0.05f else 0.058f) / density).sp, color = ink, textAlign = TextAlign.End)
                val width = (radius * 0.68f).toInt().coerceAtLeast(1)
                val layout = measurer.measure(name.uppercase(), style, overflow = TextOverflow.Ellipsis, maxLines = 1, constraints = Constraints(minWidth = width, maxWidth = width))
                // Read from the rim in, along the middle of the slice.
                rotate((i + 0.5f) * sweep - 90f, centre) {
                    translate(centre.x + radius * 0.92f - width, centre.y - layout.size.height / 2f) { drawText(layout) }
                }
            }
            drawCircle(boardInk.copy(alpha = 0.25f), radius, centre, style = Stroke(1.dp.toPx()))
        }
        drawCircle(hub, side * 0.08f, centre)
        // The pointer, tip down.
        val path = Path().apply {
            moveTo(centre.x - 11.dp.toPx(), 0f); lineTo(centre.x + 11.dp.toPx(), 0f); lineTo(centre.x, 22.dp.toPx()); close()
        }
        drawPath(path, pointer)
    }
}
