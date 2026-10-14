import Foundation

struct FindQuery: Equatable, Sendable {
    var chains: Set<String> = []
    var calories = 500.0
    var protein = 40.0
    var carbs: Double?
    var fat: Double?
    var budget: Double?
    var maxItems = 2
    var sort = "fit"
    /// Also try each item customised: sauce or cheese taken off, or another patty or fillet added.
    var customise = true
    /// Dietary needs: only items the restaurant's words show fit are used.
    var diet = DietFilter()
}
struct MealMatch: Identifiable, Sendable {
    var items: [Portion]
    var id: String { items.map { $0.food.id }.joined(separator: "|") }
    var total: Nutrition
    var chain: String { items.first?.food.chain ?? "mine" }
    /// Items changed from how the restaurant sells them.
    var customised: Int { items.filter { MealFinder.isVariant($0.food) }.count }
}
enum MealFinder {
    /// Customised copies of a food get an ID made from the original's and the changes, after this mark.
    static let variantMark: Character = "~"
    static func isVariant(_ food: Food) -> Bool { food.id.contains(variantMark) }
    static func baseID(_ food: Food) -> Substring { food.id.split(separator: variantMark, maxSplits: 1).first ?? Substring(food.id) }

    /// Parts that make an item what it is (the bun, the meat), so they're never taken off to make it fit.
    private static let structural: Set<Substring> = ["bun", "bread", "roll", "muffin", "tortilla", "wrap", "base", "crust", "toast", "rice",
        "patty", "patties", "beef", "chicken", "fillet", "fish", "egg", "sausage", "ham", "steak", "pork", "tofu"]
    static func isStructural(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("make it a") || lower.split { !$0.isLetter }.contains { structural.contains($0) }
    }

    /// Whether the item is named after the part a removal takes off, like cheese on a Cheeseburger or bacon on a Bacon & Egg McMuffin.
    static func names(_ food: Food, _ removal: Modifier) -> Bool {
        let part = removal.name.lowercased().replacingOccurrences(of: "no ", with: "", options: .anchored)
        return food.name.lowercased().contains(part)
    }

    /// Ways to order a food so it fits better, each a customised copy of it.
    /// Lighter: taking off up to three of the parts that save the most energy (sauces, cheese, bacon), never the bun or the meat.
    /// More protein: the extra patty or fillet with the most protein for its energy, alone and with the lighter changes.
    /// With dietary needs set, only removals are used: what an extra patty or fillet adds isn't known for every need.
    static func variants(of food: Food, additions: Bool = true) -> [Food] {
        let mods = food.modifiers ?? []
        guard !mods.isEmpty, food.cal > 0 else { return [] }
        // Removals worth making: they save at least 60 kJ and cost little protein. One per group (one kind of cheese, say).
        var groups = Set<String>()
        let removals = mods.filter { $0.kind == "r" && -$0.kj >= 60 && -$0.p <= max(2, food.p * 0.15) && !isStructural($0.name) && !names(food, $0) }
            .sorted { $0.kj < $1.kj }
            .filter { groups.insert($0.group ?? $0.key).inserted }
        let protein = additions ? mods.filter { $0.kind == "f" && $0.p >= 4 && $0.kj > 0 }
            .max { $0.p / $0.kj < $1.p / $1.kj } : nil
        var plans: [[String: Double]] = []
        for count in 1...min(3, max(1, removals.count)) where removals.count >= count {
            plans.append(Dictionary(uniqueKeysWithValues: removals.prefix(count).map { ($0.key, 1.0) }))
        }
        if let protein {
            plans.append([protein.key: 1])
            for lighter in plans.dropLast() { plans.append(lighter.merging([protein.key: 1]) { a, _ in a }) }
        }
        return plans.map { plan in
            var copy = food.customised(plan)
            copy.id = food.id + String(variantMark) + plan.keys.sorted().joined(separator: "+")
            return copy
        }.filter(\.isValid)
    }

