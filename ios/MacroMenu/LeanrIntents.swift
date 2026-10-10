import AppIntents
#if canImport(VisualIntelligence)
import VisualIntelligence
#endif

enum MealTimeOption: String, AppEnum {
    case breakfast, lunch, dinner, snacks
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Meal"
    static let caseDisplayRepresentations: [MealTimeOption: DisplayRepresentation] = [
        .breakfast: "Breakfast", .lunch: "Lunch", .dinner: "Dinner", .snacks: "Snacks"]
    var mealTime: MealTime { MealTime(rawValue: rawValue) ?? .snacks }
}

struct RestaurantEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Restaurant"
    static let defaultQuery = RestaurantQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct RestaurantQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [RestaurantEntity] {
        await all().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [RestaurantEntity] { await all() }
    func entities(matching string: String) async throws -> [RestaurantEntity] {
        let restaurants = await all()
        if let id = Assistant.nicknames[string.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)],
           let match = restaurants.first(where: { $0.id == id }) { return [match] }
        return FoodSearch.filter(restaurants, query: string) { $0.name }
    }
    private func all() async -> [RestaurantEntity] {
        await MainActor.run { AppServices.store.catalog.chains.map { RestaurantEntity(id: $0.id, name: $0.name) } }
    }
}

/// "Log my usual lunch": logs the meal you've had most often at that meal time in the last month.
struct LogUsualMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Log My Usual Meal"
    static let description = IntentDescription("Logs the meal you've had most often at this meal time over the last month, to today.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Meal") var meal: MealTimeOption?

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        AppServices.start()
        let store = AppServices.store, mealTime = meal?.mealTime ?? MealTime.suggested()
        guard let usual = Assistant.usual(mealTime, logs: store.data.logs) else {
            return .result(dialog: "You haven't logged \(mealTime.title.lowercased()) in the last month, so there's no usual \(mealTime.title.lowercased()) yet.")
        }
        guard store.log(QuickLog.copies(usual.items), name: usual.name, date: Date(), mealTime: mealTime) else {
            return .result(dialog: "Leanr couldn't save that. Open the app to check your data.")
        }
        await AppServices.health.finishPending()
        let total = Nutrition(usual.items)
        var text = "Logged \(usual.name) to \(mealTime.title.lowercased()): \(total.cal.rounded().number) Cal, \(total.p.number) g protein."
        if let left = Assistant.remaining(store.data, goals: store.goals).calories {
            text += left >= 0 ? " \(left.rounded().number) Cal left today." : " That's \(abs(left).rounded().number) Cal over today's target."
        }
        return .result(dialog: "\(text)")
    }
}

/// "What fits at KFC?": the best orders there for what's left of today's targets.
struct WhatFitsIntent: AppIntent {
    static let title: LocalizedStringResource = "What Fits at a Restaurant"
    static let description = IntentDescription("Finds orders at a restaurant that fit what's left of today's calories and protein.")

    @Parameter(title: "Restaurant", requestValueDialog: "Which restaurant?") var restaurant: RestaurantEntity

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        AppServices.start()
        let store = AppServices.store
        let query = Assistant.budget(store.data, goals: store.goals, chain: restaurant.id)
        let foods = store.foods
        let matches = await Task.detached(priority: .userInitiated) { query.map { MealFinder.find(foods, query: $0) } ?? [] }.value
        let answer = Assistant.fitsAnswer(restaurant: restaurant.name, query: query, matches: matches,
                                          caloriesLeft: Assistant.remaining(store.data, goals: store.goals).calories)
        return .result(dialog: "\(answer)")
    }
}

/// A food Leanr knows: a menu item, an everyday food or one of yours. Siri and Visual Intelligence show its macros.
struct FoodEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Food"
    static let defaultQuery = FoodQuery()
    let id: String
    let name: String
    let detail: String
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(detail)", image: .init(systemName: "fork.knife"))
    }
    @MainActor init(_ food: Food, store: AppStore) {
        id = food.id; name = food.name
        detail = "\(food.cal.rounded().number) Cal · \(food.p.number) g protein · \(store.chainName(food.chain))\(food.serve.isEmpty ? "" : " · " + food.serve)"
    }
    @MainActor static func food(_ id: String) -> Food? { AppServices.store.foods.first { $0.id == id } }
}

