package com.isaiahgraham.leanrrr.feature.settings

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ProcessLifecycleOwner
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.MainActivity
import com.isaiahgraham.leanrrr.R
import com.isaiahgraham.leanrrr.data.AppData
import com.isaiahgraham.leanrrr.data.Goals
import com.isaiahgraham.leanrrr.data.LeanrJson
import com.isaiahgraham.leanrrr.data.LogEntry
import com.isaiahgraham.leanrrr.data.MealTime
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Prefs
import com.isaiahgraham.leanrrr.data.WeightEntry
import com.isaiahgraham.leanrrr.data.dayKey
import com.isaiahgraham.leanrrr.data.number
import kotlinx.serialization.Serializable
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZonedDateTime
import java.time.temporal.TemporalAdjusters
import kotlin.math.abs
import kotlin.math.roundToLong

/**
 * "Nothing logged for lunch yet" nudges (MealReminders.swift). A notification can't check the log when it fires, so reminders
 * are booked two weeks ahead with AlarmManager and today's is taken back as soon as that meal is logged.
 * The fourth reminder is the late-night one, kept under the Snacks slot: it only goes out if nothing at all was logged that day.
 * Water reminders sit alongside them: spaced through the day, and dropped for a day once its water target is reached.
 */
object MealReminders {
    val meals = listOf(MealTime.BREAKFAST, MealTime.LUNCH, MealTime.DINNER, MealTime.SNACKS)
    /** What a reminder is called, since the Snacks slot is the late-night check. */
    fun title(meal: MealTime): String = if (meal == MealTime.SNACKS) "Late night" else meal.title
    private const val PREFIX = "reminder."
    private const val DAYS = 14L

    const val WEEKLY_KEY = "reminder.weekly.on"
    val weeklyOn: Boolean get() = Prefs.bool(WEEKLY_KEY)
    const val WEEKLY_TIME_KEY = "reminder.weekly.minutes"
    /** 10 pm, in minutes after midnight. */
    const val DEFAULT_WEEKLY_MINUTES = 22 * 60

    /** When on Sunday the weekly review goes out. Choosing the time comes with Premium; without it, it's always the default. */
    fun weeklyMinutes(unlocked: Boolean): Int = if (!unlocked) DEFAULT_WEEKLY_MINUTES else Prefs.long(WEEKLY_TIME_KEY)?.toInt() ?: DEFAULT_WEEKLY_MINUTES

    /** The next Sunday at that time. */
    fun nextReview(after: ZonedDateTime, minutes: Int = DEFAULT_WEEKLY_MINUTES): ZonedDateTime {
        var date = after.toLocalDate().with(TemporalAdjusters.nextOrSame(DayOfWeek.SUNDAY))
        var at = date.atTime(minutes / 60, minutes % 60).atZone(after.zone)
        if (!at.isAfter(after)) { date = date.plusWeeks(1); at = date.atTime(minutes / 60, minutes % 60).atZone(after.zone) }
        return at
    }

    fun enabledKey(meal: MealTime) = "reminder.${meal.raw}.on"
    fun timeKey(meal: MealTime) = "reminder.${meal.raw}.minutes"
    fun defaultMinutes(meal: MealTime): Int = when (meal) {
        MealTime.BREAKFAST -> 9 * 60 + 30
        MealTime.LUNCH -> 13 * 60 + 30
        MealTime.DINNER -> 19 * 60 + 30
        MealTime.SNACKS -> 21 * 60 + 30
    }
    fun isOn(meal: MealTime): Boolean = Prefs.bool(enabledKey(meal))
    /** Minutes after midnight. */
    fun minutes(meal: MealTime): Int = Prefs.long(timeKey(meal))?.toInt() ?: defaultMinutes(meal)

