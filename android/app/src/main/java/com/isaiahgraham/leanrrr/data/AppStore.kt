package com.isaiahgraham.leanrrr.data

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * Everything Leanrrr knows, observable by Compose: the saved data (`app-state.json`, the same file format as iOS) and the
 * food lists. A port of AppStore.swift. Every change goes through [change], which validates, saves atomically, offers Undo
 * and tells the hooks (Health Connect, widgets) about it.
 *
 * Feature code adds its own mutations as extension functions that call [change] (see the `feature` packages).
 */
class AppStore(private val context: Context) {
    private val file = File(context.filesDir, "MacroMenu/app-state.json")
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    var data by mutableStateOf(AppData()); private set
    var catalog by mutableStateOf(MenuCatalog()); private set
    /** Everyday foods (bananas, chicken breast, rice...), bundled with the app. */
    var everyday by mutableStateOf(emptyList<Food>()); private set
    /** USDA survey foods: searchable and matched from photos, but never suggested. */
    var survey by mutableStateOf(emptyList<Food>()); private set
    /** Coles and Woolworths ready meals and snacks. Search and Find's supermarket mode see them; the Map and suggestions don't. */
    var supermarket by mutableStateOf(emptyList<Food>()); private set
    var supermarketChains by mutableStateOf(emptyList<Chain>()); private set
    var listVersions by mutableStateOf(emptyMap<String, FoodListVersion>()); private set
    private var bundledListVersions: Map<String, FoodListVersion> = emptyMap()
    /** Foods other people shared, already filtered for reports and hidden people. */
    var community by mutableStateOf(emptyList<Food>()); private set
    var communityRevision by mutableIntStateOf(0); private set
    /** True once the bundled food files have been read (they're large, so they load off the main thread). */
    var foodsLoaded by mutableStateOf(false); private set

    var loadError by mutableStateOf<String?>(null); private set
    var errorMessage by mutableStateOf<String?>(null)
    var notice by mutableStateOf<String?>(null)
    /** What's waiting to be shown over the app, first in line first. */
    val moments = mutableStateListOf<Moment>()
    /** Goes up with every meal logged, for the haptic that confirms it. */
    var mealsLoggedPulse by mutableIntStateOf(0)
    /** Goes up with every refusal, for the haptic that goes with it. */
    var refusedPulse by mutableIntStateOf(0)
    /** Set once the launch animation has gone, so a card isn't shown underneath it. */
    var launchSettled by mutableStateOf(false)

    /** The last week of steps and active energy from Health Connect, kept in memory for widgets. Not part of AppData. */
    var widgetSteps by mutableStateOf(emptyMap<String, Double>()); private set
    var widgetEnergy by mutableStateOf(emptyMap<String, Double>()); private set
    private var stepsMarkedDay: String? = null

    data class UndoStep(val id: String = newId(), val label: String, val snapshot: AppData)
    var undo by mutableStateOf<UndoStep?>(null); private set

    /** Called after local changes so Health Connect can follow the log and weights. */
    var logsChanged: ((old: AppData, new: AppData) -> Unit)? = null
    /** Called after every save. */
    var saved: (() -> Unit)? = null
    /** Called whenever widgets should be brought up to date. */
    var widgetsRefreshed: (() -> Unit)? = null

    var region by mutableStateOf(MenuRegion.saved); private set

    init {
        try {
            if (file.exists()) {
                val loaded = LeanrJson.decodeFromString<AppData>(file.readText())
                if (!loaded.isValid) throw IllegalStateException("The saved file didn't pass its checks.")
                data = loaded
            }
        } catch (e: Exception) {
            loadError = "Saved data could not be read. The original file has been preserved. ${e.message ?: ""}".trim()
        }
        scope.launch { loadFoods() }
    }

    private fun asset(name: String): String = context.assets.open(name).bufferedReader().use { it.readText() }

