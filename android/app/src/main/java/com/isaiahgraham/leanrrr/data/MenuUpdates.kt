package com.isaiahgraham.leanrrr.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.time.Instant
import java.time.OffsetDateTime

/**
 * One of the food files built into the app that can also arrive newer from Leanrrr's Supabase project:
 * each country's restaurant menu, everyday foods, USDA survey foods and supermarket foods. A port of MenuUpdates.swift.
 */
sealed class FoodDataset {
    data class Menu(val region: MenuRegion) : FoodDataset()
    data object Everyday : FoodDataset()
    data object Survey : FoodDataset()
    data object Supermarket : FoodDataset()

    /** The dataset's id on Supabase (`public.datasets`). */
    val id: String
        get() = when (this) {
            is Menu -> "menu-${region.raw}"
            Everyday -> "generic"
            Survey -> "survey"
            Supermarket -> "supermarket"
        }

    fun cacheFile(context: Context): File = File(context.filesDir, "Updates/$id.json")
    val isList: Boolean get() = this == Everyday || this == Survey
}

/** Revisions and publish times of the bundled food files that don't carry their own (`FoodLists.json`). */
@Serializable
data class FoodListVersion(val revision: String? = null, val published: String? = null)

/**
 * Fetches newer food data, so new items and corrected figures arrive without an app update. The requests carry nothing
 * about the user, only the app's public read-only key. A download is only used if it's a format this version understands,
 * is newer than what's in use, and every item checks out. The copy built into the app is always there to fall back on.
 */
object MenuUpdates {
    const val SERVER = "https://dmfmrqvmwvabzkqgdbdw.supabase.co/rest/v1/"
    /** The project's publishable key: it can only read foods (row-level security), so it's safe to ship in the app. */
    const val PUBLISHABLE_KEY = "sb_publishable_rV4qINsqDY5CRsh88QzcGQ_2KFiIuJE"
    const val FORMAT = 1
    private const val INTERVAL_MS = 6L * 60 * 60 * 1000
    private const val MAX_BYTES = 16_000_000
    private const val CLOCK_SLACK_S = 24L * 60 * 60

    fun url(dataset: FoodDataset) = "${SERVER}rpc/dataset?id=${URLEncoder.encode(dataset.id, "UTF-8")}"
    fun versionUrl(dataset: FoodDataset) = "${SERVER}datasets?id=eq.${URLEncoder.encode(dataset.id, "UTF-8")}&select=revision,published"

    fun publishedDate(text: String?): Instant? = text?.let { runCatching { OffsetDateTime.parse(it).toInstant() }.getOrNull() }

    /** Whether `candidate` can replace `current`. */
    fun acceptable(candidate: MenuCatalog, current: MenuCatalog, now: Instant = Instant.now()): Boolean {
        if (candidate.format != FORMAT || candidate.foods.isEmpty() || candidate.chains.isEmpty() != current.chains.isEmpty() ||
            candidate.foods.size < current.foods.size / 2) return false
        val latest = now.plusSeconds(CLOCK_SLACK_S)
        if (candidate.published != null) {
            val date = publishedDate(candidate.published) ?: return false
            if (date > latest) return false
            val mine = publishedDate(current.published)
            if (mine != null && mine <= latest && date <= mine) return false
        } else if (current.published != null) return false
        val chains = candidate.chains.map { it.id }.toSet()
        val ids = candidate.foods.map { it.id }
        val known: (Food) -> Boolean = if (chains.isEmpty()) { f -> f.chain == "generic" } else { f -> f.chain in chains }
        return ids.toSet().size == ids.size && candidate.foods.all { it.isValid && known(it) }
    }

    @Serializable private data class Version(val revision: String? = null, val published: String? = null)

    private fun get(url: String): ByteArray? {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 30_000; readTimeout = 30_000; useCaches = false
            setRequestProperty("apikey", PUBLISHABLE_KEY)
            setRequestProperty("Accept", "application/json")
        }
        return try {
            if (connection.responseCode != 200) return null
            connection.inputStream.use { input ->
                val bytes = input.readBytes()
                if (bytes.size > MAX_BYTES) null else bytes
            }
        } catch (_: Exception) { null } finally { connection.disconnect() }
    }

    /** Downloads a dataset if it's been a while and Supabase has a newer one, and hands it back. */
    suspend fun check(context: Context, dataset: FoodDataset, current: MenuCatalog, force: Boolean = false): MenuCatalog? = withContext(Dispatchers.IO) {
        val checkedKey = "data.lastChecked.${dataset.id}"
        val now = System.currentTimeMillis()
        val last = Prefs.long(checkedKey)
        if (!force && last != null && now - last < INTERVAL_MS) return@withContext null
        // First the revision and date alone (a few bytes): the same or an older dataset isn't downloaded at all.
        val versionBytes = get(versionUrl(dataset)) ?: return@withContext null
        Prefs.set(checkedKey, now)
        val version = runCatching { LeanrJson.decodeFromString<List<Version>>(versionBytes.decodeToString()).firstOrNull() }.getOrNull()
            ?: return@withContext null
        if (version.revision != null && version.revision == current.revision) return@withContext null
        val theirs = publishedDate(version.published); val mine = publishedDate(current.published)
        if (theirs != null && mine != null && theirs <= mine) return@withContext null
        val bytes = get(url(dataset)) ?: return@withContext null
        val catalog = runCatching { LeanrJson.decodeFromString<MenuCatalog>(bytes.decodeToString()) }.getOrNull() ?: return@withContext null
        if (!acceptable(catalog, current)) return@withContext null
        runCatching {
            val file = dataset.cacheFile(context)
            file.parentFile?.mkdirs()
            val temp = File(file.parentFile, file.name + ".tmp")
            temp.writeBytes(bytes)
            temp.renameTo(file)
        }.getOrElse { return@withContext null }
        catalog
    }

    /** The newer of the built-in data and a previously downloaded copy. */
    fun best(context: Context, dataset: FoodDataset, bundled: MenuCatalog): MenuCatalog {
        val file = dataset.cacheFile(context)
        if (!file.exists()) return bundled
        val cached = runCatching { LeanrJson.decodeFromString<MenuCatalog>(file.readText()) }.getOrNull() ?: return bundled
        return if (acceptable(cached, bundled)) cached else bundled
    }
}
