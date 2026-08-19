import AppKit
import Observation
import ImageIO

@Observable @MainActor
final class Library {
    var folderURL: URL?
    var photos: [Photo] = []
    var selection: Set<URL> = []
    /// The most recently clicked photo — "Open in editor" targets this.
    var lastSelected: URL?
    var editing: Photo?
    var copiedEdit: EditState?
    /// The live edit session, when the edit view is open — lets external inputs
    /// (MCP tools) mutate the same EditState the UI is rendering (ADR 0008).
    weak var activeEditor: EditViewModel?

    /// True while an agent is actively driving edits over MCP; the UI frosts the
    /// rail with a presence pill and the agent's stated intent, and soft-locks
    /// manual input. Clears 3s after the last call.
    var agentActive = false
    var agentIntent: String?
    private var agentClearItem: DispatchWorkItem?

    func noteAgentActivity(intent: String? = nil) {
        agentActive = true
        if let intent { agentIntent = intent }
        activeEditor?.armed = nil
        agentClearItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.agentActive = false
            self?.agentIntent = nil
        }
        agentClearItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)
    }

    /// Continuous library zoom (0 = tiny thumbs/years … 1 = large thumbs/days).
    /// One value drives both thumbnail size and grouping granularity; the header
    /// slider and trackpad pinch both write it.
    var zoomLevel: Double = 0.8

    enum Zoom { case days, months, years }
    var zoom: Zoom {
        if zoomLevel < 0.3 { .years } else if zoomLevel < 0.58 { .months } else { .days }
    }

    var folderName: String { folderURL?.lastPathComponent ?? "" }
    var selectedPhotos: [Photo] { photos.filter { selection.contains($0.url) } }

    static func noteRecentEdit(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: "recentEdits") ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(12)), forKey: "recentEdits")
    }

    static func recentEdits() -> [URL] {
        (UserDefaults.standard.stringArray(forKey: "recentEdits") ?? [])
            .map(URL.init(fileURLWithPath:))
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func recentFolders() -> [URL] {
        (UserDefaults.standard.stringArray(forKey: "recentFolders") ?? [])
            .map(URL.init(fileURLWithPath:))
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// DCIM folders on mounted camera cards — the "camera just plugged in" path.
    static func cameraCardFolders() -> [URL] {
        let fm = FileManager.default
        let volumes = (try? fm.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: nil)) ?? []
        return volumes.flatMap { volume -> [URL] in
            let dcim = volume.appendingPathComponent("DCIM")
            guard fm.fileExists(atPath: dcim.path) else { return [] }
            let subs = (try? fm.contentsOfDirectory(at: dcim, includingPropertiesForKeys: nil)) ?? []
            return subs.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        }
    }

    /// Back to the start screen.
    func close() {
        activeEditor?.saveNow()
        activeEditor = nil
        editing = nil
        folderURL = nil
        photos = []
        selection = []
    }

    func open(_ url: URL) {
        folderURL = url
        editing = nil
        selection = []
        var recents = UserDefaults.standard.stringArray(forKey: "recentFolders") ?? []
        recents.removeAll { $0 == url.path }
        recents.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(recents.prefix(5)), forKey: "recentFolders")
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []

        // A RAW+JPEG pair is one photo; prefer the RAW.
        var byStem: [String: URL] = [:]
        for u in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let ext = u.pathExtension.lowercased()
            guard Photo.imageExtensions.contains(ext) else { continue }
            let stem = u.deletingPathExtension().lastPathComponent
            if let existing = byStem[stem],
               Photo.rawExtensions.contains(existing.pathExtension.lowercased()) {
                continue
            }
            byStem[stem] = u
        }
        photos = byStem.values
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map(Photo.init)
        loadThumbnails()
    }

    struct ScanResult: Sendable {
        var image: CGImage?
        var captureDate: Date?
        var exifSummary: String?
        var pixelSize: CGSize?
    }

    /// Thumbnail extraction is blocking I/O, so it runs on its own OperationQueue —
    /// never on the cooperative pool, where it would starve every other Task.
    private static let scanQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 4
        q.qualityOfService = .utility
        return q
    }()

    private func loadThumbnails() {
        KeepAwake.poke(60)
        Self.scanQueue.cancelAllOperations()
        let currentFolder = folderURL
        for photo in photos {
            let url = photo.url
            Self.scanQueue.addOperation { [weak self] in
                let result = Self.scan(url)
                DispatchQueue.main.async {
                    guard let self, self.folderURL == currentFolder,
                          let photo = self.photos.first(where: { $0.url == url }) else { return }
                    if let image = result.image {
                        photo.thumbnail = image
                        photo.aspect = CGFloat(image.width) / CGFloat(image.height)
                    }
                    photo.captureDate = result.captureDate
                    photo.exifSummary = result.exifSummary
                    photo.pixelSize = result.pixelSize
                }
            }
        }
    }

    /// Fast thumbnail + shooting metadata from the file's embedded preview —
    /// never a full RAW decode.
    nonisolated static func scan(_ url: URL) -> ScanResult {
        var result = ScanResult()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return result }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 480,
        ]
        result.image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)

        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return result
        }
        if let w = props[kCGImagePropertyPixelWidth] as? Double,
           let h = props[kCGImagePropertyPixelHeight] as? Double {
            result.pixelSize = CGSize(width: w, height: h)
        }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        if let stamp = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            result.captureDate = Self.exifDateFormatter.date(from: stamp)
        }
        var parts: [String] = []
        if let f = exif[kCGImagePropertyExifFNumber] as? Double {
            parts.append(String(format: "ƒ%.1f", f))
        }
        if let t = exif[kCGImagePropertyExifExposureTime] as? Double, t > 0 {
            parts.append(t >= 1 ? String(format: "%.0fs", t) : "1/\(Int((1 / t).rounded()))")
        }
        if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Any])?.first as? Int {
            parts.append("ISO \(iso)")
        }
        if let mm = exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? Int {
            parts.append("\(mm)mm")
        }
        result.exifSummary = parts.isEmpty ? nil : parts.joined(separator: " · ")
        return result
    }

    nonisolated static let exifDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f
    }()

    // MARK: - Import on edit

    /// Editing a photo that lives on a camera card first copies the RAW into the
    /// local library (~/Pictures/Chiaro Library/<capture day>/), so the photo and
    /// its edits survive the card being ejected or reformatted. Local photos are
    /// returned unchanged; a failed copy falls back to editing in place.
    func localized(_ photo: Photo) -> Photo {
        guard Self.isRemovable(photo.url) else { return photo }
        let day = (photo.captureDate ?? Date()).formatted(.iso8601.year().month().day())
        let folder = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Chiaro Library/\(day)")
        let target = folder.appendingPathComponent(photo.url.lastPathComponent)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            if !fm.fileExists(atPath: target.path) {
                try fm.copyItem(at: photo.url, to: target)
            }
        } catch {
            return photo
        }
        let local = Photo(url: target)
        local.edit = photo.edit
        local.rating = photo.rating
        local.thumbnail = photo.thumbnail
        local.aspect = photo.aspect
        local.captureDate = photo.captureDate
        local.exifSummary = photo.exifSummary
        Sidecar.write(for: local)
        if let index = photos.firstIndex(where: { $0.url == photo.url }) {
            photos[index] = local
        }
        if selection.remove(photo.url) != nil { selection.insert(local.url) }
        return local
    }

    /// The one entry point for opening the editor — always localizes first.
    func edit(_ photo: Photo) {
        let target = localized(photo)
        selection = [target.url]
        lastSelected = target.url
        if let activeEditor { activeEditor.switchTo(target) } else { editing = target }
    }

    static func isRemovable(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [
            .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsReadOnlyKey,
        ])
        return values?.volumeIsRemovable ?? false
            || values?.volumeIsEjectable ?? false
            || values?.volumeIsReadOnly ?? false
    }

    // MARK: - Edit transfer

    func copyEdit() {
        if let editing { copiedEdit = editing.edit }
        else if let first = selectedPhotos.first { copiedEdit = first.edit }
    }

    func pasteEdit() {
        guard let copiedEdit else { return }
        let targets = editing.map { [$0] } ?? selectedPhotos
        for photo in targets {
            photo.edit = copiedEdit
            Sidecar.write(for: photo)
        }
    }
}