    /** Different wording each day, in a fixed order so rebooking never changes what tomorrow's reminder will say. */
    private val phrases: Map<MealTime, List<Pair<String, String>>> = mapOf(
        MealTime.BREAKFAST to listOf(
            "Morning! Breakfast?" to "Nothing logged yet. Add it in a couple of taps.",
            "Start the day on the board" to "Log your breakfast and get your day going.",
            "Had breakfast yet?" to "Log it now so you don't forget later.",
            "Breakfast check-in" to "Nothing's logged for breakfast. Tap to add it.",
            "Fuel up, then log it" to "Your breakfast isn't in Leanrrr yet.",
            "Skipping breakfast?" to "No problem. If you ate something, tap to log it."),
        MealTime.LUNCH to listOf(
            "Lunch o'clock" to "Nothing logged for lunch yet. Tap to add it.",
            "Midday check-in" to "What's for lunch? Log it while it's fresh.",
            "Had lunch yet?" to "Add it now and keep your day accurate.",
            "Lunch break" to "Your lunch isn't logged yet. It only takes a moment.",
            "Don't let lunch slip by" to "Tap to log what you ate.",
            "Halfway through the day" to "Nothing logged for lunch. Add it now?"),
        MealTime.DINNER to listOf(
            "Dinner time" to "Nothing logged for dinner yet. Tap to add it.",
            "What's for dinner?" to "Log it as you go and keep your day on track.",
            "Dinner check-in" to "Your dinner isn't in Leanrrr yet.",
            "Evening! Had dinner?" to "Add it now while you remember what was on the plate.",
            "Nearly end of day" to "Log your dinner to keep your numbers right.",
            "Dinner's not logged" to "It takes a few seconds. Tap to add it."),
        MealTime.SNACKS to listOf(
            "Before you wind down" to "Nothing logged today. Add what you ate to keep your streak going.",
            "Last call for today" to "You haven't logged anything today. A quick log counts.",
            "Still time to log today" to "Add what you've eaten and close out your day.",
            "Don't lose your streak" to "Nothing's logged today. Tap to add a meal or snack.",
            "End-of-day check-in" to "Log today's food before bed. Even a quick one counts.",
            "Day's nearly done" to "Nothing logged yet today. Tap to add it."),
    )

    /** Days since the start of the era, so the wording follows the calendar day. */
    private fun ordinal(date: LocalDate): Long = date.toEpochDay() + 719_163

    /** The reminder's wording for that day. Consecutive days always differ. */
    fun message(meal: MealTime, date: LocalDate): Pair<String, String> {
        val bank = phrases[meal] ?: phrases.getValue(MealTime.DINNER)
        return bank[(ordinal(date) % bank.size).toInt()]
    }

    // Water

    const val WATER_ON_KEY = "reminder.water.on"
    const val WATER_FROM_KEY = "reminder.water.from"
    const val WATER_UNTIL_KEY = "reminder.water.until"
    const val WATER_EVERY_KEY = "reminder.water.every"
    val waterOn: Boolean get() = Prefs.bool(WATER_ON_KEY)

    /** Water reminders from `from` until `until` (minutes after midnight), every `everyHours` hours. */
    data class WaterSchedule(val from: Int = 9 * 60, val until: Int = 20 * 60, val everyHours: Int = 2) {
        companion object { val hourChoices = listOf(1, 2, 3, 4) }
    }

    val waterSchedule: WaterSchedule
        get() {
            val standard = WaterSchedule()
            val from = Prefs.long(WATER_FROM_KEY)?.toInt() ?: standard.from
            val until = Prefs.long(WATER_UNTIL_KEY)?.toInt() ?: standard.until
            val every = Prefs.long(WATER_EVERY_KEY)?.toInt() ?: standard.everyHours
            return WaterSchedule(from.coerceIn(0, 23 * 60 + 59), until.coerceIn(0, 23 * 60 + 59),
                if (every in WaterSchedule.hourChoices) every else standard.everyHours)
        }

    /** The times of day a schedule fires, as minutes after midnight. Always at least one: the start. */
    fun waterTimes(schedule: WaterSchedule): List<Int> {
        val step = maxOf(1, schedule.everyHours) * 60
        return (schedule.from..maxOf(schedule.from, schedule.until) step step).toList()
    }

    data class WaterReminder(val id: String, val slot: Int, val date: ZonedDateTime)

