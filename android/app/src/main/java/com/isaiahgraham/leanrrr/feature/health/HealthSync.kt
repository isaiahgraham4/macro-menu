package com.isaiahgraham.leanrrr.feature.health

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.HydrationRecord
import androidx.health.connect.client.records.MealType
import androidx.health.connect.client.records.NutritionRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.request.AggregateGroupByPeriodRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import androidx.health.connect.client.units.Energy
import androidx.health.connect.client.units.Mass
import androidx.health.connect.client.units.Volume
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.AppData
import com.isaiahgraham.leanrrr.data.LogEntry
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Prefs
import com.isaiahgraham.leanrrr.data.WeightEntry
import com.isaiahgraham.leanrrr.data.dayKey
import com.isaiahgraham.leanrrr.data.hundredth
import com.isaiahgraham.leanrrr.data.parseDayKey
import com.isaiahgraham.leanrrr.feature.progress.logWeight
import com.isaiahgraham.leanrrr.feature.today.WaterWeight
import com.isaiahgraham.leanrrr.ui.AppLifecycle
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.Period
import java.time.ZoneId
import kotlin.reflect.KClass

/**
 * Health Connect (a port of HealthSync.swift): writes logged nutrition, water and weigh-ins, reads weight, steps and active
 * calories burned. Every record Leanrrr writes carries the ID of its log entry, weigh-in or water day as its client record ID
 * ("entry:<id>", "weight:<id>", "water:<day>"), so edits and deletes replace exactly those records.
 */
object HealthSync {
    const val ENABLED_KEY = "health.enabled"
    private const val IGNORED_KEY = "health.ignoredWeights"
    private const val ENTRY = "entry:"
    private const val WEIGHT = "weight:"
    private const val WATER = "water:"

    private val app get() = AppServices.app
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    /** Health updates run one after another, so a quick log-then-undo can't leave a stray record behind. */
    private val queue = Mutex()
    private var enabledState by mutableStateOf(runCatching { Prefs.bool(ENABLED_KEY) }.getOrDefault(false))

    /** Whether Health Connect is installed and usable on this phone. */
    val available: Boolean get() = sdkStatus == HealthConnectClient.SDK_AVAILABLE
    /** Health Connect is there but needs installing or updating from Google Play first. */
    val needsInstall: Boolean get() = sdkStatus == HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED
    /** Checked at start and each time the app comes back, since Health Connect can be installed or updated meanwhile. */
    private var sdkState by mutableStateOf<Int?>(null)
    private val sdkStatus: Int get() = sdkState ?: checkSdk()
    private fun checkSdk(): Int =
        runCatching { HealthConnectClient.getSdkStatus(app) }.getOrDefault(HealthConnectClient.SDK_UNAVAILABLE).also { sdkState = it }
    /** One refresh at a time, so two can't import the same weigh-in twice. */
    private val refreshing = Mutex()

    /** Whether the person has turned Health Connect on in Leanrrr. */
    val enabled: Boolean get() = enabledState && available
    /** Why the last connection attempt failed, to show the person. */
    var lastError by mutableStateOf<String?>(null); private set

    /** Steps by day (day key) for the last 90 days. Kept in memory only: health data isn't copied into Leanrrr's backups. */
    var steps by mutableStateOf<Map<String, Double>>(emptyMap()); private set
    /** True once a step read has completed this launch, so screens can tell "none yet" from "not loaded". */
    var stepsLoaded by mutableStateOf(false); private set
    /** Active calories burned by day for the last 90 days. Kept in memory only, like steps. */
    var activeEnergy by mutableStateOf<Map<String, Double>>(emptyMap()); private set
    var energyLoaded by mutableStateOf(false); private set

    private val client: HealthConnectClient by lazy { HealthConnectClient.getOrCreate(app) }

