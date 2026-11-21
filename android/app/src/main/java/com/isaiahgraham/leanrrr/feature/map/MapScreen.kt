package com.isaiahgraham.leanrrr.feature.map

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color as AndroidColor
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DeliveryDining
import androidx.compose.material.icons.filled.Directions
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.outlined.LocationOn
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.AppData
import com.isaiahgraham.leanrrr.data.Goals
import com.isaiahgraham.leanrrr.data.MenuRegion
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Prefs
import com.isaiahgraham.leanrrr.data.dayKey
import com.isaiahgraham.leanrrr.data.mealText
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.feature.find.DietFilter
import com.isaiahgraham.leanrrr.feature.find.FindQuery
import com.isaiahgraham.leanrrr.feature.find.FoodDetailScreen
import com.isaiahgraham.leanrrr.feature.find.MealFinder
import com.isaiahgraham.leanrrr.feature.find.MealMatch
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.ui.components.FoodRow
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.components.NutritionView
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.osmdroid.config.Configuration
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.CustomZoomButtonsController
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker
import java.time.LocalTime
import kotlin.math.min

// A port of NearbyView.swift: the closest restaurant of each chain, near you or near a place you search for, with an order
// that fits what's left today. OpenStreetMap tiles through osmdroid stand in for MapKit.

private const val LOCATION_ASKED_KEY = "map.locationAsked"

private data class Area(val name: String, val latitude: Double, val longitude: Double)

private data class FitsRequest(
    val chains: List<String>, val calories: Double?, val protein: Double?, val lateInDay: Boolean, val diet: DietFilter, val foods: Int,
)

private sealed interface Fit {
    data object Hidden : Fit
    data object Finding : Fit
    data object Nothing : Fit
    data class Order(val match: MealMatch) : Fit
}

/** Today's targets less what's been logged today (Assistant.remaining). Null for a target that isn't set. */
private fun remaining(data: AppData, goals: Goals): Pair<Double?, Double?> {
    val key = dayKey(java.time.Instant.now())
    val eaten = Nutrition((data.logs[key] ?: emptyList()).flatMap { it.items })
    val target = data.dayGoals[key] ?: goals
    return Pair(target.values["cal"]?.let { it - eaten.cal }, target.values["p"]?.let { it - eaten.p })
}

/**
 * What to look for at one restaurant (Assistant.budget). Before 4 pm there's still a meal to come, so it's capped at your typical
 * meal; after that it can use everything that's left. Null when today's calories are used up.
 */
private fun budget(data: AppData, goals: Goals, chain: String): FindQuery? {
    val (calories, protein) = remaining(data, goals)
    val lastMeal = LocalTime.now().hour >= 16
    val cal = if (calories != null) {
        if (calories < 100) return null
        if (lastMeal) calories else min(calories, goals.mealCal)
    } else goals.mealCal
    val p = maxOf(0.0, protein?.let { if (lastMeal) it else min(it, goals.mealProtein) } ?: goals.mealProtein)
    return FindQuery(chains = setOf(chain), calories = cal, protein = p)
}

