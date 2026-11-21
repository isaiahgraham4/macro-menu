package com.isaiahgraham.leanrrr.ui.components

import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.Moment
import com.isaiahgraham.leanrrr.data.WeightGoal
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.feature.progress.MomentShareSheet
import com.isaiahgraham.leanrrr.feature.progress.WeeklyReviewScreen
import com.isaiahgraham.leanrrr.feature.progress.YearReview
import com.isaiahgraham.leanrrr.feature.progress.YearReviewScreen
import com.isaiahgraham.leanrrr.feature.progress.symbolIcon
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrBackground
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlinx.coroutines.delay
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.sin
import kotlin.random.Random

// A port of the overlay in Celebration.swift: what's in `store.moments`, shown over the app one at a time.

private const val WAIT_MS = 1100L
private const val GAP_MS = 400L
private const val CARD_MS = 3000L
private const val CONFETTI_SECONDS = 3.5

/** The timber of the cutting board the cards sit on, and the ink written on it. */
private val boardWood = Color(0.89f, 0.77f, 0.59f)
private val boardInk = Color(0.23f, 0.17f, 0.10f)
private val boardGrain = Color(0.6f, 0.4f, 0.2f)

/**
 * Shows what's in `store.moments` over the app, one at a time, once the launch has settled. They wait a beat, so a sheet can
 * close first. The goal weight fills the screen; everything else is a card that leaves by itself. Also shows the weekly
 * review when `nav.showWeeklyReview` is set, and the year's review from its card.
 */
@Composable
fun MomentsOverlay() {
    val store = AppServices.store
    val nav = AppServices.nav
    val haptics = LocalHapticFeedback.current
    var showing by remember { mutableStateOf<Moment?>(null) }
    var sharing by remember { mutableStateOf<Moment?>(null) }
    var yearReview by remember { mutableStateOf<YearReview?>(null) }
    var following by remember { mutableStateOf(false) }
    val next = store.moments.firstOrNull()

    fun finish() {
        showing = null
        following = true
        if (store.moments.isNotEmpty()) store.moments.removeAt(0)
    }

    LaunchedEffect(next, store.launchSettled) {
        if (next == null || !store.launchSettled) return@LaunchedEffect
        delay(if (following) GAP_MS else WAIT_MS)
        showing = next
        haptics.performHapticFeedback(HapticFeedbackType.Confirm)
        if (next is Moment.GoalReached) return@LaunchedEffect
        delay(CARD_MS)
        if (sharing == null) finish()
    }
    LaunchedEffect(store.moments.isEmpty()) { if (store.moments.isEmpty()) { showing = null; following = false } }

    val current = showing
    // The card keeps its words while it slides away.
    var lastCard by remember { mutableStateOf<Moment?>(null) }
    if (current != null && current !is Moment.GoalReached) lastCard = current
    var lastGoal by remember { mutableStateOf<WeightGoal?>(null) }
    if (current is Moment.GoalReached) lastGoal = current.goal
    Box(Modifier.fillMaxSize()) {
        if (current != null && current !is Moment.GoalReached) Confetti(count = 60, power = 700.0, originY = 0.78f)
        AnimatedVisibility(current != null && current !is Moment.GoalReached, Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(bottom = 80.dp),
            enter = slideInVertically(spring(dampingRatio = 0.8f)) { it } + fadeIn(), exit = slideOutVertically { it } + fadeOut()) {
            val moment = lastCard ?: return@AnimatedVisibility
            MomentCard(moment, dismiss = ::finish, open = {
                finish()
                if (moment is Moment.Year) yearReview = YearReview.make(store.data, moment.year, store.catalog.chains.map { it.id }.toSet())
                else nav.showWeeklyReview = true
            }, share = { sharing = moment })
        }
        AnimatedVisibility(current is Moment.GoalReached, enter = fadeIn(), exit = fadeOut()) {
            val goal = lastGoal ?: return@AnimatedVisibility
            GoalReachedView(goal, done = ::finish, share = { sharing = Moment.GoalReached(goal) })
        }
    }
    sharing?.let { moment -> MomentShareSheet(moment) { sharing = null; if (showing !is Moment.GoalReached) finish() } }
    if (nav.showWeeklyReview) {
        BackHandler { nav.showWeeklyReview = false }
        LeanrBackground(Modifier.clickable(remember { MutableInteractionSource() }, null) {}) { WeeklyReviewScreen(onBack = { nav.showWeeklyReview = false }) }
    }
    yearReview?.let { YearReviewScreen(it) { yearReview = null } }
}

