import SwiftUI
import StoreKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthSync.self) private var health
    @Environment(CloudSync.self) private var cloud
    @Environment(Navigator.self) private var nav
    @State private var healthFailed = false
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system
    @State private var showQuiz = false
    @State private var showPremium = false
    @State private var redeeming = false
    @State private var estimating = false
    @State private var countryFailed = false
    @AppStorage(TodaySuggestions.storageKey) private var suggestFoods = true
    @AppStorage(LiveDay.storageKey) private var liveDay = false
    @AppStorage(FeatureTips.enabledKey) private var featureTips = true
    @AppStorage(AppAccent.storageKey) private var accentRaw = AppAccent.standard.rawValue
    /// Bumped a moment after the accent changes, once this sheet's own tint has caught up, to rebuild its menu pickers.
    @State private var pickerRefresh = 0
    @AppStorage(AppIconTheme.storageKey) private var iconRaw = AppIconTheme.standard.rawValue
    private var current: AppAccent { AppAccent.resolved(accentRaw) }
    private var isCustomAccent: Bool { Premium.isUnlocked && ThemeColour.isCustom(accentRaw) }
    private var currentIcon: AppIconTheme { AppIconTheme(rawValue: iconRaw) ?? .standard }
    @AppStorage(MacroColours.proteinKey) private var proteinRaw = "blue"
    @AppStorage(MacroColours.carbsKey) private var carbsRaw = "orange"
    @AppStorage(MacroColours.fatKey) private var fatRaw = "red"
    @AppStorage(PaperTint.storageKey) private var paperRaw = PaperTint.cream.rawValue
    private var currentPaper: PaperTint { PaperTint.resolved(paperRaw) }
    private var currentPack: ColourPack? {
        ColourPack.matching(accent: accentRaw, protein: proteinRaw, carbs: carbsRaw, fat: fatRaw, icon: iconRaw,
                            paper: UserDefaults.standard.string(forKey: PaperTint.storageKey).map { _ in paperRaw })
    }
    @Environment(AppStore.self) private var store
    var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }
    /// When the restaurant menu in use was published.
    var menuDate: String {
        store.menuDate?.formatted(date: .abbreviated, time: .omitted) ?? "Built in"
    }
    var body: some View {
        LeanrList {
            if Premium.subscriptionsEnabled {
                Section {
                    Button { showPremium = true } label: {
                        HStack {
                            Label("Even Leanrrr", systemImage: Premium.isUnlocked ? "checkmark.seal.fill" : "sparkles")
                            Spacer()
                            Text(Premium.isUnlocked ? PremiumAccess.statusText(Purchases.shared.entitlement) : "See what's included")
                                .font(.roboto(.subheadline)).foregroundStyle(Color(.secondaryLabel))   // not tint-washed: the button tints .secondary
                        }
                    }
                }
            }
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.name).tag(option)
                    }
                }
                // A menu picker keeps the tint it was made with; rebuild it when a colour pack changes the accent.
                .id(pickerRefresh)
                Text("System follows your device’s appearance and changes automatically with it.")
                    .font(.roboto(.caption)).foregroundStyle(.secondary)
            }
            Section {
                ForEach(ColourPack.all) { pack in
                    let locked = !Premium.isUnlocked && !pack.isFree
                    Button { if locked { showPremium = true } else { applyPack(pack) } } label: {
                        ColourPackRow(pack: pack, selected: pack == currentPack, locked: locked)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(locked ? "\(pack.name) colour pack, needs Even Leanrrr" : "\(pack.name) colour pack")
                    .accessibilityHint(pack.detail)
                    .accessibilityAddTraits(pack == currentPack ? .isSelected : [])
                }
            } header: {
                Text("Colour packs")
            } footer: {
                if Premium.isUnlocked {
                    Text("\(currentPack?.name ?? "Your own mix") · Sets the app icon, app colour, macro colours and background together. You can still change any of them below.")
                } else {
                    Label("Colour packs come with Even Leanrrr.", systemImage: "lock.fill")
                }
            }
            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 16) {
                    ForEach(AppAccent.allCases) { accent in
                        let locked = !Premium.isUnlocked && accent != AppAccent.standard
                        let chosen = !isCustomAccent && accent == current
                        // A locked colour opens Premium instead of doing nothing.
                        Button { if locked { showPremium = true } else { accentRaw = accent.rawValue } } label: {
                            Circle().fill(accent.color).frame(width: 36, height: 36)
                                .overlay {
                                    if chosen { Image(systemName: "checkmark").fontWeight(.bold).foregroundStyle(.white) }
                                    else if locked { Image(systemName: "lock.fill").font(.roboto(.caption)).foregroundStyle(.white) }
                                }
                                .background { Circle().strokeBorder(accent.color, lineWidth: 2).padding(-5).opacity(chosen ? 1 : 0) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(locked ? "\(accent.name), needs Even Leanrrr" : accent.name)
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                    }
                }.padding(.vertical, 8)
                CustomColourRow(title: "Custom colour", raw: $accentRaw, fallback: AppAccent.standard) { showPremium = true }
            } header: {
                Text("App colour")
            } footer: {
                if Premium.isUnlocked {
                    Text("\(isCustomAccent ? "Custom" : current.name) · Changes buttons, tabs, links and progress bars.")
                    + Text(ThemeColour.lightWarning(accentRaw).map { " " + $0 } ?? "")
                } else { Label("More colours come with Even Leanrrr.", systemImage: "lock.fill") }
            }
            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 14) {
                    ForEach(PaperTint.allCases) { tint in
                        let locked = !Premium.isUnlocked && tint != .cream
                        let chosen = tint == currentPaper
                        Button { if locked { showPremium = true } else { paperRaw = tint.rawValue } } label: {
                            VStack(spacing: 6) {
                                PaperSwatch(tint: tint)
                                    .frame(width: 74, height: 52)
                                    .overlay(alignment: .bottomTrailing) {
                                        // Corner badges, the same as the app icons, so nothing sits on the preview itself.
                                        if locked {
                                            Image(systemName: "lock.fill").font(.roboto(.caption2, weight: .bold)).foregroundStyle(.white)
                                                .frame(width: 22, height: 22).background(Color.black.opacity(0.6), in: Circle()).padding(4)
                                        }
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: PaperSwatch.radius, style: .continuous)
                                            .stroke(chosen ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 3)
                                    }
                                Text(tint.name).font(.roboto(.caption, weight: .medium))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(locked ? "\(tint.name) background, needs Even Leanrrr" : "\(tint.name) background")
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                    }
                }.padding(.vertical, 8)
            } header: {
                Text("Background")
            } footer: {
                if Premium.isUnlocked { Text("\(currentPaper.name) · A faint tint behind every screen, in light and dark mode.") }
                else { Label("Tinted backgrounds come with Even Leanrrr.", systemImage: "lock.fill") }
            }
            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 14) {
                    ForEach(AppIconTheme.allCases) { icon in
                        let locked = !Premium.isUnlocked && icon != .standard
                        Button { if locked { showPremium = true } else { selectIcon(icon) } } label: {
                            VStack(spacing: 6) {
                                Image(icon.previewAsset)
                                    .resizable().scaledToFill().frame(width: 66, height: 66)
                                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                                    .overlay(alignment: .bottomTrailing) {
                                        // A corner badge, so the lock doesn't sit on top of the icon's artwork.
                                        if locked {
                                            Image(systemName: "lock.fill").font(.roboto(.caption2, weight: .bold)).foregroundStyle(.white)
                                                .frame(width: 22, height: 22).background(Color.black.opacity(0.6), in: Circle()).padding(4)
                                        }
                                    }
                                    .overlay { RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(icon == currentIcon ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 3) }
                                Text(icon.name).font(.roboto(.caption, weight: .medium))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(locked ? "\(icon.name) app icon, needs Even Leanrrr" : "\(icon.name) app icon")
                        .accessibilityAddTraits(icon == currentIcon ? .isSelected : [])
                    }
                }.padding(.vertical, 8)
            } header: {
                Text("App icon")
            } footer: {
                Text(Premium.isUnlocked ? "\(currentIcon.name)" : "\(currentIcon.name) · More icon packs come with Even Leanrrr.")
            }
            Section {
                Picker(selection: Binding(get: { store.region }, set: { if !AppServices.useRegion($0) { countryFailed = true } })) {
                    ForEach(MenuRegion.allCases) { Text($0.name).tag($0) }
                } label: { Label("Country", systemImage: "globe") }
                .id(pickerRefresh)
            } header: { Text("Restaurant menus") } footer: {
                Text("Changes which restaurants Leanrrr shows. Foods you’ve logged or saved keep their numbers. Supermarket ready meals and snacks are in Australia, New Zealand, the US, Canada, the UK and South Africa. Copycat Kitchen is only in Australia.")
            }
            Section("Targets") {
                NavigationLink { TargetsView() } label: { Label("Targets & target sets", systemImage: "target") }
                Button { estimating = true } label: { Label("Calculate my macros", systemImage: "function") }
                NavigationLink { WaterSettings() } label: { Label("Water target", systemImage: "drop") }
                NavigationLink { StepsSettings() } label: { Label("Steps", systemImage: "figure.walk") }
                NavigationLink { ActiveEnergySettings() } label: { Label("Calories burnt", systemImage: "flame") }
                Toggle(isOn: $suggestFoods) { Label("Suggest foods for what's left", systemImage: "lightbulb") }
                Toggle(isOn: $featureTips) { Label("Show tips for features I haven't tried", systemImage: "sparkles") }
                NavigationLink { MacroColourSettings() } label: { Label("Target colours", systemImage: "paintpalette") }
                NavigationLink { ReminderSettings() } label: { Label("Reminders", systemImage: "bell") }
            }
            Section {
                Toggle(isOn: $liveDay) { Label("Calories on the Lock Screen", systemImage: "lock.iphone") }
                    .onChange(of: liveDay) { LiveDay.refresh(store) }
            } footer: {
                Text("Shows the calories you have left on the Lock Screen and in the Dynamic Island. iOS ends it after about 8 hours, and it comes back when you next open Leanrrr.")
            }
            Section {
                if health.isAvailable {
                    Toggle(isOn: Binding(get: { health.enabled }, set: { on in
                        if on { Task { if !(await health.connect()) { healthFailed = true } } } else { health.disconnect() }
                    })) { Label("Connect Apple Health", systemImage: "heart") }
                } else {
                    Text("Apple Health isn’t available on this device.").foregroundStyle(.secondary)
                }
            } header: { Text("Apple Health") } footer: {
                Text("Saves the food and water you log and your weigh-ins to Health, and reads your weight, active energy and steps. To choose exactly what Leanrrr can read or write, open the Health app → your profile → Apps → Leanrrr.")
            }
            Section {
                Toggle(isOn: Binding(get: { cloud.enabled }, set: { cloud.enabled = $0 })) { Label("Sync with iCloud", systemImage: "icloud") }
                if cloud.enabled {
                    if let problem = cloud.problem {
                        Text(problem).font(.roboto(.caption)).foregroundStyle(.orange)
                    } else if let last = cloud.lastSynced {
                        LabeledContent("Last synced", value: last.formatted(.relative(presentation: .named)))
                    }
                    Button("Sync now") { Task { await cloud.sync() } }.disabled(cloud.syncing)
                }
            } header: { Text("iCloud") } footer: {
                Text("Keeps your foods, logs, targets and weigh-ins the same on every device signed in to your Apple Account. Your current meal and settings like colours stay on each device.")
            }
            SharedFoodsSection()
            BackupSection()
            Section("About") {
                LabeledContent("App", value: "Leanrrr")
                LabeledContent("Developer", value: AppInfo.developer)
                if let email = AppInfo.contactEmail, let url = URL(string: "mailto:\(email)") {
                    Link(destination: url) { LabeledContent("Contact", value: email) }
                }
                Button("Play the calorie quiz") { showQuiz = true }
                Button("Take the tour of the tabs") { nav.tourRequested = true }
                NavigationLink { SourcesView() } label: { Label("Menu sources", systemImage: "info.circle") }
                LabeledContent("Menu updated", value: menuDate)
                LabeledContent("Version", value: version)
            }
            Section("Privacy and legal") {
                NavigationLink { LegalDocumentView(document: .privacy) } label: { Label("Privacy policy", systemImage: "hand.raised") }
                // Washington's My Health My Data Act wants its own policy, linked from the app's settings and the App Store page.
                NavigationLink { LegalDocumentView(document: .healthData) } label: { Label("Consumer health data", systemImage: "heart.text.square") }
                NavigationLink { LegalDocumentView(document: .terms) } label: { Label("Terms of use", systemImage: "doc.text") }
                NavigationLink { AcknowledgementsView() } label: { Label("Acknowledgements", systemImage: "text.book.closed") }
                NavigationLink { DeleteDataView() } label: { Label("Delete all my data", systemImage: "trash").foregroundStyle(.red) }
            }
            if Premium.subscriptionsEnabled && !Premium.isUnlocked {
                // Last in Settings. Apple's own sheet for offer codes made in App Store Connect (App Review rule 3.1.1 allows no other kind).
                Section {
                    Button { redeeming = true } label: { Label("Redeem a code", systemImage: "ticket") }
                } footer: {
                    Text("Got a code for Even Leanrrr? Enter it here to start it free.")
                }
            }
        }.navigationTitle("Settings")
            // Rebuilt in the same update, a picker still picks up the old tint, so wait a turn of the run loop.
            .onChange(of: accentRaw) { DispatchQueue.main.async { pickerRefresh += 1 } }
            .sheet(isPresented: $showQuiz) { LeanrOnboarding(askCountry: false) { showQuiz = false } }
            .alert("Couldn’t load that menu", isPresented: $countryFailed) {
                Button("OK", role: .cancel) {}
            } message: { Text("Your restaurant menus haven’t changed.") }
            .sheet(isPresented: $showPremium) { PremiumView() }
            .offerCodeRedemption(isPresented: $redeeming) { _ in Task { await Purchases.shared.refresh(); await RevenueCatLink.sync() } }
            .sheet(isPresented: $estimating) {
                NavigationStack {
                    TargetCalculator { values in
                        if store.applyEstimatedTargets(values) { estimating = false; store.notice = "Targets updated" }
                    }
                }
            }
            .alert("Couldn’t connect to Apple Health", isPresented: $healthFailed) { Button("OK") {} } message: {
                Text(health.lastError ?? "Check that Health is set up on this device, then try again.")
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    private func selectIcon(_ icon: AppIconTheme) {
        iconRaw = icon.rawValue
        UIApplication.shared.setAlternateIconName(icon.alternateName)
    }

    private func applyPack(_ pack: ColourPack) {
        accentRaw = pack.accent.rawValue
        proteinRaw = pack.protein.rawValue
        carbsRaw = pack.carbs.rawValue
        fatRaw = pack.fat.rawValue
        paperRaw = pack.paper.rawValue
        // iOS shows an alert for every icon change, so skip it when the icon is already the pack's.
        if UIApplication.shared.alternateIconName != pack.icon.alternateName { selectIcon(pack.icon) } else { iconRaw = pack.icon.rawValue }
    }
}