    private suspend fun loadFoods() {
        val region = this.region
        val loaded = withContext(Dispatchers.Default) {
            val versions = runCatching { LeanrJson.decodeFromString<Map<String, FoodListVersion>>(asset("FoodLists.json")) }.getOrDefault(emptyMap())
            val menu = runCatching { LeanrJson.decodeFromString<MenuCatalog>(asset(region.menuFile)) }
            val everyday = runCatching { LeanrJson.decodeFromString<List<Food>>(asset("GenericFoods.json")) }.getOrDefault(emptyList())
                .filter { it.isValid && it.isEveryday }
            val survey = runCatching { LeanrJson.decodeFromString<List<Food>>(asset("SurveyFoods.json")) }.getOrDefault(emptyList())
                .filter { it.isValid && it.isEveryday }
            val shops = region.supermarketFile?.let { runCatching { LeanrJson.decodeFromString<MenuCatalog>(asset(it)) }.getOrNull() }
            // A newer copy downloaded earlier wins over the bundled one.
            val bestMenu = menu.getOrNull()?.let { MenuUpdates.best(context, FoodDataset.Menu(region), it) }
            Loaded(versions, menu.exceptionOrNull(), bestMenu, everyday, survey, shops)
        }
        bundledListVersions = loaded.versions
        val versions = loaded.versions.toMutableMap()
        loaded.menu?.let { catalog = it }
        loaded.menuError?.let { errorMessage = "Could not load restaurant menu: ${it.message}" }
        everyday = loaded.everyday
        survey = loaded.survey
        loaded.shops?.let { shops ->
            supermarket = shops.foods.filter { it.isValid && it.isSupermarket }
            supermarketChains = shops.chains
            if (versions["supermarket"]?.published == null) versions["supermarket"] = (versions["supermarket"] ?: FoodListVersion()).copy(published = shops.published)
        }
        listVersions = versions
        foodsLoaded = true
        refreshWidgets()
    }

    private data class Loaded(
        val versions: Map<String, FoodListVersion>, val menuError: Throwable?, val menu: MenuCatalog?,
        val everyday: List<Food>, val survey: List<Food>, val shops: MenuCatalog?,
    )

    fun useCommunity(foods: List<Food>) { if (foods != community) { community = foods; communityRevision += 1 } }

    /** A notice that says no: shown like any other, with the error haptic. */
    fun refuse(message: String) { notice = message; refusedPulse += 1 }

    /** Search, photos and the food lists see every food; suggestions keep to the curated everyday foods. */
    val foods: List<Food> get() = catalog.foods + everyday + survey + data.foods
    /** Foods the search lists show: all of the above and the supermarket shelves. */
    val searchFoods: List<Food> get() = foods + supermarket + community
    /** Foods that make up an order: restaurant menus and your own foods, without everyday foods. */
    val orderFoods: List<Food> get() = catalog.foods + data.foods

    /** Switches to a newer restaurant menu. Logged meals keep the figures they were logged with. */
    fun useMenu(menu: MenuCatalog) { catalog = menu }

    /** Switches to newer foods downloaded for a dataset. */
    fun useFoods(list: MenuCatalog, dataset: FoodDataset) {
        when (dataset) {
            is FoodDataset.Menu -> { if (dataset.region == region) catalog = list; return }
            FoodDataset.Everyday -> everyday = list.foods.filter { it.isValid && it.isEveryday }
            FoodDataset.Survey -> survey = list.foods.filter { it.isValid && it.isEveryday }
            FoodDataset.Supermarket -> {
                if (!region.hasSupermarkets) return
                supermarket = list.foods.filter { it.isValid && it.isSupermarket }
                supermarketChains = list.chains
            }
        }
        listVersions = listVersions + (dataset.id to FoodListVersion(list.revision, list.published))
    }

    /** The foods in use for a dataset, as an update would replace them, or null when it isn't in use. */
    fun foodsInUse(dataset: FoodDataset): MenuCatalog? {
        val version = listVersions[dataset.id]
        return when (dataset) {
            is FoodDataset.Menu -> if (dataset.region == region) catalog else null
            FoodDataset.Everyday -> MenuCatalog(MenuUpdates.FORMAT, version?.revision, version?.published, emptyList(), everyday)
            FoodDataset.Survey -> MenuCatalog(MenuUpdates.FORMAT, version?.revision, version?.published, emptyList(), survey)
            FoodDataset.Supermarket -> if (!region.hasSupermarkets || supermarketChains.isEmpty()) null
                else MenuCatalog(MenuUpdates.FORMAT, version?.revision, version?.published, supermarketChains, supermarket)
        }
    }

    /** Checks Supabase for newer copies of every dataset in use. */
    suspend fun checkForUpdates(force: Boolean = false) {
        for (dataset in listOf(FoodDataset.Menu(region), FoodDataset.Everyday, FoodDataset.Survey, FoodDataset.Supermarket)) {
            val current = foodsInUse(dataset) ?: continue
            MenuUpdates.check(context, dataset, current, force)?.let { useFoods(it, dataset) }
        }
    }

