package com.isaiahgraham.leanrrr.feature.settings

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.TableChart
import androidx.compose.material.icons.outlined.Upload
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.AppData
import com.isaiahgraham.leanrrr.data.AppStore
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.Goals
import com.isaiahgraham.leanrrr.data.MenuCatalog
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.SavedMeal
import com.isaiahgraham.leanrrr.data.dayKey
import com.isaiahgraham.leanrrr.data.newId
import com.isaiahgraham.leanrrr.data.nutrientNames
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.security.MessageDigest
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

private class BadBackup : Exception("The file is damaged or isn’t a Leanrrr backup.")

/** Backups from the Macro Menu web app (WebBackup.swift): foods, recipes, saved meals and target sets, without daily history. */
object WebBackup {
    /** A stable ID made from text, so importing the same web backup twice updates rather than duplicates. */
    fun identifier(text: String): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest(text.toByteArray()).take(16)
        val hex = bytes.joinToString("") { "%02X".format(it) }
        return "${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}"
    }

    private fun JsonObject.number(key: String): Double? = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.doubleOrNull
    private fun JsonObject.text(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
    private fun JsonObject.objects(key: String): List<JsonObject>? = (this[key] as? JsonArray)?.map { it as? JsonObject ?: throw BadBackup() }

    fun decode(text: String, catalog: MenuCatalog): AppData {
        val root = runCatching { Json.parseToJsonElement(text).jsonObject }.getOrNull() ?: throw BadBackup()
        if (root.text("app") != "macro-menu" || (root["v"] as? JsonPrimitive)?.intOrNull != 1) throw BadBackup()
        val foods = root.objects("foods") ?: throw BadBackup()

        fun food(row: JsonObject): Food {
            val name = row.text("name") ?: throw BadBackup()
            val cal = row.number("cal") ?: throw BadBackup()
            val protein = row.number("p") ?: throw BadBackup()
            val nut = (row["nut"] as? JsonObject)?.mapNotNull { (k, v) -> (v as? JsonPrimitive)?.doubleOrNull?.let { k to it } }?.toMap()?.toMutableMap()
            var result = Food(id = row.text("id") ?: newId(), name = name, kj = row.number("kj") ?: (cal * 4.184), cal = cal, p = protein,
                c = row.number("c"), f = row.number("f"), serve = row.text("serve") ?: "1 serving", nut = nut, price = row.number("price"))
            var extras = result.nut?.toMutableMap()
            for (extra in row.objects("other") ?: emptyList()) {
                val extraName = extra.text("name"); val value = extra.number("amt")
                if (extraName != null && value != null) {
                    if (extras == null) extras = mutableMapOf()
                    extras["$extraName (${extra.text("unit") ?: "mg"})"] = value
                }
            }
            result = result.copy(nut = extras)
            row.objects("ingredients")?.let { ingredients ->
                result = result.copy(ingredients = ingredients.map { Portion(food = food(it)) }, recipeYield = row.number("servings") ?: 1.0)
            }
            if (row.text("kind") == "order") result = result.copy(note = "Imported custom order. Nutrition is the saved snapshot from your web backup.")
            if (!result.isValid) throw BadBackup()
            return result
        }

        val imported = foods.map(::food)
        var goalSets = listOf(Goals(id = identifier("web-default-targets"), name = "Imported targets"))
        val all = catalog.foods + imported
        val meals = (root.objects("meals") ?: emptyList()).map { row ->
            val name = row.text("name") ?: throw BadBackup()
            val items = row.objects("items") ?: throw BadBackup()
            val portions = items.map { item ->
                val value = all.firstOrNull { it.id == item.text("id") } ?: throw BadBackup()
                Portion(food = value, quantity = item.number("qty") ?: 1.0)
            }
            SavedMeal(id = identifier(row.text("id") ?: name), name = name, items = portions)
        }
        root.objects("goalSets")?.takeIf { it.isNotEmpty() }?.let { sets ->
            goalSets = sets.map { row ->
                val values = row["goals"] as? JsonObject ?: JsonObject(emptyMap())
                var minimums = Goals().minimums
                (values["dir"] as? JsonObject)?.forEach { (key, dir) ->
                    minimums = if (dir.jsonPrimitive.contentOrNull == "min") minimums + key else minimums - key
                }
                Goals(id = identifier(row.text("id") ?: "web"), name = row.text("name") ?: "Imported targets",
                    values = nutrientNames.mapNotNull { n -> values.number(n.key)?.takeIf { it > 0 }?.let { n.key to it } }.toMap(),
                    minimums = minimums, mealCal = values.number("mealCal") ?: 500.0, mealProtein = values.number("mealP") ?: 40.0)
            }
        }
        val result = AppData(foods = imported, meals = meals, goalSets = goalSets)
        if (!result.isValid) throw BadBackup()
        return result
    }
}

