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
    /// Every tracked target on target in one day; `Int` is how many.
    case allTargets(Int)
    case streak(Int)
    case meals(Int)
    case steps(Double, goal: Double)
    /// How far the trend has moved towards a goal weight since it was set.
    case weighIn(moved: Double, losing: Bool, progress: Double, remaining: Double, goal: Double)
    case goalReached(WeightGoal)
    /// Last week, on the first open of a new one.
    case week(logged: Int, onTarget: Int, protein: Int)
}

extension Moment: Identifiable {
    var id: Self { self }
}

extension Moment {
    /// What a moment says, on its card and on the image it shares.
    struct Copy {
        var icon: String
        var title: String
        /// A number that counts up on the card: its value, the step it counts in, and its unit.
        var figure: (value: Double, step: Double, unit: String)?
        var detail: String
        var progress: Double?
        /// Worth a picture for a story.
        var shareable: Bool
    }

    var copy: Copy {
        switch self {
        case .targets(let hits):
            Copy(icon: "target", title: hits.count == 1 ? "\(hits[0].name) target hit" : "\(hits.count) targets hit",
                 detail: hits.count == 1 ? "\(hits[0].value.number) of \(hits[0].target.number) \(hits[0].unit)" : hits.map(\.name).formatted(),
                 shareable: false)
        case .allTargets(let count):
            Copy(icon: "checkmark.seal.fill", title: "Every target hit", detail: "All \(count) for the day. That's the whole job.", shareable: true)
        case .streak(let days):
            Copy(icon: "flame.fill", title: "\(days) days in a row", detail: "You've logged every day. Keep it going.", shareable: true)
        case .meals(let count):
            Copy(icon: "fork.knife", title: count == 1 ? "First meal logged" : "\(count.formatted()) meals logged",
                 detail: count == 1 ? "That's the hard part done." : "It all adds up.", shareable: count > 1)
        case .steps(let steps, let goal):
            Copy(icon: "figure.walk", title: "Step goal hit", detail: "\(Steps.text(steps)) steps today, past your \(Steps.text(goal)).", shareable: true)
        case .weighIn(let moved, let losing, let progress, let remaining, let goal):
            Copy(icon: "scalemass.fill", title: losing ? "You've lost" : "You've gained", figure: (moved, 0.1, "kg"),
                 detail: "\(remaining.number) kg to go until \(goal.number) kg", progress: progress, shareable: true)
        case .goalReached(let goal):
            Copy(icon: "party.popper.fill", title: "Goal reached", figure: (abs(goal.startKg - goal.kg), 0.1, "kg"),
                 detail: "\(goal.kg < goal.startKg ? "lost" : "gained") since you started at \(goal.startKg.number) kg. You're at \(goal.kg.number) kg.",
                 shareable: true)
        case .week(let logged, let onTarget, let protein):
            Copy(icon: "calendar", title: "\(logged) of 7 days logged",
                 detail: "On or under calories \(onTarget) \(onTarget == 1 ? "day" : "days"), protein hit \(protein). Tap for your review.", shareable: true)
        }
    }
    var opensReview: Bool { if case .week = self { true } else { false } }
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
    /// A week with fewer logged days than this isn't worth a card.
    static let fewestWeekDays = 3

    /// Steps that have just passed the goal today, as new counts come in from Health. Only while Leanr is running: a count
    /// that was already past the goal when it first arrived was passed some time before.
    static func stepsReached(before: [String: Double], after: [String: Double], goal: Double, day: String) -> Moment? {
        guard let now = after[day], now >= goal, let earlier = before[day], earlier < goal else { return nil }
        return .steps(now, goal: goal)
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
        // The last target of the day gets the bigger card instead of its own.
        if let count = allTargetsHit(day: today), !hits.isEmpty, marked.insert(todayMark + "All").inserted {
            earned.append(.allTargets(count))
        } else if !hits.isEmpty {
            earned.append(.targets(hits))
        }
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

    /// Last week's card, the first time Leanr opens in a new week, when enough of it was logged. Nil otherwise or once shown.
    mutating func offerWeek(now: Date = Date(), calendar: Calendar = .current) -> Moment? {
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return nil }
        let mark = "week:\(dayKey(weekStart))"
        guard !(celebrated ?? []).contains(mark) else { return nil }
        let goals = goalSets.first { $0.id == activeGoal } ?? goalSets[0]
        let review = WeeklyReview.make(self, goals: goals, ending: yesterday, calendar: calendar)
        guard review.loggedDays >= Moment.fewestWeekDays else { return nil }
        celebrated = (celebrated ?? []).union([mark])
        return .week(logged: review.loggedDays, onTarget: review.calorieDays, protein: review.proteinDays)
    }

    /// The keys of the daily targets that are tracked: the macros, and anything else with an at-least target.
    private func trackedTargets(_ goals: Goals) -> [(key: String, target: Double, minimum: Bool)] {
        nutrientNames.compactMap { nutrient in
            let minimum = goals.minimums.contains(nutrient.key)
            guard nutrient.key != "cal", ["p", "c", "f"].contains(nutrient.key) || minimum, let target = goals.values[nutrient.key] else { return nil }
            return (nutrient.key, target, minimum)
        }
    }

    /// How many targets there are when every one of them is on target today, with at least two to hit. Nil otherwise.
    private func allTargetsHit(day: String) -> Int? {
        let goals = goalSets.first { $0.id == activeGoal } ?? goalSets[0]
        let tracked = trackedTargets(goals), total = Nutrition((logs[day] ?? []).flatMap(\.items))
        guard tracked.count >= 2, tracked.allSatisfy({ Moment.onTarget(total.value($0.key), target: $0.target, minimum: $0.minimum) }) else { return nil }
        return tracked.count
    }

    /// Macro targets, other at-least targets and water that this change has brought onto target today.
    private func targetHits(comparedTo old: AppData, day: String) -> [Moment.Hit] {
        let goals = goalSets.first { $0.id == activeGoal } ?? goalSets[0]
        let total = Nutrition((logs[day] ?? []).flatMap(\.items)), earlier = Nutrition((old.logs[day] ?? []).flatMap(\.items))
        var hits = trackedTargets(goals).compactMap { key, target, minimum -> Moment.Hit? in
            guard total.value(key) > earlier.value(key), Moment.onTarget(total.value(key), target: target, minimum: minimum),
                  !Moment.onTarget(earlier.value(key), target: target, minimum: minimum),
                  let nutrient = nutrientNames.first(where: { $0.key == key }) else { return nil }
            return Moment.Hit(name: nutrient.label, value: total.value(key), target: target, unit: nutrient.unit)
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
