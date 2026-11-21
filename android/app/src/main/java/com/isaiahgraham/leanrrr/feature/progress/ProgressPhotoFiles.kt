package com.isaiahgraham.leanrrr.feature.progress

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import com.isaiahgraham.leanrrr.data.AppleInstant
import com.isaiahgraham.leanrrr.data.LeanrJson
import com.isaiahgraham.leanrrr.data.newId
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.time.Instant
import kotlin.math.max

/** A progress photo. Only this small record is kept in the index; the picture is its own file. */
@Serializable
data class ProgressPhoto(
    val id: String = newId(),
    val date: AppleInstant,
    val note: String? = null,
)

/**
 * Progress photos on this phone: a folder of JPEGs and an index (ProgressPhotoFiles.swift). They aren't part of `AppData`,
 * so they never reach backups or exports.
 */
class ProgressPhotoFiles(val directory: File) {
    private val index get() = File(directory, "index.json")
    private fun file(id: String) = File(directory, "$id.jpg")

    /** Newest first. A record whose picture has gone is left out. */
    fun load(): List<ProgressPhoto> {
        val photos = runCatching { LeanrJson.decodeFromString(ListSerializer(ProgressPhoto.serializer()), index.readText()) }.getOrNull() ?: return emptyList()
        return photos.filter { file(it.id).exists() }.sortedByDescending { it.date }
    }

    private fun save(photos: List<ProgressPhoto>) {
        directory.mkdirs()
        val temp = File(directory, "index.json.tmp")
        temp.writeText(LeanrJson.encodeToString(ListSerializer(ProgressPhoto.serializer()), photos))
        if (!temp.renameTo(index)) { index.delete(); check(temp.renameTo(index)) { "Couldn't save the photo list." } }
    }

    /** Stores a picture (already a JPEG, see [prepared]) and records it. */
    fun add(jpeg: ByteArray, date: Instant, note: String? = null): ProgressPhoto {
        directory.mkdirs()
        val photo = ProgressPhoto(date = date, note = note)
        file(photo.id).writeBytes(jpeg)
        try { save(load() + photo) } catch (e: Exception) { file(photo.id).delete(); throw e }
        return photo
    }

    /** Changes a photo's date or note. */
    fun update(photo: ProgressPhoto) {
        val photos = load().toMutableList()
        val i = photos.indexOfFirst { it.id == photo.id }
        if (i < 0) return
        photos[i] = photo
        save(photos)
    }

    fun remove(id: String) {
        save(load().filter { it.id != id })
        file(id).delete()
    }

    /** Deletes every photo and the index. For "Delete all my data". */
    fun removeAll() { directory.deleteRecursively() }

    fun data(id: String): ByteArray? = runCatching { file(id).readBytes() }.getOrNull()

    /** A small picture for a grid, decoded at a reduced size. */
    fun thumbnail(id: String, longestSide: Int = 400): Bitmap? = data(id)?.let { scaled(it, longestSide) }

    fun image(id: String): Bitmap? = data(id)?.let { scaled(it, 2000) }

    companion object {
        fun standard(context: Context) = ProgressPhotoFiles(File(context.filesDir, "MacroMenu/ProgressPhotos"))

        /** A photo as a JPEG at most `longestSide` pixels on its longest edge and upright. Null when the data isn't an image. */
        fun prepared(data: ByteArray, longestSide: Int = 1600, quality: Int = 80): ByteArray? {
            val image = scaled(data, longestSide) ?: return null
            val out = ByteArrayOutputStream()
            if (!image.compress(Bitmap.CompressFormat.JPEG, quality, out)) return null
            return out.toByteArray()
        }

        /** Decodes at no more than `longestSide`, turned upright from the camera's orientation tag. */
        fun scaled(data: ByteArray, longestSide: Int): Bitmap? {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
            var sample = 1
            while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= longestSide) sample *= 2
            val decoded = BitmapFactory.decodeByteArray(data, 0, data.size, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
            val longest = max(decoded.width, decoded.height)
            val fitted = if (longest > longestSide) {
                val scale = longestSide.toFloat() / longest
                Bitmap.createScaledBitmap(decoded, (decoded.width * scale).toInt().coerceAtLeast(1), (decoded.height * scale).toInt().coerceAtLeast(1), true)
            } else decoded
            val rotation = runCatching {
                when (ExifInterface(ByteArrayInputStream(data)).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                    ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                    ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                    ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                    else -> 0f
                }
            }.getOrDefault(0f)
            if (rotation == 0f) return fitted
            return Bitmap.createBitmap(fitted, 0, 0, fitted.width, fitted.height, Matrix().apply { postRotate(rotation) }, true)
        }
    }
}
