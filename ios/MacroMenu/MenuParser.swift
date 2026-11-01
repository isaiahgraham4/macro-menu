import Foundation

/// One run of text read from a menu photo. Positions are fractions of the page, measured from its top left.
struct MenuLine: Equatable, Sendable {
    var text: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var page = 0
    var maxX: Double { x + width }
    var midY: Double { y + height / 2 }
}

/// A dish as a menu words it. Only what was read; the figures are worked out separately (`MenuEstimator`).
struct MenuDish: Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var details = ""
    var price: Double?
    /// The menu's heading above it, such as "Entrees".
    var section: String?
}

/// Turns the text on a menu photo into dishes. Menus have no fixed layout, so this goes by what menus usually do: columns,
/// a price at the end of a dish's line, a smaller description underneath, headings in larger or capital letters.
enum MenuParser {
    struct Result: Equatable, Sendable {
        /// The big name at the top of the first page, when there is one.
        var restaurant: String?
        var dishes: [MenuDish]
    }

    private struct Row {
        var text: String
        var y: Double
        var height: Double
        var price: Double?
    }

    static func read(_ lines: [MenuLine]) -> Result {
        let readable = lines.filter { $0.text.contains { $0.isLetter || $0.isNumber } }
        let body = median(readable.map(\.height))
        let title = restaurantLine(in: readable, body: body)
        var dishes: [MenuDish] = []
        var section: String?
        for page in Set(readable.map(\.page)).sorted() {
            let text = readable.filter { $0.page == page && $0 != title }
            for column in columns(text) { parse(rows(column), body: body, section: &section, into: &dishes) }
        }
        for index in dishes.indices {
            dishes[index].name = dishes[index].name.trimmingCharacters(in: CharacterSet(charactersIn: ", "))
            dishes[index].details = dishes[index].details.trimmingCharacters(in: CharacterSet(charactersIn: ", "))
        }
        return Result(restaurant: title.map { titled(clean($0.text)) }, dishes: dishes)
    }

    // MARK: Page layout

    /// The largest words near the top of the first page, unless they only say what kind of menu it is.
    private static func restaurantLine(in lines: [MenuLine], body: Double) -> MenuLine? {
        let top = lines.filter { $0.page == 0 && $0.y < 0.25 && $0.height >= body * 1.4 && splitPrice($0.text).price == nil }
        guard let line = top.max(by: { $0.height < $1.height }) else { return nil }
        let words = line.text.split(separator: " ")
        guard (1...5).contains(words.count), !isKnownHeading(clean(line.text)) else { return nil }
        return line
    }

    /// The page's columns, left to right. A column shows up as a gap running down the page that text starts on both sides of.
    /// Lines most of the page wide (titles, footers) and lone prices aren't counted, since they cross or sit beside columns.
    static func columns(_ lines: [MenuLine]) -> [[MenuLine]] {
        let prices = lines.filter(isOnlyPrice)
        let words = lines.filter { !isOnlyPrice($0) }
        var parts = split(words)
        // Lone prices go with the column they're at the right of, going by where its lines usually start.
        let starts = parts.map { median($0.map(\.x)) }
        for price in prices {
            let index = starts.lastIndex { $0 < price.x } ?? 0
            if parts.indices.contains(index) { parts[index].append(price) } else { parts.append([price]) }
        }
        return parts
    }

    private static func split(_ lines: [MenuLine], depth: Int = 0) -> [[MenuLine]] {
        // A title or footer centred across the columns isn't part of either.
        let top = lines.map(\.y).min() ?? 0, bottom = lines.map(\.y).max() ?? 1
        let isBanner = { (line: MenuLine) in
            abs(line.x + line.width / 2 - 0.5) < 0.06 && (line.y < top + (bottom - top) * 0.15 || line.y > bottom - (bottom - top) * 0.12)
        }
        let narrow = lines.filter { $0.width < 0.6 && !isBanner($0) }
        guard depth < 3, narrow.count >= 6, let gap = columnGap(narrow) else { return [lines] }
        let left = lines.filter { $0.x < gap }
        let right = lines.filter { $0.x >= gap }
        return split(left, depth: depth + 1) + split(right, depth: depth + 1)
    }

