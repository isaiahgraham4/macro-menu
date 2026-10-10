import SwiftUI

struct FindView: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav
    @Environment(LocationStore.self) private var location
    @State private var query = FindQuery()
    @State private var matches: [MealMatch] = []
    @State private var searching = false
    @State private var initialized = false
    @State private var searchID = UUID()
    var body: some View {
        LeanrList {
            Section {
                NavigationLink {
                    BrowseView(startSearching: true)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 34, height: 34)
                            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Search foods").font(.roboto(.headline))
                            Text("Macros for menu items, everyday foods and packaged products").font(.roboto(.caption)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
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
                            Text("Browse foods ranked by protein or calories").font(.roboto(.caption)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("An order that fits.").font(.display(.title))
                    Text("Choose your calories and protein. Find combinations from one restaurant.").foregroundStyle(.secondary)
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
                    }
                }.pickerStyle(.menu).labelsHidden()
                DisclosureGroup("Macro limits") {
                    OptionalNumberField(title: "Carbs up to (g)", value: $query.carbs)
                    OptionalNumberField(title: "Fat up to (g)", value: $query.fat)
                    Text("Macro limits leave out items with missing values.").font(.roboto(.caption)).foregroundStyle(.secondary)
                }
                Button { useRemaining() } label: { Label("Use what's left of today's targets", systemImage: "arrow.down.forward.circle") }
                    .font(.roboto(.subheadline))
            }
            Section {
                ChipRow {
                    Chip(title: "All", selected: query.chains.isEmpty) { query.chains = [] }
                    ForEach(store.catalog.chains) { chain in
                        Chip(title: chain.name, selected: query.chains.contains(chain.id)) {
                            if query.chains.contains(chain.id) { query.chains.remove(chain.id) } else { query.chains.insert(chain.id) }
                        }
                    }
                }
            } header: { Text("Restaurants") }
            if searching || matches.isEmpty {
                Section(searching ? "Finding combinations…" : "No suggestions") {
                    if searching { ProgressView().frame(maxWidth: .infinity) }
                    else { ContentUnavailableView("No matching orders", systemImage: "magnifyingglass", description: Text("Try more calories or different restaurants.")) }
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
                            NearestPlaceLine(chain: match.chain)
                            NutritionView(total: match.total, details: false)
                            HStack {
                                let name = match.items.map(\.food.name).joined(separator: " + ")
                                Button("Log it") { store.logNow(match.items, name: name) }.buttonStyle(.borderedProminent)
                                    .contextMenu { YesterdayMenu { store.logNow(match.items, name: name, mealTime: $0, yesterday: true) } }
                                Button("Add to meal") { store.add(match.items) }.buttonStyle(.bordered)
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
        .task(id: SearchKey(query: query, refresh: searchID)) { await search() }
        // The closest restaurant of each chain, once location is allowed (it's never asked for here).
        .task(id: location.location?.timestamp) {
            if location.isAuthorized { await location.load(Array(Set(matches.map(\.chain)))) }
        }
    }
    private struct SearchKey: Equatable { var query: FindQuery; var refresh: UUID }
    private func useRemaining() {
        let total = Nutrition((store.data.logs[dayKey(Date())] ?? []).flatMap(\.items))
        query.calories = max(0, (store.goals.values["cal"] ?? 2200) - total.cal)
        query.protein = max(0, (store.goals.values["p"] ?? 150) - total.p)
    }
    private func search() async {
        searching = true
        let foods = store.orderFoods, request = query
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
    /// What choosing a food does, for the button on its details, e.g. "Log to Lunch".
    var pickTitle = "Use this portion"
    /// What the "+" on a row does, for VoiceOver.
    var quickAddLabel = "Log"
    /// Opens with the keyboard up, for the Search foods row.
    var startSearching = false
    @State private var searchShown = false
    /// Bumped by the keyboard's Search key when nothing on a menu matches, to search packaged foods instead.
    @State private var searchPackaged = 0
    /// The Search key was pressed before the menu results were ready; decide once they are.
    @State private var submitted = false
    static let categories = [("all", "All items"), ("main", "Mains"), ("breakfast", "Breakfast"), ("side", "Sides"), ("drink", "Drinks"), ("sweet", "Desserts"), ("extra", "Extras")]
    /// Where the "+" on a row logs to, when nothing else is choosing the food.
    @State private var yesterday = false
    @State private var meal = MealTime.suggested()
    @State private var rows: [Food] = []
    /// The request the rows were worked out for; nil until the first list is ready.
    @State private var shown: FoodSearch.Browse?
    private var request: FoodSearch.Browse { .init(search: search, chain: chain, category: category, sort: sort) }
    /// Also redo the list when your own foods change or the menu loads.
    private struct Key: Equatable { var request: FoodSearch.Browse; var custom: [Food]; var catalog: String }

    private func update(_ request: FoodSearch.Browse) async {
        // Wait for a pause in typing so each keystroke doesn't start a new search.
        if let shown, shown.search != request.search, !request.search.isEmpty { try? await Task.sleep(for: .milliseconds(120)) }
        guard !Task.isCancelled else { return }
        let foods = store.foods
        let names = Dictionary(store.catalog.chains.map { ($0.id, $0.name) }) { a, _ in a }.merging([Food.everyday: store.chainName(Food.everyday)]) { a, _ in a }
        let work = Task.detached(priority: .userInitiated) { FoodSearch.browse(foods, chainNames: names, request: request) }
        let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        if !Task.isCancelled {
            rows = result; shown = request
            if submitted { submitted = false; if result.isEmpty { searchPackaged += 1 } }
        }
    }

    /// One serving, without opening the food: handed to whoever is choosing, or logged to today.
    private func quickAdd(_ food: Food) {
        recent = RecentSearches.adding(shown?.search ?? search, to: recent)
        if let pick { pick(Portion(food: food)) } else { store.logNow([Portion(food: food)], name: food.name, mealTime: meal, yesterday: yesterday) }
    }

    var body: some View {
        LeanrList {
            if pick == nil {
                Section {
                    LogTargetPicker(yesterday: $yesterday, meal: $meal)
                } footer: { Text("Tap + on a food to log it there. Pick Yesterday for something you forgot.") }
            }
            Section {
                ChipRow {
                    Chip(title: "All", selected: chain == "all") { chain = "all" }
                    Chip(title: "Everyday foods", selected: chain == Food.everyday) { chain = chain == Food.everyday ? "all" : Food.everyday }
                    ForEach(store.catalog.chains) { item in Chip(title: item.name, selected: chain == item.id) { chain = chain == item.id ? "all" : item.id } }
                }
                ChipRow {
                    ForEach(BrowseView.categories, id: \.0) { tag, label in Chip(title: label, selected: category == tag) { category = tag } }
                }
            }
            if search.isEmpty && chain == "all" && category == "all" {
                let pinned = store.pinnedFoods
                if !pinned.isEmpty {
                    Section {
                        ForEach(pinned) { food in
                            NavigationLink { FoodDetailView(food: food, pick: pick, pickTitle: pickTitle, logYesterday: yesterday, logMeal: pick == nil ? meal : nil) } label: {
                                FoodRow(food: food, quickAdd: { quickAdd(food) }, quickAddLabel: quickAddLabel)
                            }
                            .contextMenu { PinButton(food: food) }
                            .swipeActions { Button("Unpin", systemImage: "pin.slash") { store.togglePin(food) }.tint(.orange) }
                        }
                    } header: { Label("Pinned", systemImage: "pin.fill") }
                }
                // Pinned foods already sit above, so they don't repeat here.
                let recentFoods = QuickLog.recentFoods(logs: store.data.logs).filter { food in !pinned.contains { $0.id == food.id } }
                if !recentFoods.isEmpty {
                    Section {
                        ForEach(recentFoods) { food in
                            NavigationLink { FoodDetailView(food: food, pick: pick, pickTitle: pickTitle, logYesterday: yesterday, logMeal: pick == nil ? meal : nil) } label: {
                                FoodRow(food: food, quickAdd: { quickAdd(food) }, quickAddLabel: quickAddLabel)
                            }
                            .contextMenu { PinButton(food: food) }
                        }
                    } header: { Text("Recently logged") } footer: {
                        if pinned.isEmpty { Text("Touch and hold a food to pin it here, so your regulars stay at the top.") }
                    }
                }
            }
            PackagedFoodsSection(search: search, trigger: searchPackaged, pick: pick, pickTitle: pickTitle, logYesterday: yesterday, logMeal: meal)
            Section {
                if shown == request && rows.isEmpty { ContentUnavailableView("No menu matches", systemImage: "magnifyingglass", description: Text("Search packaged foods above, or check the spelling.")) }
                ForEach(rows) { food in
                    NavigationLink {
                        FoodDetailView(food: food, pick: pick, pickTitle: pickTitle, logYesterday: yesterday, logMeal: pick == nil ? meal : nil).onAppear { recent = RecentSearches.adding(shown?.search ?? search, to: recent) }
                    } label: { FoodRow(food: food, quickAdd: { quickAdd(food) }, quickAddLabel: quickAddLabel) }
                    .contextMenu { PinButton(food: food) }
                }
            } header: {
                HStack {
                    if shown != nil { Text("\(rows.count) food\(rows.count == 1 ? "" : "s")") }
                    Spacer()
                    Picker("Sort", selection: $sort) {
                        Text("Protein per calorie").tag("density"); Text("Most protein").tag("protein"); Text("Lowest calories").tag("calories")
                        Text("Name").tag("name")
                    }.pickerStyle(.menu).labelsHidden().textCase(nil).font(.roboto(.subheadline)).fixedSize()
                }
            }
        }.searchable(text: $search, isPresented: $searchShown, prompt: "Food, product or restaurant")
            .onAppear { if startSearching && search.isEmpty { searchShown = true } }
            .task(id: Key(request: request, custom: store.data.foods, catalog: store.catalog.revision ?? String(store.catalog.foods.count))) { await update(request) }
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
            .onSubmit(of: .search) {
                recent = RecentSearches.adding(search, to: recent)
                if shown == request { if rows.isEmpty { searchPackaged += 1 } } else { submitted = true }
            }
            .navigationTitle(pick == nil ? (startSearching ? "Search foods" : "Best choices") : "Choose a food")
            .toolbar { if pick == nil { NavigationLink { SourcesView() } label: { Image(systemName: "info.circle") }.accessibilityLabel("Menu sources") } }
    }
}

/// Packaged foods from Open Food Facts for what's typed, fetched only when asked so nothing is sent while typing.
struct PackagedFoodsSection: View {
    let search: String
    /// Searches when it changes, as if the button were tapped.
    var trigger = 0
    var pick: ((Portion) -> Void)?
    var pickTitle = "Use this portion"
    var logYesterday = false
    var logMeal: MealTime?
    /// What was searched for and what came back. Nil hits while waiting.
    private struct Results: Equatable { var terms: String; var hits: [ProductHit]?; var failed: String?; var attempt = UUID() }
    @State private var results: Results?
    /// Searches already made this session, so going back and forth doesn't ask again.
    @MainActor private static var cache: [String: [ProductHit]] = [:]

    var body: some View {
        let terms = ProductSearch.terms(search)
        if !terms.isEmpty {
            Section {
                if let results, results.terms == terms {
                    if let failed = results.failed {
                        Text(failed).foregroundStyle(.secondary)
                        Button("Try again") { start(terms) }
                    } else if let hits = results.hits {
                        if hits.isEmpty { Text("No packaged foods with nutrition found for “\(search)”.").foregroundStyle(.secondary) }
                        ForEach(hits) { hit in
                            NavigationLink {
                                ProductDetailView(hit: hit, pick: pick, pickTitle: pickTitle, logYesterday: logYesterday, logMeal: logMeal)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(hit.product.food.name).font(.roboto(.headline))
                                    Text("\(hit.product.food.cal.rounded().number) Cal · \(hit.product.food.p.tenth.number) g protein per 100 \(hit.product.unit)")
                                        .font(.roboto(.subheadline)).foregroundStyle(.secondary)
                                }.padding(.vertical, 4)
                            }
                        }
                    } else {
                        ProgressView("Searching Open Food Facts…").frame(maxWidth: .infinity)
                    }
                } else {
                    Button { start(terms) } label: { Label("Search packaged foods for “\(search.trimmingCharacters(in: .whitespaces))”", systemImage: "barcode") }
                }
            } header: { Text("Packaged foods") } footer: {
                Text("From Open Food Facts, a free database anyone can edit. Only your search words are sent, and only when you tap search. Check the package before logging.")
            }
            .task(id: results?.attempt) { await run() }
            .onChange(of: trigger) { if results?.terms != terms { start(terms) } }
        }
    }

    private func start(_ terms: String) {
        results = Results(terms: terms, hits: Self.cache[terms])
    }

    private func run() async {
        guard let pending = results, pending.hits == nil, pending.failed == nil else { return }
        do {
            let hits = try await ProductSearch.search(pending.terms)
            guard !Task.isCancelled, results?.attempt == pending.attempt else { return }
            Self.cache[pending.terms] = hits
            results?.hits = hits
        } catch {
            guard !Task.isCancelled, results?.attempt == pending.attempt else { return }
            results?.failed = (error as? BarcodeLookupError)?.errorDescription ?? "Couldn't connect to Open Food Facts. Check your internet connection and try again."
        }
    }
}

/// One packaged food from a search: its full label from Open Food Facts, with how much you had and Log.
struct ProductDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let hit: ProductHit
    var pick: ((Portion) -> Void)?
    var pickTitle = "Use this portion"
    var logYesterday = false
    var logMeal: MealTime?
    /// The full product page, which has serving sizes the search doesn't. Nil until it arrives, or if it can't be fetched.
    @State private var full: BarcodeProduct?
    @State private var loading = true

    var body: some View {
        let product = full ?? hit.product
        let saved = BarcodeLookup.match(hit.code, in: store.data.foods)
        let food = saved ?? product.food
        let meal = logMeal ?? MealTime.suggested()
        LeanrForm {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(food.name).font(.display(.title2))
                    Text(saved != nil ? "In My foods · \(food.serve)" : product.per100 ? "Nutrition per 100 \(product.unit)" : "Nutrition per \(food.serve)")
                        .foregroundStyle(.secondary)
                }.padding(.vertical, 4)
                if loading { ProgressView("Getting the full label…").font(.roboto(.caption)) }
            }
            Section { NutritionView(total: Nutrition([Portion(food: food)])) }
            Section {
                BarcodeQuickActions(food: food, per100: saved == nil && product.per100, inMyFoods: saved != nil,
                                    mode: .log { portion in
                                        if let pick { pick(portion); return true }
                                        return store.logNow([portion], name: portion.food.name, mealTime: meal, yesterday: logYesterday)
                                    },
                                    actionTitle: pick != nil ? pickTitle : logYesterday ? "Log to yesterday’s \(meal.title.lowercased())" : "Log to \(meal.title)") {
                    if pick == nil { dismiss() }
                }
                .id(food.serve + (saved?.id ?? ""))
            } footer: {
                Text("Check this matches the package. Open Food Facts is edited by volunteers.")
            }
            Section {
                Link("Source: Open Food Facts · ODbL", destination: product.sourceURL)
            }
        }
        .navigationTitle("Product").navigationBarTitleDisplayMode(.inline)
        .task {
            full = try? await BarcodeLookup.fetch(code: hit.code)
            loading = false
        }
    }
}
