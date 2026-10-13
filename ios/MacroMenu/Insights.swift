import Foundation

/// Short observations from your own log over the Progress range: "Weekends average 600 Cal more than weekdays".
/// Each only appears when there's enough to go on and the difference is big enough to matter, strongest first.
/// Only days with something logged count, and figures are rounded so they read as patterns, not measurements.
enum Insights {
    struct Insight: Equatable, Identifiable, Sendable {
        var id: String
        var systemImage: String
        var text: String
        /// How strong the pattern is, for ordering; bigger first.
        var strength: Double
    }

    /// One logged day, worked out once.
    private struct Day {
        var date: Date
        var calories: Double
        var protein: Double
        var calorieTarget: Double?
        var proteinTarget: Double?
        var entries: [LogEntry]
        var hitProtein: Bool? { proteinTarget.map { protein >= $0 } }
        var overCalories: Bool? { calorieTarget.map { calories > $0 } }
    }

    static func make(_ data: AppData, goals: Goals, days: Int, ending end: Date = Date(), calendar: Calendar = .current, limit: Int = 4) -> [Insight] {
        let last = calendar.startOfDay(for: end)
        let logged: [Day] = (0..<days).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: last) else { return nil }
            let key = dayKey(date)
            guard let entries = data.logs[key], !entries.isEmpty else { return nil }
            let total = Nutrition(entries.flatMap(\.items))
            let target = data.dayGoals[key] ?? goals
            return Day(date: date, calories: total.cal, protein: total.p, calorieTarget: target.values["cal"], proteinTarget: target.values["p"], entries: entries)
        }
        guard logged.count >= 5 else { return [] }
        let found = [weekends(logged, calendar: calendar), breakfast(logged), biggestDay(logged, calendar: calendar), lateEating(logged, calendar: calendar),
                     takeaway(logged), overTargetFood(logged), lowProteinMeal(logged)].compactMap { $0 }
        return Array(found.sorted { $0.strength > $1.strength }.prefix(limit))
    }

    private static func average(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
    /// To the nearest 10, which is as close as a pattern can honestly be.
    static func calories(_ value: Double) -> String { ((value / 10).rounded() * 10).number }
    /// To the nearest 5%.
    static func percent(_ value: Double) -> String { "\(Int((value * 20).rounded() * 5))%" }

    /// Weekends against weekdays, once there are at least two of one and three of the other and they're 150 Cal apart.
    static let weekendGap = 150.0
    private static func weekends(_ days: [Day], calendar: Calendar) -> Insight? {
        let weekend = days.filter { calendar.isDateInWeekend($0.date) }.map(\.calories)
        let weekday = days.filter { !calendar.isDateInWeekend($0.date) }.map(\.calories)
        guard weekend.count >= 2, weekday.count >= 3, let a = average(weekend), let b = average(weekday), abs(a - b) >= weekendGap else { return nil }
        return Insight(id: "weekends", systemImage: "calendar",
                       text: "Weekends average \(calories(abs(a - b))) Cal \(a > b ? "more" : "less") than weekdays.", strength: abs(a - b) / 100)
    }

    /// How often protein is hit with and without breakfast, once there are three of each and they're 20 points apart.
    private static func breakfast(_ days: [Day]) -> Insight? {
        let counted = days.filter { $0.hitProtein != nil }
        let with = counted.filter { $0.entries.contains { $0.mealTime == .breakfast } }
        let without = counted.filter { !$0.entries.contains { $0.mealTime == .breakfast } }
        guard with.count >= 3, without.count >= 3 else { return nil }
        let a = Double(with.filter { $0.hitProtein == true }.count) / Double(with.count)
        let b = Double(without.filter { $0.hitProtein == true }.count) / Double(without.count)
        guard abs(a - b) >= 0.2 else { return nil }
        return Insight(id: "breakfast", systemImage: "sunrise",
                       text: "Days you log breakfast, you hit your protein target \(percent(a)) of the time, against \(percent(b)) without.",
                       strength: abs(a - b) * 10)
    }

    /// The day of the week that runs highest, once it's been seen twice and is 250 Cal over the average.
    private static func biggestDay(_ days: [Day], calendar: Calendar) -> Insight? {
        guard let overall = average(days.map(\.calories)) else { return nil }
        let byWeekday = Dictionary(grouping: days) { calendar.component(.weekday, from: $0.date) }.filter { $0.value.count >= 2 }
        guard byWeekday.count >= 3,
              let top = byWeekday.compactMapValues({ average($0.map(\.calories)) }).max(by: { ($0.value, $1.key) < ($1.value, $0.key) }),
              top.value - overall >= 250 else { return nil }
        let name = calendar.standaloneWeekdaySymbols[top.key - 1]
        return Insight(id: "weekday", systemImage: "chart.bar",
                       text: "\(name)s are your biggest day, averaging \(calories(top.value)) Cal.", strength: (top.value - overall) / 120)
    }

    /// The share of calories eaten after 8 pm, when it's a quarter or more.
    private static func lateEating(_ days: [Day], calendar: Calendar) -> Insight? {
        let entries = days.flatMap(\.entries)
        let total = entries.reduce(0) { $0 + Nutrition($1.items).cal }
        guard total > 0 else { return nil }
        let late = entries.filter { calendar.component(.hour, from: $0.time) >= 20 }.reduce(0) { $0 + Nutrition($1.items).cal }
        let share = late / total
        guard share >= 0.25 else { return nil }
        return Insight(id: "late", systemImage: "moon", text: "\(percent(share)) of your calories come after 8 pm.", strength: share * 8)
    }

    /// Days with something from a restaurant against days without, once there are three of each and 200 Cal between them.
    private static func takeaway(_ days: [Day]) -> Insight? {
        func fromRestaurant(_ day: Day) -> Bool { day.entries.flatMap(\.items).contains { $0.food.chain != "mine" && !$0.food.isEveryday } }
        let with = days.filter(fromRestaurant).map(\.calories), without = days.filter { !fromRestaurant($0) }.map(\.calories)
        guard with.count >= 3, without.count >= 3, let a = average(with), let b = average(without), abs(a - b) >= 200 else { return nil }
        return Insight(id: "takeaway", systemImage: "takeoutbag.and.cup.and.straw",
                       text: "Days with takeaway average \(calories(abs(a - b))) Cal \(a > b ? "more" : "less") than days without.", strength: abs(a - b) / 100)
    }

    /// A food that turns up on at least half the days over the calorie target, and more often than on the other days.
    private static func overTargetFood(_ days: [Day]) -> Insight? {
        let over = days.filter { $0.overCalories == true }, under = days.filter { $0.overCalories == false }
        guard over.count >= 3, under.count >= 3 else { return nil }
        func share(_ name: String, in group: [Day]) -> Double {
            Double(group.filter { $0.entries.flatMap(\.items).contains { $0.food.name.lowercased() == name } }.count) / Double(group.count)
        }
        let names = Set(over.flatMap { $0.entries.flatMap(\.items).map { $0.food.name.lowercased() } })
        let scored = names.map { name in (name: name, over: share(name, in: over), under: share(name, in: under)) }
            .filter { $0.over >= 0.5 && $0.over - $0.under >= 0.3 }
        guard let best = scored.max(by: { ($0.over - $0.under, $1.name) < ($1.over - $1.under, $0.name) }),
              let display = over.flatMap({ $0.entries.flatMap(\.items) }).first(where: { $0.food.name.lowercased() == best.name })?.food.name else { return nil }
        let count = over.filter { $0.entries.flatMap(\.items).contains { $0.food.name.lowercased() == best.name } }.count
        return Insight(id: "over-food", systemImage: "exclamationmark.circle",
                       text: "\(display) is on \(count) of the \(over.count) days you went over your calories.", strength: (best.over - best.under) * 9)
    }

    /// A meal that brings little protein, when protein is a target and the meal's been logged on at least three days.
    private static func lowProteinMeal(_ days: [Day]) -> Insight? {
        guard days.contains(where: { $0.proteinTarget != nil }) else { return nil }
        let meals: [(MealTime, Double)] = MealTime.allCases.filter { $0 != .snacks }.compactMap { meal in
            let amounts = days.compactMap { day -> Double? in
                let entries = day.entries.filter { $0.mealTime == meal }
                return entries.isEmpty ? nil : Nutrition(entries.flatMap(\.items)).p
            }
            return amounts.count >= 3 ? average(amounts).map { (meal, $0) } : nil
        }
        guard meals.count >= 2, let low = meals.min(by: { $0.1 < $1.1 }), low.1 < 20 else { return nil }
        return Insight(id: "low-protein", systemImage: "fork.knife",
                       text: "\(low.0.title) brings you \(low.1.rounded().number) g of protein on average, your lowest meal.", strength: (20 - low.1) / 4)
    }
}
