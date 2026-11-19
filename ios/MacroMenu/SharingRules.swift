import Foundation

/// What a food needs before it can be shared. Checked when saving and again on every food read back,
/// so a record written some other way still has to pass.
nonisolated enum SharingRules {
    /// Several people reporting a food hides it for everyone until it's looked at.
    static let reportsToHide = 3

    /// The foods enough different people have reported to hide them for everyone. One person reporting twice counts once.
    static func hiddenByReports(_ reports: [(recordName: String, reporter: String)]) -> Set<String> {
        var reporters: [String: Set<String>] = [:]
        for report in reports { reporters[report.recordName, default: []].insert(report.reporter) }
        return Set(reporters.filter { $0.value.count >= reportsToHide }.keys)
    }

    /// The most one serving could plausibly have of each extra nutrient: grams for the fats, sugars and fibre, milligrams for the rest.
    static let nutrientLimits: [String: Double] = ["sat": 300, "trans": 100, "sugar": 500, "fibre": 200, "sodium": 20_000, "potassium": 10_000,
                                                   "calcium": 5_000, "iron": 200, "chol": 5_000, "caffeine": 1_000]
    /// The longest `nut` text a shared record may carry; ten nutrients take about 200 characters.
    static let longestNutrientText = 1_000

    /// Only the nutrients Leanr knows, so a shared food can't carry anything else along.
    static func knownNutrients(_ nut: [String: Double]?) -> [String: Double]? {
        guard let kept = nut?.filter({ nutrientLimits[$0.key] != nil }), !kept.isEmpty else { return nil }
        return kept
    }

    /// Why this food can't be shared, or nil when it can.
    static func problem(_ food: Food) -> String? {
        let name = food.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let serve = food.serve.trimmingCharacters(in: .whitespacesAndNewlines)
        if food.ingredients != nil || food.modifiers != nil { return "Recipes and custom orders can't be shared." }
        if name.count < 3 { return "Give it a name of at least 3 letters." }
        if name.count > 80 { return "Shorten the name to 80 characters or fewer." }
        if serve.isEmpty || serve.count > 40 { return "Add a serving size, like 150 g or 1 bar." }
        if !ContentFilter.isAcceptable(name + " " + serve) { return "Take out the strong language before sharing." }
        if ContentFilter.hasContactDetails(name + " " + serve) { return "Leave links and contact details out of the name and serving." }
        guard food.isValid, food.cal > 0 else { return "Add the energy first." }
        guard let c = food.c, let f = food.f else { return "Add carbs and fat too, so others can see the numbers add up." }
        if food.cal > 3000 || food.p > 250 || c > 500 || f > 300 || (food.nut ?? [:]).contains(where: { $0.value > (nutrientLimits[$0.key] ?? .infinity) }) {
            return "These numbers are more than one serving would have. Check them, or enter one serving."
        }
        if let barcode = food.barcode, !(6...14).contains(barcode.count) || !barcode.utf8.allSatisfy({ (48...57).contains($0) }) {
            return "The barcode should be 6 to 14 digits."
        }
        if food.cat.isEmpty || food.cat.count > 20 || !food.cat.utf8.allSatisfy({ (97...122).contains($0) }) { return "This kind of food can't be shared." }
        if let (weight, _) = food.servingWeight, food.p + c + f > weight * 1.02 {
            return "Protein, carbs and fat add up to more than the serving weighs. Check the label."
        }
        let fromMacros = food.p * 4 + c * 4 + f * 9
        let allowed = max(25, food.cal * 0.15)
        // Alcohol has energy that isn't a macro, so drinks with it may list more energy than their macros explain.
        if fromMacros - food.cal > allowed || (food.cal - fromMacros > allowed && !mentionsAlcohol(name)) {
            return "The energy doesn't match the protein, carbs and fat (\(fromMacros.rounded().number) Cal from them, \(food.cal.rounded().number) Cal entered). Check the label."
        }
        return nil
    }

    static func mentionsAlcohol(_ name: String) -> Bool {
        let words = Set(FoodSearch.tokens(name))
        return !words.isDisjoint(with: ["beer", "lager", "ale", "cider", "wine", "vodka", "gin", "rum", "whisky", "whiskey", "tequila", "seltzer", "spritz", "prosecco", "champagne", "cocktail", "sake", "soju", "bourbon", "liqueur"])
    }
}

