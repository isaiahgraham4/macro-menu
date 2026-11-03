import Foundation

/// Takeaway roulette: a wheel of restaurants, each holding the dinners there that fit what's left today.
enum Roulette {
    /// A juice bar and the bakeries and cafes, which sell lunch and shut early.
    static let notDinner: Set<String> = ["boost", "brumbys", "donutking", "michels", "soul"]
    /// A dinner uses at least this much of the limit, so a snack can't win the night.
    static let leastOfLimit = 0.5
    /// Anything smaller is a dip or a sauce, not a side.
    static let smallestSide = 100.0
    /// A full burger twice is two dinners; two of something small is one.
    static let largestDoubled = 300.0
    /// The restaurants chosen for the wheel, joined with commas. Empty is every restaurant.
    static let storageKey = "roulette.chains"

    /// The restaurants on the wheel: the ones chosen, or every one when none are. Places out of reach stay off
    /// unless they're chosen, since choosing one says you'll go there. Chosen IDs no longer on the menu don't count.
    static func onWheel(_ all: [String], chosen: Set<String>, outOfReach: Set<String>) -> Set<String> {
        let picked = chosen.intersection(all)
        return picked.isEmpty ? Set(all).subtracting(outOfReach) : picked
    }

    /// One restaurant on the wheel.
    struct Slice: Identifiable, Sendable {
        var chain: String
        var orders: [MealMatch]
        var id: String { chain }
    }

    /// The limits for tonight. Dinner can use what's left today, up to half as much again as a typical meal, the same cap as
    /// suggestions. Carbs and fat count when they're daily limits with some left. Nil when today's calories are used up.
    static func limits(_ data: AppData, goals: Goals, diet: DietFilter = DietFilter(), now: Date = Date()) -> FindQuery? {
        let left = Assistant.remaining(data, goals: goals, now: now)
        var query = FindQuery()
        query.customise = false; query.diet = diet
        let cap = goals.mealCal * 1.5
        if let calories = left.calories {
            guard calories >= 100 else { return nil }
            query.calories = min(calories, cap).rounded(.down)
        } else {
            query.calories = cap
        }
        query.protein = max(0, min(left.protein ?? goals.mealProtein, goals.mealProtein)).rounded()
        let eaten = Nutrition((data.logs[dayKey(now)] ?? []).flatMap(\.items))
        let target = data.dayGoals[dayKey(now)] ?? goals
        func remaining(_ key: String, _ eaten: Double) -> Double? {
            guard let limit = target.values[key], !target.minimums.contains(key) else { return nil }
            return max(0, limit - eaten).rounded(.down)
        }
        query.carbs = remaining("c", eaten.c); query.fat = remaining("f", eaten.f)
        return query
    }

    /// What can go in a dinner: mains and real sides. Not drinks, desserts, extras or sauces, which would only pad an order up to the limit,
    /// and not breakfast (hash browns stop with it) or kids' items.
    static func isDinnerFood(_ food: Food) -> Bool {
        guard food.cat == "main" || (food.cat == "side" && food.cal >= smallestSide) else { return false }
        return food.name.range(of: #"\b(Brekky|Breakfast|Hash Brown|Kids|Kid's)\b"#, options: [.regularExpression, .caseInsensitive]) == nil
    }

    /// Whether an order counts as dinner within `query`: it meets protein and is more than a snack.
    /// The finder has already held it to the calorie, carb and fat limits.
    static func isDinner(_ order: MealMatch, query: FindQuery) -> Bool {
        let doubled = order.items.count == 2 && order.items[0].food.id == order.items[1].food.id
        return order.total.p >= query.protein && order.total.cal >= query.calories * leastOfLimit
            && (!doubled || order.items[0].food.cal <= largestDoubled)
    }

    /// The dinners at each restaurant that fit, closest fits first. A restaurant with none gets no slice.
    static func slices(_ foods: [Food], query: FindQuery) -> [Slice] {
        var slices: [Slice] = []
        for (chain, menu) in Dictionary(grouping: foods.filter(isDinnerFood), by: \.chain).sorted(by: { $0.key < $1.key }) {
            if Task.isCancelled { return [] }
            guard chain != "mine", !notDinner.contains(chain), query.chains.isEmpty || query.chains.contains(chain) else { continue }
            let orders = MealFinder.find(menu, query: query).filter { isDinner($0, query: query) }
            if !orders.isEmpty { slices.append(Slice(chain: chain, orders: orders)) }
        }
        return slices
    }

    /// What one spin lands on: a slice, then one of its dinners. Every restaurant gets the same chance however long its menu is,
    /// and neither the last restaurant nor the last order comes up twice running when there's another to choose.
    static func spin(_ slices: [Slice], after last: MealMatch?, using random: inout some RandomNumberGenerator) -> (slice: Int, order: MealMatch)? {
        let fresh = slices.indices.filter { slices[$0].chain != last?.chain }
        guard let slice = (fresh.isEmpty ? Array(slices.indices) : fresh).randomElement(using: &random) else { return nil }
        let orders = slices[slice].orders
        let unseen = orders.filter { $0.id != last?.id }
        guard let order = (unseen.isEmpty ? orders : unseen).randomElement(using: &random) else { return nil }
        return (slice, order)
    }

    /// Where the wheel stops, in degrees clockwise, so the middle of `slice` plus `offset` slice-widths sits under the pointer at the top,
    /// after at least `turns` whole turns from `angle`. Slice 0 starts at the pointer and they run clockwise.
    static func landing(from angle: Double, slice: Int, count: Int, turns: Int, offset: Double = 0) -> Double {
        let sweep = 360 / Double(max(count, 1))
        let stop = 360 - (Double(slice) + 0.5 + offset) * sweep
        let start = angle.truncatingRemainder(dividingBy: 360)
        let extra = (stop - start).truncatingRemainder(dividingBy: 360)
        return angle + Double(turns) * 360 + (extra < 0 ? extra + 360 : extra)
    }

    /// The slice under the pointer when the wheel is turned to `angle`.
    static func slice(at angle: Double, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let turned = (360 - angle.truncatingRemainder(dividingBy: 360)).truncatingRemainder(dividingBy: 360)
        return min(count - 1, Int((turned < 0 ? turned + 360 : turned) / (360 / Double(count))))
    }
}
