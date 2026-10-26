import SwiftUI
import UniformTypeIdentifiers

extension Portion {
    /// "150 g" when the food is weighed, otherwise "2 × 1 wrap" (or just "1 wrap" for one).
    var amountText: String {
        if let (grams, unit) = food.servingWeight { return "\((grams * quantity).rounded().number) \(unit)" }
        return quantity == 1 ? food.serve : "\(quantity.number) × \(food.serve)"
    }

    /// For a recipe, its ingredients scaled to this portion: half a serving of a recipe that makes two is a quarter of each.
    /// Nil for anything that isn't a recipe.
    var ingredientPortions: [Portion]? {
        guard let ingredients = food.ingredients, !ingredients.isEmpty else { return nil }
        let share = quantity / max(food.recipeYield ?? 1, 0.001)
        return ingredients.map { var scaled = $0; scaled.quantity = $0.quantity * share; return scaled }
    }
}

extension Food {
    /// This recipe made with different ingredients, its figures worked out again from them. Everything else, the ID included, stays.
    func withIngredients(_ ingredients: [Portion]) -> Food {
        let fresh = Nutrition(ingredients).food(name: name, servings: max(recipeYield ?? 1, 0.001), ingredients: ingredients)
        var value = self
        value.kj = fresh.kj; value.cal = fresh.cal; value.p = fresh.p; value.c = fresh.c; value.f = fresh.f
        value.nut = fresh.nut; value.price = fresh.price; value.pf = fresh.pf; value.ingredients = ingredients
        return value
    }

    /// A new recipe made of these foods, one serving, with any recipe among them broken into its ingredients.
    static func recipeDraft(name: String, from items: [Portion]) -> Food {
        Food(name: name, kj: 0, cal: 0, p: 0, ingredients: QuickLog.copies(mealLines(items)), recipeYield: 1)
    }
}

/// What a meal is made of, for listing: a recipe's ingredients in place of the recipe, anything else as it is.
func mealLines(_ items: [Portion]) -> [Portion] {
    items.flatMap { $0.ingredientPortions ?? [$0] }
}

/// A recipe's ingredients as rows: what it is, how much, and its calories and protein.
struct IngredientRows: View {
    var ingredients: [Portion]
    var body: some View {
        ForEach(ingredients) { item in
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.food.name).font(.roboto(.body))
                    Spacer(minLength: 8)
                    Text(item.amountText).font(.roboto(.subheadline)).foregroundStyle(.secondary).monospacedDigit()
                }
                Text("\((item.food.cal * item.quantity).rounded().number) Cal · \((item.food.p * item.quantity).number) g protein")
                    .font(.roboto(.caption)).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// A 9:16 card for an Instagram or TikTok story: the meal's name, calories and macros, and what's in it.
struct MealShareCard: View {
    @AppStorage(AppAccent.storageKey) private var accentRaw = AppAccent.standard.rawValue
    @AppStorage(MacroColours.proteinKey) private var proteinColour = "blue"
    @AppStorage(MacroColours.carbsKey) private var carbsColour = "orange"
    @AppStorage(MacroColours.fatKey) private var fatColour = "red"
    var name: String
    var items: [Portion]
    /// "Dinner · 21 Oct", for a logged meal.
    var subtitle: String?

    static let size = CGSize(width: 360, height: 640)
    private static let maxLines = 9

    private var total: Nutrition { Nutrition(items) }
    private var lines: [Portion] { mealLines(items) }
    private var isRecipe: Bool { items.contains { $0.ingredientPortions != nil } }
    private func colour(_ key: String) -> Color {
        MacroColours.colour(key, choices: Premium.isUnlocked ? ["p": proteinColour, "c": carbsColour, "f": fatColour] : [:])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("LEANR", systemImage: "leaf.fill").font(.roboto(.caption, weight: .bold))
                .foregroundStyle(AppAccent.resolved(accentRaw).color)
            Text(name).font(.custom(AppFonts.display, size: 54)).lineLimit(3).minimumScaleFactor(0.5)
                .padding(.top, 18)
            if let subtitle { Text(subtitle).font(.roboto(.subheadline)).foregroundStyle(.white.opacity(0.6)) }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(total.cal.rounded().number).font(.custom(AppFonts.display, size: 72)).monospacedDigit()
                Text("Cal").font(.roboto(.title3)).foregroundStyle(.white.opacity(0.6))
            }.padding(.top, 20)

            HStack(spacing: 10) {
                macro("Protein", total.p, missing: false, key: "p")
                macro("Carbs", total.c, missing: total.missingCarbs, key: "c")
                macro("Fat", total.f, missing: total.missingFat, key: "f")
            }.padding(.top, 6)

            if !lines.isEmpty {
                Text(isRecipe ? "INGREDIENTS" : "IN THIS MEAL").font(.roboto(.caption, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 26).padding(.bottom, 8)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(lines.prefix(lines.count > Self.maxLines ? Self.maxLines - 1 : Self.maxLines)) { line in
                        HStack(alignment: .firstTextBaseline) {
                            Text(line.food.name).font(.roboto(.subheadline)).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(line.amountText).font(.roboto(.subheadline)).foregroundStyle(.white.opacity(0.6)).monospacedDigit().lineLimit(1)
                        }
                    }
                    if lines.count > Self.maxLines {
                        Text("and \(lines.count - Self.maxLines + 1) more").font(.roboto(.subheadline)).foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            Spacer(minLength: 12)
            Text("Tracked with Leanr · Nutrition may vary").font(.roboto(.caption2)).foregroundStyle(.white.opacity(0.45))
        }
        .padding(.horizontal, 28).padding(.vertical, 36)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Color(red: 0.07, green: 0.07, blue: 0.08))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private func macro(_ label: String, _ value: Double, missing: Bool, key: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Capsule().fill(colour(key)).frame(height: 4)
            Text("\(value.rounded().number)\(missing ? "+" : "") g").font(.roboto(.title3, weight: .semibold)).monospacedDigit()
            Text(label).font(.roboto(.caption)).foregroundStyle(.white.opacity(0.6))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The card drawn at three times its size: 1080 × 1920, a story's own size.
    @MainActor static func image(name: String, items: [Portion], subtitle: String? = nil) -> UIImage? {
        let renderer = ImageRenderer(content: MealShareCard(name: name, items: items, subtitle: subtitle))
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// A rendered card shared as its own full-size PNG. Sharing a SwiftUI `Image` hands over a re-encoded copy, which looks softer once copied or posted.
struct ShareImage: Transferable {
    var image: UIImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { value in
            guard let data = value.image.pngData() else { throw CocoaError(.fileWriteUnknown) }
            return data
        }
    }
}

/// Shows the story card before sharing it, so you see what you're posting.
struct MealSharePreview: View {
    @Environment(\.dismiss) private var dismiss
    var name: String
    var items: [Portion]
    var subtitle: String?
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 20) {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .accessibilityLabel("Share image of \(name)")
                ShareLink(item: ShareImage(image: image), preview: SharePreview(name, image: Image(uiImage: image))) {
                    Label("Share image", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                Text("Post it to an Instagram or TikTok story, or save it to Photos from the share sheet.")
                    .font(.roboto(.caption)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else {
                ProgressView()
            }
        }
        .padding()
        .navigationTitle("Share image").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .task { image = MealShareCard.image(name: name, items: items, subtitle: subtitle) }
    }
}
