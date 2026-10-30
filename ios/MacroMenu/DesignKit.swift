import SwiftUI

// Small building blocks that give the list screens some structure: summary rings and bars,
// filter chips, side-by-side number tiles and action tiles.

/// Colour for a nutrient: macros use the colours chosen in Settings (the defaults when Premium is locked),
/// everything else uses the app colour.
@MainActor func nutrientStyle(_ key: String) -> AnyShapeStyle {
    guard ["p", "c", "f"].contains(key) else { return AnyShapeStyle(.tint) }
    let defaults = UserDefaults.standard
    let choices = Premium.isUnlocked ? [
        "p": defaults.string(forKey: MacroColours.proteinKey),
        "c": defaults.string(forKey: MacroColours.carbsKey),
        "f": defaults.string(forKey: MacroColours.fatKey)
    ].compactMapValues { $0 } : [:]
    return AnyShapeStyle(MacroColours.colour(key, choices: choices))
}

/// Calories eaten against a target, with what's left in the middle.
struct CalorieRing: View {
    var eaten: Double
    var target: Double
    /// Grows with the text size so "Cal left" still fits inside.
    @ScaledMetric(relativeTo: .title2) private var size = 116.0
    var body: some View {
        let over = eaten > target
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 12)
            Circle().trim(from: 0, to: min(max(eaten / max(target, 1), 0), 1))
                .stroke(over ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                CountingNumber(abs(target - eaten)) { $0.number }.font(.roboto(.title2, weight: .bold)).minimumScaleFactor(0.6)
                Text(over ? "Cal over" : "Cal left").font(.roboto(.caption)).foregroundStyle(.secondary).minimumScaleFactor(0.7)
            }.padding(14).lineLimit(1)
        }
        .frame(width: min(size, 260), height: min(size, 260))
        .figureChange([eaten, target], animation: .counting)
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
        let figures = CountingNumber(value) { "\($0.number) / \(target.number) \(unit)" }.font(.roboto(.caption))
            .foregroundStyle(over ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
        let name = Text(label).font(.roboto(.caption, weight: .medium)).foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 5) {
            // Side by side when there's room; the figures drop below the name at large text sizes.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { name.fixedSize(); Spacer(minLength: 4); figures.fixedSize() }
                VStack(alignment: .leading, spacing: 2) { name; figures }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(style)
                        .frame(width: geo.size.width * min(max(value / max(target, 0.001), 0), 1))
                }
            }.frame(height: 6)
        }
        .figureChange([value, target], animation: .counting)
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
        .buttonStyle(PressStyle())
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
                TextField(title, value: $value, format: decimalFormat())
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
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title3) private var iconWidth = 28.0
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // At the largest sizes each tile becomes a full-width row: icon, then the whole label.
                HStack(spacing: 12) {
                    Image(systemName: systemImage).font(.title3).foregroundStyle(.tint).frame(width: iconWidth)
                    Text(title).font(.roboto(.caption, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: systemImage).font(.title3).foregroundStyle(.tint).frame(minHeight: 26)
                    Text(title).font(.roboto(.caption, weight: .medium)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
                }
                .padding(.horizontal, 4).padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 78)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// A row that keeps clear of the fold on a partly open iPhone Duo. `content` gets the fold, or nil when none crosses the row.
struct FoldRow<Content: View>: View {
    private let content: (RowFold?) -> Content
    @State private var fold: RowFold?
    init(@ViewBuilder content: @escaping (RowFold?) -> Content) { self.content = content }
    var body: some View {
        content(fold).background {
            GeometryReader { geometry in
                Color.clear.onChange(of: geometry.rowFold, initial: true) { _, new in fold = new }
            }
        }
    }
}

private extension GeometryProxy {
    var rowFold: RowFold? {
        guard #available(iOS 27.1, *) else { return nil }
        // A fold running across the row is narrower than it; one running along the row spans its whole width.
        let frame = reservedRegions(kind: .division).first { $0.isActive && $0.frame.width < size.width }?.frame
        return frame.flatMap { RowFold(left: $0.minX, right: $0.maxX, rowWidth: size.width) }
    }
}

/// Equal columns parted around a fold, with half the views on each side.
struct FoldPartedLayout: Layout {
    var fold: RowFold
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = fold.width(proposed: proposal.width)
        let cells = fold.columns(width: width, count: subviews.count, spacing: spacing)
        let height = zip(subviews, cells).map { $0.sizeThatFits(ProposedViewSize(width: $1.width, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, cell) in zip(subviews, fold.columns(width: bounds.width, count: subviews.count, spacing: spacing)) {
            subview.place(at: CGPoint(x: bounds.minX + cell.x, y: bounds.minY), proposal: ProposedViewSize(width: cell.width, height: bounds.height))
        }
    }
}

extension AnyLayout {
    /// Views side by side, parted around the fold when one crosses the row.
    static func columns(spacing: CGFloat, fold: RowFold?) -> AnyLayout {
        fold.map { AnyLayout(FoldPartedLayout(fold: $0, spacing: spacing)) } ?? AnyLayout(HStackLayout(spacing: spacing))
    }
}

extension View {
    /// Narrows a three-part segmented control so the label in its middle part misses the fold.
    func middleLabelClear(of fold: RowFold?) -> some View {
        let fit = fold?.middleLabelFit
        return frame(width: fit?.width).frame(maxWidth: fit == nil ? nil : .infinity, alignment: fit?.leading == false ? .trailing : .leading)
    }

    /// Keeps a view to the left of the fold, using the room there.
    func leftOfFold(_ fold: RowFold?) -> some View {
        frame(width: fold.map { $0.left - 8 }).frame(maxWidth: fold == nil ? nil : .infinity, alignment: .leading)
    }
}

/// A row of action tiles placed directly on the list background.
struct TileRow<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        FoldRow { fold in
            // Tiles share a row normally and stack at the largest text sizes.
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout.columns(spacing: 10, fold: fold)
            layout { content }
        }
        .buttonStyle(PressStyle())
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        .listRowBackground(Color.clear)
    }
}

/// A full-width prominent button pinned above the tab bar.
struct BottomActionBar<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        FoldRow { fold in
            content
                .font(.roboto(.headline))
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .leftOfFold(fold)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }
}
