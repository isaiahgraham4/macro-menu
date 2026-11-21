package com.isaiahgraham.leanrrr.data

import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.text.NumberFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Currency
import java.util.Locale
import kotlin.math.roundToLong

private val oneDecimal = DecimalFormat("#,##0.#", DecimalFormatSymbols(Locale.US))
private val twoDecimals = DecimalFormat("#,##0.##", DecimalFormatSymbols(Locale.US))

/** Up to one decimal place with thousands separators: "2,200", "28.7". Swift's `Double.number`. */
val Double.number: String get() = if (isFinite()) oneDecimal.format(if (this == -0.0) 0.0 else this) else "–"
/** Rounded to one decimal place. */
val Double.tenth: Double get() = (this * 10).roundToLong() / 10.0
/** Rounded to two decimal places, for body weight from scales that read to 10 g. */
val Double.hundredth: Double get() = (this * 100).roundToLong() / 100.0
/** A weight in kg as typed: up to two decimal places, no trailing zeros. */
val Double.kgText: String get() = twoDecimals.format(this)

/** "A$12.50"-style money in Australian dollars, the way the iOS app writes it. */
fun Double.aud(): String = NumberFormat.getCurrencyInstance(Locale.forLanguageTag("en-AU")).apply {
    currency = Currency.getInstance("AUD")
}.format(this)

private val dayFormat = DateTimeFormatter.ofPattern("yyyy-MM-dd", Locale.US)

/** The log's key for a day: "2026-11-21", in the device's time zone. */
fun dayKey(date: Instant, zone: ZoneId = ZoneId.systemDefault()): String = date.atZone(zone).toLocalDate().format(dayFormat)
fun dayKey(date: LocalDate): String = date.format(dayFormat)
fun parseDayKey(key: String): LocalDate? = runCatching { LocalDate.parse(key, dayFormat) }.getOrNull()
fun today(): LocalDate = LocalDate.now()
fun LocalDate.startInstant(zone: ZoneId = ZoneId.systemDefault()): Instant = atStartOfDay(zone).toInstant()
