import AppKit
import Observation

@Observable
final class Photo: Identifiable {
    let url: URL
    let isRAW: Bool
    var thumbnail: CGImage?
    var aspect: CGFloat = 1.5
    var edit: EditState
    var rating: Int

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
    var hasEdits: Bool { !edit.isNeutral }

    init(url: URL) {
        self.url = url
        self.isRAW = Photo.rawExtensions.contains(url.pathExtension.lowercased())
        let sidecar = Sidecar.read(for: url)
        self.edit = sidecar?.edit ?? .neutral
        self.rating = sidecar?.rating ?? 0
    }

    static let rawExtensions: Set<String> = ["arw", "dng", "nef", "cr2", "cr3", "raf", "orf", "rw2", "srw", "pef"]
    static let imageExtensions: Set<String> = rawExtensions.union(["jpg", "jpeg", "heic", "heif", "tiff", "tif", "png"])
}
