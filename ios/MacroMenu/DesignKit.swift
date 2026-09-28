import SwiftUI

// Small building blocks that give the list screens some structure: summary rings and bars,
// filter chips, side-by-side number tiles and action tiles.

/// Colour for a nutrient: macros keep their own colours, everything else uses the app colour.
func nutrientStyle(_ key: String) -> AnyShapeStyle {
    switch key {
    case "p": AnyShapeStyle(.blue)
    case "c": AnyShapeStyle(.orange)
    case "f": AnyShapeStyle(.red)
    default: AnyShapeStyle(.tint)
    }
}

/// Calories eaten against a target, with what's left in the middle.
struct CalorieRing: View {
    var eaten: Double
    var target: Double
    var body: some View {
        let over = eaten > target
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 12)
            Circle().trim(from: 0, to: min(max(eaten / max(target, 1), 0), 1))
                .stroke(over ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(abs(target - eaten).number).font(.roboto(.title2, weight: .bold)).monospacedDigit().minimumScaleFactor(0.6)
                Text(over ? "Cal over" : "Cal left").font(.roboto(.caption)).foregroundStyle(.secondary)
            }.padding(14)
        }
        .frame(width: 116, height: 116)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(eaten.number) of \(target.number) calories")
    }
}

/// One nutrient's progress toward its target, as a label, figures and a thin bar.
struct TargetBar: View {
    var label: String
    var value: Double
    var target: Double
    var unit: String
    var minimum: Bool
    var style: AnyShapeStyle
    var body: some View {
        let over = !minimum && value > target
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.roboto(.caption, weight: .medium)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text("\(value.number) / \(target.number) \(unit)").font(.roboto(.caption)).monospacedDigit()
                    .foregroundStyle(over ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(style)
                        .frame(width: geo.size.width * min(max(value / max(target, 0.001), 0), 1))
                }
            }.frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value.number) of \(target.number) \(unit)")
    }
}

/// A capsule filter button; filled with the app colour when selected.
struct Chip: View {
    var title: String
    var selected: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.roboto(.subheadline, weight: .medium)).lineLimit(1)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)), in: Capsule())
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A full-width, horizontally scrolling row of chips, placed directly on the list background.
struct ChipRow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { content }
        }
        .scrollClipDisabled()
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        .listRowBackground(Color.clear)
    }
}

/// A number you can type, shown large on its own tile so two can sit side by side.
struct StatField: View {
    var title: String
    var unit: String
    @Binding var value: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.roboto(.caption)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TextField(title, value: $value, format: .number)
                    .font(.roboto(.title2, weight: .bold)).keyboardType(.decimalPad).monospacedDigit()
                Text(unit).font(.roboto(.subheadline)).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// The inside of an action tile: an icon over a short label.
struct TileLabel: View {
    var title: String
    var systemImage: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.title3).foregroundStyle(.tint).frame(height: 26)
            Text(title).font(.roboto(.caption, weight: .medium)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 78)
        .padding(.horizontal, 4)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// A row of action tiles placed directly on the list background.
struct TileRow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 10) { content }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
    }
}

/// A full-width prominent button pinned above the tab bar.
struct BottomActionBar<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .font(.roboto(.headline))
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 20).padding(.vertical, 10)
    }
}