/// Keeps strong language and abuse out of the foods and meals people name, and out of shared foods.
/// Whole words only, so "Scunthorpe" or "cocktail" pass, but disguised spellings like "sh1t", "f*ck", "f u c k" and "fuuuck" are caught.
nonisolated enum ContentFilter {
    private static let words: Set<String> = [
        "fuck", "fucks", "fucked", "fucking", "fucker", "fuckers", "motherfucker", "fuk", "fuks", "fukin", "fuking", "fuq", "fck", "fcking", "fking", "fkn",
        "phuck", "phuk", "cunt", "cunts", "shit", "shits", "shitty", "shite", "bullshit", "shyt",
        "bitch", "bitches", "biatch", "bastard", "bastards", "wanker", "wankers", "twat", "twats", "dickhead", "dickheads", "arsehole", "arseholes", "asshole", "assholes",
        "cock", "cocks", "dick", "dicks", "pussy", "slut", "sluts", "whore", "whores", "porn", "cum", "jizz", "dildo", "blowjob", "handjob",
        "nazi", "nazis", "hitler", "rape", "raped", "rapist",
        "nigger", "niggers", "nigga", "niggas", "faggot", "faggots", "fag", "fags", "retard", "retards", "retarded", "spastic", "tranny",
        "kike", "chink", "coon", "paki", "abo", "abos", "gook", "spic", "wetback", "raghead", "towelhead",
        "kys", "killyourself",
    ]
    /// Caught even inside another word, because no food name contains them.
    private static let roots = ["fuck", "nigger", "nigga", "faggot"]
    /// Real foods that would otherwise trip a word above.
    private static let allowedPhrases = ["spotted dick", "dick smith", "cock a leekie", "cockaleekie", "coon cheese", "rape seed oil", "faggots and peas", "faggots in gravy"]
    /// Symbols and digits standing in for letters, as in "sh1t" or "$hit".
    private static let lookalikes: [Character: Character] = ["0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s", "!": "i", "|": "i"]

    static func isAcceptable(_ text: String) -> Bool {
        var tokens = pieces(text)
        let padded = " " + tokens.joined(separator: " ") + " "
        if let allowed = allowedPhrases.first(where: { padded.contains(" \($0) ") }) {
            return isAcceptable(padded.replacingOccurrences(of: " \(allowed) ", with: " "))
        }
        tokens = tokens.map(unmasked)
        // Spaced-out letters ("f u c k") and words split in two or three ("fu ck", "kill your self").
        var joined = tokens.indices.dropLast().map { tokens[$0] + tokens[$0 + 1] }
            + tokens.indices.dropLast(2).map { tokens[$0] + tokens[$0 + 1] + tokens[$0 + 2] }
        var run: [String] = []
        for token in tokens + [""] {
            if token.count == 1 { run.append(token); continue }
            if run.count >= 3 { joined.append(run.joined()) }
            run = []
        }
        return (tokens + joined).allSatisfy { token in
            !variants(token).contains { word in words.contains(word) || roots.contains { word.contains($0) } || matchesMasked(word) }
        }
    }

    /// Whether any of these is unacceptable.
    static func flags(_ texts: [String]) -> Bool { !texts.allSatisfy(isAcceptable) }
    static let flagMessage = "Take out the offensive language to save this."

    /// Lowercased words, keeping the symbols people swap in for letters.
    private static func pieces(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
            .replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
            .split { !$0.isLetter && !$0.isNumber && !"*@$!|".contains($0) }
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "!|*")) }
            .filter { !$0.isEmpty }
    }

    /// "sh1t" as "shit". Plain numbers like "100" or "7" are left alone.
    private static func unmasked(_ token: String) -> String {
        guard token.contains(where: \.isLetter) else { return token }
        return String(token.map { lookalikes[$0] ?? $0 })
    }

    /// The word with long runs of one letter shortened, so "fuuuck" and "shiiit" are checked as well.
    private static func variants(_ token: String) -> [String] {
        var single = "", double = ""
        var last: Character?, count = 0
        for char in token {
            count = char == last ? count + 1 : 1
            last = char
            if count == 1 { single.append(char) }
            if count <= 2 { double.append(char) }
        }
        return [token, single, double]
    }

    /// "f*ck" or "c**t": each star stands for one letter of a listed word.
    private static func matchesMasked(_ token: String) -> Bool {
        guard token.contains("*"), token.contains(where: \.isLetter) else { return false }
        let chars = Array(token)
        return words.contains { word in
            word.count == chars.count && zip(word, chars).allSatisfy { $0 == $1 || $1 == "*" }
        }
    }

    static func hasContactDetails(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("http") || lower.contains("www.") || lower.contains("@") { return true }
        if [".com", ".net", ".org", ".io", ".au", ".ly"].contains(where: { lower.contains($0) }) { return true }
        // Eight or more digits in a row looks like a phone number.
        return text.filter(\.isNumber).count >= 8 && text.split { !$0.isNumber && $0 != " " }.contains { $0.filter(\.isNumber).count >= 8 }
    }
}

/// The shared record for one of your foods: "food-" and its ID, kept to the characters CloudKit allows.
nonisolated func sharedRecordName(for foodID: String) -> String {
    let safe = foodID.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }
    return "food-" + String(String(String.UnicodeScalarView(safe)).prefix(200))
}

/// Whether a record name is one this app writes: "food-" and up to 200 letters, digits, hyphens or underscores.
/// Anyone can write a record under any name, so other shapes are ignored when read back.
nonisolated func isSharedRecordName(_ name: String) -> Bool {
    guard name.hasPrefix("food-") else { return false }
    let rest = name.dropFirst(5).unicodeScalars
    return (1...200).contains(rest.count) && rest.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }
}

/// One report per person per food. The reporter comes first so a long food name can never push it off the end.
nonisolated func reportRecordName(food recordName: String, reporter: String) -> String {
    let plain = "report-\(recordName)-\(reporter)"
    if plain.count <= 255 { return plain }
    return String("report-\(String(reporter.prefix(100)))-\(recordName)".prefix(255))
}