/** True when the person has turned animations off (Reduce Motion on iOS). */
@Composable
private fun reduceMotion(): Boolean {
    val context = LocalContext.current
    return remember { Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }
}

/** A small cutting board: flat timber with fine grain and an inset line (CuttingBoard in LeanrOnboarding.swift, without the gradient). */
@Composable
private fun BoxScope.CuttingBoard(corner: Int = 28) {
    Canvas(Modifier.matchParentSize().clip(RoundedCornerShape(corner.dp))) {
        drawRect(boardWood)
        for (line in 0 until 32) {
            val y = line * size.height / 31
            val path = Path().apply {
                moveTo(0f, y)
                cubicTo(size.width * 0.3f, y - 9, size.width * 0.7f, y + 12, size.width, y + 6)
            }
            drawPath(path, boardGrain.copy(alpha = if (line % 3 == 0) 0.13f else 0.06f), style = Stroke(1f))
        }
        val inset = 7.dp.toPx()
        drawRoundRect(boardGrain.copy(alpha = 0.18f), Offset(inset, inset), Size(size.width - inset * 2, size.height - inset * 2),
            androidx.compose.ui.geometry.CornerRadius((corner - 6).dp.toPx()), style = Stroke(1.dp.toPx()))
    }
}

/** A number that counts up from zero to `value` in steps of `step`. */
@Composable
private fun countUp(value: Double, step: Double, millis: Int): Double {
    val still = reduceMotion()
    var started by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { started = true }
    val shown by animateFloatAsState(if (started || still) value.toFloat() else 0f, tween(if (still) 0 else millis), label = "count")
    return floor(shown / step + 1e-6) * step
}

/** A target, milestone or weigh-in on a small cutting board that rises from the bottom of the screen. */
@Composable
private fun MomentCard(moment: Moment, dismiss: () -> Unit, open: () -> Unit, share: () -> Unit) {
    val c = Leanr.colours
    val copy = moment.copy
    var appeared by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { appeared = true }
    val progress by animateFloatAsState(if (appeared) (copy.progress ?: 0.0).toFloat() else 0f, tween(if (reduceMotion()) 0 else 1000), label = "progress")
    Box(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 92.dp), contentAlignment = Alignment.BottomCenter) {
        Box(Modifier.widthIn(max = 420.dp).fillMaxWidth().clickable(onClick = if (moment.opensReview) open else dismiss)
            .semantics { liveRegion = LiveRegionMode.Polite }) {
            CuttingBoard()
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(symbolIcon(copy.icon), null, tint = c.accent, modifier = Modifier.size(32.dp))
                    Spacer(Modifier.width(14.dp))
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        val figure = copy.figure
                        if (figure != null) {
                            Text(copy.title, style = LeanrType.subheadline.copy(fontWeight = FontWeight.Medium), color = boardInk)
                            Text("${countUp(figure.value, figure.step, 1000).number} ${figure.unit}", style = LeanrType.roboto(28f, FontWeight.Bold), color = boardInk)
                        } else {
                            Text(copy.title, style = LeanrType.title2Display, color = boardInk)
                        }
                        Text(copy.detail, style = LeanrType.subheadline, color = boardInk)
                    }
                    if (copy.shareable) IconButton(onClick = share) { Icon(Icons.Filled.Share, "Share as an image", tint = c.accent) }
                }
                if (copy.progress != null) {
                    Box(Modifier.fillMaxWidth().height(6.dp).clip(CircleShape).background(boardInk.copy(alpha = 0.14f))) {
                        Box(Modifier.fillMaxWidth(progress.coerceIn(0f, 1f)).height(6.dp).clip(CircleShape).background(c.accent))
                    }
                }
            }
        }
    }
}

