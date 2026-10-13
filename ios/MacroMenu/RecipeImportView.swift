import SwiftUI

/// Paste a recipe's web address; Leanr loads the page and reads the recipe. Save it with the site's own nutrition per
/// serving, or match each ingredient to Leanr's foods and build it as a recipe you can change.
struct RecipeImportView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var loading = false
    @State private var failure: RecipeImport.Failure?
    @State private var recipe: ImportedRecipe?
    @State private var servings = 1.0
    @State private var rows: [FoodMatchRow] = []
    @State private var building: Food?

    private var portions: [Portion] { rows.compactMap(\.portion) }

    var body: some View {
        LeanrList {
            Section {
                TextField("Recipe link", text: $text, prompt: Text("https://…"))
                    .keyboardType(.URL).textContentType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.go).onSubmit { load() }
                HStack {
                    PasteButton(payloadType: String.self) { strings in
                        if let first = strings.first { text = first; load() }
                    }
                    .labelStyle(.titleAndIcon).buttonBorderShape(.capsule)
                    Spacer()
                    Button { load() } label: { if loading { ProgressView() } else { Text("Load recipe") } }
                        .buttonStyle(.bordered).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || loading)
                }
                if let failure { Text(failure.message).foregroundStyle(.secondary) }
            } footer: {
                Text("Copy the address from Safari or a recipe app. Leanr loads the page straight from that website and reads only its recipe details. Nothing else about you is sent.")
            }
            if let recipe {
                Section {
                    Text(recipe.name).font(.roboto(.headline))
                    NumberField(title: "Serves", value: $servings, places: 1)
                    if let source = recipe.source { Link(destination: source) { Label(recipe.host ?? "Open the page", systemImage: "safari") } }
                } header: { Text("Recipe") }
                if let food = recipe.food {
                    Section {
                        NutritionView(total: Nutrition([Portion(food: food)]))
                        Button {
                            if store.saveFood(food) { store.notice = "Saved \(food.name) to My foods"; dismiss() }
                        } label: { Text("Save with these figures").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent)
                    } header: { Text("Per serving, from \(recipe.host ?? "the page")") } footer: {
                        Text("The site's own figures for one serving. Or match the ingredients below to build it from Leanr's foods, which you can change later.")
                    }
                }
                if rows.isEmpty {
                    Section { Text("This page doesn't list its ingredients.").foregroundStyle(.secondary) }
                } else {
                    Section {
                        Text("\(portions.count) of \(rows.count) ingredients matched. Lines without an amount, like salt to taste, are left out unless you choose them.")
                            .font(.roboto(.caption)).foregroundStyle(.secondary)
                    } header: { Text("Ingredients") }
                    FoodMatchSections(rows: $rows)
                }
            }
        }
        .navigationTitle("Import a recipe").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .safeAreaInset(edge: .bottom) {
            if let recipe, !portions.isEmpty {
                BottomActionBar {
                    Button {
                        var draft = Nutrition(portions).food(name: recipe.name, servings: max(servings, 0.001), ingredients: portions)
                        draft.note = recipe.host.map { "From \($0)" }
                        building = draft
                    } label: {
                        Text("Build from \(portions.count) ingredients · \((Nutrition(portions).cal / max(servings, 1)).rounded().number) Cal a serving").frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationDestination(item: $building) { draft in RecipeEditor(food: draft, imported: true, saved: { dismiss() }) }
    }

    private func load() {
        guard let url = RecipeImport.link(in: text) else { failure = .notALink; return }
        failure = nil; loading = true
        let foods = store.foods, names = store.chainNames
        Task {
            do {
                let found = try await RecipeImport.load(url)
                let matched = await Task.detached(priority: .userInitiated) {
                    found.ingredients.compactMap { line -> FoodMatchRow? in
                        guard let phrase = FoodPhrase.ingredient(line) else { return nil }
                        return FoodMatchRow.make(phrase, title: line, in: foods, chainNames: names, preselect: phrase.amount != nil, raw: true)
                    }
                }.value
                recipe = found; servings = found.servings ?? 1; rows = matched
            } catch let error as RecipeImport.Failure {
                failure = error
            } catch {
                failure = .couldNotLoad
            }
            loading = false
        }
    }
}
