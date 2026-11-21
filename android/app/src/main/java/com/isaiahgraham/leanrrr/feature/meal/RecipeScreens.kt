package com.isaiahgraham.leanrrr.feature.meal

import android.content.ClipboardManager
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Public
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.newId
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.data.recipesBrokenUp
import com.isaiahgraham.leanrrr.feature.find.FoodSearch
import com.isaiahgraham.leanrrr.ui.components.BottomActionBar
import com.isaiahgraham.leanrrr.ui.components.LeanrRow
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.components.NumberField
import com.isaiahgraham.leanrrr.ui.components.NutritionView
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.max
import kotlin.math.roundToLong

// RecipeEditor (MyFoodsView.swift) and RecipeImportView.swift, with a simple ingredient matcher in place of
// FoodPhrase + FoodMatchList (owned by Today and Find on iOS).

/** Build or change a recipe: a name, how many servings it makes, and its ingredients. */
@Composable
fun RecipeEditorScreen(food: Food?, onClose: () -> Unit, imported: Boolean = false, saved: (() -> Unit)? = null) {
    val store = AppServices.store
    val c = Leanr.colours
    var name by remember { mutableStateOf(food?.name ?: "") }
    var servings by remember { mutableDoubleStateOf(food?.recipeYield ?: 1.0) }
    var ingredients by remember { mutableStateOf(recipesBrokenUp(food?.ingredients ?: emptyList())) }
    var picking by remember { mutableStateOf(false) }
    var own by remember { mutableStateOf(false) }
    val newRecipeID = remember { newId() }
    val recipe = Nutrition(ingredients).food(name, max(servings, 0.001), ingredients).copy(
        id = food?.id ?: newRecipeID, serve = "1 of ${servings.number} servings", note = food?.note,
    )
    if (picking) { FoodPickerScreen("Add to recipe", onPick = { ingredients = recipesBrokenUp(ingredients + it); picking = false }, onDone = { picking = false }); return }
    if (own) { FoodEditorScreen(null, onDone = { own = false }, save = { ingredients = ingredients + Portion(food = it); true }); return }
    BackHandler(onBack = onClose)
    val canSave = recipe.isValid && ingredients.isNotEmpty() && servings > 0 && name.isNotBlank()
    LeanrScreen(if (food == null || imported) "Build a recipe" else "Edit recipe", onBack = onClose, showSettings = false, actions = {
        TextButton(onClick = { if (store.saveFood(recipe)) { store.notice = "Saved ${recipe.name}"; onClose(); saved?.invoke() } }, enabled = canSave) {
            Text("Save", color = if (canSave) c.accent else c.tertiaryText)
        }
    }) {
        item {
            LeanrSection {
                TextRow(name, { name = it }, "Recipe name")
                OffensiveTextNote(name)
                NumberField("Recipe makes (servings)", servings, { servings = it }, divider = false)
            }
        }
        item { Text("INGREDIENTS", style = LeanrType.footnote, color = c.secondaryText, modifier = Modifier.padding(start = 16.dp, bottom = 6.dp)) }
        items(ingredients, key = { it.id }) { item ->
            SwipeToDelete(onDelete = { ingredients = ingredients.filter { it.id != item.id } }) {
                Column(Modifier.padding(top = 10.dp)) {
                    Row(Modifier.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(item.food.name, style = LeanrType.headline, color = c.text, modifier = Modifier.weight(1f))
                        IconButton(onClick = { ingredients = ingredients.filter { it.id != item.id } }, modifier = Modifier.size(32.dp)) {
                            Icon(Icons.Filled.Delete, "Remove ${item.food.name}", tint = c.tertiaryText, modifier = Modifier.size(18.dp))
                        }
                    }
                    NumberField("Servings of ingredient", item.quantity, { q -> ingredients = ingredients.map { if (it.id == item.id) it.copy(quantity = q) else it } })
                }
            }
        }
        item {
            LeanrSection {
                ActionRow("Choose a food") { picking = true }
                ActionRow("Enter ingredient nutrition", divider = false) { own = true }
            }
        }
        if (ingredients.isNotEmpty()) {
            item { LeanrSection("Whole recipe") { NutritionView(Nutrition(ingredients), details = false) } }
            item { LeanrSection("Per serving") { NutritionView(Nutrition(listOf(Portion(food = recipe)))) } }
        }
    }
}