private fun defaultCentre(region: MenuRegion): Pair<GeoPoint, Double> = when (region) {
    MenuRegion.AUSTRALIA -> GeoPoint(-26.0, 134.0) to 4.0
    MenuRegion.NEW_ZEALAND -> GeoPoint(-41.0, 174.0) to 5.0
    MenuRegion.UNITED_STATES -> GeoPoint(39.0, -98.0) to 4.0
    MenuRegion.CANADA -> GeoPoint(56.0, -96.0) to 3.0
    MenuRegion.UNITED_KINGDOM -> GeoPoint(54.0, -2.0) to 5.0
    MenuRegion.SOUTH_AFRICA -> GeoPoint(-29.0, 24.0) to 5.0
    MenuRegion.INDIA -> GeoPoint(22.0, 79.0) to 4.0
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MapScreen() {
    val store = AppServices.store
    val nav = AppServices.nav
    val c = Leanr.colours
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val focus = LocalFocusManager.current

    var query by remember { mutableStateOf("") }
    var area by remember { mutableStateOf<Area?>(null) }
    var areaPlaces by remember { mutableStateOf<Map<String, List<NearbyPlace>>>(emptyMap()) }
    var areaLoading by remember { mutableStateOf(false) }
    var noMatch by remember { mutableStateOf(false) }
    var searchingFor by remember { mutableStateOf("") }
    var searchJob by remember { mutableStateOf<Job?>(null) }
    var fits by remember { mutableStateOf<Map<String, MealMatch>>(emptyMap()) }
    var fitsDoneFor by remember { mutableStateOf<FitsRequest?>(null) }
    var ordering by remember { mutableStateOf<MealMatch?>(null) }
    var centreOn by remember { mutableStateOf<GeoPoint?>(null) }

    val authorized = NearbyPlaces.isAuthorized(context)
    val location = NearbyPlaces.location
    val chains = store.catalog.chains.map { it.id }.filter { ChainPlace.all.containsKey(it) }
    val places = if (area == null) NearbyPlaces.places else areaPlaces
    val nearest = chains.mapNotNull { places[it]?.firstOrNull() }.sortedBy { it.distance }
    val showingList = area != null || (authorized && location != null)
    val searchingNow = areaLoading || (area == null && NearbyPlaces.loading)

    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
        NearbyPlaces.permissionChanged()
        if (result.values.any { it }) {
            NearbyPlaces.denied = false
            scope.launch { NearbyPlaces.request(context) }
        } else {
            val activity = context as? Activity
            NearbyPlaces.denied = activity == null || !ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.ACCESS_FINE_LOCATION)
        }
    }
    fun requestLocation() {
        if (NearbyPlaces.isAuthorized(context)) { scope.launch { NearbyPlaces.request(context) }; return }
        Prefs.set(LOCATION_ASKED_KEY, true)
        permission.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION))
    }

    // Asks for "while using the app" access the first time the Map opens, then fetches the current location.
    LaunchedEffect(Unit) {
        if (NearbyPlaces.isAuthorized(context)) NearbyPlaces.request(context)
        else if (!Prefs.bool(LOCATION_ASKED_KEY)) requestLocation()
        else {
            val activity = context as? Activity
            NearbyPlaces.denied = activity != null && !ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.ACCESS_FINE_LOCATION)
        }
    }
    LaunchedEffect(location, chains) { if (location != null) NearbyPlaces.load(chains) }
    LaunchedEffect(location) { if (area == null && location != null) centreOn = GeoPoint(location.latitude, location.longitude) }

    // The best order at each nearby restaurant for what's left today, once worked out.
    val (leftCalories, leftProtein) = remaining(store.data, store.goals)
    val nothingLeft = leftCalories?.let { it < 100 } ?: false
    val fitsNeeded = FitsRequest(nearest.map { it.chain }, leftCalories, leftProtein, LocalTime.now().hour >= 16, DietFilter.saved, store.orderFoods.size)
    LaunchedEffect(fitsNeeded) {
        val request = fitsNeeded
        val data = store.data; val goals = store.goals
        val queries = request.chains.mapNotNull { chain -> budget(data, goals, chain)?.copy(diet = request.diet, customise = false) }
        val foods = store.orderFoods
        val found = withContext(Dispatchers.Default) { queries.mapNotNull { MealFinder.find(foods, it).firstOrNull() } }
        fits = found.groupBy { it.chain }.mapValues { it.value.first() }
        fitsDoneFor = request
    }
    fun fit(chain: String): Fit = when {
        nothingLeft -> Fit.Hidden
        fitsDoneFor != fitsNeeded -> Fit.Finding
        else -> fits[chain]?.let { Fit.Order(it) } ?: Fit.Nothing
    }

    /** Looks up a searched place, moves the map there and finds the restaurants around it. A newer search always wins. */
    fun startSearch(text: String) {
        val name = text.trim()
        if (name.isEmpty()) return
        searchJob?.cancel()
        searchingFor = name; areaLoading = true; noMatch = false
        focus.clearFocus()
        searchJob = scope.launch {
            val spot = Overpass.geocode(context, name, NearbyPlaces.location)
            if (spot == null) { noMatch = true; areaLoading = false; return@launch }
            area = Area(spot.name, spot.latitude, spot.longitude); areaPlaces = emptyMap(); noMatch = false; query = ""
            centreOn = GeoPoint(spot.latitude, spot.longitude)
            areaPlaces = Overpass.find(chains, spot.latitude, spot.longitude) ?: emptyMap()
            areaLoading = false
        }
    }
    fun clearArea() {
        searchJob?.cancel()
        area = null; areaPlaces = emptyMap(); areaLoading = false
        NearbyPlaces.location?.let { centreOn = GeoPoint(it.latitude, it.longitude) }
    }
    BackHandler(enabled = area != null) { clearArea() }

    Column(Modifier.fillMaxSize().statusBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 8.dp, top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Map", style = LeanrType.largeTitle, color = c.text, modifier = Modifier.weight(1f))
            IconButton(onClick = { nav.settingsOpen = true }) { Icon(Icons.Filled.Settings, "Settings", tint = c.accent) }
        }
        TextField(
            value = query, onValueChange = { query = it; noMatch = false }, singleLine = true,
            placeholder = { Text("Search a suburb, address or place", style = LeanrType.body, color = c.secondaryText) },
            leadingIcon = { Icon(Icons.Filled.Search, null, tint = c.secondaryText) },
            trailingIcon = { if (query.isNotEmpty()) IconButton(onClick = { query = "" }) { Icon(Icons.Filled.Close, "Clear", tint = c.secondaryText) } },
            textStyle = LeanrType.body, shape = RoundedCornerShape(12.dp),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            keyboardActions = KeyboardActions(onSearch = { startSearch(query) }),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = c.card, unfocusedContainerColor = c.card, focusedIndicatorColor = Color.Transparent,
                unfocusedIndicatorColor = Color.Transparent, cursorColor = c.accent,
            ),
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp),
        )
        OsmMap(
            places = chains.flatMap { (places[it] ?: emptyList()).take(5) },
            area = area, user = location?.let { GeoPoint(it.latitude, it.longitude) },
            centreOn = centreOn, onCentred = { centreOn = null },
            modifier = Modifier.fillMaxWidth().height(250.dp),
        )
        LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 24.dp)) {
            val current = area
            if (current != null) {
                item {
                    LeanrSection {
                        MapRow(Icons.Filled.Place, "Near ${current.name}", bold = true)
                        MapRow(Icons.Outlined.LocationOn, "Back to my location", accent = true, divider = false) { clearArea() }
                    }
                }
            } else {
                item { LocationStatusRows("restaurants near you", authorized, onRequest = ::requestLocation) }
                if (!authorized) item {
                    Text("Or search for a suburb or address above.", style = LeanrType.caption, color = c.secondaryText,
                        modifier = Modifier.padding(start = 16.dp, bottom = 20.dp))
                }
            }
            if (noMatch) item {
                LeanrSection { MapRow(null, "Couldn’t find “$query”. Try a suburb or full address.", secondary = true, divider = false) }
            }
            if (areaLoading && current == null) item {
                LeanrSection(header = "Finding $searchingFor…") { repeat(3) { SkeletonRow(divider = it < 2) } }
            }
            if (showingList) item {
                LeanrSection(header = if (searchingNow) "Searching nearby…" else "Closest of each restaurant") {
                    if (searchingNow && nearest.isEmpty()) repeat(3) { SkeletonRow(divider = it < 2) }
                    nearest.forEachIndexed { i, place ->
                        NearbyRow(place, fit(place.chain), divider = i < nearest.lastIndex, open = { ordering = it }) { nav.showOptions(place.chain) }
                    }
                    if (nothingLeft && nearest.isNotEmpty()) FootRow("Today’s calories are used up, so there’s no order to suggest.")
                    val missing = chains.filter { places[it]?.isEmpty() == true }.map { store.chainName(it) }
                    if (missing.isNotEmpty()) FootRow("None within 15 km: ${missing.joinToString(", ")}.")
                    if (!searchingNow && nearest.isEmpty() && places.isEmpty() && current == null && !NearbyPlaces.loading) {
                        FootRow("Couldn’t search OpenStreetMap just now.")
                    }
                }
            }
        }
    }

    ordering?.let { match ->
        ModalBottomSheet(onDismissRequest = { ordering = null }, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = c.paper) {
            OrderDetail(match, onDone = { ordering = null })
        }
    }
}

