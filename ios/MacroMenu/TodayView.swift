import SwiftUI
import Combine

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @State private var date = Date()
    @AppStorage(MacroColours.proteinKey) private var proteinColour = "blue"
    @AppStorage(MacroColours.carbsKey) private var carbsColour = "orange"
    @AppStorage(MacroColours.fatKey) private var fatColour = "red"
    @State private var quick = false
    @State private var barcode = false
    @State private var choosing = false
    @State private var editing: LogEntry?
    @State private var editingTargets = false
    @State private var showingCalendar = false
    @State private var now = Date()
    @State private var mealTime = MealTime.suggested()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    var key: String { dayKey(date) }
    var entries: [LogEntry] { store.data.logs[key] ?? [] }
    var total: Nutrition { Nutrition(entries.flatMap(\.items)) }
    var goals: Goals { key == dayKey(now) ? store.goals : store.data.dayGoals[key] ?? store.goals }
    var isToday: Bool { key == dayKey(now) }
    /// Targets other than calories, split into the three macros and everything else.
    var macroKeys: [String] { ["p", "c", "f"].filter { goals.values[$0] != nil } }
    var otherKeys: [String] { nutrientNames.map(\.key).filter { !["cal", "p", "c", "f"].contains($0) && goals.values[$0] != nil } }
    var partialNames: [String] {
        guard !entries.isEmpty else { return [] }
        return nutrientNames.filter { n in
            goals.values[n.key] != nil && (total.isPartial(n.key) || (!["cal", "p", "c", "f"].contains(n.key) && total.nut[n.key] == nil))
        }.map(\.label)
    }
    var body: some View {
        LeanrList {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Leanr").font(.system(.title, design: .rounded, weight: .bold))
                        Text("Your day, on the board.").font(.subheadline)
                    }
                    Spacer()
                    Image(systemName: "leaf.fill").font(.largeTitle)
                }
                .foregroundStyle(Color(red: 0.23, green: 0.17, blue: 0.10))
                .padding(24).background { CuttingBoard() }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            Section {
                HStack(spacing: 8) {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 28, height: 28) }.accessibilityLabel("Previous day")
                    Spacer()
                    DatePicker("Day", selection: $date, in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                        .controlSize(.small)
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 28, height: 28) }.disabled(isToday).accessibilityLabel("Next day")
                }
                .buttonStyle(.borderless)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                if !isToday { Button("Jump to today") { date = Date() }.frame(maxWidth: .infinity) }
            }
            Section {
                VStack(spacing: 18) {
                    HStack(spacing: 20) {
                        if let cal = goals.values["cal"] { CalorieRing(eaten: total.cal, target: cal) }
                        VStack(spacing: 14) {
                            if macroKeys.isEmpty {
                                Text("\(total.cal.number) Cal eaten").font(.roboto(.title3, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            ForEach(macroKeys, id: \.self) { key in bar(key) }
                        }
                    }
                    if !otherKeys.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], spacing: 14) {
                            ForEach(otherKeys, id: \.self) { key in bar(key) }
                        }
                    }
                    if !partialNames.isEmpty {
                        Text("Partial data for \(partialNames.joined(separator: ", ")): some logged items don't list them.")
                            .font(.roboto(.caption)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(.vertical, 10)
            } header: {
                HStack {
                    Text(goals.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasSuffix("targets") ? goals.name : "\(goals.name) targets")
                    Spacer()
                    Button("Edit") { editingTargets = true }.font(.roboto(.subheadline, weight: .medium)).textCase(nil)
                }
            }
            Section("Logged meals") {
                Picker("Log to", selection: $mealTime) {
                    ForEach(MealTime.allCases) { Text($0.title).tag($0) }
                }
                Button { barcode = true } label: { Label("Scan product barcode", systemImage: "barcode.viewfinder") }
            }
            ForEach(MealTime.allCases) { category in
                let meals = entries.filter { $0.mealTime == category }
                Section {
                    if meals.isEmpty { Text("Nothing logged yet").font(.subheadline).foregroundStyle(.secondary) }
                    ForEach(meals) { entry in logRow(entry) }
                } header: {
                    HStack {
                        NavigationLink {
                            MealTimeDetailView(mealTime: category, date: date)
                        } label: {
                            HStack {
                                Text(category.title)
                                Spacer()
                                if !meals.isEmpty {
                                    Text("\(Nutrition(meals.flatMap(\.items)).cal.number) Cals")
                                }
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("View \(category.title) calories and macros")
                        Menu {
                            Button("Scan barcode") { mealTime = category; barcode = true }
                            Button("Quick log / scan label") { mealTime = category; quick = true }
                            Button("Choose menu item") { mealTime = category; choosing = true }
                        } label: { Image(systemName: "plus.circle").font(.title3).padding(4) }
                            .accessibilityLabel("Add to \(category.title)")
                    }
                }
            }
            if entries.contains(where: { $0.mealTime == nil }) {
                Section {
                    ForEach(entries.filter { $0.mealTime == nil }) { entry in logRow(entry) }
                } header: { Text("Unassigned") } footer: {
                    Text("Tap an earlier entry to assign it to a meal time.")
                }
            }
            Section {
                TileRow {
                    Button { choosing = true } label: { TileLabel(title: "Log a menu item", systemImage: "fork.knife") }
                    Button { quick = true } label: { TileLabel(title: "Quick log", systemImage: "square.and.pencil") }
                    if !entries.isEmpty {
                        ShareLink(item: mealText("\(date.formatted(date: .complete,time: .omitted))", entries.flatMap(\.items))) { TileLabel(title: "Share day", systemImage: "square.and.arrow.up") }
                    }
                }
            }
        }.navigationTitle(isToday ? "Today" : "Daily log")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingCalendar = true } label: {
                        Label("\(store.data.widgetCalories.streak(on: now))", systemImage: "calendar")
                    }.accessibilityLabel("Tracking calendar, \(store.data.widgetCalories.streak(on: now)) day streak")
                }
            }
            .sheet(isPresented: $showingCalendar) {
                NavigationStack { TrackingCalendarView(selectedDate: $date) }
            }
            .navigationDestination(isPresented: $editingTargets) { TargetsView() }
            .sheet(isPresented: $quick) { NavigationStack {
                FoodEditor(food: nil, savePortion: { store.log([$0], name: $0.food.name, date: date, mealTime: mealTime) }) {
                    store.log([Portion(food: $0)], name: $0.name, date: date, mealTime: mealTime)
                }
            } }
            .sheet(isPresented: $barcode) {
                BarcodeFoodFlow(savePortion: { store.log([$0], name: $0.food.name, date: date, mealTime: mealTime) }) {
                    store.log([Portion(food: $0)], name: $0.name, date: date, mealTime: mealTime)
                }
            }
            .sheet(isPresented: $choosing) { NavigationStack { BrowseView { portion in
                if store.log([portion],name: portion.food.name,date: date, mealTime: mealTime) { choosing = false }
            }.toolbar { Button("Done") { choosing = false } } } }
            .sheet(item: $editing) { entry in NavigationStack { LogEditor(entry: entry, day: key) } }
            .onReceive(timer) { value in
                let followingToday = dayKey(date) == dayKey(now)
                now = value
                if followingToday { date = value }
            }
    }
    private func logRow(_ entry: LogEntry) -> some View {
        Button { editing = entry } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name).font(.roboto(.headline)).foregroundStyle(.primary)
                    Text(Nutrition(entry.items).text).font(.roboto(.caption)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(entry.time.formatted(date: .omitted, time: .shortened)).font(.roboto(.caption)).foregroundStyle(.secondary)
            }.padding(.vertical, 2)
        }
        .swipeActions {
            Button("Delete", role: .destructive) { store.change { $0.logs[key]?.removeAll { $0.id == entry.id } } }
            Button("Copy to today") {
                if store.log(entry.items, name: entry.name, date: Date(), mealTime: entry.mealTime) { store.notice = "Copied to today" }
            }.tint(.blue)
        }
    }
    private func shift(_ days: Int) {
        let moved = Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
        date = min(Date(), moved)
    }
    private func bar(_ key: String) -> some View {
        let n = nutrientNames.first { $0.key == key }!
        let choices = Premium.isUnlocked ? ["p": proteinColour, "c": carbsColour, "f": fatColour] : [:]
        let style = ["p", "c", "f"].contains(key) ? AnyShapeStyle(MacroColours.colour(key, choices: choices)) : nutrientStyle(key)
        return TargetBar(label: n.label, value: total.value(key), target: goals.values[key] ?? 0, unit: n.unit, minimum: goals.minimums.contains(key), style: style)
    }
}

