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
    /// False when only one of the two engines saw it and the other was sure of something else: it's listed, but the user
    /// has to tick it.
    var agreed = true
    /// How big each one looks next to a normal serving. Only Apple Intelligence judges this; the classifier says regular.
    var size = PortionSize.regular
    /// Why it isn't ticked, when that's something other than the two readings disagreeing.
    var reason: String?
}

/// A rough portion size for an everyday food in a photo, as a share of one serving.
enum PortionSize: String, CaseIterable, Identifiable, Sendable {
    case small, regular, large
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var factor: Double {
        switch self {
        case .small: 0.6
        case .regular: 1
        case .large: 1.5
        }
    }
    /// Portion sizes apply to everyday and your own foods. A restaurant's item is already one size (its menu lists the others).
    static func applies(to food: Food) -> Bool { food.isEveryday || food.chain == "mine" }
}

/// Names the foods in a photo of a meal, then finds them in Leanr. Apple Intelligence does it where the device has it,
/// and Apple's built-in image classifier (`MealVision`) everywhere else, or when the first finds nothing. All on the device.
enum MealPhoto {
    /// Which engine named the foods, so the screen can say how much to trust the amounts.
    enum Engine: Sendable { case appleIntelligence, imageRecognition, both }

    struct Recognition: Sendable {
        var foods: [SeenFood]
        var engine: Engine
    }

    /// Whether this device can use Apple Intelligence's photo reading: iOS 27, Apple Intelligence on, and a model that reads images.
    static var isAvailable: Bool {
        guard #available(iOS 27.0, macOS 27.0, *) else { return false }
        let model = SystemLanguageModel.default
        return model.isAvailable && model.capabilities.contains(.vision)
    }

    /// Photo logging is offered on every iPhone: without Apple Intelligence the image classifier does the naming.
    static var canOffer: Bool { true }

    /// The foods in the photo. Apple's image classifier always looks (it says how sure it is), and Apple Intelligence
    /// does too where the iPhone has it; each fills in what the other misses.
    static func recognise(_ image: CGImage) async throws -> Recognition {
        // The classifier can fail (the iOS simulator has no neural engine); then the model's answer stands alone.
        async let classified = try? await MealVision.scoredFoods(in: image)
        var named: [SeenFood] = []
        if isAvailable, #available(iOS 27.0, macOS 27.0, *) { named = (try? await foods(in: image)) ?? [] }
        let vision = await classified ?? []
        if named.isEmpty && vision.isEmpty { _ = try await MealVision.scoredFoods(in: image) }   // surfaces a real error
        return merge(named: named, classified: vision)
    }

    /// Whether the classifier is this sure, the model's different answer is shown but not ticked for the user.
    static let sureScore = 0.45

    /// Combines the two engines' answers. Foods both saw count once; the classifier's go first (it's calibrated); a food
    /// only the model saw is added, unticked if the classifier was confident of something else.
    static func merge(named: [SeenFood], classified: [(food: SeenFood, score: Double)]) -> Recognition {
        if classified.isEmpty { return Recognition(foods: named, engine: .appleIntelligence) }
        if named.isEmpty { return Recognition(foods: classified.map(\.food).map { doubted($0, confirmedBy: []) }, engine: .imageRecognition) }
        let sure = classified.contains { $0.score >= sureScore }
        var foods = classified.map(\.food)
        for item in named {
            if let index = foods.firstIndex(where: { same($0, item) }) {
                foods[index].count = max(foods[index].count, item.count)
                if foods[index].brand == nil { foods[index].brand = item.brand }
                foods[index].size = item.size
            } else {
                var extra = item
                extra.agreed = !sure
                foods.append(extra)
            }
        }
        return Recognition(foods: foods.map { doubted($0, confirmedBy: named) }, engine: .both)
    }

    /// Labels the classifier gives to things that only look alike: a bowl of rice, tofu and salad reads as "soup".
    /// They're listed but not ticked unless Apple Intelligence saw the same.
    static let lookalikes: Set<String> = ["soup"]

    static func doubted(_ food: SeenFood, confirmedBy named: [SeenFood]) -> SeenFood {
        guard lookalikes.contains(food.name.lowercased()), !named.contains(where: { same($0, food) }) else { return food }
        var doubted = food
        doubted.agreed = false
        doubted.reason = "Bowls of food often look like soup in photos, so it isn't ticked. Choose it if it was soup."
        return doubted
    }

    /// Whether two engines mean the same food: one name inside the other ("burger", "hamburger"), or a shared whole word.
    static func same(_ a: SeenFood, _ b: SeenFood) -> Bool {
        func forms(_ food: SeenFood) -> [String] { ([food.name] + food.alternatives).map { $0.lowercased() } }
        for x in forms(a) {
            for y in forms(b) {
                if x.count >= 4, y.count >= 4, x.contains(y) || y.contains(x) { return true }
                let shared = Set(FoodSearch.tokens(x).map(stem)).intersection(FoodSearch.tokens(y).map(stem))
                if shared.contains(where: { $0.count >= 4 }) { return true }
            }
        }
        return false
    }

