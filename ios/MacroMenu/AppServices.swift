import Foundation
import AppIntents
import UserNotifications

/// The app's data and the services that follow it. Shared by the screens and by Siri and Shortcuts,
/// which can run without the app on screen.
@MainActor enum AppServices {
    static let store = AppStore()
    static let health = HealthSync()
    static let cloud = CloudSync()
    static let nav = Navigator()
    private static let router = NotificationRouter()
    private static var started = false

    /// Connects the store to Apple Health, iCloud and meal reminders. Safe to call more than once.
    static func start() {
        guard !started else { return }
        started = true
        health.store = store; cloud.store = store
        UNUserNotificationCenter.current().delegate = router
        store.logsChanged = { old, new in health.follow(old: old, new: new) }
        store.saved = { cloud.markDirty(); rebookReminders() }
        // Meals, targets and weigh-ins from another device change what's reminded, too.
        store.synced = { rebookReminders() }
        rebookReminders()
        LeanrShortcuts.updateAppShortcutParameters()
        // A menu downloaded earlier may be newer than the one built into the app.
        let bundled = store.catalog
        Task {
            let best = await Task.detached(priority: .utility) { MenuUpdates.best(bundled: bundled) }.value
            // Only if it's still newer: a download may have landed while the saved copy was being read.
            if MenuUpdates.acceptable(best, over: store.catalog) { useMenu(best) }
            await checkMenu()
        }
    }

    /// Looks for a newer menu online; runs at most every few hours unless forced. Overlapping calls share one check.
    static func checkMenu(force: Bool = false) async {
        if let running = menuCheck { return await running.value }
        let check = Task {
            if let menu = await MenuUpdates.check(current: store.catalog, force: force),
               MenuUpdates.acceptable(menu, over: store.catalog) { useMenu(menu) }
        }
        menuCheck = check
        await check.value
        menuCheck = nil
    }
    private static var menuCheck: Task<Void, Never>?

    private static func useMenu(_ menu: MenuCatalog) {
        store.useMenu(menu)
        LeanrShortcuts.updateAppShortcutParameters()
    }

    /// Rebooks reminders if anything they depend on changed, or the day moved on.
    static func rebookReminders() {
        let inputs = MealReminders.inputs(store.data, goals: store.goals)
        guard inputs != lastInputs else { return }
        lastInputs = inputs
        MealReminders.refresh(store.data, goals: store.goals)
    }
    private static var lastInputs: MealReminders.Inputs?
}

/// Opens the right screen when a notification is tapped. Meal reminders don't show while Leanr is open.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let weekly = response.notification.request.identifier.hasPrefix("reminder.weekly.")
        await MainActor.run {
            AppServices.nav.tab = .today
            if weekly { AppServices.nav.showWeeklyReview = true }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        notification.request.identifier.hasPrefix("reminder.weekly.") ? [.banner, .list, .sound] : []
    }
}
