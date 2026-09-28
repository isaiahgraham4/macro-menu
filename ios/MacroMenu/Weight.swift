import Foundation

struct WeightEntry: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var date: Date
    var kg: Double
    /// Set when the weight came from Apple Health, so it isn't imported twice or written back.
    var healthID: UUID?
    var isValid: Bool { kg.isFinite && (20...400).contains(kg) }
}

/// A smoothed weight trend that looks past day-to-day water swings, and what it says about maintenance calories.
enum WeightTrend {
    struct Point: Hashable, Sendable {
        var date: Date
        var kg: Double
        var trend: Double
    }

    /// Kilocalories in a kilogram of body weight change, the usual rule of thumb.
    static let caloriesPerKG = 7700.0

    /// One point per day with a weigh-in (the day's last), smoothed so each day moves the trend 10% of the way to the scale.
    /// Gaps between weigh-ins move it further, as if the missing days had been weighed at the same value.
    static func points(_ entries: [WeightEntry], calendar: Calendar = .current) -> [Point] {
        let byDay = Dictionary(grouping: entries.filter(\.isValid)) { calendar.startOfDay(for: $0.date) }
        var result: [Point] = []
        for day in byDay.keys.sorted() {
            let kg = byDay[day]!.max { $0.date < $1.date }!.kg
            guard let last = result.last else { result.append(Point(date: day, kg: kg, trend: kg)); continue }
            let gap = max(1, calendar.dateComponents([.day], from: last.date, to: day).day ?? 1)
            let weight = 1 - pow(0.9, Double(gap))
            result.append(Point(date: day, kg: kg, trend: last.trend + weight * (kg - last.trend)))
        }
        return result
    }

    /// Trend change per week over the last `days` days, once weigh-ins span at least a week.
    static func weeklyChange(_ points: [Point], days: Int = 28, now: Date = Date(), calendar: Calendar = .current) -> Double? {
        guard let start = calendar.date(byAdding: .day, value: -days, to: now) else { return nil }
        let recent = points.filter { $0.date >= start }
        guard let first = recent.first, let last = recent.last,
              let span = calendar.dateComponents([.day], from: first.date, to: last.date).day, span >= 7 else { return nil }
        return (last.trend - first.trend) / Double(span) * 7
    }

    struct Maintenance: Hashable, Sendable {
        var calories: Double
        var loggedDays: Int
        var weighInDays: Int
    }

    /// Calories that would hold your weight steady: average logged intake, less the energy that went into weight change.
    /// Needs at least 10 logged days and two weeks of weigh-ins in the last `days` days (today isn't counted; it's unfinished).
    static func maintenance(logs: [String: [LogEntry]], points: [Point], days: Int = 28, now: Date = Date(), calendar: Calendar = .current) -> Maintenance? {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -days, to: today) else { return nil }
        let dayKeys = (0..<days).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }.map(dayKey)
        let intakes = dayKeys.compactMap { key -> Double? in
            guard let entries = logs[key], !entries.isEmpty else { return nil }
            return Nutrition(entries.flatMap(\.items)).cal
        }
        let window = points.filter { $0.date >= start && $0.date < today }
        guard intakes.count >= 10, let first = window.first, let last = window.last,
              let span = calendar.dateComponents([.day], from: first.date, to: last.date).day, span >= 14 else { return nil }
        let intake = intakes.reduce(0, +) / Double(intakes.count)
        let calories = intake - (last.trend - first.trend) * caloriesPerKG / Double(span)
        guard (1000...6000).contains(calories) else { return nil }
        return Maintenance(calories: calories, loggedDays: intakes.count, weighInDays: window.count)
    }
}
