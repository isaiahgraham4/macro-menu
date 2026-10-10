import Foundation

/// The answers behind Siri and Shortcuts, kept apart from App Intents so the checks can run them.
enum Assistant {
    /// The meal you've logged most often to `mealTime` in the last 30 days.
    static func usual(_ mealTime: MealTime, logs: [String: [LogEntry]], now: Date = Date(), calendar: Calendar = .current) -> LogEntry? {
        QuickLog.frequent(logs: logs.mapValues { $0.filter { $0.mealTime == mealTime } }, now: now, limit: 1, calendar: calendar).first
    }

    /// Today's targets less what's been logged today. Nil for a target that isn't set.
    static func remaining(_ data: AppData, goals: Goals, now: Date = Date()) -> (calories: Double?, protein: Double?) {
        let key = dayKey(now), eaten = Nutrition((data.logs[key] ?? []).flatMap(\.items))
        let target = data.dayGoals[key] ?? goals
        return (target.values["cal"].map { $0 - eaten.cal }, target.values["p"].map { $0 - eaten.p })
    }

    /// What to look for at one restaurant. Before 4 pm there's still a meal to come, so it's capped at your typical meal;
    /// after that it can use everything that's left. Nil when today's calories are used up.
    static func budget(_ data: AppData, goals: Goals, chain: String, now: Date = Date(), calendar: Calendar = .current) -> FindQuery? {
        let left = remaining(data, goals: goals, now: now)
        let lastMeal = calendar.component(.hour, from: now) >= 16
        var query = FindQuery(chains: [chain])
        if let calories = left.calories {
            guard calories >= 100 else { return nil }
            query.calories = lastMeal ? calories : min(calories, goals.mealCal)
        } else {
            query.calories = goals.mealCal
        }
        query.protein = max(0, left.protein.map { lastMeal ? $0 : min($0, goals.mealProtein) } ?? goals.mealProtein)
        return query
    }

    /// A spoken and shown answer to "What fits at …?".
    /// "A Banana (1 medium, 118 g) has 105 Cal, 1.3 g protein, 27 g carbs and 0.4 g fat."
    static func macrosAnswer(_ food: Food, place: String) -> String {
        var parts = ["\(food.cal.rounded().number) Cal", "\(food.p.number) g protein"]
        if let c = food.c { parts.append("\(c.number) g carbs") }
        if let f = food.f { parts.append("\(f.number) g fat") }
        let list = parts.count > 1 ? parts.dropLast().joined(separator: ", ") + " and " + parts.last! : parts[0]
        let serve = food.serve.isEmpty ? "" : " (\(food.serve))"
        return "\(food.name)\(serve) from \(place) has \(list)."
    }

    /// Words Visual Intelligence gives for nearly everything, which would match far too much.
    static let vagueLabels: Set<String> = ["food", "foods", "dish", "meal", "cuisine", "ingredient", "produce", "snack", "fast food",
        "recipe", "plate", "tableware", "dinnerware", "drink", "beverage", "fruit", "vegetable", "meat", "dessert", "baked goods"]

    /// Leanr foods for what Visual Intelligence sees, best label first, without repeats.
    static func visualMatches(labels: [String], foods: [Food], chainNames: [String: String], limit: Int = 10) -> [Food] {
        var results: [Food] = []
        for label in labels where !vagueLabels.contains(label.lowercased()) {
            for food in MealPhoto.matches(for: SeenFood(name: label, count: 1), in: foods, chainNames: chainNames, limit: 6)
            where !results.contains(where: { $0.id == food.id }) {
                results.append(food)
            }
            if results.count >= limit { break }
        }
        return Array(results.prefix(limit))
    }

    /// What to search Leanr for from Visual Intelligence's labels: the first specific one.
    static func visualSearchText(_ labels: [String]) -> String {
        labels.first { !vagueLabels.contains($0.lowercased()) } ?? labels.first ?? ""
    }

    static func fitsAnswer(restaurant: String, query: FindQuery?, matches: [MealMatch], caloriesLeft: Double?) -> String {
        guard let query else {
            let used = caloriesLeft.map { " You're \(abs($0).rounded().number) Cal \($0 < 0 ? "over" : "under") today's target." } ?? ""
            return "You've used today's calories, so nothing at \(restaurant) fits.\(used)"
        }
        let heading = "At \(restaurant), for up to \(query.calories.rounded().number) Cal with \(query.protein.rounded().number) g protein:"
        guard !matches.isEmpty else { return "Nothing at \(restaurant) fits in \(query.calories.rounded().number) Cal." }
        let lines = matches.prefix(3).map { match in
            "• \(describe(match.items)): \(match.total.cal.rounded().number) Cal, \(match.total.p.number) g protein"
        }
        return ([heading] + lines).joined(separator: "\n")
    }

    /// "2 × Zinger Burger + Chips", grouping repeats of the same food.
    static func describe(_ items: [Portion]) -> String {
        var order: [String] = [], counts: [String: (name: String, count: Double)] = [:]
        for item in items {
            if counts[item.food.id] == nil { order.append(item.food.id) }
            counts[item.food.id, default: (item.food.name, 0)].count += item.quantity
        }
        return order.compactMap { counts[$0] }.map { $0.count == 1 ? $0.name : "\($0.count.number) × \($0.name)" }.joined(separator: " + ")
    }

    /// Restaurant names people say that differ from the menu's name.
    static let nicknames: [String: String] = ["maccas": "mcd", "macca's": "mcd", "mcdonalds": "mcd", "hj": "hj", "hjs": "hj", "hungry jacks": "hj",
                                               "gyg": "gyg", "guzman": "gyg", "guzman y gomez": "gyg", "red rooster": "rr", "rooster": "rr",
                                               "dominos": "dominos", "subway": "sub", "kentucky": "kfc", "zambreros": "zam", "zambrero's": "zam",
                                               "boost": "boost", "boost juice": "boost"]
}
