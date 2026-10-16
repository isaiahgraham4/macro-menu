import SwiftUI
import Charts

/// Progress: weight, measurements and photos, and a breakdown of the last week, month or three months of logging.
struct ProgressTabView: View {
    @Environment(AppStore.self) private var store
    @Environment(HealthSync.self) private var health
    @AppStorage("progress.range") private var range = 30
    @AppStorage(ProgressPage.storageKey) private var pageRaw = ProgressPage.overview.rawValue
    @AppStorage(MacroColours.proteinKey) private var proteinColour = "blue"
    @AppStorage(MacroColours.carbsKey) private var carbsColour = "orange"
    @AppStorage(MacroColours.fatKey) private var fatColour = "red"
    @AppStorage(ProgressPart.orderKey) private var orderText = ""
    @AppStorage(ProgressPart.hiddenKey) private var hiddenText = ""
    @State private var arranging = false

    private var breakdown: ProgressBreakdown {
        ProgressBreakdown.make(store.data, goals: store.goals, days: ProgressBreakdown.ranges.contains(range) ? range : 30)
    }
    private var trend: [WeightTrend.Point] { WeightTrend.points(store.data.weightLog) }
    private var page: ProgressPage { ProgressPage(rawValue: pageRaw) ?? .overview }

    var body: some View {
        let breakdown = breakdown
        LeanrList {
            Section {
                Picker("Show", selection: $pageRaw) {
                    ForEach(ProgressPage.allCases) { Text($0.title).tag($0.rawValue) }
                }.pickerStyle(.segmented)
                // The range changes the graphs, so Overview (check-in, insights and this week) leaves it out.
                if page != .overview {
                    Picker("Range", selection: $range) {
                        Text("7 days").tag(7); Text("30 days").tag(30); Text("90 days").tag(90)
                    }.pickerStyle(.segmented)
                }
            }
            ForEach(ProgressPart.shown(order: orderText, hidden: hiddenText).filter { $0.page == page }) { part in
                section(part, breakdown)
            }
        }
        .navigationTitle("Progress")
        .toolbar {
            Button { arranging = true } label: { Label("Arrange sections", systemImage: "arrow.up.arrow.down") }
        }
        .sheet(isPresented: $arranging) { NavigationStack { ProgressArrangeView(orderText: $orderText, hiddenText: $hiddenText) } }
    }

    @ViewBuilder private func section(_ part: ProgressPart, _ breakdown: ProgressBreakdown) -> some View {
        let logged = breakdown.loggedDays > 0
        switch part {
        case .checkIn: Section { CheckInRow() }
        case .insights: insightsSection(breakdown.days)
        case .weight: weightSection(breakdown)
        case .steps: StepsProgressSection(days: Dictionary(uniqueKeysWithValues: breakdown.points.map { ($0.key, $0.date) }))
        case .activeEnergy: ActiveEnergyProgressSection(days: Dictionary(uniqueKeysWithValues: breakdown.points.map { ($0.key, $0.date) }))
        case .body: BodySection()
        case .week: weekSection
        case .calories:
            if logged {
                caloriesSection(breakdown)
            } else {
                Section {
                    ContentUnavailableView("Nothing logged in the last \(breakdown.days) days", systemImage: "chart.bar",
                                           description: Text("Log a few days and your averages, macro split and biggest contributors fill in here."))
                }
            }
        case .averages: if logged { averagesSection(breakdown) }
        case .macros: if logged, let share = breakdown.share { macroSection(share, complete: breakdown.shareComplete) }
        case .meals: if logged && !breakdown.mealTimes.isEmpty { mealTimeSection(breakdown) }
        case .contributors: if logged && !breakdown.topFoods.isEmpty { contributorsSection(breakdown) }
        }
    }

    // MARK: Insights

    @ViewBuilder private func insightsSection(_ days: Int) -> some View {
        let insights = Insights.make(store.data, goals: store.goals, days: days)
        if !insights.isEmpty {
            Section {
                ForEach(insights) { insight in
                    Label { Text(insight.text) } icon: { Image(systemName: insight.systemImage).foregroundStyle(.tint) }
                }
            } header: { Text("Insights · last \(days) days") }
        }
    }

    // MARK: Your week

