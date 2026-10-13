import Foundation

/// The latest snapshot on Apple Watch, kept where both the watch app and its complications can read it.
enum WatchStorage {
    static let groupID = "group.com.isaiahgraham.MacroMenu"
    static let key = "watch.snapshot"
    /// The complications, one kind each.
    static let caloriesKind = "LeanrWatchCalories"
    static let proteinKind = "LeanrWatchProtein"
    static let waterKind = "LeanrWatchWater"

    private static var defaults: UserDefaults { UserDefaults(suiteName: groupID) ?? .standard }

    static func read() -> WatchSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WatchSnapshot.self, from: data)
    }

    static func write(_ snapshot: WatchSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    /// Whether a new snapshot changes anything a complication shows, so the iPhone only spends its daily allowance
    /// of complication updates when it matters.
    static func complicationsDiffer(_ a: WatchSnapshot?, _ b: WatchSnapshot) -> Bool {
        guard let a else { return true }
        return a.day != b.day || a.calories.rounded() != b.calories.rounded() || a.protein.rounded() != b.protein.rounded()
            || a.water != b.water || a.calorieTarget != b.calorieTarget || a.proteinTarget != b.proteinTarget || a.waterTarget != b.waterTarget
    }
}