    static func extraFits(_ main: Food, _ extra: Food) -> Bool {
        if extra.name.hasPrefix("Mini Extra:") { return main.name.contains("Mini") }
        if extra.name.hasPrefix("Brekkie Extra:") { return main.cat == "breakfast" }
        if extra.name.hasPrefix("Dipping Sauce:") {
            return main.name.range(of: "Tender|Fries|Nugget|Wing|Pops|Fried Chicken|Chicken Piece|Strips|Bolas|Bites|Chips|Drumstick", options: [.regularExpression,.caseInsensitive]) != nil
        }
        if extra.chain == "gyg" && extra.name.hasPrefix("Extra ") {
            return main.cat != "breakfast" && main.name.range(of: "Mini|Little G|Taco|Quesadilla|Fries|Tender", options: .regularExpression) == nil
        }
        return !(extra.chain == "sub" && extra.name.hasPrefix("Extra ") && main.name.contains("Nachos"))
    }
    static func find(_ foods: [Food], query q: FindQuery) -> [MealMatch] {
        guard q.calories > 0 else { return [] }
        let foods = q.diet.isEmpty ? foods : foods.filter(q.diet.allows)
        var best: [String: [MealMatch]] = [:]
        func better(_ a: MealMatch, _ b: MealMatch) -> Bool {
            let x = a.total, y = b.total
            let sx = max(0, q.protein - x.p).rounded(), sy = max(0, q.protein - y.p).rounded()
            if q.sort == "protein" { return x.p == y.p ? (x.cal == y.cal ? a.customised < b.customised : x.cal < y.cal) : x.p > y.p }
            if sx != sy { return sx < sy }
            // Otherwise equal orders: the one with fewer changes from how it's sold.
            if x.cal.rounded() == y.cal.rounded() && a.customised != b.customised { return a.customised < b.customised }
            switch q.sort {
            case "lean": return x.cal < y.cal
            case "cheap": return x.price < y.price
            case "value": return x.p / max(x.price,0.01) > y.p / max(y.price,0.01)
            default:
                // Closest fit: when both meet protein equally, an order as it's sold beats one that needs changes.
                if a.customised != b.customised { return a.customised < b.customised }
                return x.cal == y.cal ? a.items.count < b.items.count : x.cal > y.cal
            }
        }
        func consider(_ list: [Food]) {
            let cal = list.reduce(0) { $0 + $1.cal }
            guard cal <= q.calories else { return }
            guard list.filter({ $0.cat == "drink" }).count <= 1, list.filter({ $0.cat == "sweet" }).count <= 1 else { return }
            let extras = list.filter { $0.cat == "extra" }
            guard extras.count <= 1, extras.allSatisfy({ extraFits(list[0],$0) }) else { return }
            if q.carbs != nil || q.fat != nil { guard list.allSatisfy({ $0.c != nil && $0.f != nil }) else { return } }
            if let cap = q.carbs, list.reduce(0, { $0 + ($1.c ?? 0) }) > cap { return }
            if let cap = q.fat, list.reduce(0, { $0 + ($1.f ?? 0) }) > cap { return }
            if q.budget != nil || q.sort == "cheap" || q.sort == "value" { guard list.allSatisfy({ $0.price != nil }) else { return } }
            if let budget = q.budget, list.reduce(0, { $0 + ($1.price ?? 0) }) > budget { return }
            let items = list.map { Portion(food: $0) }
            let match = MealMatch(items: items, total: Nutrition(items))
            // An item and its customised versions share two places, so one burger doesn't fill the list.
            let anchor = String(baseID(list[0]))
            var candidates = best[anchor] ?? []; candidates.append(match); candidates.sort(by: better)
            best[anchor] = Array(candidates.prefix(2))
        }
        for chain in Set(foods.map(\.chain)).sorted() where q.chains.isEmpty || q.chains.contains(chain) {
            let eligible = foods.filter { $0.chain == chain && $0.cat != "swap" && $0.cal > 0 && $0.cal <= q.calories }
            // A chain with no mains (a juice bar) builds orders around its drinks instead.
            let anchors = foods.contains { $0.chain == chain && $0.isAnchor }
            var mains = anchors ? eligible.filter(\.isAnchor) : eligible
            if q.customise {
                // Built from every main, including those over the limit as sold: taking the sauce off may bring one under it.
                let all = foods.filter { $0.chain == chain && $0.cat != "swap" && $0.cal > 0 && (!anchors || $0.isAnchor) }
                mains += all.flatMap { variants(of: $0, additions: q.diet.isEmpty) }.filter { $0.cal <= q.calories }
            }
            let sides = anchors ? eligible.filter { !$0.isAnchor && ($0.cal >= 50 || $0.cat == "drink") }.sorted { $0.cal < $1.cal } : []
            for main in mains {
                if Task.isCancelled { return [] }
                // Customised items are tried alone, doubled and with one side; three-item orders stay as sold, which keeps the search quick.
                let full = q.maxItems > 2 && !isVariant(main)
                consider([main])
                guard q.maxItems > 1 else { continue }
                consider([main,main])
                for a in sides.indices {
                    if main.cal + sides[a].cal > q.calories { break }
                    consider([main,sides[a]])
                    if full {
                        consider([main,main,sides[a]])
                        for b in a..<sides.count {
                            if main.cal + sides[a].cal + sides[b].cal > q.calories { break }
                            consider([main,sides[a],sides[b]])
                        }
                    }
                }
                if full { consider([main,main,main]) }
            }
        }
        return Array(best.values.flatMap { $0 }.sorted(by: better).prefix(24))
    }
}
