import Foundation
import CoreGraphics
import ImageIO
import Security
import UniformTypeIdentifiers

/// Meal photos read by an AI service the person picks, with their own API key ("bring your own key").
/// Off by default. When it's on, the photo goes straight from the iPhone to that provider, under the provider's terms;
/// Leanr has no server and never receives it, and the person's provider bills them, not Leanr. Like the readers on the
/// phone, it only says which foods are there and roughly how much: the figures always come from Leanr's own data.
enum CloudVision {
    enum Provider: String, CaseIterable, Identifiable, Sendable {
        case gemini, openai, anthropic
        var id: Self { self }
        var title: String {
            switch self {
            case .gemini: "Google Gemini"
            case .openai: "OpenAI"
            case .anthropic: "Anthropic Claude"
            }
        }
        /// Models that read images, the suggested one first. Gemini's cheapest model has a free tier.
        var models: [String] {
            switch self {
            case .gemini: ["gemini-3.5-flash-lite", "gemini-3.8-flash", "gemini-flash-latest"]
            case .openai: ["gpt-5.4-mini", "gpt-6-luna", "gpt-5.4-nano"]
            case .anthropic: ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"]
            }
        }
        /// Where to make a key.
        var keyPage: URL {
            switch self {
            case .gemini: URL(string: "https://aistudio.google.com/apikey")!
            case .openai: URL(string: "https://platform.openai.com/api-keys")!
            case .anthropic: URL(string: "https://platform.claude.com/settings/keys")!
            }
        }
    }

    static let enabledKey = "cloudVision.enabled"
    static let providerKey = "cloudVision.provider"
    static let modelKey = "cloudVision.model"

    static var provider: Provider { Provider(rawValue: UserDefaults.standard.string(forKey: providerKey) ?? "") ?? .gemini }
    static var model: String {
        let saved = UserDefaults.standard.string(forKey: modelKey) ?? ""
        return provider.models.contains(saved) ? saved : provider.models[0]
    }
    /// On, with a key saved for the chosen provider.
    static var isOn: Bool { UserDefaults.standard.bool(forKey: enabledKey) && Keychain.read(provider.rawValue) != nil }

    enum Failure: LocalizedError {
        case noKey, refused, badReply, http(Int, String)
        var errorDescription: String? {
            switch self {
            case .noKey: "No API key is saved."
            case .refused: "The provider declined to read this photo."
            case .badReply: "The provider's answer couldn't be read."
            case .http(let code, let message):
                code == 401 || code == 403 ? "The key was rejected. Check it in Settings." : code == 429 ? "The key is over its limit for now." : "The provider said: \(message)"
            }
        }
    }

    /// What's asked of every provider. The same rules as Apple Intelligence on the phone: name, don't estimate nutrition.
    static let instructions = """
        You look at photos for a food diary. List each separate food or drink you can see, the biggest first, at most 8. \
        For each give: "name", a few plain words someone would search a food diary for ("chicken drumstick", "white rice", \
        "firm tofu"); "otherNames", up to three other names a nutrition database might use; "brand", only if a restaurant \
        or brand name or logo is printed in the photo, otherwise ""; "count", how many there are; "size", "small", "regular" \
        or "large" next to one normal serving for one person; and "grams", your best estimate of the weight of one of them. \
        Never estimate calories or nutrients. If there's no food or drink, return an empty list. \
        Reply with only JSON: {"foods": [{"name": "", "otherNames": [], "brand": "", "count": 1, "size": "regular", "grams": 0}]}
        """

    static var schema: [String: Any] { [
        "type": "object",
        "properties": ["foods": ["type": "array", "items": [
            "type": "object",
            "properties": [
                "name": ["type": "string"], "otherNames": ["type": "array", "items": ["type": "string"]],
                "brand": ["type": "string"], "count": ["type": "integer"],
                "size": ["type": "string", "enum": ["small", "regular", "large"]], "grams": ["type": "number"],
            ],
            "required": ["name", "otherNames", "brand", "count", "size", "grams"],
            "additionalProperties": false,
        ]]],
        "required": ["foods"],
        "additionalProperties": false,
    ] }

    /// The foods the chosen provider sees in the photo.
    static func foods(in image: CGImage) async throws -> [SeenFood] {
        guard let key = Keychain.read(provider.rawValue) else { throw Failure.noKey }
        guard let jpeg = jpeg(image) else { throw Failure.badReply }
        let text = try await ask(provider, model: model, key: key, image: jpeg)
        return try parse(text)
    }