    /** Switches to another country's bundled menus and saves the choice. Logs, meals and your own foods stay as they are. */
    suspend fun useRegion(new: MenuRegion): Boolean {
        val result = withContext(Dispatchers.Default) {
            val menu = runCatching { LeanrJson.decodeFromString<MenuCatalog>(asset(new.menuFile)) }.getOrNull() ?: return@withContext null
            val shops = new.supermarketFile?.let { runCatching { LeanrJson.decodeFromString<MenuCatalog>(asset(it)) }.getOrNull() }
            Pair(MenuUpdates.best(context, FoodDataset.Menu(new), menu), shops)
        } ?: return false
        Prefs.set(MenuRegion.KEY, new.raw)
        region = new
        catalog = result.first
        val shops = result.second
        supermarket = shops?.foods?.filter { it.isValid && it.isSupermarket } ?: emptyList()
        supermarketChains = shops?.chains ?: emptyList()
        listVersions = if (shops != null) listVersions + ("supermarket" to FoodListVersion(bundledListVersions["supermarket"]?.revision,
            bundledListVersions["supermarket"]?.published ?: shops.published)) else listVersions - "supermarket"
        return true
    }

    val goals: Goals get() = data.goalSets.firstOrNull { it.id == data.activeGoal } ?: data.goalSets[0]

    fun applyEstimatedTargets(values: Map<String, Double>): Boolean {
        val activeID = goals.id
        return change { state ->
            val i = state.goalSets.indexOfFirst { it.id == activeID }
            if (i < 0) return@change state
            val updated = state.goalSets[i].copy(values = state.goalSets[i].values + values)
            state.copy(goalSets = state.goalSets.replace(i, updated), activeGoal = activeID,
                dayGoals = state.dayGoals + (dayKey(Instant.now()) to updated))
        }
    }

    /** Saves a new or edited target set. Today's snapshot follows it only when it's the set in use. */
    fun saveGoals(goal: Goals): Boolean {
        val activeID = goals.id
        return change { state ->
            val i = state.goalSets.indexOfFirst { it.id == goal.id }
            val sets = if (i >= 0) state.goalSets.replace(i, goal) else state.goalSets + goal
            state.copy(goalSets = sets, dayGoals = if (goal.id == activeID) state.dayGoals + (dayKey(Instant.now()) to goal) else state.dayGoals)
        }
    }

    /** Switches the target set in use, from today on. */
    fun useGoals(goal: Goals): Boolean = change { it.copy(activeGoal = goal.id, dayGoals = it.dayGoals + (dayKey(Instant.now()) to goal)) }

    /** Deletes a target set (never the last one). Deleting the set in use switches today to the first one left. */
    fun deleteGoals(goal: Goals): Boolean {
        if (data.goalSets.size <= 1) return false
        val wasActive = goal.id == goals.id
        return change(undo = "Deleted ${goal.name}") { state ->
            val sets = state.goalSets.filter { it.id != goal.id }
            if (!wasActive) state.copy(goalSets = sets)
            else state.copy(goalSets = sets, activeGoal = sets[0].id, dayGoals = state.dayGoals + (dayKey(Instant.now()) to sets[0]))
        }
    }

    fun chain(id: String): Chain? = catalog.chains.firstOrNull { it.id == id }
    val menuDate: Instant? get() = MenuUpdates.publishedDate(catalog.published)

    fun chainName(id: String): String = when (id) {
        Food.EVERYDAY -> "Everyday foods"
        Food.COMMUNITY -> "Community"
        else -> (catalog.chains + supermarketChains).firstOrNull { it.id == id }?.name ?: "My foods"
    }

    /** Restaurants, supermarkets and everyday foods by ID, for search and questions. */
    val searchChainNames: Map<String, String>
        get() {
            val names = LinkedHashMap<String, String>()
            (catalog.chains + supermarketChains).forEach { names.putIfAbsent(it.id, it.name) }
            names.putIfAbsent(Food.EVERYDAY, chainName(Food.EVERYDAY))
            names.putIfAbsent(Food.COMMUNITY, chainName(Food.COMMUNITY))
            return names
        }

