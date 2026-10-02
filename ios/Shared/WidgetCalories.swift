import Foundation

/// A small read-only projection of the food log shared with the widget extension.
struct WidgetCalories: Codable, Equatable, Sendable {
    static let groupID = "group.com.isaiahgraham.MacroMenu"
    static let kind = "LeanrCaloriesLeft"
    static let premiumKind = "LeanrAllTargets"
    static let macrosKind = "LeanrMacros"
    static let streakKind = "LeanrTrackingStreak"
    var target: Double?
    var dailyCalories: [String: Double]
    // Optional so snapshots written before colour syncing still decode.
    var accent: String? = nil
    var nutrientTargets: [WidgetNutrientTarget]? = nil
    var dailyNutrients: [String: [String: Double]]? = nil
    var dailyPartialNutrients: [String: [String]]? = nil
    var premiumUnlocked: Bool? = nil
    var trackedDays: [String]? = nil
    var macroColours: [String: String]? = nil
    /// Usual meals and pinned foods for the Log again widget.
    var quickLogOptions: [WidgetQuickLog]? = nil
    var trackingDays: Set<String> { Set(trackedDays ?? Array(dailyCalories.filter { $0.value > 0 }.keys)) }
    func streak(on date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Int {
        TrackingStreak.count(days: trackingDays, on: date, calendar: calendar)
    }
    var selectedAccent: AppAccent { accent.flatMap(AppAccent.init(rawValue:)) ?? .standard }

    var isValid: Bool {
        (target.map { $0.isFinite && $0 > 0 } ?? true) &&
        dailyCalories.values.allSatisfy { $0.isFinite && $0 >= 0 } &&
        (nutrientTargets ?? []).allSatisfy { $0.target.isFinite && $0.target > 0 } &&
        (dailyNutrients ?? [:]).values.allSatisfy { $0.values.allSatisfy { $0.isFinite && $0 >= 0 } }
    }

    func eaten(on date: Date, timeZone: TimeZone = .current) -> Double {
        dailyCalories[Self.dayKey(date, timeZone: timeZone)] ?? 0
    }

    func remaining(on date: Date, timeZone: TimeZone = .current) -> Double? {
        target.map { $0 - eaten(on: date, timeZone: timeZone) }
    }

    static func dayKey(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Future entries reset the display even if the app isn't opened at midnight.
    static func timelineDates(from date: Date, calendar: Calendar = .current) -> [Date] {
        [date] + (1...7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: date))
        }
    }

    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("calories-widget.json")
    }

    static func read() -> WidgetCalories? {
        guard let url = fileURL, let bytes = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(Self.self, from: bytes), value.isValid else { return nil }
        return value
    }
}

enum TrackingStreak {
    /// Today remains available to log; yesterday's streak stays active until tonight.
    static func count(days: Set<String>, on date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Int {
        var cursor = calendar.startOfDay(for: date)
        if !days.contains(WidgetCalories.dayKey(cursor, timeZone: calendar.timeZone)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(WidgetCalories.dayKey(cursor, timeZone: calendar.timeZone)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}

struct WidgetNutrientTarget: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var unit: String
    var target: Double
    var minimum: Bool
}

/// One thing the Log again widget offers: your usual meal for a meal time, or a pinned food.
struct WidgetQuickLog: Codable, Equatable, Identifiable, Sendable {
    /// "usual:breakfast" or "pin:<food ID>".
    var id: String
    var name: String
    var calories: Double
    /// For a usual meal, the meal time it's for and logs to.
    var mealTime: String?
    /// The day it was last logged ("yyyy-MM-dd") when the snapshot was made, to show a tick once it's in today's log.
    var lastLogged: String?
    var isUsual: Bool { id.hasPrefix("usual:") }
}

/// Meal times by the clock, shared with the widget so it can switch to the next meal on its own.
enum MealSlot {
    static func at(_ date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<11: "breakfast"
        case 11..<16: "lunch"
        case 16..<22: "dinner"
        default: "snacks"
        }
    }
    /// The next times the meal time changes, soonest first.
    static func changes(after date: Date, calendar: Calendar = .current) -> [Date] {
        [5, 11, 16, 22].compactMap {
            calendar.nextDate(after: date, matching: DateComponents(hour: $0, minute: 0), matchingPolicy: .nextTime)
        }.sorted()
    }
}

extension WidgetCalories {
    static let logAgainKind = "LeanrLogAgain"
    /// What the Log again widget shows at `date`: the usual meal for that meal time first, then pinned foods.
    func quickLogs(at date: Date) -> [WidgetQuickLog] {
        let slot = MealSlot.at(date), options = quickLogOptions ?? []
        let usual = options.filter { $0.isUsual && $0.mealTime == slot }
        // A pinned food that is also the usual meal shows once.
        return usual + options.filter { pin in !pin.isUsual && !usual.contains { $0.name == pin.name } }
    }
}

/// Requests from the widget that Leanr couldn't log straight away. The app logs them, with their original time, next time it runs.
enum QuickLogQueue {
    struct Request: Codable, Equatable, Sendable { var option: String; var date: Date }
    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetCalories.groupID)?
            .appendingPathComponent("quick-log-queue.json")
    }
    static func read() -> [Request] {
        guard let url = fileURL, let bytes = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Request].self, from: bytes)) ?? []
    }
    static func write(_ requests: [Request]) {
        guard let url = fileURL else { return }
        if requests.isEmpty { try? FileManager.default.removeItem(at: url); return }
        try? JSONEncoder().encode(requests).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func add(_ option: String, at date: Date) { write(read() + [Request(option: option, date: date)]) }

    /// Shows a queued request on the widgets straight away: its calories in today's total and a tick on the option.
    static func showQueued(_ option: String, at date: Date) {
        guard var snapshot = WidgetCalories.read(), let url = WidgetCalories.fileURL,
              let index = snapshot.quickLogOptions?.firstIndex(where: { $0.id == option }),
              let item = snapshot.quickLogOptions?[index] else { return }
        let day = WidgetCalories.dayKey(date)
        snapshot.dailyCalories[day, default: 0] += item.calories
        snapshot.trackedDays = Array(Set((snapshot.trackedDays ?? []) + [day])).sorted()
        snapshot.quickLogOptions?[index].lastLogged = day
        try? JSONEncoder().encode(snapshot).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