/** The OpenStreetMap view: the user's spot, a searched place in red and up to five restaurants of each chain. */
@Composable
private fun OsmMap(places: List<NearbyPlace>, area: Area?, user: GeoPoint?, centreOn: GeoPoint?, onCentred: () -> Unit, modifier: Modifier) {
    val context = LocalContext.current
    val c = Leanr.colours
    val store = AppServices.store
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val map = remember {
        Configuration.getInstance().apply {
            load(context, context.getSharedPreferences("osmdroid", Context.MODE_PRIVATE))
            // OpenStreetMap's tile policy asks for an identifying user agent: the app's package name, nothing personal.
            userAgentValue = context.packageName
        }
        MapView(context).apply {
            setTileSource(TileSourceFactory.MAPNIK)
            setMultiTouchControls(true)
            zoomController.setVisibility(CustomZoomButtonsController.Visibility.NEVER)
            val (centre, zoom) = defaultCentre(store.region)
            controller.setZoom(zoom)
            controller.setCenter(user ?: centre)
            if (user != null) controller.setZoom(14.0)
        }
    }
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> map.onResume()
                Lifecycle.Event.ON_PAUSE -> map.onPause()
                else -> {}
            }
        }
        lifecycle.addObserver(observer)
        map.onResume()
        onDispose { lifecycle.removeObserver(observer); map.onPause(); map.onDetach() }
    }
    LaunchedEffect(centreOn) {
        centreOn ?: return@LaunchedEffect
        // About 5 km across, like the iOS map.
        map.controller.animateTo(centreOn, 14.0, 600L)
        onCentred()
    }
    val accent = c.accent.toArgb()
    LaunchedEffect(places, area, user, accent) {
        map.overlays.clear()
        for (place in places) {
            map.overlays += Marker(map).apply {
                position = GeoPoint(place.latitude, place.longitude)
                setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
                title = place.name
                snippet = listOfNotNull(place.address.ifBlank { null }, place.hours, place.distanceText).joinToString("\n")
                icon = ContextCompat.getDrawable(context, org.osmdroid.library.R.drawable.marker_default)?.mutate()?.apply { setTint(accent) }
            }
        }
        if (area != null) map.overlays += Marker(map).apply {
            position = GeoPoint(area.latitude, area.longitude)
            setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
            title = area.name
            icon = ContextCompat.getDrawable(context, org.osmdroid.library.R.drawable.marker_default)?.mutate()?.apply { setTint(AndroidColor.RED) }
        }
        if (user != null) map.overlays += Marker(map).apply {
            position = user
            setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_CENTER)
            title = "My location"
            icon = GradientDrawable().apply {
                shape = GradientDrawable.OVAL; setColor(0xFF0A84FF.toInt()); setStroke(6, AndroidColor.WHITE); setSize(44, 44)
            }
        }
        map.invalidate()
    }
    Box(modifier.clipToBounds()) {
        AndroidView(factory = { map }, modifier = Modifier.fillMaxSize().clipToBounds())
        // OpenStreetMap's licence asks for this credit on the map.
        Text("© OpenStreetMap contributors", style = LeanrType.caption2, color = Color.Black,
            modifier = Modifier.align(Alignment.BottomStart).padding(4.dp).background(Color.White.copy(alpha = 0.75f), RoundedCornerShape(4.dp)).padding(horizontal = 4.dp, vertical = 1.dp))
        if (user != null) Surface(shape = CircleShape, color = c.card, shadowElevation = 3.dp,
            modifier = Modifier.align(Alignment.BottomEnd).padding(10.dp).size(40.dp).clip(CircleShape).clickable { map.controller.animateTo(user, 14.0, 600L) }) {
            Box(contentAlignment = Alignment.Center) { Icon(Icons.Filled.MyLocation, "My location", tint = c.accent, modifier = Modifier.size(22.dp)) }
        }
    }
}

