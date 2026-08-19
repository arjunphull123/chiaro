import Foundation

/// Non-destructive edit persistence (ADR 0002): one JSON file beside each photo.
enum Sidecar {
    struct Document: Codable {
        var version = 1
        var edit: EditState
        var rating: Int = 0
    }

    static func url(for photoURL: URL) -> URL {
        photoURL.deletingPathExtension().appendingPathExtension("chiaro.json")
    }

    static func read(for photoURL: URL) -> Document? {
        guard let data = try? Data(contentsOf: url(for: photoURL)) else { return nil }
        return try? JSONDecoder().decode(Document.self, from: data)
    }

    static func write(for photo: Photo) {
        let doc = Document(edit: photo.edit, rating: photo.rating)
        let target = url(for: photo.url)
        if doc.edit.isNeutral && doc.rating == 0 {
            try? FileManager.default.removeItem(at: target)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(doc) {
            try? data.write(to: target, options: .atomic)
        }
    }
}