    private val writeTypes: List<KClass<out Record>> = listOf(NutritionRecord::class, WeightRecord::class, HydrationRecord::class)
    private val readTypes: List<KClass<out Record>> = listOf(WeightRecord::class, StepsRecord::class, ActiveCaloriesBurnedRecord::class)
    /** Everything Leanrrr asks Health Connect for. */
    val permissions: Set<String> =
        writeTypes.map { HealthPermission.getWritePermission(it) }.toSet() + readTypes.map { HealthPermission.getReadPermission(it) }

    /** Hooks the store: changes to the log, weigh-ins and water follow into Health Connect, and each return to the app reads again. */
    fun install() {
        val store = AppServices.store
        val previous = store.logsChanged
        store.logsChanged = { old, new -> previous?.invoke(old, new); follow(old, new) }
        AppLifecycle.onResume { checkSdk(); scope.launch { refresh() } }
    }

    private suspend fun granted(): Set<String> = runCatching { client.permissionController.getGrantedPermissions() }.getOrDefault(emptySet())

    /** After the permission screen: copies the last week's log to Health Connect and reads weights and activity. */
    suspend fun connect(grantedNow: Set<String>): Boolean {
        if (!available) { lastError = "Health Connect isn’t available on this phone."; return false }
        val all = grantedNow.ifEmpty { granted() }
        if (all.intersect(permissions).isEmpty()) { lastError = "Leanrrr wasn’t given access in Health Connect."; return false }
        lastError = null
        enabledState = true
        Prefs.set(ENABLED_KEY, true)
        val data = AppServices.store.data
        val start = dayKey(LocalDate.now().minusDays(7))
        queue.withLock {
            for ((day, entries) in data.logs) if (day >= start) for (entry in entries) replace(entry, day)
            for (weight in data.weightLog) if (weight.healthID == null) replace(weight)
            for ((day, millilitres) in data.water ?: emptyMap()) if (day >= start) replaceWater(day, millilitres)
        }
        refresh()
        return true
    }

    fun disconnect() {
        enabledState = false
        Prefs.set(ENABLED_KEY, false)
        steps = emptyMap(); stepsLoaded = false; activeEnergy = emptyMap(); energyLoaded = false
        AppServices.store.updateSteps(emptyMap())
        AppServices.store.updateActiveEnergy(emptyMap())
    }

    /** Mirrors a change in Leanrrr: removed or edited entries and weights come out of Health Connect, new versions go in. */
    private fun follow(old: AppData, new: AppData) {
        if (!enabled) return
        val before = entries(old); val after = entries(new)
        val beforeWeights = old.weightLog.filter { it.healthID == null }.associateBy { it.id }
        val afterWeights = new.weightLog.filter { it.healthID == null }.associateBy { it.id }
        // Weights imported from Health Connect that you delete in Leanrrr stay hidden rather than coming back on the next import.
        val hidden = old.weightLog.mapNotNull { it.healthID }.filter { id -> new.weightLog.none { it.healthID == id } }
        if (hidden.isNotEmpty()) Prefs.set(IGNORED_KEY, (ignored() + hidden).joinToString(","))
        // Water is one record a day, replaced whenever that day's total changes.
        val waterBefore = old.water ?: emptyMap(); val waterAfter = new.water ?: emptyMap()
        val waterDays = (waterBefore.keys + waterAfter.keys).filter { waterBefore[it] != waterAfter[it] }
        scope.launch {
            queue.withLock {
                for (day in waterDays) replaceWater(day, waterAfter[day] ?: 0.0)
                for ((id, entry) in after) if (before[id]?.first != entry.first) replace(entry.first, entry.second)
                for (id in before.keys) if (!after.containsKey(id)) deleteRecords(NutritionRecord::class, ENTRY + id)
                for ((id, weight) in afterWeights) if (beforeWeights[id] != weight) replace(weight)
                for (id in beforeWeights.keys) if (!afterWeights.containsKey(id)) deleteRecords(WeightRecord::class, WEIGHT + id)
            }
        }
    }

    /** Reads weight, steps and active energy again and writes anything new. */
    suspend fun refresh() {
        if (!enabled || !refreshing.tryLock()) return
        try {
            refreshActiveEnergy()
            importWeights()
            refreshSteps()
        } finally { refreshing.unlock() }
    }

