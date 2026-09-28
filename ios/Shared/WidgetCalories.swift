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