    /// Checks a key with a tiny request (no photo), so Settings can say whether it works before it's saved.
    static func check(_ provider: Provider, model: String, key: String) async throws {
        _ = try parse(try await ask(provider, model: model, key: key, image: nil, prompt: "There is no photo. Return an empty list."))
    }

    // MARK: Requests

    private static func ask(_ provider: Provider, model: String, key: String, image: Data?, prompt: String = "Which foods and drinks are in this photo?") async throws -> String {
        var request: URLRequest
        var body: [String: Any]
        let base64 = image?.base64EncodedString()
        switch provider {
        case .gemini:
            request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
            // In a header, not the URL, so the key never sits in logs.
            request.setValue(key, forHTTPHeaderField: "X-goog-api-key")
            var parts: [[String: Any]] = base64.map { [["inlineData": ["mimeType": "image/jpeg", "data": $0]]] } ?? []
            parts.append(["text": prompt])
            body = ["systemInstruction": ["parts": [["text": instructions]]], "contents": [["parts": parts]],
                    "generationConfig": ["responseMimeType": "application/json", "maxOutputTokens": 4096]]
        case .openai:
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            var content: [[String: Any]] = [["type": "text", "text": prompt]]
            if let base64 { content.append(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]]) }
            body = ["model": model, "messages": [["role": "system", "content": instructions], ["role": "user", "content": content]],
                    "response_format": ["type": "json_object"], "max_completion_tokens": 4096]
        case .anthropic:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            var content: [[String: Any]] = base64.map { [["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": $0]]] } ?? []
            content.append(["type": "text", "text": prompt])
            body = ["model": model, "max_tokens": 16000, "system": instructions, "messages": [["role": "user", "content": content]],
                    // Naming foods is a simple job: low effort keeps it quick and cheap on the person's own bill.
                    "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": schema]]]
            // If a safety check declines the photo, the API retries it on its recommended fallback model.
            // Haiku has no server-side fallback, so it goes without.
            if !model.contains("haiku") {
                request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
                body["fallbacks"] = "default"
            }
        }
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.httpShouldHandleCookies = false
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status == 200 else {
            let message = ((json["error"] as? [String: Any])?["message"] as? String) ?? HTTPURLResponse.localizedString(forStatusCode: status)
            throw Failure.http(status, message)
        }
        return try reply(provider, json)
    }

    /// The text of the answer, from each provider's reply shape.
    static func reply(_ provider: Provider, _ json: [String: Any]) throws -> String {
        switch provider {
        case .gemini:
            let parts = (((json["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
            let text = parts.compactMap { $0["text"] as? String }.joined()
            guard !text.isEmpty else { throw Failure.refused }
            return text
        case .openai:
            let message = ((json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]) ?? [:]
            if message["refusal"] as? String != nil { throw Failure.refused }
            guard let text = message["content"] as? String else { throw Failure.badReply }
            return text
        case .anthropic:
            // Check the stop reason before reading: a declined request may not follow the schema.
            if json["stop_reason"] as? String == "refusal" { throw Failure.refused }
            let text = ((json["content"] as? [[String: Any]]) ?? []).filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
            guard !text.isEmpty else { throw Failure.badReply }
            return text
        }
    }

    /// The foods in an answer, tolerating a code fence around the JSON.
    static func parse(_ text: String) throws -> [SeenFood] {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") { trimmed = String(trimmed[start...end]) }
        guard let data = trimmed.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let foods = object["foods"] as? [[String: Any]] else { throw Failure.badReply }
        return foods.prefix(8).compactMap { item in
            let name = (item["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let brand = (item["brand"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let others = (item["otherNames"] as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.lowercased() != name.lowercased() }
            let count = min(max((item["count"] as? NSNumber)?.intValue ?? 1, 1), 12)
            let grams = (item["grams"] as? NSNumber)?.doubleValue
            return SeenFood(name: name, alternatives: Array(others.prefix(3)), brand: brand.isEmpty ? nil : brand, count: count,
                            size: PortionSize(rawValue: (item["size"] as? String ?? "").lowercased()) ?? .regular,
                            grams: grams.flatMap { $0.isFinite && $0 > 0 && $0 < 3000 ? $0 : nil })
        }
    }

    /// The photo as a JPEG for upload.
    static func jpeg(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

/// API keys, kept in the iOS Keychain on this device only (never in Leanr's data, iCloud or backups).
enum Keychain {
    private static let service = "com.isaiahgraham.MacroMenu.apikeys"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    @discardableResult static func save(_ key: String, for account: String) -> Bool {
        delete(account)
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account, kSecValueData as String: Data(key.utf8),
                                   kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ account: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
    }

    static func deleteAll() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }
}
