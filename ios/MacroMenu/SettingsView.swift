import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthSync.self) private var health
    @Environment(CloudSync.self) private var cloud
    @State private var healthFailed = false
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system
    @State private var showQuiz = false
    @State private var showPremium = false
    @State private var estimating = false
    @AppStorage(TodaySuggestions.storageKey) private var suggestFoods = true
    @AppStorage(AppAccent.storageKey) private var accentRaw = AppAccent.standard.rawValue
    @AppStorage(AppIconTheme.storageKey) private var iconRaw = AppIconTheme.black.rawValue
    private var current: AppAccent { AppAccent.resolved(accentRaw) }
    private var currentIcon: AppIconTheme { AppIconTheme(rawValue: iconRaw) ?? .black }
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
                            Label("Even Leanr", systemImage: Premium.isUnlocked ? "checkmark.seal.fill" : "sparkles")
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
                Text("System follows your device’s appearance and changes automatically with it.")
                    .font(.roboto(.caption)).foregroundStyle(.secondary)
            }
            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 16) {
                    ForEach(AppAccent.allCases) { accent in
                        let locked = !Premium.isUnlocked && accent != AppAccent.standard
                        // A locked colour opens Premium instead of doing nothing.
                        Button { if locked { showPremium = true } else { accentRaw = accent.rawValue } } label: {
                            Circle().fill(accent.color).frame(width: 36, height: 36)
                                .overlay {
                                    if accent == current { Image(systemName: "checkmark").fontWeight(.bold).foregroundStyle(.white) }
                                    else if locked { Image(systemName: "lock.fill").font(.roboto(.caption)).foregroundStyle(.white) }
                                }
                                .background { Circle().strokeBorder(accent.color, lineWidth: 2).padding(-5).opacity(accent == current ? 1 : 0) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(locked ? "\(accent.name), needs Even Leanr" : accent.name)
                        .accessibilityAddTraits(accent == current ? .isSelected : [])
                    }
                }.padding(.vertical, 8)
            } header: {
                Text("App colour")
            } footer: {
                if Premium.isUnlocked { Text("\(current.name) · Changes buttons, tabs, links and progress bars.") }
                else { Label("More colours come with Even Leanr.", systemImage: "lock.fill") }
            }
            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 14) {
                    ForEach(AppIconTheme.allCases) { icon in
                        let locked = !Premium.isUnlocked && icon != .black
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
                        .accessibilityLabel(locked ? "\(icon.name) app icon, needs Even Leanr" : "\(icon.name) app icon")
                        .accessibilityAddTraits(icon == currentIcon ? .isSelected : [])
                    }
                }.padding(.vertical, 8)
            } header: {
                Text("App icon")
            } footer: {
                Text(Premium.isUnlocked ? "\(currentIcon.name)" : "\(currentIcon.name) · More icon packs come with Even Leanr.")
            }
            Section("Targets") {
                NavigationLink { TargetsView() } label: { Label("Targets & target sets", systemImage: "target") }
                Button { estimating = true } label: { Label("Calculate my macros", systemImage: "function") }
                NavigationLink { WaterSettings() } label: { Label("Water target", systemImage: "drop") }
                Toggle(isOn: $suggestFoods) { Label("Suggest foods for what's left", systemImage: "lightbulb") }
                NavigationLink { MacroColourSettings() } label: { Label("Target colours", systemImage: "paintpalette") }
                NavigationLink { ReminderSettings() } label: { Label("Meal reminders", systemImage: "bell") }
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
                Text("Saves the food you log and your weigh-ins to Health, and reads your weight and active energy. To choose exactly what Leanr can read or write, open the Health app → your profile → Apps → Leanr.")
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
            BackupSection()
            Section("About") {
                LabeledContent("App", value: "Leanr")
                LabeledContent("Developer", value: AppInfo.developer)
                if let email = AppInfo.contactEmail, let url = URL(string: "mailto:\(email)") {
                    Link(destination: url) { LabeledContent("Contact", value: email) }
                }
                Button("Play the calorie quiz") { showQuiz = true }
                NavigationLink { SourcesView() } label: { Label("Menu sources", systemImage: "info.circle") }
                LabeledContent("Menu updated", value: menuDate)
                LabeledContent("Version", value: version)
            }
            Section("Privacy and legal") {
                NavigationLink { LegalDocumentView(document: .privacy) } label: { Label("Privacy policy", systemImage: "hand.raised") }
                NavigationLink { LegalDocumentView(document: .terms) } label: { Label("Terms of use", systemImage: "doc.text") }
                NavigationLink { AcknowledgementsView() } label: { Label("Acknowledgements", systemImage: "text.book.closed") }
                NavigationLink { DeleteDataView() } label: { Label("Delete all my data", systemImage: "trash").foregroundStyle(.red) }
            }
        }.navigationTitle("Settings")
            .sheet(isPresented: $showQuiz) { LeanrOnboarding { showQuiz = false } }
            .sheet(isPresented: $showPremium) { PremiumView() }
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
}