    /// This week at a glance, whatever range is chosen. The full review has earlier weeks and a card to share.
    @ViewBuilder private var weekSection: some View {
        let review = WeeklyReview.make(store.data, goals: store.goals)
        Section {
            if review.loggedDays == 0 {
                Text("Nothing logged this week yet.").foregroundStyle(.secondary)
            } else {
                LabeledContent("Days logged", value: "\(review.loggedDays) of 7")
                if let calories = review.averageCalories {
                    LabeledContent("Average calories", value: "\(calories.rounded().number)\(review.calorieTarget.map { " · target \($0.rounded().number)" } ?? "")")
                }
                if let protein = review.averageProtein {
                    LabeledContent("Average protein", value: "\(protein.rounded().number) g\(review.proteinTarget.map { " · target \($0.rounded().number)" } ?? "")")
                }
                if review.proteinTarget != nil {
                    LabeledContent("Protein target hit", value: "\(review.proteinDays) \(review.proteinDays == 1 ? "day" : "days")")
                }
                if review.calorieTarget != nil {
                    LabeledContent("On or under calories", value: "\(review.calorieDays) \(review.calorieDays == 1 ? "day" : "days")")
                }
                if let change = review.weightChange {
                    LabeledContent("Weight trend", value: "\(WeeklyReview.signed(change)) kg")
                }
                ForEach(review.nudges, id: \.self) { Text($0).font(.roboto(.subheadline)).foregroundStyle(.secondary) }
                if !review.topMeals.isEmpty {
                    LabeledContent("Most logged", value: review.topMeals.map(\.name).joined(separator: ", "))
                }
            }
            NavigationLink { WeeklyReviewView() } label: { Label("Full review and sharing", systemImage: "chart.bar.xaxis") }
        } header: {
            Text("Your week · \(WeeklyReviewCard.range(review))")
        }
    }

    // MARK: Weight

