import Foundation

/// Daily steps. The counts come from Apple Health and are only held in memory, never saved in Leanr's data or iCloud copy;
/// only the goal is Leanr's own.
enum Steps {
    static let defaultGoal = 8000.0
    static let goalRange = 1000.0...100_000.0

    static func goal(_ data: AppData) -> Double { data.stepGoal ?? defaultGoal }

    static func isValid(_ data: AppData) -> Bool {
        data.stepGoal.map { $0.isFinite && goalRange.contains($0) } ?? true
    }

    /// 6420 → "6,420".
    static func text(_ steps: Double) -> String {
        steps.rounded().formatted(.number.precision(.fractionLength(0)))
    }

    /// How far through the goal, from 0 to 1.
    static func progress(_ steps: Double, goal: Double) -> Double {
        goal > 0 ? min(1, max(0, steps / goal)) : 0
    }

    struct Summary: Equatable, Sendable {
        /// Average over the days that have any steps recorded.
        var average: Double?
        var countedDays: Int
        var daysMet: Int
        var total: Double
        var best: Double?
    }

    /// Steps across the given days (day keys). A day with nothing recorded isn't counted, so a phone left at home
    /// doesn't pull the average down to zero.
    static func summary(_ steps: [String: Double], days: [String], goal: Double) -> Summary {
        let counted = days.compactMap { steps[$0] }.filter { $0 > 0 }
        let total = counted.reduce(0, +)
        return Summary(average: counted.isEmpty ? nil : total / Double(counted.count), countedDays: counted.count,
                       daysMet: counted.filter { $0 >= goal }.count, total: total, best: counted.max())
    }
}