/** The very first Leanrrr backup format (FoodBackup in FoodStore.swift): a version and a list of saved foods. */
private object LegacyBackup {
    fun decode(text: String, current: AppData): AppData? {
        val root = runCatching { Json.parseToJsonElement(text).jsonObject }.getOrNull() ?: return null
        if ((root["version"] as? JsonPrimitive)?.intOrNull != 1 || root.containsKey("goalSets")) return null
        val foods = runCatching {
            root["foods"]!!.jsonArray.map { element ->
                val row = element.jsonObject
                val calories = row["calories"]!!.jsonPrimitive.doubleOrNull!!
                Food(id = row["id"]!!.jsonPrimitive.content, name = row["name"]!!.jsonPrimitive.content, kj = calories * 4.184, cal = calories,
                    p = row["protein"]!!.jsonPrimitive.doubleOrNull!!, c = row["carbs"]?.jsonPrimitive?.doubleOrNull, f = row["fat"]?.jsonPrimitive?.doubleOrNull,
                    serve = row["serving"]?.jsonPrimitive?.contentOrNull ?: "1 serving")
            }
        }.getOrNull() ?: return null
        if (!foods.all { it.isValid } || foods.map { it.id }.toSet().size != foods.size) return null
        return AppData(foods = foods, goalSets = current.goalSets)
    }
}

/** Reads any backup Leanrrr understands: this app's or the iOS app's (the same format), the first format, or a Macro Menu web backup. */
fun AppStore.decodeAnyBackup(text: String): AppData {
    runCatching { return decodeBackup(text) }
    LegacyBackup.decode(text, data)?.let { return it }
    return WebBackup.decode(text, catalog)
}

/** Spreadsheet exports of the food log (LogExport.swift). Missing figures stay blank rather than zero. */
internal object CsvExport {
    private val timeFormat = DateTimeFormatter.ofPattern("HH:mm", Locale.US)

    private fun number(value: Double?, places: Int = 1): String {
        if (value == null || !value.isFinite()) return ""
        val text = String.format(Locale.US, "%.${places}f", value).trimEnd('0').trimEnd('.')
        return if (text == "-0") "0" else text
    }

    /** One row per food logged. */
    fun items(data: AppData, chainName: (String) -> String): String {
        val extras = nutrientNames.drop(4)
        val rows = mutableListOf(listOf("Date", "Time", "Meal time", "Meal", "Food", "Restaurant", "Serving", "Quantity", "Calories", "kJ", "Protein (g)", "Carbs (g)", "Fat (g)") +
            extras.map { "${it.label} (${it.unit})" })
        for (day in data.logs.keys.sorted()) {
            for (entry in (data.logs[day] ?: emptyList()).sortedBy { it.time }) {
                for (item in entry.items) {
                    val food = item.food; val q = item.quantity
                    rows += listOf(day, entry.time.atZone(ZoneId.systemDefault()).format(timeFormat), entry.mealTime?.title ?: "", entry.name, food.name,
                        chainName(food.chain), food.serve, number(q, 2), number(food.cal * q), number(food.kj * q), number(food.p * q),
                        number(food.c?.let { it * q }), number(food.f?.let { it * q })) + extras.map { n -> number(food.nut?.get(n.key)?.let { it * q }) }
                }
            }
        }
        return csv(rows)
    }

    /** One row per logged day, with that day's targets. "Incomplete" names totals where some foods had no figure. */
    fun days(data: AppData): String {
        val keys = nutrientNames.map { it.key }
        val rows = mutableListOf(listOf("Date", "Meals") + nutrientNames.map { "${it.label} (${it.unit})" } + listOf("Incomplete") +
            nutrientNames.map { "${it.label} target (${it.unit})" })
        val current = data.goalSets.firstOrNull { it.id == data.activeGoal } ?: data.goalSets.firstOrNull()
        for (day in data.logs.keys.sorted()) {
            val entries = data.logs[day] ?: emptyList()
            if (entries.isEmpty()) continue
            val items = entries.flatMap { it.items }; val total = Nutrition(items)
            // Blank when no food that day listed the figure; a 0 would read as a real total.
            fun listed(key: String) = when (key) {
                "cal", "p" -> true
                "c" -> items.any { it.food.c != null }
                "f" -> items.any { it.food.f != null }
                else -> total.nut[key] != null
            }
            val incomplete = nutrientNames.filter { total.isPartial(it.key) }.joinToString("; ") { it.label }
            val goals = data.dayGoals[day] ?: current
            rows += listOf(day, entries.size.toString()) + keys.map { if (listed(it)) number(total.value(it)) else "" } + listOf(incomplete) +
                keys.map { number(goals?.values?.get(it)) }
        }
        return csv(rows)
    }

