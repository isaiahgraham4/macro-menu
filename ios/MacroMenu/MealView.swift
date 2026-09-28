import SwiftUI

struct MealView: View {
    @Environment(AppStore.self) private var store
    @State private var picking = false
    @State private var name = ""
    @State private var date = Date()
    @State private var mealTime = MealTime.suggested()
    @State private var clear = false
    @State private var image: UIImage?
    var title: String { name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "My meal" : name }
    var body: some View {
        LeanrList {
            Section {
                if store.data.tray.isEmpty { ContentUnavailableView("Build your meal", systemImage: "fork.knife", description: Text("Search the menu or add an order from Find.")) }
                ForEach(store.data.tray) { item in
                    VStack(alignment: .leading, spacing: 8) {
                      HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.food.name).font(.roboto(.headline))
                            Text("\((item.food.cal * item.quantity).number) Cal · \((item.food.p * item.quantity).number) g protein").font(.roboto(.caption)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Stepper(value: quantity(item), in: 0.5...50, step: 0.5) {
                            Text("× \(item.quantity.number)").font(.roboto(.subheadline, weight: .medium)).monospacedDigit()
                        }.fixedSize()
                      }
                      if item.food.chain != "mine" {
                          NavigationLink {
                              MealSwapsView(portionID: item.id)
                          } label: {
                              Label("Smarter swaps", systemImage: "arrow.triangle.2.circlepath")
                                  .font(.roboto(.subheadline)).foregroundStyle(.tint)
                          }
                      }
                    }.padding(.vertical, 4)
                }.onDelete { offsets in store.change { $0.tray.remove(atOffsets: offsets) } }
                Button { picking = true } label: { Label("Add food", systemImage: "plus.circle.fill") }
            }
            if !store.data.tray.isEmpty {
                Section("Meal totals") { NutritionView(total: Nutrition(store.data.tray)) }
                Section("Log it") {
                    TextField("Name this meal", text: $name)
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
                        .listRowSeparator(.hidden)
                }
                Section {
                    TileRow {
                        Button {
                            if store.change({ $0.meals.append(SavedMeal(name: title, items: $0.tray)) }) { store.notice = "Meal saved" }
                        } label: { TileLabel(title: "Save for later", systemImage: "bookmark") }
                        ShareLink(item: mealText(title, store.data.tray)) { TileLabel(title: "Share text", systemImage: "square.and.arrow.up") }
                        Button { UIPasteboard.general.string = mealText(title,store.data.tray); store.notice = "Meal copied" } label: { TileLabel(title: "Copy", systemImage: "doc.on.doc") }
                        Button {
                            let renderer = ImageRenderer(content: MealShareCard(name: title, items: store.data.tray)); renderer.scale = 3
                            image = renderer.uiImage
                        } label: { TileLabel(title: "Make image", systemImage: "photo") }
                    }
                    if let image {
                        ShareLink(item: Image(uiImage: image), preview: SharePreview(title, image: Image(uiImage: image))) { Label("Share meal image", systemImage: "photo.on.rectangle") }
                    }
                }
            }
            if !store.data.meals.isEmpty {
                Section("Saved meals") {
                    ForEach(store.data.meals) { meal in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(meal.name).font(.roboto(.headline))
                                Text(Nutrition(meal.items).text).font(.roboto(.caption)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Add") { store.add(meal.items) }.buttonStyle(.bordered).font(.roboto(.subheadline, weight: .medium))
                        }.padding(.vertical, 2)
                    }.onDelete { offsets in store.change { $0.meals.remove(atOffsets: offsets) } }
                }
            }
        }.navigationTitle("This meal")
            .toolbar { if !store.data.tray.isEmpty { Button("Clear", role: .destructive) { clear = true } } }
            .confirmationDialog("Clear this meal?", isPresented: $clear, titleVisibility: .visible) { Button("Clear meal", role: .destructive) { store.change { $0.tray = [] } } }
            .sheet(isPresented: $picking) { NavigationStack { BrowseView { portion in store.add([portion]); picking = false }.toolbar { Button("Done") { picking = false } } } }
            .onChange(of: store.data.tray) { image = nil }
            .onChange(of: name) { image = nil }
    }
    private func quantity(_ item: Portion) -> Binding<Double> {
        Binding(get: { store.data.tray.first { $0.id == item.id }?.quantity ?? item.quantity }, set: { value in
            if value > 0, value.isFinite { store.change { state in if let i = state.tray.firstIndex(where: { $0.id == item.id }) { state.tray[i].quantity = value } } }
        })
    }
}