    /** Water reminders over the next two weeks. A day whose target is already reached has none, and none are in the past. */
    fun waterPlan(schedule: WaterSchedule, water: Map<String, Double>, target: Double, now: ZonedDateTime = ZonedDateTime.now()): List<WaterReminder> {
        val today = now.toLocalDate(); val times = waterTimes(schedule)
        return (0 until DAYS).flatMap { offset ->
            val day = today.plusDays(offset); val key = dayKey(day)
            if (target > 0 && (water[key] ?: 0.0) >= target) return@flatMap emptyList()
            times.mapIndexedNotNull { slot, minutes ->
                val date = day.atTime(minutes / 60, minutes % 60).atZone(now.zone)
                if (date.isAfter(now)) WaterReminder("reminder.water.$key.$minutes", slot, date) else null
            }
        }
    }

    private val waterPhrases = listOf(
        "Time for some water" to "Have a glass, then tap to log it.",
        "Water break" to "A quick glass now keeps the day on track.",
        "Sip, sip" to "When did you last have water? Tap to log it.",
        "Stay topped up" to "Have a glass and log it in a tap.",
        "Drink up" to "A glass of water, then log it in Leanrrr.",
        "Hydration check" to "Water time. It takes a second to log.")

    /** The wording for one water reminder. Consecutive days differ, and so do neighbouring reminders on the same day. */
    fun waterMessage(date: LocalDate, slot: Int): Pair<String, String> = waterPhrases[((ordinal(date) + slot) % waterPhrases.size).toInt()]

    /** The most reminders kept booked at once, soonest first (iOS keeps only 64 pending notifications; the same cap keeps AlarmManager light). */
    const val BOOKING_LIMIT = 64

    @Serializable
    data class Booking(val id: String, val at: Long, val title: String, val body: String, val channel: String)

    /** Meal and water reminders in the order they'll fire, cut to what fits. `reserved` leaves room for other notifications. */
    fun bookings(meals: List<Reminder>, water: List<WaterReminder>, reserved: Int = 0): List<Booking> {
        val all = meals.map { r ->
            val (title, body) = message(r.meal, r.date.toLocalDate())
            Booking(r.id, r.date.toInstant().toEpochMilli(), title, body, CHANNEL_MEALS)
        } + water.map { r ->
            val (title, body) = waterMessage(r.date.toLocalDate(), r.slot)
            Booking(r.id, r.date.toInstant().toEpochMilli(), title, body, CHANNEL_WATER)
        }
        return all.sortedWith(compareBy({ it.at }, { it.id })).take(maxOf(0, BOOKING_LIMIT - reserved))
    }

    data class Reminder(val id: String, val meal: MealTime, val date: ZonedDateTime)

    /** Reminders still to come over the next two weeks, skipping meals already logged that day. */
    fun plan(settings: List<Pair<MealTime, Int>>, logs: Map<String, List<LogEntry>>, now: ZonedDateTime = ZonedDateTime.now()): List<Reminder> {
        val today = now.toLocalDate()
        return (0 until DAYS).flatMap { offset ->
            val day = today.plusDays(offset); val key = dayKey(day)
            val entries = logs[key] ?: emptyList(); val logged = entries.mapNotNull { it.mealTime }.toSet()
            settings.mapNotNull { (meal, minutes) ->
                // Late night is a check on the whole day; the others on their own meal.
                val covered = if (meal == MealTime.SNACKS) entries.isNotEmpty() else meal in logged
                // The chosen clock time, so daylight-saving days keep it.
                val date = day.atTime(minutes / 60, minutes % 60).atZone(now.zone)
                if (covered || !date.isAfter(now)) null else Reminder("reminder.${meal.raw}.$key", meal, date)
            }
        }
    }

    /** What the booked reminders depend on: the log near the booking window, targets, weigh-ins and water. Cheap to compare. */
    data class Inputs(
        val logs: Map<String, List<LogEntry>>,
        val goals: Map<String, Double>,
        val dayGoals: Map<String, Map<String, Double>>,
        val weighIns: Int,
        val lastWeight: WeightEntry?,
        val water: Map<String, Double>,
        val waterTarget: Double,
        val logReminders: Boolean,
        val settings: String,
        val day: String,
    )

