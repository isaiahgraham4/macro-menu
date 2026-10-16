import Foundation

/// A recipe read from a web page. Most recipe sites describe the recipe for search engines in a schema.org block, which
/// lists the name, how many it serves, the ingredients and often nutrition per serving. Only that block is read.
struct ImportedRecipe: Equatable, Sendable {
    var name: String
    var servings: Double?
    var ingredients: [String]
    /// Per serving, when the page lists it: "cal", "p", "c", "f", and others under Leanr's nutrient keys.
    var nutrition: [String: Double]
    var source: URL?
    var host: String? { source?.host()?.replacingOccurrences(of: "www.", with: "") }

    /// The page's own figures as a food, when it lists at least calories and protein.
    var food: Food? {
        guard let cal = nutrition["cal"], let p = nutrition["p"], cal > 0 else { return nil }
        let nut = nutrition.filter { !["cal", "p", "c", "f"].contains($0.key) }.mapValues(\.tenth)
        return Food(name: name, kj: (cal * 4.184).rounded(), cal: cal.rounded(), p: p.tenth, c: nutrition["c"]?.tenth, f: nutrition["f"]?.tenth,
                    serve: "1 serving", nut: nut.isEmpty ? nil : nut, note: host.map { "From \($0)" })
    }
}

enum RecipeImport {
    enum Failure: Error, Equatable {
        case notALink, couldNotLoad, noRecipe
        var message: String {
            switch self {
            case .notALink: "That isn't a web link. Copy the recipe page's address from Safari and paste it here."
            case .couldNotLoad: "The page couldn't be loaded. Check you're online and the link opens in Safari."
            case .noRecipe: "No recipe was found on that page. Leanr reads the recipe details most recipe sites include, and this page doesn't have them."
            }
        }
    }

