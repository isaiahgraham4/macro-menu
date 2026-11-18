import SwiftUI

/// The short tour of the tabs that follows first-run onboarding, and that Settings can replay. Each step switches to its tab,
/// so the screen behind the card is the one being described and the tab bar shows which tab it is.
enum TourStep: Int, CaseIterable, Identifiable {
    case today, find, map, meal, progress, settings
    var id: Int { rawValue }

    /// Every tab has a step; a new tab won't build until it's given one here.
    static func step(for tab: AppTab) -> TourStep {
        switch tab {
        case .today: .today
        case .find: .find
        case .map: .map
        case .meal: .meal
        case .progress: .progress
        }
    }

    /// The tab showing behind the card. Settings is reached from Today's gear.
    var tab: AppTab {
        switch self {
        case .today, .settings: .today
        case .find: .find
        case .map: .map
        case .meal: .meal
        case .progress: .progress
        }
    }

    var title: String {
        switch self {
        case .today: "Today"
        case .find: "Find"
        case .map: "Map"
        case .meal: "Meal"
        case .progress: "Progress"
        case .settings: "Settings"
        }
    }

    var detail: String {
        switch self {
        case .today: "Log what you eat and see what's left of your day. Scan, Photo and Describe are the quickest ways in."
        case .find: "Say what you have left and Leanrrr suggests orders that fit, using each restaurant's own numbers."
        case .map: "The closest restaurant of each chain, with the best order at each for what's left today."
        case .meal: "Build a meal from any foods, or send an order here from Find, then log it in one go."
        case .progress: "Your weight trend, measurements and how your week, month or three months went."
        case .settings: "Targets, reminders, Apple Health and colours live behind the gear at the top right of every tab."
        }
    }

    var symbol: String {
        switch self {
        case .today: "calendar"
        case .find: "magnifyingglass"
        case .map: "map"
        case .meal: "fork.knife"
        case .progress: "chart.line.uptrend.xyaxis"
        case .settings: "gearshape"
        }
    }

    var next: TourStep? { TourStep(rawValue: rawValue + 1) }
    var isLast: Bool { next == nil }
}

enum TabTour {
    /// Set once the tour has been finished or skipped, so it's offered only once.
    static let seenKey = "leanr.tour.seen"
}

/// The card for one step, on the same cutting board as the moment cards and onboarding, above the tab bar.
struct TabTourCard: View {
    let step: TourStep
    let advance: () -> Void
    let skip: () -> Void
    @AppStorage(AppAccent.storageKey) private var accentRaw = AppAccent.standard.rawValue
    @Environment(\.dynamicTypeSize) private var typeSize
    private var accent: Color { AppAccent.resolvedColor(accentRaw) }

    var body: some View {
        FoldRow { fold in
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 5) {
                    ForEach(TourStep.allCases) { other in
                        Capsule().fill(other.rawValue <= step.rawValue ? AnyShapeStyle(accent) : AnyShapeStyle(boardInk.opacity(0.14)))
                            .frame(height: 4)
                    }
                }
                .accessibilityHidden(true)
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
                layout {
                    Image(systemName: step.symbol).font(.title).foregroundStyle(accent).frame(width: 40).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title).font(.display(.title3))
                        Text(step.detail).font(.roboto(.subheadline))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(boardInk)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(step.title), \(step.rawValue + 1) of \(TourStep.allCases.count). \(step.detail)")
                HStack {
                    if !step.isLast {
                        Button("Skip tour", action: skip).buttonStyle(.borderless).tint(boardInk.opacity(0.7))
                            .frame(minHeight: 44)
                    }
                    Spacer()
                    Button(step.isLast ? "Done" : "Next", action: advance)
                        .buttonStyle(.borderedProminent).tint(accent)
                        .font(.roboto(.headline))
                }
            }
            .padding(20)
            .background { CuttingBoard() }
            .frame(maxWidth: 420)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .padding(.horizontal, 16)
            .leftOfFold(fold).frame(maxWidth: .infinity)
        }
        .padding(.bottom, 92)
    }
}

/// Runs the tour over the tab view: a scrim that keeps taps off the screens, and the card for the current step.
struct TabTourOverlay: ViewModifier {
    @Binding var step: TourStep?
    let nav: Navigator
    /// Called when the tour is finished or skipped, to record that it's been seen.
    let finished: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if step != nil {
                    Color.black.opacity(0.28).ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {}
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) {
                if let step {
                    TabTourCard(step: step, advance: { advance(from: step) }, skip: finish)
                        .id(step)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.15), value: step)
            .sensoryFeedback(.selection, trigger: step) { old, new in old != nil && new != nil }
            .onChange(of: step) {
                guard let step else { return }
                nav.tab = step.tab
                AccessibilityNotification.Announcement("\(step.title). \(step.detail)").post()
            }
    }

    private func advance(from current: TourStep) {
        if let next = current.next { step = next } else { finish() }
    }

    private func finish() {
        finished()
        step = nil
        nav.tab = .today
    }
}
