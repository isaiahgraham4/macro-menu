import Foundation

/// Forgiving food search: every word must appear in the text, allowing a typo or two
/// ("mchicken" finds "McChicken", "nugets" finds "Nuggets"). Lower scores are closer matches.
enum FoodSearch {
    static func score(_ text: String, query: String) -> Int? {
        let words = tokens(query)
        guard !words.isEmpty else { return 0 }
        let parts = tokens(text)
        // Adjacent pairs let "mc chicken" and "mcchicken" find each other.
        let joined = parts.indices.dropLast().map { parts[$0] + parts[$0 + 1] }
        let candidates = parts + joined
        var total = 0
        for word in words {
            if candidates.contains(where: { $0.contains(word) }) { continue }
            let allowed = word.count >= 7 ? 2 : word.count >= 4 ? 1 : 0
            guard allowed > 0 else { return nil }
            let best = candidates.map { candidate in
                // Compare with the whole word and with its start, so a half-typed word still matches.
                // People rarely mistype the first letter, so a different first letter costs extra.
                let distances = (max(1, word.count - 1)...(word.count + 1)).map { length in
                    distance(word, String(candidate.prefix(length)))
                } + [distance(word, candidate)]
                return (distances.min() ?? .max) + (candidate.first == word.first ? 0 : 1)
            }.min() ?? .max
            guard best <= allowed else { return nil }
            total += best
        }
        return total
    }

    /// Items that match, closest first; ties keep their original order.
    static func filter<T>(_ items: [T], query: String, text: (T) -> String) -> [T] {
        guard !tokens(query).isEmpty else { return items }
        return items.enumerated()
            .compactMap { index, item in score(text(item), query: query).map { (index, $0, item) } }
            .sorted { ($0.1, $0.0) < ($1.1, $1.0) }
            .map(\.2)
    }

    static func tokens(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
            .split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// Levenshtein edit distance.
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var row = Array(0...b.count)
        for i in 1...a.count {
            var previous = row[0]; row[0] = i
            for j in 1...b.count {
                let current = row[j]
                row[j] = a[i - 1] == b[j - 1] ? previous : min(previous, row[j], row[j - 1]) + 1
                previous = current
            }
        }
        return row[b.count]
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