/** Explains or asks for location access; shows nothing once a location is available (LocationStatusRows). */
@Composable
private fun LocationStatusRows(what: String, authorized: Boolean, onRequest: () -> Unit) {
    val context = LocalContext.current
    when {
        !authorized && NearbyPlaces.denied -> LeanrSection {
            MapRow(null, "Location access is off, so Leanrrr can’t find $what.", secondary = true)
            MapRow(null, "Open Settings", accent = true, divider = false) {
                context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
        }
        !authorized -> LeanrSection(footer = "Your location is only used while you’re using the app.") {
            MapRow(Icons.Outlined.LocationOn, "Use my location", accent = true, divider = false, onClick = onRequest)
        }
        NearbyPlaces.failed -> LeanrSection {
            MapRow(null, "Couldn’t get your location.", secondary = true)
            MapRow(null, "Try again", accent = true, divider = false, onClick = onRequest)
        }
        NearbyPlaces.location == null -> LeanrSection { repeat(3) { SkeletonRow(divider = it < 2) } }
    }
}

@Composable
private fun MapRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector?, title: String, bold: Boolean = false, accent: Boolean = false,
    secondary: Boolean = false, divider: Boolean = true, onClick: (() -> Unit)? = null,
) {
    val c = Leanr.colours
    Column {
        Row(Modifier.fillMaxWidth().then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier).padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically) {
            if (icon != null) { Icon(icon, null, tint = c.accent, modifier = Modifier.size(20.dp)); Spacer(Modifier.width(12.dp)) }
            Text(title, style = if (bold) LeanrType.headline else LeanrType.body,
                color = when { accent -> c.accent; secondary -> c.secondaryText; else -> c.text })
        }
        if (divider) HorizontalDivider(Modifier.padding(start = 16.dp), color = c.separator, thickness = 0.5.dp)
    }
}