struct MacroColourSettings: View {
    @AppStorage(MacroColours.proteinKey) private var protein = "blue"
    @AppStorage(MacroColours.carbsKey) private var carbs = "orange"
    @AppStorage(MacroColours.fatKey) private var fat = "red"
    var body: some View {
        LeanrList {
            if !Premium.isUnlocked { Section { PremiumPromptRow(message: "Separate macro colours come with Even Leanr.") } }
            Group {
                swatches("Protein", key: "p", selection: $protein)
                swatches("Carbs", key: "c", selection: $carbs)
                swatches("Fat", key: "f", selection: $fat)
                Section {
                    Button("Reset to default colours") { protein = "blue"; carbs = "orange"; fat = "red" }
                } footer: {
                    Text("Choose separate colours for your macros in Leanr and its widgets.")
                }
            }.disabled(!Premium.isUnlocked)
        }.navigationTitle("Target colours")
    }
    /// Real colour swatches, like App colour: a menu picker redraws its icons in the tint colour, so every choice looked the same.
    private func swatches(_ title: String, key: String, selection: Binding<String>) -> some View {
        let current = MacroColours.colour(key, choices: [key: selection.wrappedValue])
        let name = AppAccent(rawValue: selection.wrappedValue)?.name ?? ""
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
            if !Premium.isUnlocked { Section { PremiumPromptRow(message: "Choosing your meal reminders comes with Even Leanr.") } }
            Group {
                if !MealReminders.meals.allSatisfy(MealReminders.isOn) {
                    Section {
                        Button {
                            Task {
                                if await MealReminders.enableAll() { reload() } else { denied = true }
                            }
                        } label: { Label("Turn on all reminders", systemImage: "bell.badge") }
                    } footer: { Text("Breakfast, lunch, dinner and late night at their usual times. Change any of them below.") }
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
                    Text("Leanr only reminds you if nothing has been logged to that meal by then. Log it and today's reminder is cancelled. The wording changes from day to day.")
                        .font(.roboto(.subheadline)).foregroundStyle(.secondary)
                } footer: {
                    if !Premium.isUnlocked { Label("Choosing which meals remind you, and when, comes with Even Leanr.", systemImage: "lock.fill") }
                }
            }.disabled(!Premium.isUnlocked)
            Section {
                Toggle("Weekly review", isOn: Binding(get: { MealReminders.weeklyOn }, set: { on in
                    if on {
                        Task { if await MealReminders.requestPermission() { save(MealReminders.weeklyKey, true) } else { denied = true } }
                    } else { save(MealReminders.weeklyKey, false) }
                }))
            } footer: { Text("Sundays at 6 pm: days logged, average calories, protein days and your weight trend.") }
        }
        .navigationTitle("Meal reminders")
        .alert("Notifications are off for Leanr", isPresented: $denied) {
            Button("Open Settings") { if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Turn on notifications for Leanr in the Settings app to get meal reminders.") }
    }
    private func time(_ minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
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
