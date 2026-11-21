package com.isaiahgraham.leanrrr.data

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import java.time.Instant
import java.util.UUID

/**
 * JSON that reads and writes exactly what the iOS app does, so a backup made on an iPhone opens here and the other way round.
 * Swift's `JSONEncoder` leaves out nil optionals and writes every other property, which is what these settings do.
 */
val LeanrJson = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
    encodeDefaults = true
    coerceInputValues = true
    isLenient = true
    allowSpecialFloatingPointValues = false
}

val PrettyJson = Json(from = LeanrJson) { prettyPrint = true }

/** A new ID in the form Swift's `UUID().uuidString` writes: upper-case. */
fun newId(): String = UUID.randomUUID().toString().uppercase()

/** Seconds between 1970 and 2001-01-01, the reference date Swift's `JSONEncoder` counts dates from. */
private const val APPLE_EPOCH = 978_307_200.0

/** Dates as Swift's default `JSONEncoder` writes them: a number of seconds since 1 January 2001. */
object AppleDateSerializer : KSerializer<Instant> {
    override val descriptor = PrimitiveSerialDescriptor("AppleDate", PrimitiveKind.DOUBLE)
    override fun serialize(encoder: Encoder, value: Instant) =
        encoder.encodeDouble(value.epochSecond + value.nano / 1e9 - APPLE_EPOCH)
    override fun deserialize(decoder: Decoder): Instant {
        val seconds = decoder.decodeDouble() + APPLE_EPOCH
        val whole = Math.floor(seconds).toLong()
        return Instant.ofEpochSecond(whole, ((seconds - whole) * 1e9).toLong())
    }
}

typealias AppleInstant = @Serializable(AppleDateSerializer::class) Instant
