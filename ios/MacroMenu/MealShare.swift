import Photos
import PhotosUI
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

/// One meal time on a whole-day card: "Lunch" and what was logged to it.
struct MealShareGroup: Hashable {
    var title: String
    var items: [Portion]
}

/// What a share-image sheet should draw: one meal, one meal time, or a whole day split by meal.
struct MealShareRequest: Identifiable {
    let id = UUID()
    var name: String
    var items: [Portion]
    var subtitle: String?
    var groups: [MealShareGroup] = []

    /// A day's log as a card: every meal time with something in it, then anything not given one.
    static func day(_ entries: [LogEntry], on date: Date) -> MealShareRequest {
        var groups = MealTime.allCases.compactMap { time -> MealShareGroup? in
            let items = entries.filter { $0.mealTime == time }.flatMap(\.items)
            return items.isEmpty ? nil : MealShareGroup(title: time.title, items: items)
        }
        let other = entries.filter { $0.mealTime == nil }.flatMap(\.items)
        if !other.isEmpty { groups.append(MealShareGroup(title: "Other", items: other)) }
        return MealShareRequest(name: date.formatted(.dateTime.weekday(.wide)), items: entries.flatMap(\.items),
                                subtitle: date.formatted(.dateTime.day().month(.wide).year()), groups: groups)
    }

