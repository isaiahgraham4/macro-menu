import Foundation
import AppIntents
import UserNotifications

/// The app's data and the services that follow it. Shared by the screens and by Siri and Shortcuts,
/// which can run without the app on screen.
@MainActor enum AppServices {
    static let store = AppStore()
    static let health = HealthSync()
    static let cloud = CloudSync()
    static let community = CommunityFoods()
    static let nav = Navigator()
    private static let router = NotificationRouter()
    private static var started = false

    /// Connects the store to Apple Health, iCloud and meal reminders. Safe to call more than once.
    static func start() {
        guard !started else { return }
        started = true
        health.store = store; cloud.store = store; community.store = store
        // Connected before? Steps arriving in the background keep the Steps widget current.
        health.watchSteps()
        // Premium turning on or off changes the app colour, the widgets and which reminders are booked.
        if Premium.subscriptionsEnabled {
            Purchases.shared.onChange = { store.refreshWidgets(); rebookReminders() }
            RevenueCatLink.start()
            Purchases.shared.start()
        }
        UNUserNotificationCenter.current().delegate = router
        store.logsChanged = { old, new in health.follow(old: old, new: new); community.follow(old: old, new: new) }
        store.saved = { cloud.markDirty(); rebookReminders() }
        // Meals, targets and weigh-ins from another device change what's reminded, too.
        store.synced = { rebookReminders() }
        // Apple Watch shows today's totals and logs with a tap, so it hears about every change.
        store.widgetsRefreshed = { WatchLink.shared.send(); LiveDay.refresh(store) }
        WatchLink.shared.start(store)
        rebookReminders()
        logQueued()
        // Foods other people shared, and any of yours still waiting to upload.
        Task { await community.refresh() }
        LeanrShortcuts.updateAppShortcutParameters()
        Task { await useSavedMenu() }
    }

    /// Food data downloaded earlier may be newer than what's built into the app; then looks for newer data online.
    private static func useSavedMenu() async {
        for dataset in onlineDatasets {
            guard let bundled = store.foodsInUse(dataset) else { continue }
            let best = await Task.detached(priority: .utility) { MenuUpdates.best(bundled: bundled, cachedAt: dataset.cacheURL) }.value
            // Only if it's still newer and still in use: a download or a change of country in Settings may have landed meanwhile.
            if let current = store.foodsInUse(dataset), MenuUpdates.acceptable(best, over: current) { use(best, for: dataset) }
        }
        await checkMenu()
    }

    /// Every dataset the chosen country uses: its menu, everyday and survey foods, and supermarket foods in Australia.
    private static var onlineDatasets: [FoodDataset] {
        [.menu(store.region), .everyday, .survey] + (store.region.hasSupermarkets ? [.supermarket] : [])
    }

    /// Switches every menu to another country's, from setup or Settings.
    @discardableResult static func useRegion(_ region: MenuRegion) -> Bool {
        guard region != store.region else { return true }
        guard store.useRegion(region) else { return false }
        LeanrShortcuts.updateAppShortcutParameters()
        if started { Task { await useSavedMenu() } }
        return true
    }

    /// The Log again widget's button: logs the option now, then waits for Apple Health so it isn't cut off if Leanr goes back to sleep.
    static func logAgain(_ option: String) async {
        start()
        if store.logAgain(option) { store.notice = WidgetCalories.waterAmount(option) != nil ? "Added water from your widget" : "Logged from your widget" }
        await health.finishPending()
    }

    /// Logs anything the widget had to queue while Leanr couldn't run it.
    static func logQueued() {
        // While saved data can't be read nothing can be logged, so leave the taps queued rather than lose them.
        guard store.loadError == nil else { return }
        let requests = QuickLogQueue.take()
        guard !requests.isEmpty else { return }
        if store.applyQueuedQuickLogs(requests) > 0 { store.notice = "Logged from your widget" }
    }

    /// Looks for newer food data online; runs at most every few hours unless forced. Overlapping calls share one check.
    static func checkMenu(force: Bool = false) async {
        if let running = menuCheck { return await running.value }
        let check = Task {
            for dataset in onlineDatasets {
                guard let current = store.foodsInUse(dataset) else { continue }
                if let newer = await MenuUpdates.check(dataset, current: current, force: force),
                   let latest = store.foodsInUse(dataset), MenuUpdates.acceptable(newer, over: latest) { use(newer, for: dataset) }
            }
        }
        menuCheck = check
        await check.value
        menuCheck = nil
    }
    private static var menuCheck: Task<Void, Never>?

    private static func use(_ foods: MenuCatalog, for dataset: FoodDataset) {
        store.useFoods(foods, for: dataset)
        LeanrShortcuts.updateAppShortcutParameters()
    }

    /// Rebooks reminders if anything they depend on changed, or the day moved on.
    static func rebookReminders() {
        let inputs = MealReminders.inputs(store.data, goals: store.goals, logReminders: Premium.isUnlocked)
        guard inputs != lastInputs else { return }
        lastInputs = inputs
        MealReminders.refresh(store.data, goals: store.goals, logReminders: Premium.isUnlocked)
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
