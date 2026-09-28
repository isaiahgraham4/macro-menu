import SwiftUI
import WidgetKit

@main
struct LeanrWidgetBundle: WidgetBundle {
    var body: some Widget {
        LeanrCaloriesWidget()
        LeanrTargetsWidget()
        LeanrMacrosWidget()
        LeanrStreakWidget()
    }
}

struct LeanrTargetsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetCalories.premiumKind, provider: TargetsProvider()) { entry in
            TargetsWidgetView(entry: entry)
        }
        .configurationDisplayName("All targets")
        .description("Calories and all the nutrient targets you track, together in one place.")
        .supportedFamilies([.systemLarge])
    }
}

struct TargetsProvider: TimelineProvider {
    static var example: CaloriesEntry {
        let date = Date()
        let key = WidgetCalories.dayKey(date)
        var snapshot = WidgetCalories(target: 2200, dailyCalories: [key: 1350])
        snapshot.premiumUnlocked = true
        snapshot.nutrientTargets = [
            WidgetNutrientTarget(id: "p", name: "Protein", unit: "g", target: 150, minimum: true),
            WidgetNutrientTarget(id: "c", name: "Carbs", unit: "g", target: 250, minimum: false),
            WidgetNutrientTarget(id: "f", name: "Fat", unit: "g", target: 70, minimum: false),
            WidgetNutrientTarget(id: "fibre", name: "Fibre", unit: "g", target: 30, minimum: true)
        ]
        snapshot.dailyNutrients = [key: ["p": 95, "c": 130, "f": 50, "fibre": 18]]
        return CaloriesEntry(date: date, calories: snapshot)
    }
    func placeholder(in context: Context) -> CaloriesEntry { Self.example }
    func getSnapshot(in context: Context, completion: @escaping (CaloriesEntry) -> Void) {
        completion(context.isPreview ? Self.example : CaloriesEntry(date: Date(), calories: WidgetCalories.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CaloriesEntry>) -> Void) {
        CaloriesProvider().getTimeline(in: context, completion: completion)
    }
}

struct TargetsWidgetView: View {
    let entry: CaloriesEntry
    private var accent: Color { (entry.calories?.selectedAccent ?? .standard).color }
    private var targets: [WidgetNutrientTarget] { entry.calories?.nutrientTargets ?? [] }
    private var key: String { WidgetCalories.dayKey(entry.date) }
    private var partial: [String] { entry.calories?.dailyPartialNutrients?[key] ?? [] }

    var body: some View {
        Group {
            if let snapshot = entry.calories {
                if snapshot.premiumUnlocked == true {
                    dashboard
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "lock.fill").font(.title).foregroundStyle(accent)
                        Text("All targets").font(.title2.bold())
                        Text("Open Leanr to unlock this widget.").font(.subheadline).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 10) {
                    Label("Leanr", systemImage: "leaf.fill").font(.headline)
                    Text("Open Leanr to sync your targets").multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .privacySensitive()
        .widgetURL(URL(string: "leanr://today"))
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Leanr", systemImage: "leaf.fill").font(.headline).foregroundStyle(accent)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(entry.eatenValue).font(.system(size: 30, weight: .bold, design: .rounded))
                Text("/ \(entry.targetValue) cals").font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }.lineLimit(1).minimumScaleFactor(0.6)
            ProgressView(value: entry.progress).tint(accent)
                .accessibilityLabel("Calories: \(entry.eatenValue) of \(entry.targetValue)")
            if targets.isEmpty {
                Text("Add nutrient targets in Leanr to see them here.").font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                GeometryReader { geometry in
                    let rows = (targets.count + 1) / 2
                    let spacing: CGFloat = targets.count > 8 ? 4 : 10
                    let height = max(22, (geometry.size.height - CGFloat(max(0, rows - 1)) * spacing) / CGFloat(rows))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: spacing) {
                        ForEach(targets) { target in
                            nutrientRow(target, compact: targets.count > 8)
                                .frame(height: height)
                        }
                    }
                }
            }
            Text(partial.isEmpty ? "Today · Your active targets" : "+ Partial totals: some food data is missing")
                .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func nutrientRow(_ target: WidgetNutrientTarget, compact: Bool) -> some View {
        let value = entry.calories?.dailyNutrients?[key]?[target.id] ?? 0
        let incomplete = partial.contains(target.id)
        return VStack(alignment: .leading, spacing: compact ? 1 : 4) {
            if compact {
                HStack(spacing: 3) {
                    Text(target.name).font(.system(size: 9, weight: .semibold))
                    Spacer(minLength: 0)
                    Text("\(number(value))\(incomplete ? "+" : "")/\(number(target.target)) \(target.unit)")
                        .font(.system(size: 8)).monospacedDigit().foregroundStyle(.secondary)
                }.lineLimit(1).minimumScaleFactor(0.6)
            } else {
            Text(target.name).font(.system(size: compact ? 10 : 12, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.75)
            Text("\(number(value))\(incomplete ? "+" : "") / \(target.minimum ? "≥" : "≤")\(number(target.target)) \(target.unit)")
                .font(.system(size: compact ? 9 : 11)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6).foregroundStyle(.secondary)
            }
            ProgressView(value: min(1, max(0, value / target.target)))
                .tint(["p", "c", "f"].contains(target.id) ? MacroColours.colour(target.id, choices: entry.calories?.macroColours ?? [:]) : accent)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(target.name): \(number(value)) \(target.unit)\(incomplete ? ", partial total" : ""). Target \(target.minimum ? "at least" : "at most") \(number(target.target)) \(target.unit).")
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...1)))
    }
}
