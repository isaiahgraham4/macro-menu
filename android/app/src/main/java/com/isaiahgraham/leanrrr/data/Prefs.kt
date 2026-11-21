package com.isaiahgraham.leanrrr.data

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember

/**
 * Small settings, the way the iOS app keeps them in UserDefaults (same key names: "accent", "leanr.region", ...).
 * Data that matters lives in `app-state.json` through [AppStore]; these are preferences.
 */
object Prefs {
    lateinit var shared: SharedPreferences
        private set

    fun init(context: Context) {
        shared = context.getSharedPreferences("leanr", Context.MODE_PRIVATE)
    }

    fun string(key: String): String? = shared.getString(key, null)
    fun string(key: String, default: String): String = shared.getString(key, null) ?: default
    fun bool(key: String, default: Boolean = false): Boolean = shared.getBoolean(key, default)
    fun double(key: String): Double? = if (shared.contains(key)) java.lang.Double.longBitsToDouble(shared.getLong(key, 0)) else null
    fun long(key: String): Long? = if (shared.contains(key)) shared.getLong(key, 0) else null

    fun set(key: String, value: String?) = shared.edit().apply { if (value == null) remove(key) else putString(key, value) }.apply()
    fun set(key: String, value: Boolean) = shared.edit().putBoolean(key, value).apply()
    fun set(key: String, value: Double) = shared.edit().putLong(key, java.lang.Double.doubleToRawLongBits(value)).apply()
    fun set(key: String, value: Long) = shared.edit().putLong(key, value).apply()
    fun remove(key: String) = shared.edit().remove(key).apply()
}

/** A string preference as Compose state that follows changes made anywhere (SwiftUI's `@AppStorage`). */
@Composable
fun rememberStringPref(key: String, default: String): MutableState<String> {
    val state = remember(key) { PrefState(key) { Prefs.string(key, default) } }
    DisposableEffect(key) {
        val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, changed ->
            if (changed == key) state.inner.value = Prefs.string(key, default)
        }
        Prefs.shared.registerOnSharedPreferenceChangeListener(listener)
        onDispose { Prefs.shared.unregisterOnSharedPreferenceChangeListener(listener) }
    }
    return state.also { it.write = { v -> Prefs.set(key, v) } }
}

@Composable
fun rememberBoolPref(key: String, default: Boolean): MutableState<Boolean> {
    val state = remember(key) { PrefState(key) { Prefs.bool(key, default) } }
    DisposableEffect(key) {
        val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, changed ->
            if (changed == key) state.inner.value = Prefs.bool(key, default)
        }
        Prefs.shared.registerOnSharedPreferenceChangeListener(listener)
        onDispose { Prefs.shared.unregisterOnSharedPreferenceChangeListener(listener) }
    }
    return state.also { it.write = { v -> Prefs.set(key, v) } }
}

private class PrefState<T>(val key: String, read: () -> T) : MutableState<T> {
    val inner = mutableStateOf(read())
    var write: (T) -> Unit = {}
    override var value: T
        get() = inner.value
        set(v) { inner.value = v; write(v) }
    override fun component1(): T = value
    override fun component2(): (T) -> Unit = { value = it }
}
