import SwiftUI
import FoundationModels

/// Find → Dietary needs: what to leave out of orders, Best choices, search and suggestions.
struct DietNeedsView: View {
    @Environment(AppStore.self) private var store
    @AppStorage(DietFilter.storageKey) private var raw = ""
    private var filter: DietFilter { DietFilter(raw: raw) }

    var body: some View {
        LeanrList {
            Section {
                ForEach(DietOption.meatOptions) { toggle($0) }
            } header: { Text("What you eat") } footer: {
                Text("No beef and No pork also leave out gelatine, which is made from either.")
            }
            Section {
                ForEach(DietOption.allergenOptions) { toggle($0, label: "No \($0.title.lowercased())") }
            } header: { Text("Allergens to avoid") } footer: {
                Text("Items that \"may contain\" an allergen are left out too.")
            }
            Section {
                let coverage = coverage
                ForEach(coverage, id: \.name) { row in
                    LabeledContent(row.name) {
                        Text(row.allergens > 0 ? "What's in it \(row.meat)% · allergens \(row.allergens)%" : "What's in it \(row.meat)%").monospacedDigit()
                    }.font(.roboto(.subheadline))
                }
            } header: { Text("What each restaurant says") } footer: {
                Text("Leanr only offers an item when the restaurant's own ingredient lists, descriptions, labels or allergen guides show it fits. Items they don't cover are left out rather than guessed. Kitchens are shared, so always tell the restaurant about an allergy. Your own foods are never filtered.")
            }
            if !filter.isEmpty {
                Section { Button("Clear all", role: .destructive) { raw = "" } }
            }
        }
        .navigationTitle("Dietary needs")
    }

    private func toggle(_ option: DietOption, label: String? = nil) -> some View {
        Toggle(label ?? option.title, isOn: Binding(
            get: { filter.options.contains(option) },
            set: { on in var next = filter; if on { next.options.insert(option) } else { next.options.remove(option) }; raw = next.raw }))
    }

    /// For each restaurant: the share of its items with known meat, and with published allergens.
    private var coverage: [(name: String, meat: Int, allergens: Int)] {
        store.catalog.chains.filter { $0.id != "mine" }.compactMap { chain in
            let foods = store.catalog.foods.filter { $0.chain == chain.id }
            guard !foods.isEmpty else { return nil }
            let meat = foods.filter { $0.diet?.meat != nil }.count, allergens = foods.filter { $0.diet?.al != nil }.count
            return (chain.name, Int((Double(meat) / Double(foods.count) * 100).rounded()), Int((Double(allergens) / Double(foods.count) * 100).rounded()))
        }.sorted { ($0.allergens, $0.meat, $1.name) > ($1.allergens, $1.meat, $0.name) }
    }
}

/// On a restaurant item's details: what meats and allergens are in it, and where that comes from.
struct DietSection: View {
    @Environment(AppStore.self) private var store
    let food: Food

    var body: some View {
        if food.chain != "mine", let info = food.isEveryday ? nil : food.diet ?? DietInfo() {
            Section {
                if let meat = info.meat {
                    let words = meat.map { $0 == "other" ? "other meat" : $0 }
                    LabeledContent("Meat", value: meat.isEmpty ? (info.isVegan ? "None · vegan" : "None · vegetarian") : words.joined(separator: ", ").capitalizedFirst)
                } else {
                    LabeledContent("Meat", value: "Not listed")
                }
                if let al = info.al {
                    LabeledContent("Contains", value: al.isEmpty ? "None of the major allergens" : al.map(DietOption.allergenName).joined(separator: ", ").capitalizedFirst)
                    if let may = info.may, !may.isEmpty {
                        LabeledContent("May contain", value: may.map(DietOption.allergenName).joined(separator: ", ").capitalizedFirst)
                    }
                } else {
                    LabeledContent("Allergens", value: "Not published")
                }
            } header: { Text("Dietary") } footer: {
                Text(sourceText(info) + " Kitchens are shared, so check with the restaurant about an allergy.")
            }
        }
    }

