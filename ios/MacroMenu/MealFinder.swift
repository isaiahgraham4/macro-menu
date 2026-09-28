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
}
struct MealMatch: Identifiable, Sendable {
    var items: [Portion]
    var id: String { items.map { $0.food.id }.joined(separator: "|") }
    var total: Nutrition
    var chain: String { items.first?.food.chain ?? "mine" }
}
enum MealFinder {
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
        var best: [String: [MealMatch]] = [:]
        func better(_ a: MealMatch, _ b: MealMatch) -> Bool {
            let x = a.total, y = b.total
            let sx = max(0, q.protein - x.p).rounded(), sy = max(0, q.protein - y.p).rounded()
            if q.sort == "protein" { return x.p == y.p ? x.cal < y.cal : x.p > y.p }
            if sx != sy { return sx < sy }
            switch q.sort {
            case "lean": return x.cal < y.cal
            case "cheap": return x.price < y.price
            case "value": return x.p / max(x.price,0.01) > y.p / max(y.price,0.01)
            default: return x.cal == y.cal ? a.items.count < b.items.count : x.cal > y.cal
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
            let anchor = list[0].id
            var candidates = best[anchor] ?? []; candidates.append(match); candidates.sort(by: better)
            best[anchor] = Array(candidates.prefix(2))
        }
        for chain in Set(foods.map(\.chain)).sorted() where q.chains.isEmpty || q.chains.contains(chain) {
            let eligible = foods.filter { $0.chain == chain && $0.cat != "swap" && $0.cal > 0 && $0.cal <= q.calories }
            let mains = eligible.filter(\.isAnchor)
            let sides = eligible.filter { !$0.isAnchor && ($0.cal >= 50 || $0.cat == "drink") }.sorted { $0.cal < $1.cal }
            for main in mains {
                if Task.isCancelled { return [] }
                consider([main])
                guard q.maxItems > 1 else { continue }
                consider([main,main])
                for a in sides.indices {
                    if main.cal + sides[a].cal > q.calories { break }
                    consider([main,sides[a]])
                    if q.maxItems > 2 {
                        consider([main,main,sides[a]])
                        for b in a..<sides.count {
                            if main.cal + sides[a].cal + sides[b].cal > q.calories { break }
                            consider([main,sides[a],sides[b]])
                        }
                    }
                }
                if q.maxItems > 2 { consider([main,main,main]) }
            }
        }
        return Array(best.values.flatMap { $0 }.sorted(by: better).prefix(24))
    }
}
