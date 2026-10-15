import SwiftUI
import WidgetKit

struct LeanrCaloriesBurntWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetCalories.burntKind, provider: CaloriesProvider()) { entry in
            CaloriesBurntWidgetView(entry: entry)
        }
        .configurationDisplayName("Calories burnt")
        .description("Today's active calories from Apple Health, against your recent days.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct CaloriesBurntWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CaloriesEntry

    private var burnt: Double? { entry.calories?.energyBurnt(on: entry.date) }
    private var average: Double? { entry.calories?.energyAverage(excluding: entry.date) }
    /// How today compares with the recent average, from 0 to 1.
    private var progress: Double {
        guard let burnt, let average, average > 0 else { return 0 }
        return min(1, burnt / average)
    }
    private func text(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) }
    private var valueText: String { burnt.map(text) ?? "—" }
    private var caption: String {
        if entry.calories == nil { return "Open Leanr to sync" }
        guard burnt != nil else { return "None recorded yet" }
        return average.map { "Average \(text($0)) Cal" } ?? "Active today"
    }

    /// The last seven days, oldest first, for the medium widget.
    private var week: [(day: Date, calories: Double)] {
        (0..<7).reversed().compactMap { offset in
            Calendar.current.date(byAdding: .day, value: -offset, to: entry.date).map { ($0, entry.calories?.energyBurnt(on: $0) ?? 0) }
        }
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Text(burnt == nil ? "Leanr · \(caption)" : "Leanr · \(valueText) Cal burnt")
            case .accessoryCircular:
                Gauge(value: progress) {
                    Image(systemName: "flame")
                } currentValueLabel: {
                    Text(valueText).font(.roboto(size: 12, weight: .bold)).minimumScaleFactor(0.5)
                }
                .gaugeStyle(.accessoryCircularCapacity)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 3) {
                    Label("Calories burnt", systemImage: "flame").font(.roboto(.caption, weight: .semibold))
                    Text(burnt == nil ? caption : "\(valueText) Cal").font(.roboto(.headline)).minimumScaleFactor(0.7).lineLimit(1)
                    ProgressView(value: progress)
                }
            case .systemMedium:
                HStack(spacing: 18) {
                    ring
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Last 7 days").font(.roboto(.caption)).foregroundStyle(.secondary)
                        let most = max(week.map(\.calories).max() ?? 0, 1)
                        HStack(alignment: .bottom, spacing: 6) {
                            ForEach(Array(week.enumerated()), id: \.offset) { _, item in
                                VStack(spacing: 4) {
                                    Capsule().fill(Color.orange.opacity(item.calories > 0 ? 0.85 : 0.2))
                                        .frame(height: max(4, 56 * item.calories / most))
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
        .accessibilityLabel(entry.calories == nil ? "Open Leanr to sync your calories burnt"
                            : burnt == nil ? "No active calories recorded yet today"
                            : "\(valueText) calories burnt today. \(caption)")
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Color.orange.opacity(0.2), lineWidth: 10)
            Circle().trim(from: 0, to: progress).stroke(Color.orange, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Image(systemName: "flame").font(.caption).foregroundStyle(.orange)
                Text(valueText).font(.roboto(.title3, weight: .bold)).minimumScaleFactor(0.5).lineLimit(1)
                Text("Cal burnt").font(.roboto(size: 10)).foregroundStyle(.secondary)
            }.padding(10)
        }
        .frame(maxWidth: 120, maxHeight: 120)
    }
}