/** One ingredient line matched to Leanrrr's foods: the likely match ticked, with its amount worked out (FoodMatchRow). */
data class IngredientMatch(
    val id: String = newId(),
    val title: String,
    val matches: List<Food>,
    val chosen: String?,
    val quantity: Double,
    val phrase: IngredientPhrase,
    /** False when the amount is a guess that should be checked. */
    val sure: Boolean = true,
) {
    val food: Food? get() = matches.firstOrNull { it.id == chosen }
    val portion: Portion? get() = food?.let { Portion(food = it, quantity = quantity) }

    fun choosing(id: String?): IngredientMatch {
        val next = copy(chosen = id)
        val food = next.food ?: return next
        val (q, s) = phrase.servings(food)
        return next.copy(quantity = q, sure = s)
    }

    companion object {
        /** A row for a recipe line. An uncooked version comes first, since recipes weigh meat and vegetables before cooking. */
        fun make(line: String, foods: List<Food>, chainNames: Map<String, String>): IngredientMatch? {
            val phrase = IngredientPhrase.parse(line) ?: return null
            var matches = FoodSearch.search(phrase.name, foods, chainNames, limit = 6).toMutableList()
            val raw = matches.indexOfFirst { food -> food.name.lowercase().split(Regex("[^a-z]+")).contains("raw") }
            if (raw > 0) matches.add(0, matches.removeAt(raw))
            matches = matches.take(4).toMutableList()
            val row = IngredientMatch(title = line.replaceFirstChar { it.uppercase() }, matches = matches, chosen = null, quantity = 1.0, phrase = phrase)
            return if (phrase.amount != null && matches.isNotEmpty()) row.choosing(matches[0].id) else row
        }
    }
}

/** What a recipe line says: how much, in what unit, of what. A simpler stand-in for FoodPhrase.ingredient. */
data class IngredientPhrase(val name: String, val amount: Double?, val unit: String?) {
    /** How many servings of `food` this is, and whether that's more than a guess. */
    fun servings(food: Food): Pair<Double, Boolean> {
        val amount = amount ?: return 1.0 to false
        val weight = food.servingWeight
        val millilitres = when (unit) { "cup" -> 250.0; "tbsp" -> 20.0; "tsp" -> 5.0; else -> null }
        return when {
            (unit == "g" || unit == "ml") && weight != null -> (amount / weight.first).clean() to true
            millilitres != null && weight != null -> (amount * millilitres / weight.first).clean() to false
            unit == null -> amount.clean() to true
            else -> 1.0 to false
        }
    }

    private fun Double.clean(): Double = if (!isFinite() || this <= 0) 1.0 else (this * 100).roundToLong() / 100.0

