import SwiftUI
import Charts

struct WeightView: View {
    @Environment(AppStore.self) private var store
    @Environment(HealthSync.self) private var health
    @State private var kg = 0.0
    @State private var date = Date()
    @State private var range = 90
    @State private var estimating = false
    @State private var goalKG: Double?
    @State private var pace = 0.5
    private var points: [WeightTrend.Point] { WeightTrend.points(store.data.weightLog) }
    private var shown: [WeightTrend.Point] {
        let start = Calendar.current.date(byAdding: .day, value: -range, to: Date()) ?? .distantPast
        return points.filter { $0.date >= start }
    }
    private var weekly: Double? { WeightTrend.weeklyChange(points) }
    private var maintenance: WeightTrend.Maintenance? { WeightTrend.maintenance(logs: store.data.logs, points: points) }

    var body: some View {
        LeanrList {
            Section {
                if let last = points.last {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Trend").font(.roboto(.caption)).foregroundStyle(.secondary)
                            Text("\(last.trend.number) kg").font(.roboto(.title, weight: .bold)).monospacedDigit()
                        }
                        Spacer()
                        if let weekly {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Per week").font(.roboto(.caption)).foregroundStyle(.secondary)
                                Text(signed(weekly) + " kg").font(.roboto(.title3, weight: .semibold)).monospacedDigit()
                            }
                        }
                    }
                    Picker("Range", selection: $range) {
                        Text("30 days").tag(30); Text("90 days").tag(90); Text("1 year").tag(365)
                    }.pickerStyle(.segmented)
                    Chart {
                        ForEach(shown, id: \.date) { point in
                            PointMark(x: .value("Day", point.date), y: .value("Scale", point.kg))
                                .foregroundStyle(.secondary).symbolSize(18)
                            LineMark(x: .value("Day", point.date), y: .value("Trend", point.trend))
                                .foregroundStyle(.tint).lineStyle(StrokeStyle(lineWidth: 3)).interpolationMethod(.monotone)
                        }
                    }
                    .chartYScale(domain: yDomain)
                    .frame(height: 200)
                    .accessibilityLabel("Weight chart: trend \(last.trend.number) kg")
                } else {
                    ContentUnavailableView("No weigh-ins yet", systemImage: "scalemass",
                                           description: Text("Log your weight below. A few weigh-ins a week is enough to see your trend."))
                }
            } footer: {
                if !points.isEmpty { Text("Dots are scale readings; the line is your trend, which smooths out day-to-day swings from water and food.") }
            }

            goalSection

            Section("Log weight") {
                NumberField(title: "Weight (kg)", value: $kg, places: 2)
                DatePicker("Date", selection: $date, in: ...Date())
                Button("Save weight") { save() }.disabled(!(20...400).contains(kg))
            }

            if let maintenance {
                Section {
                    LabeledContent("Measured maintenance", value: "\(maintenance.calories.rounded().number) Cal/day")
                    Button("Update my targets from this") { estimating = true }
                } header: { Text("What your data says") } footer: {
                    Text("From \(maintenance.loggedDays) logged days and your weight trend over the last 4 weeks. It's most accurate when you log everything you eat.")
                }
            } else if points.count >= 2 {
                Section {
                    Text("Log your food on most days and weigh in over two weeks, and Leanr will estimate the calories that hold your weight steady.")
                        .font(.roboto(.subheadline)).foregroundStyle(.secondary)
                }
            }

            Section {
                if health.enabled {
                    Label("Weights from Apple Health are included, and weights you log here are saved to Health.", systemImage: "heart.fill")
                        .font(.roboto(.subheadline)).foregroundStyle(.secondary)
                } else if health.isAvailable {
                    Button { Task { _ = await health.connect() } } label: { Label("Connect Apple Health", systemImage: "heart") }
                }
            }

            if !store.data.weightLog.isEmpty {
                Section("History") {
                    ForEach(store.data.weightLog.sorted { $0.date > $1.date }) { entry in
                        HStack {
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                            if entry.healthID != nil { Image(systemName: "heart.fill").font(.caption).foregroundStyle(.pink).accessibilityLabel("From Apple Health") }
                            Spacer()
                            Text("\(entry.kg.kgText) kg").monospacedDigit()
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                store.change(undo: "Deleted \(entry.kg.kgText) kg weigh-in") { $0.weights?.removeAll { $0.id == entry.id } }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Weight")
        .onAppear { if goalKG == nil, let goal = store.data.weightGoal { goalKG = goal.kg } }
        .onAppear { if kg == 0 { kg = (store.data.weightLog.max { $0.date < $1.date }?.kg ?? 0).hundredth } }
        .task { await health.refresh() }
        .sheet(isPresented: $estimating) {
            NavigationStack {
                TargetCalculator { values in
                    if store.applyEstimatedTargets(values) { estimating = false; store.notice = "Targets updated" }
                }
            }
        }
    }

    // MARK: Goal

    private var goalStatus: WeightTrend.GoalStatus? {
        store.data.weightGoal.flatMap { WeightTrend.goalStatus($0, points: points) }
    }

    private func dateText(_ date: Date) -> String { date.formatted(.dateTime.day().month(.abbreviated).year()) }

    private func weeksText(until date: Date) -> String {
        let days = max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 0)
        if days < 14 { return days == 1 ? "1 day" : "\(days) days" }
        if days < 70 { return "\(Int((Double(days) / 7).rounded())) weeks" }
        return "\(Int((Double(days) / 30.4).rounded())) months"
    }

    @ViewBuilder private var goalSection: some View {
        let goal = store.data.weightGoal
        Section {
            OptionalNumberField(title: "Goal weight (kg)", value: $goalKG, places: 1)
            if let entered = goalKG, (20...400).contains(entered), entered.hundredth != goal?.kg {
                Button(goal == nil ? "Set goal" : "Update goal") { setGoal() }
            }
            if let goal, let status = goalStatus {
                LabeledContent("Now (trend)", value: "\(status.current.number) kg")
                switch status.direction {
                case .reached:
                    Label("You're at your goal weight", systemImage: "checkmark.seal.fill").foregroundStyle(.tint)
                case .lose, .gain:
                    LabeledContent("To go", value: "\(status.remaining.number) kg to \(status.direction == .lose ? "lose" : "gain")")
                    ProgressView(value: status.progress) {
                        Text("\(Int((status.progress * 100).rounded()))% of the way from \(goal.startKg.number) kg").font(.roboto(.caption))
                    }.tint(.accentColor)
                }
                projection(status)
            } else if goal != nil {
                Text("Log a weigh-in to see how far off you are.").foregroundStyle(.secondary)
            }
            if goal != nil {
                Button("Remove goal", role: .destructive) {
                    if store.change(undo: "Removed weight goal", { $0.weightGoal = nil }) { goalKG = nil }
                }
            }
        } header: { Text("Goal") } footer: {
            Text(goal == nil
                 ? "Set a goal weight to see how far off you are and when you could get there at your current pace."
                 : "Projections use your trend, not a single weigh-in, so they settle as you log more. They're an estimate, not a promise.")
        }
    }

    @ViewBuilder private func projection(_ status: WeightTrend.GoalStatus) -> some View {
        if status.direction != .reached {
            switch status.pace {
            case .towards:
                if let projected = status.projected, let weekly = status.weeklyChange {
                    LabeledContent("At your pace", value: dateText(projected))
                    Text("About \(weeksText(until: projected)) away, at \(signed(weekly)) kg a week.")
                        .font(.roboto(.caption)).foregroundStyle(.secondary)
                }
            case .away:
                Text("Your trend is moving the other way (\(signed(status.weeklyChange ?? 0)) kg a week), so there's no date yet.")
                    .font(.roboto(.caption)).foregroundStyle(.secondary)
            case .flat:
                Text("Your trend is steady, so there's no date at this pace.").font(.roboto(.caption)).foregroundStyle(.secondary)
            case .tooFar:
                Text("At this pace it's more than five years away.").font(.roboto(.caption)).foregroundStyle(.secondary)
            case .unknown:
                Text("A week or more of weigh-ins shows your pace and a date.").font(.roboto(.caption)).foregroundStyle(.secondary)
            }
            // What a chosen pace would mean, whatever the trend is doing now.
            Picker("If you aim for", selection: $pace) {
                ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { Text("\($0.kgText) kg/wk").tag($0) }
            }.pickerStyle(.segmented)
            if let date = WeightTrend.date(toCover: status.remaining, kgPerWeek: pace) {
                let calories = WeightTrend.dailyCalorieDifference(kgPerWeek: pace).rounded()
                LabeledContent("At \(pace.kgText) kg a week", value: dateText(date))
                Text("About \(weeksText(until: date)), \(calories.number) Cal a day \(status.direction == .lose ? "below" : "above") what holds your weight. Slower is easier to keep up.")
                    .font(.roboto(.caption)).foregroundStyle(.secondary)
            }
        }
    }

    private func setGoal() {
        guard let entered = goalKG, (20...400).contains(entered) else { return }
        let target = entered.hundredth
        let start = (points.last?.trend ?? store.data.weightLog.max { $0.date < $1.date }?.kg ?? target).hundredth
        let goal = WeightGoal(kg: target, startKg: (20...400).contains(start) ? start : target, set: Date())
        if store.change(undo: "Set goal weight to \(goal.kg.kgText) kg", { $0.weightGoal = goal }) { goalKG = goal.kg }
    }

    private var yDomain: ClosedRange<Double> {
        let values = shown.flatMap { [$0.kg, $0.trend] }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        return (low - 1).rounded(.down)...(high + 1).rounded(.up)
    }
    private func signed(_ value: Double) -> String { (value > 0 ? "+" : value < 0 ? "−" : "") + abs(value).number }
    private func save() {
        let entry = WeightEntry(date: date, kg: kg.hundredth)
        if store.change(undo: "Logged \(entry.kg.kgText) kg", { $0.weights = $0.weightLog + [entry] }) { date = Date() }
    }
}

/// Today's weight trend and activity, linking to the weight log.
struct BodySummary: View {
    @Environment(AppStore.self) private var store
    @Environment(HealthSync.self) private var health
    @Environment(Navigator.self) private var nav
    var body: some View {
        let points = WeightTrend.points(store.data.weightLog)
        Button { nav.tab = .progress } label: {
            HStack(spacing: 14) {
                Image(systemName: "scalemass.fill").font(.title2).foregroundStyle(.tint).frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    if let last = points.last {
                        Text("\(last.trend.number) kg").font(.roboto(.headline)).monospacedDigit()
                        if let weekly = WeightTrend.weeklyChange(points) {
                            Text("Trend \(weekly > 0 ? "+" : weekly < 0 ? "−" : "")\(abs(weekly).number) kg a week")
                                .font(.roboto(.caption)).foregroundStyle(.secondary)
                        } else {
                            Text("Weight trend").font(.roboto(.caption)).foregroundStyle(.secondary)
                        }
                        if let goal = store.data.weightGoal, let status = WeightTrend.goalStatus(goal, points: points) {
                            Text(status.direction == .reached ? "At your goal of \(goal.kg.kgText) kg"
                                 : "Goal \(goal.kg.kgText) kg · \(status.remaining.number) kg to go")
                                .font(.roboto(.caption)).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Log your weight").font(.roboto(.headline))
                        Text("See your trend and measured maintenance").font(.roboto(.caption)).foregroundStyle(.secondary)
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
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }.padding(.vertical, 4).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
