package com.isaiahgraham.leanrrr.feature.today

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.isaiahgraham.leanrrr.AppServices
import com.isaiahgraham.leanrrr.MainActivity
import com.isaiahgraham.leanrrr.R
import com.isaiahgraham.leanrrr.data.Nutrition
import com.isaiahgraham.leanrrr.data.Prefs
import com.isaiahgraham.leanrrr.data.dayKey
import com.isaiahgraham.leanrrr.data.number
import com.isaiahgraham.leanrrr.ui.AppLifecycle
import java.time.LocalDate
import java.time.ZoneId
import kotlin.math.abs
import kotlin.math.max

/**
 * Today's calories in an ongoing notification, for people who turn it on in Settings (LiveDay.swift's Live Activity).
 * It follows every change to the log, and goes at midnight, when the figures stop being today's; it comes back with the
 * next change or when Leanrrr next opens.
 */
object LiveDay {
    /** The Settings switch, the same key as on iOS. Settings should ask for notification permission when it's turned on. */
    const val STORAGE_KEY = "liveDay"
    private const val CHANNEL = "today.liveDay"
    private const val ID = 4101
    private var listener: SharedPreferences.OnSharedPreferenceChangeListener? = null

    /** Hooks the notification to the store: every save and widget refresh, the app coming to the front, and the setting. */
    fun install() {
        val store = AppServices.store
        val previous = store.widgetsRefreshed
        store.widgetsRefreshed = { previous?.invoke(); refresh() }
        AppLifecycle.onResume { refresh() }
        listener = SharedPreferences.OnSharedPreferenceChangeListener { _, key -> if (key == STORAGE_KEY) refresh() }.also {
            Prefs.shared.registerOnSharedPreferenceChangeListener(it)
        }
    }

    /** Posts, updates or removes the notification to match today's log and the setting. */
    fun refresh(context: Context = AppServices.app) {
        val manager = NotificationManagerCompat.from(context)
        val store = AppServices.store
        val target = store.goals.values["cal"]
        if (!Prefs.bool(STORAGE_KEY) || target == null || !allowed(context)) { manager.cancel(ID); return }
        ensureChannel(context)
        val today = LocalDate.now()
        val total = Nutrition((store.data.logs[dayKey(today)] ?: emptyList()).flatMap { it.items })
        val left = target - total.cal
        val title = if (left >= 0) "${left.whole.number} Cal left" else "${abs(left).whole.number} Cal over"
        val proteinTarget = store.goals.values["p"]
        val text = "Eaten ${total.cal.whole.number} of ${target.whole.number} Cal" +
            " · Protein ${total.p.whole.number}${proteinTarget?.let { " of ${it.whole.number}" } ?: ""} g"
        val open = PendingIntent.getActivity(
            context, ID, Intent(Intent.ACTION_VIEW, Uri.parse("leanr://today"), context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val midnight = today.plusDays(1).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.today_ic_notification)
            .setContentTitle(title)
            .setContentText(text)
            .setProgress(max(1, target.toInt()), total.cal.toInt().coerceIn(0, max(1, target.toInt())), false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(open)
            .setTimeoutAfter(max(60_000L, midnight - System.currentTimeMillis()))
            .build()
        try { manager.notify(ID, notification) } catch (_: SecurityException) { }
    }

    /** Whether notifications can be shown: the permission on Android 13 and later, and not switched off for the app. */
    fun allowed(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return false
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    private fun ensureChannel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL) != null) return
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "Calories left today", NotificationManager.IMPORTANCE_LOW).apply {
            description = "Today’s calories, kept in your notifications while it’s turned on in Settings."
            setShowBadge(false)
        })
    }
}

/** Today's start-up hooks (one line in Startup.kt). */
object TodayStartup {
    fun install() {
        LiveDay.install()
        // Sips older than two days are only kept to judge recent weigh-ins; tidy them when the app starts.
        val store = AppServices.store
        val sips = store.data.waterSips
        if (sips != null && sips.any { it.time.isBefore(java.time.Instant.now().minusSeconds(48 * 3600)) }) store.change { WaterWeight.tidy(it) }
    }
}