    companion object {
        private val fractions = mapOf('½' to 0.5, '¼' to 0.25, '¾' to 0.75, '⅓' to 1.0 / 3, '⅔' to 2.0 / 3, '⅛' to 0.125)
        private val units = mapOf("g" to "g", "gram" to "g", "grams" to "g", "kg" to "kg", "ml" to "ml", "l" to "l", "litre" to "l", "litres" to "l",
            "cup" to "cup", "cups" to "cup", "tbsp" to "tbsp", "tablespoon" to "tbsp", "tablespoons" to "tbsp", "tbs" to "tbsp",
            "tsp" to "tsp", "teaspoon" to "tsp", "teaspoons" to "tsp")
        /** Words a recipe uses for how something's prepared, which a food list doesn't. */
        private val preparation = setOf("chopped", "diced", "sliced", "minced", "grated", "shredded", "crushed", "peeled", "trimmed", "halved",
            "quartered", "finely", "roughly", "thinly", "coarsely", "freshly", "fresh", "packed", "heaped", "level", "softened", "melted",
            "beaten", "lightly", "sifted", "drained", "rinsed", "cubed", "torn", "picked", "deseeded", "seeded", "large", "medium", "small",
            "of", "x", "about", "approx", "pinch", "handful", "to", "taste", "cans", "can", "tin", "tins", "clove", "cloves", "bunch")

        fun parse(line: String): IngredientPhrase? {
            var text = line.lowercase().replace("’", "'")
            // A weight in brackets is more exact than cups or a count: "1 cup (150 g) flour".
            var bracket: Pair<Double, String>? = null
            Regex("""\((?:about |approx\.? )?(\d+(?:\.\d+)?)\s*(g|kg|ml|l)\b[^)]*\)""").find(text)?.let {
                val value = it.groupValues[1].toDoubleOrNull() ?: 0.0; val unit = it.groupValues[2]
                bracket = (value * (if (unit == "kg" || unit == "l") 1000 else 1)) to (if (unit == "g" || unit == "kg") "g" else "ml")
            }
            text = text.replace(Regex("""\([^)]*\)"""), " ")
            // Preparation notes come after a comma or a dash: "onion, finely chopped".
            text = text.split(',', '—').first().replace(Regex("""\s[-–]\s.*$"""), "")
            for ((ch, v) in fractions) text = text.replace(ch.toString(), " ${v} ")
            var amount: Double? = null
            Regex("""^\s*(\d+(?:\.\d+)?)(?:\s+(\d+)/(\d+)|/(\d+))?(?:\s*[-–]\s*\d+(?:\.\d+)?)?\s*(\d*\.\d+)?""").find(text)?.let { m ->
                var value = m.groupValues[1].toDoubleOrNull() ?: 0.0
                if (m.groupValues[4].isNotEmpty()) value /= (m.groupValues[4].toDoubleOrNull() ?: 1.0)
                if (m.groupValues[2].isNotEmpty()) value += (m.groupValues[2].toDoubleOrNull() ?: 0.0) / (m.groupValues[3].toDoubleOrNull() ?: 1.0)
                m.groupValues[5].toDoubleOrNull()?.let { value += it }
                if (value > 0) amount = value
                text = text.substring(m.range.last + 1)
            }
            var unit: String? = null
            Regex("""^\s*([a-z]+)\b\.?""").find(text)?.let { m ->
                units[m.groupValues[1]]?.let { u -> unit = u; text = text.substring(m.range.last + 1) }
            }
            if (unit == "kg") { amount = amount?.times(1000); unit = "g" }
            if (unit == "l") { amount = amount?.times(1000); unit = "ml" }
            bracket?.let { (grams, u) -> if (unit != "g" && unit != "ml") { amount = grams * (if (unit == null) (amount ?: 1.0) else 1.0); unit = u } }
            // "cornflour / corn starch", "butter or margarine": the first is the name.
            val words = text.split('/').first().split(" or ").first().split(Regex("[^a-z']+")).filter { it.length > 1 && it !in preparation }
            val name = words.joinToString(" ")
            if (name.none { it.isLetter() }) return null
            return IngredientPhrase(name, amount, unit)
        }
    }
}

/**
 * Paste a recipe's web address; Leanrrr loads the page and reads the recipe. Save it with the site's own nutrition per
 * serving, or match each ingredient to Leanrrr's foods and build it as a recipe you can change.
 */