    /// The middle of the widest stretch that little text crosses, with a good share of the lines starting on each side. A centred
    /// title or footer can cross it, so a few lines are allowed to.
    private static func columnGap(_ lines: [MenuLine]) -> Double? {
        let steps = 100
        var cover = [Int](repeating: 0, count: steps)
        for line in lines {
            let start = max(0, Int(line.x * Double(steps))), end = min(steps - 1, Int(line.maxX * Double(steps)))
            if start <= end { for index in start...end { cover[index] += 1 } }
        }
        let allowed = max(1, lines.count / 12)
        let low = Int((lines.map(\.x).min() ?? 0) * Double(steps)), high = Int((lines.map(\.x).max() ?? 1) * Double(steps))
        var best: (start: Int, length: Int)?
        var index = low + 1
        while index <= min(steps - 1, high) {
            guard cover[index] <= allowed else { index += 1; continue }
            var end = index
            while end + 1 < steps, cover[end + 1] <= allowed { end += 1 }
            if end - index + 1 > (best?.length ?? 0) { best = (index, end - index + 1) }
            index = end + 1
        }
        guard let best, best.length >= 3 else { return nil }
        let middle = (Double(best.start) + Double(best.length) / 2) / Double(steps)
        let share = max(3, lines.count / 5)
        guard lines.filter({ $0.x < middle }).count >= share, lines.filter({ $0.x >= middle }).count >= share else { return nil }
        return middle
    }

    private static func isOnlyPrice(_ line: MenuLine) -> Bool {
        let split = splitPrice(line.text)
        return split.price != nil && !split.words.contains(where: \.isLetter)
    }

    /// One column's lines from top to bottom, with a price printed apart on the same level joined to its line.
    private static func rows(_ lines: [MenuLine]) -> [Row] {
        let words = lines.filter { !isOnlyPrice($0) }.sorted { $0.y < $1.y }
        var rows = words.map { Row(text: $0.text, y: $0.y, height: $0.height) }
        for price in lines.filter(isOnlyPrice).sorted(by: { $0.y < $1.y }) {
            let level = rows.indices.filter { rows[$0].price == nil && abs(rows[$0].y + rows[$0].height / 2 - price.midY) < max(rows[$0].height, price.height) * 0.75 }
            if let row = level.min(by: { abs(rows[$0].y - price.y) < abs(rows[$1].y - price.y) }) {
                rows[row].price = splitPrice(price.text).price
            } else {
                // A price on its own line, as centred menus print them: it stays in place and goes with the dish above.
                rows.append(Row(text: price.text, y: price.y, height: price.height))
                rows.sort { $0.y < $1.y }
            }
        }
        return rows
    }

    // MARK: Reading the lines

    private static func parse(_ rows: [Row], body: Double, section: inout String?, into dishes: inout [MenuDish]) {
        let rows = rows.filter { !isNoise($0.text) }
        var nameHeight = body
        var startedHere = false
        for (index, row) in rows.enumerated() {
            let split = splitPrice(row.text)
            let price = row.price ?? split.price
            let words = clean(split.words)
            if !words.contains(where: \.isLetter) {
                if let price, startedHere, dishes[dishes.count - 1].price == nil { dishes[dishes.count - 1].price = price }
                continue
            }
            if isExtra(words) { continue }
            let next = rows.dropFirst(index + 1).first
            let last = startedHere ? dishes.last : nil
            let describes = last.map { isDescription(words, height: row.height, nameHeight: nameHeight, dish: $0, priced: price != nil) } ?? false
            if price == nil, !describes, isHeading(words, height: row.height, body: body, next: next) {
                section = titled(words); startedHere = false
                continue
            }
            if describes {
                let at = dishes.count - 1
                dishes[at].details = dishes[at].details.isEmpty ? words : dishes[at].details + " " + words
                if dishes[at].price == nil { dishes[at].price = price }
                continue
            }
            guard words.split(separator: " ").count <= 14 else { continue }
            var dish = named(words)
            dish.price = price; dish.section = section
            dishes.append(dish)
            nameHeight = row.height; startedHere = true
        }
    }

