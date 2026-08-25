import Foundation
import CryptoKit

/// Non-destructive edit persistence (ADR 0002): one JSON file beside each photo.
/// Photos on removable/read-only volumes (a plugged-in camera card) keep their
/// sidecars in Application Support instead, keyed by source path (ADR 0007).
enum Sidecar {
    /// A named saved state of the edit — Lightroom-style snapshot.
    struct Snapshot: Codable, Equatable, Identifiable {
        var name: String
        var date: Date
        var edit: EditState
        var id: String { "\(name)-\(date.timeIntervalSince1970)" }
    }

    struct Document: Codable {
        var version = 1
        var edit: EditState
        var starred: Bool = false
        var versions: [Snapshot] = []

        init(edit: EditState, starred: Bool, versions: [Snapshot]) {
            self.edit = edit
            self.starred = starred
            self.versions = versions
        }

        // Tolerant decode; pre-flag sidecars carried a 0-5 rating.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
            edit = try c.decodeIfPresent(EditState.self, forKey: .edit) ?? EditState()
            versions = try c.decodeIfPresent([Snapshot].self, forKey: .versions) ?? []
            if let flag = try c.decodeIfPresent(Bool.self, forKey: .starred) {
                starred = flag
            } else if let legacy = try? decoder.container(keyedBy: LegacyKeys.self),
                      let rating = try legacy.decodeIfPresent(Int.self, forKey: .rating) {
                starred = rating > 0
            }
        }

        private enum LegacyKeys: String, CodingKey { case rating }
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

    /// Returns false only on total failure — both the beside-file location and
    /// the Application Support fallback rejected the write (disk full, unwritable
    /// home). Callers that report success to an agent should check it.
    @discardableResult
    static func write(for photo: Photo) -> Bool {
        let doc = Document(edit: photo.edit, starred: photo.starred, versions: photo.snapshots)
        let target = preferredURL(photo.url)
        if doc.edit.isNeutral && !doc.starred && doc.versions.isEmpty {
            try? FileManager.default.removeItem(at: besideURL(photo.url))
            try? FileManager.default.removeItem(at: storeURL(photo.url))
            return true
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(doc) else { return false }
        do {
            try data.write(to: target, options: .atomic)
            return true
        } catch {
            do {
                try data.write(to: storeURL(photo.url), options: .atomic)
                return true
            } catch {
                NSLog("Chiaro: could not save edits for \(photo.name): \(error.localizedDescription)")
                return false
            }
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
