import Foundation

/// Something worth stopping to mark, shown over the app for a few seconds. The goal weight gets the whole screen.
enum Moment: Hashable, Sendable {
    struct Hit: Hashable, Sendable {
        var name: String
        var value: Double
        var target: Double
        var unit: String
    }
    case targets([Hit])
    case streak(Int)
    case meals(Int)
    /// How far the trend has moved towards a goal weight since it was set.
    case weighIn(moved: Double, losing: Bool, progress: Double, remaining: Double, goal: Double)
    case goalReached(WeightGoal)
}

extension Moment {
    /// Days in a row of logging that are worth marking.
    static let streaks = [3, 7, 14, 30, 60, 100, 180, 365]
    /// Meals logged in all that are worth marking.
    static let mealCounts = [1, 10, 25, 50, 100, 250, 500, 1000, 2500]
    /// More new entries than this at once is a restored backup, not a meal.
    static let mostNewEntries = 12
    /// An at-most target counts as hit from this share of it, up to the target itself.
    private static let closeToLimit = 0.95

    /// Whether a daily figure is on target: at or past an at-least target, or close under an at-most one.
    static func onTarget(_ value: Double, target: Double, minimum: Bool) -> Bool {
        minimum ? value >= target : value >= target * closeToLimit && value <= target
    }
}

extension AppData {
    var mealsLogged: Int { logs.values.reduce(0) { $0 + $1.count } }

    /// What this change has just earned, biggest first. Each is marked in `celebrated`, so nothing is earned twice.
    mutating func earnMoments(comparedTo old: AppData, now: Date = Date()) -> [Moment] {
        var earned: [Moment] = []
        if markGoalReached(comparedTo: old), let goal = weightGoal { earned.append(.goalReached(goal)) }
        var marked = celebrated ?? []
        let today = dayKey(now), todayMark = "day:\(today):"
        let hits = targetHits(comparedTo: old, day: today).filter { marked.insert(todayMark + $0.name).inserted }
        if !hits.isEmpty { earned.append(.targets(hits)) }
        let before = old.mealsLogged, after = mealsLogged
        if after > before, after - before <= Moment.mostNewEntries {
            let streak = widgetCalories.streak(on: now), streakBefore = old.widgetCalories.streak(on: now)
            if let days = Moment.streaks.last(where: { streakBefore < $0 && streak >= $0 }), marked.insert("streak:\(days)").inserted {
                earned.append(.streak(days))
            }
            if let count = Moment.mealCounts.last(where: { before < $0 && after >= $0 }), marked.insert("meals:\(count)").inserted {
                earned.append(.meals(count))
            }
        }
        // Yesterday's targets no longer matter, so only milestones are kept for good.
        marked = marked.filter { !$0.hasPrefix("day:") || $0.hasPrefix(todayMark) }
        if !marked.isEmpty || celebrated != nil { celebrated = marked }
        return earned
    }

    /// Macro targets, other at-least targets and water that this change has brought onto target today.
    private func targetHits(comparedTo old: AppData, day: String) -> [Moment.Hit] {
        let goals = goalSets.first { $0.id == activeGoal } ?? goalSets[0]
        let total = Nutrition((logs[day] ?? []).flatMap(\.items)), earlier = Nutrition((old.logs[day] ?? []).flatMap(\.items))
        var hits = nutrientNames.compactMap { nutrient -> Moment.Hit? in
            let minimum = goals.minimums.contains(nutrient.key)
            guard nutrient.key != "cal", ["p", "c", "f"].contains(nutrient.key) || minimum, let target = goals.values[nutrient.key],
                  total.value(nutrient.key) > earlier.value(nutrient.key),
                  Moment.onTarget(total.value(nutrient.key), target: target, minimum: minimum),
                  !Moment.onTarget(earlier.value(nutrient.key), target: target, minimum: minimum) else { return nil }
            return Moment.Hit(name: nutrient.label, value: total.value(nutrient.key), target: target, unit: nutrient.unit)
        }
        let water = Water.total(self, on: day), waterBefore = Water.total(old, on: day), waterTarget = Water.target(self)
        if water >= waterTarget, waterBefore < waterTarget {
            hits.append(Moment.Hit(name: "Water", value: water, target: waterTarget, unit: "mL"))
        }
        return hits
    }

    /// How a new weigh-in stands against the goal weight. Nil with no goal, once there, or with nothing gained on it yet.
    var weighInMoment: Moment? {
        guard let goal = weightGoal, let status = WeightTrend.goalStatus(goal, points: WeightTrend.points(weightLog)),
              status.direction != .reached else { return nil }
        let losing = goal.kg < goal.startKg
        let moved = ((goal.startKg - status.current) * (losing ? 1 : -1)).tenth
        guard moved > 0 else { return nil }
        return .weighIn(moved: moved, losing: losing, progress: status.progress, remaining: status.remaining, goal: goal.kg)
    }
}
