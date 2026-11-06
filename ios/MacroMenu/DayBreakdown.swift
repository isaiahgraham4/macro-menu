import Foundation

/// Everything logged on one day, taken apart for the breakdown that opens from Today's targets:
/// the macros and their share of energy, every nutrient any food listed, and which foods it came from.
/// A nutrient is "partial" when some logged foods don't list it, and the total counts only the ones that do.
struct DayBreakdown: Sendable {
    /// One logged food, as it was logged (a recipe stays one line).
    struct Line: Identifiable, Sendable {
        var id: UUID
        var name: String
        /// "2 × 1 serving" or "1 burger".
        var amount: String
        var mealTime: MealTime?
        var nutrition: Nutrition
    }
    /// One food's part in a nutrient's total.
    struct Source: Identifiable, Sendable, Equatable {
        var id: UUID
        var name: String
        var value: Double
    }
    struct Macro: Identifiable, Sendable {
        var key: String
        var label: String
        var grams: Double
        /// Share of the energy from protein, carbs and fat (4/4/9), from 0 to 1.
        var share: Double
        var target: Double?
        var minimum: Bool
        var partial: Bool
        var sources: [Source]
        var id: String { key }
    }
    struct Nutrient: Identifiable, Sendable {
        var key: String
        var label: String
        var unit: String
        var value: Double
        var target: Double?
        var minimum: Bool
        /// How many of the day's foods list it.
        var listedBy: Int
        var sources: [Source]
        var id: String { key }
    }

    var lines: [Line]
    var total: Nutrition
    var macros: [Macro]
    /// Nutrients at least one food listed, in the usual order, then any others by name.
    var nutrients: [Nutrient]
    /// Nutrients with a target that none of the day's foods listed.
    var unlisted: [String]

    init(entries: [LogEntry], goals: Goals) {
        let lines = entries.flatMap { entry in
            entry.items.map { portion in
                Line(id: portion.id, name: portion.food.name, amount: Self.amount(portion), mealTime: entry.mealTime, nutrition: Nutrition([portion]))
            }
        }
        let total = Nutrition(entries.flatMap(\.items))
        self.lines = lines
        self.total = total

        func sources(_ value: (Nutrition) -> Double?) -> [Source] {
            lines.compactMap { line in value(line.nutrition).map { Source(id: line.id, name: line.name, value: $0) } }
                .filter { $0.value > 0 }
                .sorted { $0.value > $1.value }
        }
        let energy = total.p * 4 + total.c * 4 + total.f * 9
        macros = [("p", "Protein", total.p), ("c", "Carbs", total.c), ("f", "Fat", total.f)].map { key, label, grams in
            let factor = key == "f" ? 9.0 : 4.0
            return Macro(key: key, label: label, grams: grams, share: energy > 0 ? grams * factor / energy : 0,
                         target: goals.values[key], minimum: goals.minimums.contains(key), partial: total.isPartial(key),
                         sources: sources { $0.value(key) })
        }

        let known = nutrientNames.dropFirst(4).map(\.key)
        let extra = Set(lines.flatMap { $0.nutrition.nut.keys }).subtracting(known).sorted()
        var nutrients: [Nutrient] = []
        for key in known + extra {
            let listing = lines.filter { $0.nutrition.nut[key] != nil }
            guard !listing.isEmpty else { continue }
            let name = nutrientNames.first { $0.key == key }
            nutrients.append(Nutrient(key: key, label: name?.label ?? key.capitalized, unit: name?.unit ?? "",
                                      value: total.nut[key] ?? 0, target: goals.values[key], minimum: goals.minimums.contains(key),
                                      listedBy: listing.count, sources: sources { $0.nut[key] }))
        }
        self.nutrients = nutrients
        unlisted = nutrientNames.dropFirst(4)
            .filter { name in goals.values[name.key] != nil && !nutrients.contains { $0.key == name.key } }
            .map(\.label)
    }

    /// How many foods were logged, for "listed by 3 of 5 foods".
    var foodCount: Int { lines.count }

    /// True when some of the day's foods don't list this nutrient, so its total is only what's known.
    func isPartial(_ nutrient: Nutrient) -> Bool { nutrient.listedBy < foodCount }

    /// "2 × 1 serving", or just the serve for one.
    static func amount(_ portion: Portion) -> String {
        let serve = portion.food.serve
        return portion.quantity == 1 ? serve : "\(portion.quantity.formatted(.number.precision(.fractionLength(0...2)))) × \(serve)"
    }

    /// "48 g of 150 g", "1,200 mg, at most 2,300 mg" and the like, for a figure against its target.
    static func progress(_ value: Double, target: Double?, minimum: Bool, unit: String) -> String? {
        guard let target, target > 0 else { return nil }
        let percent = Int((value / target * 100).rounded())
        return minimum ? "\(percent)% of \(target.number) \(unit) goal" : "\(percent)% of \(target.number) \(unit) limit"
    }
}
