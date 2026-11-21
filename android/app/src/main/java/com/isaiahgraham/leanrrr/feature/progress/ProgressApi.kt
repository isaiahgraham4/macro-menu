package com.isaiahgraham.leanrrr.feature.progress

import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.AppStore
import com.isaiahgraham.leanrrr.data.Moment
import com.isaiahgraham.leanrrr.data.WeightEntry
import com.isaiahgraham.leanrrr.data.kgText
import com.isaiahgraham.leanrrr.data.offerWeek
import com.isaiahgraham.leanrrr.data.offerYear
import com.isaiahgraham.leanrrr.data.weighInMoment
import com.isaiahgraham.leanrrr.feature.today.WaterWeight
import com.isaiahgraham.leanrrr.ui.AppLifecycle

// Progress's entry points for the rest of the app (cross-feature signatures are fixed; see PORTING.md).

/**
 * Logs a weigh-in, with an estimate of how much of it is water drunk in the hours before (see WaterWeight), and shows how far
 * it's come towards the goal weight unless reaching the goal is already being marked (AppStore.logWeight).
 */
fun AppStore.logWeight(entry: WeightEntry): Boolean {
    var value = entry
    if (value.waterKG == null) {
        val water = WaterWeight.kilograms(entry.date, data)
        value = value.copy(waterKG = if (water > 0) water else null)
    }
    if (!change(undo = "Logged ${value.kg.kgText} kg") { it.copy(weights = it.weightLog + value) }) return false
    if (moments.none { it is Moment.GoalReached }) data.weighInMoment?.let { moments += it }
    return true
}

/** Shows last week's card on the first open of a new week, and the year's in December, when enough was logged. */
fun AppStore.offerReviews() {
    if (!launchSettled) return
    var updated = data
    val offered = mutableListOf<Moment>()
    updated.offerYear()?.let { (marked, moment) -> updated = marked; offered += moment }
    updated.offerWeek()?.let { (marked, moment) -> updated = marked; offered += moment }
    if (offered.isEmpty() || !change { updated }) return
    moments += offered
}

/** Hooks Progress into the app: the weekly and yearly cards are offered each time the app comes to the front. */
object ProgressFeature {
    fun install() {
        AppLifecycle.onResume { AppServices.store.offerReviews() }
    }
}
