import SwiftUI
import FoundationModels

/// Type or dictate what you ate ("two eggs, toast with butter and a flat white"); Leanr finds each food in its own data
/// and you check them before logging. Apple Intelligence reads the words where the iPhone has it, and Leanr's own
/// reading does everywhere else. Nothing leaves the iPhone.
struct MealTextView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let mealTime: MealTime
    /// Logs the chosen portions under one name; false if it couldn't be saved.
    let log: (_ portions: [Portion], _ name: String) -> Bool
    /// The button's wording, e.g. "Log" or "Plan".
    var verb = "Log"

    @State private var text = ""
    @State private var rows: [FoodMatchRow] = []
    @State private var reading = false
    @State private var read = false
    @State private var failed = false
    @FocusState private var typing: Bool

    private var portions: [Portion] { rows.compactMap(\.portion) }

    var body: some View {
        LeanrList {
            Section {
                TextField("Two eggs, toast with butter and a flat white", text: $text, axis: .vertical)
                    .lineLimit(3...8).focused($typing).submitLabel(.done)
                    .onSubmit { find() }
                Button { find() } label: {
                    if reading { ProgressView("Reading…").frame(maxWidth: .infinity) } else { Text("Find these foods").frame(maxWidth: .infinity) }
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reading)
            } footer: {
                Text("Type it, or tap the microphone on the keyboard and say it. Name a restaurant (\"from KFC\") to look there first. Your iPhone reads the words, and nothing is sent anywhere.")
            }
            if read && rows.isEmpty {
                Section { Text("No foods found in that. Try naming each food, like \"chicken breast, rice and broccoli\".").foregroundStyle(.secondary) }
            }
            FoodMatchSections(rows: $rows)
        }
        .navigationTitle("Describe your meal").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .safeAreaInset(edge: .bottom) {
            if !portions.isEmpty && !typing {
                BottomActionBar {
                    Button {
                        if log(portions, portions.map(\.food.name).joined(separator: " + ")) { dismiss() } else { failed = true }
                    } label: {
                        Text("\(verb) \(portions.count) to \(mealTime.title) · \(Nutrition(portions).cal.rounded().number) Cal").frame(maxWidth: .infinity)
                    }.disabled(!portions.allSatisfy(\.isValid))
                }
            }
        }
        .onAppear { typing = rows.isEmpty }
        .alert("Couldn’t save that", isPresented: $failed) { Button("OK", role: .cancel) {} } message: {
            Text("Your data was not changed. Check available storage and try again.")
        }
    }

    private func find() {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, !reading else { return }
        typing = false; reading = true
        let foods = store.foods, names = store.chainNames
        let known = Set(foods.map { " " + FoodSearch.tokens($0.name).filter { !["and", "with", "n"].contains($0) }.joined(separator: " ") + " " })
        Task {
            var phrases = await MealWords.read(words)
            if phrases.isEmpty {
                phrases = FoodPhrase.meal(words) { candidate in
                    let wanted = " " + FoodSearch.tokens(candidate).filter { !["and", "with", "n"].contains($0) }.joined(separator: " ") + " "
                    return known.contains { $0.contains(wanted) }
                }
            }
            let found = await Task.detached(priority: .userInitiated) {
                phrases.map { phrase in
                    FoodMatchRow.make(phrase, title: phrase.original.isEmpty ? phrase.name : phrase.original, in: foods, chainNames: names)
                }
            }.value
            rows = found; read = true; reading = false
        }
    }
}

/// Apple Intelligence's reading of a meal in words. Empty when the iPhone doesn't have it or it can't answer, and then
/// Leanr's own reading is used.
enum MealWords {
    static var isAvailable: Bool {
        guard #available(iOS 26.0, *) else { return false }
        return SystemLanguageModel.default.isAvailable
    }

    static func read(_ text: String) async -> [FoodPhrase] {
        guard isAvailable, #available(iOS 26.0, *) else { return [] }
        return (try? await foods(in: text)) ?? []
    }

    @available(iOS 26.0, *)
    @Generable(description: "The foods and drinks someone says they ate")
    struct Described {
        @Guide(description: "Each separate food or drink, in the order mentioned. A dish with a name of its own, like \"fish and chips\" or \"bacon and egg McMuffin\", is one item.", .maximumCount(12))
        var foods: [Item]

        @Generable(description: "One food or drink")
        struct Item {
            @Guide(description: "How much, as said, with its unit: \"2\", \"200 g\", \"1 cup\", \"half\", \"2 slices\". Empty if no amount was said.")
            var amount: String
            @Guide(description: "What it is, in plain words someone would search a food diary for, without the amount or restaurant: \"eggs\", \"toast\", \"flat white\", \"Big Mac\", \"spaghetti bolognese\". Expand slang: \"spag bol\" is \"spaghetti bolognese\".")
            var name: String
            @Guide(description: "The restaurant or brand if one was named for it, like \"McDonald's\" or \"KFC\". Otherwise empty.")
            var brand: String
            @Guide(description: "Up to two other names a nutrition database might list it under.", .maximumCount(2))
            var otherNames: [String]
        }
    }

    @available(iOS 26.0, *)
    static func foods(in text: String) async throws -> [FoodPhrase] {
        let session = LanguageModelSession(instructions: """
            You read what someone ate for a food diary and list each food or drink with the amount they said. \
            Only list what they said they ate. Never estimate calories or nutrients, and never add foods they didn't mention.
            """)
        let response = try await session.respond(to: "What did they eat? \"\(text)\"", generating: Described.self)
        return response.content.foods.compactMap { item in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, var phrase = FoodPhrase.food("\(item.amount) \(name)") else { return nil }
            let brand = item.brand.trimmingCharacters(in: .whitespacesAndNewlines)
            if !brand.isEmpty { phrase.brand = brand }
            phrase.alternatives = item.otherNames.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            phrase.original = [item.amount, item.name].filter { !$0.isEmpty }.joined(separator: " ") + (brand.isEmpty ? "" : " · \(brand)")
            return phrase
        }
    }
}
