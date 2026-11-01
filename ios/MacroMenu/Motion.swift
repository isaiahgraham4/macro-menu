import SwiftUI
import Combine

// The app's small movements: figures that roll, skeletons that stand in for loading rows,
// and the light on the worktop. All of them hold still with Reduce Motion on.

extension Animation {
    // Springs, so a change that lands mid-way carries on from where it is rather than restarting.
    /// How fast a small change settles: long enough to see, short enough never to feel slow.
    static let figure = Animation.smooth(duration: 0.2)
    /// How long a logged amount takes to count up, with its ring and bars alongside.
    static let counting = Animation.smooth(duration: 0.7)
}

/// A number that really counts to its new value, passing through the numbers on the way.
struct CountingNumber: View, Animatable {
    /// The number being shown, which moves while the animation runs.
    var value: Double
    /// Where it's heading. Steps of `step` on the way, so decimals don't flicker, and the exact figure at the end.
    private let end: Double
    private let step: Double
    private let text: (Double) -> String

    init(_ value: Double, step: Double = 1, text: @escaping (Double) -> String) {
        self.value = value; end = value; self.step = step; self.text = text
    }

    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(text(abs(value - end) < step / 2 ? end : (value / step).rounded() * step)).monospacedDigit()
    }
}

/// The shape of a share image while it's being made.
struct ShareCardSkeleton: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18).fill(.fill.tertiary)
            .aspectRatio(MealShareCard.size, contentMode: .fit)
            .skeleton("Making your image")
    }
}

/// A button that gives a little when you press it, for the app's own tiles and chips.
struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.figure, value: configuration.isPressed)
    }
}

private struct FigureChange<Value: Equatable>: ViewModifier {
    let value: Value
    let animation: Animation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

private struct Skeleton: ViewModifier {
    let label: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false
    func body(content: Content) -> some View {
        content
            .redacted(reason: .placeholder)
            .opacity(dimmed ? 0.5 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: dimmed)
            .onAppear { dimmed = !reduceMotion }
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
    }
}

extension View {
    /// Animates a bar, ring or other figure when `value` changes.
    func figureChange(_ value: some Equatable, animation: Animation = .figure) -> some View {
        modifier(FigureChange(value: value, animation: animation))
    }

    /// A number that rolls to its new value instead of snapping.
    func rolling(_ value: Double) -> some View {
        contentTransition(.numericText(value: value)).figureChange(value)
    }

    /// Shows a row as the soft, gently pulsing outline of what's on its way. `label` is what VoiceOver says.
    func skeleton(_ label: String) -> some View {
        modifier(Skeleton(label: label))
    }
}

/// Stands in for an `OrderMatchCard` while orders are found.
struct OrderCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RESTAURANT").font(.roboto(.caption, weight: .semibold))
            Text("A burger and a side").font(.roboto(.headline))
            VStack(alignment: .leading, spacing: 14) {
                Text("000 Cal").font(.roboto(.largeTitle, weight: .bold))
                HStack(spacing: 0) {
                    ForEach(["Protein", "Carbs", "Fat"], id: \.self) { name in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name).font(.roboto(.caption))
                            Text("00 g").font(.roboto(.headline))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Capsule().fill(.quaternary).frame(height: 6)
            }.padding(.vertical, 8)
            HStack {
                Capsule().fill(.quaternary).frame(width: 76, height: 34)
                Capsule().fill(.quaternary).frame(width: 112, height: 34)
            }
        }.padding(.vertical, 6)
    }
}

/// Stands in for a two-line row, such as a packaged food or a nearby restaurant.
struct RowSkeleton: View {
    var title = "A food or a restaurant"
    var detail = "Its details on a second line"
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.roboto(.headline))
            Text(detail).font(.roboto(.subheadline))
        }.padding(.vertical, 4)
    }
}

/// Light drifting slowly over the worktop: soft patches of the app colour, strongest at the top of the screen,
/// drawn 30 times a second. It stops in the background and holds still in Low Power Mode or with Reduce Motion on.
struct WorktopLight: View {
    var tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var still: Bool { reduceMotion || lowPower || scenePhase != .active }
    private static let size = 4
    /// How strong the light is in each row, top to bottom.
    private static let depth = [1, 0.75, 0.3, 0.1]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: still)) { context in
            // From the clock, not from when this screen opened, so the light carries on across screens.
            let time = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600 * 24)
            MeshGradient(width: Self.size, height: Self.size, points: Self.points(time), colors: colours(time))
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: DispatchQueue.main)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    /// A grid whose points wander slowly. Those on an edge slide along it, so the light always fills the screen.
    private static func points(_ time: Double) -> [SIMD2<Float>] {
        let last = Double(size - 1)
        return (0..<size * size).map { index in
            let row = Double(index / size), column = Double(index % size), phase = Double(index) * 1.7
            let x = column / last + (column == 0 || column == last ? 0 : 0.12 * sin(time * 0.31 + phase))
            let y = row / last + (row == 0 || row == last ? 0 : 0.12 * cos(time * 0.27 + phase))
            return SIMD2(Float(x), Float(y))
        }
    }

    /// Each patch of light swells and fades at its own pace.
    private func colours(_ time: Double) -> [Color] {
        (0..<Self.size * Self.size).map { index in
            let glow = 0.5 + 0.5 * sin(time * 0.23 + Double(index) * 2.4)
            return tint.opacity(glow * Self.depth[index / Self.size])
        }
    }
}
