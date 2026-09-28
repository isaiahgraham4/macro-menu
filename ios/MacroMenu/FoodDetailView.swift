import SwiftUI

struct FoodDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var food: Food
    var pick: ((Portion) -> Void)?
    @State private var quantity = 1.0
    @State private var useWeight = false
    @State private var weight = 100.0
    @State private var changes: [String: Double] = [:]
    @State private var customName = ""
    @State private var ownAdjustment: Food?
    @State private var editingAdjustment = false
    @State private var subtract = false
    var adjusted: Food {
        var result = food
        let selected = (food.modifiers ?? []).filter { (changes[$0.key] ?? 0) > 0 }
        var names: [String] = []
        for mod in selected {
            let q = changes[mod.key] ?? 0
            result.kj += mod.kj * q; result.p += mod.p * q
            if let c = result.c, let delta = mod.c { result.c = c + delta * q } else { result.c = nil }
            if let f = result.f, let delta = mod.f { result.f = f + delta * q } else { result.f = nil }
            for key in Array((result.nut ?? [:]).keys) {
                if let delta = mod.nut?[key] { result.nut?[key, default: 0] += delta * q }
                // Estimated removals leave other nutrients as listed rather than hiding them.
                else if mod.est != true { result.nut?.removeValue(forKey: key) }
            }
            if let price = result.price, let delta = mod.price { result.price = max(0, price + delta * q) } else { result.price = nil }
            names.append("\(q > 1 ? q.number + " × " : "")\(mod.name)")
        }
        if let ownAdjustment {
            let sign = subtract ? -1.0 : 1.0
            result.kj += ownAdjustment.kj * sign; result.p += ownAdjustment.p * sign
            if let c = result.c, let delta = ownAdjustment.c { result.c = c + delta * sign } else { result.c = nil }
            if let f = result.f, let delta = ownAdjustment.f { result.f = f + delta * sign } else { result.f = nil }
            for key in Array((result.nut ?? [:]).keys) {
                if let delta = ownAdjustment.nut?[key] { result.nut?[key, default: 0] += delta * sign }
                else { result.nut?.removeValue(forKey: key) }
            }
            if let price = result.price, let delta = ownAdjustment.price { result.price = max(0,price + delta * sign) } else { result.price = nil }
            names.append((subtract ? "Without " : "Extra ") + ownAdjustment.name)
        }
        if !names.isEmpty {
            result.kj = max(0,result.kj); result.cal = (result.kj / 4.184).rounded(); result.p = max(0,result.p)
            result.c = result.c.map { max(0,$0) }; result.f = result.f.map { max(0,$0) }
            result.nut = result.nut?.mapValues { max(0,$0) }
            result.name = customName.isEmpty ? food.name + " · " + names.joined(separator: ", ") : customName
            result.note = "Based on \(food.name). " + names.joined(separator: ", ")
            result.modifiers = nil
        }
        return result
    }
    var amount: Double { useWeight ? weight / (food.servingWeight?.0 ?? 100) : quantity }
    var portion: Portion { Portion(food: adjusted, quantity: amount) }
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
                    Toggle("Measure in \(serving.1)", isOn: $useWeight)
                    if useWeight { NumberField(title: "Amount (\(serving.1))", value: $weight) }
                    else { NumberField(title: "Servings", value: $quantity, places: 2) }
                } else { NumberField(title: "Servings", value: $quantity, places: 2) }
                Text("\(amount.number) × \(food.serve)").font(.roboto(.caption)).foregroundStyle(.secondary)
            }
            if food.chain != "mine" {
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
                        if removals.contains(where: { $0.est == true }) {
                            Text("Calories for each ingredient are from \(store.chainName(food.chain)). Protein, carbs and fat are estimated from the ingredient type; saturated fat, sugars and sodium stay as listed.")
                        }
                    }
                }
                Section("Customise your order") {
                    ForEach([("f","Extra filling"),("a","Extras"),("s","Swaps")], id: \.0) { kind, label in
                        let mods = (food.modifiers ?? []).filter { $0.kind == kind }
                        if !mods.isEmpty {
                            DisclosureGroup(label) {
                                ForEach(mods, id: \.key) { mod in
                                    if kind == "s" {
                                        Toggle(mod.name, isOn: selection(mod))
                                    } else {
                                        Stepper("\(mod.name) · \((changes[mod.key] ?? 0).number)", value: Binding(get: { changes[mod.key] ?? 0 }, set: { changes[mod.key] = $0 }), in: 0...5)
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
                }
            }
            if pick == nil { NearestPlaceSection(chain: food.chain) }
            if customized {
                Section {
                    Button { saveCustom() } label: { Label("Save custom order to My foods", systemImage: "bookmark") }.disabled(!adjusted.isValid)
                }
            }
        }.navigationTitle("Food details").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: mealText(adjusted.name, [portion])) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Share nutrition")
                }
            }
            .safeAreaInset(edge: .bottom) {
                BottomActionBar {
                    Button { addPortion() } label: {
                        Text(pick == nil ? "Add to meal · \(Nutrition([portion]).cal.number) Cal" : "Use this portion").frame(maxWidth: .infinity)
                    }.disabled(!portion.isValid)
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
    private func saveCustom() {
        var value = adjusted; value.id = UUID().uuidString; value.chain = "mine"
        if store.saveFood(value) { store.notice = "Custom order saved" }
    }
}
