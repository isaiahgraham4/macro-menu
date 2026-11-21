package com.isaiahgraham.leanrrr.feature.progress

import android.graphics.Bitmap
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Compare
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.outlined.Straighten
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.data.BodyMeasurement
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.data.tenth
import com.isaiahgraham.leanrrr.ui.components.LeanrRow
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.components.LeanrSection
import com.isaiahgraham.leanrrr.ui.components.OptionalNumberField
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.ZoneId

// A port of BodyView.swift: tape measurements and progress photos.

/** Weight's companions on the Progress tab: measurements and progress photos. */
@Composable
fun BodySection(openMeasurements: () -> Unit, openPhotos: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    val waist = BodyMeasurements.change(BodyMeasurements.readings(store.data.measurementLog, BodySite.WAIST.raw))
    LeanrSection("Body", footer = "Measurements are backed up with the rest of your data. Progress photos stay on this phone.") {
        LeanrRow("Measurements", leading = { Icon(Icons.Outlined.Straighten, null, tint = c.accent) }, onClick = openMeasurements,
            trailing = { waist?.let { Text("Waist ${it.latest.cm.number} cm", style = LeanrType.caption, color = c.secondaryText) } })
        LeanrRow("Progress photos", divider = false, leading = { Icon(Icons.Filled.CameraAlt, null, tint = c.accent) }, onClick = openPhotos)
    }
}

@Composable
fun MeasurementsScreen(onBack: () -> Unit, openSite: (String) -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    val entries = store.data.measurementLog
    var adding by remember { mutableStateOf(false) }
    LeanrScreen("Measurements", onBack = onBack) {
        val sites = BodyMeasurements.sites(entries)
        item {
            if (entries.isEmpty()) {
                LeanrSection { EmptyState(Icons.Outlined.Straighten, "No measurements yet", "Waist, hips, chest and more. Scales miss what a tape measure shows, so these are worth taking monthly.") }
            } else {
                LeanrSection("Latest", footer = "Changes compare the latest reading with the one before it, and with your first.") {
                    sites.forEachIndexed { i, site ->
                        val change = BodyMeasurements.change(BodyMeasurements.readings(entries, site)) ?: return@forEachIndexed
                        val first = change.first; val sinceFirst = change.sinceFirst
                        LeanrRow(BodyMeasurements.title(site),
                            subtitle = if (first != null && sinceFirst != null) "${BodyMeasurements.signed(sinceFirst)} since ${shortDay(first.date.day())}"
                                else "First reading ${shortDay(change.latest.date.day())}",
                            divider = i < sites.size - 1, onClick = { openSite(site) },
                            trailing = {
                                Column(horizontalAlignment = Alignment.End) {
                                    Text("${change.latest.cm.number} cm", style = LeanrType.headline, color = c.text)
                                    change.sinceLast?.let { Text("${BodyMeasurements.signed(it)} last time", style = LeanrType.caption, color = c.secondaryText) }
                                }
                            })
                    }
                }
            }
        }
        item {
            LeanrSection(footer = "Measure at the same spot each time, relaxed, in the morning if you can. Skip any site you don't want to track.") {
                LeanrRow("Add measurements", divider = false, titleColour = c.accent, leading = { Icon(Icons.Filled.AddCircle, null, tint = c.accent) }, onClick = { adding = true })
            }
        }
        if (entries.isNotEmpty()) item {
            LeanrSection("History") {
                val history = entries.sortedByDescending { it.date }
                history.forEachIndexed { i, entry ->
                    val known = BodyMeasurements.sites(listOf(entry))
                    val summary = known.mapNotNull { site -> entry.values[site]?.let { "${BodyMeasurements.title(site)} ${it.number}" } }.joinToString(" · ") + " cm"
                    LeanrRow(mediumDate(entry.date), subtitle = summary, divider = i < history.size - 1, trailing = {
                        IconButton(onClick = { store.change(undo = "Deleted measurements") { s -> s.copy(measurements = s.measurements?.filter { it.id != entry.id }) } }) {
                            Icon(Icons.Filled.Delete, "Delete", tint = c.secondaryText)
                        }
                    })
                }
            }
        }
    }
    if (adding) MeasurementEntrySheet { adding = false }
}