    /// A word without its plural, so "strawberry" finds "Strawberries" and "eggs" finds "Egg".
    static func stem(_ word: String) -> String {
        if word.hasSuffix("ies"), word.count > 4 { return String(word.dropLast(3)) + "y" }
        for ending in ["ches", "shes", "sses", "xes", "oes"] where word.hasSuffix(ending) && word.count > 4 { return String(word.dropLast(2)) }
        if word.hasSuffix("s"), !word.hasSuffix("ss"), word.count > 3 { return String(word.dropLast()) }
        return word
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
            @Guide(description: "What it is, in a few plain words someone would search a food diary for. Always the whole name of the food, never a body part or one ambiguous word: \"chicken drumstick\", not \"leg\". Examples: \"banana\", \"cheeseburger\", \"chicken breast\", \"white rice\" or \"cappuccino\". Use the plain generic name, not a restaurant's product name, unless the packaging in the photo prints that name. No adjectives about how it looks.")
            var name: String
            @Guide(description: "The restaurant or brand only if you can read its name or see its logo on packaging, a wrapper, a cup or a box in the photo, such as \"McDonald's\" or \"KFC\". Never guess it from the food itself: a burger, chips, chicken or pizza is not evidence of any restaurant. Otherwise empty.")
            var brand: String
            @Guide(description: "How many of it there are", .range(1...12))
            var count: Int
            @Guide(description: "How big each one looks next to one normal serving for one person: small, regular or large", .anyOf(["small", "regular", "large"]))
            var size: String
            @Guide(description: "Up to three other names a nutrition database might list it under, most specific first, such as \"chicken drumstick\" and \"chicken thigh\" for a chicken leg, or \"cheeseburger\" and \"hamburger\" for a burger.", .maximumCount(3))
            var otherNames: [String]
        }
    }

    /// The foods Apple Intelligence sees in the photo. Throws if the model is unavailable or can't answer.
    @available(iOS 27.0, macOS 27.0, *)
    static func foods(in image: CGImage) async throws -> [SeenFood] {
        let session = LanguageModelSession(instructions: """
            You look at photos for a food diary and say which foods and drinks are in them. \
            Only name what you can see. Never estimate calories or nutrients. \
            Never name a restaurant or brand unless its name or logo is printed in the photo. \
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
            return SeenFood(name: name, alternatives: Array(others.prefix(3)), brand: brand.isEmpty ? nil : brand, count: min(max(item.count, 1), 12),
                            size: PortionSize(rawValue: item.size.lowercased()) ?? .regular)
        }
    }

    /// The version most people mean when a photo just says "rice" or "bread".
    private static let usual: Set<String> = ["White rice, cooked", "White bread", "Pasta, cooked", "Milk, full cream", "Garden salad, no dressing"]

    /// Matches in the order a person would expect: the food named exactly that, then foods whose main name ends with it
    /// ("White rice, cooked" for "rice"), then those that start with it; Leanr's own everyday foods before USDA's survey
    /// foods; cooked before raw or dry; plainer names first.
    /// Each source (a restaurant, or everyday foods) stays together, in the order the sources were found.
    static func ordered(_ foods: [Food], for words: [String]) -> [Food] {
        func key(_ food: Food) -> (Int, Int, Int, Int, Int, Int) {
            let all = FoodSearch.tokens(food.name).map(stem)
            let main = FoodSearch.tokens(String(food.name.prefix { $0 != "," })).map(stem)
            let words = words.map(stem)
            let bucket = all == words ? 0 : (main.count >= words.count && Array(main.suffix(words.count)) == words) ? 1 : (main.starts(with: words) ? 2 : 3)
            let uncooked = all.contains { ["raw", "dry", "uncooked", "powder", "canned"].contains($0) } ? 1 : 0
            // "Rice, cooked" and "Egg" are the ingredient; "Spanish rice" and "Egg noodles" are dishes made with it.
            let dish = food.name.contains(",") || all.count == 1 ? 0 : 1
            return (bucket, food.isSurvey ? 1 : 0, uncooked, dish, usual.contains(food.name) ? 0 : 1, main.count)
        }
        var sources: [String] = []
        for food in foods where !sources.contains(food.chain) { sources.append(food.chain) }
        return sources.flatMap { source in
            foods.filter { $0.chain == source }.sorted { a, b in
                let ka = key(a), kb = key(b)
                return ka != kb ? ka < kb : a.name < b.name
            }
        }
    }

    /// Other names people and photos use for a chain, as lower-case letters only, to its id in the menu.
    static let brandAliases: [String: String] = [
        "maccas": "mcd", "macca": "mcd", "mcdonalds": "mcd", "mcdonald": "mcd", "golden arches": "mcd",
        "hungryjacks": "hj", "hungry jacks": "hj", "hj": "hj", "burgerking": "hj", "burger king": "hj",
        "kfc": "kfc", "kentuckyfriedchicken": "kfc", "kentucky fried chicken": "kfc",
        "gyg": "gyg", "guzman": "gyg", "guzmanygomez": "gyg", "guzman y gomez": "gyg",
        "nandos": "nandos", "dominos": "dominos", "dominospizza": "dominos", "redrooster": "rr", "red rooster": "rr",
        "subway": "sub", "oporto": "oporto", "zambrero": "zam", "boost": "boost", "boostjuice": "boost", "boost juice": "boost",
        "schnitz": "schnitz", "grilld": "grilld",
    ]

    /// The restaurant a brand names, if it's one Leanr has: a known nickname first, then a close match to the chain's name.
    static func chain(for brand: String?, chainNames: [String: String]) -> String? {
        guard let brand, !brand.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let letters = brand.lowercased().filter { $0.isLetter || $0 == " " }.trimmingCharacters(in: .whitespaces)
        if let id = brandAliases[letters] ?? brandAliases[letters.replacingOccurrences(of: " ", with: "")],
           id != Food.everyday, chainNames[id] != nil { return id }
        return chainNames.sorted { $0.key < $1.key }.first {
            $0.key != Food.everyday && (FoodSearch.score($0.value, query: brand) == 0 || FoodSearch.score(brand, query: $0.value) == 0)
        }?.key
    }

    /// The match to tick by default. A restaurant's item is only ticked when the photo showed that restaurant's brand, or
    /// when you're at one of its restaurants (`nearby`); a burger or chips named in a photo says nothing about where it came
    /// from, so otherwise those are listed but left for the user to choose. With neither, the first everyday food is ticked.
    static func preselected(from matches: [Food], for seen: SeenFood, chainNames: [String: String], nearby: String? = nil) -> Food? {
        guard seen.agreed else { return nil }
        if let chain = chain(for: seen.brand, chainNames: chainNames), let hit = matches.first(where: { $0.chain == chain }) { return hit }
        // At a restaurant, its item is ticked unless an everyday food is plainly the thing seen (a banana is still a banana).
        if let nearby, let hit = matches.first(where: { $0.chain == nearby }), !matches.contains(where: { $0.isEveryday && plainly($0, is: seen) }) { return hit }
        return matches.first(where: \.isEveryday)
    }

    /// Whether a food is plainly the thing seen: its name before any comma is the same words ("Banana, raw" for "banana").
    static func plainly(_ food: Food, is seen: SeenFood) -> Bool {
        let main = FoodSearch.tokens(String(food.name.prefix { $0 != "," })).map(stem)
        return ([seen.name] + seen.alternatives).contains { FoodSearch.tokens($0).map(stem) == main }
    }

    /// Leanr foods that match what was seen, closest first. Every word must start a word of the food's name (no typo matching,
    /// so "chair" never finds "Chai"). With a brand, its restaurant comes first; without one, everyday foods (plain rice before a rice bowl).
    /// The other names are tried when the first finds nothing.
    /// `nearby` is a restaurant you're at: when the photo shows no brand, its two closest items go first, ahead of the usual matches.
    static func matches(for seen: SeenFood, in foods: [Food], chainNames: [String: String], limit: Int = 4, nearby: String? = nil) -> [Food] {
        let brand = chain(for: seen.brand, chainNames: chainNames)
        let usual = lookUp(seen, in: foods, chainNames: chainNames, chain: brand, limit: limit)
        guard brand == nil, let nearby, chainNames[nearby] != nil else { return usual }
        let local = lookUp(seen, in: foods, chainNames: chainNames, chain: nearby, limit: limit).filter { $0.chain == nearby }.prefix(2)
        return Array((local + usual.filter { food in !local.contains { $0.id == food.id } }).prefix(limit))
    }

    private static func lookUp(_ seen: SeenFood, in foods: [Food], chainNames: [String: String], chain: String?, limit: Int) -> [Food] {
        for search in [seen.name] + seen.alternatives {
            let query = FoodSearch.Query(search)
            guard !query.isEmpty else { continue }
            func exact(_ place: String) -> [Food] {
                FoodSearch.browse(foods, chainNames: chainNames, request: .init(search: search, chain: place)).filter { food in
                    // Each word starts a word of the name ("leg" doesn't match inside "Little G's").
                    let words = FoodSearch.tokens(food.name + " " + (chainNames[food.chain] ?? ""))
                    // A couple of extra letters at most, so "egg" finds "Eggs" but "pepper" never finds "Pepperoni".
                    return query.words.allSatisfy { word in words.contains { ($0.hasPrefix(word) && $0.count - word.count <= 2) || stem($0) == stem(word) } }
                }
            }
            var found = exact(chain ?? Food.everyday)
            for food in exact("all") where !found.contains(where: { $0.id == food.id }) { found.append(food) }
            if !found.isEmpty { return Array(ordered(found, for: query.words).prefix(limit)) }
        }
        return []
    }
}
