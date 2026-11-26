import SwiftUI

struct MealView: View {
    @Environment(AppStore.self) private var store
    @State private var picking = false
    @State private var scanning = false
    @State private var name = ""
    @State private var date = Date()
    @State private var mealTime = MealTime.suggested()
    @State private var clear = false
    @State private var makingImage = false
    @State private var editingItem: Portion?
    @State private var left = LeftTodayModel()
    @AppStorage(TodaySuggestions.storageKey) private var suggestionsOn = true
    /// "Log again" cards widen with the text size.
    @ScaledMetric(relativeTo: .subheadline) private var cardWidth = 150.0
    var title: String { name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? suggestedName : name }
    /// What's in the meal, customisations included, e.g. "McChicken · No McChicken Sauce, 2 × Small Fries".
    var suggestedName: String {
        let names = store.data.tray.map { ($0.quantity == 1 ? "" : "\($0.quantity.number) × ") + $0.food.name }
        return names.isEmpty ? "My meal" : names.joined(separator: ", ")
    }
    var body: some View {
        LeanrList {
            Section {
                NavigationLink { MyFoodsView() } label: {
                    HStack {
                        Label("My foods", systemImage: "bookmark")
                        Spacer()
                        let count = store.data.foods.count
                        if count > 0 { Text("\(count)").font(.roboto(.subheadline)).foregroundStyle(.secondary).monospacedDigit() }
                    }
                }
            }
            Section {
                // A short prompt rather than a full-height empty state, so the log shortcuts below stay on screen.
                if store.data.tray.isEmpty {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Build your meal").font(.roboto(.headline))
                            Text("Add foods here, or send an order from Find.").font(.roboto(.caption)).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "fork.knife").foregroundStyle(.secondary) }
                }
                ForEach(store.data.tray) { item in
                    VStack(alignment: .leading, spacing: 8) {
                      HStack(spacing: 12) {
                        Button { editingItem = item } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.food.name).font(.roboto(.headline))
                                    Text("\((item.food.cal * item.quantity).number) Cal · \((item.food.p * item.quantity).number) g protein").font(.roboto(.caption)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens it to change the amount or options")
                        Stepper(value: quantity(item), in: 0.5...50, step: 0.5) {
                            Text("× \(item.quantity.number)").font(.roboto(.subheadline, weight: .medium)).monospacedDigit()
                        }.fixedSize()
                      }
                      if item.food.chain != "mine" && !item.food.isEveryday {
                          NavigationLink {
                              MealSwapsView(portionID: item.id)
                          } label: {
                              Label("Smarter swaps", systemImage: "arrow.triangle.2.circlepath")
                                  .font(.roboto(.subheadline)).foregroundStyle(.tint)
                          }
                      }
                    }.padding(.vertical, 4)
                }.onDelete { offsets in store.change(undo: "Removed from your meal") { $0.tray.remove(atOffsets: offsets) } }
                Button { picking = true } label: { Label("Add food", systemImage: "plus.circle.fill") }
                Button { scanning = true } label: { Label("Scan barcode", systemImage: "barcode.viewfinder") }
            } footer: {
                if !store.data.tray.isEmpty { Text("Tap a food to change it. Swipe to remove it.") }
            }
            if !store.data.tray.isEmpty {
                Section("Meal totals") { NutritionView(total: Nutrition(store.data.tray)) }
                Section("Log it") {
                    TextField("Name this meal", text: $name, prompt: Text(suggestedName), axis: .vertical)
                    OffensiveTextNote(name)
                    DatePicker("Log date", selection: $date, in: ...Date(), displayedComponents: .date)
                    Picker("Meal time", selection: $mealTime) {
                        ForEach(MealTime.allCases) { Text($0.title).tag($0) }
                    }
                    Button {
                        if store.log(store.data.tray, name: title, date: date, clearTray: true, mealTime: mealTime) {
                            store.notice = "Logged to \(date.formatted(date: .abbreviated, time: .omitted))"; name = ""
                        }
                    } label: { Text("Log meal").font(.roboto(.headline)).frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(ContentFilter.flags([name]))
                        .listRowSeparator(.hidden)
                }
                Section {
                    TileRow {
                        Button {
                            if store.change({ $0.meals.append(SavedMeal(name: title, items: $0.tray)) }) { store.notice = "Meal saved" }
                        } label: { TileLabel(title: "Save for later", systemImage: "bookmark") }
                            .disabled(ContentFilter.flags([name]))
                        ShareLink(item: mealText(title, store.data.tray)) { TileLabel(title: "Share text", systemImage: "square.and.arrow.up") }
                        Button { UIPasteboard.general.string = mealText(title,store.data.tray); store.notice = "Meal copied" } label: { TileLabel(title: "Copy", systemImage: "doc.on.doc") }
                        Button { makingImage = true } label: { TileLabel(title: "Make image", systemImage: "photo") }
                    }
                }
            }
            quickLog
            if !store.data.meals.isEmpty {
                Section {
                    ForEach(store.data.meals) { meal in
                        HStack(spacing: 12) {
                            NavigationLink { SavedMealEditor(meal: meal) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(meal.name).font(.roboto(.headline))
                                    Text(Nutrition(meal.items).text).font(.roboto(.caption)).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityHint("Edit this meal's name and items")
                            Button("Add") { store.add(meal.items) }.buttonStyle(.bordered).font(.roboto(.subheadline, weight: .medium))
                                .accessibilityLabel("Add \(meal.name) to your meal")
                        }.padding(.vertical, 2)
                    }.onDelete { offsets in store.change(undo: "Deleted saved meal") { $0.meals.remove(atOffsets: offsets) } }
                } header: { Text("Saved meals") }
            }
            LeftTodaySection(model: left, mealTime: mealTime)
        }.navigationTitle("This meal")
            .toolbar { if !store.data.tray.isEmpty { Button("Clear", role: .destructive) { clear = true } } }
            .confirmationDialog("Clear this meal?", isPresented: $clear, titleVisibility: .visible) { Button("Clear meal", role: .destructive) { store.change(undo: "Cleared your meal") { $0.tray = [] } } }
            .sheet(isPresented: $picking) { NavigationStack { BrowseView(pick: { portion in store.add([portion]); picking = false }, pickTitle: "Add to meal", quickAddLabel: "Add").toolbar { Button("Done") { picking = false } } } }
            .task(id: LeftTodayModel.key(store, enabled: suggestionsOn)) { await left.refresh(store, enabled: suggestionsOn) }
            // A packet's barcode goes straight into the meal; the editor is there if the serving needs changing.
            .sheet(isPresented: $scanning) {
                BarcodeFoodFlow(savePortion: { store.add([$0]) }, actionTitle: "Add to meal") { store.add([Portion(food: $0)]) }
            }
            .sheet(item: $editingItem) { item in
                PortionEditSheet(item: item, title: "Update meal") { changed in
                    store.change(undo: "Changed \(item.food.name)") { state in
                        guard let i = state.tray.firstIndex(where: { $0.id == item.id }) else { return }
                        state.tray[i] = changed
                        state.tray = combined(state.tray)
                    }
                }
            }
            .sheet(isPresented: $makingImage) { NavigationStack { MealSharePreview(name: title, items: store.data.tray) } }
    }
    /// One-tap logging: the same meal as yesterday, or a meal you log often.
    @ViewBuilder private var quickLog: some View {
        let yesterday = QuickLog.previous(mealTime, before: date, logs: store.data.logs)
        let frequent = QuickLog.frequent(logs: store.data.logs, now: date)
        if !yesterday.isEmpty || !frequent.isEmpty {
            Section {
                if store.data.tray.isEmpty {
                    Picker("Log to", selection: $mealTime) { ForEach(MealTime.allCases) { Text($0.title).tag($0) } }
                }
                if !yesterday.isEmpty {
                    Button {
                        let items = yesterday.flatMap(\.items)
                        let name = yesterday.count == 1 ? yesterday[0].name : "Yesterday’s \(mealTime.title.lowercased())"
                        if store.log(QuickLog.copies(items), name: name, date: date, mealTime: mealTime) { store.notice = "Logged \(name)" }
                    } label: {
                        HStack {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Same as yesterday’s \(mealTime.title.lowercased())").font(.roboto(.headline))
                                    Text(yesterday.map(\.name).joined(separator: ", ")).font(.roboto(.caption)).foregroundStyle(.secondary).lineLimit(1)
                                }
                            } icon: { Image(systemName: "arrow.uturn.backward.circle.fill") }
                            Spacer()
                            Text("\(Nutrition(yesterday.flatMap(\.items)).cal.number) Cal").font(.roboto(.subheadline)).foregroundStyle(.secondary)
                        }
                    }
                }
                if !frequent.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(frequent) { entry in
                                Button {
                                    if store.log(QuickLog.copies(entry.items), name: entry.name, date: date, mealTime: mealTime) { store.notice = "Logged \(entry.name)" }
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.name).font(.roboto(.subheadline, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                        Text("\(Nutrition(entry.items).cal.number) Cal · \(Nutrition(entry.items).p.number) g protein")
                                            .font(.roboto(.caption)).foregroundStyle(.secondary)
                                    }
                                    .frame(width: min(cardWidth, 300), alignment: .topLeading).frame(minHeight: 76, alignment: .topLeading).padding(12)
                                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Log \(entry.name) to \(mealTime.title)")
                            }
                        }
                    }
                    .scrollClipDisabled()
                }
            } header: { Text("Log again") } footer: {
                let day = Calendar.current.isDateInToday(date) ? "today" : "on " + date.formatted(date: .abbreviated, time: .omitted)
                Text("Logs straight to \(mealTime.title.lowercased()) \(day), without changing the meal you're building.")
            }
        }
    }
    private func quantity(_ item: Portion) -> Binding<Double> {
        Binding(get: { store.data.tray.first { $0.id == item.id }?.quantity ?? item.quantity }, set: { value in
            if value > 0, value.isFinite { store.change { state in if let i = state.tray.firstIndex(where: { $0.id == item.id }) { state.tray[i].quantity = value } } }
        })
    }
}

