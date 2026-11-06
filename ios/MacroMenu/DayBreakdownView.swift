import SwiftUI

/// Opened by tapping the targets on Today: the day's totals, each macro and micronutrient with the foods it came from,
/// and every food logged with its own figures.
struct DayBreakdownView: View {
    @Environment(AppStore.self) private var store
    let date: Date
    let goals: Goals

    private var entries: [LogEntry] { store.data.logs[dayKey(date)] ?? [] }

    var body: some View {
        let day = DayBreakdown(entries: entries, goals: goals)
        LeanrList {
            Section {
                Text(date.formatted(date: .complete, time: .omitted)).font(.roboto(.subheadline)).foregroundStyle(.secondary)
                NutritionView(total: day.total, details: false)
                if let cal = goals.values["cal"] {
                    LabeledContent("Calorie target", value: "\(cal.number) Cal")
                    LabeledContent(day.total.cal > cal ? "Over by" : "Left", value: "\(abs(cal - day.total.cal).number) Cal")
                        .foregroundStyle(day.total.cal > cal ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
                }
                LabeledContent("Energy", value: "\(day.total.kj.number) kJ")
            }
            .font(.roboto(.body))

            if day.lines.isEmpty {
                Section {
                    Text("Nothing logged on this day yet.").foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(day.macros) { macro in macroRow(macro) }
                } header: { Text("Macros") } footer: {
                    Text("Share is each macro's part of the energy from protein, carbs and fat. Open one to see where it came from.")
                }

                Section {
                    if day.nutrients.isEmpty {
                        Text("None of the food logged on this day lists micronutrients. Restaurant items usually list sodium, sugars and saturated fat, and foods you add yourself can list more.")
                            .font(.roboto(.subheadline)).foregroundStyle(.secondary)
                    }
                    ForEach(day.nutrients) { nutrient in nutrientRow(nutrient, day: day) }
                } header: { Text("Micronutrients") } footer: {
                    if !day.unlisted.isEmpty {
                        Text("No food logged on this day lists \(ListFormatter.localizedString(byJoining: day.unlisted.map { $0.lowercased() })), so \(day.unlisted.count == 1 ? "it isn't" : "they aren't") shown.")
                    }
                }

                ForEach(groups(day.lines), id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.lines) { line in foodRow(line) }
                    }
                }
            }
        }
        .navigationTitle("Breakdown")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Rows

