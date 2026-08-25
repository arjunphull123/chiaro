import AppKit
import Observation

@Observable
final class Photo: Identifiable {
    let url: URL
    let isRAW: Bool
    var thumbnail: CGImage?
    var aspect: CGFloat = 1.5
    var edit: EditState
    var starred: Bool
    /// The edit the current `thumbnail` was rendered with — nil means it is
    /// the file's plain embedded preview. Lets the library re-render only
    /// tiles whose edits actually changed.
    var thumbEdit: EditState?
    var snapshots: [Sidecar.Snapshot] = []
    var captureDate: Date?
    var exifSummary: String?
    var pixelSize: CGSize?

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
    /// For display only — `name` stays the identity sidecars and MCP address.
    var filename: String { url.lastPathComponent }
    var hasEdits: Bool { !edit.isNeutral }

    init(url: URL) {
        self.url = url
        self.isRAW = Photo.isRAW(url)
        let sidecar = Sidecar.read(for: url)
        self.edit = sidecar?.edit ?? .neutral
        self.starred = sidecar?.starred ?? false
        self.snapshots = sidecar?.versions ?? []
    }

    static let rawExtensions: Set<String> = ["arw", "dng", "nef", "cr2", "cr3", "raf", "orf", "rw2", "srw", "pef"]
    static func isRAW(_ url: URL) -> Bool { rawExtensions.contains(url.pathExtension.lowercased()) }
    static let imageExtensions: Set<String> = rawExtensions.union(["jpg", "jpeg", "heic", "heif", "tiff", "tif", "png"])
}
