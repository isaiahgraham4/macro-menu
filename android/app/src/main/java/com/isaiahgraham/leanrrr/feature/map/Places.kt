package com.isaiahgraham.leanrrr.feature.map

import android.Manifest
import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import com.isaiahgraham.leanrrr.AppServices
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.Locale
import kotlin.coroutines.resume
import kotlin.math.roundToInt

// A port of Places.swift. MapKit's search becomes the OpenStreetMap Overpass API (no key, nothing personal sent: only the
// point to search around), CLLocationManager becomes the fused location provider, and App Store links become Google Play.

/**
 * How to find a chain on OpenStreetMap and open its ordering app.
 * `match`: lowercased name fragments a place's name or brand must contain, so "Subway" doesn't match a train station.
 * `playPackage`: the chain's Android app on Google Play (checked on Google Play on 21 Nov 2026), or null when no app could be
 * verified, in which case "Open app" goes to the chain's website instead.
 */
data class ChainPlace(
    val query: String,
    val match: List<String>,
    val appName: String,
    val playPackage: String?,
    /** A web page to order from or read about the chain when there's no verified app. Falls back to the menu's own link. */
    val web: String? = null,
) {
    val launchTitle: String get() = if (playPackage != null) "Open $appName" else "$appName website"

    fun matches(name: String?): Boolean {
        val lower = (name ?: "").lowercase(Locale.ROOT)
        return match.any { lower.contains(it) }
    }

    companion object {
        /** Keyed by chain id in the menu files. Packages from Google Play searches in each chain's country, title and developer checked. */
        val all: Map<String, ChainPlace> = mapOf(
            "mcd" to ChainPlace("McDonald's", listOf("mcdonald"), "MyMacca's", "com.mcdonalds.au.gma"),
            "kfc" to ChainPlace("KFC", listOf("kfc"), "KFC", "com.kfcaus.ordering"),
            "hj" to ChainPlace("Hungry Jack's", listOf("hungry jack"), "Hungry Jack's", "com.webling.hungryjacks"),
            "sub" to ChainPlace("Subway", listOf("subway"), "Subway", "au.com.subcard.app"),
            "gyg" to ChainPlace("Guzman y Gomez", listOf("guzman", "gyg"), "GYG", "com.gyg.gomex"),
            "nandos" to ChainPlace("Nando's", listOf("nando"), "Nando's", "com.redcat.PeriPerks"),
            "oporto" to ChainPlace("Oporto", listOf("oporto"), "Oporto", "com.gruden.oporto"),
            "rr" to ChainPlace("Red Rooster", listOf("red rooster"), "Red Rooster", "com.gruden.redrooster"),
            "dominos" to ChainPlace("Domino's Pizza", listOf("domino"), "Domino's", "au.com.dominos.olo.android.app"),
            // TODO: no Spudbar app found on Google Play.
            "spud" to ChainPlace("Spudbar", listOf("spud"), "Spudbar", null, "https://www.spudbar.com.au/"),
            "zam" to ChainPlace("Zambrero", listOf("zambrero"), "Zambrero", "com.zambrero.ordering.app"),
            "boost" to ChainPlace("Boost Juice", listOf("boost juice"), "Boost Juice", "com.redcat.BoostApp"),
            "grilld" to ChainPlace("Grill'd", listOf("grill'd", "grilld", "grill’d"), "Grill'd", "com.grilld.grilld"),
            "schnitz" to ChainPlace("Schnitz", listOf("schnitz"), "Schnitz", "au.com.redcat.schnitz"),
            "betty" to ChainPlace("Betty's Burgers", listOf("betty's", "bettys", "betty’s"), "Betty's Burgers", "com.retailzoo.bettysburgers"),
            "fiveguys" to ChainPlace("Five Guys", listOf("five guys"), "Five Guys", "com.fiveguys.fiveguysuk"),
            "crust" to ChainPlace("Crust Pizza", listOf("crust"), "Crust", "au.com.crust.mobile"),
            "donutking" to ChainPlace("Donut King", listOf("donut king"), "Donut King", "com.rfg.donutking"),
            "michels" to ChainPlace("Michel's Patisserie", listOf("michel's", "michels", "michel’s"), "Michel's Loyalty", "com.rfg.michels"),
            "brumbys" to ChainPlace("Brumby's Bakery", listOf("brumby"), "Brumby's Rewards", "com.rfg.brumbys"),
            "soul" to ChainPlace("Soul Origin", listOf("soul origin"), "Soul Origin", "com.shift8.soulorigin"),
            "rolld" to ChainPlace("Roll'd", listOf("roll'd", "rolld", "roll’d"), "Roll'd", "rolld.abacus.co"),
            "thisbowl" to ChainPlace("THISBOWL", listOf("thisbowl", "this bowl", "fishbowl"), "THISBOWL", "com.bitebusiness.fishbowl"),
            "coles" to ChainPlace("Coles Supermarket", listOf("coles"), "Coles", "com.coles.android.shopmate"),
            "woolworths" to ChainPlace("Woolworths", listOf("woolworths"), "Woolworths", "com.woolworths"),
            // United States.
            "us-mcd" to ChainPlace("McDonald's", listOf("mcdonald"), "McDonald's", "com.mcdonalds.app"),
            "us-cfa" to ChainPlace("Chick-fil-A", listOf("chick-fil-a", "chick fil a", "chickfila"), "Chick-fil-A", "com.chickfila.cfaflagship"),
            "us-wendys" to ChainPlace("Wendy's", listOf("wendy's", "wendys", "wendy’s"), "Wendy's", "com.wendys.nutritiontool"),
            "us-tacobell" to ChainPlace("Taco Bell", listOf("taco bell"), "Taco Bell", "com.tacobell.ordering"),
            "us-panda" to ChainPlace("Panda Express", listOf("panda express"), "Panda Express", "com.pandaexpress.app"),
            "us-bk" to ChainPlace("Burger King", listOf("burger king"), "Burger King", "com.emn8.mobilem8.nativeapp.bk"),
            "us-popeyes" to ChainPlace("Popeyes", listOf("popeyes"), "Popeyes", "com.emn8.mobilem8.nativeapp.popeyes"),
            // Canada, the UK and New Zealand.
            "ca-mcd" to ChainPlace("McDonald's", listOf("mcdonald"), "McDonald's", "com.mcdonalds.superapp"),
            "ca-bk" to ChainPlace("Burger King", listOf("burger king"), "Burger King", "com.emn8.mobilem8.nativeapp.bkca"),
            "ca-tims" to ChainPlace("Tim Hortons", listOf("tim hortons", "tim horton"), "Tim Hortons", "digital.rbi.timhortons"),
            "uk-mcd" to ChainPlace("McDonald's", listOf("mcdonald"), "McDonald's", "com.mcdonalds.app.uk"),
            "uk-greggs" to ChainPlace("Greggs", listOf("greggs"), "Greggs", "com.mobile5.greggs"),
            "nz-mcd" to ChainPlace("McDonald's", listOf("mcdonald"), "McDonald's", "com.mcdonalds.mobileapp"),
            "nz-dominos" to ChainPlace("Domino's Pizza", listOf("domino"), "Domino's", "au.com.dominos.olo.android.app.nz"),
            // South Africa.
            "za-mcd" to ChainPlace("McDonald's", listOf("mcdonald"), "McDonald's", "com.mcdonalds.mobileapp"),
            "za-nandos" to ChainPlace("Nando's", listOf("nando"), "Nando's", "co.za.nandos.nandosapp"),
            "za-wimpy" to ChainPlace("Wimpy", listOf("wimpy"), "Wimpy Rewards", "za.co.wigroup.wimpy"),
            "za-debonairs" to ChainPlace("Debonairs Pizza", listOf("debonairs"), "Debonairs Pizza", "mobi.debonairspizza.iosapp"),
            "za-kauai" to ChainPlace("Kauai", listOf("kauai"), "Kauai", "kauai.juice"),
            // India. TODO: iOS links the global McDonald's app; on Google Play India's is a different (McDelivery) app, not verified.
            "in-mcd" to ChainPlace("McDonald's", listOf("mcdonald"), "McDonald's", null),
            "in-kfc" to ChainPlace("KFC", listOf("kfc"), "KFC India", "com.yum.kfc"),
            "in-pizzahut" to ChainPlace("Pizza Hut", listOf("pizza hut"), "Pizza Hut India", "com.phdv.universal"),
        )
    }
}