    private fun settingsSignature(): String = (meals.map { "${isOn(it)}${minutes(it)}" } +
        listOf("$waterOn$waterSchedule", "$weeklyOn${Prefs.long(WEEKLY_TIME_KEY)}")).joinToString("|")

    fun inputs(data: AppData, goals: Goals, logReminders: Boolean): Inputs {
        val today = LocalDate.now()
        val keys = (-7L until DAYS).map { dayKey(today.plusDays(it)) }
        return Inputs(
            logs = keys.mapNotNull { k -> data.logs[k]?.let { k to it } }.toMap(),
            goals = goals.values,
            dayGoals = keys.mapNotNull { k -> data.dayGoals[k]?.let { k to it.values } }.toMap(),
            weighIns = data.weightLog.size, lastWeight = data.weightLog.maxByOrNull { it.date },
            water = keys.mapNotNull { k -> data.water?.get(k)?.let { k to it } }.toMap(),
            waterTarget = waterTarget(data), logReminders = logReminders, settings = settingsSignature(), day = dayKey(today),
        )
    }

    fun waterTarget(data: AppData): Double = data.waterTarget ?: 2000.0

    private const val BOOKED_KEY = "reminder.booked"
    const val CHANNEL_MEALS = "meal-reminders"
    const val CHANNEL_WATER = "water-reminders"
    const val CHANNEL_WEEKLY = "weekly-review"
    const val WEEKLY_PREFIX = "reminder.weekly."

    /**
     * Rebooks reminders after the log or the settings change. The weekly review's text is worked out now, so it's rebooked
     * with every change to stay current. With `logReminders` off (Premium locked), the meal and water reminders are cleared
     * and only the weekly review remains.
     */
    @Synchronized
    fun refresh(context: Context, data: AppData, goals: Goals, logReminders: Boolean) {
        val settings = if (logReminders) meals.filter(::isOn).map { it to minutes(it) } else emptyList()
        val upcoming = plan(settings, data.logs)
        val watering = if (logReminders && waterOn) waterPlan(waterSchedule, data.water ?: emptyMap(), waterTarget(data)) else emptyList()
        var weekly: Booking? = null
        if (weeklyOn) {
            val date = nextReview(ZonedDateTime.now(), weeklyMinutes(logReminders))
            val review = WeekSummary.make(data, goals, date.toLocalDate())
            if (review.loggedDays > 0) weekly = Booking("$WEEKLY_PREFIX${dayKey(date.toLocalDate())}", date.toInstant().toEpochMilli(),
                "Your week in Leanrrr", review.summary, CHANNEL_WEEKLY)
        }
        cancelBooked(context)
        if ((upcoming.isEmpty() && watering.isEmpty() && weekly == null) || !notificationsAllowed(context)) return
        val all = bookings(upcoming, watering, reserved = if (weekly == null) 0 else 1) + listOfNotNull(weekly)
        ensureChannels(context)
        all.forEach { schedule(context, it) }
        Prefs.set(BOOKED_KEY, LeanrJson.encodeToString(kotlinx.serialization.builtins.ListSerializer(Booking.serializer()), all))
    }

    private fun alarmIntent(context: Context, booking: Booking?, id: String): PendingIntent? {
        val intent = Intent(context, ReminderReceiver::class.java).setAction(ReminderReceiver.ACTION_FIRE).setData(Uri.parse("leanr-reminder://$id"))
        if (booking != null) intent.putExtra("id", booking.id).putExtra("title", booking.title).putExtra("body", booking.body).putExtra("channel", booking.channel)
        val flags = PendingIntent.FLAG_IMMUTABLE or if (booking == null) PendingIntent.FLAG_NO_CREATE else PendingIntent.FLAG_UPDATE_CURRENT
        return PendingIntent.getBroadcast(context, 0, intent, flags)
    }