    /// Whether a line carries on from the dish above rather than starting a new one.
    private static func isDescription(_ words: String, height: Double, nameHeight: Double, dish: MenuDish, priced: Bool) -> Bool {
        let lower = words.first?.isLowercase == true
        let wrapped = ["and", "with", "or", "of", "in", "on", "a", "&"].contains { dish.details.lowercased().hasSuffix(" \($0)") } || dish.details.hasSuffix(",")
        if priced {
            // The price can be on the description's line instead of the name's.
            return dish.price == nil && dish.details.isEmpty && (lower || words.contains(",") || height < nameHeight * 0.88)
        }
        let joining = ["served", "comes", "choice of", "choose", "topped", "includes", "your choice"].contains { words.lowercased().hasPrefix($0) }
        return lower || wrapped || joining || words.contains(",") || height < nameHeight * 0.88 || words.hasSuffix(".")
            || words.split(separator: " ").count > 7
    }

    private static let headingWords: Set<String> = [
        "entree", "entrees", "entrée", "entrées", "starter", "starters", "appetisers", "appetizers", "main", "mains", "side", "sides", "dessert", "desserts", "sweet", "sweets",
        "drink", "drinks", "beverages", "beers", "wines", "cocktails", "spirits", "coffee", "tea", "kids", "children", "breakfast", "brunch", "lunch", "dinner", "menu",
        "pizzas", "pastas", "burgers", "salads", "soups", "curries", "sandwiches", "wraps", "tacos", "sushi", "grill", "seafood", "vegetarian", "specials", "snacks", "share",
        "sharing", "banquet", "noodles", "rice", "extras", "sauces", "plates", "tapas", "antipasti", "steaks", "toasties", "bowls",
    ]

    private static func isKnownHeading(_ words: String) -> Bool {
        let parts = words.lowercased().split { !$0.isLetter && $0 != "é" }.map(String.init).filter { $0 != "and" }
        guard (1...4).contains(parts.count) else { return false }
        if parts.allSatisfy(headingWords.contains) { return true }
        return parts.count == 1 ? headingWords.contains(parts[0]) || ["pizza", "pasta", "salad", "soup", "wine", "beer"].contains(parts[0])
            : parts.contains(where: headingWords.contains) && parts.contains { $0.hasSuffix("s") || ["from", "the", "to", "small", "large"].contains($0) }
    }

    private static func isHeading(_ words: String, height: Double, body: Double, next: Row?) -> Bool {
        if isKnownHeading(words) { return true }
        guard words.split(separator: " ").count <= 5, !words.contains(",") else { return false }
        // A dish printed big or in capitals has its description next; a heading has the next dish.
        let nextDescribes = next.map { row in
            let text = clean(splitPrice(row.text).words)
            return text.first?.isLowercase == true || text.contains(",") || row.height < height * 0.8 && height < body * 1.2
        } ?? false
        if nextDescribes { return false }
        if height >= body * 1.25 { return true }
        let letters = words.filter(\.isLetter)
        return !letters.isEmpty && letters.allSatisfy(\.isUppercase) && next.map { splitPrice($0.text).price != nil || $0.price != nil } ?? false
    }

