import SwiftUI
import Charts

struct WeightView: View {
    @Environment(AppStore.self) private var store
    @Environment(HealthSync.self) private var health
    @State private var kg = 0.0
    @State private var date = Date()
    @State private var range = 90
    @State private var estimating = false
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

            Section("Log weight") {
                NumberField(title: "Weight (kg)", value: $kg)
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
                            Text("\(entry.kg.number) kg").monospacedDigit()
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                store.change(undo: "Deleted \(entry.kg.number) kg weigh-in") { $0.weights?.removeAll { $0.id == entry.id } }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Weight")
        .onAppear { if kg == 0 { kg = store.data.weightLog.max { $0.date < $1.date }?.kg ?? 0 } }
        .task { await health.refresh() }
        .sheet(isPresented: $estimating) {
            NavigationStack {
                TargetCalculator { values in
                    if store.applyEstimatedTargets(values) { estimating = false; store.notice = "Targets updated" }
                }
            }
        }
    }

    private var yDomain: ClosedRange<Double> {
        let values = shown.flatMap { [$0.kg, $0.trend] }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        return (low - 1).rounded(.down)...(high + 1).rounded(.up)
    }
    private func signed(_ value: Double) -> String { (value > 0 ? "+" : value < 0 ? "−" : "") + abs(value).number }
    private func save() {
        let entry = WeightEntry(date: date, kg: kg.tenth)
        if store.change(undo: "Logged \(entry.kg.number) kg", { $0.weights = $0.weightLog + [entry] }) { date = Date() }
    }
}

/// Today's weight trend and activity, linking to the weight log.
struct BodySummary: View {
    @Environment(AppStore.self) private var store
    @Environment(HealthSync.self) private var health
    var body: some View {
        let points = WeightTrend.points(store.data.weightLog)
        NavigationLink { WeightView() } label: {
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
            }.padding(.vertical, 4)
        }
    }
}
