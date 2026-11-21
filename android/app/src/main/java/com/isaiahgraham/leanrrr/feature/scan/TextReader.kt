package com.isaiahgraham.leanrrr.feature.scan

import android.graphics.Bitmap
import android.graphics.Rect
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.math.abs
import kotlin.math.min

/**
 * Reads text in a photo with ML Kit's on-device text recognition (the Android stand-in for Apple Vision). It runs on the
 * phone and sends nothing anywhere. A port of LabelReader (MyFoodsView.swift) and MenuReader.swift.
 */
object TextReader {
    /** Enough for a folded menu, front and back; more would only slow the reading down. */
    const val PAGE_LIMIT = 6

    suspend fun recognise(bitmap: Bitmap): Text = suspendCancellableCoroutine { continuation ->
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        recognizer.process(InputImage.fromBitmap(bitmap, 0))
            .addOnSuccessListener { continuation.resume(it) }
            .addOnFailureListener { continuation.resumeWithException(it) }
            .addOnCompleteListener { recognizer.close() }
    }

    private data class Piece(val text: String, val box: Rect)

    private fun pieces(text: Text): List<Piece> =
        text.textBlocks.flatMap { block -> block.lines.mapNotNull { line -> line.boundingBox?.let { Piece(line.text, it) } } }

    /**
     * A nutrition panel's text, one printed row per line. Recognition often returns the nutrient name and each value as
     * separate boxes, so horizontal rows are put back together, left to right, before LabelParser reads them.
     */
    suspend fun labelText(bitmap: Bitmap): String {
        val rows = mutableListOf<MutableList<Piece>>()
        for (piece in pieces(recognise(bitmap)).sortedBy { it.box.exactCenterY() }) {
            val row = rows.firstOrNull { row ->
                val anchor = row.first().box
                abs(anchor.exactCenterY() - piece.box.exactCenterY()) < min(anchor.height(), piece.box.height()) * 0.55f
            }
            if (row != null) row += piece else rows += mutableListOf(piece)
        }
        return rows.joinToString("\n") { row -> row.sortedBy { it.box.left }.joinToString("  ") { it.text } }
    }

    /** The text on one menu page as lines with positions as fractions of the page, measured from its top left. */
    suspend fun menuLines(bitmap: Bitmap, page: Int): List<MenuLine> {
        val width = bitmap.width.toDouble(); val height = bitmap.height.toDouble()
        return pieces(recognise(bitmap)).map { piece ->
            MenuLine(piece.text, piece.box.left / width, piece.box.top / height, piece.box.width() / width, piece.box.height() / height, page)
        }
    }

    /** Reads up to six menu pages and finds the dishes. */
    suspend fun readMenu(pages: List<Bitmap>): MenuParser.Result {
        val lines = mutableListOf<MenuLine>()
        for ((page, image) in pages.take(PAGE_LIMIT).withIndex()) lines += menuLines(image, page)
        return MenuParser.read(lines)
    }
}
