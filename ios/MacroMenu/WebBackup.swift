import Foundation
import CryptoKit

enum WebBackup {
    static func identifier(_ text: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data(text.utf8)).prefix(16))
        return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
    }
    static func decode(_ bytes: Data, catalog: MenuCatalog) throws -> AppData {
        guard let root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              root["app"] as? String == "macro-menu", root["v"] as? Int == 1,
              let foods = root["foods"] as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
        func number(_ row: [String: Any], _ key: String) -> Double? { (row[key] as? NSNumber)?.doubleValue }
        func food(_ row: [String: Any]) throws -> Food {
            guard let name = row["name"] as? String, let cal = number(row,"cal"), let protein = number(row,"p") else { throw CocoaError(.fileReadCorruptFile) }
            var result = Food(id: row["id"] as? String ?? UUID().uuidString, name: name,
                              kj: number(row,"kj") ?? cal * 4.184, cal: cal, p: protein,
                              c: number(row,"c"), f: number(row,"f"), serve: row["serve"] as? String ?? "1 serving",
                              nut: row["nut"] as? [String: Double], price: number(row,"price"))
            for extra in row["other"] as? [[String: Any]] ?? [] {
                if let name = extra["name"] as? String, let value = number(extra,"amt") {
                    if result.nut == nil { result.nut = [:] }
                    result.nut?["\(name) (\(extra["unit"] as? String ?? "mg"))"] = value
                }
            }
            if let ingredients = row["ingredients"] as? [[String: Any]] {
                result.ingredients = try ingredients.map { Portion(food: try food($0)) }
                result.recipeYield = number(row,"servings") ?? 1
            }
            if row["kind"] as? String == "order" { result.note = "Imported custom order. Nutrition is the saved snapshot from your web backup." }
            guard result.isValid else { throw CocoaError(.fileReadCorruptFile) }
            return result
        }
        var result = AppData(); result.foods = try foods.map(food)
        result.goalSets = [Goals(id: identifier("web-default-targets"), name: "Imported targets")]
        let all = catalog.foods + result.foods
        for row in root["meals"] as? [[String: Any]] ?? [] {
            guard let name = row["name"] as? String, let items = row["items"] as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
            let portions = try items.map { item -> Portion in
                guard let value = all.first(where: { $0.id == item["id"] as? String }) else { throw CocoaError(.fileReadCorruptFile) }
                return Portion(food: value, quantity: number(item,"qty") ?? 1)
            }
            result.meals.append(SavedMeal(id: identifier(row["id"] as? String ?? name), name: name, items: portions))
        }
        if let sets = root["goalSets"] as? [[String: Any]], !sets.isEmpty {
            result.goalSets = sets.map { row in
                var goal = Goals(id: identifier(row["id"] as? String ?? "web"), name: row["name"] as? String ?? "Imported targets")
                let values = row["goals"] as? [String: Any] ?? [:]
                goal.values = Dictionary(uniqueKeysWithValues: nutrientNames.compactMap { n in number(values,n.key).flatMap { $0 > 0 ? (n.key,$0) : nil } })
                goal.mealCal = number(values,"mealCal") ?? 500; goal.mealProtein = number(values,"mealP") ?? 40
                for (key, dir) in values["dir"] as? [String: String] ?? [:] {
                    if dir == "min" { goal.minimums.insert(key) } else { goal.minimums.remove(key) }
                }
                return goal
            }
        }
        guard result.isValid else { throw CocoaError(.fileReadCorruptFile) }
        return result
    }
}