    private func sourceText(_ info: DietInfo) -> String {
        let owner = store.chainName(food.chain)
        switch info.src {
        case "ingredients": return "From \(owner.possessive) ingredient list."
        case "description": return "From \(owner.possessive) description of the item."
        case "labels": return "From \(owner.possessive) own vegetarian and allergen labels."
        case "name": return "Worked out from the item's name, which names what's in it."
        default: return "\(owner) doesn't say what's in this item, so dietary needs leave it out."
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Ask Leanr's answers: the question as an order search, what was understood, and the orders that fit.
struct AskLeanrView: View {
    @Environment(AppStore.self) private var store
    @State var question: String
    @State private var request: AskLeanr.Request?
    @State private var matches: [MealMatch] = []
    @State private var searching = true
    @State private var usedModel = false
    @State private var asked = ""

    var body: some View {
        LeanrList {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").foregroundStyle(.tint).accessibilityHidden(true)
                    TextField("Ask Leanr", text: $question, axis: .vertical).lineLimit(1...3).submitLabel(.search)
                        .onSubmit { asked = question }
                }
                if let request {
                    // What was understood, so a misreading is easy to spot and fix by rewording.
                    FlowLayout(spacing: 6) {
                        ForEach(request.understood, id: \.self) { part in
                            Text(part).font(.roboto(.caption, weight: .medium))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(.tint.opacity(0.12), in: Capsule())
                        }
                    }.accessibilityElement(children: .combine).accessibilityLabel("Understood: " + request.understood.joined(separator: ", "))
                }
            } footer: {
                Text(usedModel ? "Read with Apple Intelligence on this iPhone. The orders come from Leanr's menus." : "The orders come from Leanr's menus and the restaurants' published figures.")
            }
            if searching {
                Section { ProgressView("Finding orders…").frame(maxWidth: .infinity) }
            } else if matches.isEmpty {
                Section {
                    ContentUnavailableView("No orders fit", systemImage: "magnifyingglass",
                                           description: Text("Try more calories, less protein or another restaurant."))
                }
            } else {
                ForEach(Array(matches.prefix(10).enumerated()), id: \.element.id) { index, match in
                    Section {
                        // When protein wasn't asked for, there's no target to be short of.
                        OrderMatchCard(match: match, protein: request.flatMap { $0.said.contains(.protein) || $0.query.sort != "protein" ? $0.query.protein : nil })
                    } header: { if index == 0 { Text("\(min(matches.count, 10)) orders") } }
                }
            }
        }
        .navigationTitle("Ask Leanr").navigationBarTitleDisplayMode(.inline)
        .onAppear { if asked.isEmpty { asked = question } }
        .task(id: asked) { await answer(asked) }
    }

    private func answer(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        searching = true
        let names = Dictionary(store.catalog.chains.map { ($0.id, $0.name) }) { a, _ in a }
        let defaults = FindQuery(calories: store.goals.mealCal, protein: store.goals.mealProtein, diet: DietFilter.saved)
        var parsed = AskLeanr.parse(text, chainNames: names, defaults: defaults)
        usedModel = false
        if AskLeanrModel.isAvailable, let filled = await AskLeanrModel.fill(text, request: parsed, chainNames: names) {
            parsed = filled; usedModel = true
        }
        if parsed.usesRemaining {
            let left = Assistant.remaining(store.data, goals: store.goals)
            parsed.query.calories = max(0, left.calories ?? parsed.query.calories)
            parsed.query.protein = max(0, left.protein ?? parsed.query.protein)
            parsed.understood[0] = "What's left today: \(parsed.query.calories.rounded().number) Cal"
        }
        request = parsed
        let foods = store.orderFoods, query = parsed.query
        let result = await Task.detached(priority: .userInitiated) { MealFinder.find(foods, query: query) }.value
        guard !Task.isCancelled else { return }
        matches = result; searching = false
    }
}

/// Apple Intelligence's reading of a question, for what the rules in `AskLeanr` didn't find. It only fills in what was asked
/// for (numbers, restaurants, needs); the answers still come from the order finder.
enum AskLeanrModel {
    static var isAvailable: Bool {
        guard #available(iOS 26.0, *) else { return false }
        return SystemLanguageModel.default.isAvailable
    }

    @available(iOS 26.0, *)
    @Generable(description: "What someone wants from a fast-food order")
    struct Asked {
        @Guide(description: "The most calories they want, as a number. 0 if they didn't say.")
        var calories: Int
        @Guide(description: "The grams of protein they want, as a number. 0 if they didn't say.")
        var protein: Int
        @Guide(description: "Restaurants or chains they named, as written. Empty if none.", .maximumCount(4))
        var restaurants: [String]
        @Guide(description: "How many items in the order: 1, 2 or 3. 0 if they didn't say.")
        var items: Int
        @Guide(description: "They want no meat at all.")
        var vegetarian: Bool
        @Guide(description: "They want nothing from animals.")
        var vegan: Bool
        @Guide(description: "They don't eat beef.")
        var noBeef: Bool
        @Guide(description: "They don't eat pork.")
        var noPork: Bool
        @Guide(description: "Allergens they need to avoid, from: gluten, milk, egg, soy, sesame, peanut, treenut, fish, shellfish.", .maximumCount(9))
        var allergens: [String]
        @Guide(description: "They want as much protein as possible.")
        var mostProtein: Bool
        @Guide(description: "They want as few calories as possible.")
        var fewestCalories: Bool
    }

