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
    @AppStorage(MacroColours.proteinKey) private var proteinColour = "blue"
    @AppStorage(MacroColours.carbsKey) private var carbsColour = "orange"
    @AppStorage(MacroColours.fatKey) private var fatColour = "red"

    private var key: String { dayKey(date) }
    private var entries: [LogEntry] { MealPlan.entries(store.data, on: key) }
    private var goals: Goals { store.goals }
    /// What's already logged for the day, so planning today counts it.
    private var eaten: Nutrition { Nutrition((store.data.logs[key] ?? []).flatMap(\.items)) }
    private var planned: Nutrition { Nutrition(entries.flatMap(\.items)) }
    /// Logged food plus the plan: where the day ends up if you eat it all.
    private var total: Nutrition { Nutrition((store.data.logs[key] ?? []).flatMap(\.items) + entries.flatMap(\.items)) }
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
                        EatenPlannedBar(label: "Calories", eaten: eaten.cal, planned: planned.cal, target: cal, unit: "Cal", minimum: false, colour: .accentColor)
                    }
                    ForEach(Self.macros, id: \.key) { macro in
                        if let target = goals.values[macro.key] {
                            EatenPlannedBar(label: macro.label, eaten: eaten.value(macro.key), planned: planned.value(macro.key), target: target, unit: "g",
                                            minimum: goals.minimums.contains(macro.key), colour: colour(macro.key))
                        } else {
                            // No target set: still show the day's running total.
                            HStack {
                                Text(macro.label).font(.roboto(.caption, weight: .medium)).foregroundStyle(.secondary)
                                Spacer()
                                Text("\(total.value(macro.key).rounded().number) g").font(.roboto(.caption)).monospacedDigit()
                            }
                        }
                    }
                }.padding(.vertical, 6)
            } header: { Text(eaten.cal > 0 ? "Eaten and planned" : "Planned so far") } footer: { Text(leftText) }
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

    private static let macros: [(key: String, label: String)] = [("p", "Protein"), ("c", "Carbs"), ("f", "Fat")]

    private func colour(_ key: String) -> Color {
        MacroColours.colour(key, choices: Premium.isUnlocked ? ["p": proteinColour, "c": carbsColour, "f": fatColour] : [:])
    }

    /// What the day leaves after the plan, counting anything already logged.
    private var leftText: String {
        guard !entries.isEmpty else { return "" }
        var parts: [String] = []
        if let cal = goals.values["cal"] {
            let left = cal - total.cal
            parts.append(left >= 0 ? "\(left.rounded().number) Cal" : "\(abs(left).rounded().number) Cal over")
        }
        for macro in Self.macros {
            guard let target = goals.values[macro.key] else { continue }
            let left = target - total.value(macro.key)
            parts.append(left >= 0 ? "\(left.rounded().number) g \(macro.label.lowercased())" : "\(abs(left).rounded().number) g \(macro.label.lowercased()) over")
        }
        guard !parts.isEmpty else { return "" }
        let logged = eaten.cal > 0 ? "Counts the \(eaten.cal.rounded().number) Cal you've logged plus \(planned.cal.rounded().number) Cal planned. " : ""
        return logged + "After this plan: " + parts.joined(separator: ", ") + "."
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

/// A target bar split in two: what's eaten in the full colour, then what's planned in a lighter shade of it.
private struct EatenPlannedBar: View {
    var label: String
    var eaten: Double
    var planned: Double
    var target: Double
    var unit: String
    var minimum: Bool
    var colour: Color

    var body: some View {
        let total = (eaten + planned).rounded()
        let over = !minimum && total > target
        let figures = Text("\(total.number) / \(target.number) \(unit)").font(.roboto(.caption)).monospacedDigit()
            .foregroundStyle(over ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
        let name = Text(label).font(.roboto(.caption, weight: .medium)).foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 5) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { name.fixedSize(); Spacer(minLength: 4); figures.fixedSize() }
                VStack(alignment: .leading, spacing: 2) { name; figures }
            }
            GeometryReader { geo in
                let scale = geo.size.width / max(target, 0.001)
                let eatenWidth = min(max(eaten * scale, 0), geo.size.width)
                let plannedWidth = min(max(planned * scale, 0), geo.size.width - eatenWidth)
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(colour.opacity(0.4)).frame(width: eatenWidth + plannedWidth)
                    Capsule().fill(colour).frame(width: eatenWidth)
                }
            }.frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(eaten.rounded().number) eaten and \(planned.rounded().number) planned, of \(target.number) \(unit)")
    }
}
