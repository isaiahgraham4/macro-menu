import Foundation

/// What's in a restaurant item, from the restaurant's own words (see `Scripts/diet-info.py`). Nil fields aren't known.
struct DietInfo: Codable, Hashable, Sendable {
    /// The meats in it: beef, pork, chicken, lamb, fish, seafood, gelatine, other. Empty when there's none; nil when not known.
    var meat: [String]?
    /// Allergens the restaurant lists it as containing; nil when it doesn't publish them for this item.
    var al: [String]?
    /// Allergens it may contain.
    var may: [String]?
    /// "vegan" or "vegetarian".
    var vg: String?
    /// Where the meat information came from: "ingredients", "description", "name" or "labels".
    var src: String?

    var isVegetarian: Bool { meat?.isEmpty == true }
    var isVegan: Bool { vg == "vegan" }

    /// For everyday foods, which are single foods named plainly ("Chicken breast, cooked", "Greek yoghurt"), from the name.
    static func guess(_ name: String) -> DietInfo {
        let lower = name.lowercased()
        let meat = DietOption.meatWords.filter { lower.range(of: $0.value, options: .regularExpression) != nil }.map(\.key).sorted()
        let al = DietOption.allergenWords.filter { lower.range(of: $0.value, options: .regularExpression) != nil }.map(\.key).sorted()
        let animal = lower.range(of: #"honey|\bmilk|cheese|yog|butter|cream|egg|whey"#, options: .regularExpression) != nil
        return DietInfo(meat: meat, al: al, vg: meat.isEmpty ? (animal ? "vegetarian" : "vegan") : nil, src: "name")
    }
}

enum DietOption: String, CaseIterable, Identifiable, Sendable {
    case vegetarian, vegan, noBeef = "nobeef", noPork = "nopork"
    case gluten, milk, egg, soy, sesame, peanut, treenut, fish, shellfish
    var id: String { rawValue }

    static let meatOptions: [DietOption] = [.vegetarian, .vegan, .noBeef, .noPork]
    static let allergenOptions: [DietOption] = [.gluten, .milk, .egg, .soy, .sesame, .peanut, .treenut, .fish, .shellfish]
    var isAllergen: Bool { DietOption.allergenOptions.contains(self) }

    var title: String {
        switch self {
        case .vegetarian: "Vegetarian"
        case .vegan: "Vegan"
        case .noBeef: "No beef"
        case .noPork: "No pork"
        case .gluten: "Gluten"
        case .milk: "Milk"
        case .egg: "Eggs"
        case .soy: "Soy"
        case .sesame: "Sesame"
        case .peanut: "Peanuts"
        case .treenut: "Tree nuts"
        case .fish: "Fish"
        case .shellfish: "Shellfish"
        }
    }
    /// Short words for a summary: "Vegetarian · No gluten".
    var short: String { isAllergen ? "No \(title.lowercased())" : title }

    /// An allergen's name in a sentence: "Contains gluten, milk".
    static func allergenName(_ key: String) -> String { DietOption(rawValue: key)?.title.lowercased() ?? key }

    static let meatWords: [String: String] = [
        "beef": #"\bbeef|steak|\bmince|veal|brisket"#, "pork": #"\bpork|bacon|\bham\b|salami|prosciutto|chorizo|pepperoni"#,
        "chicken": #"chicken|turkey|\bduck"#, "lamb": #"\blamb\b|mutton"#, "fish": #"\bfish|salmon|tuna|\bcod\b|sardine|anchov|barramundi|snapper|trout"#,
        "seafood": #"prawn|shrimp|crab|lobster|oyster|mussel|scallop|squid|calamari"#, "gelatine": #"gelatin|jelly"#,
    ]
    static let allergenWords: [String: String] = [
        "gluten": #"bread|wheat|pasta|spaghetti|noodle|flour|toast|cereal|\boats?\b|barley|\brye\b|beer|biscuit|cake|cracker|muffin|pizza|couscous|bagel|croissant|tortilla|wrap|weet|bran|crumpet|pastry|pie\b"#,
        "milk": #"\bmilk|cheese|yog|butter|cream|latte|cappuccino|flat white|whey|custard|ice cream|ricotta|feta|mozzarella|parmesan"#,
        "egg": #"\beggs?\b|mayo|omelette|frittata"#, "soy": #"\bsoy|tofu|edamame|tempeh|miso"#, "sesame": #"sesame|tahini|hummus"#,
        "peanut": #"peanut"#, "treenut": #"almond|cashew|walnut|pecan|pistachio|hazelnut|macadamia|brazil nut|\bnuts?\b"#,
        "fish": #"\bfish|salmon|tuna|\bcod\b|sardine|anchov|barramundi|snapper|trout"#,
        "shellfish": #"prawn|shrimp|crab|lobster|oyster|mussel|scallop|squid|calamari"#,
    ]
}

/// The dietary needs set on Find, which leave items out of orders, Best choices, search and suggestions.
/// An item is only offered when the restaurant's own words show it fits; anything unknown is left out.
struct DietFilter: Equatable, Hashable, Sendable {
    var options: Set<DietOption> = []
    static let storageKey = "diet.filter"

    init(options: Set<DietOption> = []) { self.options = options }
    init(raw: String) { options = Set(raw.split(separator: ",").compactMap { DietOption(rawValue: String($0)) }) }
    var raw: String { options.map(\.rawValue).sorted().joined(separator: ",") }
    /// What's set on this device.
    static var saved: DietFilter { DietFilter(raw: UserDefaults.standard.string(forKey: storageKey) ?? "") }

    var isEmpty: Bool { options.isEmpty }
    var allergens: Set<String> { Set(options.filter(\.isAllergen).map(\.rawValue)) }
    /// "Vegetarian · No gluten", in the order the options are listed.
    var summary: String {
        // Vegan covers vegetarian, and either covers no beef and no pork.
        var shown = options
        if shown.contains(.vegan) { shown.remove(.vegetarian) }
        if shown.contains(.vegan) || shown.contains(.vegetarian) { shown.subtract([.noBeef, .noPork]) }
        return DietOption.allCases.filter(shown.contains).map(\.short).joined(separator: " · ")
    }

    /// Whether an item fits. Your own foods always do: you know what's in them.
    func allows(_ food: Food) -> Bool {
        guard !isEmpty, food.chain != "mine" else { return true }
        guard let info = food.isEveryday ? DietInfo.guess(food.name) : food.diet else { return false }
        if options.contains(where: { !$0.isAllergen }) {
            guard let meat = info.meat else { return false }
            if options.contains(.vegetarian) && !meat.isEmpty { return false }
            if options.contains(.vegan) && !info.isVegan { return false }
            // Gelatine is made from pork or beef, so it counts against both.
            if options.contains(.noBeef) && (meat.contains("beef") || meat.contains("gelatine")) { return false }
            if options.contains(.noPork) && (meat.contains("pork") || meat.contains("gelatine")) { return false }
        }
        let avoid = allergens
        if !avoid.isEmpty {
            // "May contain" counts too: someone avoiding an allergen can't take that chance.
            guard let al = info.al else { return false }
            if !avoid.isDisjoint(with: al) || !avoid.isDisjoint(with: info.may ?? []) { return false }
        }
        return true
    }
}

extension String {
    /// "KFC's", but "Nando's" and "McDonald's" stay as they are.
    var possessive: String { hasSuffix("'s") || hasSuffix("’s") ? self : self + "'s" }
}
