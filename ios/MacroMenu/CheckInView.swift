import SwiftUI

/// The weekly check-in: how the week went, the pace you want, and a new calorie target to accept or pass on.
struct CheckInView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var pace = 0.0
    @State private var loaded = false

    private var suggestion: CheckIn.Suggestion? { CheckIn.suggestion(store.data, goals: store.goals, pace: pace) }
    private var week: WeeklyReview {
        WeeklyReview.make(store.data, goals: store.goals, ending: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
    }

    var body: some View {
        LeanrList {
            if let suggestion {
                weekSection(suggestion)
                paceSection(suggestion)
                targetSection(suggestion)
                Section {
                    Button {
                        if store.finishCheckIn(suggestion, accept: true) { store.notice = "Targets updated"; dismiss() }
                    } label: { Text("Use new targets").font(.roboto(.headline)).frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).controlSize(.large).listRowSeparator(.hidden)
                    Button("Keep my current targets") {
                        if store.finishCheckIn(suggestion, accept: false) { store.notice = "Check-in done"; dismiss() }
                    }.frame(maxWidth: .infinity)
                } footer: {
                    Text("Either way, the next check-in is in a week. These are estimates: talk to a doctor or Accredited Practising Dietitian before big changes, especially if you're pregnant, have a medical condition or have had an eating disorder.")
                }
            } else {
                notReadySection
            }
            historySection
        }
        .navigationTitle("Weekly check-in").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            loaded = true; pace = CheckIn.pace(store.data)
        }
    }

    private func weekSection(_ suggestion: CheckIn.Suggestion) -> some View {
        Section {
            Text(CheckIn.headline(suggestion)).font(.roboto(.headline))
            if let trend = suggestion.trendWeight { LabeledContent("Trend weight", value: "\(trend.number) kg") }
            LabeledContent("Days logged this week", value: "\(week.loggedDays) of 7")
            if let average = week.averageCalories { LabeledContent("Average eaten", value: "\(average.rounded().number) Cal a day") }
            LabeledContent("Measured maintenance", value: "\(suggestion.maintenance.rounded().number) Cal a day")
        } header: { Text("How it's going") } footer: {
            Text("Maintenance is what you've eaten less what went into weight change, from \(suggestion.loggedDays) logged days and your weight trend over the last 4 weeks. It's most accurate when you log everything.")
        }
    }

    private func paceSection(_ suggestion: CheckIn.Suggestion) -> some View {
        Section {
            Picker("Pace", selection: $pace) {
                ForEach(CheckIn.paces, id: \.self) { Text(CheckIn.paceText($0)).tag($0) }
            }
            if suggestion.paceIsFast {
                Text("That's more than 1% of your body weight a week, which is hard to keep up and can cost muscle. A slower pace is easier to stick with.")
                    .font(.roboto(.caption)).foregroundStyle(.orange)
            }
        } header: { Text("Your goal") }
    }

    private func targetSection(_ suggestion: CheckIn.Suggestion) -> some View {
        let current = store.goals.values
        return Section {
            change("Calories", from: current["cal"], to: suggestion.calories, unit: "Cal")
            if let protein = current["p"] { LabeledContent("Protein", value: "\(protein.rounded().number) g · unchanged") }
            if let carbs = suggestion.values["c"] { change("Carbs", from: current["c"], to: carbs, unit: "g") }
            if let fat = suggestion.values["f"] { change("Fat", from: current["f"], to: fat, unit: "g") }
        } header: { Text("New daily targets") } footer: {
            if suggestion.limitedByFloor {
                Text("Leanr won't suggest less than \(CheckIn.lowest.number) Cal a day. Choose a slower pace, or talk to a health professional about going lower.")
            } else if suggestion.limitedByStep {
                Text("Your pace needs a bigger change than this, so it's taken \(CheckIn.largestStep.number) Cal at a time. Next week's check-in goes further if it's still needed.")
            } else {
                Text("Protein stays where it is. Carbs and fat change together, in the same proportions as now.")
            }
        }
    }

    private func change(_ title: String, from old: Double?, to new: Double, unit: String) -> some View {
        LabeledContent(title) {
            if let old, abs(old - new) >= 1 {
                Text("\(old.rounded().number) → \(new.rounded().number) \(unit)").monospacedDigit()
            } else {
                Text("\(new.rounded().number) \(unit)").monospacedDigit()
            }
        }
    }

    private var notReadySection: some View {
        let ready = CheckIn.readiness(store.data)
        return Section {
            Label("Not enough to go on yet", systemImage: "hourglass").font(.roboto(.headline))
            if ready.daysNeeded > 0 {
                LabeledContent("Days logged (last 4 weeks)", value: "\(ready.loggedDays) of 10")
            }
            if ready.weighInDaysNeeded > 0 {
                LabeledContent("Weigh-ins span", value: "\(ready.weighInSpan) of 14 days")
            }
        } footer: {
            Text("Check-ins measure your maintenance from what you eat and how your weight moves, so they need at least 10 logged days and two weeks of weigh-ins in the last four weeks. Weigh in a few times a week, ideally at the same time of day.")
        }
    }

    @ViewBuilder private var historySection: some View {
        let records = (store.data.checkIns ?? []).sorted { $0.date > $1.date }.prefix(8)
        if !records.isEmpty {
            Section("Earlier check-ins") {
                ForEach(Array(records)) { record in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.date.formatted(date: .abbreviated, time: .omitted)).font(.roboto(.headline))
                        Text(historyText(record)).font(.roboto(.caption)).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func historyText(_ record: CheckInRecord) -> String {
        var parts: [String] = []
        if let weekly = record.weeklyChange { parts.append("\(WeeklyReview.signed(weekly)) kg a week") }
        if record.accepted {
            parts.append(record.previousCalories.map { "\($0.rounded().number) → \(record.calories.rounded().number) Cal" } ?? "\(record.calories.rounded().number) Cal")
        } else {
            parts.append("kept \(record.previousCalories.map { "\($0.rounded().number) Cal" } ?? "targets")")
        }
        return parts.joined(separator: " · ")
    }
}

/// A row that opens the check-in, saying whether it's ready, when the next is, or what it still needs.
struct CheckInRow: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationLink { CheckInView() } label: {
            HStack(spacing: 14) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill").font(.title2).foregroundStyle(.tint).frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Weekly check-in").font(.roboto(.headline))
                    Text(status).font(.roboto(.caption)).foregroundStyle(.secondary)
                }
            }.padding(.vertical, 4)
        }
    }

    private var status: String {
        let data = store.data
        if CheckIn.isDue(data) {
            if let suggestion = CheckIn.suggestion(data, goals: store.goals, pace: CheckIn.pace(data)) {
                return suggestion.change.map { abs($0) >= 1 ? "Ready: a new target of \(suggestion.calories.rounded().number) Cal" : "Ready: your target still fits" } ?? "Ready to look at"
            }
            let ready = CheckIn.readiness(data)
            var needs: [String] = []
            if ready.daysNeeded > 0 { needs.append("\(ready.daysNeeded) more logged \(ready.daysNeeded == 1 ? "day" : "days")") }
            if ready.weighInDaysNeeded > 0 { needs.append("\(ready.weighInDaysNeeded) more days of weigh-ins") }
            return needs.isEmpty ? "Not enough data yet" : "Needs " + needs.joined(separator: " and ")
        }
        return CheckIn.nextDate(data).map { "Next on \($0.formatted(.dateTime.weekday(.wide).day().month()))" } ?? ""
    }
}

extension CheckIn {
    /// Whether to put the check-in on Today: it's due and there's a suggestion to look at.
    @MainActor static func showOnToday(_ store: AppStore) -> Bool {
        isDue(store.data) && suggestion(store.data, goals: store.goals, pace: pace(store.data)) != nil
    }
}