/// Changes a saved meal in place: rename it, change amounts, add foods and take them out.
/// Nothing is saved until Save, so backing out leaves the meal as it was.
struct SavedMealEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SavedMeal
    @State private var picking = false
    @State private var confirmingDelete = false
    @State private var editingItem: Portion?
    @State private var original: SavedMeal

    init(meal: SavedMeal) {
        // A meal saved with a recipe beside other foods lists its ingredients, as a meal built today does.
        var meal = meal
        meal.items = combined(meal.items)
        _original = State(initialValue: meal)
        _draft = State(initialValue: meal)
    }

    private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var changed: Bool { draft != original }

    var body: some View {
        LeanrList {
            Section("Name") {
                TextField("Meal name", text: $draft.name, axis: .vertical).font(.roboto(.body))
                OffensiveTextNote(draft.name)
            }
            Section {
                if draft.items.isEmpty {
                    Text("Add at least one food to keep this meal.").foregroundStyle(.secondary)
                }
                ForEach($draft.items) { $item in
                    HStack(spacing: 12) {
                        Button { editingItem = item } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.food.name).font(.roboto(.headline))
                                    Text("\((item.food.cal * item.quantity).number) Cal · \((item.food.p * item.quantity).number) g protein")
                                        .font(.roboto(.caption)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens it to change the amount or options")
                        Stepper(value: $item.quantity, in: 0.5...50, step: 0.5) {
                            Text("× \(item.quantity.number)").font(.roboto(.subheadline, weight: .medium)).monospacedDigit()
                        }
                        .fixedSize()
                        .accessibilityLabel("\(item.food.name) amount")
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { draft.items.remove(atOffsets: $0) }
                Button { picking = true } label: { Label("Add food", systemImage: "plus.circle.fill") }
            } header: { Text("Items") } footer: { Text("Tap an item to change it. Swipe to remove it.") }
            if !draft.items.isEmpty {
                Section("Totals") { NutritionView(total: Nutrition(draft.items)) }
            }
            Section {
                Button("Delete saved meal", role: .destructive) { confirmingDelete = true }
            }
        }
        .navigationTitle("Edit meal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    var meal = draft; meal.name = trimmedName
                    if store.updateMeal(meal) { store.notice = "Saved \(meal.name)"; dismiss() }
                }
                .disabled(!changed || trimmedName.isEmpty || draft.items.isEmpty || ContentFilter.flags([trimmedName]))
            }
        }
        .sheet(isPresented: $picking) {
            NavigationStack {
                BrowseView(pick: { portion in
                    var fresh = portion; fresh.id = UUID()
                    if let i = draft.items.firstIndex(where: { $0.food == fresh.food }) { draft.items[i].quantity += fresh.quantity }
                    else { draft.items.append(fresh) }
                    draft.items = combined(draft.items)
                    picking = false
                }, pickTitle: "Add to \(trimmedName.isEmpty ? "meal" : trimmedName)", quickAddLabel: "Add")
                .toolbar { Button("Done") { picking = false } }
            }
        }
        .sheet(item: $editingItem) { item in
            PortionEditSheet(item: item, title: "Update item") { changed in
                guard let i = draft.items.firstIndex(where: { $0.id == item.id }) else { return }
                draft.items[i] = changed
                draft.items = combined(draft.items)
            }
        }
        .confirmationDialog("Delete \(original.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete saved meal", role: .destructive) {
                if store.change(undo: "Deleted saved meal", { $0.meals.removeAll { $0.id == original.id } }) { dismiss() }
            }
        }
    }
}

/// Reopens a food already in a meal or recipe on its food screen, with its amount and options as they were.
/// `save` gets the changed portion under the same ID, so it takes the old one's place.
struct PortionEditSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let item: Portion
    let title: String
    let save: (Portion) -> Void
    var body: some View {
        NavigationStack {
            FoodDetailView(food: store.baseFood(for: item), editing: item, pick: { portion in
                var changed = portion; changed.id = item.id
                save(changed); dismiss()
            }, pickTitle: title)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
