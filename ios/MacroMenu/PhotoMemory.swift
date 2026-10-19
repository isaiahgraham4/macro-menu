import Foundation

/// What you logged for each food a photo named, so the next photo of it is ticked as that food and amount straight away.
/// Kept on this device only (UserDefaults), never in your data, iCloud or backups; "Delete all my data" clears it.
enum PhotoMemory {
    struct Choice: Codable, Equatable, Sendable {
        var foodID: String
        /// Servings for each one counted in the photo.
        var perItem: Double
        var used: Date
    }

    static let storageKey = "photo.choices"
    /// The most foods remembered; the ones used longest ago go first.
    static let limit = 200

    /// The same photo food however it was worded: "Strawberries" and "strawberry" share a key.
    static func key(for seen: SeenFood) -> String {
        FoodSearch.tokens(seen.name).map(MealPhoto.stem).joined(separator: " ")
    }

    static func choice(for seen: SeenFood, in choices: [String: Choice]) -> Choice? {
        let key = key(for: seen)
        return key.isEmpty ? nil : choices[key]
    }

    /// The choices with what was just logged added: each food's pick and its amount per item seen.
    static func remembering(_ logged: [(seen: SeenFood, food: Food, quantity: Double)], in choices: [String: Choice], now: Date = Date()) -> [String: Choice] {
        var updated = choices
        for item in logged {
            let key = key(for: item.seen)
            let perItem = item.quantity / Double(max(item.seen.count, 1))
            guard !key.isEmpty, perItem.isFinite, perItem > 0 else { continue }
            updated[key] = Choice(foodID: item.food.id, perItem: perItem, used: now)
        }
        if updated.count > limit {
            for old in updated.sorted(by: { $0.value.used < $1.value.used }).prefix(updated.count - limit) { updated[old.key] = nil }
        }
        return updated
    }

    static func load(_ defaults: UserDefaults = .standard) -> [String: Choice] {
        guard let data = defaults.data(forKey: storageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Choice].self, from: data)) ?? [:]
    }

    static func save(_ choices: [String: Choice], _ defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(choices) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
