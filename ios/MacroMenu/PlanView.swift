import SwiftUI

/// Plan a day's meals ahead against its targets. Nothing counts until it's eaten: on the day, Today lists the plan and a tap logs each meal.
struct PlanView: View {
    @Environment(AppStore.self) private var store
    @State private var date: Date = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    @State private var choosing: MealTime?
    @State private var describing: MealTime?
    @State private var scanning: MealTime?
    @State private var clearing = false
    @State private var ideas: [Assistant.Suggestion] = []

    private var key: String { dayKey(date) }
    private var entries: [LogEntry] { MealPlan.entries(store.data, on: key) }
    private var goals: Goals { store.goals }
    private var total: Nutrition { Nutrition(entries.flatMap(\.items)) }
    /// The first meal with nothing in it yet, where a suggestion goes.
    private var openMeal: MealTime { MealTime.allCases.first { meal in !entries.contains { $0.mealTime == meal } } ?? .snacks }

    var body: some View {
        LeanrList {
            Section {
                Picker("Day", selection: $date) {
                    ForEach(MealPlan.days(), id: \.self) { day in Text(Self.title(day)).tag(day) }
                }
            }
            Section {
                VStack(spacing: 12) {
                    if let cal = goals.values["cal"] {
                        TargetBar(label: "Calories", value: total.cal.rounded(), target: cal, unit: "Cal", minimum: false, style: AnyShapeStyle(.tint))
                    }
                    if let protein = goals.values["p"] {
                        TargetBar(label: "Protein", value: total.p.rounded(), target: protein, unit: "g", minimum: true, style: AnyShapeStyle(MacroColours.colour("p", choices: [:])))
                    }
                }.padding(.vertical, 6)
            } header: { Text("Planned so far") } footer: {
                if let left = goals.values["cal"].map({ $0 - total.cal }), left > 0, !entries.isEmpty {
                    Text("\(left.rounded().number) Cal left to plan\(goals.values["p"].map { $0 - total.p > 0 ? ", including \(($0 - total.p).rounded().number) g protein" : "" } ?? "").")
                }
            }
            ForEach(MealTime.allCases) { meal in mealSection(meal) }
            if !ideas.isEmpty {
                Section {
                    ForEach(ideas) { idea in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(idea.name).font(.roboto(.headline))
                                Text("\(idea.calories.rounded().number) Cal · \(idea.protein.number) g protein · \(idea.sourceText)").font(.roboto(.caption)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Button {
                                store.plan(idea.items, name: idea.name, mealTime: openMeal, on: date)
                            } label: { Image(systemName: "plus.circle.fill").font(.title2).frame(width: 44, height: 44).contentShape(Rectangle()) }
                                .buttonStyle(.borderless).accessibilityLabel("Plan \(idea.name) for \(openMeal.title)")
                        }
                    }
                } header: { Text("To fill the gap") } footer: { Text("Tap + to add it to \(openMeal.title.lowercased()).") }
            }
            Section {
                let today = store.data.logs[dayKey(Date())] ?? []
                if !Calendar.current.isDateInToday(date), !today.isEmpty {
                    Button("Copy today's meals", systemImage: "doc.on.doc") {
                        store.change(undo: "Copied today's meals") { state in
                            for entry in today { MealPlan.add(entry.items, name: entry.name, mealTime: entry.mealTime ?? .snacks, on: key, to: &state) }
                        }
                    }
                }
                if !entries.isEmpty { Button("Clear this day's plan", systemImage: "trash", role: .destructive) { clearing = true } }
            } footer: {
                Text("Plans count towards nothing until you log them. On the day, they're on Today, ready to log with a tap.")
            }
        }
        .navigationTitle("Plan ahead")
        .task(id: IdeasKey(day: key, planned: entries.map(\.id), calories: Int(total.cal), goal: goals.values["cal"])) { await refreshIdeas() }
        .sheet(item: $choosing) { meal in
            NavigationStack {
                BrowseView(pick: { portion in
                    if store.plan([portion], name: portion.food.name, mealTime: meal, on: date) { choosing = nil }
                }, pickTitle: "Plan for \(meal.title)", quickAddLabel: "Plan").toolbar { Button("Done") { choosing = nil } }
            }
        }
        .sheet(item: $scanning) { meal in
            BarcodeFoodFlow(savePortion: { store.plan([$0], name: $0.food.name, mealTime: meal, on: date) }, actionTitle: "Plan for \(meal.title)") {
                store.plan([Portion(food: $0)], name: $0.name, mealTime: meal, on: date)
            }
        }
        .sheet(item: $describing) { meal in
            NavigationStack {
                MealTextView(mealTime: meal, log: { portions, name in store.plan(portions, name: name, mealTime: meal, on: date) }, verb: "Plan")
            }
        }
        .confirmationDialog("Clear the plan for \(Self.title(date).lowercased())?", isPresented: $clearing, titleVisibility: .visible) {
            Button("Clear plan", role: .destructive) {
                store.change(undo: "Cleared your plan") { state in
                    state.plans?.removeValue(forKey: key)
                    if state.plans?.isEmpty == true { state.plans = nil }
                }
            }
        }
    }