    /** Each day's steps for the last 90 days. Health Connect adds up the phone, watch and other apps without counting a walk twice. */
    suspend fun refreshSteps() {
        if (!enabled) return
        val days = dailySums(StepsRecord.COUNT_TOTAL) { (it as? Long)?.toDouble() }
        steps = days ?: emptyMap()
        stepsLoaded = true
        AppServices.store.updateSteps(steps)
    }

    /** Each day's active calories burned for the last 90 days. */
    suspend fun refreshActiveEnergy() {
        if (!enabled) return
        val days = dailySums(ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL) { (it as? Energy)?.inKilocalories }
        activeEnergy = days ?: emptyMap()
        energyLoaded = true
        AppServices.store.updateActiveEnergy(activeEnergy)
    }

    /** Today's active energy, or null when none is recorded. */
    val activeEnergyToday: Double? get() = activeEnergy[dayKey(LocalDate.now())]?.takeIf { it > 0 }

    /**
     * Each day's total of a measure for the last 90 days, from every source together. Days with nothing are left out.
     * Null when Health Connect refuses, which is what a permission that wasn't given looks like.
     */
    private suspend fun <T : Any> dailySums(metric: androidx.health.connect.client.aggregate.AggregateMetric<T>, value: (Any?) -> Double?): Map<String, Double>? {
        val today = LocalDate.now()
        val request = AggregateGroupByPeriodRequest(
            metrics = setOf(metric),
            timeRangeFilter = TimeRangeFilter.between(today.minusDays(89).atStartOfDay(), LocalDateTime.now()),
            timeRangeSlicer = Period.ofDays(1),
        )
        val groups = runCatching { client.aggregateGroupByPeriod(request) }.getOrNull() ?: return null
        val days = mutableMapOf<String, Double>()
        for (group in groups) {
            val sum = value(group.result[metric]) ?: continue
            if (sum > 0) days[dayKey(group.startTime.toLocalDate())] = Math.round(sum).toDouble()
        }
        return days
    }

    private fun ignored(): Set<String> = (Prefs.string(IGNORED_KEY) ?: "").split(",").filter { it.isNotBlank() }.toSet()

    /** Imports weigh-ins other apps and scales saved to Health Connect in the last year. */
    private suspend fun importWeights() {
        val store = AppServices.store
        val since = Instant.now().minus(Duration.ofDays(365))
        val records = mutableListOf<WeightRecord>()
        var token: String? = null
        do {
            val response = runCatching {
                client.readRecords(ReadRecordsRequest(WeightRecord::class, TimeRangeFilter.after(since), pageToken = token))
            }.getOrNull() ?: return
            records += response.records
            token = response.pageToken
        } while (token != null)
        val ignored = ignored()
        val known = store.data.weightLog.mapNotNull { it.healthID }.toSet()
        val mine = app.packageName
        val fresh = records.filter { r ->
            r.metadata.dataOrigin.packageName != mine && r.metadata.clientRecordId?.startsWith(WEIGHT) != true &&
                r.metadata.id !in known && r.metadata.id !in ignored
        }.map {
            // Scales and other apps often store pounds converted to kg (181.5 lb is 82.3293 kg); Leanrrr keeps weights to 10 g.
            val entry = WeightEntry(date = it.time, kg = it.weight.inKilograms.hundredth, healthID = it.metadata.id)
            val water = WaterWeight.kilograms(entry.date, store.data)
            entry.copy(waterKG = if (water > 0) water else null)
        }.filter { it.isValid }.sortedBy { it.date }
        if (fresh.isEmpty()) return
        // A fresh weigh-in goes through Progress, so the goal and its moments follow it. A backlog (the first import) is added in one save.
        val recent = Instant.now().minus(Duration.ofDays(2))
        val backlog = fresh.filter { it.date < recent }
        if (backlog.isNotEmpty()) store.change { it.copy(weights = it.weightLog + backlog) }
        for (entry in fresh.filter { it.date >= recent }) {
            if (store.data.weightLog.none { it.healthID == entry.healthID }) store.logWeight(entry)
        }
    }