    private func macroRow(_ macro: DayBreakdown.Macro) -> some View {
        DisclosureGroup {
            sourceList(macro.sources, unit: "g")
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Circle().fill(nutrientStyle(macro.key)).frame(width: 9, height: 9)
                    Text(macro.label).font(.roboto(.headline))
                    Spacer()
                    Text("\(macro.grams.number)\(macro.partial ? "+" : "") g").font(.roboto(.headline)).monospacedDigit()
                }
                HStack {
                    Text("\(Int((macro.share * 100).rounded()))% of energy")
                    Spacer()
                    if let progress = DayBreakdown.progress(macro.grams, target: macro.target, minimum: macro.minimum, unit: "g") {
                        Text(progress).foregroundStyle(isOver(macro.grams, macro.target, macro.minimum) ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    }
                }
                .font(.roboto(.caption)).foregroundStyle(.secondary).monospacedDigit()
                if let target = macro.target, target > 0 { bar(macro.grams, target: target, style: nutrientStyle(macro.key), over: isOver(macro.grams, target, macro.minimum)) }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func nutrientRow(_ nutrient: DayBreakdown.Nutrient, day: DayBreakdown) -> some View {
        DisclosureGroup {
            sourceList(nutrient.sources, unit: nutrient.unit)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(nutrient.label).font(.roboto(.subheadline, weight: .medium))
                    Spacer()
                    Text("\(nutrient.value.number)\(day.isPartial(nutrient) ? "+" : "") \(nutrient.unit)").font(.roboto(.subheadline, weight: .medium)).monospacedDigit()
                }
                let progress = DayBreakdown.progress(nutrient.value, target: nutrient.target, minimum: nutrient.minimum, unit: nutrient.unit)
                if progress != nil || day.isPartial(nutrient) {
                    HStack {
                        if day.isPartial(nutrient) { Text("Listed by \(nutrient.listedBy) of \(day.foodCount) foods") }
                        Spacer()
                        if let progress {
                            Text(progress).foregroundStyle(isOver(nutrient.value, nutrient.target, nutrient.minimum) ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                        }
                    }
                    .font(.roboto(.caption)).foregroundStyle(.secondary).monospacedDigit()
                }
                if let target = nutrient.target, target > 0 { bar(nutrient.value, target: target, style: AnyShapeStyle(.tint), over: isOver(nutrient.value, target, nutrient.minimum)) }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func foodRow(_ line: DayBreakdown.Line) -> some View {
        let n = line.nutrition
        return DisclosureGroup {
            LabeledContent("Energy", value: "\(n.kj.number) kJ")
            ForEach(nutrientNames.dropFirst(4), id: \.key) { name in
                if let value = n.nut[name.key] { LabeledContent(name.label, value: "\(value.number) \(name.unit)") }
            }
            ForEach(n.nut.keys.filter { key in !nutrientNames.contains { $0.key == key } }.sorted(), id: \.self) { key in
                LabeledContent(key.capitalized, value: (n.nut[key] ?? 0).number)
            }
            if n.nut.isEmpty {
                Text("No micronutrients listed for this food.").foregroundStyle(.secondary)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(line.name).font(.roboto(.headline)).lineLimit(2)
                    Spacer()
                    Text("\(n.cal.number) Cal").font(.roboto(.subheadline, weight: .medium)).monospacedDigit()
                }
                Text(line.amount).font(.roboto(.caption)).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    macroFigure("P", n.p, partial: false, key: "p")
                    macroFigure("C", n.c, partial: n.missingCarbs, key: "c")
                    macroFigure("F", n.f, partial: n.missingFat, key: "f")
                }
                .font(.roboto(.caption, weight: .medium))
            }
            .accessibilityElement(children: .combine)
        }
        .font(.roboto(.subheadline))
    }

    // MARK: Pieces

    private func macroFigure(_ letter: String, _ grams: Double, partial: Bool, key: String) -> some View {
        Text(partial && grams == 0 ? "\(letter) –" : "\(letter) \(grams.number) g")
            .foregroundStyle(nutrientStyle(key)).monospacedDigit()
            .accessibilityLabel(partial && grams == 0 ? "\(nutrientNames.first { $0.key == key }!.label) not listed" : "\(grams.number) grams \(nutrientNames.first { $0.key == key }!.label.lowercased())")
    }

    @ViewBuilder private func sourceList(_ sources: [DayBreakdown.Source], unit: String) -> some View {
        if sources.isEmpty {
            Text("Nothing logged on this day lists it.").font(.roboto(.subheadline)).foregroundStyle(.secondary)
        }
        let total = sources.reduce(0) { $0 + $1.value }
        ForEach(sources) { source in
            HStack(alignment: .firstTextBaseline) {
                Text(source.name).font(.roboto(.subheadline)).lineLimit(2)
                Spacer()
                Text("\(source.value.number) \(unit)").font(.roboto(.subheadline, weight: .medium)).monospacedDigit()
                if total > 0 {
                    Text("\(Int((source.value / total * 100).rounded()))%").font(.roboto(.caption)).foregroundStyle(.secondary)
                        .monospacedDigit().frame(minWidth: 36, alignment: .trailing)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func bar(_ value: Double, target: Double, style: AnyShapeStyle, over: Bool) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(over ? AnyShapeStyle(.orange) : style).frame(width: geo.size.width * min(max(value / target, 0), 1))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }

    private func isOver(_ value: Double, _ target: Double?, _ minimum: Bool) -> Bool {
        guard let target, !minimum else { return false }
        return value > target
    }

    /// The day's food under its meal times, in the usual order, with anything unassigned last.
    private func groups(_ lines: [DayBreakdown.Line]) -> [(title: String, lines: [DayBreakdown.Line])] {
        var result = MealTime.allCases.compactMap { time -> (title: String, lines: [DayBreakdown.Line])? in
            let matching = lines.filter { $0.mealTime == time }
            return matching.isEmpty ? nil : (time.title, matching)
        }
        let unassigned = lines.filter { $0.mealTime == nil }
        if !unassigned.isEmpty { result.append(("Unassigned", unassigned)) }
        return result
    }
}
