import Foundation

/// The country whose restaurant menus Leanr shows, chosen in setup and in Settings. Each has its own bundled menu file;
/// supermarket ready meals (Coles and Woolworths) and Copycat Kitchen exist only for Australia.
/// Logged meals, saved meals and your own foods are copies, so they're kept whichever country is chosen.
enum MenuRegion: String, CaseIterable, Identifiable, Sendable {
    case australia = "AU"
    case unitedStates = "US"

    var id: String { rawValue }
    var name: String { self == .australia ? "Australia" : "United States" }
    /// Bundled menu file: `MenuData.json` (`Scripts/export-menu.cjs`) or `MenuData-US.json` (`Scripts/us/build-us-menu.py`).
    var menuFile: String { self == .australia ? "MenuData" : "MenuData-US" }
    var menuURL: URL? { Bundle.main.url(forResource: menuFile, withExtension: "json") }
    var hasSupermarkets: Bool { self == .australia }
    var supermarketURL: URL? { hasSupermarkets ? Bundle.main.url(forResource: "SupermarketFoods", withExtension: "json") : nil }
    /// Copycat Kitchen compares home recipes with Australian menu items.
    var hasCopycatKitchen: Bool { self == .australia }
    /// Only the Australian menu is published online for updates between app versions (`MenuUpdates`).
    var updatesOnline: Bool { self == .australia }
    /// Open Food Facts' tag for products sold here, searched before the rest of the world.
    var openFoodFactsCountry: String { self == .australia ? "en:australia" : "en:united-states" }
    /// The App Store country chains' ordering apps are linked in.
    var appStoreCountry: String { self == .australia ? "au" : "us" }
    /// What Sources says about the bundled menu.
    var menuNote: String {
        switch self {
        case .australia: "Bundled Australian menu snapshot from 24 September 2026."
        case .unitedStates: "Bundled US menu snapshot from 12–13 November 2026, from each chain’s own published nutrition."
        }
    }

    /// The three meals setup asks people to guess, with what the serve leaves out.
    var quiz: [(id: String, note: String)] {
        switch self {
        case .australia: [("kfc:10-wicked-wings", "10 wings · no sides or drink"),
                          ("mcd:cheesy-double-quarter-pounder", "Burger only · no sides or drink"),
                          ("hj:triple-whopper-with-cheese", "Burger only · no sides or drink")]
        case .unitedStates: [("us-wendys:baconator", "Burger only · no sides or drink"),
                             ("us-mcd:double-quarter-pounder-with-cheese", "Burger only · no sides or drink"),
                             ("us-panda:the-original-orange-chicken", "One entrée serve · no rice, noodles or drink")]
        }
    }

    static let key = "leanr.region"
    /// The country chosen, or Australia for anyone who set up before there was a choice.
    static var saved: MenuRegion {
        UserDefaults.standard.string(forKey: key).flatMap(MenuRegion.init(rawValue:)) ?? .australia
    }
    /// What setup offers first: the phone's own region when it's one Leanr has menus for.
    static var suggested: MenuRegion { Locale.current.region?.identifier == "US" ? .unitedStates : .australia }

    /// A chain id from the nickname tables (written with Australian ids) in the menu in use: "mcd" is "us-mcd" in the US menu.
    static func chain(_ id: String, in chainNames: [String: String]) -> String? {
        if chainNames[id] != nil { return id }
        return chainNames["us-" + id] != nil ? "us-" + id : nil
    }
}