/// One pack in Settings: its icon, name, a line about it, and swatches for the app colour, the three macros and the background.
private struct ColourPackRow: View {
    let pack: ColourPack
    let selected: Bool
    let locked: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(pack.icon.previewAsset)
                .resizable().scaledToFill().frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                // A hairline, so the white Classic icon doesn't vanish into the white row.
                .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(.separator), lineWidth: 0.5) }
            VStack(alignment: .leading, spacing: 2) {
                Text(pack.name).font(.roboto(.body, weight: .medium)).foregroundStyle(.primary)
                Text(pack.detail).font(.roboto(.caption)).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 5) {
                    swatch(pack.accent, wide: true)
                    swatch(pack.protein)
                    swatch(pack.carbs)
                    swatch(pack.fat)
                    PaperSwatch(tint: pack.paper, compact: true).frame(width: 18, height: 12).padding(.leading, 3)
                }.padding(.top, 3).accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            if selected {
                Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint)
            } else if locked {
                Image(systemName: "lock.fill").font(.roboto(.caption)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    /// The app colour is a short bar, the macros are dots, so the two kinds read apart.
    private func swatch(_ accent: AppAccent, wide: Bool = false) -> some View {
        Capsule().fill(accent.color).frame(width: wide ? 22 : 10, height: 10)
    }
}

/// A background tint as a tiny screen: the light shade with the app's dot grid and two cards, and the dark shade as a
/// band on the right with its own cards. The light side gets most of the room because that's where the tints differ;
/// the dark ones are all near black. The cards are what make a faint tint readable, the same way they do in the app.
/// `compact` draws only the two shades, for the colour pack rows.
struct PaperSwatch: View {
    let tint: PaperTint
    var compact = false

    static let radius: CGFloat = 10
    /// The card colour in dark mode (secondary grouped background).
    private static let darkCard = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    private static let ink = Color(red: 0.40, green: 0.31, blue: 0.20)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: compact ? 3 : Self.radius, style: .continuous)
        Canvas { context, size in
            let split = (size.width * (compact ? 0.62 : 0.64)).rounded()
            let light = CGRect(x: 0, y: 0, width: split, height: size.height)
            let dark = CGRect(x: split, y: 0, width: size.width - split, height: size.height)
            context.fill(Path(light), with: .color(tint.color(dark: false)))
            context.fill(Path(dark), with: .color(tint.color(dark: true)))
            guard !compact else { return }
            drawDots(in: light, ink: Self.ink.opacity(0.22), context: context)
            drawDots(in: dark, ink: Color.white.opacity(0.14), context: context)
            drawCards(in: light, card: .white, line: Color.black.opacity(0.12), second: true, context: context)
            drawCards(in: dark, card: Self.darkCard, line: Color.white.opacity(0.16), second: false, context: context)
        }
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color(.separator), lineWidth: 0.5) }
        .accessibilityHidden(true)
    }

    /// The order-pad dot grid, scaled down.
    private func drawDots(in rect: CGRect, ink: Color, context: GraphicsContext) {
        var dots = Path()
        let step = 6.0
        for x in stride(from: rect.minX + step / 2, to: rect.maxX, by: step) {
            for y in stride(from: rect.minY + step / 2, to: rect.maxY, by: step) {
                dots.addEllipse(in: CGRect(x: x - 0.55, y: y - 0.55, width: 1.1, height: 1.1))
            }
        }
        context.fill(dots, with: .color(ink))
    }

    /// A card like the app's with a short line of text, and on the light side a smaller card under it.
    /// They're kept small so most of the swatch is the tint itself.
    private func drawCards(in rect: CGRect, card: Color, line: Color, second: Bool, context: GraphicsContext) {
        let inset = rect.width > 40 ? 7.0 : 5.0
        let width = rect.width - inset * 2
        let first = CGRect(x: rect.minX + inset, y: rect.minY + (rect.height * 0.16).rounded(), width: width, height: (rect.height * 0.3).rounded())
        context.fill(Path(roundedRect: first, cornerRadius: 3.5, style: .continuous), with: .color(card))
        let text = CGRect(x: first.minX + 4, y: first.midY - 1.25, width: first.width * 0.5, height: 2.5)
        context.fill(Path(roundedRect: text, cornerRadius: 1.25), with: .color(line))
        if second {
            let below = CGRect(x: first.minX, y: first.maxY + 4, width: (width * 0.62).rounded(), height: (rect.height * 0.18).rounded())
            context.fill(Path(roundedRect: below, cornerRadius: 3, style: .continuous), with: .color(card))
        }
    }
}