/** One restaurant found on OpenStreetMap. */
data class NearbyPlace(
    val id: String,
    val chain: String,
    val name: String,
    val latitude: Double,
    val longitude: Double,
    val address: String,
    /** OpenStreetMap's `opening_hours` tag as written ("Mo-Su 06:00-23:00", "24/7"), when the place has one. */
    val hours: String?,
    val distance: Double,
) {
    val distanceText: String get() = distanceText(distance)

    /** Opens the phone's maps app with directions, or OpenStreetMap in the browser when there's none. */
    fun directions(context: Context) {
        val label = Uri.encode(name)
        val geo = Intent(Intent.ACTION_VIEW, Uri.parse("geo:$latitude,$longitude?q=$latitude,$longitude($label)")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try { context.startActivity(geo) } catch (_: ActivityNotFoundException) {
            openUrl(context, "https://www.openstreetmap.org/directions?to=$latitude%2C$longitude")
        }
    }

    companion object {
        /** "350 m" or "2.4 km", the way road distances are written in Australia. */
        fun distanceText(metres: Double): String = when {
            metres < 1000 -> "${((metres / 10).roundToInt() * 10).coerceAtLeast(10)} m"
            metres < 10_000 -> String.format(Locale.US, "%.1f km", metres / 1000)
            else -> "${(metres / 1000).roundToInt()} km"
        }
    }
}

internal fun openUrl(context: Context, url: String) {
    try { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } catch (_: ActivityNotFoundException) {}
}

/** Opens the chain's app when it's installed, otherwise its Google Play page; chains without a verified app open their website. */
fun openChainApp(context: Context, chain: String) {
    val place = ChainPlace.all[chain] ?: return
    val pkg = place.playPackage
    if (pkg == null) {
        (place.web ?: AppServices.store.chain(chain)?.url)?.let { openUrl(context, it) }
        return
    }
    // Starting another app's launcher activity isn't limited by package visibility, so no installed-app list is needed.
    val launch = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER).setPackage(pkg).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    try { context.startActivity(launch); return } catch (_: ActivityNotFoundException) {} catch (_: SecurityException) {}
    try {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$pkg")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (_: ActivityNotFoundException) {
        openUrl(context, "https://play.google.com/store/apps/details?id=$pkg")
    }
}