    private fun entries(data: AppData): Map<String, Pair<LogEntry, String>> {
        val result = mutableMapOf<String, Pair<LogEntry, String>>()
        for ((day, list) in data.logs) for (entry in list) result[entry.id] = entry to day
        return result
    }

    /** Logged time on the logged day; entries added to another day are placed at noon on that day. */
    private fun sampleTime(entry: LogEntry, day: String): Instant {
        if (dayKey(entry.time) == day) return entry.time
        return parseDayKey(day)?.atTime(12, 0)?.atZone(ZoneId.systemDefault())?.toInstant() ?: entry.time
    }

    private fun mealType(time: MealTime?): Int = when (time) {
        MealTime.BREAKFAST -> MealType.MEAL_TYPE_BREAKFAST
        MealTime.LUNCH -> MealType.MEAL_TYPE_LUNCH
        MealTime.DINNER -> MealType.MEAL_TYPE_DINNER
        MealTime.SNACKS -> MealType.MEAL_TYPE_SNACK
        null -> MealType.MEAL_TYPE_UNKNOWN
    }

    private suspend fun deleteRecords(type: KClass<out Record>, clientId: String) {
        runCatching { client.deleteRecords(type, emptyList(), listOf(clientId)) }
    }

    /** One meal as one nutrition record. Nutrients that some items don't list are left out rather than undercounted. */
    private suspend fun replace(entry: LogEntry, day: String) {
        deleteRecords(NutritionRecord::class, ENTRY + entry.id)
        val total = Nutrition(entry.items)
        fun nut(key: String): Double? = total.nut[key]?.takeIf { it > 0 && key !in total.partial }
        fun grams(value: Double?) = value?.takeIf { it > 0 }?.let { Mass.grams(it) }
        fun milligrams(value: Double?) = value?.takeIf { it > 0 }?.let { Mass.milligrams(it) }
        val start = sampleTime(entry, day)
        val offset = ZoneId.systemDefault().rules.getOffset(start)
        val record = NutritionRecord(
            startTime = start, startZoneOffset = offset, endTime = start.plusSeconds(60), endZoneOffset = offset,
            metadata = Metadata.manualEntry(clientRecordId = ENTRY + entry.id),
            energy = total.cal.takeIf { it > 0 }?.let { Energy.kilocalories(it) },
            protein = grams(total.p),
            totalCarbohydrate = if (total.missingCarbs) null else grams(total.c),
            totalFat = if (total.missingFat) null else grams(total.f),
            saturatedFat = grams(nut("sat")), transFat = grams(nut("trans")), sugar = grams(nut("sugar")), dietaryFiber = grams(nut("fibre")),
            sodium = milligrams(nut("sodium")), potassium = milligrams(nut("potassium")), calcium = milligrams(nut("calcium")),
            iron = milligrams(nut("iron")), cholesterol = milligrams(nut("chol")), caffeine = milligrams(nut("caffeine")),
            name = entry.name, mealType = mealType(entry.mealTime),
        )
        if (record.energy == null && record.protein == null && record.totalCarbohydrate == null && record.totalFat == null) return
        runCatching { client.insertRecords(listOf(record)) }
    }

    /** One water record for a day: its total, dated the start of that day. A day back at nothing has no record. */
    private suspend fun replaceWater(day: String, millilitres: Double) {
        deleteRecords(HydrationRecord::class, WATER + day)
        if (millilitres <= 0) return
        val start = parseDayKey(day)?.atStartOfDay(ZoneId.systemDefault())?.toInstant() ?: return
        val offset = ZoneId.systemDefault().rules.getOffset(start)
        val record = HydrationRecord(start, offset, start.plusSeconds(60), offset, Volume.milliliters(millilitres), Metadata.manualEntry(clientRecordId = WATER + day))
        runCatching { client.insertRecords(listOf(record)) }
    }

