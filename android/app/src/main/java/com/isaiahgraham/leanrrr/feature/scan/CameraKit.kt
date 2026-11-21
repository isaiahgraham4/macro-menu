package com.isaiahgraham.leanrrr.feature.scan

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.net.Uri
import android.provider.Settings
import android.view.ScaleGestureDetector
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.OptIn
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.util.concurrent.Executors
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.math.max
import kotlin.math.roundToInt

// The camera for every scanner: CameraX preview, the CAMERA permission, the Photo Picker, and ML Kit barcode reading.
// Camera frames and photos are processed on the phone; nothing is uploaded.

/** The camera permission as Compose state: whether it's granted, whether it was refused, and a way to ask. */
class CameraAccess internal constructor(granted: Boolean) {
    var granted by mutableStateOf(granted); internal set
    /** Asked and refused: the scanners then offer to open the app's settings, and keep their typed or photo paths. */
    var denied by mutableStateOf(false); internal set
    internal var launch: () -> Unit = {}
    fun request() { if (!granted) launch() }
}

@Composable
fun rememberCameraAccess(askNow: Boolean = false): CameraAccess {
    val context = LocalContext.current
    val access = remember { CameraAccess(hasCamera(context)) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        access.granted = ok; access.denied = !ok
    }
    access.launch = { launcher.launch(Manifest.permission.CAMERA) }
    // Coming back from Settings with access turned on.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME && hasCamera(context)) { access.granted = true; access.denied = false }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    androidx.compose.runtime.LaunchedEffect(Unit) { if (askNow && !access.granted) access.request() }
    return access
}

private fun hasCamera(context: Context) = ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

/** Opens this app's page in system Settings, where camera access can be turned on. */
fun openAppSettings(context: Context) {
    context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}

/** Product barcodes as on iOS: EAN-13 (with UPC-A), EAN-8 and ITF-14. */
internal fun productBarcodeScanner(): BarcodeScanner = BarcodeScanning.getClient(
    BarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_EAN_13, Barcode.FORMAT_UPC_A, Barcode.FORMAT_EAN_8, Barcode.FORMAT_ITF).build(),
)

/**
 * Watches camera frames for product barcodes. `found` gets the first checksum-valid code once, then it stops;
 * `seen` reports whether any barcode is in view (for the meal camera's "Barcode in shot" shortcut).
 */
class BarcodeAnalyzer(
    private val validOnly: Boolean = true,
    private val seen: ((Boolean) -> Unit)? = null,
    private val found: ((String) -> Unit)? = null,
) : ImageAnalysis.Analyzer {
    private val scanner = productBarcodeScanner()
    @Volatile private var stopped = false
    private val main = android.os.Handler(android.os.Looper.getMainLooper())

    @OptIn(ExperimentalGetImage::class)
    override fun analyze(proxy: ImageProxy) {
        val image = proxy.image
        if (stopped || image == null) { proxy.close(); return }
        scanner.process(InputImage.fromMediaImage(image, proxy.imageInfo.rotationDegrees))
            .addOnSuccessListener { codes ->
                if (stopped) return@addOnSuccessListener
                seen?.let { report -> main.post { report(codes.isNotEmpty()) } }
                val code = codes.mapNotNull { it.rawValue }.firstOrNull { !validOnly || BarcodeLookup.isValid(it) }
                if (code != null && found != null) { stopped = true; main.post { found.invoke(code) } }
            }
            .addOnCompleteListener { proxy.close() }
    }

    fun stop() { stopped = true; scanner.close() }
}

/** Takes the full-quality photo when the shutter is tapped. */
class PhotoTaker {
    internal var capture: ImageCapture? = null
    val ready: Boolean get() = capture != null

    suspend fun take(context: Context): Bitmap = suspendCancellableCoroutine { continuation ->
        val capture = capture ?: run { continuation.resumeWithException(IllegalStateException("Camera not ready")); return@suspendCancellableCoroutine }
        capture.takePicture(ContextCompat.getMainExecutor(context), object : ImageCapture.OnImageCapturedCallback() {
            override fun onCaptureSuccess(image: ImageProxy) {
                val rotation = image.imageInfo.rotationDegrees
                val bitmap = try { image.toBitmap() } finally { image.close() }
                continuation.resume(bitmap.rotated(rotation).scaledDown(3000))
            }
            override fun onError(exception: ImageCaptureException) { continuation.resumeWithException(exception) }
        })
    }
}

/**
 * The live camera. With an `analyzer` it watches frames (barcodes); with a `photo` taker it can take a picture. Pinch to zoom.
 * The camera stops when this leaves the screen or the app goes to the background.
 */
