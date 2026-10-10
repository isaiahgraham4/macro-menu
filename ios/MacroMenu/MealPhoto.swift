import Foundation
import CoreGraphics
import FoundationModels

/// A food recognised in a photo: just what it is and how many. The figures always come from Leanr's own data, never the model.
struct SeenFood: Equatable, Sendable {
    var name: String
    /// Other names a food list might use ("chicken drumstick" for "chicken leg"), most specific first.
    var alternatives: [String] = []
    /// The restaurant or brand, when packaging shows it.
    var brand: String?
    var count: Int
}

/// Names the foods in a photo of a meal with Apple's on-device model (Apple Intelligence), then finds them in Leanr.
/// Nothing leaves the device.
enum MealPhoto {
    /// Whether this device can recognise foods in photos: iOS 27, Apple Intelligence on, and a model that reads images.
    static var isAvailable: Bool {
        guard #available(iOS 27.0, macOS 27.0, *) else { return false }
        let model = SystemLanguageModel.default
        return model.isAvailable && model.capabilities.contains(.vision)
    }

    /// Whether to offer the photo button: the device can do it, or could once Apple Intelligence is turned on.
    static var canOffer: Bool {
        guard #available(iOS 27.0, macOS 27.0, *) else { return false }
        switch SystemLanguageModel.default.availability {
        case .available: return SystemLanguageModel.default.capabilities.contains(.vision)
        case .unavailable(.deviceNotEligible): return false
        case .unavailable: return true
        }
    }

    /// Why recognising isn't available, to show instead of the button.
    static var unavailableReason: String? {
        guard #available(iOS 27.0, macOS 27.0, *) else { return "Needs iOS 27 or later with Apple Intelligence." }
        switch SystemLanguageModel.default.availability {
        case .available: return SystemLanguageModel.default.capabilities.contains(.vision) ? nil : "This device's Apple Intelligence model can't read photos."
        case .unavailable(.deviceNotEligible): return "Needs an iPhone that supports Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in the Settings app to use this."
        case .unavailable(.modelNotReady): return "Apple Intelligence is still getting ready. Try again soon."
        case .unavailable: return "Apple Intelligence isn't available right now."
        }
    }

    @available(iOS 27.0, macOS 27.0, *)
    @Generable(description: "The foods and drinks in a photo")
    struct Recognised {
        @Guide(description: "Each separate food or drink you can see, the biggest or most obvious first. Empty if there's no food or drink.", .maximumCount(8))
        var foods: [Item]

        @Generable(description: "One thing in the photo")
        struct Item {
            @Guide(description: "True only if this is something people eat or drink")
            var isFoodOrDrink: Bool
            @Guide(description: "What it is, in a few plain words someone would search a food diary for, such as \"banana\", \"Big Mac\", \"chicken breast\", \"white rice\" or \"cappuccino\". No adjectives about how it looks.")
            var name: String
            @Guide(description: "The restaurant or brand only if packaging, a logo or a wrapper in the photo shows it, such as \"McDonald's\" or \"KFC\". Otherwise empty.")
            var brand: String
            @Guide(description: "How many of it there are", .range(1...12))
            var count: Int
            @Guide(description: "Up to three other names a nutrition database might list it under, most specific first, such as \"chicken drumstick\" and \"chicken thigh\" for a chicken leg, or \"cheeseburger\" and \"hamburger\" for a burger.", .maximumCount(3))
            var otherNames: [String]
        }
    }

    /// The foods in the photo. Throws if the model is unavailable or can't answer.
    @available(iOS 27.0, macOS 27.0, *)
    static func foods(in image: CGImage) async throws -> [SeenFood] {
        let session = LanguageModelSession(instructions: """
            You look at photos for a food diary and say which foods and drinks are in them. \
            Only name what you can see. Never estimate calories or nutrients. \
            If the photo has no food or drink, return an empty list.
            """)
        let response = try await session.respond(generating: Recognised.self) {
            "Which foods and drinks are in this photo, and how many of each?"
            Attachment(image)
        }
        return response.content.foods.compactMap { item in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard item.isFoodOrDrink, !name.isEmpty else { return nil }
            let brand = item.brand.trimmingCharacters(in: .whitespacesAndNewlines)
            let others = item.otherNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && $0.lowercased() != name.lowercased() }
            return SeenFood(name: name, alternatives: Array(others.prefix(3)), brand: brand.isEmpty ? nil : brand, count: min(max(item.count, 1), 12))
        }
    }

    /// Leanr foods that match what was seen, closest first. Every word must start a word of the food's name (no typo matching,
    /// so "chair" never finds "Chai"). With a brand, its restaurant comes first; without one, everyday foods (plain rice before a rice bowl).
    /// The other names are tried when the first finds nothing.
    static func matches(for seen: SeenFood, in foods: [Food], chainNames: [String: String], limit: Int = 4) -> [Food] {
        let chain = seen.brand.flatMap { brand in
            chainNames.first { $0.key != Food.everyday && (FoodSearch.score($0.value, query: brand) == 0 || FoodSearch.score(brand, query: $0.value) == 0) }?.key
        }
        for search in [seen.name] + seen.alternatives {
            let query = FoodSearch.Query(search)
            guard !query.isEmpty else { continue }
            func exact(_ place: String) -> [Food] {
                FoodSearch.browse(foods, chainNames: chainNames, request: .init(search: search, chain: place)).filter { food in
                    // Each word starts a word of the name ("leg" doesn't match inside "Little G's").
                    let words = FoodSearch.tokens(food.name + " " + (chainNames[food.chain] ?? ""))
                    return query.words.allSatisfy { word in words.contains { $0.hasPrefix(word) } }
                }
            }
            var found = exact(chain ?? Food.everyday)
            for food in exact("all") where !found.contains(where: { $0.id == food.id }) { found.append(food) }
            if !found.isEmpty { return Array(found.prefix(limit)) }
        }
        return []
    }
}
