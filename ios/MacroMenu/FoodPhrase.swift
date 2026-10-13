import Foundation

/// A food named in words: typed or spoken ("two eggs", "200 g chicken breast", "a flat white from Maccas"), or an ingredient
/// line from a recipe ("2 cups (300 g) plain flour, sifted"). Only what and how much; the figures always come from Leanr's own foods.
struct FoodPhrase: Equatable, Sendable {
    enum Unit: String, Equatable, Sendable {
        case gram, millilitre, cup, tablespoon, teaspoon
        /// Counted things: a slice, a can, a bowl. Each is taken as one serving.
        case each
    }
    /// What to search for, without amounts or preparation.
    var name: String
    /// The number given, or nil when none was.
    var amount: Double?
    var unit: Unit?
    /// A restaurant or brand the words named ("from KFC", "Maccas").
    var brand: String?
    /// The line as written, for showing beside the match.
    var original: String
    /// Other names a food list might use, when Apple Intelligence offered some.
    var alternatives: [String] = []

    /// How many of `food`'s servings this is, and whether that came from the words or was a guess (an amount Leanr
    /// couldn't relate to the food's serving, which the screen asks to be checked).
    func servings(of food: Food) -> (servings: Double, sure: Bool) {
        let amount = self.amount ?? 1
        guard let unit, amount > 0 else { return (max(amount, 0.25), self.amount != nil || unit == nil) }
        let serve = food.serve.lowercased()
        switch unit {
        case .each:
            return (amount, true)
        case .cup where serve.contains("cup"), .tablespoon where serve.contains("tbsp") || serve.contains("tablespoon"),
             .teaspoon where serve.contains("tsp") || serve.contains("teaspoon"):
            let per = FoodPhrase.leadingNumber(serve) ?? 1
            return (amount / max(per, 0.01), true)
        default:
            let grams = amount * (unit == .cup ? 250 : unit == .tablespoon ? 15 : unit == .teaspoon ? 5 : 1)
            guard let weight = food.servingWeight?.0, weight > 0 else { return (1, false) }
            return (FoodPhrase.rounded(grams / weight), unit == .gram || unit == .millilitre)
        }
    }

    /// Servings to a sensible step: quarters, or tenths for small amounts.
    static func rounded(_ value: Double) -> Double {
        value < 1 ? max(0.1, (value * 10).rounded() / 10) : (value * 4).rounded() / 4
    }

    static func leadingNumber(_ text: String) -> Double? {
        var tokens = words(text)
        return quantity(&tokens)
    }

    /// Size words that a restaurant's menu uses ("Large Fries") but a list of everyday foods doesn't.
    private static let sizes: Set<String> = ["large", "medium", "small", "regular", "big", "little", "mini", "whole", "plain", "homemade", "fresh", "hot", "cold", "iced"]

    /// What people usually mean by a word that also starts a dish's name: "toast" is bread, not French toast.
    static let usualNames: [String: String] = [
        "toast": "white bread", "slice of toast": "white bread", "white toast": "white bread", "wholemeal toast": "wholemeal bread",
        "sourdough toast": "sourdough bread", "multigrain toast": "multigrain bread", "rye toast": "rye bread",
        "vegetable oil": "canola oil", "cooking oil": "canola oil", "oil": "olive oil", "extra virgin olive oil": "olive oil", "virgin olive oil": "olive oil",
        "coffee": "black coffee", "long black": "black coffee", "short black": "black coffee", "espresso": "black coffee",
    ]

    /// Words that describe a food rather than name it.
    private static let describing: Set<String> = [
        "light", "lite", "plain", "dark", "raw", "unsalted", "salted", "reduced", "low", "full", "whole", "brown", "white", "red", "green",
        "yellow", "dried", "frozen", "canned", "tinned", "natural", "greek", "baby", "free", "lean", "smoked", "toasted", "cooked", "boneless", "skinless",
    ]

