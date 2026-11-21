package com.isaiahgraham.leanrrr.feature.today

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.AppData
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.dayKey
import com.isaiahgraham.leanrrr.data.nutrientNames
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Spreadsheet exports of the food log (LogExport.swift). Missing figures stay blank rather than zero, so a total is never passed off as complete. */
object LogExport {
    /** One row per food logged. */
    fun items(data: AppData, chainName: (String) -> String): String {
        val extras = nutrientNames.drop(4)
        val rows = mutableListOf(
            listOf("Date", "Time", "Meal time", "Meal", "Food", "Restaurant", "Serving", "Quantity", "Calories", "kJ", "Protein (g)", "Carbs (g)", "Fat (g)") +
                extras.map { "${it.label} (${it.unit})" },
        )
        for (day in data.logs.keys.sorted()) {
            for (entry in (data.logs[day] ?: emptyList()).sortedBy { it.time }) {
                for (item in entry.items) {
                    val food = item.food; val q = item.quantity
                    rows += listOf(
                        day, time(entry.time), entry.mealTime?.title ?: "", entry.name, food.name, chainName(food.chain), food.serve, number(q, 2),
                        number(food.cal * q), number(food.kj * q), number(food.p * q), number(food.c?.let { it * q }), number(food.f?.let { it * q }),
                    ) + extras.map { n -> number(food.nut?.get(n.key)?.let { it * q }) }
                }
            }
        }
        return csv(rows)
    }

    /** One row per logged day, with that day's targets. "Incomplete" names totals where some foods had no figure. */
    fun days(data: AppData): String {
        val keys = nutrientNames.map { it.key }
        val rows = mutableListOf(
            listOf("Date", "Meals") + nutrientNames.map { "${it.label} (${it.unit})" } + listOf("Incomplete") +
                nutrientNames.map { "${it.label} target (${it.unit})" },
        )
        val current = data.goalSets.firstOrNull { it.id == data.activeGoal } ?: data.goalSets.firstOrNull()
        for (day in data.logs.keys.sorted()) {
            val entries = data.logs[day] ?: emptyList()
            if (entries.isEmpty()) continue
            val items = entries.flatMap { it.items }
            val total = Nutrition(items)
            // Blank when no food that day listed the figure; a 0 would read as a real total.
            fun listed(key: String): Boolean = when (key) {
                "cal", "p" -> true
                "c" -> items.any { it.food.c != null }
                "f" -> items.any { it.food.f != null }
                else -> total.nut[key] != null
            }
            val incomplete = nutrientNames.filter { total.isPartial(it.key) }.joinToString("; ") { it.label }
            val goals = data.dayGoals[day] ?: current
            rows += listOf(day, entries.size.toString()) + keys.map { if (listed(it)) number(total.value(it)) else "" } +
                listOf(incomplete) + keys.map { number(goals?.values?.get(it)) }
        }
        return csv(rows)
    }

    fun csv(rows: List<List<String>>): String = rows.joinToString("\r\n") { row -> row.joinToString(",") { field(it) } } + "\r\n"

    /** Quotes a field when needed. Text that a spreadsheet would run as a formula gets a leading apostrophe. */
    fun field(value: String): String {
        var text = value
        val first = text.firstOrNull()
        if (first != null && first in "=+-@\t\r" && text.toDoubleOrNull() == null) text = "'$text"
        if (text.none { it in ",\"\r\n" }) return text
        return "\"" + text.replace("\"", "\"\"") + "\""
    }

    private fun number(value: Double?, places: Int = 1): String {
        if (value == null || !value.isFinite()) return ""
        val format = DecimalFormat(if (places == 2) "0.##" else "0.#", DecimalFormatSymbols(Locale.US))
        return format.format(if (value == -0.0) 0.0 else value)
    }

    private val clock = DateTimeFormatter.ofPattern("HH:mm", Locale.US)
    private fun time(date: Instant): String = date.atZone(ZoneId.systemDefault()).format(clock)

    /** The file names the iOS app gives the two exports. */
    fun itemsFileName(): String = "Leanrrr food log ${dayKey(Instant.now())}.csv"
    fun daysFileName(): String = "Leanrrr daily totals ${dayKey(Instant.now())}.csv"

    /** Writes a CSV to a document the person picked (Storage Access Framework). */
    fun write(context: Context, uri: Uri, text: String): Boolean = runCatching {
        context.contentResolver.openOutputStream(uri, "wt")?.use { it.write(text.toByteArray(Charsets.UTF_8)) } != null
    }.getOrDefault(false)

    /** Hands a CSV to the share sheet as text, for apps that take it that way (no file provider needed). */
    fun share(context: Context, text: String, title: String) {
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/csv"
            putExtra(Intent.EXTRA_SUBJECT, title)
            putExtra(Intent.EXTRA_TEXT, text)
        }
        context.startActivity(Intent.createChooser(send, title).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}

/**
 * A "Save as CSV" launcher for My foods and Settings: `export(LogExport.items(...), LogExport.itemsFileName())` asks where to
 * save the file, then writes it and shows a notice.
 */
@Composable
fun rememberCsvExporter(): (text: String, fileName: String) -> Unit {
    val context = LocalContext.current
    var pending by remember { mutableStateOf<String?>(null) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("text/csv")) { uri ->
        val text = pending
        pending = null
        if (uri != null && text != null) {
            val store = AppServices.store
            if (LogExport.write(context, uri, text)) store.notice = "Exported" else store.refuse("Couldn’t save the file")
        }
    }
    return { text, fileName -> pending = text; launcher.launch(fileName) }
}