@Composable
private fun FootRow(text: String) {
    Text(text, style = LeanrType.caption, color = Leanr.colours.secondaryText, modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp))
}

/** A grey placeholder the shape of a restaurant row, while it loads. */
@Composable
private fun SkeletonRow(divider: Boolean) {
    val c = Leanr.colours
    val fill = c.text.copy(alpha = 0.08f)
    Column {
        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.fillMaxWidth(0.55f).height(16.dp).clip(RoundedCornerShape(4.dp)).background(fill))
            Box(Modifier.fillMaxWidth(0.8f).height(12.dp).clip(RoundedCornerShape(4.dp)).background(fill))
        }
        if (divider) HorizontalDivider(Modifier.padding(start = 16.dp), color = c.separator, thickness = 0.5.dp)
    }
}

/** A found restaurant: name, address, distance, what fits there, directions and the chain's app (NearbyRow). */
@Composable
private fun NearbyRow(place: NearbyPlace, fit: Fit, divider: Boolean, open: (MealMatch) -> Unit, showOptions: () -> Unit) {
    val c = Leanr.colours
    val store = AppServices.store
    val context = LocalContext.current
    val name = store.chainName(place.chain)
    Column {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.Bottom) {
                Text(name, style = LeanrType.headline, color = c.text, modifier = Modifier.weight(1f))
                Text(place.distanceText, style = LeanrType.subheadline, color = c.secondaryText)
            }
            if (place.address.isNotEmpty()) Text(place.address, style = LeanrType.caption, color = c.secondaryText)
            FitLine(fit, open)
            // Hours and delivery share a line, and the actions share the next one.
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                if (place.hours != null) Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.weight(1f, fill = false)) {
                    Icon(Icons.Outlined.Schedule, null, tint = c.accent, modifier = Modifier.size(15.dp))
                    Spacer(Modifier.width(6.dp))
                    Text(hoursText(place.hours), style = LeanrType.caption.copy(fontWeight = FontWeight.SemiBold), color = c.text,
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                DeliveryLine(place)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Button(onClick = showOptions, modifier = Modifier.weight(1f), shape = RoundedCornerShape(10.dp), contentPadding = PaddingValues(horizontal = 10.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = c.accent, contentColor = if (c.dark) Color.Black else Color.White)) {
                    Icon(Icons.AutoMirrored.Filled.List, null, modifier = Modifier.size(18.dp)); Spacer(Modifier.width(6.dp))
                    Text("Show $name options", style = LeanrType.subheadline.copy(fontWeight = FontWeight.SemiBold), maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                OutlinedButton(onClick = { place.directions(context) }, shape = RoundedCornerShape(10.dp), contentPadding = PaddingValues(0.dp), modifier = Modifier.size(44.dp, 40.dp)) {
                    Icon(Icons.Filled.Directions, "Directions to $name", tint = c.accent)
                }
                ChainPlace.all[place.chain]?.let { app ->
                    OutlinedButton(onClick = { openChainApp(context, place.chain) }, shape = RoundedCornerShape(10.dp), contentPadding = PaddingValues(0.dp), modifier = Modifier.size(44.dp, 40.dp)) {
                        Icon(Icons.AutoMirrored.Filled.OpenInNew, app.launchTitle, tint = c.accent)
                    }
                }
            }
        }
        if (divider) HorizontalDivider(Modifier.padding(start = 16.dp), color = c.separator, thickness = 0.5.dp)
    }
}