    /// The phrase as something to look up, the way a photo's foods are: the name, then the name without size words.
    var seen: SeenFood {
        if brand == nil, let usual = Self.usualNames[name] {
            return SeenFood(name: usual, alternatives: [name] + alternatives, brand: nil, count: unit == nil || unit == .each ? max(1, Int((amount ?? 1).rounded())) : 1)
        }
        let words = name.split(separator: " ").map(String.init)
        let plain = words.filter { !Self.sizes.contains($0) }.joined(separator: " ")
        let count = unit == nil || unit == .each ? max(1, Int((amount ?? 1).rounded())) : 1
        // Last, the name without its first word: "light soy sauce" finds "Soy sauce". Only when what's left is still two
        // words or the first was just a description, so "baking soda" never becomes "soda".
        let rest = words.dropFirst()
        let shorter = words.count >= 2 && (rest.count >= 2 || Self.describing.contains(words[0])) ? rest.joined(separator: " ") : ""
        let others = ((plain != name && !plain.isEmpty ? [plain] : []) + alternatives + [shorter])
            .filter { !$0.isEmpty && $0 != name }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return SeenFood(name: name, alternatives: others, brand: brand, count: count)
    }

    /// The match to tick: the brand's item when one was named, an everyday food, or the only restaurant that has it
    /// ("big mac" is only at McDonald's). A "cheeseburger" from no particular place is left for the person to choose.
    static func preselected(from matches: [Food], for phrase: FoodPhrase, chainNames: [String: String]) -> Food? {
        if let food = MealPhoto.preselected(from: matches, for: phrase.seen, chainNames: chainNames) { return food }
        guard phrase.brand == nil, let first = matches.first, matches.allSatisfy({ $0.chain == first.chain }) else { return nil }
        return first
    }

    // MARK: Meals in words

    /// The foods in a sentence: "two eggs, toast with butter and a flat white". `known` says whether some words are one food
    /// ("fish and chips", "mac and cheese"), so those aren't split.
    static func meal(_ text: String, known: (String) -> Bool = { _ in false }) -> [FoodPhrase] {
        var cleaned = " " + text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "+", with: ",")
            .replacingOccurrences(of: ";", with: ",")
            .replacingOccurrences(of: "\n", with: ",")
            .replacingOccurrences(of: ".", with: ",") + " "
        // Numbers with a decimal point lost their point above; put it back ("1,5 kg" from "1.5 kg").
        cleaned = cleaned.replacingOccurrences(of: #"(\d),(\d)"#, with: "$1.$2", options: .regularExpression)
        for filler in [#"\bi(?:'ve| have)? (?:just )?(?:had|ate|eaten)\b"#, #"\bfor (?:breakfast|brekkie|lunch|dinner|tea|supper|a snack|snack|snacks|morning tea|afternoon tea|dessert)\b"#,
                       #"\b(?:today|tonight|this morning|this arvo|this afternoon|this evening|just now|earlier)\b"#, #"^\s*(?:had|ate)\b"#] {
            cleaned = cleaned.replacingOccurrences(of: filler, with: " ", options: .regularExpression)
        }
        var phrases: [FoodPhrase] = []
        for part in cleaned.split(separator: ",") {
            for piece in joinKnown(split(String(part)), known: known) {
                if let phrase = phrase(piece, recipe: false) { phrases.append(phrase) }
            }
        }
        // "A Big Mac and large fries from Maccas": the brand covers everything that names no other.
        if let brand = phrases.compactMap(\.brand).first {
            for index in phrases.indices where phrases[index].brand == nil { phrases[index].brand = brand }
        }
        return phrases
    }

    /// One food's words, not split on "and": "2 slices of raisin toast".
    static func food(_ text: String) -> FoodPhrase? { phrase(text.lowercased(), recipe: false) }

    private static let joiners = ["and", "with", "plus", "then", "n"]

    /// Splits on "and", "with" and "plus", keeping each joining word so known pairs can be put back.
    private static func split(_ text: String) -> [(text: String, joiner: String?)] {
        var pieces: [(String, String?)] = []
        var current: [String] = [], joiner: String?
        for word in text.split(separator: " ").map(String.init) {
            if joiners.contains(word), !current.isEmpty {
                pieces.append((current.joined(separator: " "), joiner)); current = []; joiner = word
            } else { current.append(word) }
        }
        if !current.isEmpty { pieces.append((current.joined(separator: " "), joiner)) }
        return pieces
    }

