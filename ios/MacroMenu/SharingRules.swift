import Foundation

/// What a food needs before it can be shared. Checked when saving and again on every food read back,
/// so a record written some other way still has to pass.
nonisolated enum SharingRules {
    /// Several people reporting a food hides it for everyone until it's looked at.
    static let reportsToHide = 3

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
        if food.cal > 3000 || food.p > 250 || c > 500 || f > 300 {
            return "These numbers are more than one serving would have. Check them, or enter one serving."
        }
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

/// Keeps strong language and abuse out of shared food names. Whole words only, so "Scunthorpe" or "cocktail" pass.
nonisolated enum ContentFilter {
    private static let words: Set<String> = [
        "fuck", "fucks", "fucked", "fucking", "fucker", "fuckers", "motherfucker", "cunt", "cunts", "shit", "shits", "shitty", "bullshit",
        "bitch", "bitches", "bastard", "bastards", "wanker", "wankers", "twat", "twats", "dickhead", "dickheads", "arsehole", "asshole",
        "cock", "cocks", "dick", "dicks", "pussy", "slut", "sluts", "whore", "whores", "porn", "nazi", "nazis", "rape", "rapist",
        "nigger", "niggers", "nigga", "niggas", "faggot", "faggots", "fag", "fags", "retard", "retards", "retarded", "spastic", "tranny", "kike", "chink", "coon", "paki", "abo", "abos", "gook",
        "kys",
    ]
    static func isAcceptable(_ text: String) -> Bool {
        let tokens = FoodSearch.tokens(text)
        // Also catch "f u c k" and "fu.ck" style spacing by joining short neighbouring pieces.
        let joined = tokens.indices.dropLast().map { tokens[$0] + tokens[$0 + 1] }
        return (tokens + joined).allSatisfy { !words.contains($0) }
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
