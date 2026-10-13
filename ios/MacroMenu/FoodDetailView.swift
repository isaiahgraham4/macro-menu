import SwiftUI

struct FoodDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let initial: Food
    /// One of your own foods or recipes shows its latest figures, so an edit appears here at once.
    var food: Food { initial.chain == "mine" ? (store.data.foods.first { $0.id == initial.id } ?? initial) : initial }
    var pick: ((Portion) -> Void)?
    var pickTitle = "Use this portion"
    /// Where the log button goes by default: yesterday instead of today, and a meal other than the one the clock suggests.
    var logYesterday = false
    var logMeal: MealTime?
    @State private var editing = false

    init(food: Food, pick: ((Portion) -> Void)? = nil, pickTitle: String = "Use this portion", logYesterday: Bool = false, logMeal: MealTime? = nil) {
        initial = food; self.pick = pick; self.pickTitle = pickTitle; self.logYesterday = logYesterday; self.logMeal = logMeal
    }
    /// True for a food or recipe you made yourself and can still change.
    private var editable: Bool { food.chain == "mine" && store.data.foods.contains { $0.id == food.id } }
    @State private var quantity = 1.0
    @State private var useWeight = false
    @State private var weight = 100.0
    @State private var changes: [String: Double] = [:]
    @State private var customName = ""
    @State private var ownAdjustment: Food?
    @State private var editingAdjustment = false
    @State private var subtract = false
    /// The custom order pinned from this screen, so the pin button can show it and unpin it.
    @State private var pinnedCustom: Food?
    /// What pinning a custom order saves: the order as set up now, under its own ID.
    private var pinnable: Food {
        if let pinnedCustom, pinnedCustom.name == adjusted.name, pinnedCustom.kj == adjusted.kj { return pinnedCustom }
        var value = adjusted; value.id = UUID().uuidString; return value
    }
    var adjusted: Food { food.customised(changes, adding: ownAdjustment, subtract: subtract, name: customName) }
    var amount: Double { useWeight ? weight / (food.servingWeight?.0 ?? 100) : quantity }
    var portion: Portion { Portion(food: adjusted, quantity: amount) }
    /// "McDonald's", "Hungry Jack's" or "KFC's", for "… energy" and "… figures".
    var owner: String { let name = store.chainName(food.chain); return name.hasSuffix("'s") || name.hasSuffix("’s") ? name : name + "'s" }
    var customized: Bool { changes.values.contains { $0 > 0 } || ownAdjustment != nil }
    var body: some View {
        LeanrForm {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(food.name).font(.display(.title2))
                    Text(food.serve.isEmpty ? store.chainName(food.chain) : "\(store.chainName(food.chain)) · \(food.serve)").foregroundStyle(.secondary)
                }.padding(.vertical, 4)
                if let note = food.note { Text(note).font(.roboto(.caption)) }
                if food.mismatch { Label("Published energy doesn’t match the listed macros.", systemImage: "exclamationmark.triangle").font(.roboto(.caption)).foregroundStyle(.orange) }
            }
            Section("Nutrition for your portion") { NutritionView(total: Nutrition([portion])) }
            Section("Portion") {
                if let serving = food.servingWeight {
                    Picker("Measure in", selection: $useWeight) {
                        Text("Servings").tag(false); Text(serving.1 == "g" ? "Grams" : "mL").tag(true)
                    }.pickerStyle(.segmented)
                        // Start from one serving's weight, so switching doesn't change the portion.
                        .onChange(of: useWeight) { if useWeight { weight = (serving.0 * quantity).tenth } else { quantity = ((weight / serving.0) * 100).rounded() / 100 } }
                    if useWeight { NumberField(title: "Amount (\(serving.1))", value: $weight) }
                    else { NumberField(title: "Servings", value: $quantity, places: 2) }
                } else { NumberField(title: "Servings", value: $quantity, places: 2) }
                Text("\(amount.number) × \(food.serve)").font(.roboto(.caption)).foregroundStyle(.secondary)
            }
            if food.chain != "mine" && !food.isEveryday {
                let removals = (food.modifiers ?? []).filter { $0.kind == "r" }
                if !removals.isEmpty {
                    Section {
                        ForEach(removals, id: \.key) { mod in
                            Toggle(isOn: selection(mod)) {
                                HStack {
                                    Text(mod.name)
                                    Spacer()
                                    Text("\((mod.kj / 4.184).rounded().number) Cal").font(.roboto(.subheadline)).foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                        }
                    } header: {
                        Text("Remove ingredients")
                    } footer: {
                        if food.chain == "grilld" {
                            Text("Sauce removals are estimates: Grill'd's own figures for that sauce sold as a dip, for about 15 g, since Grill'd doesn't publish how much goes on each burger. Other removals are the difference between burgers Grill'd publishes.")
                        } else if removals.contains(where: { $0.est == true }) {
                            Text("Calories for each ingredient are from \(store.chainName(food.chain)). For parts it doesn't sell on their own, protein, carbs and fat are estimated from the ingredient type and other nutrients stay as listed.")
                        } else if food.chain == "grilld" {
                            Text("Worked out from Grill'd figures for burgers published with and without it.")
                        } else if ["hj", "kfc", "rr", "oporto"].contains(food.chain) {
                            Text("Worked out from \(owner) figures for the same item with and without it.")
                        } else {
                            Text("Nutrition for each ingredient is from \(owner) published figures.")
                        }
                    }
                }
                let additions = (food.modifiers ?? []).filter { $0.kind == "f" || $0.kind == "a" }
                Section {
                    ForEach([("f","Extra filling"),("a","Extras"),("s","Swaps")], id: \.0) { kind, label in
                        let mods = (food.modifiers ?? []).filter { $0.kind == kind }
                        if !mods.isEmpty {
                            DisclosureGroup(label) {
                                ForEach(mods, id: \.key) { mod in
                                    if kind == "s" {
                                        Toggle(mod.name, isOn: selection(mod))
                                    } else {
                                        Stepper(value: Binding(get: { changes[mod.key] ?? 0 }, set: { changes[mod.key] = $0 }), in: 0...5) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("\(mod.name) · \((changes[mod.key] ?? 0).number)")
                                                Text("+\((mod.kj / 4.184).rounded().number) Cal each").font(.roboto(.caption)).foregroundStyle(.secondary).monospacedDigit()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if let ownAdjustment {
                        HStack {
                            Text((subtract ? "Without " : "Extra ") + ownAdjustment.name)
                            Spacer()
                            Button("Undo", role: .destructive) { self.ownAdjustment = nil }.buttonStyle(.borderless)
                        }
                    } else {
                        Button { subtract = true; editingAdjustment = true } label: { Label("Remove something else", systemImage: "minus.circle") }
                        Button { subtract = false; editingAdjustment = true } label: { Label("Add something else", systemImage: "plus.circle") }
                    }
                    if customized { TextField("Name this custom order", text: $customName) }
                } header: {
                    Text("Customise your order")
                } footer: {
                    if additions.contains(where: { $0.est == true }) {
                        Text("Extras use \(owner) energy for that ingredient. For parts it doesn't sell on their own, protein, carbs and fat are estimated from the ingredient type.")
                    } else if food.chain == "grilld" && (food.modifiers ?? []).contains(where: { $0.kind == "s" }) {
                        Text("Bun and patty swaps and extras are the difference between burgers Grill'd publishes. Grill'd doesn't publish single ingredients, so use Remove something else for anything else.")
                    } else if ["hj", "kfc", "rr", "oporto"].contains(food.chain) && additions.contains(where: { !$0.key.hasPrefix("item:") }) {
                        Text("Extras are the difference between two \(store.chainName(food.chain)) items sold with and without them.")
                    } else if additions.contains(where: { $0.key.hasPrefix("item:") && $0.kind == "f" }) {
                        Text("Extra fillets use \(owner) figures for the fillet sold on its own.")
                    }
                }
            }
            if pick == nil { NearestPlaceSection(chain: food.chain) }
            if let chain = store.chain(food.chain), chain.id != "mine" { FoodSourceSection(chain: chain) }
            if food.isEveryday { EverydaySourceSection(food: food) }
            if customized {
                Section {
                    Button { saveCustom() } label: { Label("Save custom order to My foods", systemImage: "bookmark") }.disabled(!adjusted.isValid)
                }
            }
        }.navigationTitle("Food details").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if editable {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { editing = true } label: { Text(food.ingredients != nil ? "Edit recipe" : "Edit") }
                            .accessibilityLabel(food.ingredients != nil ? "Edit this recipe" : "Edit this food")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // A custom order is pinned as it's set up now, as its own food.
                    let target = customized ? pinnable : food
                    let pinned = store.isPinned(target)
                    Button { store.togglePin(target); if customized { pinnedCustom = pinned ? nil : target } } label: {
                        Image(systemName: pinned ? "pin.fill" : "pin")
                    }.accessibilityLabel(pinned ? "Unpin" : "Pin to top")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: mealText(adjusted.name, [portion])) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Share nutrition")
                }
            }
            .safeAreaInset(edge: .bottom) {
                BottomActionBar {
                    if pick != nil {
                        Button { addPortion() } label: { Text("\(pickTitle) · \(Nutrition([portion]).cal.number) Cal").frame(maxWidth: .infinity) }
                            .disabled(!portion.isValid)
                    } else {
                        let suggested = logMeal ?? MealTime.suggested()
                        HStack(spacing: 10) {
                            Button { logPortion(suggested, yesterday: logYesterday) } label: {
                                Text("Log to \(logYesterday ? "yesterday’s \(suggested.title.lowercased())" : suggested.title) · \(Nutrition([portion]).cal.number) Cal")
                                    .lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
                            }
                            Menu {
                                Section("Today") {
                                    ForEach(MealTime.allCases.filter { logYesterday || $0 != suggested }) { meal in
                                        Button(meal.title) { logPortion(meal, yesterday: false) }
                                    }
                                }
                                YesterdayMenu { logPortion($0, yesterday: true) }
                                Divider()
                                Button("Add to the meal I'm building", systemImage: "fork.knife") { addPortion() }
                            } label: { Image(systemName: "ellipsis").frame(width: 24, height: 22) }
                                .buttonStyle(.bordered).accessibilityLabel("More ways to add")
                        }.disabled(!portion.isValid)
                    }
                }
            }
            .sheet(isPresented: $editing) {
                NavigationStack {
                    if food.ingredients != nil { RecipeEditor(food: food) }
                    else { FoodEditor(food: food) { store.saveFood($0) } }
                }
            }
            .sheet(isPresented: $editingAdjustment) {
                NavigationStack { FoodEditor(food: nil) { value in ownAdjustment = value; editingAdjustment = false; return true } }
            }
    }
    /// On/off options (removals and swaps); turning one on clears others in the same group.
    private func selection(_ mod: Modifier) -> Binding<Bool> {
        Binding(get: { (changes[mod.key] ?? 0) > 0 }, set: { enabled in
            if enabled, let group = mod.group {
                for other in food.modifiers ?? [] where other.group == group { changes[other.key] = 0 }
            }
            changes[mod.key] = enabled ? 1 : 0
        })
    }
    private func addPortion() {
        var value = portion
        if customized { value.food.id = UUID().uuidString }
        if let pick { pick(value) } else { store.add([value]); dismiss() }
    }
    private func logPortion(_ mealTime: MealTime, yesterday: Bool) {
        var value = portion
        if customized { value.food.id = UUID().uuidString }
        if store.logNow([value], name: value.food.name, mealTime: mealTime, yesterday: yesterday) { dismiss() }
    }
    private func saveCustom() {
        var value = adjusted; value.id = UUID().uuidString; value.chain = "mine"
        if store.saveFood(value) { store.notice = "Custom order saved" }
    }
}

/// Where an everyday food's figures come from.
struct EverydaySourceSection: View {
    let food: Food
    var body: some View {
        Section {
            LabeledContent("From", value: "USDA FoodData Central")
            if let url = food.everydaySource { Link("View this food at FoodData Central", destination: url) }
        } header: { Text("Source") } footer: {
            Text("Average figures for this kind of food from the U.S. Department of Agriculture (public domain). Brands, varieties and cooking change them, so use the label when there is one.")
        }
    }
}

/// Where a restaurant food's figures come from, so every number can be traced to the chain's own information.
struct FoodSourceSection: View {
    @Environment(AppStore.self) private var store
    let chain: Chain
    var body: some View {
        Section {
            if let how = chain.how { LabeledContent("From", value: how) }
            if let src = chain.src { Text(src).font(.roboto(.caption)).foregroundStyle(.secondary) }
            if let date = store.menuDate { LabeledContent("Menu snapshot", value: date.formatted(date: .abbreviated, time: .omitted)) }
            if let raw = chain.url, let url = URL(string: raw) { Link("View \(chain.name)'s nutrition information", destination: url) }
        } header: { Text("Source") } footer: {
            Text("Figures are \(chain.name)'s own published information, as at the snapshot date. Leanr isn't affiliated with \(chain.name). Spot something wrong? Let me know through \(AppInfo.contactText).")
        }
    }
}
