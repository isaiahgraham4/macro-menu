import SwiftUI
import UniformTypeIdentifiers

/// A file to save through the share sheet: a JSON backup or a CSV export.
struct FoodDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = bytes
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
/// Number boxes show at most one decimal place (two for prices and servings).
func decimalFormat(_ places: Int = 1) -> FloatingPointFormatStyle<Double> { .number.precision(.fractionLength(0...places)) }

struct NumberField: View {
    var title: String
    @Binding var value: Double
    var places = 1
    /// What VoiceOver reads when the visible title alone is ambiguous, e.g. several "Servings" fields on one screen.
    var spokenTitle: String? = nil
    var body: some View {
        HStack {
            Text(title).accessibilityHidden(spokenTitle != nil)
            Spacer()
            TextField(title, value: $value, format: decimalFormat(places)).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 120)
                .accessibilityLabel(spokenTitle ?? title)
        }
    }
}
struct OptionalNumberField: View {
    var title: String
    @Binding var value: Double?
    var places = 1
    var body: some View {
        HStack { Text(title); Spacer(); TextField("Not set", value: $value, format: decimalFormat(places)).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 120).accessibilityLabel(title) }
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
    /// Shows a "+" that adds one serving without opening the food.
    var quickAdd: (() -> Void)?
    var quickAddLabel = "Log"
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        // At the largest text sizes the "+" moves under the details, so the name keeps the full width.
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            details
            if let quickAdd {
                Button(action: quickAdd) {
                    Image(systemName: "plus.circle.fill").font(.title2).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.borderless).accessibilityLabel("\(quickAddLabel) \(food.name)")
            }
        }
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(food.name).font(.roboto(.headline)).foregroundStyle(.primary)
            Text(food.serve.isEmpty ? store.chainName(food.chain) : "\(store.chainName(food.chain)) · \(food.serve)").font(.roboto(.caption)).foregroundStyle(.secondary)
            Text("\(food.cal.number) Cal · \(food.p.number) g protein").font(.roboto(.subheadline)).foregroundStyle(.secondary).monospacedDigit()
        }
        // Full width, so the "+" lines up at the trailing edge on every row.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical,4)
    }
}
/// Pins a food to the top of the "+" menu and the Log again widget, or unpins it.
struct PinButton: View {
    @Environment(AppStore.self) private var store
    var food: Food
    var body: some View {
        let pinned = store.isPinned(food)
        Button(pinned ? "Unpin" : "Pin to top", systemImage: pinned ? "pin.slash" : "pin") { store.togglePin(food) }
    }
}
/// Today or yesterday, and which meal: where one-tap logging goes.
struct LogTargetPicker: View {
    @Binding var yesterday: Bool
    @Binding var meal: MealTime
    var body: some View {
        HStack(spacing: 12) {
            Picker("Day to log to", selection: $yesterday) { Text("Today").tag(false); Text("Yesterday").tag(true) }.pickerStyle(.segmented)
            Picker("Meal to log to", selection: $meal) { ForEach(MealTime.allCases) { Text($0.title).tag($0) } }
                .pickerStyle(.menu).labelsHidden().fixedSize()
        }
    }
}
/// "Log to yesterday's …" choices for a menu, for a meal that was forgotten.
struct YesterdayMenu: View {
    var log: (MealTime) -> Void
    var body: some View {
        Section("Forgot it yesterday?") {
            ForEach(MealTime.allCases) { meal in Button("Yesterday’s \(meal.title.lowercased())") { log(meal) } }
        }
    }
}
struct SourcesView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        LeanrList {
            Section { Text("Bundled Australian menu snapshot from 24 September 2026. Missing nutrients stay unknown. Custom orders and recipes are estimates based on their ingredients.") }
            ForEach(store.catalog.chains.filter { $0.id != "mine" }) { chain in
                Section(chain.name) {
                    Text(chain.src ?? "").font(.roboto(.subheadline))
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
            Label("LEANR", systemImage: "leaf.fill").font(.roboto(.caption, weight: .bold)).foregroundStyle(AppAccent.resolved(accentRaw).color)
            Text(name).font(.display())
            ForEach(items) { item in Text("\(item.quantity.number) × \(item.food.name)").font(.roboto(.body)) }
            Divider(); NutritionView(total: Nutrition(items))
            Text("Australian menu snapshot · Nutrition may vary").font(.roboto(.caption)).foregroundStyle(.secondary)
        }.padding(28).frame(width: 390).background(.white).foregroundStyle(.black).environment(\.colorScheme, .light)
    }
}
