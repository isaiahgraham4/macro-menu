import SwiftUI
import UserNotifications
import WidgetKit

/// Who makes Leanr, for the About screen and the policies.
enum AppInfo {
    static let developer = "Isaiah Graham"
    static let location = "Victoria, Australia"
    /// The support address shown in the policies and Settings. Set it before release; while it's nil the policies point
    /// to the App Store page instead and the Contact row is hidden.
    static let contactEmail: String? = nil

    static var contactText: String { contactEmail ?? "the App Support link on Leanr's App Store page" }
}

/// The privacy policy or terms, read from the Markdown files in `Legal/` (the same text to host for the App Store).
struct LegalDocumentView: View {
    enum Document: String { case privacy = "PrivacyPolicy", terms = "Terms" }
    let document: Document

    private var title: String { document == .privacy ? "Privacy policy" : "Terms of use" }

    private var blocks: [Block] {
        guard let url = Bundle.main.url(forResource: document.rawValue, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [.paragraph("This document couldn't be loaded.")] }
        return Block.parse(text.replacingOccurrences(of: "{{CONTACT}}", with: AppInfo.contactText))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .heading(let text):
                        Text(text).font(.roboto(.headline, weight: .bold)).padding(.top, 10).accessibilityAddTraits(.isHeader)
                    case .paragraph(let text):
                        Text(Block.inline(text)).font(.roboto(.body))
                    case .bullet(let text):
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•").accessibilityHidden(true)
                            Text(Block.inline(text))
                        }.font(.roboto(.body))
                    }
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background { LeanrBackground() }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    enum Block: Equatable {
        case heading(String), paragraph(String), bullet(String)

        /// Headings (`##`), bullets (`- `) and paragraphs. The `#` title line is left out; the screen has its own.
        static func parse(_ text: String) -> [Block] {
            text.components(separatedBy: .newlines).compactMap { line in
                let line = line.trimmingCharacters(in: .whitespaces)
                if line.isEmpty || line.hasPrefix("# ") { return nil }
                if line.hasPrefix("## ") { return .heading(String(line.dropFirst(3))) }
                if line.hasPrefix("- ") { return .bullet(String(line.dropFirst(2))) }
                return .paragraph(line)
            }
        }

        static func inline(_ text: String) -> AttributedString {
            (try? AttributedString(markdown: text)) ?? AttributedString(text)
        }
    }
}

/// Fonts, data sources and trademarks, with the licence texts the fonts require.
struct AcknowledgementsView: View {
    var body: some View {
        LeanrList {
            Section {
                Text("Leanr isn't affiliated with, endorsed by or sponsored by any restaurant or delivery service. Restaurant names and brands belong to their owners and are used only to identify their food.")
            } header: { Text("Restaurants") }
            Section {
                credit("Restaurant nutrition", "Each chain's published nutrition information. See Settings → Menu sources.")
                credit("Product data", "Open Food Facts, available under the Open Database License (ODbL).",
                       link: "https://world.openfoodfacts.org/terms-of-use")
                credit("Everyday foods", "U.S. Department of Agriculture, Agricultural Research Service. FoodData Central (SR Legacy), public domain.",
                       link: "https://fdc.nal.usda.gov")
                credit("Maps and opening hours", "Apple Maps.")
            } header: { Text("Data") }
            Section {
                licence("Roboto", "Copyright 2011 Google Inc. Apache License, Version 2.0.", file: "Apache-2.0")
                licence("Bebas Neue", "Copyright 2019 The Bebas Neue Project Authors. SIL Open Font License, Version 1.1.", file: "OFL-BebasNeue")
            } header: { Text("Fonts") }
            Section {
                Text("Leanr's icons are Apple's SF Symbols, used under Apple's licence for apps on its platforms.")
            } header: { Text("Icons") }
        }
        .navigationTitle("Acknowledgements")
    }

