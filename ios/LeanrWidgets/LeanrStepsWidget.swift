import SwiftUI
import WidgetKit

struct LeanrStepsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetCalories.stepsKind, provider: CaloriesProvider()) { entry in
            StepsWidgetView(entry: entry)
        }
        .configurationDisplayName("Steps")
        .description("Today's steps from Apple Health against your goal.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct StepsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CaloriesEntry

    private var goal: Double { entry.calories?.stepGoal ?? 8000 }
    private var accent: Color { (entry.calories?.selectedAccent ?? .standard).color }
    private var count: Double? { entry.calories?.stepCount(on: entry.date) }
    private var progress: Double { goal > 0 ? min(1, (count ?? 0) / goal) : 0 }
    private func text(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) }
    private var valueText: String { count.map(text) ?? "—" }
    private var caption: String {
        if entry.calories == nil { return "Open Leanr to sync" }
        guard let count else { return "No steps yet today" }
        return count >= goal ? "Goal reached" : "\(text(goal - count)) to go"
    }

    /// The last seven days, oldest first, for the medium widget.
    private var week: [(day: Date, steps: Double)] {
        (0..<7).reversed().compactMap { offset in
            Calendar.current.date(byAdding: .day, value: -offset, to: entry.date).map { ($0, entry.calories?.stepCount(on: $0) ?? 0) }
        }
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Text(count == nil ? "Leanr · \(caption)" : "Leanr · \(valueText) steps")
            case .accessoryCircular:
                Gauge(value: progress) {
                    Image(systemName: "figure.walk")
                } currentValueLabel: {
                    Text(valueText).font(.roboto(size: 12, weight: .bold)).minimumScaleFactor(0.5)
                }
                .gaugeStyle(.accessoryCircularCapacity)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 3) {
                    Label("Steps", systemImage: "figure.walk").font(.roboto(.caption, weight: .semibold))
                    Text(count == nil ? caption : "\(valueText) of \(text(goal))").font(.roboto(.headline)).minimumScaleFactor(0.7).lineLimit(1)
                    ProgressView(value: progress)
                }
            case .systemMedium:
                HStack(spacing: 18) {
                    ring
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Last 7 days").font(.roboto(.caption)).foregroundStyle(.secondary)
                        HStack(alignment: .bottom, spacing: 6) {
                            ForEach(Array(week.enumerated()), id: \.offset) { _, item in
                                VStack(spacing: 4) {
                                    Capsule().fill(item.steps >= goal ? accent : accent.opacity(0.45))
                                        .frame(height: max(4, 56 * min(1, item.steps / max(goal, 1))))
                                    Text(item.day.formatted(.dateTime.weekday(.narrow))).font(.roboto(size: 10)).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity)
                            }
                        }.frame(height: 76, alignment: .bottom)
                    }
                }
            default:
                VStack(spacing: 6) {
                    ring
                    Text(caption).font(.roboto(.caption)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
        }
        .privacySensitive().widgetURL(URL(string: "leanr://progress"))
        .containerBackground(for: .widget) { Color(.systemBackground) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.calories == nil ? "Open Leanr to sync your steps"
                            : count == nil ? "No steps yet today. Goal \(text(goal))"
                            : "\(valueText) steps of \(text(goal)). \(caption)")
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(accent.opacity(0.2), lineWidth: 10)
            Circle().trim(from: 0, to: progress).stroke(accent, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Image(systemName: "figure.walk").font(.caption).foregroundStyle(accent)
                Text(valueText).font(.roboto(.title3, weight: .bold)).minimumScaleFactor(0.5).lineLimit(1)
                Text("of \(text(goal))").font(.roboto(size: 10)).foregroundStyle(.secondary)
            }.padding(10)
        }
        .frame(maxWidth: 120, maxHeight: 120)
    }
}