struct MealTimeDetailView: View {
    @Environment(AppStore.self) private var store
    let mealTime: MealTime
    let date: Date
    @State private var editing: LogEntry?

    private var entries: [LogEntry] {
        (store.data.logs[dayKey(date)] ?? []).filter { $0.mealTime == mealTime }
    }

    var body: some View {
        LeanrList {
            Section {
                Text(date.formatted(date: .complete, time: .omitted))
                    .font(.subheadline).foregroundStyle(.secondary)
                NutritionView(total: Nutrition(entries.flatMap(\.items)))
            } header: {
                Text("\(mealTime.title) totals")
            } footer: {
                Text("Includes only food logged to \(mealTime.title.lowercased()) on this day.")
            }
            Section("Logged food") {
                if entries.isEmpty {
                    Text("Nothing logged for \(mealTime.title.lowercased()) yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    Button { editing = entry } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(entry.name).font(.headline)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption)
                            }
                            Text(Nutrition(entry.items).text)
                                .font(.caption).foregroundStyle(.secondary)
                        }.foregroundStyle(.primary)
                    }
                }
            }
        }
        .navigationTitle(mealTime.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { entry in
            NavigationStack { LogEditor(entry: entry, day: dayKey(date)) }
        }
    }
}

struct LogEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var entry: LogEntry
    var day: String
    var body: some View {
        LeanrForm {
            TextField("Meal name", text: $entry.name)
            Picker("Meal time", selection: $entry.mealTime) {
                Text("Unassigned").tag(MealTime?.none)
                ForEach(MealTime.allCases) { Text($0.title).tag(Optional($0)) }
            }
            ForEach($entry.items) { $item in
                Section(item.food.name) { NumberField(title: "Servings", value: $item.quantity, places: 2) }
            }.onDelete { entry.items.remove(atOffsets: $0) }
            NutritionView(total: Nutrition(entry.items))
        }.navigationTitle("Edit logged meal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if store.change({ state in if let index = state.logs[day]?.firstIndex(where: { $0.id == entry.id }) { state.logs[day]?[index] = entry } }) { dismiss() } }.disabled(!entry.isValid)
                }
            }
    }
}

