import Foundation

/// One weekly check-in: what the trend and log said, and the calorie target that came out of it.
struct CheckInRecord: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var date: Date
    /// Trend change per week at the time, in kg (negative is losing).
    var weeklyChange: Double?
    /// Measured maintenance at the time.
    var maintenance: Double
    /// The pace asked for, in kg a week.
    var pace: Double
    var previousCalories: Double?
    var calories: Double
    /// False when the suggestion was looked at and the old targets kept.
    var accepted: Bool
    var isValid: Bool {
        [maintenance, pace, calories].allSatisfy(\.isFinite) && (weeklyChange?.isFinite ?? true) && (previousCalories?.isFinite ?? true)
            && CheckIn.paceRange.contains(pace) && CheckIn.calorieRange.contains(calories)
    }
}

/// A weekly check-in, like an adaptive coach: maintenance measured from the last four weeks of logging and weigh-ins,
/// the pace you want to lose or gain at, and the calorie target that gets you there. Protein stays put; carbs and fat
/// take up the change in the same proportions as before.
enum CheckIn {
    /// Paces offered, in kg a week.
    static let paces: [Double] = [-1, -0.75, -0.5, -0.25, 0, 0.25, 0.5]
    static let paceRange = -1.0...0.5
    static let calorieRange = 1200.0...6000.0
    /// The lowest target a check-in will suggest.
    static let lowest = 1200.0
    /// The most one check-in moves the calorie target, so a noisy week can't swing it far.
    static let largestStep = 300.0
    /// Days between check-ins.
    static let interval = 7

    static func paceText(_ pace: Double) -> String {
        if pace == 0 { return "Maintain" }
        return "\(pace < 0 ? "Lose" : "Gain") \(abs(pace).formatted(.number.precision(.fractionLength(0...2)))) kg a week"
    }

    /// The pace you set, or one that fits your weight goal: losing half a kilo a week, or gaining a quarter.
    static func pace(_ data: AppData, now: Date = Date()) -> Double {
        if let pace = data.checkInPace { return pace }
        guard let goal = data.weightGoal, let status = WeightTrend.goalStatus(goal, points: WeightTrend.points(data.weightLog), now: now) else { return 0 }
        switch status.direction {
        case .lose: return -0.5
        case .gain: return 0.25
        case .reached: return 0
        }
    }

    /// The most recent check-in.
    static func last(_ data: AppData) -> CheckInRecord? { (data.checkIns ?? []).max { $0.date < $1.date } }

    /// When the next check-in is due: a week after the last one, or now if there hasn't been one.
    static func nextDate(_ data: AppData, calendar: Calendar = .current) -> Date? {
        guard let last = last(data) else { return nil }
        return calendar.date(byAdding: .day, value: interval, to: calendar.startOfDay(for: last.date))
    }

    static func isDue(_ data: AppData, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let next = nextDate(data, calendar: calendar) else { return true }
        return now >= next
    }

    /// How close you are to having enough for a check-in: maintenance needs 10 logged days and two weeks of weigh-ins
    /// in the last four weeks.
    struct Readiness: Equatable, Sendable {
        var loggedDays: Int
        var weighInSpan: Int
        var daysNeeded: Int { max(0, 10 - loggedDays) }
        var weighInDaysNeeded: Int { max(0, 14 - weighInSpan) }
    }

