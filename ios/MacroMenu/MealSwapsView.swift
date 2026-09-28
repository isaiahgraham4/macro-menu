import SwiftUI

struct MealSwapsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let portionID: UUID

    var body: some View {
        LeanrList {
            if let portion = store.data.tray.first(where: { $0.id == portionID }) {
                Section("Your current choice") {
                    Text(portion.food.name).font(.roboto(.headline))
                    Text("\((portion.food.cal * portion.quantity).number) Cal · \((portion.food.p * portion.quantity).number) g protein")
                    Text("\(store.chainName(portion.food.chain)) · × \(portion.quantity.number)")
                        .font(.roboto(.caption)).foregroundStyle(.secondary)
                }
                let options = MealSwaps.options(for: portion, foods: store.catalog.foods)
                if options.isEmpty {
                    ContentUnavailableView("No lower-calorie swaps", systemImage: "arrow.triangle.2.circlepath", description: Text("We couldn't find an alternative with at least 20 fewer calories in this restaurant's menu category."))
                } else {
                    Section {
                        ForEach(options) { food in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(food.name).font(.roboto(.headline))
                                Text("× \(portion.quantity.number) · \(food.serve) each")
                                    .font(.roboto(.caption)).foregroundStyle(.secondary)
                                Text("\((food.cal * portion.quantity).number) Cal · \((food.p * portion.quantity).number) g protein")
                                Label("\(((portion.food.cal - food.cal) * portion.quantity).number) fewer Cal", systemImage: "arrow.down.circle.fill")
                                    .foregroundStyle(.tint)
                                let proteinChange = (food.p - portion.food.p) * portion.quantity
                                Text(proteinChange == 0 ? "Same protein" : "\(abs(proteinChange).number) g \(proteinChange > 0 ? "more" : "less") protein")
                                    .font(.roboto(.subheadline)).foregroundStyle(.secondary)
                                Button("Use this swap") {
                                    if store.change({ state in
                                        if let index = state.tray.firstIndex(where: { $0.id == portionID }) {
                                            state.tray[index].food = food
                                        }
                                    }) {
                                        store.notice = "Swapped to \(food.name)"
                                        dismiss()
                                    }
                                }.buttonStyle(.bordered)
                            }.padding(.vertical, 6)
                        }
                    } header: { Text("Lower-calorie alternatives") } footer: {
                        Text("Same restaurant and menu category. Your quantity stays the same; serving sizes and ingredients may differ. Alternatives retaining at least 80% of the original protein appear first. Customisations aren't carried over.")
                    }
                }
            } else {
                ContentUnavailableView("Meal item removed", systemImage: "fork.knife", description: Text("Return to your meal to choose another item."))
            }
        }.navigationTitle("Smarter swaps")
            .navigationBarTitleDisplayMode(.inline)
    }
}
