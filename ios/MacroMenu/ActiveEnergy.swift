import Foundation

/// Calories burnt: the active energy Apple Health holds for each day. Like steps, the figures come from Health and are only
/// held in memory, never saved in Leanr's data or iCloud copy. It counts movement, not the calories the body uses at rest.
enum ActiveEnergy {
    /// 412.4 → "412".
    static func text(_ calories: Double) -> String {
        calories.rounded().formatted(.number.precision(.fractionLength(0)))
    }

    struct Summary: Equatable, Sendable {
        /// Average over the days that have any recorded.
        var average: Double?
        var countedDays: Int
        var total: Double
        var best: Double?
    }

    /// Active energy across the given days (day keys). A day with nothing recorded isn't counted, so a watch left on the
    /// charger doesn't pull the average down to zero.
    static func summary(_ energy: [String: Double], days: [String]) -> Summary {
        let counted = days.compactMap { energy[$0] }.filter { $0 > 0 }
        let total = counted.reduce(0, +)
        return Summary(average: counted.isEmpty ? nil : total / Double(counted.count), countedDays: counted.count, total: total, best: counted.max())
    }

    /// The average over the fortnight before `date`, not counting `date` itself, which is still in progress.
    /// Nil until three days have anything recorded: too few days say little about a typical one.
    static func recentAverage(_ energy: [String: Double], before date: Date, calendar: Calendar = .current) -> Double? {
        let today = calendar.startOfDay(for: date)
        let days = (1...14).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
            .compactMap { energy[dayKey($0)] }.filter { $0 > 0 }
        return days.count >= 3 ? days.reduce(0, +) / Double(days.count) : nil
    }
}
