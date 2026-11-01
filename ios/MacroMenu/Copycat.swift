import Foundation

/// Copycat Kitchen: home versions of takeaway items, added up from their ingredients and put next to the chain's own
/// figures. Recipes come from `Scripts/copycat.py`; the shop side is read from the menu, so a menu update reaches it.
struct CopycatBook: Codable, Sendable {
    var ingredients: [String: CopycatIngredient]
    var recipes: [CopycatRecipe]

    static let bundled: CopycatBook = load(Bundle.main.url(forResource: "CopycatKitchen", withExtension: "json"))
    static func load(_ url: URL?) -> CopycatBook {
        guard let url, let data = try? Data(contentsOf: url), let book = try? JSONDecoder().decode(CopycatBook.self, from: data) else {
            return CopycatBook(ingredients: [:], recipes: [])
        }
        return book
    }

    /// The one-serve total of a recipe with these swaps on.
    func nutrition(_ recipe: CopycatRecipe, swaps: Set<String> = []) -> Nutrition {
        Nutrition(portions(recipe, swaps: swaps))
    }

    /// Every ingredient as a portion of its per-100 g figures, so saving a recipe keeps it editable like one built by hand.
    func portions(_ recipe: CopycatRecipe, swaps: Set<String> = []) -> [Portion] {
        recipe.rows(swaps: swaps).compactMap { row in
            ingredients[row.key].map { Portion(food: $0.food(key: row.key, name: row.label), quantity: row.g / 100) }
        }
    }

    /// One serve as a food to log or save. The ID follows the recipe and its swaps, so saving it again updates the same food.
    func food(_ recipe: CopycatRecipe, swaps: Set<String> = [], shopName: String) -> Food {
        let items = portions(recipe, swaps: swaps)
        var value = Nutrition(items).food(name: swaps.isEmpty ? recipe.name : "\(recipe.name), lighter", servings: 1, ingredients: items)
        // Whole calories and tenths of a gram: these are sums of averages, and finer digits would claim more than they know.
        value.cal = value.cal.rounded(); value.kj = value.cal * 4.184; value.p = value.p.tenth
        value.c = value.c?.tenth; value.f = value.f?.tenth
        value.nut = value.nut?.reduce(into: [:]) { $0[$1.key] = $1.key == "sodium" ? $1.value.rounded() : $1.value.tenth }
        value.id = (["copycat", recipe.id] + swaps.sorted()).joined(separator: ":")
        value.serve = recipe.serving
        value.note = "Home version of \(shopName), added up from its ingredients."
        return value
    }

    /// Recipes with a shop item still on the menu, each beside that item at the size the recipe is compared with.
    func comparisons(menu: [Food]) -> [CopycatComparison] {
        let ids = Set(recipes.map(\.shop))
        let shop = Dictionary(menu.filter { ids.contains($0.id) }.map { ($0.id, $0) }) { a, _ in a }
        return recipes.compactMap { recipe in
            guard let food = shop[recipe.shop] else { return nil }
            return CopycatComparison(recipe: recipe, shopFood: food, shop: Nutrition([Portion(food: food, quantity: recipe.quantity)]),
                                     home: nutrition(recipe), lean: nutrition(recipe, swaps: Set(recipe.swaps.map(\.id))))
        }
    }
}

struct CopycatIngredient: Codable, Sendable {
    var kj: Double
    var p: Double
    var c: Double
    var f: Double
    var nut: [String: Double]

    func food(key: String, name: String) -> Food {
        Food(id: "copycat:\(key)", chain: Food.everyday, name: name, cat: "food", kj: kj, cal: kj / 4.184, p: p, c: c, f: f, serve: "100 g", nut: nut)
    }
}

struct CopycatRow: Codable, Identifiable, Hashable, Sendable {
    var slot: String
    var key: String
    var g: Double
    var label: String
    var measure: String
    /// True once a swap has changed this row. Not stored in the recipe file.
    var swapped = false
    var id: String { slot }
    private enum CodingKeys: String, CodingKey { case slot, key, g, label, measure }
}

struct CopycatSwap: Codable, Identifiable, Hashable, Sendable {
    struct Change: Codable, Hashable, Sendable {
        var slot: String
        var key: String?
        var g: Double?
        var label: String?
        var measure: String?
    }
    var id: String
    var label: String
    var why: String
    var changes: [Change]
}

struct CopycatRecipe: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    /// The menu item it copies, and how many of it make the compared size (three slices of a pizza).
    var shop: String
    var quantity: Double
    var unit: String
    var serves: Int
    var time: String
    var hook: String
    var verdict: String
    var method: [String]
    var rows: [CopycatRow]
    var swaps: [CopycatSwap]

    /// "1 burger", or the unit as it stands when it already has a number ("3 large slices").
    var serving: String { unit.first?.isNumber == true ? unit : "1 \(unit)" }

    func rows(swaps on: Set<String>) -> [CopycatRow] {
        var result = rows
        for swap in swaps where on.contains(swap.id) {
            for change in swap.changes {
                guard let i = result.firstIndex(where: { $0.slot == change.slot }) else { continue }
                if let key = change.key { result[i].key = key }
                if let g = change.g { result[i].g = g }
                if let label = change.label { result[i].label = label }
                if let measure = change.measure { result[i].measure = measure }
                result[i].swapped = true
            }
        }
        return result
    }
}

struct CopycatComparison: Identifiable, Sendable {
    var recipe: CopycatRecipe
    var shopFood: Food
    var shop: Nutrition
    var home: Nutrition
    var lean: Nutrition
    var id: String { recipe.id }
    /// The menu name, without the slice count of an item sold by the slice.
    var shopName: String { shopFood.name.replacingOccurrences(of: " (1 slice)", with: "") }

    /// Percent change in energy from the shop's figure.
    func change(_ total: Nutrition) -> Int {
        shop.kj > 0 ? Int(((total.kj - shop.kj) / shop.kj * 100).rounded()) : 0
    }
    var verdict: CopycatVerdict { CopycatVerdict(change(home)) }
}

/// Within 2% either way is too close to call, given the ingredient figures are averages.
enum CopycatVerdict: Sendable {
    case homeLighter, level, shopLighter
    init(_ change: Int) { self = change < -2 ? .homeLighter : change > 2 ? .shopLighter : .level }
    var title: String {
        switch self {
        case .homeLighter: "Home lighter"
        case .level: "About level"
        case .shopLighter: "Shop lighter"
        }
    }
}

enum CopycatSort: String, CaseIterable, Identifiable, Sendable {
    case saving, protein, fat
    var id: Self { self }
    var title: String {
        switch self {
        case .saving: "Biggest saving"
        case .protein: "Most extra protein"
        case .fat: "Most fat cut"
        }
    }
    func sorted(_ list: [CopycatComparison]) -> [CopycatComparison] {
        switch self {
        case .saving: list.sorted { $0.change($0.home) < $1.change($1.home) }
        case .protein: list.sorted { $0.home.p - $0.shop.p > $1.home.p - $1.shop.p }
        case .fat: list.sorted { $0.home.f - $0.shop.f < $1.home.f - $1.shop.f }
        }
    }
}
