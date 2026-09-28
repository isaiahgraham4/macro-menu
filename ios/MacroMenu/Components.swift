import SwiftUI
import UniformTypeIdentifiers

struct FoodDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = bytes
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct NumberField: View {
    var title: String
    @Binding var value: Double
    var body: some View {
        HStack { Text(title); Spacer(); TextField(title, value: $value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 120) }
    }
}
struct OptionalNumberField: View {
    var title: String
    @Binding var value: Double?
    var body: some View {
        HStack { Text(title); Spacer(); TextField("Not set", value: $value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 120).accessibilityLabel(title) }
    }
}
struct NutritionView: View {
    @AppStorage(MacroColours.proteinKey) private var proteinColour = "blue"
    @AppStorage(MacroColours.carbsKey) private var carbsColour = "orange"
    @AppStorage(MacroColours.fatKey) private var fatColour = "red"
    private func colour(_ key: String) -> Color {
        MacroColours.colour(key, choices: Premium.isUnlocked ? ["p": proteinColour, "c": carbsColour, "f": fatColour] : [:])
    }
    var total: Nutrition
    var details = true
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(total.cal.number).font(.roboto(.largeTitle, weight: .bold))
                Text("Cal").foregroundStyle(.secondary)
                Spacer()
                Text(total.priceText).font(.roboto(.subheadline, weight: .medium))
            }
            HStack(spacing: 0) {
                macro("Protein", total.p, false, colour("p"))
                macro("Carbs", total.c, total.missingCarbs, colour("c"))
                macro("Fat", total.f, total.missingFat, colour("f"))
            }
            GeometryReader { geo in
                let energy = max(1, total.p * 4 + total.c * 4 + total.f * 9)
                HStack(spacing: 2) {
                    colour("p").frame(width: max(0, geo.size.width * total.p * 4 / energy - 2))
                    colour("c").frame(width: max(0, geo.size.width * total.c * 4 / energy - 2))
                    colour("f")
                }.clipShape(Capsule())
            }.frame(height: 6).accessibilityHidden(true)
            if total.missingCarbs || total.missingFat { Text("+ Partial total: some items don’t publish all macros.").font(.roboto(.caption)).foregroundStyle(.secondary) }
            if details {
                Text("\(total.kj.number) kJ").font(.roboto(.caption)).foregroundStyle(.secondary)
                ForEach(nutrientNames.dropFirst(4), id: \.key) { n in
                    if let value = total.nut[n.key] {
                        LabeledContent(n.label, value: "\(value.number) \(n.unit)\(total.partial.contains(n.key) ? " (partial)" : "")").font(.roboto(.subheadline))
                    }
                }
                ForEach(total.nut.keys.filter { key in !nutrientNames.contains { $0.key == key } }.sorted(), id: \.self) { key in
                    LabeledContent(key, value: "\((total.nut[key] ?? 0).number)\(total.partial.contains(key) ? " (partial)" : "")").font(.roboto(.subheadline))
                }
            }
        }.padding(.vertical, 8)
    }
    private func macro(_ name: String, _ value: Double, _ partial: Bool, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.roboto(.caption)).foregroundStyle(.secondary)
            Text("\(value.number)\(partial ? "+" : "") g").font(.roboto(.headline)).foregroundStyle(color)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct FoodRow: View {
    @Environment(AppStore.self) private var store
    var food: Food
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(food.name).font(.roboto(.headline)).foregroundStyle(.primary)
            Text(food.serve.isEmpty ? store.chainName(food.chain) : "\(store.chainName(food.chain)) · \(food.serve)").font(.roboto(.caption)).foregroundStyle(.secondary)
            HStack {
                Text("\(food.cal.number) Cal · \(food.p.number) g protein").font(.roboto(.subheadline))
                Spacer()
                if let price = food.price { Text((food.pf == true ? "From " : "") + price.formatted(.currency(code: "AUD"))).font(.roboto(.caption)) }
            }.foregroundStyle(.secondary)
        }.padding(.vertical,4)
    }
}
struct SourcesView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        LeanrList {
            Section { Text("Bundled Australian menu snapshot from 24 September 2026. Prices are Melbourne CBD pick-up prices and vary by store. Missing nutrients stay unknown. Custom orders and recipes are estimates based on their ingredients.") }
            ForEach(store.catalog.chains.filter { $0.id != "mine" }) { chain in
                Section(chain.name) {
                    Text(chain.src ?? "").font(.roboto(.subheadline))
                    Text(chain.psrc ?? "").font(.roboto(.caption)).foregroundStyle(.secondary)
                    if let raw = chain.url, let url = URL(string: raw) { Link("View source", destination: url) }
                }
            }
        }.navigationTitle("Menu sources")
    }
}
struct MealShareCard: View {
    @AppStorage(AppAccent.storageKey) private var accentRaw = AppAccent.standard.rawValue
    var name: String
    var items: [Portion]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("MACRO MENU", systemImage: "fork.knife").font(.roboto(.caption, weight: .bold)).foregroundStyle(AppAccent.resolved(accentRaw).color)
            Text(name).font(.display())
            ForEach(items) { item in Text("\(item.quantity.number) × \(item.food.name)").font(.roboto(.body)) }
            Divider(); NutritionView(total: Nutrition(items))
            Text("Australian menu snapshot · Prices and nutrition may vary").font(.roboto(.caption)).foregroundStyle(.secondary)
        }.padding(28).frame(width: 390).background(.white).foregroundStyle(.black).environment(\.colorScheme, .light)
    }
}