    /// Everything logged to one meal time, such as the day's lunch.
    static func meal(_ time: MealTime, _ entries: [LogEntry], on date: Date) -> MealShareRequest {
        let logged = entries.filter { $0.mealTime == time }
        return MealShareRequest(name: logged.count == 1 ? logged[0].name : time.title, items: logged.flatMap(\.items),
                                subtitle: "\(time.title) · \(date.formatted(.dateTime.day().month(.abbreviated)))")
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
    /// For a whole day: a row per meal time in place of the food list.
    var groups: [MealShareGroup] = []
    var design: ShareDesign = .night

    static let size = CGSize(width: 360, height: 640)

    private var total: Nutrition { Nutrition(items) }
    private var lines: [Portion] { mealLines(items) }
    private var isRecipe: Bool { items.contains { $0.ingredientPortions != nil } }
    private var palette: SharePalette { design.palette(accent: AppAccent.resolvedColor(accentRaw)) }
    private func colour(_ key: String) -> Color {
        MacroColours.colour(key, choices: Premium.isUnlocked ? ["p": proteinColour, "c": carbsColour, "f": fatColour] : [:])
    }

    var body: some View {
        // The card is a fixed 9:16, so it tries fewer ingredient rows until the name, macros and rows all fit above the footer.
        Group {
            if design == .docket {
                ViewThatFits(in: .vertical) {
                    docket(rows: 10); docket(rows: 8); docket(rows: 6); docket(rows: 5); docket(rows: 4); docket(rows: 3); docket(rows: 2); docket(rows: 1)
                }
            } else {
                ViewThatFits(in: .vertical) {
                    card(rows: 9); card(rows: 7); card(rows: 6); card(rows: 5); card(rows: 4); card(rows: 3); card(rows: 2); card(rows: 1)
                }
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 36)
        .modifier(ShareSurface(palette: palette))
    }

    /// The card's contents, listing up to `rows` ingredient lines (the last of them "and N more" when there are too many).
    private func card(rows: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("LEANRRR", systemImage: "leaf.fill").font(.roboto(.caption, weight: .bold))
                .foregroundStyle(palette.brand)
            Text(name).font(.custom(AppFonts.display, size: 54)).lineLimit(3).minimumScaleFactor(0.5)
                .padding(.top, 18)
            if let subtitle { Text(subtitle).font(.roboto(.subheadline)).foregroundStyle(palette.dim) }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(total.cal.rounded().number).font(.custom(AppFonts.display, size: 72)).monospacedDigit()
                Text("Cal").font(.roboto(.title3)).foregroundStyle(palette.dim)
            }.padding(.top, 20)

            HStack(spacing: 10) {
                macro("Protein", total.p, missing: false, key: "p")
                macro("Carbs", total.c, missing: total.missingCarbs, key: "c")
                macro("Fat", total.f, missing: total.missingFat, key: "f")
            }.padding(.top, 6)

            if !groups.isEmpty {
                Text("BY MEAL").font(.roboto(.caption, weight: .bold)).foregroundStyle(palette.dim)
                    .padding(.top, 26).padding(.bottom, 8)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(groups, id: \.self) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(group.title).font(.roboto(.subheadline, weight: .semibold))
                                Spacer(minLength: 8)
                                Text("\(Nutrition(group.items).cal.rounded().number) Cal").font(.roboto(.subheadline))
                                    .foregroundStyle(palette.dim).monospacedDigit()
                            }
                            // Fewer rows to fit means fewer food names under each meal, down to just the totals.
                            if rows > 2 {
                                Text(mealLines(group.items).map(\.food.name).joined(separator: ", "))
                                    .font(.roboto(.caption)).foregroundStyle(palette.dim).lineLimit(rows > 5 ? 2 : 1)
                            }
                        }
                    }
                }
            } else if !lines.isEmpty {
                Text(isRecipe ? "INGREDIENTS" : "IN THIS MEAL").font(.roboto(.caption, weight: .bold)).foregroundStyle(palette.dim)
                    .padding(.top, 26).padding(.bottom, 8)
                let shown = lines.count > rows ? max(rows - 1, 0) : rows
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(lines.prefix(shown)) { line in
                        HStack(alignment: .firstTextBaseline) {
                            Text(line.food.name).font(.roboto(.subheadline)).lineLimit(2)
                            Spacer(minLength: 8)
                            Text(line.amountText).font(.roboto(.subheadline)).foregroundStyle(palette.dim).monospacedDigit().lineLimit(1)
                        }
                    }
                    if lines.count > shown {
                        Text("and \(lines.count - shown) more").font(.roboto(.subheadline)).foregroundStyle(palette.dim)
                    }
                }
            }
            Spacer(minLength: 12)
            Text("Tracked with Leanrrr · Nutrition may vary").font(.roboto(.caption2)).foregroundStyle(palette.faint)
        }
    }

    private func macro(_ label: String, _ value: Double, missing: Bool, key: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Capsule().fill(palette.plainBars ? palette.ink : colour(key)).frame(height: 4)
            Text("\(value.rounded().number)\(missing ? "+" : "") g").font(.roboto(.title3, weight: .semibold)).monospacedDigit()
            Text(label).font(.roboto(.caption)).foregroundStyle(palette.dim)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .monospaced) }

    /// The meal as a takeaway receipt: each line with its calories, then the total and macros. Up to `rows` lines.
    private func docket(rows: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 4) {
                Text("LEANRRR").font(mono(15, .bold)).tracking(4)
                Text(subtitle ?? Date().formatted(date: .abbreviated, time: .omitted)).font(mono(12)).foregroundStyle(palette.dim)
            }
            .frame(maxWidth: .infinity)
            DashedRule(colour: palette.faint).padding(.vertical, 14)
            Text(name.uppercased()).font(mono(22, .bold)).lineLimit(2).minimumScaleFactor(0.6)
            DashedRule(colour: palette.faint).padding(.vertical, 14)

            VStack(alignment: .leading, spacing: 9) {
                if !groups.isEmpty {
                    ForEach(groups, id: \.self) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            docketLine(group.title.uppercased(), "\(Nutrition(group.items).cal.rounded().number)", bold: true)
                            if rows > 3 {
                                Text(mealLines(group.items).map(\.food.name).joined(separator: ", "))
                                    .font(mono(11)).foregroundStyle(palette.dim).lineLimit(rows > 6 ? 2 : 1)
                            }
                        }
                    }
                } else {
                    let shown = lines.count > rows ? max(rows - 1, 0) : rows
                    ForEach(lines.prefix(shown)) { line in
                        VStack(alignment: .leading, spacing: 1) {
                            docketLine(line.food.name, "\((line.food.cal * line.quantity).rounded().number)")
                            if rows > 4 { Text(line.amountText).font(mono(11)).foregroundStyle(palette.dim).lineLimit(1) }
                        }
                    }
                    if lines.count > shown {
                        Text("+ \(lines.count - shown) more").font(mono(13)).foregroundStyle(palette.dim)
                    }
                }
            }

            DashedRule(colour: palette.faint).padding(.vertical, 14)
            HStack(alignment: .firstTextBaseline) {
                Text("TOTAL"); Spacer(minLength: 8); Text("\(total.cal.rounded().number) Cal").monospacedDigit()
            }.font(mono(20, .bold))
            VStack(spacing: 4) {
                docketLine("Protein", "\(total.p.rounded().number) g")
                docketLine("Carbs", "\(total.c.rounded().number)\(total.missingCarbs ? "+" : "") g")
                docketLine("Fat", "\(total.f.rounded().number)\(total.missingFat ? "+" : "") g")
            }.padding(.top, 8)

            Spacer(minLength: 12)
            DashedRule(colour: palette.faint).padding(.bottom, 10)
            VStack(spacing: 3) {
                Text("THANK YOU · TRACKED WITH LEANRRR").font(mono(10, .semibold))
                Text("Nutrition may vary").font(mono(10)).foregroundStyle(palette.faint)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// "Big Mac ........ 563" style: the name on the left, the figure on the right.
    private func docketLine(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).lineLimit(2)
            Spacer(minLength: 8)
            Text(value).monospacedDigit().lineLimit(1)
        }
        .font(mono(13, bold ? .bold : .regular))
    }

    /// The card drawn at three times its size: 1080 × 1920, a story's own size.
    @MainActor static func image(name: String, items: [Portion], subtitle: String? = nil, groups: [MealShareGroup] = [],
                                 design: ShareDesign = .night) -> UIImage? {
        let renderer = ImageRenderer(content: MealShareCard(name: name, items: items, subtitle: subtitle, groups: groups, design: design))
        renderer.scale = 3
        renderer.isOpaque = !design.isTransparent
        return renderer.uiImage
    }
}