    private fun write(updated: AppData) {
        check(loadError == null) { "Saved data couldn't be read, so nothing is written over it." }
        check(updated.isValid) { "That change didn't pass its checks." }
        file.parentFile?.mkdirs()
        val temp = File(file.parentFile, "app-state.json.tmp")
        temp.writeText(LeanrJson.encodeToString(AppData.serializer(), updated))
        if (!temp.renameTo(file)) { file.delete(); temp.renameTo(file) }
    }

    /**
     * Saves a change. With `undo`, the banner offers to reverse it; any other change clears that offer.
     * The action gets the current data and returns the new data (Kotlin's data classes are immutable, unlike Swift's inout).
     */
    fun change(undo: String? = null, action: (AppData) -> AppData): Boolean {
        val old = data
        // Milestones and targets reached are marked in the same save, so nothing is earned twice (earnMoments in Moments.swift).
        val (updated, earned) = action(old).earning(old)
        try { write(updated) } catch (e: Exception) { errorMessage = "Couldn’t save: ${e.message}"; return false }
        data = updated
        this.undo = undo?.let { UndoStep(label = it, snapshot = old) }
        moments += earned
        refreshWidgets()
        logsChanged?.invoke(old, updated)
        saved?.invoke()
        return true
    }

    fun undoLast() {
        val step = undo ?: return
        val old = data
        try { write(step.snapshot) } catch (e: Exception) { errorMessage = "Couldn’t undo: ${e.message}"; return }
        data = step.snapshot; undo = null; notice = null; moments.clear()
        refreshWidgets()
        logsChanged?.invoke(old, data)
        saved?.invoke()
    }

    fun dismissUndo(id: String) { if (undo?.id == id) undo = null }

    /** Starts again with nothing saved. Can't be undone. Health Connect isn't touched here. */
    fun eraseEverything(): Boolean {
        val fresh = AppData()
        loadError = null
        try { write(fresh) } catch (e: Exception) { errorMessage = "Couldn’t delete your data: ${e.message}"; return false }
        data = fresh; undo = null; notice = null
        refreshWidgets()
        return true
    }

    /** Takes the latest step counts from Health Connect, keeping the last seven days for the widget. */
    fun updateSteps(steps: Map<String, Double>, now: LocalDate = LocalDate.now()) {
        val keep = (0L until 7L).map { dayKey(now.minusDays(it)) }.toSet()
        val recent = steps.filterKeys { it in keep }
        if (recent == widgetSteps) return
        val today = dayKey(now)
        if (stepsMarkedDay != today) {
            stepsReachedMoment(widgetSteps, recent, data.stepGoal ?: DEFAULT_STEP_GOAL, today)?.let { stepsMarkedDay = today; moments += it }
        }
        widgetSteps = recent
        refreshWidgets()
    }

    fun updateActiveEnergy(energy: Map<String, Double>, now: LocalDate = LocalDate.now()) {
        val keep = (0L until 7L).map { dayKey(now.minusDays(it)) }.toSet()
        val recent = energy.filterKeys { it in keep }
        if (recent == widgetEnergy) return
        widgetEnergy = recent
        refreshWidgets()
    }

    fun refreshWidgets() { widgetsRefreshed?.invoke() }

    fun saveFood(food: Food): Boolean = change { state ->
        val i = state.foods.indexOfFirst { it.id == food.id }
        state.copy(foods = if (i >= 0) state.foods.replace(i, food) else state.foods + food)
    }

    /** Keeps a logged food (usually a scanned product) in My foods. A food that already has this barcode is updated rather than added twice. */
    fun saveToMyFoods(food: Food): Food? {
        var value = food.copy(chain = "mine", modifiers = null)
        if (food.isCommunity) value = value.copy(id = newId(), contributor = null, shared = null)
        val cal = value.cal.tenth
        value = value.copy(cal = cal, kj = cal * 4.184, p = value.p.tenth, c = value.c?.tenth, f = value.f?.tenth, nut = value.nut?.mapValues { it.value.tenth })
        food.barcode?.let { code -> data.foods.firstOrNull { it.barcode == code }?.let { value = value.copy(id = it.id) } }
        return if (saveFood(value)) value else null
    }

    /** Pinned foods with today's figures where the item is still on the menu or in My foods. */
    val pinnedFoods: List<Food>
        get() {
            val pins = data.pinned ?: return emptyList()
            if (pins.isEmpty()) return emptyList()
            val ids = pins.map { it.id }.toSet()
            val current = foods.filter { it.id in ids }.associateBy { it.id }
            return pins.map { current[it.id] ?: it }
        }

