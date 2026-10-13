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
        return "\(Steps.text(count)) of \(Steps.text(goal))"
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
                Text("Steps come from Apple Health, so they include your iPhone, a watch and any other source you've allowed. Leanr only reads them and doesn't copy them to iCloud.")
            }
            if !valid { Section { Text("Use a goal from 1,000 to 100,000 steps.").foregroundStyle(.secondary) } }
        }
        .navigationTitle("Steps goal")
        .onAppear {
            guard !loaded else { return }
            loaded = true; goal = Steps.goal(store.data)
        }
    }
}

/// Steps over the Progress tab's range: a bar per day against the goal, with the average and how often you reached it.
struct StepsProgressSection: View {
    @Environment(AppStore.self) private var store
    @Environment(HealthSync.self) private var health
    let days: [String: Date]

    var body: some View {
        if health.isAvailable {
            let goal = Steps.goal(store.data)
            let keys = days.keys.sorted()
            let summary = Steps.summary(health.steps, days: keys, goal: goal)
            Section {
                if let average = summary.average {
                    Chart {
                        ForEach(keys, id: \.self) { key in
                            if let date = days[key], let steps = health.steps[key], steps > 0 {
                                BarMark(x: .value("Day", date, unit: .day), y: .value("Steps", steps))
                                    .foregroundStyle(steps >= goal ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
                            }
                        }
                        RuleMark(y: .value("Goal", goal)).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                    .frame(height: 150)
                    .accessibilityLabel("Steps per day, average \(Steps.text(average))")
                    LabeledContent("Average", value: "\(Steps.text(average)) steps · \(summary.countedDays) days")
                    LabeledContent("Days at goal", value: "\(summary.daysMet) of \(summary.countedDays)")
                    if let best = summary.best { LabeledContent("Best day", value: "\(Steps.text(best)) steps") }
                } else {
                    Label(health.enabled ? "No steps found in Health for these days" : "Connect Apple Health to see your steps",
                          systemImage: "figure.walk").foregroundStyle(.secondary)
                    StepsAccessButton()
                }
            } header: { Text("Steps") } footer: {
                Text("From Apple Health. Days with no steps recorded aren't counted in the average. The goal is \(Steps.text(goal)); change it in Settings.")
            }
            .task { await health.refreshSteps() }
        }
    }
}
