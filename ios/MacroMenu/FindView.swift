import SwiftUI

struct FindView: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav
    @State private var query = FindQuery()
    @State private var matches: [MealMatch] = []
    @State private var searching = false
    @State private var initialized = false
    @State private var searchID = UUID()
    var body: some View {
        LeanrList {
            Section {
                NavigationLink {
                    BrowseView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 34, height: 34)
                            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Best choices").font(.roboto(.headline))
                            Text("Browse foods ranked by protein, calories or value").font(.roboto(.caption)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("An order that fits.").font(.display(.title))
                    Text("Choose your calories, protein and budget. Find combinations from one restaurant.").foregroundStyle(.secondary)
                }.padding(.top, 6)
                HStack(spacing: 10) {
                    StatField(title: "Calories up to", unit: "Cal", value: $query.calories)
                    StatField(title: "Protein target", unit: "g", value: $query.protein)
                }
                .listRowSeparator(.hidden)
                HStack {
                    Picker("Items per order", selection: $query.maxItems) { ForEach(1...3, id: \.self) { Text("Up to \($0) item\($0 == 1 ? "" : "s")").tag($0) } }
                    Spacer()
                    Picker("Rank by", selection: $query.sort) {
                        Text("Closest fit").tag("fit"); Text("Lowest calories").tag("lean"); Text("Most protein").tag("protein")
                        Text("Cheapest").tag("cheap"); Text("Protein per dollar").tag("value")
                    }
                }.pickerStyle(.menu).labelsHidden()
                DisclosureGroup("Budget & macro limits") {
                    OptionalNumberField(title: "Budget (AUD)", value: $query.budget, places: 2)
                    OptionalNumberField(title: "Carbs up to (g)", value: $query.carbs)
                    OptionalNumberField(title: "Fat up to (g)", value: $query.fat)
                    Text("Price and macro filters exclude items with missing values.").font(.roboto(.caption)).foregroundStyle(.secondary)
                }
                Button { useRemaining() } label: { Label("Use what's left of today's targets", systemImage: "arrow.down.forward.circle") }
                    .font(.roboto(.subheadline))
            }
            Section("Restaurants") {
                ChipRow {
                    Chip(title: "All", selected: query.chains.isEmpty) { query.chains = [] }
                    ForEach(store.catalog.chains) { chain in
                        Chip(title: chain.name, selected: query.chains.contains(chain.id)) {
                            if query.chains.contains(chain.id) { query.chains.remove(chain.id) } else { query.chains.insert(chain.id) }
                        }
                    }
                }
            }
            if searching || matches.isEmpty {
                Section(searching ? "Finding combinations…" : "No suggestions") {
                    if searching { ProgressView().frame(maxWidth: .infinity) }
                    else { ContentUnavailableView("No matching orders", systemImage: "magnifyingglass", description: Text("Try more calories, a wider budget or different restaurants.")) }
                }
            } else {
                ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(store.chainName(match.chain).uppercased()).font(.roboto(.caption, weight: .semibold)).foregroundStyle(.secondary)
                                Spacer()
                                let met = match.total.p >= query.protein
                                Text(met ? "Protein target met" : "\((query.protein - match.total.p).number) g short")
                                    .font(.roboto(.caption, weight: .medium)).foregroundStyle(met ? .green : .orange)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background((met ? Color.green : Color.orange).opacity(0.15), in: Capsule())
                            }
                            NavigationLink { OrderDetailView(match: match) } label: {
                                Text(match.items.map { $0.food.name }.joined(separator: " + ")).font(.roboto(.headline))
                            }
                            NutritionView(total: match.total, details: false)
                            HStack {
                                Button("Add to meal") { store.add(match.items) }.buttonStyle(.borderedProminent)
                                ShareLink(item: mealText("Suggested order", match.items)) { Image(systemName: "square.and.arrow.up") }.buttonStyle(.bordered).accessibilityLabel("Share order")
                            }
                        }.padding(.vertical, 6)
                    } header: {
                        if index == 0 { Text("\(matches.count) suggested orders") }
                    }
                }
            }
        }
        .navigationTitle("Find a meal")
        .toolbar { NavigationLink { SourcesView() } label: { Image(systemName: "info.circle") }.accessibilityLabel("Menu sources") }
        .onAppear { if !initialized { query.calories = store.goals.mealCal; query.protein = store.goals.mealProtein; initialized = true } }
        .onChange(of: nav.findChain, initial: true) { if let chain = nav.findChain { query.chains = [chain]; nav.findChain = nil } }
        .onChange(of: store.data.foods) { searchID = UUID() }
        .task(id: query) { await search() }
        .task(id: searchID) { await search() }
    }
    private func useRemaining() {
        let total = Nutrition((store.data.logs[dayKey(Date())] ?? []).flatMap(\.items))
        query.calories = max(0, (store.goals.values["cal"] ?? 2200) - total.cal)
        query.protein = max(0, (store.goals.values["p"] ?? 150) - total.p)
    }
    private func search() async {
        searching = true
        let foods = store.foods, request = query
        let work = Task.detached(priority: .userInitiated) { MealFinder.find(foods, query: request) }
        let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        if !Task.isCancelled { matches = result; searching = false }
    }
}

