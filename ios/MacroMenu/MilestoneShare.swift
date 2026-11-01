import SwiftUI

/// The 9:16 story card behind milestones and the year in review: an icon, a title, a big figure and a line about it.
struct StoryCard: View {
    @AppStorage(AppAccent.storageKey) private var accentRaw = AppAccent.standard.rawValue
    var icon: String
    var title: String
    var figure: (value: String, unit: String)?
    var detail: String
    var progress: Double?
    var footnote: String

    var body: some View {
        let accent = AppAccent.resolved(accentRaw).color
        VStack(alignment: .leading, spacing: 0) {
            Label("TAKEAWISE", systemImage: "leaf.fill").font(.roboto(.caption, weight: .bold)).foregroundStyle(accent)
            Spacer(minLength: 24)
            Image(systemName: icon).font(.system(size: 44)).foregroundStyle(accent).padding(.bottom, 22)
            Text(title).font(.custom(AppFonts.display, size: figure == nil ? 64 : 40)).lineLimit(3).minimumScaleFactor(0.5)
            if let figure {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(figure.value).font(.custom(AppFonts.display, size: 96)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    Text(figure.unit).font(.roboto(.title2)).foregroundStyle(.white.opacity(0.6))
                }.padding(.top, 6)
            }
            Text(detail).font(.roboto(.title3)).foregroundStyle(.white.opacity(0.75)).padding(.top, 14)
            if let progress {
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    GeometryReader { geometry in Capsule().fill(accent).frame(width: geometry.size.width * progress) }
                }.frame(height: 8).padding(.top, 24)
            }
            Spacer(minLength: 24)
            Text(footnote).font(.roboto(.subheadline)).foregroundStyle(.white.opacity(0.6))
            Text("Tracked with Takeawise").font(.roboto(.caption2)).foregroundStyle(.white.opacity(0.45)).padding(.top, 6)
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
    @MainActor var image: UIImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 3
        return renderer.uiImage
    }
}

extension Moment {
    /// The moment as a story card.
    var storyCard: StoryCard {
        let copy = self.copy
        return StoryCard(icon: copy.icon, title: copy.title, figure: copy.figure.map { ($0.value.number, $0.unit) },
                         detail: copy.detail.replacingOccurrences(of: " Tap for your review.", with: ""), progress: copy.progress,
                         footnote: Date().formatted(date: .long, time: .omitted))
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
                    .font(.roboto(.caption)).foregroundStyle(.secondary).multilineTextAlignment(.center).balanced()
            } else {
                ShareCardSkeleton()
            }
        }
        .padding()
        .navigationTitle("Share image").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .task { image = moment.storyCard.image }
    }
}
