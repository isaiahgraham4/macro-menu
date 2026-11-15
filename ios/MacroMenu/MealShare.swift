import Photos
import SwiftUI
import UniformTypeIdentifiers

extension Portion {
    /// "150 g" when the food is weighed, otherwise "2 × 1 wrap" (or just "1 wrap" for one).
    var amountText: String {
        if let (grams, unit) = food.servingWeight { return "\((grams * quantity).rounded().number) \(unit)" }
        return quantity == 1 ? food.serve : "\(quantity.number) × \(food.serve)"
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

    private var total: Nutrition { Nutrition(items) }
    private var lines: [Portion] { mealLines(items) }
    private var isRecipe: Bool { items.contains { $0.ingredientPortions != nil } }
    private func colour(_ key: String) -> Color {
        MacroColours.colour(key, choices: Premium.isUnlocked ? ["p": proteinColour, "c": carbsColour, "f": fatColour] : [:])
    }

    var body: some View {
        // The card is a fixed 9:16, so it tries fewer ingredient rows until the name, macros and rows all fit above the footer.
        ViewThatFits(in: .vertical) {
            card(rows: 9); card(rows: 7); card(rows: 6); card(rows: 5); card(rows: 4); card(rows: 3); card(rows: 2); card(rows: 1)
        }
        .padding(.horizontal, 28).padding(.vertical, 36)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Color(red: 0.07, green: 0.07, blue: 0.08))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        // A picture, not a screen: the same size whatever text size the sharer uses.
        .dynamicTypeSize(.large)
    }

    /// The card's contents, listing up to `rows` ingredient lines (the last of them "and N more" when there are too many).
    private func card(rows: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("LEANRRR", systemImage: "leaf.fill").font(.roboto(.caption, weight: .bold))
                .foregroundStyle(AppAccent.resolvedColor(accentRaw))
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
                let shown = lines.count > rows ? max(rows - 1, 0) : rows
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(lines.prefix(shown)) { line in
                        HStack(alignment: .firstTextBaseline) {
                            Text(line.food.name).font(.roboto(.subheadline)).lineLimit(2)
                            Spacer(minLength: 8)
                            Text(line.amountText).font(.roboto(.subheadline)).foregroundStyle(.white.opacity(0.6)).monospacedDigit().lineLimit(1)
                        }
                    }
                    if lines.count > shown {
                        Text("and \(lines.count - shown) more").font(.roboto(.subheadline)).foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            Spacer(minLength: 12)
            Text("Tracked with Leanrrr · Nutrition may vary").font(.roboto(.caption2)).foregroundStyle(.white.opacity(0.45))
        }
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

extension UIImage {
    /// The same picture redrawn at 1×, so its pixel size is its size. A 3× render is 1080 × 1920 pixels but says 360 × 640,
    /// and apps that go by the stated size (pasting into Snapchat, for one) blow up the small version and it looks blurry.
    var flattened: UIImage {
        guard scale != 1 else { return self }
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1; format.opaque = true
        let pixels = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        return UIGraphicsImageRenderer(size: pixels, format: format).image { _ in draw(in: CGRect(origin: .zero, size: pixels)) }
    }
}

/// The share sheet for a picture, handed the full-size image itself so Copy, Save Image and every app get all of it.
@MainActor enum ImageShareSheet {
    static func present(_ image: UIImage) {
        let sheet = UIActivityViewController(activityItems: [image.flattened], applicationActivities: nil)
        guard let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        // On iPad the sheet is a popover and needs somewhere to point.
        sheet.popoverPresentationController?.sourceView = top.view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 80, width: 0, height: 0)
        sheet.popoverPresentationController?.permittedArrowDirections = .down
        top.present(sheet, animated: true)
    }
}

/// Share, Save to Photos and Copy for a rendered story card, each handing over the full 1080 × 1920 picture.
struct ShareCardActions: View {
    var image: UIImage
    var shareTitle = "Share image"
    var hint = "Post it to an Instagram or TikTok story, or paste it into a chat."
    @State private var status: Status?

    enum Status: Equatable { case saved, copied, saveFailed }

    var body: some View {
        VStack(spacing: 10) {
            Button { ImageShareSheet.present(image) } label: {
                Label(shareTitle, systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            HStack(spacing: 10) {
                Button { Task { await save() } } label: {
                    Label("Save to Photos", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
                }
                Button(action: copy) {
                    Label("Copy", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered).controlSize(.large)
            Text(message).font(.roboto(.caption)).foregroundStyle(status == .saveFailed ? .red : .secondary)
                .multilineTextAlignment(.center).balanced()
                .contentTransition(.opacity).animation(.default, value: status)
        }
        .sensoryFeedback(trigger: status) { _, new in new == .saveFailed ? .error : new == nil ? nil : .success }
    }

    private var message: String {
        switch status {
        case .saved: "Saved to Photos."
        case .copied: "Copied. Paste it into a story or chat."
        case .saveFailed: "Couldn't save. Let Leanrrr add photos in Settings > Privacy > Photos."
        case nil: hint
        }
    }

    private func copy() {
        guard let png = image.flattened.pngData() else { return }
        UIPasteboard.general.setData(png, forPasteboardType: UTType.png.identifier)
        status = .copied
    }

    private func save() async {
        guard let png = image.flattened.pngData() else { return }
        status = await Self.addToPhotos(png) ? .saved : .saveFailed
    }

    /// Adds the PNG to the photo library as it is, asking for add-only access first. Off the main actor:
    /// Photos runs the change block on its own queue, and a main-actor closure there traps.
    nonisolated private static func addToPhotos(_ png: Data) async -> Bool {
        let access = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard access == .authorized || access == .limited else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: png, options: nil)
            }
            return true
        } catch {
            return false
        }
    }
}

/// Shows a story card before sharing it, so you see what you're posting, with ways to share, save or copy it.
struct StoryImagePreview: View {
    @Environment(\.dismiss) private var dismiss
    var name: String
    var make: @MainActor () -> UIImage?
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 20) {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .accessibilityLabel("Share image: \(name)")
                ShareCardActions(image: image)
            } else {
                ShareCardSkeleton()
            }
        }
        .padding()
        .navigationTitle("Share image").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .task { image = make() }
    }
}

/// A meal's story card, previewed before sharing.
struct MealSharePreview: View {
    var name: String
    var items: [Portion]
    var subtitle: String?

    var body: some View {
        StoryImagePreview(name: name) { MealShareCard.image(name: name, items: items, subtitle: subtitle) }
    }
}
