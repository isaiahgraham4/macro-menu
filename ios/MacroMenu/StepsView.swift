import SwiftUI
import Charts

/// Today's steps from Apple Health against the goal. Read-only: the count comes from the iPhone, a watch or any other source.
struct StepsRow: View {
    @Environment(AppStore.self) private var store
    @Environment(HealthSync.self) private var health
    /// The day being looked at on Today.
    let date: Date

    private var count: Double { health.steps[dayKey(date)] ?? 0 }
    private var goal: Double { Steps.goal(store.data) }

    var body: some View {
        if health.isAvailable {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    Image(systemName: "figure.walk").font(.title2).foregroundStyle(.green).frame(width: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Steps").font(.roboto(.headline))
                        Text(detail).font(.roboto(.caption)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Spacer(minLength: 0)
                }
                if health.enabled && !health.steps.isEmpty {
                    ProgressView(value: Steps.progress(count, goal: goal)).tint(.green)
                        .accessibilityLabel("Steps").accessibilityValue("\(Steps.text(count)) of \(Steps.text(goal))")
                } else {
                    StepsAccessButton()
                }
            }
            .padding(.vertical, 4)
            .task { await health.refreshSteps() }
        }
    }

    private var detail: String {
        if !health.enabled { return "Connect Apple Health to see your steps" }
        if health.steps.isEmpty { return health.stepsLoaded ? "No steps found in Health yet" : "Loading…" }
        return "\(Steps.text(count)) of \(Steps.text(goal))" + (health.stepSourceName.map { " · \($0)" } ?? "")
    }
}

/// The one button that gets steps flowing: connect Health, or allow reading steps if Health was connected before steps existed.
struct StepsAccessButton: View {
    @Environment(HealthSync.self) private var health
    var body: some View {
        if !health.enabled {
            Button { Task { _ = await health.connect() } } label: { Label("Connect Apple Health", systemImage: "heart") }
        } else if health.stepsLoaded && health.steps.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button { Task { await health.requestStepAccess() } } label: { Label("Allow Leanr to read steps", systemImage: "figure.walk") }
                Text("If you've already answered, change it in the Health app → your profile → Apps → Leanr.")
                    .font(.roboto(.caption)).foregroundStyle(.secondary)
            }
        }
    }
}

/// The daily step goal.
struct StepsSettings: View {
    @Environment(AppStore.self) private var store
    @Environment(HealthSync.self) private var health
    @State private var goal = Steps.defaultGoal
    @State private var loaded = false

    private var valid: Bool { Steps.goalRange.contains(goal) }
    private var changed: Bool { goal != Steps.goal(store.data) }

    var body: some View {
        LeanrList {
            Section {
                NumberField(title: "Daily goal (steps)", value: $goal, places: 0)
                if changed { Button("Save") { if store.setStepGoal(goal.rounded()) { store.notice = "Step goal saved" } }.disabled(!valid) }
            } footer: {
                Text("Steps come from Apple Health. Leanr only reads them and doesn't copy them to iCloud.")
            }
            if health.isAvailable && health.enabled {
                Section {
                    Picker("Show steps from", selection: Binding(get: { health.stepSourceID }, set: { id in Task { await health.chooseStepSource(id) } })) {
                        Text("All sources together").tag(String?.none)
                        ForEach(health.stepSources) { source in
                            Text(source.name).tag(Optional(source.id))
                        }
                    }.pickerStyle(.inline).labelsHidden()
                } header: { Text("Source") } footer: {
                    Text("Apple Health combines your iPhone, watch and other sources without counting a walk twice. If one source is more accurate for you, such as a Fitbit through Google Health, choose it to show only its steps. If you pick one and it records nothing on a day, that day shows nothing.")
                }
                if !health.stepSources.isEmpty {
                    Section {
                        ForEach(health.stepSources) { source in
                            LabeledContent(source.name, value: health.stepSourceTotals[source.id].map { "\(Steps.text($0)) today" } ?? "–")
                        }
                    } header: { Text("Steps today by source") } footer: {
                        Text("Compare these to see which source has been counting best.")
                    }
                }
            }
            if !valid { Section { Text("Use a goal from 1,000 to 100,000 steps.").foregroundStyle(.secondary) } }
        }
        .navigationTitle("Steps")
        .task { await health.loadStepSources() }
        .onAppear {
            guard !loaded else { return }
            loaded = true; goal = Steps.goal(store.data)
        }
    }
}

/// Steps over the Progress tab's range: a bar per day against the goal, with the average, how often you reached the goal,
/// and a tap or drag on the graph to read any day.
struct StepsProgressSection: View {
    @Environment(AppStore.self) private var store
    @Environment(HealthSync.self) private var health
    /// The days in the range, by day key.
    let days: [String: Date]
    @State private var selected: Date?

    var body: some View {
        if health.isAvailable {
            let goal = Steps.goal(store.data)
            let keys = days.keys.sorted()
            let summary = Steps.summary(health.steps, days: keys, goal: goal)
            let today = health.steps[dayKey(Date())]
            Section {
                if let average = summary.average {
                    HStack(alignment: .top, spacing: 12) {
                        figure("Today", today.map(Steps.text) ?? "–")
                        figure("Average", Steps.text(average))
                        figure("Best", summary.best.map(Steps.text) ?? "–")
                        figure("At goal", "\(summary.daysMet) of \(summary.countedDays)")
                    }
                    graph(keys: keys, goal: goal, average: average)
                    if let selected, let steps = steps(on: selected) {
                        Text("\(selected.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))): \(Steps.text(steps)) steps")
                            .font(.roboto(.subheadline, weight: .medium)).monospacedDigit()
                    }
                } else {
                    Label(health.enabled ? "No steps found in Health for these days" : "Connect Apple Health to see your steps",
                          systemImage: "figure.walk").foregroundStyle(.secondary)
                    StepsAccessButton()
                }
            } header: { Text("Steps") } footer: {
                Text("From \(health.stepSourceName.map { "\($0), through Apple Health" } ?? "Apple Health"). Days with no steps recorded aren't counted in the average. The dashed line is your goal of \(Steps.text(goal)) and the solid line is your average. Change the goal or source in Settings → Targets → Steps.")
            }
            .task { await health.refreshSteps() }
        }
    }

    private func steps(on date: Date) -> Double? {
        health.steps[dayKey(date)].flatMap { $0 > 0 ? $0 : nil }
    }

    private func figure(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.roboto(.caption)).foregroundStyle(.secondary)
            Text(value).font(.roboto(.headline, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func graph(keys: [String], goal: Double, average: Double) -> some View {
        Chart {
            ForEach(keys, id: \.self) { key in
                if let date = days[key], let steps = health.steps[key], steps > 0 {
                    BarMark(x: .value("Day", date, unit: .day), y: .value("Steps", steps))
                        .foregroundStyle(steps >= goal ? AnyShapeStyle(.green) : AnyShapeStyle(.green.opacity(0.45)))
                        .opacity(selected == nil || dayKey(selected!) == key ? 1 : 0.5)
                }
            }
            RuleMark(y: .value("Goal", goal)).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("Goal \(Steps.text(goal))").font(.roboto(size: 10)).foregroundStyle(.secondary)
                }
            RuleMark(y: .value("Average", average)).foregroundStyle(.green).lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartXSelection(value: $selected)
        .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine(); AxisValueLabel() } }
        .frame(height: 190)
        .accessibilityLabel("Steps per day, average \(Steps.text(average)), goal \(Steps.text(goal))")
    }
}
