import SwiftUI

struct WeeklyReviewView: View {
    @Environment(AppStore.self) private var store
    @State private var weeksBack = 0
    @State private var image: UIImage?
    private var review: WeeklyReview {
        let end = Calendar.current.date(byAdding: .day, value: -7 * weeksBack, to: Date()) ?? Date()
        return WeeklyReview.make(store.data, goals: store.goals, ending: end)
    }

    var body: some View {
        let review = review
        LeanrList {
            Section {
                HStack {
                    Button { weeksBack += 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("Previous week")
                    Spacer()
                    Text(WeeklyReviewCard.range(review)).font(.roboto(.headline))
                    Spacer()
                    Button { weeksBack -= 1 } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44).contentShape(Rectangle()) }
                        .disabled(weeksBack == 0).accessibilityLabel("Next week")
                }.buttonStyle(.borderless)
            }
            if review.loggedDays == 0 {
                ContentUnavailableView("Nothing logged this week", systemImage: "calendar",
                                       description: Text("Log a few days and your review fills in here."))
            } else {
                Section {
                    StatGrid(review: review)
                } footer: { Text("Averages count only the days you logged, so they aren't pulled down by days you skipped.") }
                if !review.nudges.isEmpty {
                    Section {
                        ForEach(review.nudges, id: \.self) { Text($0).font(.roboto(.subheadline)) }
                    } header: { Text("Fibre and sodium") } footer: {
                        Text("Counts only days where every food you logged lists the nutrient (fibre on \(review.fibre.countedDays) of \(review.loggedDays) logged days, sodium on \(review.sodium.countedDays)). A guide isn't a diagnosis: if you have a medical reason to watch either, follow your doctor or dietitian.")
                    }
                }
                if !review.topMeals.isEmpty {
                    Section("Most logged") {
                        ForEach(review.topMeals, id: \.name) { meal in
                            LabeledContent(meal.name, value: "\(meal.count) times")
                        }
                    }
                }
                if let image {
                    Section {
                        ShareLink(item: Image(uiImage: image), preview: SharePreview("My week in Leanr", image: Image(uiImage: image))) {
                            Label("Share this week", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .navigationTitle("Your week")
        .task(id: review) {
            let renderer = ImageRenderer(content: WeeklyReviewCard(review: review)); renderer.scale = 3
            image = review.loggedDays > 0 ? renderer.uiImage : nil
        }
    }
}

/// The review's numbers as tiles.
private struct StatGrid: View {
    var review: WeeklyReview
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(spacing: 12) {
          tile("Total calories", "\(review.totalCalories.rounded().number) Cal", review.totalCalorieTarget.map {
              "Target \($0.rounded().number) Cal over \(review.loggedDays == 7 ? "the week" : review.loggedDays == 1 ? "the day you logged" : "the \(review.loggedDays) days you logged")"
          })
          LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            tile("Days logged", "\(review.loggedDays) of 7", nil)
            tile("Avg calories", review.averageCalories.map { "\($0.rounded().number)" } ?? "–",
                 review.calorieTarget.map { "Target \($0.rounded().number) Cal" })
            tile("Avg protein", review.averageProtein.map { "\($0.rounded().number) g" } ?? "–",
                 review.proteinTarget.map { "Target \($0.rounded().number) g" })
            tile("Protein hit", review.proteinTarget == nil ? "–" : "\(review.proteinDays) \(review.proteinDays == 1 ? "day" : "days")", "At or above target")
            tile("Calories on target", review.calorieTarget == nil ? "–" : "\(review.calorieDays) \(review.calorieDays == 1 ? "day" : "days")", "At or under target")
            tile("Avg fibre", review.fibre.average.map { "\($0.rounded().number) g" } ?? "–", nutrientDetail(review.fibre, unit: "g"))
            tile("Avg sodium", review.sodium.average.map { "\($0.rounded().number) mg" } ?? "–", nutrientDetail(review.sodium, unit: "mg"))
            tile("Weight trend", review.weightChange.map { "\(WeeklyReview.signed($0)) kg" } ?? "–",
                 review.trendWeight.map { "Now \($0.number) kg" } ?? "Weigh in to see it")
          }
        }.padding(.vertical, 4)
    }
    /// "Target 25 g · 4 of 6 days", or why there's no figure.
    private func nutrientDetail(_ week: WeeklyReview.NutrientWeek, unit: String) -> String {
        guard week.average != nil else { return "Not every food you logged lists it" }
        let label = week.targetIsGuide ? "Guide" : "Target"
        return "\(label) \(week.isMinimum ? "" : "≤ ")\(week.target.rounded().number) \(unit) · \(week.countedDays) of \(week.loggedDays) \(week.loggedDays == 1 ? "day" : "days")"
    }
    private func tile(_ title: String, _ value: String, _ detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.roboto(.caption)).foregroundStyle(.secondary)
            Text(value).font(.roboto(.title2, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            if let detail { Text(detail).font(.roboto(.caption)).foregroundStyle(.secondary).lineLimit(2) }
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading).padding(12)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

/// An always-light card to share, matching the meal card.
struct WeeklyReviewCard: View {
    @AppStorage(AppAccent.storageKey) private var accentRaw = AppAccent.standard.rawValue
    var review: WeeklyReview
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("LEANR", systemImage: "leaf.fill").font(.roboto(.caption, weight: .bold)).foregroundStyle(AppAccent.resolved(accentRaw).color)
            VStack(alignment: .leading, spacing: 2) {
                Text("My week").font(.display())
                Text(Self.range(review)).font(.roboto(.subheadline)).foregroundStyle(.secondary)
            }
            StatGrid(review: review)
            if !review.topMeals.isEmpty {
                Text("Most logged: " + review.topMeals.map(\.name).joined(separator: ", ")).font(.roboto(.subheadline))
            }
        }.padding(28).frame(width: 390).background(.white).foregroundStyle(.black).environment(\.colorScheme, .light)
    }
    static func range(_ review: WeeklyReview) -> String {
        "\(review.start.formatted(.dateTime.day().month(.abbreviated))) – \(review.end.formatted(.dateTime.day().month(.abbreviated)))"
    }
}
