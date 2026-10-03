import Foundation

/// Whether a restaurant is likely to deliver to you, from how far away it is and whether it's open.
/// Delivery apps don't let other apps check an address, so this is an estimate: they usually deliver within about 5 km,
/// sometimes up to about 8 km. The delivery app has the final say once it sees your address.
enum Delivery: Equatable, Sendable {
    case likely(metres: Double)
    case maybe(metres: Double)
    case tooFar
    /// Closed now, so nothing delivers until it opens.
    case closed

    static let likelyWithin = 5_000.0
    static let maybeWithin = 8_000.0

    /// `metres` is nil when there's no restaurant of that chain nearby; `status` is nil when hours aren't known.
    static func estimate(metres: Double?, status: PlaceHours.Status?) -> Delivery {
        guard let metres, metres <= maybeWithin else { return .tooFar }
        if case .closed = status { return .closed }
        return metres <= likelyWithin ? .likely(metres: metres) : .maybe(metres: metres)
    }

    var text: String {
        switch self {
        case .likely: "Delivery likely"
        case .maybe: "Delivery may reach you"
        case .tooFar: "Probably too far to deliver"
        case .closed: "Closed, so no delivery right now"
        }
    }

    var available: Bool { if case .likely = self { true } else if case .maybe = self { true } else { false } }
}

/// A delivery app to check and order in. Links open the app when it's installed, otherwise its website.
struct DeliveryApp: Identifiable, Sendable {
    let name: String
    let search: @Sendable (String) -> URL?
    var id: String { name }

    static let all: [DeliveryApp] = [
        DeliveryApp(name: "Uber Eats") { query in
            var parts = URLComponents(string: "https://www.ubereats.com/au/search")
            parts?.queryItems = [URLQueryItem(name: "q", value: query)]
            return parts?.url
        },
        DeliveryApp(name: "DoorDash") { query in
            query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed).flatMap { URL(string: "https://www.doordash.com/search/store/\($0)/") }
        },
        // Menulog asks for your address before it can search.
        DeliveryApp(name: "Menulog") { _ in URL(string: "https://www.menulog.com.au/") },
    ]
}
