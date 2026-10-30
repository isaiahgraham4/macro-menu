import SwiftUI

/// A 9:16 card for an Instagram or TikTok story: a milestone, its figure and a line about it.
struct MilestoneShareCard: View {
    @AppStorage(AppAccent.storageKey) private var accentRaw = AppAccent.standard.rawValue
    let moment: Moment
    var date = Date()

    var body: some View {
        let copy = moment.copy, accent = AppAccent.resolved(accentRaw).color
        VStack(alignment: .leading, spacing: 0) {
            Label("LEANR", systemImage: "leaf.fill").font(.roboto(.caption, weight: .bold)).foregroundStyle(accent)
            Spacer(minLength: 24)
            Image(systemName: copy.icon).font(.system(size: 44)).foregroundStyle(accent).padding(.bottom, 22)
            Text(copy.title).font(.custom(AppFonts.display, size: copy.figure == nil ? 64 : 40)).lineLimit(3).minimumScaleFactor(0.5)
            if let figure = copy.figure {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(figure.value.number).font(.custom(AppFonts.display, size: 96)).monospacedDigit()
                    Text(figure.unit).font(.roboto(.title2)).foregroundStyle(.white.opacity(0.6))
                }.padding(.top, 6)
            }
            Text(copy.detail.replacingOccurrences(of: " Tap for your review.", with: ""))
                .font(.roboto(.title3)).foregroundStyle(.white.opacity(0.75)).padding(.top, 14)
            if let progress = copy.progress {
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    GeometryReader { geometry in Capsule().fill(accent).frame(width: geometry.size.width * progress) }
                }.frame(height: 8).padding(.top, 24)
            }
            Spacer(minLength: 24)
            Text(date.formatted(date: .long, time: .omitted)).font(.roboto(.subheadline)).foregroundStyle(.white.opacity(0.6))
            Text("Tracked with Leanr").font(.roboto(.caption2)).foregroundStyle(.white.opacity(0.45)).padding(.top, 6)
        }
        .padding(.horizontal, 32).padding(.vertical, 40)
        .frame(width: MealShareCard.size.width, height: MealShareCard.size.height, alignment: .topLeading)
        .background(Color(red: 0.07, green: 0.07, blue: 0.08))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        // A picture, not a screen: the same size whatever text size the sharer uses.
        .dynamicTypeSize(.large)
    }

    /// The card drawn at three times its size: 1080 × 1920, a story's own size.
    @MainActor static func image(_ moment: Moment) -> UIImage? {
        let renderer = ImageRenderer(content: MilestoneShareCard(moment: moment))
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// Shows a milestone's story card before sharing it, so you see what you're posting.
struct MomentSharePreview: View {
    @Environment(\.dismiss) private var dismiss
    let moment: Moment
    @State private var image: UIImage?

    var body: some View {
        let title = moment.copy.title
        VStack(spacing: 20) {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .accessibilityLabel("Share image: \(title)")
                ShareLink(item: ShareImage(image: image), preview: SharePreview(title, image: Image(uiImage: image))) {
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
        .task { image = MilestoneShareCard.image(moment) }
    }
}
