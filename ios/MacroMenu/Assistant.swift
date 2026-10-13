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

    /// Something to eat that fits what's left today.
    struct Suggestion: Identifiable, Equatable, Sendable {
        enum Source: Equatable, Sendable { case pinned, recent, myFood, savedMeal, everyday, restaurant(String) }
        var id: String
        var name: String
        var items: [Portion]
        var source: Source
        var calories: Double
        var protein: Double
        /// "Pinned", "Lately", "At KFC"...
        var sourceText: String {
            switch source {
            case .pinned: "Pinned"
            case .recent: "Eaten lately"
            case .myFood: "Your food"
            case .savedMeal: "Your meal"
            case .everyday: "Everyday food"
            case .restaurant(let name): "At \(name)"
            }
        }
    }

    /// What's left to fill today, in words: "62 g protein · 630 Cal". Nil when there's nothing left to fill or no target to measure against.
    static func leftText(_ data: AppData, goals: Goals, now: Date = Date()) -> String? {
        let left = remaining(data, goals: goals, now: now)
        var parts: [String] = []
        if let protein = left.protein, protein > 0 { parts.append("\(protein.rounded().number) g protein") }
        if let calories = left.calories, calories > 0 { parts.append("\(calories.rounded().number) Cal") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The restaurant you've logged most in the last 30 days, if any of it was from a restaurant.
    static func usualChain(logs: [String: [LogEntry]], now: Date = Date(), days: Int = 30, calendar: Calendar = .current) -> String? {
        guard let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) else { return nil }
        var counts: [String: Int] = [:]
        for (day, entries) in logs where day >= dayKey(start) {
            for item in entries.flatMap(\.items) where item.food.chain != "mine" && item.food.chain != Food.everyday {
                counts[item.food.chain, default: 0] += 1
            }
        }
        return counts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
    }

    /// Up to `limit` things that fit what's left of today: foods you pinned, ate lately, saved or made yourself first, an order at the
    /// restaurant you use most, then everyday foods to fill any gap. Ranked by how much of a meal's protein they cover per calorie.
    /// Nothing when today's calories are used up or the protein target is met, since there's nothing to close.
    static func suggestions(_ data: AppData, goals: Goals, pinned: [Food], everyday: [Food], restaurantFoods: [Food], chainNames: [String: String],
                            now: Date = Date(), calendar: Calendar = .current, limit: Int = 3) -> [Suggestion] {
        let left = remaining(data, goals: goals, now: now)
        if let calories = left.calories, calories < 100 { return [] }
        if let protein = left.protein, protein <= 0 { return [] }
        // A suggestion is one meal, so it's held to your typical meal (a half more after 4 pm, when fewer meals are left to come),
        // and counts protein only up to a typical meal's worth, so a huge platter doesn't outrank a sensible one.
        let lastMeal = calendar.component(.hour, from: now) >= 16
        let mealCap = lastMeal ? goals.mealCal * 1.5 : goals.mealCal
        let budget = left.calories.map { min($0, mealCap) } ?? mealCap
        let want = left.protein ?? goals.mealProtein
        let useful = goals.mealProtein > 0 ? min(want, goals.mealProtein) : want
        let floor = max(3, min(useful, 10))

        func suggestion(_ name: String, _ items: [Portion], _ source: Suggestion.Source, id: String) -> Suggestion? {
            let total = Nutrition(items)
            guard !items.isEmpty, items.allSatisfy(\.isValid), total.cal >= 30, total.cal <= budget, total.p >= floor else { return nil }
            return Suggestion(id: id, name: name, items: items, source: source, calories: total.cal, protein: total.p)
        }
        func ranked(_ list: [Suggestion]) -> [Suggestion] {
            func score(_ item: Suggestion) -> Double { min(item.protein, useful) / item.calories }
            return list.sorted { (score($0), min($0.protein, useful), $1.name) > (score($1), min($1.protein, useful), $0.name) }
        }
        var seen = Set<String>()
        func fresh(_ suggestion: Suggestion?) -> Suggestion? {
            guard let suggestion, seen.insert(suggestion.name.lowercased()).inserted else { return nil }
            return suggestion
        }

        var usual: [Suggestion] = []
        for food in pinned { if let item = fresh(suggestion(food.name, [Portion(food: food)], .pinned, id: "food:\(food.id)")) { usual.append(item) } }
        for food in QuickLog.recentFoods(logs: data.logs, now: now, limit: 60, calendar: calendar) {
            if let item = fresh(suggestion(food.name, [Portion(food: food)], .recent, id: "food:\(food.id)")) { usual.append(item) }
        }
        for food in data.foods {
            if let item = fresh(suggestion(food.name, [Portion(food: food)], .myFood, id: "food:\(food.id)")) { usual.append(item) }
        }
        for meal in data.meals {
            if let item = fresh(suggestion(meal.name, QuickLog.copies(meal.items), .savedMeal, id: "meal:\(meal.id)")) { usual.append(item) }
        }
        var chosen = Array(ranked(usual).prefix(limit))

        // One order at the restaurant you use most, found the same way "What fits at KFC" finds it.
        var restaurant: Suggestion?
        if let chain = usualChain(logs: data.logs, now: now, calendar: calendar) {
            var query = FindQuery(chains: [chain])
            query.calories = budget; query.protein = useful; query.customise = false
            let match = MealFinder.find(restaurantFoods, query: query).first { $0.total.p >= floor && $0.total.cal <= budget }
            if let match {
                let name = chainNames[chain] ?? chain
                restaurant = suggestion(describe(match.items), match.items, .restaurant(name), id: "order:\(match.id)")
            }
        }

        if chosen.count < limit {
            let usualNames = Set(chosen.map { $0.name.lowercased() })
            let staples = everyday.filter { food in
                ["food", "breakfast"].contains(food.cat) && !food.name.lowercased().contains("raw") && !usualNames.contains(food.name.lowercased())
            }
            let fill = ranked(staples.compactMap { fresh(suggestion($0.name, [Portion(food: $0)], .everyday, id: "food:\($0.id)")) })
            chosen += fill.prefix(limit - chosen.count - (restaurant == nil ? 0 : 1))
        }
        if let restaurant {
            if chosen.count >= limit { chosen.removeLast() }
            chosen.append(restaurant)
        }
        return Array(chosen.prefix(limit))
    }

    /// A spoken and shown answer to "What fits at …?".
    /// What to offer for a spoken food name: a food named exactly that, on its own, so "banana" doesn't ask which of ten bananas.
    /// Several exact matches (the same burger at two chains) are all offered so Siri can ask which.
    static func spokenMatches(_ foods: [Food], query: String, chainNames: [String: String], limit: Int = 10) -> [Food] {
        let found = FoodSearch.browse(foods, chainNames: chainNames, request: .init(search: query))
        let words = FoodSearch.tokens(query)
        let exact = found.filter { FoodSearch.tokens($0.name) == words }
        return Array((exact.isEmpty ? found : exact).prefix(limit))
    }

    /// How many servings a spoken amount means: grams when the food has a weight to compare with, otherwise servings, otherwise one.
    /// Nil when the amount isn't sensible, so Siri can say so rather than log it.
    static func servings(_ servings: Double?, grams: Double?, of food: Food) -> Double? {
        if let grams {
            guard grams > 0, let weight = food.servingWeight?.0, weight > 0 else { return nil }
            let quantity = grams / weight
            return (0.01...100).contains(quantity) ? quantity : nil
        }
        let quantity = servings ?? 1
        return quantity.isFinite && quantity > 0 && quantity <= 100 ? quantity : nil
    }

    /// "Logged 2 × Banana to snacks: 210 Cal, 2.6 g protein. 1,200 Cal left today."
    static func loggedAnswer(food: Food, quantity: Double, mealTime: MealTime, caloriesLeft: Double?) -> String {
        let total = Nutrition([Portion(food: food, quantity: quantity)])
        let amount = quantity == 1 ? "" : "\(quantity.number) × "
        var text = "Logged \(amount)\(food.name) to \(mealTime.title.lowercased()): \(total.cal.rounded().number) Cal, \(total.p.number) g protein."
        if let left = caloriesLeft {
            text += left >= 0 ? " \(left.rounded().number) Cal left today." : " That's \(abs(left).rounded().number) Cal over today's target."
        }
        return text
    }

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
                                               "boost": "boost", "boost juice": "boost", "schnitz": "schnitz", "grilld": "grilld", "grill'd": "grilld", "grill’d": "grilld"]
}