extension UIImage {
    /// The same picture redrawn at 1×, so its pixel size is its size. A 3× render is 1080 × 1920 pixels but says 360 × 640,
    /// and apps that go by the stated size (pasting into Snapchat, for one) blow up the small version and it looks blurry.
    var flattened: UIImage { flattened(opaque: true) }

    /// The same, keeping see-through parts see-through when `opaque` is false (the Clear design).
    func flattened(opaque: Bool) -> UIImage {
        guard scale != 1 else { return self }
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1; format.opaque = opaque
        let pixels = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        return UIGraphicsImageRenderer(size: pixels, format: format).image { _ in draw(in: CGRect(origin: .zero, size: pixels)) }
    }
}

/// The share sheet for a picture, handed the full-size image itself so Copy, Save Image and every app get all of it.
@MainActor enum ImageShareSheet {
    static func present(_ image: UIImage, opaque: Bool = true) {
        let sheet = UIActivityViewController(activityItems: [image.flattened(opaque: opaque)], applicationActivities: nil)
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
    var hint = ShareCardActions.standardHint
    /// A see-through card (the Clear design): kept see-through in the PNG that's shared, saved or copied.
    var transparent = false
    @AppStorage(AppAccent.storageKey) private var accentRaw = AppAccent.standard.rawValue
    @State private var status: Status?

    static let standardHint = "Post it to an Instagram or TikTok story, or paste it into a chat."

    enum Status: Equatable { case saved, copied, saveFailed }

    var body: some View {
        VStack(spacing: 10) {
            Button { ImageShareSheet.present(image, opaque: !transparent) } label: {
                Label(shareTitle, systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .tint(AppAccent.resolvedColor(accentRaw))
            HStack(spacing: 10) {
                Button { Task { await save() } } label: {
                    Label("Save to Photos", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
                }
                Button(action: copy) {
                    Label("Copy", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered).controlSize(.large)
            .tint(AppAccent.resolvedColor(accentRaw))
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
        guard let png = image.flattened(opaque: !transparent).pngData() else { return }
        UIPasteboard.general.setData(png, forPasteboardType: UTType.png.identifier)
        status = .copied
    }

    private func save() async {
        guard let png = image.flattened(opaque: !transparent).pngData() else { return }
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

/// Shows a story card before sharing it, so you see what you're posting, with ways to share, save or copy it,
/// and a choice of designs when the card has them.
struct StoryImagePreview: View {
    @Environment(\.dismiss) private var dismiss
    var name: String
    /// The designs to offer; none means the card has one look and no picker is shown.
    var designs: [ShareDesign]
    var make: @MainActor (ShareDesign) -> UIImage?
    @AppStorage(ShareDesign.storageKey) private var designRaw = ShareDesign.night.rawValue
    @State private var image: UIImage?
    /// A photo of the food to put the card on, taken here or picked from Photos. Never saved by the app itself.
    @State private var photo: UIImage?
    @State private var camera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var photoProblem = false

    init(name: String, designs: [ShareDesign] = ShareDesign.allCases, make: @escaping @MainActor (ShareDesign) -> UIImage?) {
        self.name = name; self.designs = designs; self.make = make
    }

    /// A card with one look.
    init(name: String, make: @escaping @MainActor () -> UIImage?) {
        self.init(name: name, designs: []) { _ in make() }
    }

    /// The remembered design if this card offers it, otherwise its first.
    private var design: ShareDesign {
        guard let first = designs.first else { return .night }
        let saved = ShareDesign(rawValue: designRaw) ?? .night
        return designs.contains(saved) ? saved : first
    }

    /// See-through only when it's the Clear card on its own; on a photo it's a normal picture.
    private var transparent: Bool { design.isTransparent && photo == nil }

    private var hint: String {
        if photo != nil { return "Your photo with the card on it. Share it to a story or save it." }
        return design.hint ?? ShareCardActions.standardHint
    }

    var body: some View {
        VStack(spacing: 14) {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .background { if transparent { Checkerboard() } }
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .accessibilityLabel("Share image: \(name), \(design.name) design\(photo == nil ? "" : ", on your photo")")
            } else {
                ShareCardSkeleton()
            }
            if !designs.isEmpty { photoButtons }
            if designs.count > 1 { ShareDesignPicker(designs: designs, selection: $designRaw) }
            if let image { ShareCardActions(image: image, hint: hint, transparent: transparent) }
        }
        .padding()
        .navigationTitle("Share image").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .task(id: Render(design: design, photo: photo.map(ObjectIdentifier.init))) { render() }
        .onChange(of: pickerItem) {
            guard let item = pickerItem else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let picked = UIImage(data: data) { photo = picked }
                else { photoProblem = true }
                pickerItem = nil
            }
        }
        .fullScreenCover(isPresented: $camera) {
            ProgressCameraPicker { taken in
                camera = false
                if let taken { photo = taken }
            }.ignoresSafeArea()
        }
        .alert("That photo couldn't be opened.", isPresented: $photoProblem) { Button("OK", role: .cancel) {} }
        #if DEBUG
        // `-demoSharePhoto <path>` starts with that picture as the photo, since the simulator has no camera.
        .onAppear {
            let args = CommandLine.arguments
            if photo == nil, let i = args.firstIndex(of: "-demoSharePhoto"), i + 1 < args.count { photo = UIImage(contentsOfFile: args[i + 1]) }
        }
        #endif
    }

    /// Take a photo of the food or pick one, to put the card on; or take the photo off again.
    private var photoButtons: some View {
        HStack(spacing: 10) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { camera = true } label: {
                    Label(photo == nil ? "Take photo" : "Retake", systemImage: "camera").frame(maxWidth: .infinity)
                }
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(photo == nil ? "Choose photo" : "Change", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
            }
            if photo != nil {
                Button { photo = nil } label: { Label("No photo", systemImage: "xmark").frame(maxWidth: .infinity) }
            }
        }
        .buttonStyle(.bordered).controlSize(.small).labelStyle(.titleAndIcon)
        .font(.roboto(.subheadline))
    }

    /// What the picture depends on, so a new design or photo draws it again.
    private struct Render: Equatable {
        var design: ShareDesign
        var photo: ObjectIdentifier?
    }

    private func render() {
        guard let card = make(design) else { image = nil; return }
        image = photo.flatMap { PhotoStory.image(photo: $0, card: card, design: design) } ?? card
    }
}

/// Your photo filling a story with the card on it: the Clear card's words straight across the photo, any other design as a
/// small card in the bottom corner so the food stays in view.
struct PhotoStory: View {
    var photo: UIImage
    var card: UIImage
    var design: ShareDesign

    var body: some View {
        let size = MealShareCard.size
        ZStack(alignment: .bottomLeading) {
            Image(uiImage: photo).resizable().scaledToFill()
                .frame(width: size.width, height: size.height).clipped()
            if design.isTransparent {
                // A flat dim, so white words read over a bright plate.
                Color.black.opacity(0.3)
                Image(uiImage: card).resizable().frame(width: size.width, height: size.height)
            } else {
                Image(uiImage: card).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: size.width * 0.5)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                    .padding(18)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    /// Drawn at three times its size, 1080 × 1920 like the card.
    @MainActor static func image(photo: UIImage, card: UIImage, design: ShareDesign) -> UIImage? {
        let renderer = ImageRenderer(content: PhotoStory(photo: photo, card: card, design: design))
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

/// A meal's story card, previewed before sharing.
struct MealSharePreview: View {
    var name: String
    var items: [Portion]
    var subtitle: String?
    var groups: [MealShareGroup] = []

    init(name: String, items: [Portion], subtitle: String? = nil, groups: [MealShareGroup] = []) {
        self.name = name; self.items = items; self.subtitle = subtitle; self.groups = groups
    }
    init(_ request: MealShareRequest) {
        self.init(name: request.name, items: request.items, subtitle: request.subtitle, groups: request.groups)
    }

    var body: some View {
        StoryImagePreview(name: name) { design in
            MealShareCard.image(name: name, items: items, subtitle: subtitle, groups: groups, design: design)
        }
    }
}