    /// Puts back pairs that name one food, like "fish and chips".
    private static func joinKnown(_ pieces: [(text: String, joiner: String?)], known: (String) -> Bool) -> [String] {
        var result: [String] = []
        var index = 0
        while index < pieces.count {
            var text = pieces[index].text
            while index + 1 < pieces.count, let joiner = pieces[index + 1].joiner {
                let joined = text + " " + (joiner == "n" ? "and" : joiner) + " " + pieces[index + 1].text
                guard known(bare(joined)) else { break }
                text = joined; index += 1
            }
            result.append(text); index += 1
        }
        return result
    }

    /// The words without amounts or brand, as `known` sees them.
    private static func bare(_ text: String) -> String {
        phrase(text, recipe: false)?.name ?? text
    }

    // MARK: Recipe ingredients

    /// One ingredient line from a recipe. Nil for lines that aren't a food ("Salt and pepper, to taste" still is; an empty
    /// line or a heading isn't).
    static func ingredient(_ line: String) -> FoodPhrase? {
        var text = line.lowercased().replacingOccurrences(of: "’", with: "'")
        // A weight in brackets is more exact than cups or a count: "1 cup (150 g) flour", "2 x 400g cans tomatoes".
        var bracketGrams: (Double, Unit)?
        if let match = text.firstMatch(of: /\((?:about |approx\.? )?(\d+(?:\.\d+)?)\s*(g|kg|ml|l)\b[^)]*\)/) {
            let value = Double(match.1) ?? 0, unit = String(match.2)
            bracketGrams = (value * (unit == "kg" || unit == "l" ? 1000 : 1), unit == "g" || unit == "kg" ? .gram : .millilitre)
        }
        text = text.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        // Preparation notes come after a comma or a dash: "onion, finely chopped".
        if let cut = text.firstIndex(where: { $0 == "," || $0 == "—" }) { text = String(text[..<cut]) }
        text = text.replacingOccurrences(of: #"(?<!\d)\s?–\s?(?!\d).*$"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?<!\d)\s-\s(?!\d).*$"#, with: "", options: .regularExpression)
        guard var phrase = phrase(text, recipe: true) else { return nil }
        phrase.original = line.trimmingCharacters(in: .whitespacesAndNewlines)
        // "cornflour / corn starch", "butter or margarine": the first is the name, the rest are other names for it.
        let names = phrase.name.components(separatedBy: "/").flatMap { $0.components(separatedBy: " or ") }
            .map { $0.trimmingCharacters(in: CharacterSet.alphanumerics.inverted) }.filter { $0.contains(where: \.isLetter) }
        if names.count > 1 { phrase.name = names[0]; phrase.alternatives = Array(names.dropFirst()) }
        if let (grams, unit) = bracketGrams, phrase.unit != .gram && phrase.unit != .millilitre {
            phrase.amount = grams * (phrase.unit == .each || phrase.unit == nil ? (phrase.amount ?? 1) : 1)
            phrase.unit = unit
        }
        return phrase
    }

    /// Words a recipe uses for how something's prepared, which a food list doesn't.
    private static let preparation: Set<String> = [
        "chopped", "diced", "sliced", "minced", "grated", "shredded", "crushed", "peeled", "trimmed", "halved", "quartered",
        "finely", "roughly", "thinly", "coarsely", "freshly", "fresh", "packed", "heaped", "level", "softened", "melted",
        "beaten", "lightly", "sifted", "drained", "rinsed", "cubed", "torn", "picked", "deseeded", "seeded", "large", "medium", "small",
        "extra", "good", "quality", "organic", "plus", "optional", "about", "approximately", "approx",
    ]

    // MARK: Parsing one food