    private func mealSection(_ meal: MealTime) -> some View {
        let planned = entries.filter { $0.mealTime == meal }
        return Section {
            ForEach(planned) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name).font(.roboto(.headline))
                    Text(Nutrition(entry.items).text).font(.roboto(.caption)).foregroundStyle(.secondary)
                }
                .swipeActions { Button("Remove", role: .destructive) { store.removePlanned(entry.id, on: date) } }
            }
            Menu {
                Button("Choose a food", systemImage: "magnifyingglass") { choosing = meal }
                Button("Scan a barcode", systemImage: "barcode.viewfinder") { scanning = meal }
                Button("Describe it", systemImage: "text.bubble") { describing = meal }
                if !store.data.meals.isEmpty {
                    Section("Saved meals") {
                        ForEach(store.data.meals) { saved in
                            Button(saved.name) { store.plan(saved.items, name: saved.name, mealTime: meal, on: date) }
                        }
                    }
                }
                if let usual = Assistant.usual(meal, logs: store.data.logs) {
                    Button("Your usual: \(usual.name)", systemImage: "arrow.uturn.backward") { store.plan(usual.items, name: usual.name, mealTime: meal, on: date) }
                }
            } label: { Label("Add to \(meal.title.lowercased())", systemImage: "plus.circle.fill") }
        } header: {
            HStack {
                Text(meal.title)
                Spacer()
                if !planned.isEmpty { Text("\(Nutrition(planned.flatMap(\.items)).cal.rounded().number) Cal").monospacedDigit() }
            }
        }
    }

    private struct IdeasKey: Equatable { var day: String; var planned: [UUID]; var calories: Int; var goal: Double? }

    /// Ideas that fit what the plan leaves, worked out as if the plan were eaten, at midday so each is one meal's worth.
    private func refreshIdeas() async {
        guard !entries.isEmpty else { ideas = []; return }
        let data = MealPlan.asLogged(store.data, day: key), goals = goals, pinned = store.pinnedFoods, everyday = store.suggestibleEveryday, restaurants = store.suggestibleRestaurantFoods, diet = DietFilter.saved
        let names = Dictionary(store.catalog.chains.map { ($0.id, $0.name) }) { a, _ in a }
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        let planned = Set(entries.map { $0.name.lowercased() })
        ideas = await Task.detached(priority: .userInitiated) {
            // Ask for a few extra, since anything already in the plan is left out.
            Assistant.suggestions(data, goals: goals, pinned: pinned, everyday: everyday, restaurantFoods: restaurants, chainNames: names, diet: diet, now: noon, limit: 6)
                .filter { !planned.contains($0.name.lowercased()) }.prefix(3).map { $0 }
        }.value
    }

    static func title(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide).day().month())
    }
}

/// Today's planned meals, each logged with a tap.
struct PlannedSection: View {
    @Environment(AppStore.self) private var store
    let date: Date

    var body: some View {
        let planned = MealPlan.entries(store.data, on: dayKey(date))
        if !planned.isEmpty {
            Section {
                ForEach(MealTime.allCases) { meal in
                    ForEach(planned.filter { $0.mealTime == meal }) { entry in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.name).font(.roboto(.headline))
                                Text("\(meal.title) · \(Nutrition(entry.items).cal.rounded().number) Cal · \(Nutrition(entry.items).p.rounded().number) g protein")
                                    .font(.roboto(.caption)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Button {
                                if store.logPlanned([entry.id], on: date) { store.notice = "Logged \(entry.name)" }
                            } label: { Image(systemName: "checkmark.circle").font(.title2).frame(width: 44, height: 44).contentShape(Rectangle()) }
                                .buttonStyle(.borderless).accessibilityLabel("Log \(entry.name)")
                        }
                        .swipeActions { Button("Remove", role: .destructive) { store.removePlanned(entry.id, on: date) } }
                    }
                }
                if planned.count > 1 {
                    Button("Log all \(planned.count)") { if store.logPlanned(Set(planned.map(\.id)), on: date) { store.notice = "Logged your plan" } }
                }
            } header: { Text("Planned") } footer: { Text("Tick a meal when you've eaten it to log it.") }
        }
    }
}
