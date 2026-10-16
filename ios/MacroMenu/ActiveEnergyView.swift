import SwiftUI
import Charts

/// Calories burnt on the day being looked at on Today, from Apple Health. Read-only, and shown once Health is connected.
struct ActiveEnergyRow: View {
    @Environment(HealthSync.self) private var health
    /// The day being looked at on Today.
    let date: Date

    private var count: Double { health.activeEnergy[dayKey(date)] ?? 0 }

    var body: some View {
        if health.isAvailable && health.enabled {
            HStack(spacing: 14) {
                Image(systemName: "flame").font(.title2).foregroundStyle(.orange).frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Calories burnt").font(.roboto(.headline))
                    Text(detail).font(.roboto(.caption)).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .task { await health.refreshActiveEnergy() }
            if health.energyLoaded && health.activeEnergy.isEmpty { EnergyAccessButton() }
        }
    }

    private var detail: String {
        if health.activeEnergy.isEmpty { return health.energyLoaded ? "No active calories found in Health yet" : "Loading…" }
        guard count > 0 else { return "None recorded" + (health.energySourceName.map { " · \($0)" } ?? "") }
        return "\(ActiveEnergy.text(count)) Cal active" + (health.energySourceName.map { " · \($0)" } ?? "")
    }
}

/// Allows reading calories burnt when Health was connected before they existed, or points to where to change an earlier answer.
struct EnergyAccessButton: View {
    @Environment(HealthSync.self) private var health
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { Task { await health.requestEnergyAccess() } } label: { Label("Allow Leanr to read calories burnt", systemImage: "flame") }
            Text("If you've already answered, change it in the Health app → your profile → Apps → Leanr.")
                .font(.roboto(.caption)).foregroundStyle(.secondary)
        }
    }
}

/// Where calories burnt come from: all sources together, or one app or device.
struct ActiveEnergySettings: View {
    @Environment(HealthSync.self) private var health

    var body: some View {
        LeanrList {
            if health.isAvailable && health.enabled {
                if health.energyLoaded && health.activeEnergy.isEmpty { Section { EnergyAccessButton() } }
                Section {
                    Picker("Show calories burnt from", selection: Binding(get: { health.energySourceID }, set: { id in Task { await health.chooseEnergySource(id) } })) {
                        Text("All sources together").tag(String?.none)
                        ForEach(health.energySources) { source in
                            Text(source.name).tag(Optional(source.id))
                        }
                    }.pickerStyle(.inline).labelsHidden()
                } header: { Text("Source") } footer: {
                    Text("Apple Health combines your watch, iPhone and other sources without counting a workout twice. If one source is more accurate for you, such as an Apple Watch, choose it to show only its calories. If you pick one and it records nothing on a day, that day shows nothing.")
                }
                if !health.energySources.isEmpty {
                    Section {
                        ForEach(health.energySources) { source in
                            LabeledContent(source.name, value: health.energySourceTotals[source.id].map { "\(ActiveEnergy.text($0)) Cal today" } ?? "–")
                        }
                    } header: { Text("Calories burnt today by source") } footer: {
                        Text("Compare these to see which source has been counting best.")
                    }
                }
            } else {
                Section {
                    Button { Task { _ = await health.connect() } } label: { Label("Connect Apple Health", systemImage: "heart") }
                        .disabled(!health.isAvailable)
                } footer: { Text("Calories burnt come from Apple Health. Leanr only reads them and doesn't copy them to iCloud.") }
            }
            Section {
                Text("These are active calories, the energy you burn moving around and exercising. They don't include the calories your body uses at rest.")
                    .font(.roboto(.subheadline)).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Calories burnt")
        .task { await health.loadEnergySources() }
    }
}

/// Calories burnt over the Progress tab's range: a bar per day with the average, and a tap or drag on the graph to read any day.
struct ActiveEnergyProgressSection: View {
    @Environment(HealthSync.self) private var health
    /// The days in the range, by day key.
    let days: [String: Date]
    @State private var selected: Date?

    var body: some View {
        if health.isAvailable && health.enabled {
            let keys = days.keys.sorted()
            let summary = ActiveEnergy.summary(health.activeEnergy, days: keys)
            let today = health.activeEnergyToday
            Section {
                if let average = summary.average {
                    HStack(alignment: .top, spacing: 12) {
                        figure("Today", today.map(ActiveEnergy.text) ?? "–")
                        figure("Average", ActiveEnergy.text(average))
                        figure("Best", summary.best.map(ActiveEnergy.text) ?? "–")
                        figure("Total", ActiveEnergy.text(summary.total))
                    }
                    graph(keys: keys, average: average)
                    if let selected, let calories = energy(on: selected) {
                        Text("\(selected.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))): \(ActiveEnergy.text(calories)) Cal burnt")
                            .font(.roboto(.subheadline, weight: .medium)).monospacedDigit()
                    }
                } else {
                    Label("No active calories found in Health for these days", systemImage: "flame").foregroundStyle(.secondary)
                }
            } header: { Text("Calories burnt") } footer: {
                Text("Active calories from \(health.energySourceName.map { "\($0), through Apple Health" } ?? "Apple Health"). Days with none recorded aren't counted in the average, shown as the solid line. Change the source in Settings → Targets → Calories burnt.")
            }
            .task { await health.refreshActiveEnergy() }
        }
    }

    private func energy(on date: Date) -> Double? {
        health.activeEnergy[dayKey(date)].flatMap { $0 > 0 ? $0 : nil }
    }

    private func figure(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.roboto(.caption)).foregroundStyle(.secondary)
            Text(value).font(.roboto(.headline, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func graph(keys: [String], average: Double) -> some View {
        Chart {
            ForEach(keys, id: \.self) { key in
                if let date = days[key], let calories = health.activeEnergy[key], calories > 0 {
                    BarMark(x: .value("Day", date, unit: .day), y: .value("Calories burnt", calories))
                        .foregroundStyle(.orange)
                        .opacity(selected == nil || dayKey(selected!) == key ? 1 : 0.5)
                }
            }
            RuleMark(y: .value("Average", average)).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartXSelection(value: $selected)
        .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine(); AxisValueLabel() } }
        .frame(height: 190)
        .accessibilityLabel("Calories burnt per day, average \(ActiveEnergy.text(average))")
    }
}