/** Measurements for one day, any sites you like. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MeasurementEntrySheet(onDismiss: () -> Unit) {
    val store = AppServices.store
    val c = Leanr.colours
    var date by remember { mutableStateOf(Instant.now()) }
    val values = remember { mutableStateMapOf<String, Double?>() }
    val cleaned = values.filterValues { it != null && it in 5.0..300.0 }.mapValues { it.value!!.tenth }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = c.paper) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = onDismiss) { Text("Cancel") }
                Text("Add measurements", style = LeanrType.headline, color = c.text, modifier = Modifier.weight(1f).padding(horizontal = 8.dp))
                TextButton(enabled = cleaned.isNotEmpty(), onClick = {
                    val entry = BodyMeasurement(date = date, values = cleaned)
                    if (store.change(undo = "Saved measurements") { it.copy(measurements = it.measurementLog + entry) }) onDismiss()
                }) { Text("Save", fontWeight = FontWeight.Bold) }
            }
            LeanrSection { DateTimeRow("Date", date, { date = it }, withTime = false, divider = false) }
            LeanrSection(footer = "Leave a site blank to skip it. Each reading must be between 5 and 300 cm.") {
                BodySite.entries.forEachIndexed { i, site ->
                    val last = BodyMeasurements.change(BodyMeasurements.readings(store.data.measurementLog, site.raw))?.latest?.cm
                    OptionalNumberField("${site.title} (cm)", values[site.raw], { values[site.raw] = it }, divider = last == null && i < BodySite.entries.size - 1)
                    if (last != null) Text("Last time ${last.number} cm", style = LeanrType.caption, color = c.secondaryText, modifier = Modifier.padding(start = 16.dp, bottom = 8.dp))
                }
            }
        }
    }
}

@Composable
fun MeasurementChartScreen(site: String, onBack: () -> Unit) {
    val readings = BodyMeasurements.readings(AppServices.store.data.measurementLog, site)
    LeanrScreen(BodyMeasurements.title(site), onBack = onBack) {
        item {
            LeanrSection {
                if (readings.size >= 2) DatedLineChart(readings.map { it.date.day() to it.cm }, "${BodyMeasurements.title(site)} chart", Modifier.padding(horizontal = 12.dp))
                else SectionText("Take a second measurement to see how it changes.")
            }
        }
        item {
            LeanrSection("Readings") {
                readings.reversed().forEachIndexed { i, r -> ValueRow(mediumDate(r.date), "${r.cm.number} cm", divider = i < readings.size - 1) }
            }
        }
    }
}

// MARK: Progress photos

/** The photo files and a cache of thumbnails, for the screens below. Works on this phone only. */
private class PhotoLibrary(val files: ProgressPhotoFiles) {
    var photos by mutableStateOf(files.load())
    var problem by mutableStateOf<String?>(null)
    private val thumbnails = HashMap<String, Bitmap>()

    fun reload() { photos = files.load() }
    fun add(data: ByteArray, date: Instant = Instant.now()): Boolean {
        val jpeg = ProgressPhotoFiles.prepared(data) ?: run { problem = "That photo couldn't be read."; return false }
        try { files.add(jpeg, date) } catch (e: Exception) { problem = "Couldn't save the photo. Check your phone's storage."; return false }
        reload(); return true
    }
    fun update(photo: ProgressPhoto) { try { files.update(photo) } catch (e: Exception) { problem = "Couldn't save the change." }; reload() }
    fun remove(photo: ProgressPhoto) { try { files.remove(photo.id) } catch (e: Exception) { problem = "Couldn't delete the photo." }; thumbnails.remove(photo.id); reload() }
    fun thumbnail(photo: ProgressPhoto): Bitmap? = thumbnails[photo.id] ?: files.thumbnail(photo.id)?.also { thumbnails[photo.id] = it }
}

