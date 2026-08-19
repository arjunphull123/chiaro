import Foundation
import CryptoKit

/// Non-destructive edit persistence (ADR 0002): one JSON file beside each photo.
/// Photos on removable/read-only volumes (a plugged-in camera card) keep their
/// sidecars in Application Support instead, keyed by source path (ADR 0007).
enum Sidecar {
    struct Document: Codable {
        var version = 1
        var edit: EditState
        var rating: Int = 0
    }

    static func read(for photoURL: URL) -> Document? {
        for location in [besideURL(photoURL), storeURL(photoURL)] {
            if let data = try? Data(contentsOf: location),
               let doc = try? JSONDecoder().decode(Document.self, from: data) {
                return doc
            }
        }
        return nil
    }

    static func write(for photo: Photo) {
        let doc = Document(edit: photo.edit, rating: photo.rating)
        let target = preferredURL(photo.url)
        if doc.edit.isNeutral && doc.rating == 0 {
            try? FileManager.default.removeItem(at: besideURL(photo.url))
            try? FileManager.default.removeItem(at: storeURL(photo.url))
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(doc) else { return }
        do {
            try data.write(to: target, options: .atomic)
        } catch {
            try? data.write(to: storeURL(photo.url), options: .atomic)
        }
    }

    static func lastEditDate(for photoURL: URL) -> Date? {
        for location in [besideURL(photoURL), storeURL(photoURL)] {
            if let date = try? location.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                return date
            }
        }
        return nil
    }

    // MARK: - Locations

    private static func preferredURL(_ photoURL: URL) -> URL {
        isRemovable(photoURL) ? storeURL(photoURL) : besideURL(photoURL)
    }

    private static func besideURL(_ photoURL: URL) -> URL {
        photoURL.deletingPathExtension().appendingPathExtension("chiaro.json")
    }

    private static func storeURL(_ photoURL: URL) -> URL {
        let digest = SHA256.hash(data: Data(photoURL.path.utf8))
            .prefix(8).map { String(format: "%02x", $0) }.joined()
        return store.appendingPathComponent("\(digest)-\(photoURL.deletingPathExtension().lastPathComponent).chiaro.json")
    }

    private static let store: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Chiaro/Sidecars")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func isRemovable(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [
            .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsReadOnlyKey,
        ])
        return values?.volumeIsRemovable ?? false
            || values?.volumeIsEjectable ?? false
            || values?.volumeIsReadOnly ?? false
    }
}
