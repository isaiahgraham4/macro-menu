package com.isaiahgraham.leanrrr.feature.progress

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.isaiahgraham.leanrrr.data.kgText
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.Roboto
import java.time.LocalDate
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.pow

// The Progress graphs, drawn with Compose Canvas (Swift Charts on iOS).

/** One bar: its day, and nothing drawn when `value` is null. */
data class ChartBar(val key: String, val date: LocalDate, val value: Double?, val colour: Color, val alpha: Float = 1f)

/** A horizontal line across the chart: a target (dashed) or an average (solid), with an optional label above its right end. */
data class ChartRule(val value: Double, val colour: Color, val dashed: Boolean, val width: Dp = 1.dp, val label: String? = null)

private fun niceStep(range: Double, ticks: Int = 4): Double {
    if (range <= 0) return 1.0
    val raw = range / ticks
    val magnitude = 10.0.pow(floor(log10(raw)))
    val residual = raw / magnitude
    return magnitude * when { residual > 5 -> 10.0; residual > 2 -> 5.0; residual > 1 -> 2.0; else -> 1.0 }
}

private fun axisText(value: Double): String = if (value >= 1000) "${(value / 1000).number}k" else value.number

private fun DrawScope.label(measurer: TextMeasurer, text: String, x: Float, y: Float, style: TextStyle, alignRight: Boolean = false, centre: Boolean = false) {
    val layout = measurer.measure(text, style)
    val left = when { alignRight -> x - layout.size.width; centre -> x - layout.size.width / 2f; else -> x }
    drawText(layout, topLeft = Offset(left.coerceIn(0f, max(0f, size.width - layout.size.width)), y))
}

/**
 * Bars per day with rules across them, a value axis on the left and a few day labels along the bottom. A tap or drag picks
 * the day under the finger (`chartXSelection`), and lifting the finger keeps it chosen.
 */
@Composable
fun BarChart(bars: List<ChartBar>, rules: List<ChartRule>, description: String, modifier: Modifier = Modifier, height: Dp = 190.dp,
             selected: String? = null, onSelect: ((String?) -> Unit)? = null) {
    val c = Leanr.colours
    val measurer = rememberTextMeasurer()
    val axisStyle = TextStyle(fontFamily = Roboto, fontSize = 10.sp, color = c.secondaryText)
    val grid = c.text.copy(alpha = 0.08f)
    val axisWidth = 34.dp
    fun index(x: Float, width: Float, left: Float): Int? {
        if (bars.isEmpty()) return null
        val slot = (width - left) / bars.size
        return ((x - left) / slot).toInt().coerceIn(0, bars.size - 1)
    }
    var gestures = Modifier.semantics { contentDescription = description }
    if (onSelect != null) {
        gestures = gestures.pointerInput(bars) {
            detectTapGestures { offset ->
                val i = index(offset.x, size.width.toFloat(), axisWidth.toPx())
                onSelect(i?.let { bars[it].key }?.takeIf { it != selected })
            }
        }.pointerInput(bars) {
            detectDragGestures { change, _ -> index(change.position.x, size.width.toFloat(), axisWidth.toPx())?.let { onSelect(bars[it].key) } }
        }
    }
    Canvas(modifier.fillMaxWidth().height(height).padding(vertical = 8.dp).then(gestures)) {
        val left = axisWidth.toPx(); val bottomLabels = 16.dp.toPx(); val top = 12.dp.toPx()
        val plotHeight = size.height - bottomLabels - top
        val highest = (bars.mapNotNull { it.value } + rules.map { it.value }).maxOrNull() ?: 1.0
        val step = niceStep(highest * 1.05)
        val ceiling = max(step, ceil(highest * 1.05 / step) * step)
        fun y(v: Double) = top + plotHeight * (1 - (v / ceiling)).toFloat()
        var tick = 0.0
        while (tick <= ceiling + 0.001) {
            drawLine(grid, Offset(left, y(tick)), Offset(size.width, y(tick)), 1f)
            label(measurer, axisText(tick), 0f, y(tick) - 6.sp.toPx(), axisStyle)
            tick += step
        }
        val slot = (size.width - left) / max(1, bars.size)
        val barWidth = max(1f, slot * 0.7f)
        bars.forEachIndexed { i, bar ->
            val value = bar.value ?: return@forEachIndexed
            val x = left + slot * i + (slot - barWidth) / 2
            val dim = if (selected == null || selected == bar.key) 1f else 0.5f
            drawRoundRect(bar.colour.copy(alpha = bar.colour.alpha * bar.alpha * dim), Offset(x, y(value)), Size(barWidth, y(0.0) - y(value)),
                CornerRadius(minOf(3.dp.toPx(), barWidth / 2)))
        }
        for (rule in rules) {
            val effect = if (rule.dashed) PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 3.dp.toPx())) else null
            drawLine(rule.colour, Offset(left, y(rule.value)), Offset(size.width, y(rule.value)), rule.width.toPx(), pathEffect = effect)
            rule.label?.let { label(measurer, it, size.width, y(rule.value) - 14.sp.toPx(), axisStyle, alignRight = true) }
        }
        if (bars.isNotEmpty()) {
            val marks = if (bars.size <= 7) bars.indices.toList() else listOf(0, bars.size / 2, bars.size - 1)
            for (i in marks) {
                val text = if (bars.size <= 7) bars[i].date.dayOfWeek.getDisplayName(java.time.format.TextStyle.SHORT, java.util.Locale.getDefault())
                    else shortDay(bars[i].date)
                label(measurer, text, left + slot * i + slot / 2, size.height - bottomLabels + 2.dp.toPx(), axisStyle, centre = true)
            }
        }
    }
}

