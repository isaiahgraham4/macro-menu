package com.isaiahgraham.leanrrr.feature.scan

import android.graphics.Bitmap
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlinx.coroutines.launch

/**
 * A full-screen camera for one photo or several pages (FoodCamera.swift, and the camera parts of the label and menu scanners):
 * a frame to line up in, the full-quality picture when the shutter is tapped, and, with `onBarcode`, a shortcut to the product
 * scanner when a barcode is in shot. Everything stays on the phone.
 *
 * With `pages` above 1 it keeps taking pictures until Done (or the limit), for a menu's pages.
 */
@Composable
fun PhotoCamera(
    hint: String,
    onPhotos: (List<Bitmap>) -> Unit,
    onCancel: () -> Unit,
    pages: Int = 1,
    square: Boolean = true,
    onBarcode: (() -> Unit)? = null,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val access = rememberCameraAccess(askNow = true)
    val taker = remember { PhotoTaker() }
    var capturing by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf<String?>(null) }
    var seesBarcode by remember { mutableStateOf(false) }
    val taken = remember { mutableListOf<Bitmap>() }
    var count by remember { mutableIntStateOf(0) }
    val analyzer = remember(onBarcode != null) { if (onBarcode != null) BarcodeAnalyzer(validOnly = false, seen = { seesBarcode = it }) else null }
    DisposableEffect(analyzer) { onDispose { analyzer?.stop() } }
    BackHandler(onBack = onCancel)

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        if (access.granted) CameraPreview(Modifier.fillMaxSize(), analyzer = analyzer, photo = taker) { failed = it }
        val frameColour = Color.White.copy(alpha = 0.85f)
        Box(
            Modifier.align(Alignment.Center).fillMaxWidth().padding(24.dp).then(if (square) Modifier.aspectRatio(1f) else Modifier.aspectRatio(0.72f))
                .drawBehind {
                    drawRoundRect(frameColour, cornerRadius = CornerRadius(28.dp.toPx()),
                        style = Stroke(width = 2.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(10.dp.toPx(), 8.dp.toPx()))))
                },
        )
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(horizontal = 20.dp, vertical = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(Modifier.fillMaxWidth()) {
                Pill("Cancel") { onCancel() }
                Spacer(Modifier.weight(1f))
                if (pages > 1 && count > 0) Pill("Done · $count") { onPhotos(taken.toList()) }
            }
            val message = when {
                !access.granted && access.denied -> "Camera access is off. Allow it in Settings, or choose a photo instead."
                failed != null -> failed!!
                else -> hint
            }
            Text(message, style = LeanrType.subheadline, color = Color.White,
                modifier = Modifier.background(Color.Black.copy(alpha = 0.45f), CircleShape).padding(horizontal = 14.dp, vertical = 8.dp))
            if (!access.granted && access.denied) Pill("Open Settings") { openAppSettings(context) }
            Spacer(Modifier.weight(1f))
            if (onBarcode != null && seesBarcode) {
                Button(onClick = onBarcode, colors = ButtonDefaults.buttonColors(containerColor = Leanr.colours.accent)) {
                    Icon(Icons.Filled.QrCodeScanner, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp))
                    Text("Barcode in shot · Scan the product", style = LeanrType.subheadline)
                }
            }
            val enabled = access.granted && !capturing
            Box(
                Modifier.size(78.dp).border(BorderStroke(4.dp, Color.White), CircleShape).clickable(enabled = enabled) {
                    capturing = true; failed = null
                    scope.launch {
                        val photo = runCatching { taker.take(context) }.getOrNull()
                        capturing = false
                        if (photo == null) { failed = "That didn't take. Try again."; return@launch }
                        taken += photo; count = taken.size
                        if (pages <= 1 || taken.size >= pages) onPhotos(taken.toList())
                    }
                }.semantics { contentDescription = "Take photo" },
                contentAlignment = Alignment.Center,
            ) { Box(Modifier.size(64.dp).alpha(if (capturing || !enabled) 0.5f else 1f).background(Color.White, CircleShape)) }
        }
    }
}

@Composable
private fun Pill(title: String, onClick: () -> Unit) {
    Text(title, style = LeanrType.headline, color = Color.White,
        modifier = Modifier.background(Color.Black.copy(alpha = 0.45f), RoundedCornerShape(50)).clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp))
}
