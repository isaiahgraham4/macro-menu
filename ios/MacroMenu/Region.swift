import Foundation

/// The country whose restaurant menus Leanr shows, chosen in setup and in Settings. Each has its own bundled menu file;
/// supermarket ready meals (Coles and Woolworths) and Copycat Kitchen exist only for Australia.
/// Logged meals, saved meals and your own foods are copies, so they're kept whichever country is chosen.
enum MenuRegion: String, CaseIterable, Identifiable, Sendable {
    case australia = "AU"
    case newZealand = "NZ"
    case unitedStates = "US"
    case canada = "CA"
    case unitedKingdom = "GB"
    case southAfrica = "ZA"
    case india = "IN"

    var id: String { rawValue }
    var name: String {
        switch self {
        case .australia: "Australia"
        case .newZealand: "New Zealand"
        case .unitedStates: "United States"
        case .canada: "Canada"
        case .unitedKingdom: "United Kingdom"
        case .southAfrica: "South Africa"
        case .india: "India"
        }
    }
    /// Short name for "Bundled … menu data": "Australian", "US".
    var menuLabel: String {
        switch self {
        case .australia: "Australian"
        case .newZealand: "New Zealand"
        case .unitedStates: "US"
        case .canada: "Canadian"
        case .unitedKingdom: "UK"
        case .southAfrica: "South African"
        case .india: "Indian"
        }
    }
    /// What this country's chain ids start with ("us-mcd", "ca-mcd"); Australia's ids have none ("mcd").
    var chainPrefix: String {
        switch self {
        case .australia: ""
        case .newZealand: "nz-"
        case .unitedStates: "us-"
        case .canada: "ca-"
        case .unitedKingdom: "uk-"
        case .southAfrica: "za-"
        case .india: "in-"
        }
    }
    /// Bundled menu file: `MenuData.json` (`Scripts/export-menu.cjs`), `MenuData-US.json` (`Scripts/us/build-us-menu.py`), or
    /// `MenuData-CA.json`, `-GB`, `-NZ`, `-ZA` and `-IN` (`Scripts/intl/build-intl-menu.py`).
    var menuFile: String { self == .australia ? "MenuData" : "MenuData-\(rawValue)" }
    var menuURL: URL? { Bundle.main.url(forResource: menuFile, withExtension: "json") }
    var hasSupermarkets: Bool { self == .australia }
    var supermarketURL: URL? { hasSupermarkets ? Bundle.main.url(forResource: "SupermarketFoods", withExtension: "json") : nil }
    /// Copycat Kitchen compares home recipes with Australian menu items.
    var hasCopycatKitchen: Bool { self == .australia }
    /// Open Food Facts' tag for products sold here, searched before the rest of the world.
    var openFoodFactsCountry: String {
        switch self {
        case .australia: "en:australia"
        case .newZealand: "en:new-zealand"
        case .unitedStates: "en:united-states"
        case .canada: "en:canada"
        case .unitedKingdom: "en:united-kingdom"
        case .southAfrica: "en:south-africa"
        case .india: "en:india"
        }
    }
    /// The App Store country chains' ordering apps are linked in.
    var appStoreCountry: String { self == .unitedKingdom ? "gb" : rawValue.lowercased() }
    /// What Sources says about the bundled menu.
    var menuNote: String {
        switch self {
        case .australia: "Bundled Australian menu snapshot from 24 September 2026."
        case .unitedStates: "Bundled US menu snapshot from 12–14 November 2026, from each chain’s own published nutrition."
        case .newZealand, .canada, .unitedKingdom: "Bundled \(menuLabel) menu snapshot from 14 November 2026, from each chain’s own published nutrition."
        case .southAfrica, .india: "Bundled \(menuLabel) menu snapshot from 20 November 2026, from each chain’s own published nutrition."
        }
    }
    /// The example under Find's Ask box.
    var askExample: String {
        switch self {
        case .australia: "Ask Leanrrr: 40 g protein at Nando's"
        case .newZealand: "Ask Leanrrr: 40 g protein at McDonald's"
        case .unitedStates: "Ask Leanrrr: 40 g protein at Chick-fil-A"
        case .canada: "Ask Leanrrr: 40 g protein at Tim Hortons"
        case .unitedKingdom: "Ask Leanrrr: 30 g protein at Greggs"
        case .southAfrica: "Ask Leanrrr: 40 g protein at Nando's"
        case .india: "Ask Leanrrr: 30 g protein at KFC"
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
        case .canada: [("ca-bk:triple-whopper", "Burger only · no sides or drink"),
                       ("ca-mcd:poutine-large", "Large poutine · no burger or drink"),
                       ("ca-mcd:big-mac", "Burger only · no sides or drink")]
        case .unitedKingdom: [("uk-mcd:double-quarter-pounder-with-cheese", "Burger only · no sides or drink"),
                              ("uk-greggs:steak-bake", "One bake · no drink"),
                              ("uk-mcd:chicken-selects-5-pc", "5 pieces · no sauce, sides or drink")]
        case .newZealand: [("nz-mcd:double-quarter-pounder-w-cheese", "Burger only · no sides or drink"),
                           ("nz-dominos:mega-meatlovers-classic-crust-slice", "One slice of a large classic crust"),
                           ("nz-mcd:chicken-mcnuggets-20-pc", "20 nuggets · no sauce, sides or drink")]
        case .southAfrica: [("za-nandos:1-2-chicken", "Half chicken · no sides or drink"),
                            ("za-mcd:mcfeast", "Burger only · no sides or drink"),
                            ("za-wimpy:mega-breakfast", "As plated · no drink")]
        case .india: [("in-mcd:veg-maharaja-mac", "Burger only · no sides or drink"),
                      ("in-kfc:hot-crispy-chicken-2-pc", "2 pieces · no sides or drink"),
                      ("in-pizzahut:margherita-pizza-medium-pan", "A whole medium pan pizza, 6 slices")]
        }
    }

    static let key = "leanr.region"
    /// The country chosen, or Australia for anyone who set up before there was a choice.
    static var saved: MenuRegion {
        UserDefaults.standard.string(forKey: key).flatMap(MenuRegion.init(rawValue:)) ?? .australia
    }
    /// What setup offers first: the phone's own region when it's one Leanr has menus for.
    static var suggested: MenuRegion {
        switch Locale.current.region?.identifier {
        case "US": .unitedStates
        case "NZ": .newZealand
        case "CA": .canada
        case "GB": .unitedKingdom
        case "ZA": .southAfrica
        case "IN": .india
        default: .australia
        }
    }

    /// A chain id from the nickname tables (written with Australian ids) in the menu in use: "mcd" is "us-mcd" in the US menu.
    /// Hungry Jack's is Burger King everywhere else ("hj" finds "us-bk").
    static func chain(_ id: String, in chainNames: [String: String]) -> String? {
        if chainNames[id] != nil { return id }
        let bare = allCases.map(\.chainPrefix).filter { !$0.isEmpty }.reduce(id) { $0.hasPrefix($1) ? String($0.dropFirst($1.count)) : $0 }
        for prefix in allCases.map(\.chainPrefix) where !prefix.isEmpty {
            for candidate in bare == "hj" ? ["hj", "bk"] : [bare] where chainNames[prefix + candidate] != nil { return prefix + candidate }
        }
        return nil
    }
}
