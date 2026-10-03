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
    @AppStorage(OpenNow.storageKey) private var openOnly = true
    /// Chains to leave out because the closest one is closed (only with "Open now only" on).
    private var closedNow: [String: Date?] { openOnly ? OpenNow.closed(location: location) : [:] }
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
            Section {
                ChipRow {
                    Chip(title: "All", selected: query.chains.isEmpty) { query.chains = [] }
                    ForEach(store.catalog.chains) { chain in
                        Chip(title: chain.name, selected: query.chains.contains(chain.id)) {
                            if query.chains.contains(chain.id) { query.chains.remove(chain.id) } else { query.chains.insert(chain.id) }
                        }
                    }
                }
                OpenNowToggle(isOn: $openOnly)
            } header: { Text("Restaurants") } footer: { OpenNowFooter(on: openOnly, closed: closedNow) }
            if searching || matches.isEmpty {
                Section(searching ? "Finding combinations…" : "No suggestions") {
                    if searching { ProgressView().frame(maxWidth: .infinity) }
                    else if !query.chains.isEmpty, query.chains.allSatisfy({ closedNow.keys.contains($0) }) {
                        ContentUnavailableView {
                            Label("Closed right now", systemImage: "clock")
                        } description: {
                            Text("\(OpenNow.describe(closedNow.filter { query.chains.contains($0.key) }, names: store.chainName)) near you. Turn off Open now only to see it anyway.")
                        } actions: { Button("Show anyway") { openOnly = false } }
                    }
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
        .task(id: SearchKey(query: query, closed: Set(closedNow.keys), refresh: searchID)) { await search() }
        // The closest restaurant of each chain and its hours, once location is allowed (it's never asked for here).
        .task(id: location.location?.timestamp) {
            if location.isAuthorized { await location.load(Array(Set(matches.map(\.chain)))) }
            await OpenNow.load(location: location)
        }
    }
    private struct SearchKey: Equatable { var query: FindQuery; var closed: Set<String>; var refresh: UUID }
    private func useRemaining() {
        let total = Nutrition((store.data.logs[dayKey(Date())] ?? []).flatMap(\.items))
        query.calories = max(0, (store.goals.values["cal"] ?? 2200) - total.cal)
        query.protein = max(0, (store.goals.values["p"] ?? 150) - total.p)
    }
    private func search() async {
        searching = true
        // Your own foods aren't restaurants, so they're never left out.
        let closed = Set(closedNow.keys)
        let foods = store.foods.filter { !closed.contains($0.chain) }, request = query
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
    @Environment(LocationStore.self) private var location
    @AppStorage(OpenNow.storageKey) private var openOnly = true
    var pick: ((Portion) -> Void)?
    /// Closed restaurants are left out when looking for something to eat, not when logging something already eaten.
    private var closedNow: [String: Date?] { pick == nil && openOnly ? OpenNow.closed(location: location) : [:] }
    /// What choosing a food does, for the button on its details, e.g. "Log to Lunch".
    var pickTitle = "Use this portion"
    /// What the "+" on a row does, for VoiceOver.
    var quickAddLabel = "Log"
    static let categories = [("all", "All items"), ("main", "Mains"), ("breakfast", "Breakfast"), ("side", "Sides"), ("drink", "Drinks"), ("sweet", "Desserts"), ("extra", "Extras")]
    /// Where the "+" on a row logs to, when nothing else is choosing the food.
    @State private var yesterday = false
    @State private var meal = MealTime.suggested()
    @State private var rows: [Food] = []
    /// The request the rows were worked out for; nil until the first list is ready.
    @State private var shown: FoodSearch.Browse?
    private var request: FoodSearch.Browse { .init(search: search, chain: chain, category: category, sort: sort) }
    /// Also redo the list when your own foods change or the menu loads.
    private struct Key: Equatable { var request: FoodSearch.Browse; var custom: [Food]; var catalog: String; var closed: Set<String> }

    private func update(_ request: FoodSearch.Browse) async {
        // Wait for a pause in typing so each keystroke doesn't start a new search.
        if let shown, shown.search != request.search, !request.search.isEmpty { try? await Task.sleep(for: .milliseconds(120)) }
        guard !Task.isCancelled else { return }
        let closed = Set(closedNow.keys)
        let foods = store.foods.filter { !closed.contains($0.chain) }
        let names = Dictionary(store.catalog.chains.map { ($0.id, $0.name) }) { a, _ in a }
        let work = Task.detached(priority: .userInitiated) { FoodSearch.browse(foods, chainNames: names, request: request) }
        let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        if !Task.isCancelled { rows = result; shown = request }
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
                    Chip(title: "All restaurants", selected: chain == "all") { chain = "all" }
                    ForEach(store.catalog.chains) { item in Chip(title: item.name, selected: chain == item.id) { chain = chain == item.id ? "all" : item.id } }
                }
                ChipRow {
                    ForEach(BrowseView.categories, id: \.0) { tag, label in Chip(title: label, selected: category == tag) { category = tag } }
                }
                if pick == nil { OpenNowToggle(isOn: $openOnly) }
            } footer: { if pick == nil { OpenNowFooter(on: openOnly, closed: closedNow) } }
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
            Section {
                if shown == request && rows.isEmpty { ContentUnavailableView.search(text: search) }
                ForEach(rows) { food in
                    NavigationLink {
                        FoodDetailView(food: food, pick: pick, pickTitle: pickTitle, logYesterday: yesterday, logMeal: pick == nil ? meal : nil).onAppear { recent = RecentSearches.adding(shown?.search ?? search, to: recent) }
                    } label: { FoodRow(food: food, quickAdd: { quickAdd(food) }, quickAddLabel: quickAddLabel) }
                    .contextMenu { PinButton(food: food) }
                }
            } header: {
                HStack {
                    if shown != nil { Text("\(rows.count) foods") }
                    Spacer()
                    Picker("Sort", selection: $sort) {
                        Text("Protein per calorie").tag("density"); Text("Most protein").tag("protein"); Text("Lowest calories").tag("calories")
                        Text("Protein per dollar").tag("value"); Text("Name").tag("name")
                    }.pickerStyle(.menu).labelsHidden().textCase(nil).font(.roboto(.subheadline)).fixedSize()
                }
            }
        }.searchable(text: $search, prompt: "Food or restaurant")
            .task(id: Key(request: request, custom: store.data.foods, catalog: store.catalog.revision ?? String(store.catalog.foods.count), closed: Set(closedNow.keys))) { await update(request) }
            .task(id: location.location?.timestamp) { if pick == nil { await OpenNow.load(location: location) } }
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
            .toolbar { if pick == nil { NavigationLink { SourcesView() } label: { Image(systemName: "info.circle") }.accessibilityLabel("Menu sources") } }
    }
}

/// The "Open now only" switch on Find and Best choices.
struct OpenNowToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) { Label("Open now only", systemImage: "clock") }.font(.roboto(.subheadline))
    }
}

/// What "Open now only" is doing: which restaurants it's hiding, or why it can't tell yet.
struct OpenNowFooter: View {
    @Environment(LocationStore.self) private var location
    @Environment(AppStore.self) private var store
    let on: Bool
    let closed: [String: Date?]
    var body: some View {
        if on {
            if !location.isAuthorized { Text("Allow location on the Map tab to hide restaurants that are closed near you.") }
            else if !PlaceHoursStore.shared.isConfigured { Text("Opening hours aren't set up yet, so every restaurant is shown.") }
            else if !closed.isEmpty { Text("Hidden while closed near you: \(OpenNow.describe(closed, names: store.chainName)).") }
        }
    }
}
