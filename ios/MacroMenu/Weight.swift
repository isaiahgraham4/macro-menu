import Foundation

struct WeightEntry: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var date: Date
    var kg: Double
    /// Set when the weight came from Apple Health, so it isn't imported twice or written back.
    var healthID: UUID?
    var isValid: Bool { kg.isFinite && (20...400).contains(kg) }
}

/// A weight to aim for, and where you started so progress can be shown.
struct WeightGoal: Codable, Hashable, Sendable {
    var kg: Double
    /// Your trend weight when the goal was set.
    var startKg: Double
    var set: Date
    var isValid: Bool { (20...400).contains(kg) && (20...400).contains(startKg) }
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

    /// How far you are from a goal weight, and when you'd get there.
    struct GoalStatus: Equatable, Sendable {
        enum Direction: Sendable { case lose, gain, reached }
        /// What the recent trend says about reaching the goal.
        enum Pace: Equatable, Sendable {
            /// Not enough weigh-ins over a week or more to measure a pace.
            case unknown
            /// Moving towards the goal, so `projected` is set.
            case towards
            /// Moving away from the goal.
            case away
            /// Barely moving.
            case flat
            /// Moving towards it, but slowly enough that it's more than five years off.
            case tooFar
        }
        var goal: Double
        /// Today's trend weight.
        var current: Double
        var direction: Direction
        /// Kilograms still to go, never negative.
        var remaining: Double
        /// 0...1, how much of the way from the starting weight you've come.
        var progress: Double
        /// Trend change per week over the last four weeks, signed.
        var weeklyChange: Double?
        var pace: Pace
        /// When the goal is reached if the trend keeps going at its current pace.
        var projected: Date?
    }

    /// Within this many kilograms of the goal counts as there.
    static let reachedWithin = 0.1
    /// A trend that moves less than this per week is treated as flat.
    static let flatPace = 0.05
    static let longestProjectionDays = 5 * 365

    /// Where you stand against a goal weight, from the smoothed trend. Nil until there's a weigh-in.
    static func goalStatus(_ goal: WeightGoal, points: [Point], now: Date = Date(), calendar: Calendar = .current) -> GoalStatus? {
        guard let current = points.last?.trend else { return nil }
        let difference = goal.kg - current
        let remaining = max(0, abs(difference))
        let direction: GoalStatus.Direction = remaining <= reachedWithin ? .reached : (difference < 0 ? .lose : .gain)
        let journey = abs(goal.startKg - goal.kg)
        var progress = 1.0
        if direction != .reached {
            let travelled = (goal.startKg - current) * (goal.startKg > goal.kg ? 1 : -1)
            progress = journey > 0 ? min(1, max(0, travelled / journey)) : 0
        }
        let weekly = weeklyChange(points, now: now, calendar: calendar)
        var status = GoalStatus(goal: goal.kg, current: current, direction: direction, remaining: remaining, progress: progress,
                                weeklyChange: weekly, pace: .unknown, projected: nil)
        guard direction != .reached, let weekly else { return status }
        let towards = difference < 0 ? -weekly : weekly
        if abs(weekly) < flatPace { status.pace = .flat; return status }
        guard towards > 0 else { status.pace = .away; return status }
        if let date = date(toCover: remaining, kgPerWeek: towards, now: now, calendar: calendar) {
            status.pace = .towards; status.projected = date
        } else {
            status.pace = .tooFar
        }
        return status
    }

    /// The date `kg` kilograms are covered at `kgPerWeek`, or nil when that's more than five years away.
    static func date(toCover kg: Double, kgPerWeek: Double, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard kg >= 0, kgPerWeek > 0 else { return nil }
        let days = (kg / kgPerWeek * 7).rounded(.up)
        guard days.isFinite, days <= Double(longestProjectionDays) else { return nil }
        return calendar.date(byAdding: .day, value: Int(days), to: now)
    }

    /// Calories a day below (losing) or above (gaining) what holds your weight steady, for a pace in kg a week.
    static func dailyCalorieDifference(kgPerWeek: Double) -> Double { kgPerWeek * caloriesPerKG / 7 }

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

extension AppData {
    /// What goes to iCloud: everything except weights read from Apple Health, because Apple doesn't allow health data
    /// from HealthKit to be stored in iCloud. Weights entered in Leanr still sync.
    var forICloud: AppData {
        var copy = self
        if copy.weights != nil { copy.weights = copy.weightLog.filter { $0.healthID == nil } }
        return copy
    }

    /// A copy from iCloud with this device's weights from Apple Health put back, since iCloud never has them.
    func keepingHealthWeights(from local: AppData) -> AppData {
        let fromHealth = local.weightLog.filter { $0.healthID != nil }
        guard !fromHealth.isEmpty else { return self }
        var copy = self
        copy.weights = weightLog.filter { $0.healthID == nil } + fromHealth
        return copy
    }
}
