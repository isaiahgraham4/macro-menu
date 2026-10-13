import SwiftUI

/// One food named by a photo, a sentence or a recipe line, the Leanr foods that match it, and how much to use.
struct FoodMatchRow: Identifiable {
    let id = UUID()
    /// What was seen or written, for the header.
    var title: String
    var matches: [Food]
    /// The match to use, or nil to leave this one out.
    var chosen: String?
    var quantity: Double
    /// The words, so the amount can be worked out again when another match is chosen.
    var phrase: FoodPhrase?
    /// False when the amount is a guess that should be checked.
    var sure = true
    /// Said above the picker when nothing is chosen.
    var unchosenNote: String?
    var food: Food? { matches.first { $0.id == chosen } }
    var portion: Portion? { food.map { Portion(food: $0, quantity: quantity) } }

    /// A row for typed words or a recipe line, with the likely match ticked and its amount worked out.
    /// With `raw`, an uncooked version comes first, since recipes weigh meat and vegetables before cooking.
    static func make(_ phrase: FoodPhrase, title: String, in foods: [Food], chainNames: [String: String], preselect: Bool = true, raw: Bool = false) -> FoodMatchRow {
        var matches = MealPhoto.matches(for: phrase.seen, in: foods, chainNames: chainNames, limit: raw ? 6 : 4)
        if raw, let index = matches.firstIndex(where: { FoodSearch.tokens($0.name).contains("raw") }) {
            matches.insert(matches.remove(at: index), at: 0)
        }
        matches = Array(matches.prefix(4))
        let chosen = preselect ? FoodPhrase.preselected(from: matches, for: phrase, chainNames: chainNames) : nil
        var row = FoodMatchRow(title: title.prefix(1).uppercased() + title.dropFirst(), matches: matches, chosen: chosen?.id, quantity: 1, phrase: phrase,
                               unchosenNote: phrase.brand == nil
                                ? "Several places have this. Pick the one you had."
                                : "Nothing from \(phrase.brand ?? "there") matched. Pick the closest, or search for it.")
        row.updateAmount()
        return row
    }

    /// Sets the amount from the words for the chosen match.
    mutating func updateAmount() {
        guard let phrase, let food else { return }
        let worked = phrase.servings(of: food)
        quantity = worked.servings; sure = worked.sure
    }
}

/// A section per row: pick the match (or leave it out), set the servings, or search for something else.
struct FoodMatchSections: View {
    @Environment(AppStore.self) private var store
    @Binding var rows: [FoodMatchRow]
    @State private var searching: FoodMatchRow.ID?

    var body: some View {
        ForEach($rows) { $row in
            Section {
                if row.matches.isEmpty {
                    Text("Not in Leanr yet. Search for something close, or leave it out.").foregroundStyle(.secondary)
                } else {
                    if row.chosen == nil, let note = row.unchosenNote {
                        Text(note).font(.roboto(.caption)).foregroundStyle(.secondary)
                    }
                    Picker("Use", selection: $row.chosen) {
                        ForEach(row.matches) { food in Text(food.name).tag(Optional(food.id)) }
                        Text("Leave it out").tag(String?.none)
                    }
                    .onChange(of: row.chosen) { row.updateAmount() }
                    if let food = row.food {
                        NumberField(title: "Servings", value: $row.quantity, places: 2, spokenTitle: "Servings of \(food.name)")
                        Text("\(store.chainName(food.chain)) · \(food.serve.isEmpty ? "1 serving" : food.serve) each · \(Nutrition([Portion(food: food, quantity: row.quantity)]).cal.rounded().number) Cal")
                            .font(.roboto(.caption)).foregroundStyle(.secondary)
                        if !row.sure {
                            Text("Check the amount: Leanr couldn't turn \"\(row.phrase?.original ?? row.title)\" into servings of this food.")
                                .font(.roboto(.caption)).foregroundStyle(.orange)
                        }
                    }
                }
                Button("Search for it instead", systemImage: "magnifyingglass") { searching = row.id }
            } header: { Text(row.title) }
        }
        .sheet(item: Binding(get: { searching.map(Target.init) }, set: { searching = $0?.id })) { target in
            NavigationStack {
                BrowseView(pick: { portion in
                    if let index = rows.firstIndex(where: { $0.id == target.id }) {
                        rows[index].matches.removeAll { $0.id == portion.food.id }
                        rows[index].matches.insert(portion.food, at: 0)
                        rows[index].chosen = portion.food.id
                        rows[index].quantity = portion.quantity
                        rows[index].sure = true
                    }
                    searching = nil
                }, pickTitle: "Use this", initialSearch: rows.first { $0.id == target.id }.map { $0.phrase?.name ?? $0.title } ?? "")
                .toolbar { Button("Done") { searching = nil } }
            }
        }
    }

    private struct Target: Identifiable { let id: FoodMatchRow.ID }
}

extension AppStore {
    /// Restaurant names by ID, with everyday foods, for matching.
    var chainNames: [String: String] {
        Dictionary(catalog.chains.map { ($0.id, $0.name) }) { a, _ in a }.merging([Food.everyday: chainName(Food.everyday)]) { a, _ in a }
    }
}
