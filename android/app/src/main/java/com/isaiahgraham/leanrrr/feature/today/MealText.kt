package com.isaiahgraham.leanrrr.feature.today

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.ui.components.BottomActionBar
import com.isaiahgraham.leanrrr.ui.components.LeanrRow
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.components.NumberField
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Type or dictate what you ate ("two eggs, toast with butter and a flat white"); Leanrrr finds each food in its own data and
 * you check them before logging (MealTextView.swift). Leanrrr's own reading is used; nothing leaves the phone.
 * `log` saves the chosen portions under one name and returns false if it couldn't. `verb` is the button's wording ("Log", "Plan").
 */
@Composable
fun MealTextScreen(mealTime: MealTime, onBack: () -> Unit, verb: String = "Log", log: (List<Portion>, String) -> Boolean) {
    val store = AppServices.store
    val scope = rememberCoroutineScope()
    val keyboard = LocalSoftwareKeyboardController.current
    var text by rememberSaveable { mutableStateOf("") }
    var rows by remember { mutableStateOf(emptyList<FoodMatchRow>()) }
    var reading by remember { mutableStateOf(false) }
    var read by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    var searching by remember { mutableStateOf<String?>(null) }
    val portions = rows.mapNotNull { it.portion }

    searching?.let { id ->
        val row = rows.firstOrNull { it.id == id }
        FoodPickerScreen("Search", "Use this", initialSearch = row?.let { it.phrase?.name ?: it.title } ?: "", onBack = { searching = null }, onPick = { portion ->
            rows = rows.map { r ->
                if (r.id != id) r else r.copy(matches = listOf(portion.food) + r.matches.filter { it.id != portion.food.id }, chosen = portion.food.id,
                    quantity = portion.quantity, sure = true)
            }
            searching = null
        })
        return
    }

    fun find() {
        val words = text.trim()
        if (words.isEmpty() || reading) return
        keyboard?.hide(); reading = true
        val foods = store.foods
        val names = store.searchChainNames
        scope.launch {
            rows = withContext(Dispatchers.Default) {
                val index = FoodMatching.index(foods, names)
                fun bareWords(name: String) = " " + FoodMatching.tokens(name).filter { it !in listOf("and", "with", "n") }.joinToString(" ") + " "
                val known = index.map { bareWords(it.food.name) }.toSet()
                val phrases = FoodPhrase.meal(words) { candidate -> val wanted = bareWords(candidate); known.any { it.contains(wanted) } }
                phrases.map { FoodMatchRow.make(it, if (it.original.isEmpty()) it.name else it.original, index, names) }
            }
            read = true; reading = false
        }
    }

    BackTo(onBack = onBack)
    LeanrScreen("Describe your meal", onBack = onBack, showSettings = false, bottomBar = {
        if (portions.isNotEmpty()) {
            BottomActionBar("$verb ${portions.size} to ${mealTime.title} · ${Nutrition(portions).cal.whole.number} Cal", enabled = portions.all { it.isValid }) {
                if (log(portions, portions.joinToString(" + ") { it.food.name })) onBack() else failed = true
            }
        }
    }) {
        item {
            LeanrSection(footer = "Type it, or tap the microphone on the keyboard and say it. Name a restaurant (\"from KFC\") to look there first. Your phone reads the words, and nothing is sent anywhere.") {
                SectionTextField(text, { text = it }, "Two eggs, toast with butter and a flat white", singleLine = false, minLines = 3)
                TextButton(onClick = { find() }, enabled = text.isNotBlank() && !reading, modifier = Modifier.fillMaxWidth()) {
                    if (reading) {
                        CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = Leanr.colours.accent)
                        Spacer(Modifier.size(8.dp))
                        Text("Reading…", style = LeanrType.body)
                    } else Text("Find these foods", style = LeanrType.body, color = if (text.isNotBlank()) Leanr.colours.accent else Leanr.colours.tertiaryText)
                }
            }
        }
        if (read && rows.isEmpty()) {
            item { LeanrSection { SectionText("No foods found in that. Try naming each food, like \"chicken breast, rice and broccoli\".") } }
        }
        foodMatchSections(rows, onChange = { updated -> rows = rows.map { if (it.id == updated.id) updated else it } }, onSearch = { searching = it })
    }
    if (failed) MessageDialog("Couldn’t save that", "Your data was not changed. Check available storage and try again.") { failed = false }
}

/** A section per row: pick the match (or leave it out), set the servings, or search for something else (FoodMatchSections). */
fun LazyListScope.foodMatchSections(rows: List<FoodMatchRow>, onChange: (FoodMatchRow) -> Unit, onSearch: (String) -> Unit) {
    rows.forEach { row ->
        item(key = "match-${row.id}") { FoodMatchSection(row, onChange, onSearch) }
    }
}

@Composable
private fun FoodMatchSection(row: FoodMatchRow, onChange: (FoodMatchRow) -> Unit, onSearch: (String) -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    LeanrSection(row.title) {
        if (row.matches.isEmpty()) {
            SectionText("Not in Leanrrr yet. Search for something close, or leave it out.")
        } else {
            if (row.chosen == null && row.unchosenNote != null) {
                Text(row.unchosenNote, style = LeanrType.caption, color = c.secondaryText, modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 10.dp))
            }
            val options = row.matches.map { it.id to it.name } + (null to "Leave it out")
            options.forEach { (id, name) ->
                LeanrRow(name, onClick = { onChange(row.copy(chosen = id).withAmount()) }, leading = {
                    RadioButton(selected = row.chosen == id, onClick = null, colors = RadioButtonDefaults.colors(selectedColor = c.accent))
                })
            }
            row.food?.let { food ->
                key(row.id, food.id) {
                    NumberField("Servings", row.quantity, { onChange(row.copy(quantity = it)) })
                }
                Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("${store.chainName(food.chain)} · ${food.serve.ifEmpty { "1 serving" }} each · ${Nutrition(listOf(Portion(food = food, quantity = row.quantity))).cal.whole.number} Cal",
                        style = LeanrType.caption, color = c.secondaryText)
                    if (!row.sure) {
                        Text("Check the amount: Leanrrr couldn’t turn \"${row.phrase?.original ?: row.title}\" into servings of this food.", style = LeanrType.caption, color = c.over)
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = { onSearch(row.id) }, modifier = Modifier.padding(horizontal = 4.dp)) {
                Icon(Icons.Filled.Search, null, tint = c.accent, modifier = Modifier.size(18.dp))
                Spacer(Modifier.size(6.dp))
                Text("Search for it instead", style = LeanrType.body, color = c.accent)
            }
        }
    }
}
