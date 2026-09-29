import SwiftUI
import WidgetKit

struct LeanrMacrosWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetCalories.macrosKind, provider: TargetsProvider()) { entry in
            MacrosWidgetView(entry: entry)
        }
        .configurationDisplayName("Calories & macros")
        .description("Calories remaining with protein, carbs and fat against your targets.")
        .supportedFamilies([.systemMedium])
    }
}

struct MacrosWidgetView: View {
    let entry: CaloriesEntry
    private var accent: Color { (entry.calories?.selectedAccent ?? .standard).color }
    private var key: String { WidgetCalories.dayKey(entry.date) }

    var body: some View {
        Group {
            if entry.calories == nil {
                Text("Open Leanr to sync your targets").font(.roboto(.subheadline))
            } else if entry.calories?.premiumUnlocked != true {
                Label("Open Leanr to unlock this widget", systemImage: "lock.fill").font(.roboto(.subheadline))
            } else {
                GeometryReader { geometry in
                    let diameter = min(geometry.size.height, geometry.size.width * 0.37)
                    HStack(spacing: 16) {
                        calorieRing.frame(width: diameter, height: diameter)
                        VStack(spacing: 12) {
                            macro("p", name: "Protein", colour: MacroColours.colour("p", choices: entry.calories?.macroColours ?? [:]))
                            macro("c", name: "Carbs", colour: MacroColours.colour("c", choices: entry.calories?.macroColours ?? [:]))
                            macro("f", name: "Fat", colour: MacroColours.colour("f", choices: entry.calories?.macroColours ?? [:]))
                        }.frame(maxWidth: .infinity)
                    }.frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
        .privacySensitive()
        .widgetURL(URL(string: "leanr://today"))
        .containerBackground(for: .widget) { Color(.secondarySystemBackground) }
    }

    private var calorieRing: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.16), lineWidth: 10)
            if entry.progress > 0 {
                Circle().trim(from: 0, to: entry.progress)
                    .stroke(accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90)).widgetAccentable()
            }
            VStack(spacing: 2) {
                Text(entry.value).font(.roboto(size: 27, weight: .bold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
                Image(systemName: "leaf.fill")
                    .font(.roboto(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
                    .widgetAccentable()
                Text(entry.remaining == nil ? "Set target" : ((entry.remaining ?? 0) < 0 ? "Cals over" : "Cals left"))
                    .font(.roboto(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }.padding(14)
        }.padding(5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.remaining == nil ? "Set a calorie target in Leanr" : "\(entry.value) \(entry.caption)")
    }

    private func macro(_ id: String, name: String, colour: Color) -> some View {
        let value = entry.calories?.dailyNutrients?[key]?[id] ?? 0
        let target = entry.calories?.nutrientTargets?.first { $0.id == id }?.target
        let partial = entry.calories?.dailyPartialNutrients?[key]?.contains(id) == true
        let targetText = target.map { number($0) } ?? "—"
        let progress = target.map { min(1, max(0, value / $0)) } ?? 0
        return VStack(spacing: 5) {
            HStack(spacing: 4) {
                Text(name).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(number(value))\(partial ? "+" : "") / \(targetText) g").monospacedDigit()
            }.font(.roboto(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.65)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.16))
                    if progress > 0 {
                        Capsule().fill(colour).frame(width: max(2, geometry.size.width * progress))
                            .widgetAccentable()
                    }
                }
            }.frame(height: 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(number(value)) grams\(partial ? ", partial total" : ""). \(target == nil ? "No target set" : "Target \(targetText) grams")")
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...1)))
    }
}
