import Foundation

enum MealSwaps {
    static func options(for portion: Portion, foods: [Food]) -> [Food] {
        guard portion.isValid, portion.food.chain != "mine", !portion.food.isEveryday else { return [] }
        return foods.filter {
            $0.isValid && $0.id != portion.food.id &&
            $0.chain == portion.food.chain && $0.cat == portion.food.cat &&
            (portion.food.cal - $0.cal) * portion.quantity >= 20 && isServing($0, against: portion.food)
        }.sorted {
            // Prefer alternatives that retain protein, then compare calorie savings.
            let lhsRetains = $0.p >= portion.food.p * 0.8
            let rhsRetains = $1.p >= portion.food.p * 0.8
            if lhsRetains != rhsRetains { return lhsRetains }
            if $0.cal != $1.cal { return $0.cal < $1.cal }
            return $0.id < $1.id
        }.prefix(12).map { $0 }
    }

    /// Whether `food` is a serving you'd eat instead, not a packet or one piece of a pack: at least a third of the
    /// original's weight. A menu's "side" can be a 5 g seasoning sachet, and its "main" a single nugget split from a box.
    /// Foods without comparable weights are kept.
    static func isServing(_ food: Food, against original: Food) -> Bool {
        guard let weight = food.servingWeight, let originalWeight = original.servingWeight, weight.1 == originalWeight.1 else { return true }
        return weight.0 >= originalWeight.0 / 3
    }
}