    private static let numbers: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "half": 0.5, "quarter": 0.25, "couple": 2, "few": 3, "dozen": 12,
    ]
    private static let fractions: [Character: Double] = ["½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "⅛": 0.125]
    private static let units: [String: (Unit, Double)] = [
        "g": (.gram, 1), "gram": (.gram, 1), "grams": (.gram, 1), "gm": (.gram, 1), "kg": (.gram, 1000), "kgs": (.gram, 1000), "kilo": (.gram, 1000), "kilos": (.gram, 1000),
        "oz": (.gram, 28.35), "ounce": (.gram, 28.35), "ounces": (.gram, 28.35), "lb": (.gram, 453.6), "lbs": (.gram, 453.6), "pound": (.gram, 453.6), "pounds": (.gram, 453.6),
        "ml": (.millilitre, 1), "mls": (.millilitre, 1), "millilitre": (.millilitre, 1), "millilitres": (.millilitre, 1), "milliliter": (.millilitre, 1), "milliliters": (.millilitre, 1),
        "l": (.millilitre, 1000), "litre": (.millilitre, 1000), "litres": (.millilitre, 1000), "liter": (.millilitre, 1000), "liters": (.millilitre, 1000),
        "cup": (.cup, 1), "cups": (.cup, 1), "tbsp": (.tablespoon, 1), "tbs": (.tablespoon, 1), "tablespoon": (.tablespoon, 1), "tablespoons": (.tablespoon, 1),
        "tsp": (.teaspoon, 1), "teaspoon": (.teaspoon, 1), "teaspoons": (.teaspoon, 1),
        "slice": (.each, 1), "slices": (.each, 1), "piece": (.each, 1), "pieces": (.each, 1), "serve": (.each, 1), "serves": (.each, 1),
        "serving": (.each, 1), "servings": (.each, 1), "portion": (.each, 1), "portions": (.each, 1), "can": (.each, 1), "cans": (.each, 1),
        "tin": (.each, 1), "tins": (.each, 1), "bottle": (.each, 1), "bottles": (.each, 1), "glass": (.each, 1), "glasses": (.each, 1),
        "bowl": (.each, 1), "bowls": (.each, 1), "plate": (.each, 1), "plates": (.each, 1), "handful": (.each, 1), "handfuls": (.each, 1),
        "scoop": (.each, 1), "scoops": (.each, 1), "packet": (.each, 1), "packets": (.each, 1), "bar": (.each, 1), "bars": (.each, 1),
        "clove": (.each, 1), "cloves": (.each, 1), "stem": (.each, 1), "stems": (.each, 1), "bunch": (.each, 1), "bunches": (.each, 1),
        "head": (.each, 1), "heads": (.each, 1), "leaf": (.each, 1), "leaves": (.each, 1), "stalk": (.each, 1), "stalks": (.each, 1), "pinch": (.each, 1), "dash": (.each, 1), "sprig": (.each, 1), "sprigs": (.each, 1),
    ]
    private static let fillers: Set<String> = ["of", "the", "some", "my", "x", "×", "bit", "little", "lot", "lots", "about", "around", "like", "maybe", "approx"]

    /// Words, with numbers parted from units ("200g" to "200 g", "x2" to "x 2").
    private static func words(_ text: String) -> [String] {
        var spaced = ""
        var previous: Character?
        for character in text {
            if let previous, (previous.isNumber && character.isLetter) || (previous.isLetter && character.isNumber) || fractions[character] != nil {
                spaced.append(" ")
            }
            spaced.append(character); previous = character
        }
        return spaced.split { $0 == " " || $0 == "\t" }.map(String.init)
    }

    /// Takes a quantity off the front of the words: "2", "1.5", "1 1/2", "½", "two", "a couple of", "half a".
    private static func quantity(_ tokens: inout [String]) -> Double? {
        var total: Double?
        while let first = tokens.first {
            if let value = Double(first) {
                total = (total ?? 0) + value; tokens.removeFirst()
                // "2 to 3", "2 or 3": take the first.
                if tokens.count > 1, ["to", "or", "-", "–"].contains(tokens[0]), Double(tokens[1]) != nil { tokens.removeFirst(2) }
            } else if let range = first.firstMatch(of: /^(\d+(?:\.\d+)?)[-–](\d+(?:\.\d+)?)$/), let value = Double(range.1) {
                // "2-3": take the first.
                total = (total ?? 0) + value; tokens.removeFirst()
            } else if first.contains("/"), let fraction = fraction(first) {
                total = (total ?? 0) + fraction; tokens.removeFirst()
            } else if first.count == 1, let character = first.first, let value = fractions[character] {
                total = (total ?? 0) + value; tokens.removeFirst()
            } else if total == nil, let value = numbers[first] {
                tokens.removeFirst()
                // "half a sandwich", "a couple of eggs", "a dozen eggs", "a half".
                if value == 0.5 || value == 0.25, ["a", "an"].contains(tokens.first) { tokens.removeFirst() }
                if (first == "a" || first == "an"), let next = tokens.first, let nextValue = numbers[next], !["a", "an"].contains(next) {
                    tokens.removeFirst(); total = nextValue
                } else { total = value }
                return total
            } else { break }
        }
        return total
    }

    private static func fraction(_ text: String) -> Double? {
        let parts = text.split(separator: "/")
        guard parts.count == 2, let top = Double(parts[0]), let bottom = Double(parts[1]), bottom > 0 else { return nil }
        return top / bottom
    }

    /// One food's words to a phrase. Nil when nothing's left to search for.
    private static func phrase(_ text: String, recipe: Bool) -> FoodPhrase? {
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var working = " " + original + " "
        var brand: String?
        if let match = working.firstMatch(of: /\s(?:from|at)\s+(.+?)\s*$/) {
            brand = String(match.1).trimmingCharacters(in: .whitespaces); working = String(working[..<match.range.lowerBound])
        }
        var tokens = words(working)
        // "Maccas cheeseburger", "a KFC zinger": a known nickname at the start is the brand.
        if brand == nil {
            for skip in [0, 1] where tokens.count > skip + 1 {
                if skip == 1, !["a", "an", "some", "the", "my"].contains(tokens[0]), Double(tokens[0]) == nil, numbers[tokens[0]] == nil { continue }
                for length in [3, 2, 1] where tokens.count > skip + length {
                    let candidate = tokens[skip..<(skip + length)].joined(separator: " ")
                    if MealPhoto.brandAliases[candidate.filter { $0.isLetter || $0 == " " }] != nil {
                        brand = candidate; tokens.removeSubrange(skip..<(skip + length)); break
                    }
                }
                if brand != nil { break }
            }
        }
        var amount = quantity(&tokens)
        var unit: Unit?
        func takeUnit() {
            guard let first = tokens.first?.trimmingCharacters(in: CharacterSet(charactersIn: ".")), let (found, scale) = units[first] else { return }
            // "a can of coke" counts; "glass" in "glass noodles" with nothing before it doesn't.
            guard amount != nil || tokens.count > 1 && ["of"].contains(tokens[1]) else { return }
            tokens.removeFirst(); unit = found; amount = (amount ?? 1) * scale
        }
        takeUnit()
        // "1 x 400 g can of tomatoes": a count, then a size.
        if (tokens.first == "x" || tokens.first == "×"), tokens.count > 1, Double(tokens[1]) != nil {
            tokens.removeFirst()
            let count = amount ?? 1
            amount = quantity(&tokens); unit = nil; takeUnit()
            amount = (amount ?? 1) * count
            if unit == nil { unit = .each }
            if let next = tokens.first, units[next]?.0 == .each { tokens.removeFirst() }
        }
        while let first = tokens.first, fillers.contains(first) || (recipe && preparation.contains(first)) { tokens.removeFirst() }
        // A count after the name: "eggs x2", "coffee × 2".
        if amount == nil, tokens.count >= 2, ["x", "×"].contains(tokens[tokens.count - 2]), let value = Double(tokens[tokens.count - 1]) {
            amount = value; tokens.removeLast(2)
        } else if amount == nil, let last = tokens.last, last.hasPrefix("x"), let value = Double(last.dropFirst()) {
            amount = value; tokens.removeLast()
        }
        if recipe {
            tokens = tokens.filter { !preparation.contains($0) }
            for ending in [["to", "taste"], ["to", "serve"], ["for", "serving"], ["for", "garnish"], ["to", "garnish"], ["if", "needed"]] {
                if let start = tokens.indices.first(where: { tokens[$0...].starts(with: ending) }) { tokens.removeSubrange(start...) }
            }
        }
        let name = tokens.filter { !fillers.contains($0) || tokens.count == 1 }.joined(separator: " ").trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard name.contains(where: \.isLetter) else { return nil }
        return FoodPhrase(name: name, amount: amount, unit: unit, brand: brand, original: original)
    }
}