    private func credit(_ title: String, _ detail: String, link: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.roboto(.subheadline, weight: .semibold))
            Text(detail).font(.roboto(.subheadline)).foregroundStyle(.secondary)
            if let link, let url = URL(string: link) { Link("Licence", destination: url).font(.roboto(.subheadline)) }
        }
    }

    private func licence(_ name: String, _ detail: String, file: String) -> some View {
        NavigationLink {
            ScrollView {
                Text((Bundle.main.url(forResource: file, withExtension: "txt")).flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "")
                    .font(.system(.footnote, design: .monospaced)).textSelection(.enabled).padding(16)
            }.navigationTitle(name).navigationBarTitleDisplayMode(.inline)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.roboto(.subheadline, weight: .semibold))
                Text(detail).font(.roboto(.subheadline)).foregroundStyle(.secondary)
            }
        }
    }
}

/// Deletes everything Leanr keeps: on this device, the iCloud copy, and (if chosen) what it saved to Apple Health.
struct DeleteDataView: View {
    @Environment(AppStore.self) private var store
    @Environment(CloudSync.self) private var cloud
    @Environment(HealthSync.self) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var includeHealth = true
    @State private var confirming = false
    @State private var working = false
    @State private var result: String?

    var body: some View {
        LeanrList {
            Section {
                Text("This deletes your foods, recipes, saved meals, food log, meal plans, check-ins, weigh-ins, measurements, water, progress photos, targets, reminders and settings from this iPhone, and Leanr's copy in your iCloud. It can't be undone.")
                Text("Want a copy first? Export a backup in Settings.").foregroundStyle(.secondary)
            }
            if health.enabled {
                Section {
                    Toggle("Also delete what Leanr saved to Apple Health", isOn: $includeHealth)
                } footer: {
                    Text("Removes the food, water and weights Leanr wrote to Health. Weights from your scale or other apps stay.")
                }
            }
            Section {
                Button(role: .destructive) { confirming = true } label: {
                    HStack {
                        Label("Delete all my data", systemImage: "trash").foregroundStyle(.red)
                        if working { Spacer(); ProgressView() }
                    }
                }
                .disabled(working)
            } footer: {
                Text("iCloud sync is turned off on this iPhone afterwards, so copies on your other devices don't come back. Delete there too if Leanr is on another device. I don't hold any of your data, so there's nothing else to delete.")
            }
        }
        .navigationTitle("Delete all my data")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete everything?", isPresented: $confirming) {
            Button("Delete", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(includeHealth && health.enabled ? "Your Leanr data on this iPhone, in iCloud and in Apple Health will be deleted." : "Your Leanr data on this iPhone and in iCloud will be deleted.")
        }
        .alert("Your data is deleted", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil; dismiss() } })) {
            Button("OK") { result = nil; dismiss() }
        } message: { Text(result ?? "") }
    }

    private func delete() async {
        working = true; defer { working = false }
        let cloudDeleted = await cloud.deleteCopy()
        if includeHealth && health.enabled { await health.deleteEverythingSaved() }
        health.disconnect()
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests(); center.removeAllDeliveredNotifications()
        DataDeletion.clearSettings()
        guard store.eraseEverything() else { return }
        WidgetCenter.shared.reloadAllTimelines()
        result = cloudDeleted ? "Leanr has started fresh." : "Leanr has started fresh on this iPhone. iCloud couldn't be reached, so delete Leanr's folder in the Files app under iCloud Drive."
    }
}

enum DataDeletion {
    /// Clears saved settings and caches, keeping only that onboarding was seen and that iCloud sync is now off.
    @MainActor static func clearSettings() {
        let defaults = UserDefaults.standard
        if let domain = Bundle.main.bundleIdentifier { defaults.removePersistentDomain(forName: domain) }
        defaults.set(true, forKey: "leanr.onboarding.completed")
        defaults.set(false, forKey: CloudSync.enabledKey)
        for url in [WidgetCalories.fileURL, QuickLogQueue.fileURL].compactMap({ $0 }) { try? FileManager.default.removeItem(at: url) }
        ProgressPhotoFiles.standard.removeAll()
    }
}