    static func readiness(_ data: AppData, now: Date = Date(), calendar: Calendar = .current) -> Readiness {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -28, to: today) ?? today
        let keys = (0..<28).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }.map(dayKey)
        let logged = keys.filter { !(data.logs[$0] ?? []).isEmpty }.count
        let window = WeightTrend.points(data.weightLog, calendar: calendar).filter { $0.date >= start && $0.date < today }
        let span = window.first.flatMap { first in window.last.map { calendar.dateComponents([.day], from: first.date, to: $0.date).day ?? 0 } } ?? 0
        return Readiness(loggedDays: logged, weighInSpan: span)
    }

    struct Suggestion: Equatable, Sendable {
        var maintenance: Double
        var loggedDays: Int
        /// Trend change per week over the last four weeks, signed.
        var weeklyChange: Double?
        var trendWeight: Double?
        var pace: Double
        var currentCalories: Double?
        /// The new calorie target, and the full set of targets that goes with it.
        var calories: Double
        var values: [String: Double]
        /// True when the target was held to `largestStep` from the current one, or to `lowest`.
        var limitedByStep: Bool
        var limitedByFloor: Bool
        /// True when the pace is more than 1% of body weight a week.
        var paceIsFast: Bool
        var change: Double? { currentCalories.map { calories - $0 } }
    }

    /// The suggested targets for a pace. Nil until maintenance can be measured.
    static func suggestion(_ data: AppData, goals: Goals, pace: Double, now: Date = Date(), calendar: Calendar = .current) -> Suggestion? {
        let points = WeightTrend.points(data.weightLog, calendar: calendar)
        guard let measured = WeightTrend.maintenance(logs: data.logs, points: points, now: now, calendar: calendar) else { return nil }
        let current = goals.values["cal"]
        let ideal = measured.calories + WeightTrend.dailyCalorieDifference(kgPerWeek: pace)
        var calories = ideal
        var limitedByStep = false, limitedByFloor = false
        if let current, abs(calories - current) > largestStep {
            calories = current + (calories > current ? largestStep : -largestStep)
            limitedByStep = true
        }
        if calories < lowest { calories = lowest; limitedByFloor = true }
        calories = min(calorieRange.upperBound, (calories / 10).rounded() * 10)
        let trend = points.last?.trend
        let fast = trend.map { abs(pace) > $0 * 0.01 } ?? false
        return Suggestion(maintenance: measured.calories, loggedDays: measured.loggedDays,
                          weeklyChange: WeightTrend.weeklyChange(points, now: now, calendar: calendar), trendWeight: trend,
                          pace: pace, currentCalories: current, calories: calories, values: values(goals, calories: calories),
                          limitedByStep: limitedByStep, limitedByFloor: limitedByFloor, paceIsFast: fast)
    }

    /// Targets for a new calorie figure. Protein is kept; carbs and fat share what's left in the same proportion as now.
    /// Without both a carb and a fat target, only calories change.
    static func values(_ goals: Goals, calories: Double) -> [String: Double] {
        var values = ["cal": calories]
        guard let c = goals.values["c"], let f = goals.values["f"] else { return values }
        let protein = goals.values["p"] ?? 0
        let before = c * 4 + f * 9, after = calories - protein * 4
        guard before > 0, after > 0 else { return values }
        let scale = after / before
        values["c"] = (c * scale).rounded()
        values["f"] = (f * scale).rounded()
        return values
    }

    /// "You're losing 0.32 kg a week. You asked for 0.5." and so on.
    static func headline(_ suggestion: Suggestion) -> String {
        let pace = suggestion.pace
        let asked = pace == 0 ? "to hold steady" : "\(abs(pace).formatted(.number.precision(.fractionLength(0...2)))) kg a week"
        guard let weekly = suggestion.weeklyChange else { return "Your goal is \(pace == 0 ? "to maintain" : asked)." }
        let amount = abs(weekly).formatted(.number.precision(.fractionLength(0...2)))
        let moving = abs(weekly) < WeightTrend.flatPace ? "Your weight is holding steady" : "You're \(weekly < 0 ? "losing" : "gaining") \(amount) kg a week"
        return pace == 0 ? "\(moving). Your goal is to maintain." : "\(moving). Your goal is to \(pace < 0 ? "lose" : "gain") \(asked)."
    }

    /// Notes a check-in. Only the last 52 are kept.
    static func record(_ suggestion: Suggestion, accepted: Bool, now: Date = Date(), into data: inout AppData) {
        let record = CheckInRecord(date: now, weeklyChange: suggestion.weeklyChange, maintenance: suggestion.maintenance, pace: suggestion.pace,
                                   previousCalories: suggestion.currentCalories, calories: suggestion.calories, accepted: accepted)
        data.checkIns = Array(((data.checkIns ?? []) + [record]).sorted { $0.date < $1.date }.suffix(52))
    }

    static func isValid(_ data: AppData) -> Bool {
        (data.checkIns ?? []).allSatisfy(\.isValid) && Set((data.checkIns ?? []).map(\.id)).count == (data.checkIns ?? []).count
            && (data.checkInPace.map { $0.isFinite && paceRange.contains($0) } ?? true)
    }
}