/** Looking up restaurants and places on OpenStreetMap. Requests carry the app's package name as the user agent and nothing else. */
object Overpass {
    /** The main Overpass server, then a public mirror: the main one is often busy and can take 30 s or more. */
    private val ENDPOINTS = listOf("https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter")
    const val RADIUS = 15_000
    private val json = Json { ignoreUnknownKeys = true }

    private fun userAgent(): String = AppServices.app.packageName

    /** Every chain's restaurants within about 15 km of a point, closest first, grouped by chain. Null when the search failed. */
    suspend fun find(chains: List<String>, latitude: Double, longitude: Double): Map<String, List<NearbyPlace>>? = withContext(Dispatchers.IO) {
        val places = chains.mapNotNull { id -> ChainPlace.all[id]?.let { id to it } }
        if (places.isEmpty()) return@withContext emptyMap()
        val fragments = places.flatMap { it.second.match }.distinct().joinToString("|") { regexEscape(it) }
        val around = "around:$RADIUS,$latitude,$longitude"
        // Restaurants, cafés and shops whose name or brand contains a chain's words. A place needs an amenity or shop tag,
        // so a "Subway" train station or a street called Crust Lane isn't a restaurant.
        val query = """
            [out:json][timeout:40];
            (
              nwr["amenity"~"^(fast_food|restaurant|cafe|ice_cream|food_court)${'$'}"]["name"~"$fragments",i]($around);
              nwr["amenity"~"^(fast_food|restaurant|cafe|ice_cream|food_court)${'$'}"]["brand"~"$fragments",i]($around);
              nwr["shop"]["name"~"$fragments",i]($around);
            );
            out center tags;
        """.trimIndent()
        // Restaurants, cafés and food courts are filtered first (an amenity tag on its own is quick for Overpass); the name match runs on those.
        val form = "data=" + URLEncoder.encode(query, "UTF-8")
        val body = ENDPOINTS.firstNotNullOfOrNull { endpoint -> runCatching { post(endpoint, form) }.onFailure { android.util.Log.w("LeanrMap", "Overpass $endpoint failed: $it\n$query") }.getOrNull() } ?: return@withContext null
        val elements = runCatching { json.parseToJsonElement(body).jsonObject["elements"]?.jsonArray }.getOrNull() ?: return@withContext null
        val here = FloatArray(1)
        val found = mutableMapOf<String, MutableList<NearbyPlace>>()
        for (element in elements) {
            val obj = element.jsonObject
            val tags = obj["tags"]?.jsonObject ?: continue
            val center = obj["center"]?.jsonObject
            val lat = (obj["lat"] ?: center?.get("lat"))?.jsonPrimitive?.doubleOrNull ?: continue
            val lon = (obj["lon"] ?: center?.get("lon"))?.jsonPrimitive?.doubleOrNull ?: continue
            val name = tags.text("name")
            val brand = tags.text("brand")
            val chain = places.firstOrNull { (_, place) -> place.matches(name) || place.matches(brand) }?.first ?: continue
            Location.distanceBetween(latitude, longitude, lat, lon, here)
            if (here[0] > RADIUS) continue
            val id = "${obj["type"]?.jsonPrimitive?.contentOrNull}/${obj["id"]?.jsonPrimitive?.contentOrNull}"
            found.getOrPut(chain) { mutableListOf() } += NearbyPlace(
                id = id, chain = chain, name = name ?: brand ?: AppServices.store.chainName(chain), latitude = lat, longitude = lon,
                address = address(tags), hours = tags.text("opening_hours"), distance = here[0].toDouble(),
            )
        }
        // Every chain asked about gets an answer, empty when there's none within 15 km.
        places.associate { (id, _) -> id to (found[id]?.sortedBy { it.distance } ?: emptyList()) }
    }

