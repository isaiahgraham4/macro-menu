import Foundation

/// One thing in a dish and how much of it, from Takeawise's own foods.
struct MenuComponent: Identifiable, Equatable, Sendable {
    var id = UUID()
    var food: Food
    var quantity: Double
    /// False when it's been taken out of the dish.
    var isOn = true
    var grams: Double? { food.servingWeight.map { $0.0 * quantity } }
    var portion: Portion { Portion(food: food, quantity: quantity) }
}

/// What a dish probably has in it, and how that was worked out. The figures always come from Takeawise's foods.
struct MenuEstimate: Equatable, Sendable {
    enum Basis: Equatable, Sendable {
        /// The restaurant's own item, found in Takeawise's menus.
        case official
        /// A dish Takeawise knows, at a typical serve.
        case typicalDish
        /// Added up from the ingredients the menu lists.
        case ingredients
        /// Apple Intelligence said what's usually in it, and Takeawise added that up.
        case suggested
        /// Very little to go on, such as one ingredient or only the menu's heading.
        case rough
        /// The person searched for it and picked a food.
        case chosen
    }

    var components: [MenuComponent]
    var basis: Basis

    /// How far off the figure could be, as a share of it either way.
    var spread: Double {
        switch basis {
        case .official, .chosen: 0
        case .typicalDish: 0.2
        case .ingredients: 0.3
        case .suggested: 0.3
        case .rough: 0.4
        }
    }

    var label: String {
        switch basis {
        case .official: "Official figures"
        case .typicalDish: "Typical serve"
        case .ingredients: "From the menu's ingredients"
        case .suggested: "Ingredients suggested on your iPhone"
        case .rough: "Rough guess"
        case .chosen: "Your pick"
        }
    }

    /// An exact food rather than a sum: its figures stand as they are, so sizes and rounding don't apply.
    var isExact: Bool { basis == .official || basis == .chosen }

    func total(_ size: PortionSize = .regular) -> Nutrition {
        Nutrition(components.filter(\.isOn).map { Portion(food: $0.food, quantity: $0.quantity * (isExact ? 1 : size.factor)) })
    }

    /// What to log for the dish.
    func portion(named name: String, size: PortionSize = .regular) -> Portion? {
        if isExact { return components.first { $0.isOn }?.portion }
        return food(named: name, size: size).map { Portion(food: $0) }
    }

    /// The dish as something to log: the restaurant's own item when there is one, otherwise one estimated food, rounded so it
    /// doesn't claim to be exact. It's nil when everything has been taken out.
    func food(named name: String, size: PortionSize = .regular) -> Food? {
        let used = components.filter(\.isOn)
        guard !used.isEmpty else { return nil }
        if isExact, let food = used.first?.food { return food }
        let total = total(size)
        let calories = (total.cal / 10).rounded() * 10
        let others = total.nut.filter { !total.partial.contains($0.key) }.mapValues { ($0 * 10).rounded() / 10 }
        return Food(name: name, kj: (calories * 4.184).rounded(), cal: calories, p: total.p.rounded(), c: total.c.rounded(), f: total.f.rounded(),
                    serve: "1 dish, estimated", nut: others.isEmpty ? nil : others, note: "Estimated from a menu photo")
    }
}

/// Works out what's in a dish from its name and description. In order: the restaurant's own item, a dish in `MenuCookbook`,
/// the ingredients the menu lists, a dish with the same name in Takeawise's everyday foods, then the menu's heading.
/// With nothing to go on it gives no figure at all, rather than a made-up one.
struct MenuEstimator: Sendable {
    private let foods: [Food]
    private let chainNames: [String: String]
    private var byName: [String: Food] = [:]
    private var plain: [String: [Food]] = [:]
    /// Each cookbook phrase as joined words, with its place in the table.
    private let dishNames: [String: Int]