struct TargetsView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: Goals?
    var body: some View {
        LeanrList {
            Section("Target sets") {
                ForEach(store.data.goalSets) { goal in
                    HStack {
                        Button {
                            store.change { state in
                                state.activeGoal = goal.id
                                state.dayGoals[dayKey(Date())] = goal
                            }
                        } label: { Label(goal.name, systemImage: goal.id == store.goals.id ? "checkmark.circle.fill" : "circle") }
                        Spacer()
                        Button("Edit") { editing = goal }.buttonStyle(.borderless)
                    }.swipeActions {
                        if store.data.goalSets.count > 1 {
                            Button("Delete", role: .destructive) { store.change { $0.goalSets.removeAll { $0.id == goal.id } } }
                        }
                    }
                }
                Button("Add target set") { var goal = store.goals; goal.id = UUID(); goal.name = "New targets"; editing = goal }
            }
            Section { Text("Switch between training, rest or other day types. Past days keep the target snapshot captured when you logged them. Blank fields are not tracked.").font(.roboto(.subheadline)).foregroundStyle(.secondary) }
        }.navigationTitle("Your targets")
            .sheet(item: $editing) { goals in NavigationStack { GoalEditor(goal: goals) } }
    }
}
struct GoalEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var goal: Goals
    @State private var calculator = false
    var body: some View {
        LeanrForm {
            Section { TextField("Target set name", text: $goal.name) }
            Section("Daily targets") {
                ForEach(nutrientNames, id: \.key) { n in
                    VStack {
                        OptionalNumberField(title: "\(n.label) (\(n.unit))", value: Binding(get: { goal.values[n.key] }, set: { goal.values[n.key] = $0 }))
                        if goal.values[n.key] != nil {
                            Picker("Direction for \(n.label)", selection: Binding(get: { goal.minimums.contains(n.key) }, set: { minimum in
                                if minimum { goal.minimums.insert(n.key) } else { goal.minimums.remove(n.key) }
                            })) { Text("At most").tag(false); Text("At least").tag(true) }.pickerStyle(.segmented)
                        }
                    }
                }
            }
            Section("Typical meal") {
                NumberField(title: "Calories", value: $goal.mealCal)
                NumberField(title: "Protein (g)", value: $goal.mealProtein)
            }
            Section { Button("Estimate targets from body measurements") { calculator = true } }
        }.navigationTitle("Edit targets")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if store.change({ state in
                            if let i = state.goalSets.firstIndex(where: { $0.id == goal.id }) { state.goalSets[i] = goal } else { state.goalSets.append(goal) }
                            if state.activeGoal == goal.id || state.activeGoal == nil { state.dayGoals[dayKey(Date())] = goal }
                        }) { dismiss() }
                    }.disabled(!goal.isValid)
                }
            }
            .sheet(isPresented: $calculator) { NavigationStack { TargetCalculator { values in goal.values.merge(values) { _, new in new }; calculator = false } } }
    }
}
struct TargetCalculator: View {
    @Environment(\.dismiss) private var dismiss
    var apply: ([String: Double]) -> Void
    @State private var female = false
    @State private var age = 30.0
    @State private var height = 175.0
    @State private var weight = 75.0
    @State private var activity = 1.375
    @State private var adjustment = 0.0
    @State private var proteinPerKG = 1.6
    @State private var fatPercent = 25.0
    var maintenance: Double { (10 * weight + 6.25 * height - 5 * age + (female ? -161 : 5)) * activity }
    var calories: Double { maintenance + adjustment }
    var protein: Double { weight * proteinPerKG }
    var fat: Double { calories * fatPercent / 100 / 9 }
    var carbs: Double { max(0,(calories - protein * 4 - fat * 9) / 4) }
    var valid: Bool { (18...100).contains(age) && (120...230).contains(height) && (35...250).contains(weight) && (0.8...3.3).contains(proteinPerKG) && (15...45).contains(fatPercent) && calories > 0 && protein * 4 + fat * 9 <= calories }
    var body: some View {
        LeanrForm {
            Section("Body measurements") {
                Picker("Sex used in equation", selection: $female) { Text("Male").tag(false); Text("Female").tag(true) }
                NumberField(title: "Age (18–100)", value: $age)
                NumberField(title: "Height (cm)", value: $height)
                NumberField(title: "Weight (kg)", value: $weight)
                Picker("Activity", selection: $activity) {
                    Text("Mostly sitting").tag(1.2); Text("Light · 1–3 days/week").tag(1.375)
                    Text("Moderate · 3–5 days/week").tag(1.55); Text("Hard · 6–7 days/week").tag(1.725); Text("Very hard / physical job").tag(1.9)
                }
                Picker("Goal", selection: $adjustment) { Text("Maintain").tag(0.0); Text("Lose ~0.25 kg/week").tag(-275.0); Text("Lose ~0.5 kg/week").tag(-550.0); Text("Gain ~0.25 kg/week").tag(275.0) }
                NumberField(title: "Protein (g/kg)", value: $proteinPerKG)
                NumberField(title: "Fat share (%)", value: $fatPercent)
            }
            Section("Estimate") {
                if valid {
                    LabeledContent("Estimated maintenance", value: maintenance.number + " Cals/day")
                    LabeledContent("Daily calorie target", value: calories.number + " Cals")
                    LabeledContent("Protein", value: protein.number + " g")
                    LabeledContent("Carbs", value: carbs.number + " g")
                    LabeledContent("Fat", value: fat.number + " g")
                    Button("Use these targets") { apply(["cal":calories.rounded(),"p":protein.rounded(),"c":carbs.rounded(),"f":fat.rounded()]) }
                } else { Text("Enter valid measurements and macro settings.") }
                Text("Mifflin–St Jeor estimate for adults. Actual needs vary; review against your own progress.").font(.roboto(.caption)).foregroundStyle(.secondary)
            }
        }.navigationTitle("Estimate targets").toolbar { Button("Cancel") { dismiss() } }
    }
}