    /// A web address from pasted text: the first http or https link in it, or else the first bare address ("taste.com.au/...").
    static func link(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A real link wins over something earlier that only looks like an address, like "recipe." ending a sentence.
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
                guard let range = Range(match.range, in: trimmed), trimmed[range].lowercased().hasPrefix("http"),
                      let url = match.url.flatMap({ secure($0.absoluteString) }) else { continue }
                return url
            }
        }
        let candidates = [trimmed] + trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        for candidate in candidates {
            var value = candidate
            if !value.lowercased().hasPrefix("http"), value.contains("."), !value.contains(" ") { value = "https://" + value }
            if let url = secure(value) { return url }
        }
        return nil
    }

    /// The address over HTTPS, if it has a real host ("recipe." isn't one).
    private static func secure(_ address: String) -> URL? {
        var value = address
        // Leanr only connects over HTTPS, and nearly every recipe site has it.
        if value.lowercased().hasPrefix("http://") { value = "https://" + value.dropFirst(7) }
        guard let url = URL(string: value), url.scheme?.lowercased() == "https", let host = url.host(), host.contains("."), !host.hasSuffix(".") else { return nil }
        return url
    }

    static let largestPage = 5_000_000

    /// Loads the page straight from the site and reads its recipe.
    static func load(_ url: URL, session: URLSession = .shared) async throws -> ImportedRecipe {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) } catch { throw Failure.couldNotLoad }
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true, data.count <= largestPage else { throw Failure.couldNotLoad }
        let html = String(decoding: data, as: UTF8.self)
        guard var recipe = recipes(inHTML: html).first else { throw Failure.noRecipe }
        recipe.source = (response.url ?? url)
        return recipe
    }

    /// Every schema.org Recipe in the page's JSON-LD blocks.
    static func recipes(inHTML html: String) -> [ImportedRecipe] {
        var found: [ImportedRecipe] = []
        for match in html.matches(of: /(?is)<script[^>]*type\s*=\s*["']?application\/ld\+json["']?[^>]*>(.*?)<\/script>/) {
            let body = String(match.1).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = body.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { continue }
            for object in recipeObjects(json) { if let recipe = recipe(object) { found.append(recipe) } }
        }
        return found
    }

    private static func recipeObjects(_ json: Any) -> [[String: Any]] {
        if let array = json as? [Any] { return array.flatMap(recipeObjects) }
        guard let object = json as? [String: Any] else { return [] }
        var result: [[String: Any]] = []
        let types: [String] = (object["@type"] as? String).map { [$0] } ?? (object["@type"] as? [String]) ?? []
        if types.contains(where: { $0.caseInsensitiveCompare("Recipe") == .orderedSame }) { result.append(object) }
        for key in ["@graph", "mainEntity", "mainEntityOfPage", "itemListElement", "item"] { if let nested = object[key] { result += recipeObjects(nested) } }
        return result
    }

    private static func recipe(_ object: [String: Any]) -> ImportedRecipe? {
        let name = clean(object["name"] as? String ?? object["headline"] as? String ?? "")
        let lines = ((object["recipeIngredient"] ?? object["ingredients"]) as? [Any] ?? []).compactMap { $0 as? String }.map(clean).filter { !$0.isEmpty }
        guard !name.isEmpty, !lines.isEmpty || object["nutrition"] != nil else { return nil }
        var nutrition: [String: Double] = [:]
        if let facts = object["nutrition"] as? [String: Any] {
            for (key, field) in [("cal", "calories"), ("p", "proteinContent"), ("c", "carbohydrateContent"), ("f", "fatContent"),
                                 ("sat", "saturatedFatContent"), ("trans", "transFatContent"), ("sugar", "sugarContent"), ("fibre", "fiberContent"),
                                 ("sodium", "sodiumContent"), ("chol", "cholesterolContent")] {
                guard let value = amount(facts[field], key: key) else { continue }
                nutrition[key] = value
            }
        }
        return ImportedRecipe(name: name, servings: servings(object["recipeYield"] ?? object["yield"]), ingredients: lines, nutrition: nutrition)
    }

    /// "4", "4 servings", "Serves 6", ["4", "4 servings"], or a number.
    static func servings(_ value: Any?) -> Double? {
        if let number = value as? Double { return number > 0 ? number : nil }
        if let number = value as? Int { return number > 0 ? Double(number) : nil }
        if let array = value as? [Any] { return array.lazy.compactMap(servings).first }
        guard let text = value as? String, let match = text.firstMatch(of: /(\d+(?:\.\d+)?)/), let number = Double(match.1), number > 0, number <= 100 else { return nil }
        return number
    }

    /// A nutrient figure in Leanr's units: Cal for energy (kJ converted), grams, and milligrams for sodium and cholesterol.
    static func amount(_ value: Any?, key: String) -> Double? {
        var number: Double?, unit = ""
        if let value = value as? Double { number = value }
        else if let value = value as? Int { number = Double(value) }
        else if let text = value as? String, let match = text.replacingOccurrences(of: ",", with: "").firstMatch(of: /(\d+(?:\.\d+)?)\s*([a-zA-Zµ]*)/) {
            number = Double(match.1); unit = String(match.2).lowercased()
        }
        guard var result = number, result.isFinite, result >= 0 else { return nil }
        switch key {
        case "cal": if unit == "kj" { result /= 4.184 }
        case "sodium", "chol": if unit == "g" { result *= 1000 } else if unit == "µg" || unit == "mcg" { result /= 1000 }
        default: if unit == "mg" { result /= 1000 }
        }
        return result
    }

    /// Text without HTML tags, entities or extra spaces.
    static func clean(_ text: String) -> String {
        var value = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let entities = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&#039;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " ",
                        "&frac12;": "½", "&frac14;": "¼", "&frac34;": "¾", "&#8217;": "’", "&#8211;": "–", "&ndash;": "–", "&rsquo;": "’"]
        for (entity, character) in entities { value = value.replacingOccurrences(of: entity, with: character) }
        value = value.replacingOccurrences(of: #"&#(\d+);"#, with: " ", options: .regularExpression)
        return value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
