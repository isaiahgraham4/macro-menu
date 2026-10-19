import SwiftUI

/// Settings → Meal photos: read photos with the person's own AI key instead of only the readers on the phone.
struct PhotoReadingSettings: View {
    @AppStorage(CloudVision.enabledKey) private var enabled = false
    @AppStorage(CloudVision.providerKey) private var providerRaw = CloudVision.Provider.gemini.rawValue
    @AppStorage(CloudVision.modelKey) private var model = ""
    @Environment(\.openURL) private var openURL
    @State private var keyText = ""
    @State private var hasKey = false
    @State private var checking = false
    @State private var status: String?
    @State private var failed = false

    private var provider: CloudVision.Provider { CloudVision.Provider(rawValue: providerRaw) ?? .gemini }
    private var chosenModel: String { provider.models.contains(model) ? model : provider.models[0] }

    var body: some View {
        LeanrForm {
            Section {
                Toggle("Use my own AI key", isOn: $enabled)
            } footer: {
                Text("Off: your iPhone names the foods and nothing leaves it. On: each meal photo goes straight from your iPhone to the AI service below, using your key and under their terms. Leanr never receives it, and your provider bills you, not Leanr. If the service can't be reached, your iPhone reads the photo instead.")
            }
            Section {
                Picker("Service", selection: $providerRaw) {
                    ForEach(CloudVision.Provider.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Model", selection: Binding(get: { chosenModel }, set: { model = $0 })) {
                    ForEach(provider.models, id: \.self) { Text($0).tag($0) }
                }
                if hasKey {
                    LabeledContent("API key", value: "Saved on this iPhone")
                    Button("Remove key", role: .destructive) {
                        Keychain.delete(provider.rawValue); hasKey = false; status = nil
                    }
                } else {
                    SecureField("Paste your API key", text: $keyText).textContentType(.password).autocorrectionDisabled().textInputAutocapitalization(.never)
                    Button(checking ? "Checking…" : "Check and save key") { save() }
                        .disabled(checking || keyText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button("Get a \(provider.title) key", systemImage: "arrow.up.right.square") { openURL(provider.keyPage) }
            } header: { Text("Service") } footer: {
                Text(status ?? (provider == .gemini
                                ? "Google offers a free tier for Gemini keys, enough for everyday meal photos."
                                : "Keys are kept in this iPhone's Keychain, never in your Leanr data, iCloud or backups."))
                    .foregroundStyle(failed ? .red : .secondary)
            }
        }
        .navigationTitle("Meal photos").navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
        .onChange(of: providerRaw) { keyText = ""; status = nil; failed = false; refresh() }
    }

    private func refresh() { hasKey = Keychain.read(provider.rawValue) != nil }

    /// Tries the key with a tiny request before keeping it, so a typo shows now rather than on the next photo.
    private func save() {
        let key = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
        checking = true; status = nil; failed = false
        let provider = provider, model = chosenModel
        Task {
            do {
                try await CloudVision.check(provider, model: model, key: key)
                Keychain.save(key, for: provider.rawValue)
                keyText = ""; hasKey = true; enabled = true
                status = "Key works and is saved. Meal photos now go to \(provider.title)."
            } catch {
                failed = true
                status = "That key didn't work: \(error.localizedDescription)"
            }
            checking = false
        }
    }
}
