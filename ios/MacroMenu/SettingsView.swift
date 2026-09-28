import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthSync.self) private var health
    @Environment(CloudSync.self) private var cloud
    @State private var healthFailed = false
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system
    @State private var showQuiz = false
    @AppStorage(AppAccent.storageKey) private var accentRaw = AppAccent.standard.rawValue
    @AppStorage(AppIconTheme.storageKey) private var iconRaw = AppIconTheme.black.rawValue
    private var current: AppAccent { AppAccent.resolved(accentRaw) }
    private var currentIcon: AppIconTheme { AppIconTheme(rawValue: iconRaw) ?? .black }
    var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }
    var body: some View {
        LeanrList {
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.name).tag(option)
                    }
                }
                Text("System follows your device’s appearance and changes automatically with it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 16) {
                    ForEach(AppAccent.allCases) { accent in
                        let locked = !Premium.isUnlocked && accent != AppAccent.standard
                        Button { accentRaw = accent.rawValue } label: {
                            Circle().fill(accent.color).frame(width: 36, height: 36)
                                .overlay {
                                    if accent == current { Image(systemName: "checkmark").fontWeight(.bold).foregroundStyle(.white) }
                                    else if locked { Image(systemName: "lock.fill").font(.roboto(.caption)).foregroundStyle(.white) }
                                }
                                .background { Circle().strokeBorder(accent.color, lineWidth: 2).padding(-5).opacity(accent == current ? 1 : 0) }
                        }
                        .buttonStyle(.plain).disabled(locked)
                        .accessibilityLabel(accent.name).accessibilityAddTraits(accent == current ? .isSelected : [])
                    }
                }.padding(.vertical, 8)
            } header: {
                Text("App colour")
            } footer: {
                if Premium.isUnlocked { Text("\(current.name) · Changes buttons, tabs, links and progress bars.") }
                else { Label("More colours come with Premium.", systemImage: "lock.fill") }
            }
            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 14) {
                    ForEach(AppIconTheme.allCases) { icon in
                        let locked = !Premium.isUnlocked && icon != .black
                        Button { selectIcon(icon) } label: {
                            VStack(spacing: 6) {
                                Image(icon.previewAsset)
                                    .resizable().scaledToFill().frame(width: 66, height: 66)
                                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                                    .overlay {
                                        if locked { Image(systemName: "lock.fill").foregroundStyle(.white).shadow(radius: 3) }
                                    }
                                    .overlay { RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(icon == currentIcon ? Color.accentColor : .clear, lineWidth: 3) }
                                Text(icon.name).font(.caption.weight(.medium))
                            }
                        }
                        .buttonStyle(.plain).disabled(locked)
                        .accessibilityLabel("\(icon.name) app icon")
                        .accessibilityAddTraits(icon == currentIcon ? .isSelected : [])
                    }
                }.padding(.vertical, 8)
            } header: {
                Text("App icon")
            } footer: {
                Text("\(currentIcon.name) · More icon packs will be part of Premium when it launches.")
            }
            Section("Targets") {
                NavigationLink { TargetsView() } label: { Label("Targets & target sets", systemImage: "target") }
                NavigationLink { WeightView() } label: { Label("Weight log", systemImage: "scalemass") }
                NavigationLink { MacroColourSettings() } label: { Label("Target colours", systemImage: "paintpalette") }
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
                        Text(problem).font(.caption).foregroundStyle(.orange)
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
                Button("Play the calorie quiz") { showQuiz = true }
                NavigationLink { SourcesView() } label: { Label("Menu sources", systemImage: "info.circle") }
                LabeledContent("Version", value: version)
            }
        }.navigationTitle("Settings")
            .sheet(isPresented: $showQuiz) { LeanrOnboarding { showQuiz = false } }
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
            Section {
                picker("Protein", selection: $protein)
                picker("Carbs", selection: $carbs)
                picker("Fat", selection: $fat)
                Button("Reset to default colours") { protein = "blue"; carbs = "orange"; fat = "red" }
            } footer: {
                Text("Choose separate colours for your macros in Leanr and its widgets. This will be a Premium feature when subscriptions launch.")
            }.disabled(!Premium.isUnlocked)
        }.navigationTitle("Target colours")
    }
    private func picker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(AppAccent.allCases) { colour in
                Label { Text(colour.name) } icon: { Image(systemName: "circle.fill").foregroundStyle(colour.color) }
                    .tag(colour.rawValue)
            }
        }
    }
}