/** Leanrrr's one big moment: the first time a weigh-in takes your trend to your goal weight. */
@Composable
private fun GoalReachedView(goal: WeightGoal, done: () -> Unit, share: () -> Unit) {
    val c = Leanr.colours
    val change = abs(goal.startKg - goal.kg)
    var appeared by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { appeared = true }
    val scale by animateFloatAsState(if (appeared || reduceMotion()) 1f else 0.9f, spring(dampingRatio = 0.6f), label = "scale")
    BackHandler(onBack = done)
    LeanrBackground(Modifier.clickable(remember { MutableInteractionSource() }, null) {}) {
        Column(Modifier.align(Alignment.Center).widthIn(max = 420.dp).padding(horizontal = 24.dp).scale(scale), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Box(Modifier.fillMaxWidth().semantics { liveRegion = LiveRegionMode.Assertive }) {
                CuttingBoard()
                Column(Modifier.fillMaxWidth().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(symbolIcon("party.popper.fill"), null, tint = c.accent, modifier = Modifier.size(56.dp))
                    Text("Goal reached", style = LeanrType.largeTitle, color = boardInk)
                    Text("${countUp(change, 0.1, 1200).number} kg", style = LeanrType.roboto(34f, FontWeight.Bold), color = boardInk)
                    Text("${if (goal.kg < goal.startKg) "lost" else "gained"} since you started at ${goal.startKg.number} kg. You're at ${goal.kg.number} kg.",
                        style = LeanrType.headline, color = boardInk, textAlign = TextAlign.Center)
                }
            }
            Button(onClick = share, colors = ButtonDefaults.buttonColors(containerColor = c.accent, contentColor = if (c.dark) Color.Black else Color.White),
                shape = RoundedCornerShape(14.dp), modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)) {
                Icon(Icons.Filled.Share, null); Spacer(Modifier.width(8.dp)); Text("Share as an image", style = LeanrType.headline)
            }
            OutlinedButton(onClick = done, shape = RoundedCornerShape(14.dp), modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)) {
                Text("Done", style = LeanrType.headline, color = c.accent)
            }
        }
        Confetti(count = 150, power = 1300.0, originY = 0.4f)
    }
}

private class Piece(random: Random) {
    val angle = random.nextDouble(0.0, 2 * Math.PI)
    val speed = random.nextDouble(0.15, 1.0)
    val spin = random.nextDouble(-9.0, 9.0)
    val flutter = random.nextDouble(4.0, 11.0)
    val drift = random.nextDouble(-24.0, 24.0)
    val width = random.nextDouble(5.0, 8.0).toFloat()
    val height = random.nextDouble(8.0, 13.0).toFloat()
    val colour = random.nextInt(4)
}

/** Paper flecks thrown up from one point, which drift down and fade. Nothing is drawn with animations turned off. */
@Composable
private fun Confetti(count: Int, power: Double, originY: Float) {
    if (reduceMotion()) return
    val c = Leanr.colours
    val colours = listOf(c.accent, Color(0.89f, 0.77f, 0.59f), Color(0.64f, 0.52f, 0.37f), if (c.dark) Color(0.97f, 0.95f, 0.89f) else c.accent.copy(alpha = 0.6f))
    val pieces = remember { val random = Random(System.nanoTime()); List(count) { Piece(random) } }
    var start by remember { mutableLongStateOf(0L) }
    var now by remember { mutableLongStateOf(0L) }
    LaunchedEffect(Unit) {
        start = withFrameNanos { it }
        while (true) { now = withFrameNanos { it }; if ((now - start) / 1e9 > CONFETTI_SECONDS) break }
    }
    val time = if (start == 0L) 0.0 else (now - start) / 1e9
    if (time > CONFETTI_SECONDS) return
    Canvas(Modifier.fillMaxSize()) {
        val d = density
        val drag = 3.2; val fall = 170.0
        val fromX = size.width / 2; val fromY = size.height * originY
        val alpha = ((CONFETTI_SECONDS - time) / 1.2).coerceIn(0.0, 1.0).toFloat()
        for (piece in pieces) {
            // Thrown out fast, slowed by the air, then falling steadily.
            val thrown = (1 - exp(-drag * time)) / drag * piece.speed * power
            val x = fromX + ((cos(piece.angle) * thrown + piece.drift * sin(time * 2)) * d).toFloat()
            val y = fromY + ((sin(piece.angle) * thrown + fall * time) * d).toFloat()
            translate(x, y) {
                rotate(Math.toDegrees(piece.spin * time).toFloat(), Offset.Zero) {
                    scale(1f, cos(piece.flutter * time).toFloat(), Offset.Zero) {
                        drawRect(colours[piece.colour % colours.size].copy(alpha = alpha), Offset(-piece.width * d / 2, -piece.height * d / 2), Size(piece.width * d, piece.height * d))
                    }
                }
            }
        }
    }
}
