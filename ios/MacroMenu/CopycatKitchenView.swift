import SwiftUI

/// Home versions of takeaway items, ranked against the chains' own figures.
struct CopycatKitchenView: View {
    @Environment(AppStore.self) private var store
    @State private var sort = CopycatSort.saving

    var body: some View {
        let items = CopycatBook.bundled.comparisons(menu: store.catalog.foods)
        LeanrList {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(items.filter { $0.verdict == .homeLighter }.count) of \(items.count) beat the shop")
                        .font(.roboto(.title2, weight: .bold)).monospacedDigit()
                    Text("Cooked as written. With every swap on, \(items.filter { CopycatVerdict($0.change($0.lean)) == .homeLighter }.count) do.")
                        .font(.roboto(.subheadline)).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }
            Section {
                ChipRow {
                    ForEach(CopycatSort.allCases) { option in
                        Chip(title: option.title, selected: sort == option) { sort = option }
                    }
                }
            }
            Section {
                ForEach(sort.sorted(items)) { item in
                    NavigationLink { CopycatRecipeView(item: item) } label: { CopycatListRow(item: item) }
                }
            } footer: { CopycatNotes() }
        }
        .navigationTitle("Copycat Kitchen").navigationBarTitleDisplayMode(.inline)
    }
}

private struct CopycatListRow: View {
    @Environment(AppStore.self) private var store
    var item: CopycatComparison
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) { name; Spacer(minLength: 4); CopycatVerdictPill(verdict: item.verdict) }
                VStack(alignment: .leading, spacing: 4) { name; CopycatVerdictPill(verdict: item.verdict) }
            }
            Text("\(store.chainName(item.shopFood.chain)) · \(item.recipe.name)").font(.roboto(.caption)).foregroundStyle(.secondary)
            HStack(spacing: 0) {
                column("Shop", item.shop, nil)
                column("Home", item.home, item.change(item.home))
                column("Swaps", item.lean, item.change(item.lean))
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.shopName), \(store.chainName(item.shopFood.chain)). \(item.verdict.title). Shop \(item.shop.cal.rounded().number) calories, home \(item.home.cal.rounded().number), with swaps \(item.lean.cal.rounded().number).")
    }
    private var name: some View { Text(item.shopName).font(.roboto(.headline)).foregroundStyle(.primary) }
    private func column(_ title: String, _ total: Nutrition, _ change: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.roboto(.caption)).foregroundStyle(.secondary)
            Text(total.cal.rounded().number).font(.roboto(.headline)).monospacedDigit()
            Text(change.map(copycatChange) ?? "Cal").font(.roboto(.caption)).foregroundStyle(.secondary).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func copycatChange(_ value: Int) -> String { value == 0 ? "level" : "\(value > 0 ? "+" : "−")\(abs(value))%" }

private struct CopycatVerdictPill: View {
    var verdict: CopycatVerdict
    var body: some View {
        Text(verdict.title).font(.roboto(.caption, weight: .medium)).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.fill.tertiary, in: Capsule())
            .foregroundStyle(style)
    }
    private var style: AnyShapeStyle {
        switch verdict {
        case .homeLighter: AnyShapeStyle(.tint)
        case .shopLighter: AnyShapeStyle(.orange)
        case .level: AnyShapeStyle(.secondary)
        }
    }
}

private struct CopycatNotes: View {
    var body: some View {
        Text("Shop figures are each chain's published ones. Home figures add up every ingredient by weight from USDA FoodData Central, so your own products will differ a little. These are unofficial recipes, not made or approved by any chain named here.")
    }
}

/// One home recipe beside the shop's figures, with swaps that change the numbers as you tick them.
struct CopycatRecipeView: View {
    @Environment(AppStore.self) private var store
    var item: CopycatComparison
    @State private var swaps: Set<String> = []
    @State private var serves: Int
    @State private var logging: Food?

    init(item: CopycatComparison) {
        self.item = item
        _serves = State(initialValue: item.recipe.serves)
    }
    private var recipe: CopycatRecipe { item.recipe }
    private var total: Nutrition { CopycatBook.bundled.nutrition(recipe, swaps: swaps) }
    private var food: Food { CopycatBook.bundled.food(recipe, swaps: swaps, shopName: item.shopName) }
    private var rows: [CopycatRow] { recipe.rows(swaps: swaps) }
    private var shoppingList: String {
        (["\(recipe.name), \(serves) \(serves == 1 ? "serve" : "serves")"] + rows.map { "\($0.label): \(gramText($0.g * Double(serves)))" }).joined(separator: "\n")
    }

