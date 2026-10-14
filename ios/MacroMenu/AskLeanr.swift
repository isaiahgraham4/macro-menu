import Foundation

/// Ask Leanr: a question in plain words ("40 g protein under 600 Cal at Nando's") turned into an order search.
/// These rules read the numbers, restaurants and dietary needs; on phones with Apple Intelligence it fills in what they miss
/// (see `AskLeanrModel`). Nothing here makes up nutrition: the answers are the order finder's, from the menus.
enum AskLeanr {
    struct Request: Equatable, Sendable {
        var query: FindQuery
        /// Words for what was understood, shown above the answers so a misreading is easy to spot.
        var understood: [String]
        /// "What's left today" was asked for: the calories and protein come from today's targets.
        var usesRemaining = false
        /// What was read from the words rather than left at its default.
        var said: Set<Field> = []
    }
    enum Field: Hashable, Sendable { case calories, protein, carbs, fat, items, chains, sort, diet }

    /// The question as an order search. `defaults` gives the calories and protein when the question doesn't.
    static func parse(_ text: String, chainNames: [String: String], defaults: FindQuery) -> Request {
        var query = defaults
        query.chains = []
        query.diet = defaults.diet
        var said = Set<Field>()
        let lower = " " + text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "-", with: " ") + " "

        // Numbers with what they measure: "40 g protein", "protein of 40", "600 cal", "2500 kJ", "under 30 g carbs".
        let number = #"(\d+(?:\.\d+)?)"#
        func value(_ patterns: [String]) -> Double? {
            for pattern in patterns {
                if let match = lower.range(of: pattern, options: .regularExpression) {
                    let found = String(lower[match])
                    if let n = found.range(of: number, options: .regularExpression).flatMap({ Double(found[$0]) }) { return n }
                }
            }
            return nil
        }
        if let protein = value([number + #"\s*(g|grams?)?\s*(of\s+)?protein"#, #"protein\s*(of|at least|over|above|>)?\s*"# + number]) {
            query.protein = protein; said.insert(.protein)
        } else if lower.contains("high protein") || lower.contains("most protein") || lower.contains("lots of protein") {
            query.sort = "protein"; said.insert(.sort)
        }
        if let kj = value([number + #"\s*kj\b"#]) {
            query.calories = (kj / 4.184).rounded(); said.insert(.calories)
        } else if let calories = value([number + #"\s*(k?cals?|calories|kcal)\b"#]) {
            query.calories = calories; said.insert(.calories)
        } else if let bare = value([#"\b(under|below|less than|up to|max|maximum|no more than)\s+"# + number + #"(?!\s*(g|grams?)\b)"#]), bare >= 100 {
            // "under 600" with no unit is calories; grams come with a "g".
            query.calories = bare; said.insert(.calories)
        }
        if let carbs = value([number + #"\s*(g|grams?)?\s*(of\s+)?carbs?"#, #"carbs?\s*(under|below|less than|up to)?\s*"# + number]) {
            query.carbs = carbs; said.insert(.carbs)
        } else if lower.contains("low carb") || lower.contains("keto") {
            query.carbs = 30; said.insert(.carbs)
        }
        if let fat = value([number + #"\s*(g|grams?)?\s*(of\s+)?fat\b"#, #"\bfat\s*(under|below|less than|up to)?\s*"# + number]) {
            query.fat = fat; said.insert(.fat)
        } else if lower.contains("low fat") {
            query.fat = 15; said.insert(.fat)
        }
        if lower.contains("lightest") || lower.contains("lowest cal") || lower.contains("fewest cal") {
            query.sort = "lean"; said.insert(.sort)
        }

        // How many items.
        let words = ["one": 1, "1": 1, "single": 1, "two": 2, "2": 2, "three": 3, "3": 3]
        for (word, count) in words {
            if lower.range(of: #"\b"# + word + #"\s+items?\b"#, options: .regularExpression) != nil { query.maxItems = count; said.insert(.items) }
        }
        if lower.contains("just one thing") || lower.contains("one thing") || lower.contains("single item") { query.maxItems = 1; said.insert(.items) }
        if lower.contains("with a side") || lower.contains("and a side") || lower.contains("with sides") { query.maxItems = max(query.maxItems, 2); said.insert(.items) }

        // Restaurants: the menu's own names and the names people say.
        for (id, name) in chainNames where id != "mine" && id != Food.everyday {
            let plain = name.lowercased().replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "-", with: " ")
            let variants = [plain, plain.replacingOccurrences(of: "'", with: ""), plain.replacingOccurrences(of: " ", with: "")]
            if variants.contains(where: { lower.contains(" \($0)") || lower.contains(" \($0)'s") }) { query.chains.insert(id) }
        }
        for (nickname, id) in Assistant.nicknames where chainNames[id] != nil {
            if lower.range(of: #"\b"# + NSRegularExpression.escapedPattern(for: nickname) + #"\b"#, options: .regularExpression) != nil { query.chains.insert(id) }
        }
        if !query.chains.isEmpty { said.insert(.chains) }

        // Dietary needs, added to any already set.
        let needs: [(String, [DietOption])] = [
            (#"\bvegan\b|plant based"#, [.vegan]), (#"vegetarian|\bveggie\b|meat free|no meat|without meat|meatless"#, [.vegetarian]),
            (#"no beef|without beef|beef free|don't eat beef"#, [.noBeef]), (#"no pork|without pork|pork free|don't eat pork|halal"#, [.noPork]),
            (#"gluten|coeliac|celiac"#, [.gluten]), (#"dairy|lactose|no milk|milk free|milk allergy"#, [.milk]),
            (#"no eggs?\b|egg free|eggs? allergy"#, [.egg]), (#"\bnut free|no nuts|nut allergy|tree nut"#, [.peanut, .treenut]),
            (#"peanut"#, [.peanut]), (#"\bsoy\b|soya"#, [.soy]), (#"sesame"#, [.sesame]),
            (#"no fish|fish allergy|fish free"#, [.fish]), (#"shellfish|crustacean|no seafood|seafood allergy"#, [.shellfish]),
        ]
        for (pattern, options) in needs where lower.range(of: pattern, options: .regularExpression) != nil {
            query.diet.options.formUnion(options); said.insert(.diet)
        }

        let remaining = lower.contains("left today") || lower.contains("what's left") || lower.contains("whats left")
            || lower.contains("remaining") || lower.contains("rest of my day") || lower.contains("rest of today")
        var request = Request(query: query, understood: [], usesRemaining: remaining && !said.contains(.calories), said: said)
        request.understood = summary(request, chainNames: chainNames)
        // Leanr knows what's in an item, not how it was prepared or certified.
        if lower.contains("halal") { request.understood.append("Halal isn't checked, only no pork") }
        return request
    }

    /// "Up to 600 Cal", "40 g protein", "Nando's", "Vegetarian"…
    static func summary(_ request: Request, chainNames: [String: String]) -> [String] {
        let q = request.query
        var parts: [String] = []
        parts.append(request.usesRemaining ? "What's left today" : "Up to \(q.calories.rounded().number) Cal")
        if q.sort == "protein" && !request.said.contains(.protein) { parts.append("Most protein") } else { parts.append("\(q.protein.rounded().number) g protein") }
        if q.sort == "lean" { parts.append("Lowest calories") }
        if let carbs = q.carbs { parts.append("Carbs up to \(carbs.number) g") }
        if let fat = q.fat { parts.append("Fat up to \(fat.number) g") }
        if request.said.contains(.items) { parts.append(q.maxItems == 1 ? "One item" : "Up to \(q.maxItems) items") }
        parts += q.chains.compactMap { chainNames[$0] }.sorted()
        if !q.diet.isEmpty { parts.append(q.diet.summary) }
        return parts
    }
}
