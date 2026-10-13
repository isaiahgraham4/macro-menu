import Foundation

/// Meals set out ahead of time, by day. A plan counts towards nothing until each meal is logged, which moves it from the
/// plan into the log with the time it was eaten.
enum MealPlan {
    /// How far ahead you can plan, counting today.
    static let daysAhead = 7

    static func entries(_ data: AppData, on day: String) -> [LogEntry] { data.plans?[day] ?? [] }

    /// Days you can plan for: today and the six after it.
    static func days(from now: Date = Date(), calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0..<daysAhead).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    static func isValid(_ data: AppData) -> Bool {
        guard let plans = data.plans else { return true }
        return plans.keys.allSatisfy(Water.isDayKey) && plans.values.allSatisfy { $0.allSatisfy(\.isValid) }
    }

    /// Adds a meal to a day's plan, with fresh item IDs so it's independent of where it came from.
    static func add(_ items: [Portion], name: String, mealTime: MealTime, on day: String, to data: inout AppData) {
        guard Water.isDayKey(day), !items.isEmpty else { return }
        var plans = data.plans ?? [:]
        plans[day, default: []].append(LogEntry(name: name, items: QuickLog.copies(items), mealTime: mealTime))
        data.plans = plans
    }

    static func remove(_ id: LogEntry.ID, on day: String, from data: inout AppData) {
        guard var plans = data.plans else { return }
        plans[day]?.removeAll { $0.id == id }
        if plans[day]?.isEmpty == true { plans.removeValue(forKey: day) }
        data.plans = plans.isEmpty ? nil : plans
    }

    /// Moves planned meals into the log for that day, stamped `time`, and takes them off the plan.
    /// The day's targets are kept as they were, like any other logging.
    static func log(_ ids: Set<LogEntry.ID>, on day: String, at time: Date, goals: Goals, into data: inout AppData) {
        let chosen = entries(data, on: day).filter { ids.contains($0.id) }
        guard !chosen.isEmpty else { return }
        for planned in chosen {
            var entry = planned; entry.id = UUID(); entry.time = time; entry.items = QuickLog.copies(planned.items)
            data.logs[day, default: []].append(entry)
            remove(planned.id, on: day, from: &data)
        }
        if data.dayGoals[day] == nil { data.dayGoals[day] = goals }
    }

    /// Drops plans for days already gone.
    static func pruned(_ data: inout AppData, now: Date = Date()) {
        guard let plans = data.plans else { return }
        let today = dayKey(now)
        let kept = plans.filter { $0.key >= today && !$0.value.isEmpty }
        data.plans = kept.isEmpty ? nil : kept
    }

    /// What a day's plan adds up to against its targets: "1,650 of 2,200 Cal · 120 of 150 g protein".
    static func summary(_ entries: [LogEntry], goals: Goals) -> String {
        let total = Nutrition(entries.flatMap(\.items))
        var parts = ["\(total.cal.rounded().number)\(goals.values["cal"].map { " of \($0.rounded().number)" } ?? "") Cal"]
        parts.append("\(total.p.rounded().number)\(goals.values["p"].map { " of \($0.rounded().number)" } ?? "") g protein")
        return parts.joined(separator: " · ")
    }

    /// The day as it would be with the plan eaten, for working out what's left to plan around.
    static func asLogged(_ data: AppData, day: String) -> AppData {
        var copy = data
        copy.logs[day] = (data.logs[day] ?? []) + entries(data, on: day)
        return copy
    }
}
