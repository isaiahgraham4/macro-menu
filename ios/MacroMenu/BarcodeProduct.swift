import Foundation
import CoreFoundation

struct BarcodeProduct: Codable, Sendable {
    var food: Food
    var per100: Bool
    var unit: String
    var sourceURL: URL
}

enum RecentBarcodes {
    static let storageKey = "recentBarcodeProducts"
    /// How many scans are remembered and offered.
    static let limit = 10
    static func products(from data: Data) -> [BarcodeProduct] {
        ((try? JSONDecoder().decode([BarcodeProduct].self, from: data)) ?? [])
            .filter { $0.food.isValid }.prefix(limit).map { $0 }
    }
    static func recording(_ product: BarcodeProduct, in data: Data) -> Data {
        let recent = [product] + products(from: data).filter { $0.sourceURL != product.sourceURL }
        return (try? JSONEncoder().encode(Array(recent.prefix(limit)))) ?? data
    }
}

enum BarcodeLookupError: LocalizedError {
    case invalidCode, notFound, incomplete, unavailable
    var errorDescription: String? {
        switch self {
        case .invalidCode: "Check the barcode digits and try again. Enter an 8, 12, 13 or 14 digit product barcode."
        case .notFound: "This product isn't in Open Food Facts yet. Add its barcode to a food you enter yourself, and scanning it next time will find that food."
        case .incomplete: "This product doesn't have complete energy and protein data. Add its barcode to a food you enter yourself, and scanning it next time will find that food."
        case .unavailable: "The food database is unavailable right now. Try again shortly, or scan the nutrition label."
        }
    }
}

enum BarcodeLookup {
    static func validatedCode(_ input: String) throws -> String {
        let code = input.filter { !$0.isWhitespace && $0 != "-" }
        guard [8, 12, 13, 14].contains(code.count), code.utf8.allSatisfy({ (48...57).contains($0) }) else {
            throw BarcodeLookupError.invalidCode
        }
        let digits = code.utf8.map { Int($0 - 48) }
        let sum = digits.dropLast().reversed().enumerated().reduce(0) { $0 + $1.element * ($1.offset.isMultiple(of: 2) ? 3 : 1) }
        guard (10 - sum % 10) % 10 == digits.last!, Set(digits) != [0] else { throw BarcodeLookupError.invalidCode }
        return code
    }

    /// The first saved food with this barcode. Leading zeros are ignored, so a 12-digit UPC matches its 13-digit EAN.
    static func match(_ code: String, in foods: [Food]) -> Food? {
        let key = code.drop { $0 == "0" }
        return foods.first { food in food.barcode.map { $0.drop { $0 == "0" } == key } ?? false }
    }

    static func fetch(_ input: String) async throws -> BarcodeProduct {
        try await fetch(code: validatedCode(input))
    }