@Composable
fun RecipeImportScreen(onClose: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var text by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<RecipeImport.Failure?>(null) }
    var recipe by remember { mutableStateOf<ImportedRecipe?>(null) }
    var servings by remember { mutableDoubleStateOf(1.0) }
    var rows by remember { mutableStateOf(emptyList<IngredientMatch>()) }
    var building by remember { mutableStateOf<Food?>(null) }
    val portions = rows.mapNotNull { it.portion }

    fun load() {
        val url = RecipeImport.link(text) ?: run { failure = RecipeImport.Failure.NOT_A_LINK; return }
        failure = null; loading = true
        val foods = store.foods; val names = store.searchChainNames
        scope.launch {
            try {
                val found = RecipeImport.load(url)
                val matched = withContext(Dispatchers.Default) { found.ingredients.mapNotNull { IngredientMatch.make(it, foods, names) } }
                recipe = found; servings = found.servings ?: 1.0; rows = matched
            } catch (e: RecipeImport.ImportException) { failure = e.failure } catch (e: Exception) { failure = RecipeImport.Failure.COULD_NOT_LOAD }
            loading = false
        }
    }

    building?.let { draft -> RecipeEditorScreen(draft, onClose = { building = null }, imported = true, saved = onClose); return }
    BackHandler(onBack = onClose)
    LeanrScreen("Import a recipe", onBack = onClose, showSettings = false, bottomBar = {
        val current = recipe
        if (current != null && portions.isNotEmpty()) {
            BottomActionBar("Build from ${portions.size} ingredients · ${(Nutrition(portions).cal / max(servings, 1.0)).roundToLong().toDouble().number} Cal a serving") {
                building = Nutrition(portions).food(current.name, max(servings, 0.001), portions).copy(note = current.host?.let { "From $it" })
            }
        }
    }) {
        item {
            LeanrSection(footer = "Copy the address from your browser or a recipe app. Leanrrr loads the page straight from that website and reads only its recipe details. Nothing else about you is sent.") {
                TextRow(text, { text = it }, "https://…", keyboard = KeyboardType.Uri)
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    OutlinedButton(onClick = {
                        val clip = context.getSystemService(ClipboardManager::class.java)?.primaryClip
                        val pasted = clip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(context)?.toString()
                        if (!pasted.isNullOrBlank()) { text = pasted; load() }
                    }) {
                        Icon(Icons.Filled.ContentPaste, null, tint = c.accent, modifier = Modifier.size(16.dp)); Spacer(Modifier.width(6.dp))
                        Text("Paste", color = c.accent)
                    }
                    Spacer(Modifier.weight(1f))
                    OutlinedButton(onClick = { load() }, enabled = text.isNotBlank() && !loading) {
                        if (loading) CircularProgressIndicator(Modifier.size(18.dp), color = c.accent, strokeWidth = 2.dp) else Text("Load recipe", color = c.accent)
                    }
                }
                failure?.let { SectionNote(it.message) }
            }
        }
        val current = recipe ?: return@LeanrScreen
        item {
            LeanrSection("Recipe") {
                LeanrRow(current.name)
                key(current) { NumberField("Serves", servings, { servings = it }) }
                current.source?.let { source ->
                    LinkRow(current.host ?: "Open the page", Icons.Filled.Public) {
                        runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(source))) }
                    }
                }
            }
        }
        current.food?.let { food ->
            item {
                LeanrSection("Per serving, from ${current.host ?: "the page"}",
                    footer = "The site's own figures for one serving. Or match the ingredients below to build it from Leanrrr's foods, which you can change later.") {
                    NutritionView(Nutrition(listOf(Portion(food = food))))
                    androidx.compose.material3.Button(onClick = { if (store.saveFood(food)) { store.notice = "Saved ${food.name} to My foods"; onClose() } },
                        modifier = Modifier.fillMaxWidth().padding(16.dp),
                        colors = androidx.compose.material3.ButtonDefaults.buttonColors(containerColor = c.accent)) { Text("Save with these figures") }
                }
            }
        }
        if (rows.isEmpty()) {
            item { LeanrSection { LeanrRow("This page doesn't list its ingredients.", divider = false, titleColour = c.secondaryText) } }
        } else {
            item {
                LeanrSection("Ingredients") {
                    SectionNote("${portions.size} of ${rows.size} ingredients matched. Lines without an amount, like salt to taste, are left out unless you choose them.")
                }
            }
            items(rows, key = { it.id }) { row ->
                MatchSection(row) { updated -> rows = rows.map { if (it.id == updated.id) updated else it } }
            }
        }
    }
}

/** One ingredient line with its likely foods to choose from, or none, and the amount. */
@Composable
private fun MatchSection(row: IngredientMatch, onChange: (IngredientMatch) -> Unit) {
    val c = Leanr.colours
    val store = AppServices.store
    LeanrSection(row.title) {
        if (row.matches.isEmpty()) SectionNote("No match found. Add it after building, with Choose a food.")
        row.matches.forEach { food ->
            Row(Modifier.fillMaxWidth().padding(start = 4.dp, end = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                RadioButton(row.chosen == food.id, { onChange(row.choosing(food.id)) }, colors = RadioButtonDefaults.colors(selectedColor = c.accent))
                Column(Modifier.weight(1f).padding(vertical = 6.dp)) {
                    Text(food.name, style = LeanrType.body, color = c.text)
                    Text("${store.chainName(food.chain)} · ${food.cal.number} Cal · ${food.serve}", style = LeanrType.caption, color = c.secondaryText)
                }
            }
        }
        if (row.matches.isNotEmpty()) {
            Row(Modifier.fillMaxWidth().padding(start = 4.dp, end = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                RadioButton(row.chosen == null, { onChange(row.copy(chosen = null)) }, colors = RadioButtonDefaults.colors(selectedColor = c.accent))
                Text("Leave out", style = LeanrType.body, color = c.text)
            }
        }
        if (row.food != null) {
            key(row.chosen) { NumberField("Servings", row.quantity, { onChange(row.copy(quantity = it, sure = true)) }, divider = false) }
            if (!row.sure) SectionNote("Check the amount: it's worked out from the recipe's wording.", warningColour)
        }
    }
}