@Composable
fun ProgressPhotosScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val c = Leanr.colours
    val library = remember { PhotoLibrary(ProgressPhotoFiles.standard(context)) }
    var viewing by remember { mutableStateOf<ProgressPhoto?>(null) }
    var comparing by remember { mutableStateOf(false) }
    var cameraFile by remember { mutableStateOf<java.io.File?>(null) }
    var pending by remember { mutableStateOf<ByteArray?>(null) }
    LaunchedEffect(pending) {
        val bytes = pending ?: return@LaunchedEffect
        withContext(Dispatchers.Default) { library.add(bytes) }
        pending = null
    }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) pending = runCatching { context.contentResolver.openInputStream(uri)?.use { it.readBytes() } }.getOrNull()
            ?: run { library.problem = "That photo couldn't be opened."; null }
    }
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { taken ->
        val file = cameraFile
        if (taken && file != null && file.exists()) pending = file.readBytes()
        cameraFile = null
    }
    val preview = rememberLauncherForActivityResult(ActivityResultContracts.TakePicturePreview()) { bitmap ->
        if (bitmap != null) pending = java.io.ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }.toByteArray()
    }

    if (viewing != null) {
        BackHandler { viewing = null }
        PhotoDetailScreen(library, viewing!!) { viewing = null }
        return
    }
    if (comparing) {
        BackHandler { comparing = false }
        PhotoCompareScreen(library) { comparing = false }
        return
    }
    LeanrScreen("Progress photos", onBack = onBack, actions = {
        IconButton(onClick = {
            val target = cameraTarget(context)
            if (target != null) { cameraFile = target.first; camera.launch(target.second) } else preview.launch(null)
        }) { Icon(Icons.Filled.CameraAlt, "Take a photo", tint = c.accent) }
        IconButton(onClick = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }) {
            Icon(Icons.Filled.PhotoLibrary, "Choose from Photos", tint = c.accent)
        }
    }) {
        if (library.photos.isEmpty()) {
            item { LeanrSection { EmptyState(Icons.Filled.CameraAlt, "No photos yet", "Take one in the same spot and light every few weeks. Photos can show change the scale doesn't.") } }
        } else {
            library.photos.chunked(3).forEach { row ->
                item {
                    Row(Modifier.fillMaxWidth().padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        row.forEach { photo ->
                            Column(Modifier.weight(1f).clickable { viewing = photo }, horizontalAlignment = Alignment.CenterHorizontally) {
                                Box(Modifier.fillMaxWidth().aspectRatio(0.75f).clip(RoundedCornerShape(10.dp)).background(c.text.copy(alpha = 0.1f))) {
                                    library.thumbnail(photo)?.let { Image(it.asImageBitmap(), "Progress photo, ${mediumDate(photo.date)}", contentScale = ContentScale.Crop, modifier = Modifier.fillMaxWidth().aspectRatio(0.75f)) }
                                }
                                Text(dayMonthYear(photo.date.day()), style = LeanrType.caption, color = c.secondaryText, modifier = Modifier.padding(top = 4.dp))
                            }
                        }
                        repeat(3 - row.size) { Box(Modifier.weight(1f)) }
                    }
                }
            }
            if (library.photos.size >= 2) item {
                LeanrSection {
                    LeanrRow("Compare two photos", divider = false, titleColour = c.accent, leading = { Icon(Icons.Filled.Compare, null, tint = c.accent) }, onClick = { comparing = true })
                }
            }
        }
        item {
            LeanrSection(footer = "Leanrrr doesn't upload these. They aren't part of backups or exports, and \"Delete all my data\" removes them.") {
                LeanrRow("Stay on this phone", divider = false, titleColour = c.secondaryText, leading = { Icon(Icons.Filled.Lock, null, tint = c.secondaryText) })
            }
        }
    }
    library.problem?.let { problem ->
        AlertDialog(onDismissRequest = { library.problem = null }, title = { Text("Progress photos") }, text = { Text(problem) },
            confirmButton = { TextButton(onClick = { library.problem = null }) { Text("OK") } })
    }
}