/// Any colour, from the system colour picker, stored as "#RRGGBB" next to the preset swatches.
/// Locked rows open Premium when `onLocked` is given; inside an already-disabled screen they just sit greyed out.
struct CustomColourRow: View {
    let title: String
    @Binding var raw: String
    let fallback: AppAccent
    let onLocked: (() -> Void)?

    private var isCustom: Bool { ThemeColour.isCustom(raw) }

    var body: some View {
        if !Premium.isUnlocked, let onLocked {
            Button(action: onLocked) {
                Label { Text(title).foregroundStyle(.primary) } icon: { Image(systemName: "lock.fill") }
            }
            .accessibilityLabel("\(title), needs Even Leanrrr")
        } else {
            ColorPicker(selection: Binding(
                // The picked value itself, not the readable shade, so nudging it starts from what was chosen.
                get: { ThemeColour.rgb(raw).map { Color(red: $0.r, green: $0.g, blue: $0.b) } ?? fallback.color },
                set: { raw = ThemeColour.hex(from: $0) }
            ), supportsOpacity: false) {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                        if isCustom {
                            Text(ThemeColour.isAdjusted(raw) ? "\(raw) · adjusted to stay readable" : raw)
                                .font(.roboto(.caption)).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                } icon: {
                    Image(systemName: isCustom ? "checkmark.circle.fill" : "eyedropper")
                }
            }
            .accessibilityValue(isCustom ? "Chosen, \(raw)" : "Not chosen")
        }
    }
}

