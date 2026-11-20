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
    /// Any design but the docket, which is for meals; a docket here is drawn as Paper.
    var design: ShareDesign = .night

    var body: some View {
        let palette = (design == .docket ? .paper : design).palette(accent: AppAccent.resolvedColor(accentRaw))
        VStack(alignment: .leading, spacing: 0) {
            Label("LEANRRR", systemImage: "leaf.fill").font(.roboto(.caption, weight: .bold)).foregroundStyle(palette.brand)
            Spacer(minLength: 24)
            Image(systemName: icon).font(.system(size: 44)).foregroundStyle(palette.brand).padding(.bottom, 22)
            Text(title).font(.custom(AppFonts.display, size: figure == nil ? 64 : 40)).lineLimit(3).minimumScaleFactor(0.5)
            if let figure {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(figure.value).font(.custom(AppFonts.display, size: 96)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    Text(figure.unit).font(.roboto(.title2)).foregroundStyle(palette.dim)
                }.padding(.top, 6)
            }
            Text(detail).font(.roboto(.title3)).foregroundStyle(palette.ink.opacity(0.8)).padding(.top, 14)
            if let progress {
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.ink.opacity(0.15))
                    GeometryReader { geometry in Capsule().fill(palette.brand).frame(width: geometry.size.width * progress) }
                }.frame(height: 8).padding(.top, 24)
            }
            Spacer(minLength: 24)
            Text(footnote).font(.roboto(.subheadline)).foregroundStyle(palette.dim)
            Text("Tracked with Leanrrr").font(.roboto(.caption2)).foregroundStyle(palette.faint).padding(.top, 6)
        }
        .padding(.horizontal, 32).padding(.vertical, 40)
        .modifier(ShareSurface(palette: palette))
    }

    /// The card drawn at three times its size: 1080 × 1920, a story's own size.
    @MainActor var image: UIImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 3
        renderer.isOpaque = !design.isTransparent
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
    let moment: Moment

    var body: some View {
        StoryImagePreview(name: moment.copy.title, designs: ShareDesign.forMoments) { design in
            var card = moment.storyCard
            card.design = design
            return card.image
        }
    }
}
