package com.isaiahgraham.leanrrr.feature.settings

import androidx.compose.runtime.Composable

// Entry points other features use (keep these signatures).

/** The Even Leanrrr paywall (PremiumView.swift), opened from any locked feature. */
@Composable
fun PremiumSheet(onDismiss: () -> Unit) {
    FullScreenSheet(onDismiss) { PremiumScreen(onDismiss) }
}

/**
 * Meal reminder settings (MealReminders.swift / ReminderPromptView.swift). With no reminders on yet it asks which ones to
 * turn on, like the prompt on iOS; once any are on it shows the full reminder settings.
 */
@Composable
fun RemindersSheet(onDismiss: () -> Unit) {
    val prompt = androidx.compose.runtime.remember { !MealReminders.anyOn }
    FullScreenSheet(onDismiss) {
        if (prompt) ReminderPromptScreen(onDismiss) else ReminderSettingsScreen(onBack = onDismiss)
    }
}
