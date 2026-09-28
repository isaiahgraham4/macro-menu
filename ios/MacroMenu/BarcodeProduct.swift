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
    static func products(from data: Data) -> [BarcodeProduct] {
        ((try? JSONDecoder().decode([BarcodeProduct].self, from: data)) ?? [])
            .filter { $0.food.isValid }.prefix(20).map { $0 }
    }
    static func recording(_ product: BarcodeProduct, in data: Data) -> Data {
        let recent = [product] + products(from: data).filter { $0.sourceURL != product.sourceURL }
        return (try? JSONEncoder().encode(Array(recent.prefix(20)))) ?? data
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
        let code = try validatedCode(input)
        var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json")!
        components.queryItems = [URLQueryItem(name: "fields", value: "product_name,product_name_en,brands,serving_size,serving_quantity_unit,product_quantity_unit,nutriments")]
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.setValue("Leanr/1.0 (iOS; com.isaiahgraham.MacroMenu)", forHTTPHeaderField: "User-Agent")
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
