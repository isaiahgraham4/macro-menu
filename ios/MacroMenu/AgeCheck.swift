import SwiftUI
#if canImport(DeclaredAgeRange)
@preconcurrency import DeclaredAgeRange
#endif

/// Asks the App Store for the person's age category where the law requires apps to check it (Texas SB 2420 for new Texas
/// Apple Accounts; Utah and Louisiana from 2027), and keeps people under Leanrrr's minimum age of 13 out.
/// Nothing happens anywhere else: the App Store says when it applies (`requiredRegulatoryFeatures` from iOS 26.4,
/// `isEligibleForAgeFeatures` on 26.2 and 26.3). The category stays on this device and is used for nothing else.
///
/// Leanrrr's age rating must not change while this is all there is: Texas treats a new age rating as a significant change
/// that needs a parent's consent through PermissionKit's `SignificantAppUpdateTopic`, which isn't built (see AppStore/README.md).
enum AgeCheck {
    static let categoryKey = "age.category"
    static let checkedKey = "age.checked"

    static var saved: AgeCategory? { UserDefaults.standard.string(forKey: categoryKey).flatMap(AgeCategory.init(rawValue:)) }
}

extension View {
    /// Runs the age check once onboarding is done. Before iOS 26.2 there's no age signal to read, so nothing changes.
    func ageCheck(enabled: Bool) -> some View { modifier(AgeCheckModifier(enabled: enabled)) }
}

private struct AgeCheckModifier: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        #if canImport(DeclaredAgeRange)
        if #available(iOS 26.2, *) {
            content.modifier(RequiredAgeCheck(enabled: enabled))
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#if canImport(DeclaredAgeRange)
@available(iOS 26.2, *)
private struct RequiredAgeCheck: ViewModifier {
    let enabled: Bool
    @Environment(\.requestAgeRange) private var requestAgeRange
    @Environment(\.scenePhase) private var phase
    @AppStorage(AgeCheck.categoryKey) private var stored = ""
    @AppStorage(AgeCheck.checkedKey) private var checked = 0.0
    @State private var checking = false

    private var tooYoung: Bool { enabled && AgeCategory(rawValue: stored)?.meetsMinimumAge == false }

    func body(content: Content) -> some View {
        content
            .task(id: enabled) { await check() }
            .onChange(of: phase) { if phase == .active { Task { await check() } } }
            .fullScreenCover(isPresented: .constant(tooYoung)) {
                UnderAgeView(checking: checking) { Task { await check(force: true) } }
                    .interactiveDismissDisabled()
            }
    }

    /// Whether the law where this person's Apple Account is set up requires apps to check their age. Nil when the App Store
    /// can't say right now (offline), so nothing already saved is thrown away.
    @concurrent nonisolated private static func lawRequiresCheck() async -> Bool? {
        if #available(iOS 26.4, *) {
            return try? await AgeRangeService.shared.requiredRegulatoryFeatures.contains(.declaredAgeRangeRequired)
        }
        return try? await AgeRangeService.shared.isEligibleForAgeFeatures
    }

    private func check(force: Bool = false) async {
        guard enabled, !checking else { return }
        guard let required = await Self.lawRequiresCheck() else { return }
        guard required else {
            // The law no longer applies (another region, or an older account): forget any category from before.
            if !stored.isEmpty { stored = "" }
            return
        }
        if !force, Date().timeIntervalSince1970 - checked < AgeCategory.recheckEvery, !stored.isEmpty { return }
        checking = true; defer { checking = false }
        let (a, b, c) = AgeCategory.gates
        do {
            switch try await requestAgeRange(ageGates: a, b, c) {
            case .sharing(let range):
                stored = AgeCategory(lower: range.lowerBound, upper: range.upperBound)?.rawValue ?? ""
            case .declinedSharing:
                // Leanrrr can't tell, so it doesn't block anyone. It asks again the next day.
                stored = ""
            @unknown default:
                return
            }
            checked = Date().timeIntervalSince1970
        } catch {
            // No answer (offline, or the service isn't available): try again next time the app opens.
        }
    }
}
#endif

/// Shown instead of the app when the App Store says the person is under 13, Leanrrr's minimum age.
private struct UnderAgeView: View {
    let checking: Bool
    let checkAgain: () -> Void
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "person.badge.clock").font(.system(size: 54)).foregroundStyle(.secondary).accessibilityHidden(true)
            Text("Leanrrr is for people 13 and over").font(.display(.title2)).multilineTextAlignment(.center)
            Text("Your Apple Account says you're under 13, so Leanrrr can't be used on it. If that's wrong, a parent can change the age on your Apple Account, then check again.")
                .font(.roboto(.body)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(checking ? "Checking…" : "Check again", action: checkAgain)
                .buttonStyle(.borderedProminent).disabled(checking)
            Spacer()
        }
        .padding(32)
    }
}