struct FoodQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [FoodEntity] {
        await MainActor.run {
            let store = AppServices.store
            return identifiers.compactMap { id in FoodEntity.food(id).map { FoodEntity($0, store: store) } }
        }
    }
    func suggestedEntities() async throws -> [FoodEntity] {
        await MainActor.run {
            let store = AppServices.store
            let pinned = store.pinnedFoods, recent = QuickLog.recentFoods(logs: store.data.logs)
            return (pinned + recent.filter { food in !pinned.contains { $0.id == food.id } }).prefix(12).map { FoodEntity($0, store: store) }
        }
    }
    func entities(matching string: String) async throws -> [FoodEntity] {
        await MainActor.run {
            let store = AppServices.store
            let names = Dictionary(store.catalog.chains.map { ($0.id, $0.name) }) { a, _ in a }.merging([Food.everyday: store.chainName(Food.everyday)]) { a, _ in a }
            return FoodSearch.browse(store.foods, chainNames: names, request: .init(search: string)).prefix(10).map { FoodEntity($0, store: store) }
        }
    }
}

/// Opens a food in Leanr, from Siri or a Visual Intelligence result.
struct OpenFoodIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Food"
    @Parameter(title: "Food", requestValueDialog: "Which food?") var target: FoodEntity
    @MainActor func perform() async throws -> some IntentResult {
        AppServices.start()
        if let food = FoodEntity.food(target.id) { AppServices.nav.opened = .food(food) }
        return .result()
    }
}

/// "Look up a food in Leanr": its calories and macros, from Leanr's own figures.
struct FoodMacrosIntent: AppIntent {
    static let title: LocalizedStringResource = "Look Up a Food"
    static let description = IntentDescription("Says the calories, protein, carbs and fat in a food from Leanr's menus, everyday foods or your own.")
    @Parameter(title: "Food", requestValueDialog: "Which food?") var food: FoodEntity
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        AppServices.start()
        guard let item = FoodEntity.food(food.id) else { return .result(dialog: "Leanr couldn't find that food.") }
        return .result(dialog: "\(Assistant.macrosAnswer(item, place: AppServices.store.chainName(item.chain)))")
    }
}

#if canImport(VisualIntelligence)
/// Visual Intelligence: point the camera at food, or take a screenshot of it, and Leanr shows the matching foods and their macros.
/// Apple names what's in view on the device; Leanr only searches its own data, and keeps nothing.
@available(iOS 26.0, *)
struct FoodVisualSearch: IntentValueQuery {
    func values(for input: SemanticContentDescriptor) async throws -> [FoodEntity] {
        await MainActor.run {
            let store = AppServices.store
            let names = Dictionary(store.catalog.chains.map { ($0.id, $0.name) }) { a, _ in a }.merging([Food.everyday: store.chainName(Food.everyday)]) { a, _ in a }
            return Assistant.visualMatches(labels: input.labels, foods: store.foods, chainNames: names).map { FoodEntity($0, store: store) }
        }
    }
}

/// "More results" from Visual Intelligence: opens Leanr's food search for what's in view.
@available(iOS 26.0, *)
@AppIntent(schema: .visualIntelligence.semanticContentSearch)
struct SearchFoodsInViewIntent: AppIntent {
    var semanticContent: SemanticContentDescriptor
    @MainActor func perform() async throws -> some IntentResult {
        AppServices.start()
        AppServices.nav.opened = .search(Assistant.visualSearchText(semanticContent.labels))
        return .result()
    }
}
#endif

struct LeanrShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogUsualMealIntent(), phrases: [
            "Log my usual \(\.$meal) in \(.applicationName)",
            "Log my usual \(\.$meal) with \(.applicationName)",
            "Log my usual meal in \(.applicationName)"
        ], shortTitle: "Log Usual Meal", systemImageName: "arrow.uturn.backward.circle")
        AppShortcut(intent: WhatFitsIntent(), phrases: [
            "What fits at \(\.$restaurant) in \(.applicationName)",
            "What can I get at \(\.$restaurant) with \(.applicationName)",
            "What fits in \(.applicationName)"
        ], shortTitle: "What Fits", systemImageName: "fork.knife")
        AppShortcut(intent: FoodMacrosIntent(), phrases: [
            "Look up a food in \(.applicationName)",
            "How much protein is in \(\.$food) in \(.applicationName)",
            "How many calories are in \(\.$food) in \(.applicationName)"
        ], shortTitle: "Look Up a Food", systemImageName: "magnifyingglass")
    }
}
