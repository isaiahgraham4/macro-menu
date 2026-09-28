import Foundation

enum MealSwaps {
    static func options(for portion: Portion, foods: [Food]) -> [Food] {
        guard portion.isValid, portion.food.chain != "mine" else { return [] }
        return foods.filter {
            $0.isValid && $0.id != portion.food.id &&
            $0.chain == portion.food.chain && $0.cat == portion.food.cat &&
            (portion.food.cal - $0.cal) * portion.quantity >= 20
        }.sorted {
            // Prefer alternatives that retain protein, then compare calorie savings.
            let lhsRetains = $0.p >= portion.food.p * 0.8
            let rhsRetains = $1.p >= portion.food.p * 0.8
            if lhsRetains != rhsRetains { return lhsRetains }
            if $0.cal != $1.cal { return $0.cal < $1.cal }
            return $0.id < $1.id
        }.prefix(12).map { $0 }
    }
}