    private fun csv(rows: List<List<String>>): String = rows.joinToString("\r\n") { it.joinToString(",", transform = ::field) } + "\r\n"

    /** Quotes a field when needed. Text that a spreadsheet would run as a formula gets a leading apostrophe. */
    private fun field(value: String): String {
        var text = value
        if (text.isNotEmpty() && text[0] in "=+-@\t\r" && text.toDoubleOrNull() == null) text = "'$text"
        if (text.none { it in ",\"\r\n" }) return text
        return "\"" + text.replace("\"", "\"\"") + "\""
    }
}

/** Export and import of all app data, and the CSV exports (BackupSection in MyFoodsView.swift), shown in Settings. */
@Composable
internal fun BackupSection() {
    val store = AppServices.store
    val context = LocalContext.current
    var pending by remember { mutableStateOf<AppData?>(null) }
    var message by remember { mutableStateOf<String?>(null) }
    var outgoing by remember { mutableStateOf<ByteArray?>(null) }
    val today = dayKey(LocalDate.now())

    fun write(uri: Uri?) {
        val bytes = outgoing ?: return
        outgoing = null
        if (uri == null) return
        runCatching { context.contentResolver.openOutputStream(uri, "wt")!!.use { it.write(bytes) } }.onFailure { message = it.message ?: "Couldn’t save the file." }
    }
    val saveJson = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { write(it) }
    val saveCsv = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("text/csv")) { write(it) }
    val open = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        runCatching {
            val text = context.contentResolver.openInputStream(uri)!!.use { it.readBytes().toString(Charsets.UTF_8) }
            pending = store.decodeAnyBackup(text)
        }.onFailure { message = "Couldn’t import this backup. ${it.message ?: ""}".trim() }
    }
    val disabled = store.loadError != null
    // A byte-order mark so Excel reads names with accents correctly.
    fun csvBytes(text: String) = ("﻿" + text).toByteArray(Charsets.UTF_8)

    SettingsSection("Your data", footerText = "Foods, recipes, saved meals, daily logs, targets and your current meal are saved on this phone. Export a backup to transfer them; backups from Leanrrr on iPhone import too. Backups from the earlier web version also import, without daily history. CSV files open in Excel, Google Sheets or Numbers; figures a food didn't list are left blank.") {
        ButtonRow("Export all app data", Icons.Outlined.Upload, enabled = !disabled) {
            outgoing = store.export().toByteArray(Charsets.UTF_8); saveJson.launch("Leanrrr-$today.json")
        }
        ButtonRow("Import backup", Icons.Outlined.Download, enabled = !disabled) { open.launch(arrayOf("application/json", "text/plain", "application/octet-stream")) }
        ButtonRow("Export food log (CSV)", Icons.Outlined.TableChart, enabled = !disabled) {
            outgoing = csvBytes(CsvExport.items(store.data, store::chainName)); saveCsv.launch("Leanrrr food log $today.csv")
        }
        ButtonRow("Export daily totals (CSV)", Icons.Outlined.CalendarMonth, divider = false, enabled = !disabled) {
            outgoing = csvBytes(CsvExport.days(store.data)); saveCsv.launch("Leanrrr daily totals $today.csv")
        }
    }
    pending?.let { backup ->
        AlertDialog(
            onDismissRequest = { pending = null },
            title = { Text("Merge this backup?", style = LeanrType.headline) },
            text = {
                Text("Import ${backup.foods.size} foods, ${backup.meals.size} saved meals and ${backup.logs.size} days. Existing entries are kept; matching IDs are updated. A nonempty current meal is kept. Importing never shares a food with the community.",
                    style = LeanrType.subheadline)
            },
            confirmButton = {
                TextButton(onClick = {
                    message = if (store.merge(backup)) "Backup imported." else store.errorMessage ?: "Couldn’t import this backup."
                    store.errorMessage = null
                    pending = null
                }) { Text("Import backup") }
            },
            dismissButton = { TextButton(onClick = { pending = null }) { Text("Cancel") } },
        )
    }
    message?.let { MessageAlert(it) { message = null } }
}