    /// Add-ons offered under a dish: "Add chicken 6", "+ extra cheese".
    private static func isExtra(_ words: String) -> Bool {
        words.range(of: #"(?i)^(\+|add\b|extra\b|upgrade\b|make it\b|swap\b)"#, options: .regularExpression) != nil
    }

    /// Text on a menu that isn't food: contact details, surcharges, keys to the dietary letters.
    private static let noise = try! NSRegularExpression(pattern: #"""
        (?ix)
        \b0\d[\d\s-]{7,} | \b1[38]00\b | \d{4}\s\d{4}\b | www\. | https? | @ | \.com | \.au\b |
        surcharge | public\ holiday | prices?\ (include|are|subject) | \bgst\b | \bbyo\b | corkage | allerg | intoleran |
        please | ask\ (our|your|the) | wait\ ?staff | our\ staff | bookings? | book\ now | opening\ hours | \bopen\s(mon|tue|wed|thu|fri|sat|sun|daily|7) |
        follow\ us | instagram | facebook | gift\ (voucher|card) | split\ bills? | eftpos | fully\ licensed | \b(vic|nsw|qld|sa|wa|tas|act)\s\d{4}\b |
        ^\W*(v|gf|vg|df|n)\W*(=|-|:)\W*(vegetarian|vegan|gluten|dairy|nut) | ^page\s\d | ^\W*\w\W*$
        """#)

    private static func isNoise(_ text: String) -> Bool {
        noise.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    // MARK: Words on a line

    private static let price = try! NSRegularExpression(pattern: #"(?:^|\s)((?:[$£€]\s?|S(?=\d))?)(\d{1,3}(?:[.,:\-–]\d{1,2})?)(?:\s*(?:ea|each|pp|p/p))?\s*[-–/|+]?\s*$"#, options: .caseInsensitive)

    /// The number in a price as printed or misread: "5-5" is 5.50, but "12-18" is two sizes, so the first.
    private static func amount(_ digits: Substring) -> Double? {
        let parts = digits.split { "-–".contains($0) }
        if parts.count == 2 { return parts[1].count == 1 ? Double("\(parts[0]).\(parts[1])") : Double(parts[0]) }
        return Double(digits.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: ":", with: "."))
    }

    /// A line's words and the price at its end. With two prices ("12 / 18") the first, the smaller size, is kept.
    static func splitPrice(_ text: String) -> (words: String, price: Double?) {
        var words = text.replacingOccurrences(of: #"[.…_·]{2,}"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        var found: Double?
        while let match = price.firstMatch(in: words, range: NSRange(words.startIndex..., in: words)),
              let whole = Range(match.range, in: words), let sign = Range(match.range(at: 1), in: words), let digits = Range(match.range(at: 2), in: words),
              let value = amount(words[digits]) {
            // Without a currency sign, a small lone number is more likely part of the name.
            guard !words[sign].isEmpty || value >= 3 else { break }
            guard value > 0, value <= 500 else { break }
            found = value
            words = String(words[..<whole.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return (words, found)
    }

    /// The line without leaders, numbering or dietary letters.
    static func clean(_ text: String) -> String {
        var words = text.replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[.…_·]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\b(market price|mp)\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        words = words.replacingOccurrences(of: #"^(?:[•*\-–—]\s*|\d{1,3}[.)]\s+)"#, with: "", options: .regularExpression)
        // "Margherita (v)", "Pad Thai GF, DF": letters in capitals or brackets, one after another.
        let letters = #"(?:GFO?|DFO?|VGN?|VEG|VO|VE|NF|GFA|DFA|NGCI|V|N)"#
        while let range = words.range(of: #"(?:[\s,/|]+"# + letters + #"|\s*[\(\[](?i:"# + letters + #")(?:[\s,/]+(?i:"# + letters + #"))*[\)\]])[\s,/|]*$"#, options: .regularExpression) {
            words = String(words[..<range.lowerBound])
        }
        // A comma at the end stays: it says the description carries on to the next line.
        return words.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–—:|")))
    }

    /// A line as a dish: "Margherita - tomato, basil" splits at the dash, and a long line at its first comma.
    private static func named(_ words: String) -> MenuDish {
        for mark in [" - ", " – ", " — ", ": ", " | "] {
            if let range = words.range(of: mark) {
                let name = String(words[..<range.lowerBound]), rest = String(words[range.upperBound...])
                if name.contains(where: \.isLetter), rest.contains(where: \.isLetter) { return MenuDish(name: titled(name), details: rest) }
            }
        }
        if words.split(separator: " ").count > 7, let comma = words.firstIndex(of: ",") {
            return MenuDish(name: titled(String(words[..<comma])), details: words[words.index(after: comma)...].trimmingCharacters(in: .whitespaces))
        }
        return MenuDish(name: titled(words))
    }

    private static let keptCaps: Set<String> = ["BBQ", "BLT", "KFC", "IPA", "XO", "NY"]

    /// All-capital names in ordinary title case, so they read like the rest of the app.
    private static func titled(_ text: String) -> String {
        let letters = text.filter(\.isLetter)
        guard !letters.isEmpty, letters.allSatisfy(\.isUppercase) else { return text }
        return text.split(separator: " ").enumerated().map { index, word in
            if keptCaps.contains(String(word)) { return String(word) }
            let lower = word.lowercased()
            return index > 0 && ["and", "with", "of", "the", "in", "on", "or"].contains(lower) ? lower : lower.prefix(1).uppercased() + lower.dropFirst()
        }.joined(separator: " ")
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.sorted()[values.count / 2]
    }
}