@Composable
private fun PhotoDetailScreen(library: PhotoLibrary, original: ProgressPhoto, onClose: () -> Unit) {
    val c = Leanr.colours
    var date by remember { mutableStateOf(original.date) }
    var note by remember { mutableStateOf(original.note ?: "") }
    var confirming by remember { mutableStateOf(false) }
    val image = remember(original.id) { library.files.image(original.id) }
    val changed = date != original.date || note != (original.note ?: "")
    LeanrScreen(mediumDate(date), onBack = onClose, actions = {
        if (changed) TextButton(onClick = {
            library.update(original.copy(date = date, note = note.trim().ifEmpty { null })); onClose()
        }) { Text("Save", color = c.accent, fontWeight = FontWeight.Bold) }
    }) {
        item {
            image?.let {
                Image(it.asImageBitmap(), "Progress photo", contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxWidth().padding(bottom = 20.dp).clip(RoundedCornerShape(12.dp)))
            }
        }
        item {
            LeanrSection {
                DateTimeRow("Taken", date, { date = it }, withTime = false)
                OutlinedTextField(note, { note = it }, placeholder = { Text("Note") }, modifier = Modifier.fillMaxWidth().padding(12.dp))
            }
        }
        item {
            LeanrSection {
                LeanrRow("Delete photo", divider = false, titleColour = c.over, leading = { Icon(Icons.Filled.Delete, null, tint = c.over) }, onClick = { confirming = true })
            }
        }
    }
    if (confirming) AlertDialog(onDismissRequest = { confirming = false }, title = { Text("Delete this photo?") }, text = { Text("It can't be recovered.") },
        confirmButton = { TextButton(onClick = { library.remove(original); confirming = false; onClose() }) { Text("Delete photo", color = c.over) } },
        dismissButton = { TextButton(onClick = { confirming = false }) { Text("Cancel") } })
}

/** Two photos side by side, each with your trend weight at the time. */
@Composable
private fun PhotoCompareScreen(library: PhotoLibrary, onClose: () -> Unit) {
    val c = Leanr.colours
    val photos = library.photos
    var beforeID by remember { mutableStateOf(photos.lastOrNull()?.id) }
    var afterID by remember { mutableStateOf(photos.firstOrNull()?.id) }
    val points = WeightTrend.points(AppServices.store.data.weightLog)
    val options = photos.map { it.id to dayMonthYear(it.date.day()) }
    LeanrScreen("Compare", onBack = onClose) {
        item {
            LeanrSection {
                MenuPickerRow("Before", options, beforeID, { beforeID = it })
                MenuPickerRow("After", options, afterID, { afterID = it }, divider = false)
            }
        }
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                listOf("Before" to beforeID, "After" to afterID).forEach { (title, id) ->
                    val photo = photos.firstOrNull { it.id == id }
                    val image = remember(id) { id?.let { library.files.image(it) } }
                    Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(title, style = LeanrType.caption.copy(fontWeight = FontWeight.Bold), color = c.secondaryText)
                        if (photo != null && image != null) {
                            Image(image.asImageBitmap(), null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)))
                            Text(dayMonthYear(photo.date.day()), style = LeanrType.caption, color = c.text)
                            points.lastOrNull { !it.date.isAfter(photo.date.day(ZoneId.systemDefault())) }?.let {
                                Text("${it.trend.number} kg", style = LeanrType.caption, color = c.secondaryText)
                            }
                        } else {
                            Box(Modifier.fillMaxWidth().aspectRatio(0.75f).clip(RoundedCornerShape(10.dp)).background(c.text.copy(alpha = 0.1f)))
                        }
                    }
                }
            }
        }
    }
}