    private fun JsonObject.text(key: String): String? = this[key]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() }

    private fun address(tags: JsonObject): String {
        val street = listOfNotNull(tags.text("addr:housenumber"), tags.text("addr:street")).joinToString(" ")
        val town = tags.text("addr:suburb") ?: tags.text("addr:city")
        return listOf(street, town ?: "").filter { it.isNotBlank() }.joinToString(", ")
    }

    private fun regexEscape(text: String): String = text.replace(Regex("""[\\.^$|?*+()\[\]{}"]""")) { "\\\\" + it.value }

    private fun post(url: String, form: String): String {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 15_000
            connection.readTimeout = 45_000
            connection.doOutput = true
            connection.setRequestProperty("User-Agent", userAgent())
            connection.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
            connection.outputStream.use { it.write(form.toByteArray()) }
            if (connection.responseCode !in 200..299) error("HTTP ${connection.responseCode}")
            return connection.inputStream.bufferedReader().use { it.readText() }
        } finally { connection.disconnect() }
    }

    private fun get(url: String): String {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 15_000
            connection.readTimeout = 20_000
            connection.setRequestProperty("User-Agent", userAgent())
            if (connection.responseCode !in 200..299) error("HTTP ${connection.responseCode}")
            return connection.inputStream.bufferedReader().use { it.readText() }
        } finally { connection.disconnect() }
    }

    data class Spot(val name: String, val latitude: Double, val longitude: Double)

    /**
     * Finds a suburb, address or place typed into the map's search: the phone's geocoder first, then OpenStreetMap's
     * Nominatim on phones without one. Only the words typed are sent. Null when nothing matched.
     */
    @Suppress("DEPRECATION")
    suspend fun geocode(context: Context, text: String, near: Location?): Spot? = withContext(Dispatchers.IO) {
        if (Geocoder.isPresent()) {
            val geocoder = Geocoder(context, Locale.getDefault())
            val results = runCatching {
                if (near != null) geocoder.getFromLocationName(text, 1, near.latitude - 0.5, near.longitude - 0.5, near.latitude + 0.5, near.longitude + 0.5)
                    ?.takeIf { it.isNotEmpty() } ?: geocoder.getFromLocationName(text, 1)
                else geocoder.getFromLocationName(text, 1)
            }.getOrNull()
            results?.firstOrNull()?.let { a ->
                val name = a.featureName?.takeIf { it.isNotBlank() && it.toIntOrNull() == null } ?: a.locality ?: text
                return@withContext Spot(name, a.latitude, a.longitude)
            }
        }
        val region = AppServices.store.region.raw.lowercase(Locale.ROOT)
        val url = "https://nominatim.openstreetmap.org/search?format=jsonv2&limit=1&countrycodes=$region&q=" + URLEncoder.encode(text, "UTF-8")
        val body = runCatching { get(url) }.getOrNull() ?: return@withContext null
        val first = runCatching { json.parseToJsonElement(body).jsonArray.firstOrNull()?.jsonObject }.getOrNull() ?: return@withContext null
        val lat = first["lat"]?.jsonPrimitive?.contentOrNull?.toDoubleOrNull() ?: return@withContext null
        val lon = first["lon"]?.jsonPrimitive?.contentOrNull?.toDoubleOrNull() ?: return@withContext null
        val name = first["name"]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() }
            ?: first["display_name"]?.jsonPrimitive?.contentOrNull?.substringBefore(",") ?: text
        Spot(name, lat, lon)
    }
}