struct BrowseView: View {
    @Environment(AppStore.self) private var store
    @State private var search = ""
    @State private var chain = "all"
    @State private var category = "all"
    @State private var sort = "density"
    @AppStorage(RecentSearches.storageKey) private var recent = ""
    var pick: ((Portion) -> Void)?
    static let categories = [("all", "All items"), ("main", "Mains"), ("breakfast", "Breakfast"), ("side", "Sides"), ("drink", "Drinks"), ("sweet", "Desserts"), ("extra", "Extras")]
    var rows: [Food] {
        // Exact matches first, then typos from closest to furthest; each group in the chosen order.
        var scores: [String: Int] = [:]
        var rows = store.foods.filter { food in
            guard (chain == "all" || food.chain == chain) && (category == "all" || food.cat == category) && food.cat != "swap" else { return false }
            guard let score = FoodSearch.score(food.name + " " + store.chainName(food.chain), query: search) else { return false }
            scores[food.id] = score
            return true
        }
        if sort == "value" { rows = rows.filter { ($0.price ?? 0) > 0 } }
        rows.sort { a,b in
            let scoreA = scores[a.id] ?? 0, scoreB = scores[b.id] ?? 0
            if scoreA != scoreB { return scoreA < scoreB }
            switch sort {
            case "protein": return a.p > b.p
            case "calories": return a.cal < b.cal
            case "value": return a.p / (a.price ?? 1) > b.p / (b.price ?? 1)
            case "name": return a.name < b.name
            default: return a.p / max(a.cal,1) > b.p / max(b.cal,1)
            }
        }
        return rows
    }
    var body: some View {
        LeanrList {
            Section {
                ChipRow {
                    Chip(title: "All restaurants", selected: chain == "all") { chain = "all" }
                    ForEach(store.catalog.chains) { item in Chip(title: item.name, selected: chain == item.id) { chain = chain == item.id ? "all" : item.id } }
                }
                ChipRow {
                    ForEach(BrowseView.categories, id: \.0) { tag, label in Chip(title: label, selected: category == tag) { category = tag } }
                }
            }
            Section {
                if rows.isEmpty { ContentUnavailableView.search(text: search) }
                ForEach(rows) { food in
                    NavigationLink {
                        FoodDetailView(food: food, pick: pick).onAppear { recent = RecentSearches.adding(search, to: recent) }
                    } label: { FoodRow(food: food) }
                }
            } header: {
                HStack {
                    Text("\(rows.count) foods")
                    Spacer()
                    Picker("Sort", selection: $sort) {
                        Text("Protein per calorie").tag("density"); Text("Most protein").tag("protein"); Text("Lowest calories").tag("calories")
                        Text("Protein per dollar").tag("value"); Text("Name").tag("name")
                    }.pickerStyle(.menu).labelsHidden().textCase(nil).font(.roboto(.subheadline)).fixedSize()
                }
            }
        }.searchable(text: $search, prompt: "Food or restaurant")
            .searchSuggestions {
                if search.isEmpty && !recent.isEmpty {
                    Section("Recent searches") {
                        ForEach(RecentSearches.list(recent), id: \.self) { text in
                            Label(text, systemImage: "clock.arrow.circlepath").searchCompletion(text)
                        }
                        Button("Clear recent searches", role: .destructive) { recent = "" }
                    }
                }
            }
            .onSubmit(of: .search) { recent = RecentSearches.adding(search, to: recent) }
            .navigationTitle(pick == nil ? "Best choices" : "Choose a food")
            .toolbar { if pick == nil { NavigationLink { SourcesView() } label: { Image(systemName: "info.circle") } } }
    }
}
