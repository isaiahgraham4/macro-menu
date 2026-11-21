package com.isaiahgraham.leanrrr.feature.find

import android.net.Uri

/**
 * Whether a restaurant is likely to deliver to you, from how far away it is (Delivery.swift). Delivery apps don't let other apps
 * check an address, so this is an estimate: they usually deliver within about 5 km, sometimes up to about 8 km.
 */
sealed class Delivery {
    data class Likely(val metres: Double) : Delivery()
    data class Maybe(val metres: Double) : Delivery()
    data object TooFar : Delivery()

    val text: String
        get() = when (this) {
            is Likely -> "Delivery likely"
            is Maybe -> "Delivery may reach you"
            TooFar -> "Probably too far to deliver"
        }

    val available: Boolean get() = this !is TooFar

    companion object {
        const val LIKELY_WITHIN = 5_000.0
        const val MAYBE_WITHIN = 8_000.0

        /** `metres` is null when there's no restaurant of that chain nearby. */
        fun estimate(metres: Double?): Delivery {
            if (metres == null || metres > MAYBE_WITHIN) return TooFar
            return if (metres <= LIKELY_WITHIN) Likely(metres) else Maybe(metres)
        }
    }
}

/** A delivery app to check and order in. Links open the app when it's installed, otherwise its website. */
data class DeliveryApp(val name: String, val search: (String) -> String?) {
    companion object {
        val all: List<DeliveryApp> = listOf(
            DeliveryApp("Uber Eats") { query -> "https://www.ubereats.com/au/search?q=" + Uri.encode(query) },
            DeliveryApp("DoorDash") { query -> "https://www.doordash.com/search/store/" + Uri.encode(query) + "/" },
            // Menulog asks for your address before it can search.
            DeliveryApp("Menulog") { "https://www.menulog.com.au/" },
        )
    }
}
