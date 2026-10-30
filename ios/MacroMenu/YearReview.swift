import Foundation

/// A year in Leanr, for the cards in December: what was logged, the favourites, the longest streak and the way weight moved.
struct YearReview: Identifiable, Equatable, Sendable {
    var year: Int
    var meals: Int
    var days: Int
    var topMeal: (name: String, count: Int)?
    /// The restaurant logged from most.
    var topChain: (id: String, count: Int)?
    var bestStreak: Int
    var proteinDays: Int
    /// Towards the goal weight only, and nil with no goal: this isn't the place to point out a step back.
    var weight: (moved: Double, losing: Bool, goal: Double)?
    var id: Int { year }

    /// Fewer logged days than this isn't much of a year to look back on.
    static let fewestDays = 14

    static func == (a: YearReview, b: YearReview) -> Bool {
        a.year == b.year && a.meals == b.meals && a.days == b.days && a.topMeal?.name == b.topMeal?.name && a.topChain?.id == b.topChain?.id
            && a.bestStreak == b.bestStreak && a.proteinDays == b.proteinDays && a.weight?.moved == b.weight?.moved
    }

    /// The year whose review is open on `now`: all of December, and January for the year just gone.
    static func showing(on now: Date, calendar: Calendar = .current) -> Int? {
        let parts = calendar.dateComponents([.year, .month], from: now)
        guard let year = parts.year else { return nil }
        return parts.month == 12 ? year : parts.month == 1 ? year - 1 : nil
    }

    /// `restaurants` are the chains to count, so your own foods and everyday foods don't win.
    static func make(_ data: AppData, year: Int, restaurants: Set<String> = []) -> YearReview {
        let prefix = "\(year)-"
        let logged = data.logs.filter { $0.key.hasPrefix(prefix) && !$0.value.isEmpty }
        let entries = logged.values.flatMap { $0 }
        let current = data.goalSets.first { $0.id == data.activeGoal } ?? data.goalSets[0]
        let meals = Dictionary(grouping: entries.filter { $0.name != "Quick add" }, by: \.name).mapValues(\.count)
        let chains = Dictionary(grouping: entries.flatMap(\.items).filter { restaurants.contains($0.food.chain) }, by: \.food.chain).mapValues(\.count)
        func top(_ counts: [String: Int]) -> (String, Int)? {
            counts.max { ($0.value, $1.key) < ($1.value, $0.key) }.map { ($0.key, $0.value) }
        }
        let proteinDays = logged.filter { key, day in
            (data.dayGoals[key] ?? current).values["p"].map { Nutrition(day.flatMap(\.items)).p >= $0 } ?? false
        }.count
        var weight: (moved: Double, losing: Bool, goal: Double)?
        let points = WeightTrend.points(data.weightLog).filter { dayKey($0.date).hasPrefix(prefix) }
        if let goal = data.weightGoal, let first = points.first, let last = points.last {
            let losing = goal.kg < goal.startKg
            let moved = ((first.trend - last.trend) * (losing ? 1 : -1)).tenth
            if moved > 0 { weight = (moved, losing, goal.kg) }
        }
        return YearReview(year: year, meals: entries.count, days: logged.count, topMeal: top(meals).map { (name: $0.0, count: $0.1) },
                          topChain: top(chains).map { (id: $0.0, count: $0.1) }, bestStreak: TrackingStreak.best(days: Set(logged.keys)),
                          proteinDays: proteinDays, weight: weight)
    }
}