    fun isPinned(food: Food): Boolean = (data.pinned ?: emptyList()).any { it.id == food.id }

    fun togglePin(food: Food) {
        if (isPinned(food)) {
            if (change { s -> s.copy(pinned = s.pinned?.filter { it.id != food.id }) }) notice = "Unpinned ${food.name}"
        } else if ((data.pinned ?: emptyList()).size >= PIN_LIMIT) {
            refuse("You can pin up to $PIN_LIMIT foods. Unpin one first.")
        } else {
            val copy = food.copy(modifiers = null)
            if (change { s -> s.copy(pinned = (s.pinned ?: emptyList()) + copy) }) notice = "Pinned ${food.name}"
        }
    }

    /** Saves an edited logged meal, moving it to `newDay` when its date changed. Undo puts the old version back. */
    fun updateLog(entry: LogEntry, day: String, newDay: String): Boolean {
        if (!entry.isValid || data.logs[day]?.any { it.id == entry.id } != true) return false
        val currentGoals = goals
        return change(undo = "Edited ${entry.name}") { state ->
            val logs = state.logs.toMutableMap()
            if (day == newDay) {
                logs[day] = logs[day]!!.map { if (it.id == entry.id) entry else it }
                state.copy(logs = logs)
            } else {
                logs[day] = logs[day]!!.filter { it.id != entry.id }
                if (logs[day]!!.isEmpty()) logs.remove(day)
                logs[newDay] = (logs[newDay] ?: emptyList()) + entry
                state.copy(logs = logs, dayGoals = if (state.dayGoals[newDay] == null) state.dayGoals + (newDay to currentGoals) else state.dayGoals)
            }
        }
    }

    /** Deletes a logged meal, with Undo. */
    fun deleteLog(entry: LogEntry, day: String): Boolean = change(undo = "Deleted ${entry.name}") { state ->
        val logs = state.logs.toMutableMap()
        val left = (logs[day] ?: emptyList()).filter { it.id != entry.id }
        if (left.isEmpty()) logs.remove(day) else logs[day] = left
        state.copy(logs = logs)
    }

    fun updateMeal(meal: SavedMeal): Boolean {
        if (!meal.isValid || data.meals.none { it.id == meal.id }) return false
        return change(undo = "Edited ${meal.name}") { s -> s.copy(meals = s.meals.map { if (it.id == meal.id) meal else it }) }
    }

    /** Adds foods to the meal being built (the tray). */
    fun add(items: List<Portion>): Boolean {
        val added = change { state ->
            val tray = state.tray.toMutableList()
            for (item in items) {
                val i = tray.indexOfFirst { it.food == item.food }
                if (i >= 0) tray[i] = tray[i].copy(quantity = tray[i].quantity + item.quantity) else tray += item.copy(id = newId())
            }
            state.copy(tray = combined(tray))
        }
        if (added) notice = "Added to your meal"
        return added
    }

    /** `time` stamps the entry with when it was asked for (a queued widget tap) rather than now. */
    fun log(items: List<Portion>, name: String, date: LocalDate, clearTray: Boolean = false, mealTime: MealTime? = null, time: Instant? = null): Boolean {
        val key = dayKey(date); val currentGoals = goals
        val logged = change(undo = "Logged $name") { state ->
            state.copy(
                logs = state.logs + (key to ((state.logs[key] ?: emptyList()) + LogEntry(name = name, items = combined(items), time = time ?: Instant.now(), mealTime = mealTime))),
                dayGoals = if (state.dayGoals[key] == null) state.dayGoals + (key to currentGoals) else state.dayGoals,
                tray = if (clearTray) emptyList() else state.tray,
            )
        }
        if (logged) mealsLoggedPulse += 1
        return logged
    }

    /** Logs straight to today, under the meal time that fits the clock unless one is given. With `yesterday`, to the day before. */
    fun logNow(items: List<Portion>, name: String, mealTime: MealTime = MealTime.suggested(), yesterday: Boolean = false): Boolean {
        val date = if (yesterday) LocalDate.now().minusDays(1) else LocalDate.now()
        if (!log(QuickLog.copies(items), name, date, mealTime = mealTime)) return false
        notice = "Logged to ${if (yesterday) "yesterday’s " else ""}${mealTime.title.lowercase()}"
        return true
    }

    fun export(): String = PrettyJson.encodeToString(AppData.serializer(), data)

