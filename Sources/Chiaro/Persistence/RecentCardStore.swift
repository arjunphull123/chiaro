import AppKit
import CryptoKit

/// Rendered start-screen cards, kept on disk so a returning user's recents are
/// there at launch instead of after a decode and the depth model's first load.
/// Derived data only: keyed by the photo and its sidecar date, so an edit
/// invalidates it; safe to delete at any time.
enum RecentCardStore {
    struct Card {
        let image: CGImage
        let focus: CGPoint?
    }

    private nonisolated static let dir = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Chiaro/RecentCards")

    private nonisolated static func digest(_ url: URL) -> String {
        SHA256.hash(data: Data(url.path.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func base(_ url: URL, _ editDate: Date?) -> URL {
        dir.appendingPathComponent("\(digest(url))-\(Int(editDate?.timeIntervalSince1970 ?? 0))")
    }

    nonisolated static func load(_ url: URL, editDate: Date?) -> Card? {
        let base = base(url, editDate)
        guard let source = CGImageSourceCreateWithURL(base.appendingPathExtension("jpg") as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        var focus: CGPoint?
        if let data = try? Data(contentsOf: base.appendingPathExtension("json")),
           let point = try? JSONDecoder().decode([Double].self, from: data), point.count == 2 {
            focus = CGPoint(x: point[0], y: point[1])
        }
        return Card(image: image, focus: focus)
    }

    nonisolated static func save(_ card: Card, for url: URL, editDate: Date?) {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // Earlier renders of the same photo are stale by definition.
        let stale = digest(url)
        for file in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        where file.lastPathComponent.hasPrefix(stale) {
            try? fm.removeItem(at: file)
        }
        let base = base(url, editDate)
        let rep = NSBitmapImageRep(cgImage: card.image)
        try? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])?
            .write(to: base.appendingPathExtension("jpg"))
        if let focus = card.focus, let data = try? JSONEncoder().encode([focus.x, focus.y]) {
            try? data.write(to: base.appendingPathExtension("json"))
        }
    }
}