    private suspend fun replace(weight: WeightEntry) {
        deleteRecords(WeightRecord::class, WEIGHT + weight.id)
        val record = WeightRecord(weight.date, ZoneId.systemDefault().rules.getOffset(weight.date), Mass.kilograms(weight.kg), Metadata.manualEntry(clientRecordId = WEIGHT + weight.id))
        runCatching { client.insertRecords(listOf(record)) }
    }

    /** Removes every food, water and weight record Leanrrr saved. Records from other apps and devices aren't touched. */
    suspend fun deleteEverythingSaved() {
        if (!available) return
        // Deleting by time range only ever removes the calling app's own records.
        for (type in writeTypes) runCatching { client.deleteRecords(type, TimeRangeFilter.after(Instant.EPOCH)) }
    }

}

/** The Settings row that connects Health Connect, with the permission request. */
@Composable
fun HealthConnectSettings() {
    val c = Leanr.colours
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var failed by remember { mutableStateOf(false) }
    val permission = rememberLauncherForActivityResult(PermissionController.createRequestPermissionResultContract()) { granted ->
        scope.launch { if (!HealthSync.connect(granted)) failed = true }
    }
    LeanrSection(
        header = "Health Connect",
        footer = "Saves the food and water you log and your weigh-ins to Health Connect, and reads your weight, active energy and steps. " +
            "To choose exactly what Leanrrr can read or write, open Health Connect → App permissions → Leanrrr.",
    ) {
        when {
            HealthSync.available -> {
                Row(Modifier.fillMaxWidth().clickable { if (HealthSync.enabled) HealthSync.disconnect() else permission.launch(HealthSync.permissions) }
                    .padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.FavoriteBorder, null, tint = c.accent, modifier = Modifier.size(22.dp))
                    Spacer(Modifier.width(12.dp))
                    Text("Connect Health Connect", style = LeanrType.body, color = c.text, modifier = Modifier.weight(1f))
                    Switch(
                        checked = HealthSync.enabled,
                        onCheckedChange = { on -> if (on) permission.launch(HealthSync.permissions) else HealthSync.disconnect() },
                        colors = SwitchDefaults.colors(checkedTrackColor = c.accent),
                    )
                }
                HorizontalDivider(Modifier.padding(start = 50.dp), color = c.separator, thickness = 0.5.dp)
                Row(Modifier.fillMaxWidth().clickable {
                    try { context.startActivity(Intent(HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } catch (_: ActivityNotFoundException) {}
                }.padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.AutoMirrored.Filled.OpenInNew, null, tint = c.accent, modifier = Modifier.size(22.dp))
                    Spacer(Modifier.width(12.dp))
                    Text("Open Health Connect", style = LeanrType.body, color = c.accent)
                }
            }
            HealthSync.needsInstall -> Column(Modifier.fillMaxWidth().clickable {
                val uri = "market://details?id=com.google.android.apps.healthdata&url=healthconnect%3A%2F%2Fonboarding"
                try { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(uri)).setPackage("com.android.vending").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
                catch (_: ActivityNotFoundException) {
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=com.google.android.apps.healthdata")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }
            }.padding(horizontal = 16.dp, vertical = 12.dp)) {
                Text("Install Health Connect", style = LeanrType.body, color = c.accent)
                Text("Health Connect needs installing or updating from Google Play first.", style = LeanrType.caption, color = c.secondaryText)
            }
            else -> Text("Health Connect isn’t available on this phone.", style = LeanrType.body, color = c.secondaryText,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp))
        }
    }
    if (failed) AlertDialog(
        onDismissRequest = { failed = false },
        confirmButton = { TextButton(onClick = { failed = false }) { Text("OK", color = c.accent) } },
        title = { Text("Couldn’t connect to Health Connect") },
        text = { Text(HealthSync.lastError ?: "Check that Health Connect is set up on this phone, then try again.") },
    )
}