extension ThemeColour {
    /// A short note when a custom colour is shown a shade darker or lighter than picked, so text stays readable.
    static func lightWarning(_ raw: String) -> String? {
        guard isAdjusted(raw) else { return nil }
        return "Leanrrr shows it a shade darker or lighter where needed so text stays easy to read."
    }
}

struct MacroColourSettings: View {
    @AppStorage(MacroColours.proteinKey) private var protein = "blue"
    @AppStorage(MacroColours.carbsKey) private var carbs = "orange"
    @AppStorage(MacroColours.fatKey) private var fat = "red"
    var body: some View {
        LeanrList {
            if !Premium.isUnlocked { Section { PremiumPromptRow(message: "Separate macro colours come with Even Leanrrr.") } }
            Group {
                swatches("Protein", key: "p", selection: $protein)
                swatches("Carbs", key: "c", selection: $carbs)
                swatches("Fat", key: "f", selection: $fat)
                Section {
                    Button("Reset to default colours") { protein = "blue"; carbs = "orange"; fat = "red" }
                } footer: {
                    Text("Choose separate colours for your macros in Leanrrr and its widgets.")
                }
            }.disabled(!Premium.isUnlocked)
        }.navigationTitle("Target colours")
    }
    /// Real colour swatches, like App colour: a menu picker redraws its icons in the tint colour, so every choice looked the same.
    private func swatches(_ title: String, key: String, selection: Binding<String>) -> some View {
        let current = MacroColours.colour(key, choices: [key: selection.wrappedValue])
        let name = AppAccent(rawValue: selection.wrappedValue)?.name ?? (ThemeColour.isCustom(selection.wrappedValue) ? "Custom" : "")
        let fallback: AppAccent = key == "p" ? .blue : key == "c" ? .orange : .red
        return Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 16) {
                ForEach(AppAccent.allCases) { colour in
                    let chosen = colour.rawValue == selection.wrappedValue
                    Button { selection.wrappedValue = colour.rawValue } label: {
                        Circle().fill(colour.color).frame(width: 36, height: 36)
                            .overlay { if chosen { Image(systemName: "checkmark").fontWeight(.bold).foregroundStyle(.white) } }
                            .background { Circle().strokeBorder(colour.color, lineWidth: 2).padding(-5).opacity(chosen ? 1 : 0) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title), \(colour.name)").accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }.padding(.vertical, 8)
            CustomColourRow(title: "Custom \(title.lowercased()) colour", raw: selection, fallback: fallback, onLocked: nil)
        } header: {
            HStack(spacing: 6) {
                Text(title)
                Spacer()
                Circle().fill(current).frame(width: 10, height: 10)
                Text(name).textCase(nil)
            }
        }
    }
}

/// Reminders to log food: breakfast, lunch, dinner and late night, each ticked on and timed separately.
struct ReminderSettings: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var denied = false
    /// Bumped to redraw after a setting is saved, since the settings live in UserDefaults.
    @State private var revision = 0
    var body: some View {
        LeanrList {
            let _ = revision
            if !Premium.isUnlocked { Section { PremiumPromptRow(message: "Choosing your meal and water reminders comes with Even Leanrrr.") } }
            Group {
                if !MealReminders.allOn {
                    Section {
                        Button {
                            Task {
                                if await MealReminders.enableAll() { reload() } else { denied = true }
                            }
                        } label: { Label("Turn on all reminders", systemImage: "bell.badge") }
                    } footer: { Text("Breakfast, lunch, dinner, late night and water at their usual times. Change any of them below.") }
                }
                ForEach(MealReminders.meals) { meal in
                    Section {
                        Toggle(MealReminders.title(meal), isOn: Binding(get: { MealReminders.isOn(meal) }, set: { on in
                            if on {
                                Task {
                                    if await MealReminders.requestPermission() { save(MealReminders.enabledKey(meal), true) } else { denied = true }
                                }
                            } else { save(MealReminders.enabledKey(meal), false) }
                        }))
                        if MealReminders.isOn(meal) {
                            DatePicker("Remind me at", selection: Binding(get: { time(MealReminders.minutes(meal)) }, set: { date in
                                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                                save(MealReminders.timeKey(meal), (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
                            }), displayedComponents: .hourAndMinute)
                        }
                    } footer: {
                        if meal == .snacks { Text("A last nudge, only if you haven't logged anything at all today.") }
                    }
                }
                Section {
                    Text("Leanrrr only reminds you if nothing has been logged to that meal by then. Log it and today's reminder is cancelled. The wording changes from day to day.")
                        .font(.roboto(.subheadline)).foregroundStyle(.secondary)
                } footer: {
                    if !Premium.isUnlocked { Label("Choosing which meals remind you, and when, comes with Even Leanrrr.", systemImage: "lock.fill") }
                }
                Section {
                    Toggle("Water", isOn: Binding(get: { MealReminders.waterOn }, set: { on in
                        if on {
                            Task {
                                if await MealReminders.requestPermission() { save(MealReminders.waterOnKey, true) } else { denied = true }
                            }
                        } else { save(MealReminders.waterOnKey, false) }
                    }))
                    if MealReminders.waterOn {
                        let schedule = MealReminders.waterSchedule
                        DatePicker("From", selection: Binding(get: { time(schedule.from) }, set: { date in
                            let minutes = minutesOfDay(date)
                            save(MealReminders.waterFromKey, minutes)
                            // The end never sits before the start.
                            if schedule.until < minutes { UserDefaults.standard.set(min(minutes + 60, 23 * 60 + 59), forKey: MealReminders.waterUntilKey) }
                        }), displayedComponents: .hourAndMinute)
                        DatePicker("Until", selection: Binding(get: { time(schedule.until) }, set: { date in
                            save(MealReminders.waterUntilKey, max(minutesOfDay(date), schedule.from))
                        }), displayedComponents: .hourAndMinute)
                        Picker("Every", selection: Binding(get: { schedule.everyHours }, set: { save(MealReminders.waterEveryKey, $0) })) {
                            ForEach(MealReminders.WaterSchedule.hourChoices, id: \.self) { Text($0 == 1 ? "Hour" : "\($0) hours").tag($0) }
                        }
                    }
                } footer: { Text("Spaced through the day. Once you've reached your water target, the rest of that day's water reminders are dropped.") }
            }.disabled(!Premium.isUnlocked)
            Section {
                Toggle("Weekly review", isOn: Binding(get: { MealReminders.weeklyOn }, set: { on in
                    if on {
                        Task { if await MealReminders.requestPermission() { save(MealReminders.weeklyKey, true) } else { denied = true } }
                    } else { save(MealReminders.weeklyKey, false) }
                }))
                if MealReminders.weeklyOn {
                    DatePicker("Sundays at", selection: Binding(get: { time(weeklyMinutes) }, set: { save(MealReminders.weeklyTimeKey, minutesOfDay($0)) }),
                               displayedComponents: .hourAndMinute)
                        .disabled(!Premium.isUnlocked)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sundays at \(time(weeklyMinutes).formatted(date: .omitted, time: .shortened)): days logged, average calories, protein days and your weight trend.")
                    if !Premium.isUnlocked { Label("Choosing the time comes with Even Leanrrr.", systemImage: "lock.fill") }
                }
            }
        }
        .navigationTitle("Reminders")
        .alert("Notifications are off for Leanrrr", isPresented: $denied) {
            Button("Open Settings") { if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Turn on notifications for Leanrrr in the Settings app to get reminders.") }
    }
    private var weeklyMinutes: Int { MealReminders.weeklyMinutes(unlocked: Premium.isUnlocked) }
    private func time(_ minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }
    private func minutesOfDay(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
    private func save(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
        reload()
    }
    private func reload() {
        revision += 1
        MealReminders.refresh(store.data, goals: store.goals, logReminders: Premium.isUnlocked)
    }
}

/// Showing foods others shared, and bringing back people or foods you hid.
struct SharedFoodsSection: View {
    private var community: CommunityFoods { AppServices.community }
    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { community.show }, set: { on in
                community.show = on
                if on { Task { await community.refresh(force: true) } }
            })) { Label("Show foods others shared", systemImage: "person.2") }
            if community.show {
                if let problem = community.problem {
                    Text(problem).font(.roboto(.caption)).foregroundStyle(.orange)
                } else if let last = community.lastRefreshed {
                    LabeledContent("Updated", value: last.formatted(.relative(presentation: .named)))
                }
                Button("Update now") { Task { await community.refresh(force: true) } }.disabled(community.refreshing)
            }
            let hidden = community.blocked.count + community.reported.count
            if hidden > 0 {
                Button("Show hidden people and reported foods again (\(hidden))") { community.unblockEveryone() }
            }
        } header: { Text("Shared foods") } footer: {
            Text("Foods other Leanrrr users share show up in search marked Community, and when you scan their barcode. Leanrrr doesn't check them. To share one of yours, turn on sharing when you add or edit it in My foods.")
        }
    }
}