    private fun schedule(context: Context, booking: Booking) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pending = alarmIntent(context, booking, booking.id) ?: return
        runCatching {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarms.canScheduleExactAlarms()) {
                alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, booking.at, pending)
            } else {
                // Without the exact-alarm permission, a ten-minute window keeps it close to the time chosen.
                alarms.setWindow(AlarmManager.RTC_WAKEUP, booking.at, 10 * 60 * 1000L, pending)
            }
        }
    }

    private fun cancelBooked(context: Context) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val booked = Prefs.string(BOOKED_KEY)?.let {
            runCatching { LeanrJson.decodeFromString(kotlinx.serialization.builtins.ListSerializer(Booking.serializer()), it) }.getOrNull()
        } ?: emptyList()
        booked.forEach { b -> alarmIntent(context, null, b.id)?.let { alarms.cancel(it); it.cancel() } }
        Prefs.remove(BOOKED_KEY)
    }

    /** Takes back every booked reminder (Delete all my data). */
    fun cancelAll(context: Context) = cancelBooked(context)

    fun ensureChannels(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(NotificationChannel(CHANNEL_MEALS, "Meal reminders", NotificationManager.IMPORTANCE_DEFAULT)
            .apply { description = "A nudge when nothing's logged for a meal yet." })
        manager.createNotificationChannel(NotificationChannel(CHANNEL_WATER, "Water reminders", NotificationManager.IMPORTANCE_DEFAULT)
            .apply { description = "Spaced through the day until you reach your water target." })
        manager.createNotificationChannel(NotificationChannel(CHANNEL_WEEKLY, "Weekly review", NotificationManager.IMPORTANCE_DEFAULT)
            .apply { description = "Your week in Leanrrr, on Sundays." })
    }

    /** Whether the app may post notifications (POST_NOTIFICATIONS on Android 13 and later, and not turned off in Settings). */
    fun notificationsAllowed(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return false
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    /** Whether every meal reminder and the water reminder are on. */
    val allOn: Boolean get() = meals.all(::isOn) && waterOn
    /** Whether any meal or water reminder is on. */
    val anyOn: Boolean get() = meals.any(::isOn) || waterOn

    /** Turns on every meal reminder and the water reminder at their usual times (after permission has been granted). */
    fun enableAll() {
        meals.forEach { Prefs.set(enabledKey(it), true) }
        Prefs.set(WATER_ON_KEY, true)
    }

    /** Turns on just the chosen reminders (after permission has been granted). */
    fun enable(chosen: Set<MealTime>, water: Boolean) {
        chosen.forEach { Prefs.set(enabledKey(it), true) }
        if (water) Prefs.set(WATER_ON_KEY, true)
    }

    // Rebooking from the store

    private var lastInputs: Inputs? = null

    /** Rebooks if anything the reminders depend on changed, or the day moved on. */
    fun rebook(force: Boolean = false) {
        val store = AppServices.store
        val unlocked = com.isaiahgraham.leanrrr.billing.Premium.isUnlocked
        val inputs = inputs(store.data, store.goals, unlocked)
        if (!force && inputs == lastInputs) return
        lastInputs = inputs
        refresh(AppServices.app, store.data, store.goals, unlocked)
    }
}

/** Posts a booked reminder when its alarm goes off. Meal and water reminders don't show while Leanrrr is open, as on iOS. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // A reboot or app update clears alarms; the app starting (LeanrApp → Startup) has already rebooked them by now.
        if (intent.action != ACTION_FIRE) { MealReminders.rebook(force = true); return }
        val id = intent.getStringExtra("id") ?: return
        val weekly = id.startsWith(MealReminders.WEEKLY_PREFIX)
        val foreground = runCatching { ProcessLifecycleOwner.get().lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED) }.getOrDefault(false)
        if (foreground && !weekly) return
        if (!MealReminders.notificationsAllowed(context)) return
        MealReminders.ensureChannels(context)
        val open = Intent(context, MainActivity::class.java).setData(Uri.parse("leanr://today"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        if (weekly) open.putExtra(EXTRA_WEEKLY_REVIEW, true)
        val content = PendingIntent.getActivity(context, id.hashCode(), open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = NotificationCompat.Builder(context, intent.getStringExtra("channel") ?: MealReminders.CHANNEL_MEALS)
            .setSmallIcon(R.drawable.settings_ic_notification)
            .setContentTitle(intent.getStringExtra("title"))
            .setContentText(intent.getStringExtra("body"))
            .setStyle(NotificationCompat.BigTextStyle().bigText(intent.getStringExtra("body")))
            .setContentIntent(content)
            .setAutoCancel(true)
            .setGroup(intent.getStringExtra("channel"))
            .build()
        runCatching { NotificationManagerCompat.from(context).notify(id, 0, notification) }
    }

    companion object {
        const val ACTION_FIRE = "com.isaiahgraham.leanrrr.REMINDER"
        /** Set on the weekly review's tap, so Leanrrr opens the weekly review (see SettingsInstall). */
        const val EXTRA_WEEKLY_REVIEW = "leanr.weeklyReview"
    }
}