    /** Reads a backup: one from this app or the iOS app (same format). */
    fun decodeBackup(text: String): AppData {
        val current = LeanrJson.decodeFromString<AppData>(text)
        require(current.isValid) { "This backup is invalid." }
        return current
    }

    fun merge(backup: AppData): Boolean {
        if (!backup.isValid) { errorMessage = "This backup is invalid."; return false }
        return change { state -> merged(state, withoutNewSharing(backup, state)) }
    }

    companion object {
        const val PIN_LIMIT = 8
        const val DEFAULT_STEP_GOAL = 8_000.0

        /** An imported file can't turn sharing on: that takes the switch in the food editor, after the sharing agreement. */
        fun withoutNewSharing(backup: AppData, current: AppData): AppData {
            val sharedHere = current.foods.filter { it.shared == true }.map { it.id }.toSet()
            return backup.copy(foods = backup.foods.map { if (it.shared == true && it.id !in sharedHere) it.copy(shared = null) else it })
        }

        private fun <T> mergeById(current: List<T>, incoming: List<T>, id: (T) -> String): List<T> {
            val out = current.toMutableList()
            for (item in incoming) {
                val i = out.indexOfFirst { id(it) == id(item) }
                if (i >= 0) out[i] = item else out += item
            }
            return out
        }

        private fun mergeDays(current: Map<String, List<LogEntry>>, incoming: Map<String, List<LogEntry>>): Map<String, List<LogEntry>> {
            val out = current.toMutableMap()
            for ((day, entries) in incoming) out[day] = mergeById(out[day] ?: emptyList(), entries) { it.id }
            return out
        }

        /** Everything in `current` plus `backup`; entries with the same ID take the incoming version. */
        fun merged(current: AppData, backup: AppData): AppData {
            var state = current.copy(
                foods = mergeById(current.foods, backup.foods) { it.id },
                meals = mergeById(current.meals, backup.meals) { it.id },
                logs = mergeDays(current.logs, backup.logs),
                goalSets = mergeById(current.goalSets, backup.goalSets) { it.id },
                dayGoals = current.dayGoals + backup.dayGoals,
            )
            backup.pinned?.let { pins ->
                val merged = (state.pinned ?: emptyList()).toMutableList()
                pins.forEach { pin -> if (merged.none { it.id == pin.id }) merged += pin }
                state = state.copy(pinned = merged.take(PIN_LIMIT))
            }
            backup.weightGoal?.let { goal -> if (goal.set > (state.weightGoal?.set ?: Instant.MIN)) state = state.copy(weightGoal = goal) }
            backup.water?.let { incoming ->
                val water = (state.water ?: emptyMap()).toMutableMap()
                for ((day, ml) in incoming) water[day] = maxOf(water[day] ?: 0.0, ml)
                state = state.copy(water = water)
            }
            val cutoff = Instant.now().minusSeconds(48 * 3600)
            val sips = mergeById(state.waterSips ?: emptyList(), backup.waterSips ?: emptyList()) { it.id }.filter { it.time > cutoff }
            state = state.copy(
                waterSips = sips.ifEmpty { null },
                waterTarget = state.waterTarget ?: backup.waterTarget,
                waterGlass = state.waterGlass ?: backup.waterGlass,
                stepGoal = state.stepGoal ?: backup.stepGoal,
                checkInPace = state.checkInPace ?: backup.checkInPace,
            )
            backup.checkIns?.let { incoming ->
                val records = (state.checkIns ?: emptyList()).toMutableList()
                incoming.forEach { r -> if (records.none { it.id == r.id }) records += r }
                state = state.copy(checkIns = records.sortedBy { it.date }.takeLast(52))
            }
            backup.plans?.let { incoming ->
                val plans = mergeDays(state.plans ?: emptyMap(), incoming)
                state = state.copy(plans = plans.ifEmpty { null })
            }
            if (backup.measurementLog.isNotEmpty()) state = state.copy(measurements = mergeById(state.measurementLog, backup.measurementLog) { it.id })
            if (state.tray.isEmpty()) state = state.copy(tray = backup.tray)
            if (backup.weightLog.isNotEmpty()) state = state.copy(weights = mergeById(state.weightLog, backup.weightLog) { it.id })
            return state
        }
    }
}

fun <T> List<T>.replace(index: Int, value: T): List<T> = toMutableList().also { it[index] = value }

fun LocalDate.isToday(): Boolean = this == LocalDate.now(ZoneId.systemDefault())
