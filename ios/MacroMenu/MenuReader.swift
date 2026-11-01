import UIKit
import Vision
import FoundationModels

/// Reads the text on photos of a menu with Apple Vision. It runs on the iPhone and sends nothing anywhere.
enum MenuReader {
    /// Enough for a folded menu, front and back; more would only slow the reading down.
    static let pageLimit = 6

    static func read(_ pages: [UIImage]) async throws -> MenuParser.Result {
        var lines: [MenuLine] = []
        for (page, image) in pages.prefix(pageLimit).enumerated() {
            guard let upright = upright(image) else { continue }
            lines += try await Task.detached(priority: .userInitiated) { try text(in: upright, page: page) }.value
        }
        return MenuParser.read(lines)
    }

    static func text(in image: CGImage, page: Int) throws -> [MenuLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Menus borrow from these, and English alone turns "gnocchi" into something else.
        request.recognitionLanguages = ["en-US", "it-IT", "fr-FR", "es-ES"]
        request.minimumTextHeight = 0.006
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            return MenuLine(text: text, x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height, page: page)
        }
    }

    /// The photo the right way up, big enough for a menu's small print.
    private static func upright(_ image: UIImage) -> CGImage? {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > 3000 ? 3000 / longest : 1
        let target = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }.cgImage
    }
}

/// Apple Intelligence's idea of what's in a dish Takeawise can't place. It only says what's in it and how much; the figures
/// come from Takeawise's foods. Nothing where the iPhone doesn't have it, and then the dish keeps what it had.
enum MenuModel {
    static var isAvailable: Bool { MealWords.isAvailable }

    /// Only so many, since each takes a few seconds; the rest keep their rough figure.
    static let dishLimit = 12

    static func ingredients(of dish: MenuDish) async -> [(name: String, grams: Double)] {
        guard isAvailable, #available(iOS 26.0, *) else { return [] }
        return (try? await contents(of: dish)) ?? []
    }

    @available(iOS 26.0, *)
    @Generable(description: "What one restaurant serve of a dish is made of")
    struct Contents {
        @Guide(description: "The main ingredients, largest first. Leave out salt, herbs, spices and water.", .maximumCount(8))
        var ingredients: [Item]

        @Generable(description: "One ingredient")
        struct Item {
            @Guide(description: "A plain ingredient someone would search a food diary for: \"chicken thigh\", \"white rice\", \"coconut milk\".")
            var name: String
            @Guide(description: "Grams of it in one restaurant serve", .range(5...500))
            var grams: Int
        }
    }

    @available(iOS 26.0, *)
    private static func contents(of dish: MenuDish) async throws -> [(name: String, grams: Double)] {
        let session = LanguageModelSession(instructions: """
            You work out what a dish on a restaurant menu is usually made of, for a food diary. \
            Give the main ingredients of one serve and how many grams of each. \
            Never estimate calories or nutrients. If the words aren't a dish, return an empty list.
            """)
        let about = [dish.name, dish.details, dish.section.map { "Listed under \($0)." } ?? ""].filter { !$0.isEmpty }.joined(separator: ". ")
        let response = try await session.respond(to: "What's in this dish? \"\(about)\"", generating: Contents.self)
        return response.content.ingredients.map { (name: $0.name, grams: Double($0.grams)) }
    }
}
