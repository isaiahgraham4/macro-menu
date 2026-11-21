package com.isaiahgraham.leanrrr.feature.today

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.data.tenth
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection

/**
 * Logs calories and macros on their own, for something eaten when you don't know what or how much it was (QuickAddView.swift).
 * Nothing is saved to My foods: it's one entry in the day's log. `save` returns false if it couldn't be saved.
 */
@Composable
fun QuickAddScreen(mealTime: MealTime, onBack: () -> Unit, save: (Portion, MealTime) -> Boolean) {
    var time by rememberSaveable { mutableStateOf(mealTime) }
    var calories by rememberSaveable { mutableStateOf<Double?>(null) }
    var protein by rememberSaveable { mutableStateOf<Double?>(null) }
    var carbs by rememberSaveable { mutableStateOf<Double?>(null) }
    var fat by rememberSaveable { mutableStateOf<Double?>(null) }
    var note by rememberSaveable { mutableStateOf("") }
    var failed by rememberSaveable { mutableStateOf(false) }

    /** Calories worked out from the macros (4 per gram of protein and carbs, 9 per gram of fat), when none were typed. */
    val estimated: Double? = if (calories == null && listOf(protein, carbs, fat).any { (it ?: 0.0) > 0 })
        (protein ?: 0.0) * 4 + (carbs ?: 0.0) * 4 + (fat ?: 0.0) * 9 else null
    val food: Food? = (calories ?: estimated)?.takeIf { it > 0 }?.let { energy ->
        val cal = energy.tenth
        val name = note.trim()
        Food(name = name.ifEmpty { "Quick add" }, kj = cal * 4.184, cal = cal, p = (protein ?: 0.0).tenth, c = carbs?.tenth, f = fat?.tenth, serve = "Quick add")
            .takeIf { it.isValid }
    }

    BackTo(onBack = onBack)
    LeanrScreen("Quick add", onBack = onBack, showSettings = false, actions = {
        TopAction("Log", enabled = food != null) {
            val value = food ?: return@TopAction
            if (save(Portion(food = value), time)) onBack() else failed = true
        }
    }) {
        item { LeanrSection { MealTimeRow("Log to", time, divider = false) { time = it } } }
        item {
            LeanrSection(footer = if (estimated == null) "Leave blank what you don’t know. No calories? They’re worked out from the macros." else "Calories are worked out from your macros.") {
                BlankableNumberRow("Calories", "Cal", calories, placeholder = estimated?.let { "≈ ${it.number}" } ?: "0") { calories = it }
                BlankableNumberRow("Protein", "g", protein) { protein = it }
                BlankableNumberRow("Carbs", "g", carbs) { carbs = it }
                BlankableNumberRow("Fat", "g", fat, divider = false) { fat = it }
            }
        }
        item { LeanrSection { SectionTextField(note, { note = it }, "What was it? (optional)") } }
    }
    if (failed) MessageDialog("Couldn’t log this", "Your data was not changed. Check available storage and any data recovery message in the app.") { failed = false }
}
