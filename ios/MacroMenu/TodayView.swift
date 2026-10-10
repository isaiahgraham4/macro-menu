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
    @State private var photo = false
    @State private var editing: LogEntry?
    @State private var editingTargets = false
    @State private var showingCalendar = false
    @State private var now = Date()
    @State private var mealTime = MealTime.suggested()
    @Environment(\.dynamicTypeSize) private var typeSize
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
                        Text("Leanr").font(.display(.title))
                        Text("Your day, on the board.").font(.roboto(.subheadline))
                    }
                    Spacer()
                    Image(systemName: "leaf.fill").font(.largeTitle).accessibilityHidden(true)
                }
                .foregroundStyle(Color(red: 0.23, green: 0.17, blue: 0.10))
                .padding(24).background { CuttingBoard() }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            Section {
                let previous = Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("Previous day")
                let next = Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44).contentShape(Rectangle()) }.disabled(isToday).accessibilityLabel("Next day")
                let picker = DatePicker("Day", selection: $date, in: ...Date(), displayedComponents: .date).labelsHidden().controlSize(.small)
                Group {
                    if typeSize.isAccessibilitySize {
                        // At the largest text sizes the date needs the whole row, so the arrows go underneath.
                        VStack(spacing: 4) { picker; HStack { previous; Spacer(); next } }
                    } else {
                        HStack(spacing: 8) { previous; Spacer(); picker; Spacer(); next }
                    }
                }
                .buttonStyle(.borderless)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                if !isToday { Button("Jump to today") { date = Date() }.frame(maxWidth: .infinity) }
            }
            Section {
                VStack(spacing: 18) {
                    // The ring sits above the bars at the largest text sizes, so neither gets squeezed.
                    let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 20)) : AnyLayout(HStackLayout(spacing: 20))
                    layout {
                        if let cal = goals.values["cal"] { CalorieRing(eaten: total.cal, target: cal) }
                        VStack(spacing: 14) {
                            if macroKeys.isEmpty {
                                Text("\(total.cal.number) Cal eaten").font(.roboto(.title3, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            ForEach(macroKeys, id: \.self) { key in bar(key) }
                        }
                    }
                    if !otherKeys.isEmpty {
                        LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], spacing: 14) {
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
            Section {
                BodySummary()
                NavigationLink { WeeklyReviewView() } label: { Label("Your week", systemImage: "chart.bar.xaxis") }
            }
            Section("Logged meals") {
                Picker("Log to", selection: $mealTime) {
                    ForEach(MealTime.allCases) { Text($0.title).tag($0) }
                }
                Button { barcode = true } label: { Label("Scan product barcode", systemImage: "barcode.viewfinder") }
                if MealPhoto.canOffer {
                    Button { photo = true } label: { Label("Photo of your meal", systemImage: "camera.viewfinder") }
                }
            }
            ForEach(MealTime.allCases) { category in
                let meals = entries.filter { $0.mealTime == category }
                Section {
                    if meals.isEmpty { Text("Nothing logged yet").font(.roboto(.subheadline)).foregroundStyle(.secondary) }
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
                            let pinned = store.pinnedFoods
                            if !pinned.isEmpty {
                                Section("Pinned") {
                                    ForEach(pinned) { food in
                                        Button("\(food.name) · \(food.cal.number) Cal", systemImage: "pin") {
                                            if store.log([Portion(food: food)], name: food.name, date: date, mealTime: category) {
                                                store.notice = "Logged to \(category.title.lowercased())"
                                            }
                                        }
                                    }
                                }
                            }
                            Button("Scan barcode") { mealTime = category; barcode = true }
                            if MealPhoto.canOffer { Button("Photo of your meal") { mealTime = category; photo = true } }
                            Button("Quick log / scan label") { mealTime = category; quick = true }
                            Button("Choose menu item") { mealTime = category; choosing = true }
                        } label: { Image(systemName: "plus.circle").font(.title3).padding(4) } primaryAction: {
                            // A tap goes straight to the menu; holding shows the other ways to add.
                            mealTime = category; choosing = true
                        }
                            .accessibilityLabel("Add to \(category.title)")
                            .accessibilityHint("Opens the menu. Hold for pinned foods, barcode, photo and quick log.")
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
            .sheet(isPresented: $photo) {
                NavigationStack {
                    MealPhotoView(mealTime: mealTime) { portions, name in
                        guard store.log(portions, name: name, date: date, mealTime: mealTime) else { return false }
                        store.notice = "Logged to \(mealTime.title.lowercased())"
                        return true
                    }
                }
            }
            .sheet(isPresented: $choosing) { NavigationStack { BrowseView(pick: { portion in
                if store.log([portion],name: portion.food.name,date: date, mealTime: mealTime) { choosing = false; store.notice = "Logged to \(mealTime.title.lowercased())" }
            }, pickTitle: "Log to \(mealTime.title)").toolbar { Button("Done") { choosing = false } } } }
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
            Button("Delete", role: .destructive) { store.change(undo: "Deleted \(entry.name)") { $0.logs[key]?.removeAll { $0.id == entry.id } } }
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
                    .font(.roboto(.subheadline)).foregroundStyle(.secondary)
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
                                Text(entry.name).font(.roboto(.headline))
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption)
                            }
                            Text(Nutrition(entry.items).text)
                                .font(.roboto(.caption)).foregroundStyle(.secondary)
                        }.foregroundStyle(.primary)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { store.change(undo: "Deleted \(entry.name)") { $0.logs[dayKey(date)]?.removeAll { $0.id == entry.id } } }
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

/// Changes a logged meal: its name, meal time and day, the amounts, and which foods are in it.
/// Nothing changes until Save, and Undo puts the old version back.
struct LogEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var entry: LogEntry
    @State private var date: Date
    @State private var picking = false
    @State private var confirmingDelete = false
    private let original: LogEntry
    let day: String

    init(entry: LogEntry, day: String) {
        original = entry; self.day = day
        _entry = State(initialValue: entry)
        _date = State(initialValue: Self.date(of: day) ?? entry.time)
    }

    private var newDay: String { dayKey(date) }
    private var changed: Bool { entry != original || newDay != day }

    var body: some View {
        LeanrForm {
            Section {
                TextField("Meal name", text: $entry.name, axis: .vertical)
                Picker("Meal time", selection: $entry.mealTime) {
                    Text("Unassigned").tag(MealTime?.none)
                    ForEach(MealTime.allCases) { Text($0.title).tag(Optional($0)) }
                }
                DatePicker("Day", selection: $date, in: ...Date(), displayedComponents: .date)
            }
            Section {
                if entry.items.isEmpty { Text("Add at least one food to keep this meal.").foregroundStyle(.secondary) }
                ForEach($entry.items) { $item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.food.name).font(.roboto(.headline))
                        Text("\((item.food.cal * item.quantity).number) Cal · \((item.food.p * item.quantity).number) g protein")
                            .font(.roboto(.caption)).foregroundStyle(.secondary)
                        NumberField(title: "Servings", value: $item.quantity, places: 2, spokenTitle: "Servings of \(item.food.name)")
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { entry.items.remove(atOffsets: $0) }
                Button { picking = true } label: { Label("Add food", systemImage: "plus.circle.fill") }
            } header: { Text("Foods") } footer: { Text("Swipe a food to take it out.") }
            if !entry.items.isEmpty {
                Section("Totals") { NutritionView(total: Nutrition(entry.items)) }
            }
            Section {
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Label("Delete from log", systemImage: "trash").foregroundStyle(.red).frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Edit logged meal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(!changed || !entry.isValid || entry.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .sheet(isPresented: $picking) {
            NavigationStack {
                BrowseView(pick: { portion in
                    var fresh = portion; fresh.id = UUID()
                    if let i = entry.items.firstIndex(where: { $0.food == fresh.food }) { entry.items[i].quantity += fresh.quantity }
                    else { entry.items.append(fresh) }
                    picking = false
                }, pickTitle: "Add to \(entry.name)", quickAddLabel: "Add")
                .toolbar { Button("Done") { picking = false } }
            }
        }
        .confirmationDialog("Delete \(original.name) from your log?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete from log", role: .destructive) {
                if store.change(undo: "Deleted \(original.name)", { $0.logs[day]?.removeAll { $0.id == original.id } }) { dismiss() }
            }
        }
    }

    private func save() {
        var saved = entry
        saved.name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Moved to another day: same clock time, new date.
        if newDay != day {
            let calendar = Calendar.current
            let clock = calendar.dateComponents([.hour, .minute, .second], from: entry.time)
            saved.time = calendar.date(bySettingHour: clock.hour ?? 12, minute: clock.minute ?? 0, second: clock.second ?? 0, of: date) ?? date
        }
        if store.updateLog(saved, day: day, to: newDay) {
            store.notice = newDay == day ? "Saved \(saved.name)" : "Moved \(saved.name) to \(date.formatted(date: .abbreviated, time: .omitted))"
            dismiss()
        }
    }

    /// The start of a day key like "2026-10-05".
    static func date(of day: String) -> Date? {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: day)
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
                            Button("Delete", role: .destructive) { store.change(undo: "Deleted \(goal.name)") { $0.goalSets.removeAll { $0.id == goal.id } } }
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
    @Environment(AppStore.self) private var store
    @Environment(HealthSync.self) private var health
    var apply: ([String: Double]) -> Void
    // Remembered, so updating targets later only needs what's changed.
    @AppStorage("calc.female") private var female = false
    @AppStorage("calc.age") private var age = 30.0
    @AppStorage("calc.height") private var height = 175.0
    @AppStorage("calc.weight") private var weight = 75.0
    @AppStorage("calc.activity") private var activity = 1.375
    @AppStorage("calc.adjustment") private var adjustment = 0.0
    @AppStorage("calc.proteinPerKG") private var proteinPerKG = 1.6
    @AppStorage("calc.fatPercent") private var fatPercent = 25.0
    @State private var useMeasured = true
    private var points: [WeightTrend.Point] { WeightTrend.points(store.data.weightLog) }
    private var measured: WeightTrend.Maintenance? { WeightTrend.maintenance(logs: store.data.logs, points: points) }
    private static let activityLevels = [1.2, 1.375, 1.55, 1.725, 1.9]
    var bmr: Double { 10 * weight + 6.25 * height - 5 * age + (female ? -161 : 5) }
    var equation: Double { bmr * activity }
    /// Measured from your log and weight trend when there's enough data, otherwise the equation's estimate.
    var maintenance: Double { useMeasured ? measured?.calories ?? equation : equation }
    var calories: Double { maintenance + adjustment }
    var protein: Double { weight * proteinPerKG }
    var fat: Double { calories * fatPercent / 100 / 9 }
    var carbs: Double { max(0,(calories - protein * 4 - fat * 9) / 4) }
    var valid: Bool { (18...100).contains(age) && (120...230).contains(height) && (35...250).contains(weight) && (0.8...3.3).contains(proteinPerKG) && (15...45).contains(fatPercent) && calories > 0 && protein * 4 + fat * 9 <= calories }
    var body: some View {
        LeanrForm {
            if points.last != nil || measured != nil || health.averageActiveEnergy != nil {
                Section {
                    if let last = points.last {
                        LabeledContent("Trend weight", value: "\(last.trend.number) kg")
                        if abs(last.trend - weight) >= 0.1 { Button("Use my trend weight") { weight = last.trend.tenth } }
                    }
                    if let measured {
                        Toggle(isOn: $useMeasured) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Use my measured maintenance")
                                Text("\(measured.calories.rounded().number) Cal/day from \(measured.loggedDays) logged days").font(.roboto(.caption)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let active = health.averageActiveEnergy {
                        LabeledContent("Active energy (Apple Health)", value: "\(active.rounded().number) Cal/day")
                        if !(useMeasured && measured != nil) {
                            Button("Set activity from Apple Health") {
                                // Resting burn plus measured activity, plus about 10% for digesting food.
                                let factor = 1.1 * (bmr + active) / max(bmr, 1)
                                activity = Self.activityLevels.min { abs($0 - factor) < abs($1 - factor) } ?? activity
                            }
                        }
                    }
                } header: { Text("From your data") } footer: {
                    if measured != nil && useMeasured { Text("Measured maintenance replaces the activity-based estimate below. Your goal is still added or subtracted.") }
                }
            }
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
                    LabeledContent(useMeasured && measured != nil ? "Measured maintenance" : "Estimated maintenance", value: maintenance.rounded().number + " Cals/day")
                    LabeledContent("Daily calorie target", value: calories.number + " Cals")
                    LabeledContent("Protein", value: protein.number + " g")
                    LabeledContent("Carbs", value: carbs.number + " g")
                    LabeledContent("Fat", value: fat.number + " g")
                    Button("Use these targets") { apply(["cal":calories.rounded(),"p":protein.rounded(),"c":carbs.rounded(),"f":fat.rounded()]) }
                } else { Text("Enter valid measurements and macro settings.") }
                Text("Mifflin–St Jeor estimate for adults. Actual needs vary; review against your own progress. Talk to a doctor or Accredited Practising Dietitian before making big changes to how you eat, especially if you're pregnant, have a medical condition or have had an eating disorder.").font(.roboto(.caption)).foregroundStyle(.secondary)
            }
        }.navigationTitle("Estimate targets").toolbar { Button("Cancel") { dismiss() } }
            .onAppear { if let last = points.last { weight = last.trend.tenth } }
    }
}