/** OpenStreetMap's opening hours as people say them: "Open 24 hours" for 24/7, otherwise the tag with readable days. */
private fun hoursText(raw: String): String {
    if (raw.trim() == "24/7") return "Open 24 hours"
    return raw.replace("Mo", "Mon").replace("Tu", "Tue").replace("We", "Wed").replace("Th", "Thu").replace("Fr", "Fri")
        .replace("Sa", "Sat").replace("Su", "Sun").replace("PH", "public holidays").replace(";", ",")
}

@Composable
private fun FitLine(fit: Fit, open: (MealMatch) -> Unit) {
    val c = Leanr.colours
    when (fit) {
        Fit.Hidden -> {}
        Fit.Finding -> Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(c.text.copy(alpha = 0.06f)).padding(10.dp)) {
            Text("An order that fits what’s left", style = LeanrType.subheadline.copy(fontWeight = FontWeight.Medium), color = c.tertiaryText)
            Text("Finding what fits…", style = LeanrType.caption, color = c.tertiaryText)
        }
        Fit.Nothing -> Text("Nothing here fits what’s left today.", style = LeanrType.caption, color = c.secondaryText)
        is Fit.Order -> {
            val match = fit.match
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(c.accent.copy(alpha = 0.1f)).clickable { open(match) }.padding(10.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(match.items.joinToString(" + ") { it.food.name }, style = LeanrType.subheadline.copy(fontWeight = FontWeight.Medium), color = c.text, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Text("${Math.round(match.total.cal).toDouble().number} Cal · ${Math.round(match.total.p).toDouble().number} g protein", style = LeanrType.caption, color = c.secondaryText)
                }
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = c.tertiaryText)
            }
        }
    }
}

