import SwiftUI

/// Settings → Suggestions: a restaurant to add, a feature, a menu fix. Sent to Leanrrr's Supabase project through
/// `rpc/suggest` (migration 005), which only adds rows; nothing can be read back with the publishable key. Only what the
/// person typed, the kind, the app version and the menu country go up: no account, device id or email.
enum Suggestions {
    enum Kind: String, CaseIterable, Identifiable {
        case restaurant, feature, fix, other
        var id: String { rawValue }
        var title: String {
            switch self {
            case .restaurant: "A restaurant to add"
            case .feature: "A feature idea"
            case .fix: "A menu or food fix"
            case .other: "Something else"
            }
        }
        var prompt: String {
            switch self {
            case .restaurant: "Which restaurant, and where? For example: Raising Cane's, Texas"
            case .feature: "What would you like Leanrrr to do?"
            case .fix: "Which food, and what looks wrong?"
            case .other: "What's on your mind?"
            }
        }
    }

    static let limit = 1000

    static func send(kind: Kind, text: String) async throws {
        guard let url = MenuUpdates.server?.appending(path: "rpc/suggest") else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue(MenuUpdates.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpShouldHandleCookies = false
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "kind": kind.rawValue, "body": String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit)),
            "app_version": version, "country": MenuRegion.saved.rawValue,
        ])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    }
}

struct SuggestionsView: View {
    @State private var kind: Suggestions.Kind = .restaurant
    @State private var text = ""
    @State private var sending = false
    @State private var sent = 0
    @State private var failed = false
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        LeanrList {
            Section {
                Picker("About", selection: $kind) {
                    ForEach(Suggestions.Kind.allCases) { Text($0.title).tag($0) }
                }
                TextField(kind.prompt, text: $text, axis: .vertical)
                    .lineLimit(4...10)
                    .focused($focused)
                    .onChange(of: text) { if text.count > Suggestions.limit { text = String(text.prefix(Suggestions.limit)) } }
            } header: { Text("Your suggestion") } footer: {
                if text.count > Suggestions.limit - 100 { Text("\(Suggestions.limit - text.count) characters left") }
            }
            Section {
                Button { Task { await send() } } label: {
                    HStack {
                        Label("Send suggestion", systemImage: "paperplane")
                        if sending { Spacer(); ProgressView() }
                    }
                }
                .disabled(trimmed.count < 3 || sending)
            } footer: {
                Text("Sent anonymously with your app version and which country's menus you use. Nothing else about you goes with it, so I can't reply here.")
            }
            if sent > 0 {
                Section {
                    Label(sent == 1 ? "Thanks, your suggestion was sent." : "Thanks, your \(sent) suggestions were sent.", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }
            if let email = AppInfo.contactEmail, let url = URL(string: "mailto:\(email)") {
                Section {
                    Link(destination: url) { LabeledContent("Email me", value: email) }
                } footer: { Text("Want a reply? Email me instead.") }
            }
        }
        .navigationTitle("Suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn't send that", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your internet connection and try again. Your suggestion is still here.")
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        do {
            try await Suggestions.send(kind: kind, text: trimmed)
            text = ""
            focused = false
            sent += 1
        } catch {
            failed = true
        }
    }
}