    init(foods: [Food], chainNames: [String: String]) {
        self.foods = foods; self.chainNames = chainNames
        var names: [String: Int] = [:]
        for (index, recipe) in MenuCookbook.recipes.enumerated() {
            for name in recipe.names { let key = name.joined(separator: " "); if names[key] == nil { names[key] = index } }
        }
        dishNames = names
        for food in foods where food.isEveryday {
            if byName[food.name] == nil { byName[food.name] = food }
            plain[Self.tokens(String(food.name.prefix { $0 != "," })).joined(separator: " "), default: []].append(food)
        }
    }

    /// Words as the tables hold them: lower case, no accents, no plurals.
    static func tokens(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_AU"))
            .replacingOccurrences(of: "’", with: "").replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "&", with: " and ")
            .split { !$0.isLetter && !$0.isNumber }.map { MealPhoto.stem(String($0)) }
    }

    func food(_ name: String) -> Food? { byName[name] }

    /// The restaurant a menu belongs to, when Takeawise has its menu.
    func chain(for restaurant: String?) -> String? {
        MealPhoto.chain(for: restaurant, chainNames: chainNames)
    }

    func estimate(_ dish: MenuDish, chain: String? = nil) -> MenuEstimate? {
        if let chain, let food = official(dish, chain: chain) {
            return MenuEstimate(components: [MenuComponent(food: food, quantity: 1)], basis: .official)
        }
        let name = Self.tokens(dish.name)
        let details = Self.tokens(dish.details)
        let all = name + ["."] + details
        let section = dish.section.map(Self.tokens) ?? []
        let scale = scale(for: section)
        let weight = statedWeight(dish.name + " " + dish.details)

        if let match = recipe(in: name) {
            // The words that named the dish aren't ingredients on top of it: "fried rice" isn't also rice.
            var rest = name
            rest.replaceSubrange(match.words, with: ["."])
            let found = ingredients(in: rest + ["."] + details)
            return finish(assemble(match.recipe, found: found, text: all, stated: weight), scale: match.recipe.style == .asSold ? 1 : scale,
                          basis: match.recipe.style == .base && found.contains { $0.food != nil } ? .ingredients : .typicalDish)
        }
        let found = ingredients(in: all)
        if let recipe = recipe(in: section)?.recipe {
            let basis: MenuEstimate.Basis = recipe.style == .asSold ? .rough : .ingredients
            return finish(assemble(recipe, found: found, text: all, stated: weight), scale: recipe.style == .asSold ? 1 : scale, basis: basis)
        }
        let useful = found.filter { $0.food != nil }
        if useful.count >= 2 {
            return finish(built(useful, text: all, stated: weight), scale: scale, basis: .ingredients)
        }
        if let (food, quantity) = wholeFood(name) {
            return MenuEstimate(components: [MenuComponent(food: food, quantity: quantity * scale)], basis: .typicalDish)
        }
        if useful.count == 1 {
            return finish(built(useful, text: all, stated: weight), scale: scale, basis: .rough)
        }
        return nil
    }

    /// The same sum from a list of ingredients and grams, for Apple Intelligence's answer. Nil when too little of it is in Takeawise.
    func estimate(suggested parts: [(name: String, grams: Double)], section: String?) -> MenuEstimate? {
        var components: [MenuComponent] = []
        for part in parts.prefix(10) where part.grams > 0 {
            let words = Self.tokens(part.name)
            let listed = ingredients(in: words).first { $0.food != nil }?.food
            let match = listed.flatMap { byName[$0] } ?? MealPhoto.matches(for: SeenFood(name: part.name, count: 1), in: foods, chainNames: chainNames, limit: 1).first { $0.isEveryday }
            guard let match, let component = component(match.name, grams: min(part.grams, 500)) ?? component(food: match, grams: min(part.grams, 500)),
                  !components.contains(where: { $0.food.id == component.food.id }) else { continue }
            components.append(component)
        }
        guard components.count >= 2 else { return nil }
        return MenuEstimate(components: components, basis: .suggested)
    }

    // MARK: Finding what's in it

    private func official(_ dish: MenuDish, chain: String) -> Food? {
        let seen = SeenFood(name: dish.name, brand: chainNames[chain], count: 1)
        return MealPhoto.matches(for: seen, in: foods, chainNames: chainNames, limit: 4).first { $0.chain == chain && MealPhoto.plainly($0, is: seen) }
    }

    /// The cookbook dish with the longest name in these words; the earlier in the table when two are as long.
    private func recipe(in words: [String]) -> (recipe: MenuCookbook.Recipe, words: Range<Int>)? {
        var best: (start: Int, length: Int, index: Int)?
        for start in words.indices {
            for length in 1...min(4, words.count - start) {
                guard let index = dishNames[words[start..<(start + length)].joined(separator: " ")] else { continue }
                if best == nil || length > best!.length || (length == best!.length && index < best!.index) { best = (start, length, index) }
            }
        }
        return best.map { (MenuCookbook.recipes[$0.index], $0.start..<($0.start + $0.length)) }
    }

    private struct Found {
        var food: String?
        var role: MenuCookbook.Role
        var grams: Double
        /// "or" came just before it, so it's an alternative to what's listed before.
        var isChoice: Bool
    }

    /// Ingredients in the order they're named, taking the longest run of words each time. Anything after "add" or "no" is left out.
    private func ingredients(in words: [String]) -> [Found] {
        var found: [Found] = []
        var index = words.startIndex
        while index < words.endIndex {
            var matched = false
            for length in stride(from: min(4, words.count - index), through: 1, by: -1) {
                guard let item = MenuCookbook.ingredients[words[index..<(index + length)].joined(separator: " ")] else { continue }
                let before = index > 0 ? words[index - 1] : ""
                if !["no", "without", "add", "extra"].contains(before) {
                    found.append(Found(food: item.food, role: item.role, grams: item.grams, isChoice: before == "or"))
                }
                index += length; matched = true
                break
            }
            if !matched { index += 1 }
        }
        return found
    }

    /// The weight a menu prints, as in "300 g scotch fillet".
    private func statedWeight(_ text: String) -> Double? {
        guard let match = text.firstMatch(of: /(?i)\b(\d{2,4})\s?(g|gm|gram|grams)\b/), let grams = Double(match.1), (50...1500).contains(grams) else { return nil }
        return grams
    }

    private static let fryingWords: Set<String> = ["fried", "crumbed", "battered", "tempura", "karaage", "panko", "schnitzel", "crispy"]

    /// Whether something in the dish is crumbed or deep fried. A fried egg, stir fried noodles and crispy skin don't count.
    private func isFried(_ words: [String]) -> Bool {
        words.indices.contains { index in
            guard Self.fryingWords.contains(words[index]) else { return false }
            let before = index > 0 ? words[index - 1] : "", after = index + 1 < words.count ? words[index + 1] : ""
            return before != "stir" && !["egg", "rice", "skin"].contains(after)
        }
    }

    /// The proteins to use for `slot` grams. One named is the lot; several share a little more; a choice ("chicken or tofu") is the first.
    private func proteins(_ found: [Found], slot: Double) -> [MenuCookbook.Part] {
        var list = found.filter { $0.role == .protein && $0.food != nil }
        var seen = Set<String>()
        list = list.filter { seen.insert($0.food ?? "").inserted }
        if list.contains(where: \.isChoice) { list = Array(list.prefix(1)) }
        guard list.count > 1 else { return list.first.map { [.init(food: $0.food ?? "", grams: slot)] } ?? [] }
        let share = slot * min(1.5, 1 + 0.25 * Double(list.count - 1)) / Double(list.count)
        return list.prefix(4).map { .init(food: $0.food ?? "", grams: share) }
    }

    /// A starch the menu names: it takes the place of the dish's usual one of the same kind, or joins the plate if there's none.
    /// Rice, pasta or noodles are left out of a dish that's already made with them.
    private func add(_ item: Found, to parts: inout [MenuCookbook.Part]) {
        guard let food = item.food, !item.isChoice, !parts.contains(where: { $0.food == food }) else { return }
        if let kind = MenuCookbook.swaps.first(where: { $0.contains(food) }) {
            let usual = parts.firstIndex { kind.contains($0.food) }
            if usual == nil, kind == MenuCookbook.swaps[0], parts.contains(where: { MenuCookbook.filled.contains($0.food) }) { return }
            if let usual { parts[usual] = .init(food: food, grams: parts[usual].grams); return }
        }
        parts.append(.init(food: food, grams: item.grams))
    }

    private func assemble(_ recipe: MenuCookbook.Recipe, found: [Found], text: [String], stated: Double?) -> [MenuCookbook.Part] {
        var parts = recipe.parts
        switch recipe.style {
        case .asSold:
            return parts
        case .plate:
            for item in found where item.role == .starch { add(item, to: &parts) }
            return parts
        case .base:
            var fillings = proteins(found, slot: recipe.protein)
            if fillings.isEmpty, let usual = recipe.usual { fillings = [usual] }
            if let stated, !fillings.isEmpty { fillings[0].grams = stated }
            parts = fillings.filter { part in !parts.contains { $0.food == part.food } } + parts
            for item in found where item.role != .protein && !recipe.covers.contains(item.role) {
                if item.role == .starch { add(item, to: &parts) }
                else if let food = item.food, !parts.contains(where: { $0.food == food }) { parts.append(.init(food: food, grams: item.grams * 0.7)) }
            }
            if isFried(text) { parts += frying }
            return parts
        }
    }

    private var frying: [MenuCookbook.Part] { [.init(food: "Plain flour", grams: 20), .init(food: "Canola oil", grams: 15)] }

    /// A dish with no cookbook entry, from its ingredients, with a little oil the way a kitchen would use it.
    private func built(_ found: [Found], text: [String], stated: Double?) -> [MenuCookbook.Part] {
        var parts = proteins(found, slot: found.first { $0.role == .protein }?.grams ?? 0)
        if let stated, !parts.isEmpty { parts[0].grams = stated }
        for item in found where item.role != .protein {
            if let food = item.food, !parts.contains(where: { $0.food == food }) { parts.append(.init(food: food, grams: item.grams)) }
        }
        return parts + (isFried(text) ? frying : [.init(food: "Olive oil", grams: 10)])
    }

    /// A food called exactly what the dish is called. A food sold by the cup is a small measure, so it's made a plateful.
    private func wholeFood(_ name: [String]) -> (Food, Double)? {
        guard let hits = plain[name.joined(separator: " ")], let food = MealPhoto.ordered(hits, for: name).first,
              let weight = food.servingWeight?.0, weight > 0 else { return nil }
        return (food, food.serve.contains("cup") || weight <= 100 ? 350 / weight : 1)
    }

    /// Starters and shared plates are smaller than a main, and so are sides and kids' meals.
    private func scale(for section: [String]) -> Double {
        if section.contains(where: { ["entree", "starter", "small", "share", "sharing", "tapa", "appetiser", "appetizer", "antipasti", "snack", "bar"].contains($0) }) { return 0.55 }
        if section.contains(where: { ["side", "kid", "children", "junior", "little"].contains($0) }) { return 0.6 }
        return 1
    }

    private func component(_ name: String, grams: Double) -> MenuComponent? {
        byName[name].flatMap { component(food: $0, grams: grams) }
    }

    private func component(food: Food, grams: Double) -> MenuComponent? {
        guard let weight = food.servingWeight?.0, weight > 0 else { return nil }
        return MenuComponent(food: food, quantity: grams / weight)
    }

    private func finish(_ parts: [MenuCookbook.Part], scale: Double, basis: MenuEstimate.Basis) -> MenuEstimate? {
        var components: [MenuComponent] = []
        for part in parts {
            guard let made = component(part.food, grams: part.grams * scale) else { continue }
            if let index = components.firstIndex(where: { $0.food.id == made.food.id }) { components[index].quantity += made.quantity } else { components.append(made) }
        }
        return components.isEmpty ? nil : MenuEstimate(components: components, basis: basis)
    }
}