    static func fill(_ text: String, request: AskLeanr.Request, chainNames: [String: String]) async -> AskLeanr.Request? {
        guard #available(iOS 26.0, *) else { return nil }
        let session = LanguageModelSession(instructions: """
            You read what someone wants from a fast-food order so a search can find it. Only report what they said. \
            Never suggest foods and never estimate nutrition.
            """)
        guard let asked = try? await session.respond(to: "What do they want? \"\(text)\"", generating: Asked.self).content else { return nil }
        var out = request, q = out.query
        let lower = text.lowercased()
        // A number only counts if it's in the question: the model sometimes fills in a "typical" one.
        func said(_ n: Int) -> Bool { lower.range(of: #"\b\#(n)\b"#, options: .regularExpression) != nil }
        // The rules' reading wins wherever they found something; the model only fills gaps.
        if !out.said.contains(.calories), (100...6000).contains(asked.calories), said(asked.calories) {
            q.calories = Double(asked.calories); out.said.insert(.calories); out.usesRemaining = false
        }
        if !out.said.contains(.protein), (1...300).contains(asked.protein), said(asked.protein) { q.protein = Double(asked.protein); out.said.insert(.protein) }
        if !out.said.contains(.chains) {
            let found = Set(asked.restaurants.compactMap { MealPhoto.chain(for: $0, chainNames: chainNames) })
            if !found.isEmpty { q.chains = found; out.said.insert(.chains) }
        }
        if !out.said.contains(.items), (1...3).contains(asked.items),
           lower.range(of: #"\b(items?|things?|one|two|three|single|side|sides|combo)\b|\b[123]\b"#, options: .regularExpression) != nil {
            q.maxItems = asked.items; out.said.insert(.items)
        }
        if !out.said.contains(.sort) {
            if asked.mostProtein && !out.said.contains(.protein) { q.sort = "protein" } else if asked.fewestCalories { q.sort = "lean" }
        }
        var needs: [DietOption] = []
        if asked.vegetarian { needs.append(.vegetarian) }
        if asked.vegan { needs.append(.vegan) }
        if asked.noBeef { needs.append(.noBeef) }
        if asked.noPork { needs.append(.noPork) }
        // Allergens only when the question talks about allergies or "free" foods, so none are imagined.
        if lower.range(of: #"allerg|intoleran|free|coeliac|celiac|gluten|dairy|lactose|nut|egg|soy|sesame|fish|shellfish|seafood"#, options: .regularExpression) != nil {
            needs += asked.allergens.compactMap { DietOption(rawValue: $0.lowercased().replacingOccurrences(of: " ", with: "")) }.filter(\.isAllergen)
        }
        q.diet.options.formUnion(needs)
        out.query = q
        let halal = out.understood.last.map { $0.hasPrefix("Halal") } ?? false
        out.understood = AskLeanr.summary(out, chainNames: chainNames) + (halal ? ["Halal isn't checked, only no pork"] : [])
        return out
    }
}

/// Lays views out in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(proposal.width ?? .infinity, subviews)
        let width = rows.map { row in row.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, row.count - 1)) }.max() ?? 0
        let height = rows.map { $0.map(\.height).max() ?? 0 }.reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: min(width, proposal.width ?? width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY, index = 0
        for row in rows(bounds.width, subviews) {
            var x = bounds.minX
            for size in row {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing; index += 1
            }
            y += (row.map(\.height).max() ?? 0) + spacing
        }
    }

    private func rows(_ width: CGFloat, _ subviews: Subviews) -> [[CGSize]] {
        var rows: [[CGSize]] = [[]], used: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if !rows[rows.count - 1].isEmpty && used + spacing + size.width > width { rows.append([]); used = 0 }
            used += (rows[rows.count - 1].isEmpty ? 0 : spacing) + size.width
            rows[rows.count - 1].append(CGSize(width: min(size.width, width), height: size.height))
        }
        return rows
    }
}