@SuppressLint("ClickableViewAccessibility")
@Composable
fun CameraPreview(modifier: Modifier = Modifier, analyzer: ImageAnalysis.Analyzer? = null, photo: PhotoTaker? = null, failed: (String) -> Unit = {}) {
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    val onFailed by rememberUpdatedState(failed)
    val executor = remember { Executors.newSingleThreadExecutor() }
    var camera by remember { mutableStateOf<Camera?>(null) }
    val previewView = remember {
        PreviewView(context).apply {
            scaleType = PreviewView.ScaleType.FILL_CENTER
            val zoom = ScaleGestureDetector(context, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
                override fun onScale(detector: ScaleGestureDetector): Boolean {
                    val cam = camera ?: return false
                    val current = cam.cameraInfo.zoomState.value?.zoomRatio ?: 1f
                    cam.cameraControl.setZoomRatio(current * detector.scaleFactor)
                    return true
                }
            })
            setOnTouchListener { _, event -> zoom.onTouchEvent(event); true }
        }
    }
    DisposableEffect(owner, analyzer, photo) {
        val future = ProcessCameraProvider.getInstance(context)
        var provider: ProcessCameraProvider? = null
        future.addListener({
            try {
                val cameraProvider = future.get().also { provider = it }
                val preview = Preview.Builder().build().also { it.surfaceProvider = previewView.surfaceProvider }
                val useCases = mutableListOf<androidx.camera.core.UseCase>(preview)
                if (analyzer != null) {
                    useCases += ImageAnalysis.Builder().setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
                        .also { it.setAnalyzer(executor, analyzer) }
                }
                if (photo != null) {
                    val capture = ImageCapture.Builder().setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY).build()
                    photo.capture = capture
                    useCases += capture
                }
                cameraProvider.unbindAll()
                camera = cameraProvider.bindToLifecycle(owner, CameraSelector.DEFAULT_BACK_CAMERA, *useCases.toTypedArray())
            } catch (e: Exception) {
                onFailed("Couldn't start the camera. Close this and try again, or use a photo instead.")
            }
        }, ContextCompat.getMainExecutor(context))
        onDispose {
            photo?.capture = null
            camera = null
            provider?.unbindAll()
        }
    }
    DisposableEffect(Unit) { onDispose { executor.shutdown() } }
    AndroidView(factory = { previewView }, modifier = modifier)
}

/** Picks one photo with the system Photo Picker (no storage permission needed). */
@Composable
fun rememberPhotoPicker(picked: (Uri) -> Unit) =
    rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> if (uri != null) picked(uri) }

/** Picks up to `limit` photos with the system Photo Picker. */
@Composable
fun rememberPhotosPicker(limit: Int, picked: (List<Uri>) -> Unit) =
    rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(limit)) { uris -> if (uris.isNotEmpty()) picked(uris) }

val imagesOnly = androidx.activity.result.PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)

/** A picked photo the right way up, scaled so its longest side is at most `longest` pixels. */
suspend fun loadPhoto(context: Context, uri: Uri, longest: Int = 3000): Bitmap? = withContext(Dispatchers.IO) {
    runCatching {
        ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri)) { decoder, info, _ ->
            val size = info.size
            val scale = longest.toFloat() / max(size.width, size.height)
            if (scale < 1) decoder.setTargetSize((size.width * scale).roundToInt(), (size.height * scale).roundToInt())
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
        }
    }.getOrNull()
}

internal fun Bitmap.rotated(degrees: Int): Bitmap {
    if (degrees % 360 == 0) return this
    val matrix = Matrix().apply { postRotate(degrees.toFloat()) }
    return Bitmap.createBitmap(this, 0, 0, width, height, matrix, true)
}

internal fun Bitmap.scaledDown(longest: Int): Bitmap {
    val side = max(width, height)
    if (side <= longest) return this
    val scale = longest.toFloat() / side
    return Bitmap.createScaledBitmap(this, (width * scale).roundToInt(), (height * scale).roundToInt(), true)
}

/** Barcodes in a still photo, for a packet in a meal photo. */
suspend fun barcodesIn(bitmap: Bitmap): List<String> = suspendCancellableCoroutine { continuation ->
    val scanner = productBarcodeScanner()
    scanner.process(InputImage.fromBitmap(bitmap, 0))
        .addOnSuccessListener { codes -> continuation.resume(codes.mapNotNull { it.rawValue }.filter(BarcodeLookup::isValid)) }
        .addOnFailureListener { continuation.resume(emptyList()) }
        .addOnCompleteListener { scanner.close() }
}