    var body: some View {
        LeanrList {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Home version of \(store.chainName(item.shopFood.chain)) \(item.shopName) · \(recipe.time)").font(.roboto(.caption)).foregroundStyle(.secondary)
                    Text(recipe.hook)
                    Text(recipe.verdict).font(.roboto(.subheadline)).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }
            Section {
                CopycatComparisonView(shop: item.shop, home: total)
                if item.shopFood.mismatch {
                    Label("\(store.chainName(item.shopFood.chain)) publishes an energy figure that doesn’t match its own macros, so compare the macros here.", systemImage: "exclamationmark.triangle")
                        .font(.roboto(.caption)).foregroundStyle(.orange)
                }
            } header: { Text("Shop vs home, \(recipe.serving)") }
            Section("Make it lighter") {
                ForEach(recipe.swaps) { swap in
                    Toggle(isOn: Binding(get: { swaps.contains(swap.id) }, set: { on in if on { swaps.insert(swap.id) } else { swaps.remove(swap.id) } })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(swap.label)
                            Text(swap.why).font(.roboto(.caption)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                Stepper("\(serves) \(serves == 1 ? "serve" : "serves")", value: $serves, in: 1...12)
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.label).font(.roboto(.subheadline, weight: .medium)).foregroundStyle(row.swapped ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                            Text(row.measure).font(.roboto(.caption)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(gramText(row.g * Double(serves))).font(.roboto(.subheadline)).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
                ShareLink(item: shoppingList) { Label("Share shopping list", systemImage: "cart") }
            } header: { Text("Ingredients") } footer: {
                Text("Weights are raw and for all serves; measures are for one. Flour and crumbs count what sticks to the food, not what's left in the bowl.")
            }
            Section("Method") {
                ForEach(Array(recipe.method.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(index + 1)").font(.display(.title3)).foregroundStyle(.tint).monospacedDigit().accessibilityHidden(true)
                        Text(step)
                    }.accessibilityLabel("Step \(index + 1). \(step)").accessibilityElement(children: .ignore)
                }
            }
            Section {} footer: {
                Text("Take chicken to 75°C and mince to 71°C in the centre. Fat that renders out of mince isn't taken off, so burger figures run slightly high.")
            }
        }
        .navigationTitle(recipe.name).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save to My foods", systemImage: "bookmark") {
                    if let saved = store.saveToMyFoods(food) { store.notice = "Saved \(saved.name) to My foods" }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button { logging = food } label: { Text("Log it · \(total.cal.rounded().number) Cal").frame(maxWidth: .infinity) }
            }
        }
        .navigationDestination(item: $logging) { FoodDetailView(food: $0) }
    }

    private func gramText(_ grams: Double) -> String { "\(grams < 10 ? grams.tenth.number : grams.rounded().number) g" }
}

/// Shop and home side by side: a grey bar for the shop, the macro's own colour for home.
private struct CopycatComparisonView: View {
    @AppStorage(MacroColours.proteinKey) private var proteinColour = "blue"
    @AppStorage(MacroColours.carbsKey) private var carbsColour = "orange"
    @AppStorage(MacroColours.fatKey) private var fatColour = "red"
    private func colour(_ key: String) -> Color {
        MacroColours.colour(key, choices: Premium.isUnlocked ? ["p": proteinColour, "c": carbsColour, "f": fatColour] : [:])
    }
    var shop: Nutrition
    var home: Nutrition

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CopycatBar(title: "Calories", shop: shop.cal, home: home.cal, unit: "Cal", better: .lower, fill: AnyShapeStyle(.tint))
            CopycatBar(title: "Protein", shop: shop.p, home: home.p, unit: "g", better: .higher, fill: AnyShapeStyle(colour("p")))
            CopycatBar(title: "Carbs", shop: shop.c, home: home.c, unit: "g", better: nil, fill: AnyShapeStyle(colour("c")))
            CopycatBar(title: "Fat", shop: shop.f, home: home.f, unit: "g", better: .lower, fill: AnyShapeStyle(colour("f")))
            Divider()
            VStack(spacing: 6) {
                HStack {
                    Spacer()
                    Text("Shop").frame(width: 84, alignment: .trailing)
                    Text("Home").frame(width: 84, alignment: .trailing)
                }.font(.roboto(.caption)).foregroundStyle(.secondary).accessibilityHidden(true)
                ForEach(nutrientNames.dropFirst(4).filter { ["sat", "sugar", "fibre", "sodium"].contains($0.key) }, id: \.key) { n in
                    HStack {
                        Text(n.label).frame(maxWidth: .infinity, alignment: .leading)
                        Text(shop.nut[n.key].map { "\($0.number) \(n.unit)" } ?? "Not published").frame(width: 84, alignment: .trailing)
                            .foregroundStyle(shop.nut[n.key] == nil ? .secondary : .primary)
                        Text("\(n.key == "sodium" ? (home.nut[n.key] ?? 0).rounded().number : (home.nut[n.key] ?? 0).number)\(home.partial.contains(n.key) ? "+" : "") \(n.unit)").frame(width: 84, alignment: .trailing)
                    }
                    .font(.roboto(.caption)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                    .accessibilityElement(children: .combine)
                }
            }
        }.padding(.vertical, 6)
    }
}

private struct CopycatBar: View {
    enum Direction { case higher, lower }
    var title: String
    var shop: Double
    var home: Double
    var unit: String
    var better: Direction?
    var fill: AnyShapeStyle

    private var close: Bool { abs(home - shop) < max(shop, home) * 0.02 }
    private var gap: some ShapeStyle {
        guard let better, !close else { return AnyShapeStyle(.secondary) }
        return (better == .higher) == (home > shop) ? AnyShapeStyle(.tint) : AnyShapeStyle(.orange)
    }
    private var gapText: String {
        close ? "level" : "\(home > shop ? "+" : "−")\(abs(home - shop).rounded().number) \(unit)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.roboto(.subheadline, weight: .medium))
                Spacer()
                Text(gapText).font(.roboto(.caption, weight: .medium)).foregroundStyle(gap).monospacedDigit()
            }
            line(shop, AnyShapeStyle(.quaternary))
            line(home, fill)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): shop \(shop.rounded().number) \(unit), home \(home.rounded().number) \(unit)")
    }

    private func line(_ value: Double, _ style: AnyShapeStyle) -> some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                Capsule().fill(style).frame(width: geo.size.width * value / max(shop, home, 1))
            }.frame(height: 6).figureChange(value)
            Text("\(value.rounded().number) \(unit)").font(.roboto(.caption)).monospacedDigit().rolling(value)
                .lineLimit(1).frame(minWidth: 72, alignment: .trailing)
        }
    }
}