/** Whether a restaurant is likely to deliver to you (Delivery.swift), as a menu of delivery apps to check and order in. */
@Composable
private fun DeliveryLine(place: NearbyPlace) {
    val c = Leanr.colours
    val context = LocalContext.current
    val name = AppServices.store.chainName(place.chain)
    var open by remember { mutableStateOf(false) }
    // Delivery apps usually deliver within about 5 km, sometimes up to about 8 km; the app has the final say.
    val (text, colour) = when {
        place.distance <= 5_000 -> "Delivery likely" to c.text
        place.distance <= 8_000 -> "Delivery may reach you" to (if (c.dark) Color(0xFFFF9F0A) else Color(0xFFB85400))
        else -> "Probably too far to deliver" to c.secondaryText
    }
    Box {
        Row(Modifier.clip(RoundedCornerShape(6.dp)).clickable { open = true }.padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.DeliveryDining, null, tint = c.accent, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(6.dp))
            Text(text, style = LeanrType.caption.copy(fontWeight = FontWeight.Medium), color = colour)
            Icon(Icons.Filled.ArrowDropDown, null, tint = c.secondaryText, modifier = Modifier.size(16.dp))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            Text("The delivery app confirms it for your address", style = LeanrType.caption, color = c.secondaryText, modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp))
            val q = Uri.encode(name)
            DropdownMenuItem(text = { Text("Uber Eats") }, onClick = { open = false; openUrl(context, "https://www.ubereats.com/au/search?q=$q") })
            DropdownMenuItem(text = { Text("DoorDash") }, onClick = { open = false; openUrl(context, "https://www.doordash.com/search/store/$q/") })
            // Menulog asks for your address before it can search.
            DropdownMenuItem(text = { Text("Menulog") }, onClick = { open = false; openUrl(context, "https://www.menulog.com.au/") })
            ChainPlace.all[place.chain]?.let { own ->
                DropdownMenuItem(text = { Text("${own.appName} app") }, onClick = { open = false; openChainApp(context, place.chain) })
            }
        }
    }
}

/** A suggested order: its items, nutrition, where to get it, and Log it / Add to meal (OrderDetailView). */
@Composable
private fun OrderDetail(match: MealMatch, onDone: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    val context = LocalContext.current
    var detail by remember { mutableStateOf<Food?>(null) }
    detail?.let { food -> Box(Modifier.fillMaxWidth().height(640.dp)) { FoodDetailScreen(food, onBack = { detail = null }) }; return }
    val name = match.items.joinToString(" + ") { it.food.name }
    Column(Modifier.fillMaxWidth().navigationBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Order", style = LeanrType.title, color = c.text, modifier = Modifier.weight(1f))
            IconButton(onClick = {
                val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, mealText("Suggested order", match.items))
                context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }) { Icon(Icons.Filled.Share, "Share order", tint = c.accent) }
            TextButton(onClick = onDone) { Text("Done", style = LeanrType.headline, color = c.accent) }
        }
        LazyColumn(Modifier.weight(1f, fill = false), contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp)) {
            item {
                LeanrSection {
                    Column(Modifier.padding(16.dp)) {
                        Text(name, style = LeanrType.title2Display, color = c.text)
                        Text(store.chainName(match.chain), style = LeanrType.body, color = c.secondaryText)
                    }
                }
            }
            item { LeanrSection(header = "Nutrition") { NutritionView(match.total) } }
            NearbyPlaces.nearest(match.chain)?.let { place ->
                item { LeanrSection(header = "Nearest ${store.chainName(match.chain)}") { NearbyRow(place, Fit.Hidden, divider = false, open = {}) { onDone(); AppServices.nav.showOptions(match.chain) } } }
            }
            item {
                val footer = if (match.customised > 0) "Ask for the changes listed after each item’s name when you order. They use ${store.chainName(match.chain)}’s own figures for each part, so check the food’s details for how each was worked out." else null
                LeanrSection(header = "Items", footer = footer) {
                    match.items.forEachIndexed { i, item -> FoodRow(item.food, divider = i < match.items.lastIndex) { detail = item.food } }
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Button(onClick = { if (store.logNow(match.items, name)) onDone() }, modifier = Modifier.weight(1f).height(50.dp), shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(containerColor = c.accent, contentColor = if (c.dark) Color.Black else Color.White)) {
                Text("Log it · ${match.total.cal.number} Cal", style = LeanrType.headline, maxLines = 1)
            }
            OutlinedButton(onClick = { if (store.add(match.items)) onDone() }, modifier = Modifier.height(50.dp), shape = RoundedCornerShape(14.dp)) {
                Text("Add to meal", style = LeanrType.headline, color = c.accent)
            }
        }
    }
}

