import Foundation

/// Forgiving food search: every word must appear in the text, allowing a typo or two
/// ("mchicken" finds "McChicken", "nugets" finds "Nuggets"). Lower scores are closer matches.
enum FoodSearch {
    /// A food's searchable words, worked out once so each keystroke only compares.
    struct Prepared: Sendable {
        let candidates: [String]
        let letters: [[Int]]
        init(_ text: String) {
            let parts = FoodSearch.tokens(text)
            // Adjacent pairs let "mc chicken" and "mcchicken" find each other.
            candidates = parts + parts.indices.dropLast().map { parts[$0] + parts[$0 + 1] }
            letters = candidates.map(FoodSearch.letters)
        }
    }

    struct Query: Sendable {
        let words: [String]
        let letters: [[Int]]
        init(_ text: String) {
            words = FoodSearch.tokens(text)
            letters = words.map(FoodSearch.letters)
        }
        var isEmpty: Bool { words.isEmpty }
    }

    /// One number per character, so comparing words is quick but still counts what people see as a letter.
    static func letters(_ word: String) -> [Int] {
        word.map { character in
            let scalars = character.unicodeScalars
            return scalars.count == 1 ? Int(scalars[scalars.startIndex].value) : character.hashValue
        }
    }

    /// Prepared words for every text seen, kept while the app runs. Keyed by the text itself, so a renamed food is simply prepared again.
    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String: Prepared] = [:]
        func prepared(_ text: String) -> Prepared {
            if let hit = lock.withLock({ items[text] }) { return hit }
            let made = Prepared(text)
            lock.withLock { items[text] = made }
            return made
        }
    }
    private static let cache = Cache()
    static func prepared(_ text: String) -> Prepared { cache.prepared(text) }

    static func score(_ text: String, query: String) -> Int? { score(Prepared(text), query: Query(query)) }

    static func score(_ item: Prepared, query: Query) -> Int? {
        var total = 0
        for (word, letters) in zip(query.words, query.letters) {
            if item.candidates.contains(where: { $0.contains(word) }) { continue }
            let allowed = letters.count >= 7 ? 2 : letters.count >= 4 ? 1 : 0
            guard allowed > 0 else { return nil }
            var best = allowed + 1
            for candidate in item.letters {
                // People rarely mistype the first letter, so a different first letter costs extra.
                let penalty = candidate.first == letters.first ? 0 : 1
                let limit = best - 1 - penalty
                guard limit >= 0, let found = closeness(letters, candidate, limit: limit) else { continue }
                best = found + penalty
            }
            guard best <= allowed else { return nil }
            total += best
        }
        return total
    }

    /// The fewest edits between the word and the candidate, or the start of the candidate, so a half-typed word still matches.
    /// Nil when that's more than the limit, which lets most comparisons stop after a letter or two.
    static func closeness(_ word: [Int], _ candidate: [Int], limit: Int) -> Int? {
        guard !word.isEmpty, !candidate.isEmpty else { return max(word.count, candidate.count) <= limit ? max(word.count, candidate.count) : nil }
        var row = Array(0...candidate.count)
        for i in 1...word.count {
            var previous = row[0]; row[0] = i
            var smallest = i
            for j in 1...candidate.count {
                let current = row[j]
                row[j] = word[i - 1] == candidate[j - 1] ? previous : min(previous, row[j], row[j - 1]) + 1
                smallest = min(smallest, row[j])
                previous = current
            }
            // Later rows never get smaller than this one's smallest value.
            if smallest > limit { return nil }
        }
        // The last row holds the distance to each prefix of the candidate.
        let lengths = (max(1, word.count - 1)...(word.count + 1)).map { min($0, candidate.count) } + [candidate.count]
        let best = lengths.map { row[$0] }.min() ?? .max
        return best <= limit ? best : nil
    }

    /// What the Best choices list is showing.
    struct Browse: Equatable, Sendable {
        var search = "", chain = "all", category = "all", sort = "density"
    }

    /// Foods for the Best choices list: exact matches first, then typos from closest to furthest; each group in the chosen order.
    /// Gives up early, returning nothing, if the task is cancelled.
    static func browse(_ foods: [Food], chainNames: [String: String], request: Browse) -> [Food] {
        let query = Query(request.search)
        var scores: [String: Int] = [:]
        var rows = foods.filter { food in
            guard !Task.isCancelled, request.chain == "all" || food.chain == request.chain,
                  request.category == "all" || food.cat == request.category, food.cat != "swap" else { return false }
            guard !query.isEmpty else { return true }
            guard let score = score(prepared(food.name + " " + (chainNames[food.chain] ?? "My foods")), query: query) else { return false }
            scores[food.id] = score
            return true
        }
        guard !Task.isCancelled else { return [] }
        if request.sort == "value" { rows = rows.filter { ($0.price ?? 0) > 0 } }
        rows.sort { a,b in
            let scoreA = scores[a.id] ?? 0, scoreB = scores[b.id] ?? 0
            if scoreA != scoreB { return scoreA < scoreB }
            switch request.sort {
            case "protein": return a.p > b.p
            case "calories": return a.cal < b.cal
            case "value": return a.p / (a.price ?? 1) > b.p / (b.price ?? 1)
            case "name": return a.name < b.name
            default: return a.p / max(a.cal,1) > b.p / max(b.cal,1)
            }
        }
        return rows
    }

    /// Items that match, closest first; ties keep their original order.
    static func filter<T>(_ items: [T], query: String, text: (T) -> String) -> [T] {
        let query = Query(query)
        guard !query.isEmpty else { return items }
        return items.enumerated()
            .compactMap { index, item in score(Prepared(text(item)), query: query).map { (index, $0, item) } }
            .sorted { ($0.1, $0.0) < ($1.1, $1.0) }
            .map(\.2)
    }

    static func tokens(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
            .split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}

/// The last few searches, newest first.
enum RecentSearches {
    static let storageKey = "recentFoodSearches"
    static func list(_ stored: String) -> [String] { stored.split(separator: "\n").map(String.init) }
    static func adding(_ query: String, to stored: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return stored }
        let rest = list(stored).filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        return ([trimmed] + rest).prefix(8).joined(separator: "\n")
    }
}