/** The user's location (only while the app is in use) and the nearest restaurants of each chain. LocationStore in Places.swift. */
object NearbyPlaces {
    var location by mutableStateOf<Location?>(null); private set
    var places by mutableStateOf<Map<String, List<NearbyPlace>>>(emptyMap()); private set
    /** True while a search for restaurants near the user is running. */
    var loading by mutableStateOf(false); private set
    var failed by mutableStateOf(false); private set
    /** True once the person has said no and Android won't ask again, so only Settings can turn it on. */
    var denied by mutableStateOf(false)
    /** Bumped when permission changes, so screens re-read it. */
    var permissionRevision by mutableStateOf(0)
    private var locating = false
    private var searchedFor: Location? = null

    fun isAuthorized(context: Context): Boolean {
        @Suppress("UNUSED_EXPRESSION") permissionRevision
        return ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
    }

    fun nearest(chain: String): NearbyPlace? = places[chain]?.firstOrNull()

    /** Fetches the current location about once; small moves (under 300 m) keep the current results. */
    @SuppressLint("MissingPermission")
    suspend fun request(context: Context) {
        if (!isAuthorized(context) || locating) return
        locating = true
        failed = false
        val client = LocationServices.getFusedLocationProviderClient(context)
        val token = CancellationTokenSource()
        val found: Location? = try {
            suspendCancellableCoroutine { cont ->
                cont.invokeOnCancellation { token.cancel() }
                client.getCurrentLocation(Priority.PRIORITY_BALANCED_POWER_ACCURACY, token.token)
                    .addOnSuccessListener { cont.resume(it) }
                    .addOnFailureListener { cont.resume(null) }
            } ?: suspendCancellableCoroutine { cont ->
                client.lastLocation.addOnSuccessListener { cont.resume(it) }.addOnFailureListener { cont.resume(null) }
            }
        } catch (_: SecurityException) { null } finally { locating = false }
        if (found == null) { if (location == null) failed = true; return }
        val old = location
        if (old != null && old.distanceTo(found) < 300) return
        location = found
        places = emptyMap()
    }

    /** Searches OpenStreetMap for `chains` around the current location, once per location. */
    suspend fun load(chains: List<String>) {
        val here = location ?: return
        if (loading || (searchedFor === here && chains.all { places.containsKey(it) })) return
        loading = true
        val found = Overpass.find(chains, here.latitude, here.longitude)
        loading = false
        if (here !== location) return
        searchedFor = here
        if (found != null) places = places + found
    }

    /** Tells screens to read the permission again, after the system dialog closes. */
    fun permissionChanged() { permissionRevision += 1 }
}
