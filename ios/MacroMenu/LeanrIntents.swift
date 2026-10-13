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
            return Assistant.spokenMatches(store.foods, query: string, chainNames: names).map { FoodEntity($0, store: store) }
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

/// "Log banana in Leanr": logs a food to today, as one serving unless told otherwise.
struct LogFoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Food"
    static let description = IntentDescription("Logs a food from Leanr's menus, everyday foods or your own foods to today.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Food", requestValueDialog: "Which food?") var food: FoodEntity
    @Parameter(title: "Servings", default: 1) var servings: Double
    @Parameter(title: "Grams", description: "For foods weighed by the gram, such as chicken breast. Used instead of servings.") var grams: Double?
    @Parameter(title: "Meal") var meal: MealTimeOption?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$food) to \(\.$meal)") {
            \.$servings
            \.$grams
        }
    }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        AppServices.start()
        let store = AppServices.store, mealTime = meal?.mealTime ?? MealTime.suggested()
        guard let item = FoodEntity.food(food.id) else { return .result(dialog: "Leanr couldn't find that food.") }
        guard let quantity = Assistant.servings(servings, grams: grams, of: item) else {
            return .result(dialog: grams != nil && item.servingWeight == nil
                           ? "\(item.name) isn't weighed in grams in Leanr, so tell me how many servings instead."
                           : "That amount doesn't look right, so I haven't logged anything.")
        }
        guard store.log([Portion(food: item, quantity: quantity)], name: item.name, date: Date(), mealTime: mealTime) else {
            return .result(dialog: "Leanr couldn't save that. Open the app to check your data.")
        }
        await AppServices.health.finishPending()
        let left = Assistant.remaining(store.data, goals: store.goals).calories
        return .result(dialog: "\(Assistant.loggedAnswer(food: item, quantity: quantity, mealTime: mealTime, caloriesLeft: left))")
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

enum WaterSizeOption: String, AppEnum {
    case glass, bottle, litre
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Water amount"
    static let caseDisplayRepresentations: [WaterSizeOption: DisplayRepresentation] = [
        .glass: "Glass", .bottle: "Bottle", .litre: "Litre"]
    var size: Water.Size { Water.Size(rawValue: rawValue) ?? .glass }
}

/// "Log a glass of water in Leanr": adds water to today, a glass by default (the size you set in Settings).
struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Water"
    static let description = IntentDescription("Adds water to today in Leanr: a glass, a 500 mL bottle, a litre or an amount in millilitres.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Amount", default: .glass) var size: WaterSizeOption
    @Parameter(title: "Millilitres", description: "An exact amount. Used instead of the glass, bottle or litre.", inclusiveRange: (1, 5000)) var millilitres: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Log a \(\.$size) of water") { \.$millilitres }
    }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        AppServices.start()
        let store = AppServices.store
        let amount = millilitres.map(Double.init) ?? Water.millilitres(size.size, glass: Water.glass(store.data))
        guard amount > 0, amount <= Water.singleLimit, store.addWater(amount) else {
            return .result(dialog: "Leanr couldn't save that. Open the app to check your data.")
        }
        await AppServices.health.finishPending()
        let total = Water.total(store.data, on: dayKey(Date()))
        return .result(dialog: "\(Water.loggedAnswer(added: amount, total: total, target: Water.target(store.data)))")
    }
}

/// "How much water have I had in Leanr": today's total against the target.
struct WaterTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "How Much Water Today"
    static let description = IntentDescription("Says how much water you've logged today and how far that is from your target.")

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        AppServices.start()
        let store = AppServices.store
        return .result(dialog: "\(Water.todayAnswer(total: Water.total(store.data, on: dayKey(Date())), target: Water.target(store.data)))")
    }
}

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
        AppShortcut(intent: LogFoodIntent(), phrases: [
            "Log \(\.$food) in \(.applicationName)",
            "Log \(\.$food) with \(.applicationName)",
            "Add \(\.$food) to \(.applicationName)",
            "Log a food in \(.applicationName)"
        ], shortTitle: "Log a Food", systemImageName: "plus.circle")
        AppShortcut(intent: FoodMacrosIntent(), phrases: [
            "Look up a food in \(.applicationName)",
            "How much protein is in \(\.$food) in \(.applicationName)",
            "How many calories are in \(\.$food) in \(.applicationName)"
        ], shortTitle: "Look Up a Food", systemImageName: "magnifyingglass")
        AppShortcut(intent: LogWaterIntent(), phrases: [
            "Log a \(\.$size) of water in \(.applicationName)",
            "Log water in \(.applicationName)",
            "Log water with \(.applicationName)",
            "Add water to \(.applicationName)"
        ], shortTitle: "Log Water", systemImageName: "drop.fill")
        AppShortcut(intent: WaterTodayIntent(), phrases: [
            "How much water have I had in \(.applicationName)",
            "How much water today in \(.applicationName)"
        ], shortTitle: "Water Today", systemImageName: "drop")
    }
}
