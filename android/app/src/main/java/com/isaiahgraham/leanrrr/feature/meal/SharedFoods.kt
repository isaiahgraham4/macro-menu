package com.isaiahgraham.leanrrr.feature.meal

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.AppData
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.Prefs

// A port of SharedFoods.swift. On iOS, foods people choose to share go to a public CloudKit database and everyone else sees
// them in search and barcode scans as "Community" foods. Android has no CloudKit and no backend exists yet, so:
//   - the rules (SharingRules), the agreement, the "shared" flag on your foods, hiding and reporting are all here;
//   - NETWORK SIDE IS A NO-OP: nothing is uploaded or fetched, and turning sharing on reports [UNAVAILABLE].
// When a backend exists, implement [SharedFoodBackend] and swap it in for [NoSharedFoods].

/** A food someone shared, as read back from the shared database. */
data class SharedFood(
    /** "food-" plus the sharer's own food ID, so editing the food replaces the shared copy. */
    val recordName: String,
    /** The sharer's anonymous ID for this app. Only used to hide everything from someone. */
    val creator: String,
    val food: Food,
    val modified: java.time.Instant,
)

data class SharedFoodReport(val recordName: String, val reporter: String)

enum class ShareReportReason(val title: String) {
    WRONG_NUMBERS("The numbers are wrong"),
    OFFENSIVE("Offensive or abusive"),
    SPAM("Spam or advertising"),
    OTHER("Something else"),
}

/** Where shared foods live. */
interface SharedFoodBackend {
    /** Null when sharing can be used now, otherwise why not. */
    suspend fun canShare(): String?
    suspend fun everything(): Triple<List<SharedFood>, List<SharedFoodReport>, Set<String>>
    suspend fun save(food: Food)
    suspend fun delete(recordName: String)
    suspend fun report(recordName: String, reason: ShareReportReason)
}

/** NO-OP BACKEND: there's no shared food service on Android yet. Reads are empty and writes go nowhere. */
object NoSharedFoods : SharedFoodBackend {
    override suspend fun canShare(): String = CommunityFoods.UNAVAILABLE
    override suspend fun everything() = Triple(emptyList<SharedFood>(), emptyList<SharedFoodReport>(), emptySet<String>())
    override suspend fun save(food: Food) {}
    override suspend fun delete(recordName: String) {}
    override suspend fun report(recordName: String, reason: ShareReportReason) {}
}

/** Shared foods for search and barcode scans, plus the foods you choose to share. Same preference keys as iOS. */
object CommunityFoods {
    const val SHOW_KEY = "community.show"
    const val AGREED_KEY = "community.agreed"
    private const val BLOCKED_KEY = "community.blocked"
    private const val REPORTED_KEY = "community.reported"
    const val UNAVAILABLE = "Sharing isn't available on Android yet."

    var backend: SharedFoodBackend = NoSharedFoods

    private var cache: List<SharedFood> = emptyList()
    private var reports: List<SharedFoodReport> = emptyList()
    private var removed: Set<String> = emptySet()
    var problem by mutableStateOf<String?>(null); private set

    /** Show other people's foods in search and barcode scans. */
    var show: Boolean
        get() = Prefs.bool(SHOW_KEY, true)
        set(value) { Prefs.set(SHOW_KEY, value); publish() }

    val agreed: Boolean get() = Prefs.bool(AGREED_KEY, false)
    fun agree() = Prefs.set(AGREED_KEY, true)

    /** People whose foods you've hidden. */
    val blocked: Set<String> get() = Prefs.string(BLOCKED_KEY)?.split("\n")?.filter { it.isNotEmpty() }?.toSet() ?: emptySet()
    /** Foods you've reported, hidden for you straight away. */
    val reported: Set<String> get() = Prefs.string(REPORTED_KEY)?.split("\n")?.filter { it.isNotEmpty() }?.toSet() ?: emptySet()

    /** Foods others shared that you can see: not removed, not reported by several people or by you, not from someone you've hidden, not your own. */
    val visible: List<SharedFood>
        get() {
            if (!show) return emptyList()
            val hidden = SharingRules.hiddenByReports(reports.map { it.recordName to it.reporter })
            val mine = AppServices.store.data.foods.map { sharedRecordName(it.id) }.toSet()
            return cache.filter { item ->
                item.recordName !in removed && item.recordName !in hidden && item.recordName !in reported &&
                    item.creator !in blocked && item.recordName !in mine
            }
        }

    private fun publish() { AppServices.store.useCommunity(visible.map { it.food }) }

    /** Fetches the shared list. A no-op until a backend exists. */
    suspend fun refresh() {
        try {
            val (foods, r, gone) = backend.everything()
            cache = foods; reports = r; removed = gone
            publish()
        } catch (e: Exception) { problem = "Shared foods couldn't update. ${e.message ?: ""}".trim() }
    }

    /** Checked before the first share, so the switch can say why it can't turn on. */
    suspend fun canShare(): String? = backend.canShare()

    suspend fun report(food: Food, reason: ShareReportReason): Boolean {
        val name = recordName(food) ?: return false
        Prefs.set(REPORTED_KEY, (reported + name).joinToString("\n"))
        publish()
        return try { backend.report(name, reason); true } catch (e: Exception) { problem = e.message; false }
    }

    fun block(food: Food) {
        val who = food.contributor ?: cache.firstOrNull { it.food.id == food.id }?.creator ?: return
        Prefs.set(BLOCKED_KEY, (blocked + who).joinToString("\n"))
        publish()
    }

    fun unblockEveryone() {
        Prefs.remove(BLOCKED_KEY); Prefs.remove(REPORTED_KEY)
        publish()
    }

    private fun recordName(food: Food): String? =
        if (food.chain == Food.COMMUNITY && food.id.startsWith("community:")) food.id.removePrefix("community:") else null

    /** Called after local changes on iOS to upload newly shared foods and take down unshared ones. NO-OP on Android for now. */
    @Suppress("UNUSED_PARAMETER")
    fun follow(old: AppData, new: AppData) {}

    /** For Delete all my data: takes down every food you shared. Nothing was ever uploaded from Android, so it's always done. */
    @Suppress("UNUSED_PARAMETER")
    suspend fun deleteAllShared(foods: List<Food>): Boolean = true
}
