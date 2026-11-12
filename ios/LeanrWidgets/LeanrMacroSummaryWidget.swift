import SwiftUI
import WidgetKit

/// Calories left as a big number with protein, carbs and fat underneath, laid out like a weather widget.
struct LeanrMacroSummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetCalories.macroSummaryKind, provider: TargetsProvider()) { entry in
            MacroSummaryWidgetView(entry: entry)
        }
        .configurationDisplayName("Macros at a glance")
        .description("Calories left, with protein, carbs and fat. Green when protein is reached, orange when carbs or fat go over.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MacroSummaryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CaloriesEntry
    private var accent: Color { (entry.calories?.selectedAccent ?? .standard).color }
    private var key: String { WidgetCalories.dayKey(entry.date) }
    private var choices: [String: String] { entry.calories?.macroColours ?? [:] }

    var body: some View {
        Group {
            if entry.calories == nil {
                Text("Open Leanrrr to sync your targets").font(.roboto(.subheadline))
            } else if entry.calories?.premiumUnlocked != true {
                Label("Open Leanrrr to unlock this widget", systemImage: "lock.fill").font(.roboto(.subheadline))
            } else if family == .systemMedium {
                HStack(alignment: .top, spacing: 18) {
                    header.frame(maxWidth: .infinity, alignment: .topLeading)
                    VStack(spacing: 10) {
                        row("p", name: "Protein", bar: true)
                        row("c", name: "Carbs", bar: true)
                        row("f", name: "Fat", bar: true)
                    }.frame(maxWidth: .infinity).frame(maxHeight: .infinity, alignment: .center)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Spacer(minLength: 6)
                    VStack(alignment: .leading, spacing: 3) {
                        row("p", name: "Protein", bar: false)
                        row("c", name: "Carbs", bar: false)
                        row("f", name: "Fat", bar: false)
                    }
                }
            }
        }
        .privacySensitive()
        .widgetURL(URL(string: "leanr://today"))
        .containerBackground(for: .widget) { Color(.secondarySystemBackground) }
    }

    /// Leaf and calories left on one line, then what the number means and how much has been eaten.
    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill").font(.roboto(size: 20, weight: .semibold))
                    .foregroundStyle(accent).widgetAccentable()
                Text(entry.value).font(.roboto(size: 32, weight: .bold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
            }
            Text(entry.remaining == nil ? "Set a calorie target" : ((entry.remaining ?? 0) < 0 ? "Cals over" : "Cals left"))
                .font(.roboto(size: 15, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
            Text("\(entry.eatenValue) of \(entry.targetValue) eaten")
                .font(.roboto(size: 12)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.remaining == nil ? "Set a calorie target in Leanrrr" : "\(entry.value) \(entry.caption). \(entry.eatenValue) of \(entry.targetValue) eaten.")
    }

    private func row(_ id: String, name: String, bar: Bool) -> some View {
        let value = entry.calories?.dailyNutrients?[key]?[id] ?? 0
        let target = entry.calories?.nutrientTargets?.first { $0.id == id }?.target
        let partial = entry.calories?.dailyPartialNutrients?[key]?.contains(id) == true
        let targetText = target.map { number($0) } ?? "—"
        let progress = target.map { min(1, max(0, value / $0)) } ?? 0
        // Green once the protein goal is met, orange once carbs or fat go past their target.
        let status = TargetStatus.of(id, value: value, target: target)
        let textColour = status.colour
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(bar ? name : String(name.prefix(1))).foregroundStyle(textColour ?? Color.secondary)
                Spacer(minLength: 0)
                Text("\(number(value))\(partial ? "+" : "")/\(targetText)g").monospacedDigit()
                    .foregroundStyle(textColour ?? Color.primary)
            }.font(.roboto(size: bar ? 12 : 13, weight: status == .none ? .medium : .bold)).lineLimit(1).minimumScaleFactor(0.65)
            if bar {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.16))
                        if progress > 0 {
                            Capsule().fill(MacroColours.colour(id, choices: choices))
                                .frame(width: max(2, geometry.size.width * progress)).widgetAccentable()
                        }
                    }
                }.frame(height: 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(number(value)) grams\(partial ? ", partial total" : ""). \(target == nil ? "No target set" : "Target \(targetText) grams.")\(status.spoken)")
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...1)))
    }
}
