import Foundation

/// A look back over the seven days ending on a given day: how much you logged, averages against target,
/// how many days hit protein, the weight trend and your most-logged meals.
struct WeeklyReview: Equatable, Sendable {
    struct Meal: Equatable, Sendable { var name: String; var count: Int }
    var start: Date
    var end: Date
    var loggedDays: Int
    /// Averages over the days you logged, not all seven.
    var averageCalories: Double?
    var averageProtein: Double?
    var calorieTarget: Double?
    var proteinTarget: Double?
    /// Logged days with protein at or above target, and with calories at or under target.
    var proteinDays: Int
    var calorieDays: Int
    /// Change in the smoothed weight trend across the week, in kg.
    var weightChange: Double?
    var trendWeight: Double?
    var topMeals: [Meal]

    static func make(_ data: AppData, goals: Goals, ending end: Date = Date(), calendar: Calendar = .current) -> WeeklyReview {
        let last = calendar.startOfDay(for: end)
        let first = calendar.date(byAdding: .day, value: -6, to: last) ?? last
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }.map(dayKey)
        var calories: [Double] = [], protein: [Double] = [], calorieTargets: [Double] = [], proteinTargets: [Double] = []
        var proteinDays = 0, calorieDays = 0
        var counts: [String: (name: String, count: Int)] = [:]
        for key in days {
            let entries = data.logs[key] ?? []
            guard !entries.isEmpty else { continue }
            let total = Nutrition(entries.flatMap(\.items)), target = data.dayGoals[key] ?? goals
            calories.append(total.cal); protein.append(total.p)
            if let cal = target.values["cal"] { calorieTargets.append(cal); if total.cal <= cal { calorieDays += 1 } }
            if let p = target.values["p"] { proteinTargets.append(p); if total.p >= p { proteinDays += 1 } }
            for entry in entries { counts[entry.name.lowercased(), default: (entry.name, 0)].count += 1 }
        }
        func average(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }

        // The trend on the last weigh-in before the week, against the last one in it.
        let points = WeightTrend.points(data.weightLog, calendar: calendar)
        let dayAfter = calendar.date(byAdding: .day, value: 1, to: last) ?? last
        let inWeek = points.last { $0.date >= first && $0.date < dayAfter }
        let before = points.last { $0.date < first }
        let meals = counts.values.filter { $0.count >= 2 }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }.prefix(3).map { Meal(name: $0.name, count: $0.count) }

        return WeeklyReview(start: first, end: last, loggedDays: calories.count,
                            averageCalories: average(calories), averageProtein: average(protein),
                            calorieTarget: average(calorieTargets), proteinTarget: average(proteinTargets),
                            proteinDays: proteinDays, calorieDays: calorieDays,
                            weightChange: inWeek.flatMap { now in before.map { now.trend - $0.trend } }, trendWeight: inWeek?.trend,
                            topMeals: Array(meals))
    }

    /// One line for the Sunday notification.
    var summary: String {
        guard loggedDays > 0 else { return "Nothing logged this week yet." }
        var parts = ["Logged \(loggedDays) of 7 days"]
        if let averageCalories { parts.append("avg \(averageCalories.rounded().number) Cal") }
        if proteinTarget != nil { parts.append("protein target hit \(proteinDays) \(proteinDays == 1 ? "day" : "days")") }
        if let weightChange { parts.append("trend \(Self.signed(weightChange)) kg") }
        return parts.joined(separator: " · ") + "."
    }

    static func signed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return (rounded > 0 ? "+" : rounded < 0 ? "−" : "") + abs(rounded).number
    }
}