/** The one-off question that offers reminders to someone who has come back after a few days away and has none set up. */
object ReminderPrompt {
    const val LAST_ACTIVE_KEY = "leanr.lastActive"
    const val ASKED_KEY = "leanr.reminderPrompt.asked"
    /** How long away counts as "a while", and how long to leave it after asking before asking again (seconds). */
    const val AWAY_FOR = 3L * 24 * 3600
    const val ASK_AGAIN_AFTER = 30L * 24 * 3600

    /**
     * Only for someone who can choose reminders, has none on, hasn't turned notifications off, was away a while, and wasn't
     * asked recently. A first launch has no last visit, so it never asks straight away.
     */
    fun shouldShow(now: Long, lastActive: Long?, lastAsked: Long?, anyReminderOn: Boolean, notificationsDenied: Boolean, canChoose: Boolean): Boolean {
        if (!canChoose || anyReminderOn || notificationsDenied || lastActive == null || now - lastActive < AWAY_FOR) return false
        if (lastAsked != null && now - lastAsked < ASK_AGAIN_AFTER) return false
        return true
    }
}

/**
 * The seven days ending on a day, enough for the Sunday notification (WeeklyReview.make and .summary, kept here so reminders
 * don't wait on the Progress screens): days logged, total and average calories, protein days and the weight trend.
 */
internal data class WeekSummary(val loggedDays: Int, val totalCalories: Double, val averageCalories: Double?, val proteinTarget: Double?,
                                val proteinDays: Int, val weightChange: Double?) {
    val summary: String
        get() {
            if (loggedDays <= 0) return "Nothing logged this week yet."
            val parts = mutableListOf("Logged $loggedDays of 7 days", "${totalCalories.roundToLong().toDouble().number} Cal in total")
            averageCalories?.let { parts += "avg ${it.roundToLong().toDouble().number}" }
            if (proteinTarget != null) parts += "protein target hit $proteinDays ${if (proteinDays == 1) "day" else "days"}"
            weightChange?.let { parts += "trend ${signed(it)} kg" }
            return parts.joinToString(" · ") + "."
        }

    companion object {
        private fun signed(kg: Double): String {
            val rounded = Math.round(kg * 10) / 10.0
            return (if (rounded > 0) "+" else if (rounded < 0) "−" else "") + abs(rounded).number
        }

        fun make(data: AppData, goals: Goals, end: LocalDate): WeekSummary {
            val first = end.minusDays(6)
            var calories = 0.0; var count = 0; var proteinDays = 0
            val proteinTargets = mutableListOf<Double>()
            for (i in 0L until 7L) {
                val key = dayKey(first.plusDays(i))
                val entries = data.logs[key] ?: emptyList()
                if (entries.isEmpty()) continue
                val total = Nutrition(entries.flatMap { it.items }); val target = data.dayGoals[key] ?: goals
                calories += total.cal; count += 1
                target.values["p"]?.let { p -> proteinTargets += p; if (total.p >= p) proteinDays += 1 }
            }
            val points = TrendMath.points(data.weightLog)
            val inWeek = points.lastOrNull { !it.day.isBefore(first) && !it.day.isAfter(end) }
            val before = points.lastOrNull { it.day.isBefore(first) }
            return WeekSummary(count, calories, if (count > 0) calories / count else null, proteinTargets.takeIf { it.isNotEmpty() }?.average(),
                proteinDays, if (inWeek != null && before != null) inWeek.trend - before.trend else null)
        }
    }
}

