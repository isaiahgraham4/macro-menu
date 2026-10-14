import SwiftUI

enum TodaySuggestions {
    static let storageKey = "today.suggestions"
}

/// The ideas for what's left today. Owned by the screen that shows them, which calls `refresh` from a `.task(id: Model.key(...))`
/// so they're worked out again only when what's left changes, not on every redraw.
@MainActor @Observable
final class LeftTodayModel {
    private(set) var suggestions: [Assistant.Suggestion] = []

    struct Key: Equatable {
        var day: String, entries: Int, calories: Int?, protein: Int?, pinned: [String], savedMeals: Int, lastMeal: Bool, enabled: Bool
    }
    static func key(_ store: AppStore, enabled: Bool, now: Date = Date()) -> Key {
        let left = Assistant.remaining(store.data, goals: store.goals, now: now)
        return Key(day: dayKey(now), entries: store.data.logs[dayKey(now)]?.count ?? 0, calories: left.calories.map { Int($0.rounded()) },
                   protein: left.protein.map { Int($0.rounded()) }, pinned: store.pinnedFoods.map(\.id),
                   savedMeals: store.data.meals.count, lastMeal: Calendar.current.component(.hour, from: now) >= 16, enabled: enabled)
    }

    func refresh(_ store: AppStore, enabled: Bool) async {
        guard enabled else { suggestions = []; return }
        let data = store.data, goals = store.goals, pinned = store.pinnedFoods, everyday = store.suggestibleEveryday, restaurants = store.suggestibleRestaurantFoods
        let names = Dictionary(store.catalog.chains.map { ($0.id, $0.name) }) { a, _ in a }
        let now = Date()
        suggestions = await Task.detached(priority: .userInitiated) {
            Assistant.suggestions(data, goals: goals, pinned: pinned, everyday: everyday, restaurantFoods: restaurants, chainNames: names, now: now)
        }.value
    }
}

/// "Left today: 62 g protein · 630 Cal", folded away until opened, with a few one-meal ideas that fit what's left.
/// Each + logs one serving to today under `mealTime`. Settings turns it off.
struct LeftTodaySection: View {
    @Environment(AppStore.self) private var store
    @AppStorage(TodaySuggestions.storageKey) private var enabled = true
    @AppStorage("today.suggestions.open") private var open = false
    let model: LeftTodayModel
    let mealTime: MealTime

    var body: some View {
        if enabled && !model.suggestions.isEmpty {
            Section {
                DisclosureGroup(isExpanded: $open) {
                    ForEach(model.suggestions) { row($0) }
                    Text("Tap + to log one serving to \(mealTime.title). Check the portion. You can turn these off in Settings.")
                        .font(.roboto(.caption)).foregroundStyle(.secondary)
                } label: {
                    Label(Assistant.leftText(store.data, goals: store.goals).map { "Left today: \($0)" } ?? "What fits", systemImage: "lightbulb")
                        .font(.roboto(.subheadline, weight: .medium))
                }
            }
        }
    }

    private func row(_ item: Assistant.Suggestion) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.roboto(.headline))
                Text("\(item.calories.rounded().number) Cal · \(item.protein.number) g protein · \(item.sourceText)")
                    .font(.roboto(.caption)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                if store.log(QuickLog.copies(item.items), name: item.name, date: Date(), mealTime: mealTime) {
                    store.notice = "Logged to \(mealTime.title.lowercased())"
                }
            } label: { Image(systemName: "plus.circle.fill").font(.title2).frame(width: 44, height: 44).contentShape(Rectangle()) }
                .buttonStyle(.borderless)
                .accessibilityLabel("Log \(item.name) to \(mealTime.title)")
        }
        .accessibilityElement(children: .contain)
    }
}