    /// Looks up a code Open Food Facts already uses, such as one from a search, without the check-digit test.
    static func fetch(code: String) async throws -> BarcodeProduct {
        var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json")!
        components.queryItems = [URLQueryItem(name: "fields", value: "product_name,product_name_en,brands,serving_size,serving_quantity_unit,product_quantity_unit,nutriments")]
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.setValue("Leanr/1.0 (iOS; com.isaiahgraham.MacroMenu)", forHTTPHeaderField: "User-Agent")
        // Only the barcode goes out: no cookies are kept or sent.
        request.httpShouldHandleCookies = false
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw BarcodeLookupError.unavailable }
        if http.statusCode == 404 { throw BarcodeLookupError.notFound }
        guard http.statusCode == 200 else { throw BarcodeLookupError.unavailable }
        return try parse(data, code: code)
    }

    static func parse(_ data: Data, code: String) throws -> BarcodeProduct {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BarcodeLookupError.unavailable }
        guard (root["status"] as? NSNumber)?.intValue == 1,
              let product = root["product"] as? [String: Any] else { throw BarcodeLookupError.notFound }
        let nutrients = product["nutriments"] as? [String: Any] ?? [:]
        func number(_ key: String) -> Double? {
            let value: Double?
            if let n = nutrients[key] as? NSNumber {
                guard CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
                value = n.doubleValue
            } else if let s = nutrients[key] as? String { value = Double(s) }
            else { value = nil }
            return value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        }
        func calories(_ suffix: String) -> Double? {
            number("energy-kcal_" + suffix) ?? (number("energy-kj_" + suffix) ?? number("energy_" + suffix)).map { $0 / 4.184 }
        }
        func text(_ key: String) -> String { (product[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        // Keep all nutrients on one basis. Never mix per-serving and per-100 values.
        let hasServing = !text("serving_size").isEmpty && calories("serving") != nil && number("proteins_serving") != nil
        let per100 = !hasServing && calories("100g") != nil && number("proteins_100g") != nil
        let suffix = per100 ? "100g" : "serving"
        guard let cal = calories(suffix), let protein = number("proteins_" + suffix),
              per100 || !text("serving_size").isEmpty else { throw BarcodeLookupError.incomplete }
        let name = text("product_name_en").isEmpty ? text("product_name") : text("product_name_en")
        guard !name.isEmpty else { throw BarcodeLookupError.incomplete }
        let servingMeasure = LabelParser.measure(text("serving_size"))
        let unit = servingMeasure?.unit ?? ([text("serving_quantity_unit"), text("product_quantity_unit")].contains { $0.lowercased() == "ml" } ? "mL" : "g")
        let source = URL(string: "https://world.openfoodfacts.org/product/\(code)")!
        var extras: [String: Double] = [:]
        for (local, remote) in [("sat", "saturated-fat"), ("sugar", "sugars"), ("fibre", "fiber")] {
            extras[local] = number(remote + "_" + suffix)
        }
        // OFF's normalized sodium values are grams; Leanr stores sodium in milligrams.
        extras["sodium"] = number("sodium_" + suffix).map { $0 * 1000 }
        let brand = text("brands")
        var food = Food(name: brand.isEmpty ? name : "\(name) · \(brand)", kj: cal * 4.184, cal: cal,
                        p: protein, c: number("carbohydrates_" + suffix), f: number("fat_" + suffix),
                        serve: per100 ? "100 \(unit)" : text("serving_size"), nut: extras,
                        note: "Source: Open Food Facts (ODbL) · \(source.absoluteString). Check against the package label.")
        food.barcode = code
        guard food.isValid else { throw BarcodeLookupError.incomplete }
        if per100, let servingMeasure {
            let ratio = servingMeasure.amount / 100
            food.cal *= ratio; food.kj *= ratio; food.p *= ratio
            food.c = food.c.map { $0 * ratio }; food.f = food.f.map { $0 * ratio }
            food.nut = food.nut?.mapValues { $0 * ratio }
            food.serve = text("serving_size")
            return BarcodeProduct(food: food, per100: false, unit: unit, sourceURL: source)
        }
        return BarcodeProduct(food: food, per100: per100, unit: unit, sourceURL: source)
    }
}

/// A product found by searching Open Food Facts by name.
struct ProductHit: Identifiable, Hashable, Sendable {
    /// Per 100 g or mL, from the search index. Opening the product fetches its full label, with serving sizes.
    var product: BarcodeProduct
    var code: String
    var id: String { code }
    static func == (a: ProductHit, b: ProductHit) -> Bool { a.code == b.code }
    func hash(into hasher: inout Hasher) { hasher.combine(code) }
}

/// Finds packaged foods by name in Open Food Facts, for anything that isn't on a menu or in My foods.
/// Only runs when asked: Open Food Facts doesn't allow search-as-you-type, and nothing is sent while typing.
enum ProductSearch {
    static let limit = 20

    /// The words searched for: letters and numbers only, so typed punctuation can't change the query.
    static func terms(_ text: String) -> String {
        FoodSearch.tokens(text).prefix(8).map { String($0.prefix(30)) }.joined(separator: " ")
    }

    static func url(_ terms: String, australia: Bool) -> URL {
        var components = URLComponents(string: "https://search.openfoodfacts.org/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: australia ? terms + #" countries_tags:"en:australia""# : terms),
            URLQueryItem(name: "langs", value: "en"),
            URLQueryItem(name: "page_size", value: String(limit * 2)),
            URLQueryItem(name: "fields", value: "code,product_name,product_name_en,brands,quantity,nutriments"),
        ]
        return components.url!
    }

    /// Products sold in Australia first; the rest of the world only if none match.
    static func search(_ text: String) async throws -> [ProductHit] {
        let terms = terms(text)
        guard !terms.isEmpty else { return [] }
        let local = try await fetch(url(terms, australia: true))
        return local.isEmpty ? try await fetch(url(terms, australia: false)) : local
    }

    private static func fetch(_ url: URL) async throws -> [ProductHit] {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Leanr/1.0 (iOS; com.isaiahgraham.MacroMenu)", forHTTPHeaderField: "User-Agent")
        // Only the search words go out: no cookies are kept or sent.
        request.httpShouldHandleCookies = false
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw BarcodeLookupError.unavailable }
        return try parse(data)
    }

    /// Products with energy and protein, without repeats, in the order Open Food Facts ranked them.
    static func parse(_ data: Data) throws -> [ProductHit] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hits = root["hits"] as? [[String: Any]] else { throw BarcodeLookupError.unavailable }
        var seen = Set<String>()
        var results: [ProductHit] = []
        for var hit in hits {
            guard let code = hit["code"] as? String, (4...14).contains(code.count), code.utf8.allSatisfy({ (48...57).contains($0) }) else { continue }
            // The index lists brands as a list; the product page as text.
            if let brands = hit["brands"] as? [String] { hit["brands"] = brands.joined(separator: ", ") }
            if let quantity = hit["quantity"] as? String, LabelParser.measure(quantity)?.unit == "mL" { hit["product_quantity_unit"] = "ml" }
            hit["serving_size"] = nil
            let wrapped = try JSONSerialization.data(withJSONObject: ["status": 1, "product": hit])
            guard let product = try? BarcodeLookup.parse(wrapped, code: code), product.per100,
                  product.food.cal <= 950, product.food.p <= 100 else { continue }
            let key = "\(product.food.name.lowercased())|\(Int(product.food.cal.rounded()))|\(Int(product.food.p.rounded()))"
            guard seen.insert(key).inserted else { continue }
            results.append(ProductHit(product: product, code: code))
            if results.count == limit { break }
        }
        return results
    }
}