    @ViewBuilder private func weightSection(_ breakdown: ProgressBreakdown) -> some View {
        let shown = trend.filter { $0.date >= breakdown.start }
        Section {
            NavigationLink { WeightView() } label: {
                HStack(spacing: 14) {
                    Image(systemName: "scalemass.fill").font(.title2).foregroundStyle(.tint).frame(width: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        if let last = trend.last {
                            Text("\(last.trend.number) kg").font(.roboto(.headline)).monospacedDigit()
                            if let change = breakdown.weightChange {
                                Text("\(WeeklyReview.signed(change)) kg over \(breakdown.days) days")
                                    .font(.roboto(.caption)).foregroundStyle(.secondary)
                            } else if let weekly = WeightTrend.weeklyChange(trend) {
                                Text("Trend \(WeeklyReview.signed(weekly)) kg a week").font(.roboto(.caption)).foregroundStyle(.secondary)
                            }
                            if let goal = store.data.weightGoal, let status = WeightTrend.goalStatus(goal, points: trend) {
                                Text(status.direction == .reached ? "At your goal of \(goal.kg.kgText) kg"
                                     : "Goal \(goal.kg.kgText) kg · \(status.remaining.number) kg to go")
                                    .font(.roboto(.caption)).foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Log your weight").font(.roboto(.headline))
                            Text("See your trend, set a goal and a projected date").font(.roboto(.caption)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let active = health.activeEnergyToday {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("\(active.rounded().number) Cal").font(.roboto(.headline)).monospacedDigit()
                            Text("active today").font(.roboto(.caption)).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }.padding(.vertical, 4)
            }
            if shown.count >= 2 {
                Chart {
                    ForEach(shown, id: \.date) { point in
                        PointMark(x: .value("Day", point.date), y: .value("Scale", point.kg)).foregroundStyle(.secondary).symbolSize(14)
                        LineMark(x: .value("Day", point.date), y: .value("Trend", point.trend))
                            .foregroundStyle(.tint).lineStyle(StrokeStyle(lineWidth: 3)).interpolationMethod(.monotone)
                    }
                }
                .chartYScale(domain: weightDomain(shown))
                .frame(height: 150)
                .accessibilityLabel("Weight trend over \(breakdown.days) days")
            }
        } header: { Text("Weight") }
    }

    private func weightDomain(_ points: [WeightTrend.Point]) -> ClosedRange<Double> {
        let values = points.flatMap { [$0.kg, $0.trend] }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        return (low - 1).rounded(.down)...(high + 1).rounded(.up)
    }

    // MARK: Breakdown

    private func caloriesSection(_ breakdown: ProgressBreakdown) -> some View {
        Section {
            Chart {
                ForEach(breakdown.points) { point in
                    if let calories = point.calories {
                        BarMark(x: .value("Day", point.date, unit: .day), y: .value("Cal", calories))
                            .foregroundStyle((point.calorieTarget.map { calories > $0 } ?? false) ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint))
                    }
                }
                if let target = breakdown.calorieTarget {
                    RuleMark(y: .value("Target", target)).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .frame(height: 170)
            .accessibilityLabel("Calories per day over \(breakdown.days) days")
        } header: { Text("Calories per day") } footer: {
            Text(breakdown.calorieTarget == nil ? "Days you didn't log are left empty."
                 : "The dashed line is your target. Bars over it are orange, and days you didn't log are left empty.")
        }
    }

    private func averagesSection(_ breakdown: ProgressBreakdown) -> some View {
        Section {
            LabeledContent("Days logged", value: "\(breakdown.loggedDays) of \(breakdown.days)")
            if let calories = breakdown.averageCalories {
                LabeledContent("Calories", value: "\(calories.rounded().number)\(breakdown.calorieTarget.map { " · target \($0.rounded().number)" } ?? "")")
                if breakdown.calorieTarget != nil {
                    LabeledContent("Days on or under target", value: "\(breakdown.calorieDays) of \(breakdown.loggedDays)")
                }
            }
            if let protein = breakdown.averageProtein {
                LabeledContent("Protein", value: "\(protein.rounded().number) g\(breakdown.proteinTarget.map { " · target \($0.rounded().number)" } ?? "")")
                if breakdown.proteinTarget != nil {
                    LabeledContent("Days on or over target", value: "\(breakdown.proteinDays) of \(breakdown.loggedDays)")
                }
            }
            average("Carbs", breakdown.carbs, unit: "g")
            average("Fat", breakdown.fat, unit: "g")
            average("Fibre", breakdown.fibre, unit: "g")
            average("Sodium", breakdown.sodium, unit: "mg")
            if let water = breakdown.water.value {
                LabeledContent("Water", value: "\(Water.text(water)) · \(breakdown.water.countedDays) days logged")
            }
        } header: { Text("Daily averages") } footer: {
            Text("Averages count only the days you logged. Carbs, fat, fibre and sodium count only days where every food you logged lists them.")
        }
    }

    @ViewBuilder private func average(_ title: String, _ value: ProgressBreakdown.Average, unit: String) -> some View {
        if let average = value.value {
            LabeledContent(title, value: "\(average.rounded().number) \(unit) · \(value.countedDays) days counted")
        }
    }

    private func macroSection(_ share: ProgressBreakdown.MacroShare, complete: Bool) -> some View {
        let choices = Premium.isUnlocked ? ["p": proteinColour, "c": carbsColour, "f": fatColour] : [:]
        let parts: [(name: String, key: String, value: Double)] = [("Protein", "p", share.protein), ("Carbs", "c", share.carbs), ("Fat", "f", share.fat)]
        return Section {
            Chart(parts, id: \.key) { part in
                BarMark(x: .value("Share", part.value)).foregroundStyle(MacroColours.colour(part.key, choices: choices))
            }
            .chartXScale(domain: 0...1).chartXAxis(.hidden).chartLegend(.hidden).frame(height: 28)
            .accessibilityHidden(true)
            ForEach(parts, id: \.key) { part in
                HStack {
                    Circle().fill(MacroColours.colour(part.key, choices: choices)).frame(width: 10, height: 10)
                    Text(part.name)
                    Spacer()
                    Text("\(Int((part.value * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine)
            }
        } header: { Text("Where the calories come from") } footer: {
            Text(complete ? "Protein and carbs count 4 Cal a gram and fat 9. Alcohol isn't a macro, so it isn't in the split."
                 : "Some foods you logged list no carbs or fat, so these shares are approximate.")
        }
    }

    private func mealTimeSection(_ breakdown: ProgressBreakdown) -> some View {
        let biggest = breakdown.mealTimes.map(\.averageCalories).max() ?? 1
        return Section {
            ForEach(breakdown.mealTimes) { meal in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(meal.title)
                        Spacer()
                        Text("\(meal.averageCalories.rounded().number) Cal a day").monospacedDigit().foregroundStyle(.secondary)
                    }
                    ProgressView(value: meal.averageCalories, total: max(biggest, 1)).tint(.accentColor)
                }
                .accessibilityElement(children: .combine)
            }
        } header: { Text("By meal") } footer: {
            Text("Average calories at each meal on the days you logged.")
        }
    }

    private func contributorsSection(_ breakdown: ProgressBreakdown) -> some View {
        Section {
            ForEach(breakdown.topFoods) { food in
                VStack(alignment: .leading, spacing: 3) {
                    Text(food.name).font(.roboto(.headline))
                    Text("\(food.servings.number) \(food.servings == 1 ? "serving" : "servings") · \(food.calories.rounded().number) Cal · \(food.protein.rounded().number) g protein")
                        .font(.roboto(.caption)).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        } header: { Text("Biggest contributors") } footer: {
            Text("The foods that added the most calories over these \(breakdown.days) days.")
        }
    }
}

/// Progress is split into three pages so each one fits on a screen or two, instead of one long scroll.
enum ProgressPage: String, CaseIterable, Identifiable {
    case overview, body, eating
    var id: Self { self }
    static let storageKey = "progress.page"
    var title: String {
        switch self {
        case .overview: "Overview"
        case .body: "Body"
        case .eating: "Eating"
        }
    }
}

/// The sections of the Progress tab, in the order and with the ones hidden that you chose.
enum ProgressPart: String, CaseIterable, Identifiable {
    case checkIn, insights, weight, steps, activeEnergy, body, week, calories, averages, macros, meals, contributors
    var id: Self { self }
    static let orderKey = "progress.order"
    static let hiddenKey = "progress.hidden"

    var title: String {
        switch self {
        case .checkIn: "Weekly check-in"
        case .insights: "Insights"
        case .weight: "Weight"
        case .steps: "Steps"
        case .activeEnergy: "Calories burnt"
        case .body: "Measurements and photos"
        case .week: "Your week"
        case .calories: "Calories per day"
        case .averages: "Daily averages"
        case .macros: "Where the calories come from"
        case .meals: "By meal"
        case .contributors: "Biggest contributors"
        }
    }
    /// The page the section sits on.
    var page: ProgressPage {
        switch self {
        case .checkIn, .insights, .week: .overview
        case .weight, .body, .steps, .activeEnergy: .body
        case .calories, .averages, .macros, .meals, .contributors: .eating
        }
    }
    var systemImage: String {
        switch self {
        case .checkIn: "arrow.triangle.2.circlepath"
        case .insights: "lightbulb"
        case .weight: "scalemass"
        case .steps: "figure.walk"
        case .activeEnergy: "flame"
        case .body: "ruler"
        case .week: "calendar"
        case .calories: "chart.bar"
        case .averages: "equal.circle"
        case .macros: "chart.pie"
        case .meals: "fork.knife"
        case .contributors: "list.number"
        }
    }

    /// The saved order, with any section added since put at the end. Stored as names separated by commas.
    static func order(_ text: String) -> [ProgressPart] {
        var parts: [ProgressPart] = []
        for name in text.split(separator: ",") { if let part = ProgressPart(rawValue: String(name)), !parts.contains(part) { parts.append(part) } }
        return parts + allCases.filter { !parts.contains($0) }
    }
    static func hidden(_ text: String) -> Set<ProgressPart> { Set(text.split(separator: ",").compactMap { ProgressPart(rawValue: String($0)) }) }
    static func shown(order: String, hidden: String) -> [ProgressPart] {
        let hiddenParts = self.hidden(hidden)
        return self.order(order).filter { !hiddenParts.contains($0) }
    }
    static func text(_ parts: some Sequence<ProgressPart>) -> String { parts.map(\.rawValue).joined(separator: ",") }
}

/// Drag the Progress sections into the order you want, and hide the ones you don't use.
struct ProgressArrangeView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var orderText: String
    @Binding var hiddenText: String

    var body: some View {
        let order = ProgressPart.order(orderText), hidden = ProgressPart.hidden(hiddenText)
        List {
            Section {
                ForEach(order) { part in
                    HStack(spacing: 12) {
                        Image(systemName: part.systemImage).foregroundStyle(hidden.contains(part) ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint)).frame(width: 28)
                        Text(part.title).foregroundStyle(hidden.contains(part) ? .secondary : .primary)
                        Spacer()
                        Button {
                            var updated = hidden
                            if updated.contains(part) { updated.remove(part) } else { updated.insert(part) }
                            hiddenText = ProgressPart.text(ProgressPart.allCases.filter(updated.contains))
                        } label: {
                            Image(systemName: hidden.contains(part) ? "eye.slash" : "eye").frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(hidden.contains(part) ? "Show \(part.title)" : "Hide \(part.title)")
                    }
                }
                .onMove { from, to in
                    var parts = order; parts.move(fromOffsets: from, toOffset: to)
                    orderText = ProgressPart.text(parts)
                }
            } footer: { Text("Drag to reorder. Tap the eye to hide a section or bring it back.") }
            Section {
                Button("Reset to the usual order") { orderText = ""; hiddenText = "" }.disabled(orderText.isEmpty && hiddenText.isEmpty)
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Arrange Progress").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