/** The last few weigh-ins as dots joined in order, each spaced evenly and labelled with its weight and day. */
@Composable
fun WeighInChart(points: List<WeightTrend.Point>, modifier: Modifier = Modifier, height: Dp = 200.dp) {
    val c = Leanr.colours
    val measurer = rememberTextMeasurer()
    val small = TextStyle(fontFamily = Roboto, fontSize = 11.sp, color = c.secondaryText)
    val values = points.map { it.kg }
    val low = floor((values.minOrNull() ?: 0.0) - 1); val high = ceil((values.maxOrNull() ?: 1.0) + 1)
    val description = "Last ${points.size} weigh-ins" + (points.lastOrNull()?.let { ", most recent ${it.kg.kgText} kg" } ?: "")
    Canvas(modifier.fillMaxWidth().height(height).padding(vertical = 8.dp).semantics { contentDescription = description }) {
        val left = 30.dp.toPx(); val top = 22.dp.toPx(); val bottom = 18.dp.toPx()
        val plotHeight = size.height - top - bottom
        fun y(v: Double) = top + plotHeight * (1 - ((v - low) / (high - low))).toFloat()
        val step = niceStep(high - low, 3)
        var tick = ceil(low / step) * step
        while (tick <= high + 0.001) {
            drawLine(c.text.copy(alpha = 0.08f), Offset(left, y(tick)), Offset(size.width, y(tick)), 1f)
            label(measurer, tick.number, 0f, y(tick) - 6.sp.toPx(), small)
            tick += step
        }
        if (points.isEmpty()) return@Canvas
        val slot = (size.width - left) / points.size
        fun x(i: Int) = left + slot * i + slot / 2
        val path = Path()
        points.forEachIndexed { i, p -> if (i == 0) path.moveTo(x(i), y(p.kg)) else path.lineTo(x(i), y(p.kg)) }
        drawPath(path, c.accent, style = Stroke(2.dp.toPx()))
        points.forEachIndexed { i, p ->
            drawCircle(c.accent, 4.5.dp.toPx(), Offset(x(i), y(p.kg)))
            label(measurer, p.kg.kgText, x(i), y(p.kg) - 20.dp.toPx(), small, centre = true)
            label(measurer, shortDay(p.date), x(i), size.height - bottom + 3.dp.toPx(), small, centre = true)
        }
    }
}

/** Readings over time: a line through dated points, spaced by date (the measurement graph). */
@Composable
fun DatedLineChart(points: List<Pair<LocalDate, Double>>, description: String, modifier: Modifier = Modifier, height: Dp = 200.dp, padding: Double = 2.0) {
    val c = Leanr.colours
    val measurer = rememberTextMeasurer()
    val small = TextStyle(fontFamily = Roboto, fontSize = 11.sp, color = c.secondaryText)
    val values = points.map { it.second }
    val low = floor((values.minOrNull() ?: 0.0) - padding); val high = ceil((values.maxOrNull() ?: 1.0) + padding)
    Canvas(modifier.fillMaxWidth().height(height).padding(vertical = 8.dp).semantics { contentDescription = description }) {
        val left = 30.dp.toPx(); val top = 10.dp.toPx(); val bottom = 18.dp.toPx(); val right = 12.dp.toPx()
        val plotHeight = size.height - top - bottom
        fun y(v: Double) = top + plotHeight * (1 - ((v - low) / (high - low))).toFloat()
        val step = niceStep(high - low, 3)
        var tick = ceil(low / step) * step
        while (tick <= high + 0.001) {
            drawLine(c.text.copy(alpha = 0.08f), Offset(left, y(tick)), Offset(size.width, y(tick)), 1f)
            label(measurer, tick.number, 0f, y(tick) - 6.sp.toPx(), small)
            tick += step
        }
        if (points.isEmpty()) return@Canvas
        val first = points.first().first.toEpochDay(); val span = max(1L, points.last().first.toEpochDay() - first)
        fun x(d: LocalDate) = left + (size.width - left - right) * ((d.toEpochDay() - first).toFloat() / span)
        val path = Path()
        points.forEachIndexed { i, (d, v) -> if (i == 0) path.moveTo(x(d), y(v)) else path.lineTo(x(d), y(v)) }
        drawPath(path, c.accent, style = Stroke(2.dp.toPx()))
        points.forEach { (d, v) -> drawCircle(c.accent, 4.dp.toPx(), Offset(x(d), y(v))) }
        label(measurer, shortDay(points.first().first), left, size.height - bottom + 3.dp.toPx(), small)
        if (points.size > 1) label(measurer, shortDay(points.last().first), size.width, size.height - bottom + 3.dp.toPx(), small, alignRight = true)
    }
}
