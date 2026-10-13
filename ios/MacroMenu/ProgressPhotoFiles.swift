import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A progress photo. Only this small record is kept in the index; the picture is its own file.
struct ProgressPhoto: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var date: Date
    var note: String? = nil
}

/// Progress photos on this device: a folder of JPEGs and an index.
/// They aren't part of `AppData`, so they never reach iCloud sync, backups or exports.
struct ProgressPhotoFiles: Sendable {
    var directory: URL

    static let standard = ProgressPhotoFiles(directory: URL.applicationSupportDirectory.appending(path: "MacroMenu/ProgressPhotos"))

    private var indexURL: URL { directory.appending(path: "index.json") }
    private func fileURL(_ id: UUID) -> URL { directory.appending(path: "\(id.uuidString).jpg") }
    private static let options: Data.WritingOptions = [.atomic, .completeFileProtection]

    /// Newest first. A record whose picture has gone is left out.
    func load() -> [ProgressPhoto] {
        guard let data = try? Data(contentsOf: indexURL),
              let photos = try? JSONDecoder().decode([ProgressPhoto].self, from: data) else { return [] }
        return photos.filter { FileManager.default.fileExists(atPath: fileURL($0.id).path) }.sorted { $0.date > $1.date }
    }

    private func save(_ photos: [ProgressPhoto]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(photos).write(to: indexURL, options: Self.options)
    }

    /// Stores a picture (already a JPEG, see `prepared`) and records it.
    @discardableResult func add(jpeg: Data, date: Date, note: String? = nil) throws -> ProgressPhoto {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let photo = ProgressPhoto(date: date, note: note)
        try jpeg.write(to: fileURL(photo.id), options: Self.options)
        do { try save(load() + [photo]) } catch { try? FileManager.default.removeItem(at: fileURL(photo.id)); throw error }
        return photo
    }

    /// Changes a photo's date or note.
    func update(_ photo: ProgressPhoto) throws {
        var photos = load()
        guard let index = photos.firstIndex(where: { $0.id == photo.id }) else { return }
        photos[index] = photo
        try save(photos)
    }

    func remove(_ id: UUID) throws {
        try save(load().filter { $0.id != id })
        try? FileManager.default.removeItem(at: fileURL(id))
    }

    /// Deletes every photo and the index. Used by "Delete all my data".
    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    func data(_ id: UUID) -> Data? { try? Data(contentsOf: fileURL(id)) }

    /// A small picture for a grid, read without decoding the whole photo.
    func thumbnail(_ id: UUID, longestSide: Int = 400) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(fileURL(id) as CFURL, nil) else { return nil }
        return Self.scaled(source, longestSide: longestSide)
    }

    /// A photo as a JPEG at most `longestSide` pixels on its longest edge and upright, so it opens quickly and takes little room.
    /// Nil when the data isn't an image.
    static func prepared(_ data: Data, longestSide: Int = 1600, quality: Double = 0.8) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = scaled(source, longestSide: longestSide) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func scaled(_ source: CGImageSource, longestSide: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longestSide] as CFDictionary)
    }
}
