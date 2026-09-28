import SwiftUI

/// A lightweight, deterministic grain drawn at the device's native resolution.
struct CuttingBoard: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 28)
            .fill(Color(red: 0.89, green: 0.77, blue: 0.59).gradient)
            .overlay {
                Canvas { context, size in
                    for line in 0..<32 {
                        var path = Path()
                        let y = CGFloat(line) * size.height / 31
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addCurve(to: CGPoint(x: size.width, y: y + 6),
                                      control1: CGPoint(x: size.width * 0.3, y: y - 9),
                                      control2: CGPoint(x: size.width * 0.7, y: y + 12))
                        context.stroke(path, with: .color(.brown.opacity(line.isMultiple(of: 3) ? 0.13 : 0.06)), lineWidth: 1)
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 28))
            }
            .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.brown.opacity(0.18), lineWidth: 1).padding(7) }
            .accessibilityHidden(true)
    }
}

/// A warm worktop with quiet grain and an engraved plate motif at the edges.
struct LeanrBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    private var dark: Bool { scheme == .dark }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: dark
                        ? [Color(red: 0.10, green: 0.13, blue: 0.11), Color(red: 0.16, green: 0.14, blue: 0.11)]
                        : [Color(red: 0.97, green: 0.95, blue: 0.89), Color(red: 0.91, green: 0.94, blue: 0.88), Color(red: 0.96, green: 0.90, blue: 0.81)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                if contrast != .increased {
                    RadialGradient(colors: [Color.accentColor.opacity(dark ? 0.12 : 0.09), .clear],
                                   center: .topTrailing, startRadius: 0, endRadius: geometry.size.width * 0.95)
                    Canvas { context, size in
                        let ink = dark ? Color.white : Color.brown
                        // Widely spaced, gently bent lines suggest timber without competing with copy.
                        for line in 0..<38 {
                            let x = CGFloat(line) * size.width / 30
                            var grain = Path()
                            grain.move(to: CGPoint(x: x, y: 0))
                            grain.addCurve(to: CGPoint(x: x - 45, y: size.height),
                                           control1: CGPoint(x: x + 30, y: size.height * 0.35),
                                           control2: CGPoint(x: x - 65, y: size.height * 0.65))
                            context.stroke(grain, with: .color(ink.opacity(0.035)), lineWidth: 0.7)
                        }
                        // Off-canvas concentric rings echo a plate on the worktop.
                        let center = CGPoint(x: size.width + 25, y: size.height * 0.76)
                        for radius in [100.0, 112.0, 150.0, 156.0] {
                            let plate = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                              width: radius * 2, height: radius * 2))
                            context.stroke(plate, with: .color(ink.opacity(0.07)), lineWidth: 1)
                        }
                        // Deterministic flecks give the surface a light paper texture.
                        for dot in 0..<450 {
                            let x = CGFloat((dot * 73) % 997) / 997 * size.width
                            let y = CGFloat((dot * 137) % 991) / 991 * size.height
                            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)),
                                         with: .color(ink.opacity(0.06)))
                        }
                    }
                }
            }.clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct LeanrOnboarding: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var round = 0
    @State private var guess = 600.0
    @State private var revealed = false
    @State private var finished = false
    @State private var guesses: [String: Double] = [:]
    @State private var targetPrompt = false
    @State private var estimatingTargets = false
    @State private var targetSaveFailed = false
    var complete: () -> Void

    private var meals: [Food] {
        let ids = [
            "kfc:10-wicked-wings",
            "mcd:cheesy-double-quarter-pounder",
            "hj:triple-whopper-with-cheese"
        ]
        return ids.compactMap { id in store.catalog.foods.first { $0.id == id } }
    }
    private var meal: Food? { meals.indices.contains(round) ? meals[round] : nil }
    private var motion: Animation? { reduceMotion ? nil : .smooth(duration: 0.35) }
    private var answeredMeals: [Food] { meals.filter { guesses[$0.id] != nil } }
    private var guessedTotal: Double { guesses.values.reduce(0, +) }
    private var actualTotal: Double { answeredMeals.reduce(0) { $0 + $1.cal } }
    private var calorieGap: Double { actualTotal - guessedTotal }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    Label("Leanr", systemImage: "leaf.fill").font(.system(.title2, design: .rounded, weight: .bold))
                    Spacer()
                    Button("Skip") {
                        if targetPrompt { complete() } else { targetPrompt = true }
                    }.foregroundStyle(.secondary).frame(minHeight: 44)
                }
                if targetPrompt {
                    VStack(alignment: .leading, spacing: 22) {
                        Image(systemName: "target").font(.system(size: 48)).foregroundStyle(.tint)
                        Text("Want to find your targets?")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("Estimate your maintenance calories and daily protein, carbs and fat from your age, height, weight and activity level. Choose whether you want to maintain, lose or gain weight.")
                            .foregroundStyle(.secondary)
                        Text("This is optional. You can review the estimate before applying it, and change your targets later in Settings.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button { estimatingTargets = true } label: {
                            Text("Find my targets").frame(maxWidth: .infinity).padding(.vertical, 8)
                        }.buttonStyle(.borderedProminent).controlSize(.large)
                        Button("Not now — start using Leanr", action: complete)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.padding(.vertical, 24)
                } else if !finished, let meal {
                    HStack(spacing: 6) {
                        ForEach(meals.indices, id: \.self) { index in
                            Capsule().fill(index <= round ? Color.accentColor : Color.secondary.opacity(0.2)).frame(height: 4)
                        }
                    }.accessibilityLabel("Question \(round + 1) of \(meals.count)")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("A little food for thought.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("How many calories do you think are in this?").foregroundStyle(.secondary)
                    }
                    VStack(spacing: 16) {
                        HStack {
                            Text("ON THE BOARD").font(.caption.weight(.bold)).tracking(2)
                            Spacer()
                            Text(meal.chain == "mcd" ? "Macca’s" : store.chainName(meal.chain)).font(.headline)
                        }
                        Image(systemName: "takeoutbag.and.cup.and.straw.fill")
                            .font(.system(size: 60)).padding(.vertical, 8)
                        Text(meal.name).font(.system(.title2, design: .rounded, weight: .bold)).multilineTextAlignment(.center)
                        Text(meal.chain == "kfc" ? "10 wings · no sides or drink" : "Burger only · no sides or drink")
                            .font(.caption).multilineTextAlignment(.center)
                        if !meal.serve.isEmpty { Text(meal.serve).font(.caption).multilineTextAlignment(.center) }
                    }
                    .foregroundStyle(Color(red: 0.23, green: 0.17, blue: 0.10))
                    .padding(28).frame(maxWidth: .infinity)
                    .background { CuttingBoard() }
                    .id(round).transition(.opacity)

                    if revealed {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("\(meal.cal.number) calories").font(.system(.largeTitle, design: .rounded, weight: .bold)).contentTransition(.numericText())
                            Text(abs(guess - meal.cal) <= 50 ? "Close guess! You were within 50 calories." : "Your guess: \(Int(guess)) Cal · about \(Int(abs(guess - meal.cal).rounded())) Cal away.")
                            Text("No need to guess with Leanr. See calories and protein, compare your options, and build a meal that works for you.").foregroundStyle(.secondary)
                            Text("\(meal.p.number) g protein · Bundled \(store.chainName(meal.chain)) Australia menu data. Servings and recipes may vary.").font(.caption).foregroundStyle(.secondary)
                        }.accessibilityElement(children: .combine).accessibilityAddTraits(.updatesFrequently)
                        .transition(.opacity)
                    } else {
                        VStack(spacing: 12) {
                            Text("\(Int(guess)) Cal").font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit().contentTransition(.numericText())
                            Slider(value: $guess, in: 100...1600, step: 25)
                                .accessibilityLabel("Your calorie guess").accessibilityValue("\(Int(guess)) calories")
                            HStack { Text("100 Cal"); Spacer(); Text("1,600 Cal") }.font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        withAnimation(motion) {
                            if !revealed { guesses[meal.id] = guess; revealed = true }
                            else if round + 1 < meals.count { round += 1; revealed = false; guess = 600 }
                            else { finished = true }
                        }
                    } label: {
                        Text(revealed ? (round + 1 < meals.count ? "Try another meal" : "See my total") : "Reveal the calories")
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        if !answeredMeals.isEmpty {
                            Text(calorieGap > 0 ? "The calories you didn’t count." : "Your guesses, added up.")
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            VStack(alignment: .leading, spacing: 16) {
                                Text("\(abs(calorieGap).number) Cal")
                                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                                    .contentTransition(.numericText())
                                Text(calorieGap > 0 ? "more than you guessed" : calorieGap < 0 ? "less than you guessed" : "difference — spot on!")
                                    .font(.headline)
                                Divider()
                                LabeledContent("Your guesses", value: "\(guessedTotal.number) Cal")
                                LabeledContent("Menu total", value: "\(actualTotal.number) Cal")
                                Text("Across \(answeredMeals.count) quiz items combined. Overestimates offset underestimates in this total.")
                                    .font(.caption)
                            }
                            .foregroundStyle(Color(red: 0.23, green: 0.17, blue: 0.10))
                            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                            .background { CuttingBoard() }
                            if calorieGap > 0 {
                                Text("If you ate these items and logged your guesses, you’d count \(calorieGap.number) fewer calories than the menu lists. If those guesses brought you to your target, that gap would put you \(calorieGap.number) calories above it across those meals.")
                                Text("Small guessing gaps can add up and make it harder to stay on track. Leanr helps you see what’s in your meals, so you can plan toward your goals with more confidence.")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(calorieGap < 0 ? "Your combined guesses were above the menu total. Checking the numbers helps you plan without counting more calories than your meals contain." : "You matched the combined menu total. Leanr keeps the numbers handy so you don’t have to rely on a guess next time.")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Your favourites.\nA little more informed.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                        }
                        Label("Compare restaurant meals", systemImage: "magnifyingglass")
                        Label("Build a meal around your targets", systemImage: "fork.knife")
                        Label("Keep track of your day", systemImage: "calendar")
                        Text("Start with the foods you enjoy. Leanr brings the numbers into focus.").foregroundStyle(.secondary)
                        Button { withAnimation(motion) { targetPrompt = true } } label: { Text("Continue").frame(maxWidth: .infinity).padding(.vertical, 8) }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                    }.padding(.vertical, 24)
                }
            }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
        .background { LeanrBackground() }
        .interactiveDismissDisabled()
        .sheet(isPresented: $estimatingTargets) {
            NavigationStack {
                TargetCalculator { values in
                    if store.applyEstimatedTargets(values) {
                        estimatingTargets = false
                        complete()
                    } else { targetSaveFailed = true }
                }
                .alert("Couldn’t save targets", isPresented: $targetSaveFailed) {
                    Button("OK", role: .cancel) {}
                } message: { Text("Your targets haven’t changed. Try again or cancel to skip this step.") }
            }
        }
    }
}
