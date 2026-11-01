import SwiftUI

extension YearReview {
    /// The review as story cards, one for each thing there is to say.
    @MainActor func cards(chainName: (String) -> String) -> [StoryCard] {
        let name = String(year), footnote = name
        var cards = [StoryCard(icon: "calendar", title: "\(name) in Leanr", figure: (meals.formatted(), "meals logged"),
                               detail: "Across \(days.formatted()) \(days == 1 ? "day" : "days").", footnote: footnote)]
        if let topMeal {
            let chain = topChain.map { " \(chainName($0.id)) was your most logged restaurant." } ?? ""
            cards.append(StoryCard(icon: "fork.knife", title: topMeal.name, detail: "Your most logged meal, \(topMeal.count) \(topMeal.count == 1 ? "time" : "times").\(chain)", footnote: footnote))
        } else if let topChain {
            cards.append(StoryCard(icon: "fork.knife", title: chainName(topChain.id), detail: "Your most logged restaurant, \(topChain.count) \(topChain.count == 1 ? "item" : "items").", footnote: footnote))
        }
        cards.append(StoryCard(icon: "flame.fill", title: "Longest streak", figure: (bestStreak.formatted(), bestStreak == 1 ? "day" : "days"),
                               detail: proteinDays > 0 ? "And you hit your protein target on \(proteinDays.formatted()) \(proteinDays == 1 ? "day" : "days")." : "That's how habits start.", footnote: footnote))
        if let weight {
            cards.append(StoryCard(icon: "scalemass.fill", title: weight.losing ? "You lost" : "You gained", figure: (weight.moved.number, "kg"),
                                   detail: "On your way to \(weight.goal.number) kg.", footnote: footnote))
        }
        return cards
    }
}

/// The year's cards to swipe through, each one shareable as a story image.
struct YearReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    let review: YearReview
    @State private var images: [UIImage] = []
    @State private var page = 0

    var body: some View {
        VStack(spacing: 16) {
            if images.isEmpty {
                ShareCardSkeleton().padding(.bottom, 36).frame(maxHeight: .infinity)
            } else {
                TabView(selection: $page) {
                    ForEach(images.indices, id: \.self) { index in
                        Image(uiImage: images[index]).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 18)).padding(.bottom, 36).tag(index)
                            .accessibilityLabel("Card \(index + 1) of \(images.count)")
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always)).indexViewStyle(.page(backgroundDisplayMode: .always))
                ShareLink(item: ShareImage(image: images[min(page, images.count - 1)]),
                          preview: SharePreview("My \(String(review.year)) in Leanr", image: Image(uiImage: images[min(page, images.count - 1)]))) {
                    Label("Share this card", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
        .padding()
        .navigationTitle("Your \(String(review.year))").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task { images = review.cards(chainName: store.chainName).compactMap(\.image) }
    }
}
