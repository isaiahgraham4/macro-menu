import Foundation

/// Conservative suggestions: only explicitly labelled lines with numeric values are used.
/// Users choose the column and review the result before saving.
enum LabelParser {
    struct Layout {
        var servingColumn: Int?
        var per100Column: Int?
        var amount: Double?
        var unit = "g"
        var servingDescription: String?
    }

    static func measure(_ description: String) -> (amount: Double, unit: String)? {
        let regex = try! NSRegularExpression(pattern: #"(\d+(?:[.,]\d+)?)\s*(kg|ml|g|l)\b"#, options: .caseInsensitive)
        guard let match = regex.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)),
              let number = Range(match.range(at: 1), in: description),
              let unitRange = Range(match.range(at: 2), in: description),
              let amount = Double(description[number].replacingOccurrences(of: ",", with: ".")), amount > 0 else { return nil }
        let unit = description[unitRange].lowercased()
        return (amount * (["kg", "l"].contains(unit) ? 1000 : 1), ["ml", "l"].contains(unit) ? "mL" : "g")
    }

    static func layout(_ text: String) -> Layout {
        var result = Layout()
        let headers = try! NSRegularExpression(pattern: #"per\s*(100\s*(?:g|ml)|serving|serve)\b"#, options: .caseInsensitive)
        var columns: [Bool] = []
        for match in headers.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range(at: 1), in: text) else { continue }
            let hundred = text[range].hasPrefix("100")
            if !columns.contains(hundred) { columns.append(hundred) }
        }
        result.servingColumn = columns.firstIndex(of: false)
        result.per100Column = columns.firstIndex(of: true)
        let lines = text.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            guard line.range(of: #"\bserv(?:ing|e)\s*size\b"#, options: .regularExpression.union(.caseInsensitive)) != nil else { continue }
            let description = line.replacingOccurrences(of: #"(?i)^.*?serv(?:ing|e)\s*size\s*[:\-]?\s*"#, with: "", options: .regularExpression)
            let candidate = !description.isEmpty ? description : (lines.indices.contains(index + 1) ? lines[index + 1] : "")
            if !candidate.isEmpty { result.servingDescription = candidate.trimmingCharacters(in: .whitespaces) }
            if let value = measure(candidate) {
                result.amount = value.amount; result.unit = value.unit
                result.servingDescription = candidate.trimmingCharacters(in: .whitespaces)
                break
            }
        }
        return result
    }

    static func servingSuggestions(_ text: String, column: Int) -> [String: Double] {
        let info = layout(text)
        let ratio = info.per100Column == column ? (info.amount.map { $0 / 100 } ?? 1) : 1
        return suggestions(text, column: column).mapValues { $0 * ratio }
    }

    static func suggestions(_ text: String, column: Int) -> [String: Double] {
        let aliases: [(String,[String])] = [
            ("sat",["saturated"]),("trans",["trans fat"]),("sugar",["sugars","sugar"]),("fibre",["dietary fibre","dietary fiber","fibre","fiber"]),
            ("sodium",["sodium"]),("potassium",["potassium"]),("calcium",["calcium"]),("iron",["iron"]),
            ("chol",["cholesterol"]),("caffeine",["caffeine"]),("p",["protein"]),("c",["total carbohydrate","carbohydrate","carbs"]),("f",["total fat","fat"])]
        let regex = try! NSRegularExpression(pattern: #"(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:[.,]\d+)?)\s*(kcal|kj|cal|mg|µg|g|%)?"#, options: .caseInsensitive)
        var result: [String: Double] = [:]
        var statedCalories: Double?
        var statedKilojoules: Double?
        var pendingEnergyLabel: String?
        for line in text.components(separatedBy: .newlines) {
            var lower = line.lowercased().trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–—•")))
                .replacingOccurrences(of: #"k\s+j\b"#, with: "kj", options: .regularExpression)
                .replacingOccurrences(of: #"k\s+cal\b"#, with: "kcal", options: .regularExpression)
            // OCR may put the energy heading on the line before its values.
            if let heading = pendingEnergyLabel, lower.first?.isNumber == true {
                lower = heading + " " + lower
            }
            pendingEnergyLabel = nil
            let isEnergyLabel = ["energy", "calories", "kilojoules", "kj", "kcal"].contains(where: { lower.hasPrefix($0) })
            if isEnergyLabel && !lower.contains(where: \.isNumber) { pendingEnergyLabel = lower; continue }
            // Values preceded by less-than signs are bounds, not measured values.
            if lower.contains("<") || lower.contains("less than") { continue }
            let tokens: [(Double,String)] = regex.matches(in: lower, range: NSRange(lower.startIndex...,in: lower)).compactMap { match in
                guard let range = Range(match.range(at: 1),in: lower) else { return nil }
                let raw = String(lower[range])
                let grouped = raw.range(of: #"^\d{1,3}(,\d{3})+(\.\d+)?$"#, options: .regularExpression) != nil
                guard let value = Double(raw.replacingOccurrences(of: ",", with: grouped ? "" : ".")) else { return nil }
                let unit = Range(match.range(at: 2),in: lower).map { String(lower[$0]) } ?? ""
                guard unit != "%" else { return nil }
                return (value,unit)
            }
            let isStandaloneEnergy = lower.first?.isNumber == true && tokens.contains { ["kj", "kcal", "cal"].contains($0.1) }
            if isEnergyLabel || isStandaloneEnergy {
                let calories = tokens.filter { $0.1 == "cal" || $0.1 == "kcal" }
                let joules = tokens.filter { $0.1 == "kj" }
                if calories.indices.contains(column) { statedCalories = calories[column].0 }
                if joules.indices.contains(column) { statedKilojoules = joules[column].0 }
                if calories.isEmpty && joules.isEmpty && tokens.indices.contains(column) {
                    if lower.hasPrefix("calories") || lower.contains("kcal") { statedCalories = tokens[column].0 }
                    else if lower.contains("kj") || lower.contains("kilojoules") { statedKilojoules = tokens[column].0 }
                }
            } else if let (key, _) = aliases.first(where: { _, names in names.contains { lower.hasPrefix($0) || lower.hasPrefix("- " + $0) } }), tokens.indices.contains(column) {
                let (value, unit) = tokens[column]
                let wanted = nutrientNames.first { $0.key == key }?.unit ?? "g"
                if unit.isEmpty || unit == wanted.lowercased() { result[key] = value }
                else if unit == "g" && wanted == "mg" { result[key] = value * 1000 }
                else if unit == "mg" && wanted == "g" { result[key] = value / 1000 }
            }
        }
        // Prefer explicitly printed calories regardless of the order of energy rows.
        result["cal"] = statedCalories ?? statedKilojoules.map { $0 / 4.184 }
        return result
    }
}
