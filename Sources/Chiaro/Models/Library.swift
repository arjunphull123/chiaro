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
    /// The photo an agent tool call most recently named — the library lights
    /// that tile briefly so a folder-wide pass can be followed visually.
    /// Clears with the rest of agent presence, 3s after the last call.
    var agentTouchedPhoto: URL?
    private var agentClearItem: DispatchWorkItem?

    func noteAgentActivity(intent: String? = nil, photo: URL? = nil) {
        agentActive = true
        if let intent { agentIntent = intent }
        if let photo { agentTouchedPhoto = photo }
        activeEditor?.armed = nil
        agentClearItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.agentActive = false
            self?.agentIntent = nil
            self?.agentTouchedPhoto = nil
        }
        agentClearItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)
    }

    /// Continuous library zoom (0 = tiny thumbs/years … 1 = large thumbs/days).
    /// One value drives both thumbnail size and grouping granularity; the header
    /// slider and trackpad pinch both write it.
    var zoomLevel: Double = 0.8

    /// Library presentation: justified gallery, square grid, or detail list.
    enum ViewMode: String, CaseIterable {
        case gallery, grid, list
        var icon: String {
            switch self {
            case .gallery: "rectangle.grid.3x2"
            case .grid: "square.grid.3x3"
            case .list: "list.bullet"
            }
        }
        var help: String {
            switch self {
            case .gallery: "Gallery — photos keep their shape"
            case .grid: "Grid — uniform squares"
            case .list: "List — details and dates"
            }
        }
    }
    var viewMode: ViewMode = ViewMode(rawValue: UserDefaults.standard.string(forKey: "viewMode") ?? "") ?? .gallery {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: "viewMode") }
    }
    var showFilenames = UserDefaults.standard.bool(forKey: "showFilenames") {
        didSet { UserDefaults.standard.set(showFilenames, forKey: "showFilenames") }
    }

    enum Zoom { case days, months, years }
    var zoom: Zoom {
        if zoomLevel < 0.3 { .years } else if zoomLevel < 0.58 { .months } else { .days }
    }

    var folderName: String { folderURL?.lastPathComponent ?? "" }
    var selectedPhotos: [Photo] { photos.filter { selection.contains($0.url) } }

    // MARK: - Gallery filters
    // Lifted out of LibraryView so EditView's arrow-key/nav-pill stepping can
    // walk the same filtered set the gallery is showing (ADR-less mechanical fix).
    var filterStarred = false
    var filterEdited = false
    var filterRAW = false
    /// Top-level subfolder filter (nil = everything).
    var folderScope: String?
    var searchText = ""

    var visiblePhotos: [Photo] {
        var result = photos
        if filterStarred { result = result.filter(\.starred) }
        if filterEdited { result = result.filter(\.hasEdits) }
        if filterRAW { result = result.filter(\.isRAW) }
        if let folderScope {
            result = result.filter { topFolder($0) == folderScope }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        return result
    }

    /// Path of the photo's parent, relative to the opened folder ("" at root).
    func relativeFolder(_ photo: Photo) -> String {
        guard let root = folderURL else { return "" }
        let parent = photo.url.deletingLastPathComponent().standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        guard parent.hasPrefix(rootPath), parent != rootPath else { return "" }
        return String(parent.dropFirst(rootPath.count + 1))
    }

    func topFolder(_ photo: Photo) -> String? {
        let rel = relativeFolder(photo)
        return rel.isEmpty ? nil : rel.split(separator: "/").first.map(String.init)
    }

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
    /// One entry per card, not per DCIM subfolder — a card with 100MSDCF and
    /// 101MSDCF is still one card, and folder chips break it out once opened.
    static func cameraCardFolders() -> [URL] {
        let fm = FileManager.default
        let volumes = (try? fm.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: nil)) ?? []
        return volumes.compactMap { volume -> URL? in
            let dcim = volume.appendingPathComponent("DCIM")
            guard fm.fileExists(atPath: dcim.path) else { return nil }
            let subs = (try? fm.contentsOfDirectory(at: dcim, includingPropertiesForKeys: nil)) ?? []
            let dirs = subs.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            guard !dirs.isEmpty else { return nil }
            return dirs.count == 1 ? dirs[0] : dcim
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
        // Recurse into subfolders (bounded: depth 5, 10k files) so a nested
        // library — e.g. Chiaro Library/<day>/ — opens as one gallery.
        let fm = FileManager.default
        var urls: [URL] = []
        if let enumerator = fm.enumerator(
            at: url, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let file as URL in enumerator {
                if enumerator.level > 5 { enumerator.skipDescendants(); continue }
                // Never ingest our own export output as library photos.
                if file.lastPathComponent == "Chiaro Exports" {
                    enumerator.skipDescendants()
                    continue
                }
                guard Photo.imageExtensions.contains(file.pathExtension.lowercased()) else { continue }
                urls.append(file)
                if urls.count >= 10_000 { break }
            }
        }

        // A RAW+JPEG pair is one photo; prefer the RAW.
        var byStem: [String: URL] = [:]
        for u in urls.sorted(by: { $0.path < $1.path }) {
            let stem = u.deletingPathExtension().path
            if let existing = byStem[stem],
               Photo.rawExtensions.contains(existing.pathExtension.lowercased()) {
                continue
            }
            byStem[stem] = u
        }
        photos = byStem.values
            .sorted { $0.path < $1.path }
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
    /// `maxPixelSize` is the caller's display need: gallery tiles are happy at 480,
    /// but the start screen's hero draws at 1240px on a Retina panel and upscaling
    /// a 480px thumbnail into it looks visibly soft.
    nonisolated static func scan(_ url: URL, maxPixelSize: Int = 480) -> ScanResult {
        var result = ScanResult()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return result }
        let base: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        var options = base
        options[kCGImageSourceCreateThumbnailFromImageIfAbsent] = true
        var image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        // Camera JPEGs embed a 160×120 EXIF thumbnail with letterbox bars baked in
        // to pad 3:2 into 4:3 — unusable, and it reports the wrong aspect ratio.
        // RAW previews are big, so this second pass only fires on the small ones.
        if let embedded = image, max(embedded.width, embedded.height) < min(320, maxPixelSize) {
            var force = base
            force[kCGImageSourceCreateThumbnailFromImageAlways] = true
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, force as CFDictionary) ?? embedded
        }
        result.image = image

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
        local.starred = photo.starred
        local.snapshots = photo.snapshots
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
    /// Returns the (possibly localized) photo now showing, since a card photo
    /// gets copied into the library under the same name but a new URL.
    @discardableResult
    func edit(_ photo: Photo) -> Photo {
        let target = localized(photo)
        selection = [target.url]
        lastSelected = target.url
        if let activeEditor { activeEditor.switchTo(target) } else { editing = target }
        return target
    }

    static func isRemovable(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [
            .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsReadOnlyKey,
        ])
        return values?.volumeIsRemovable ?? false
            || values?.volumeIsEjectable ?? false
            || values?.volumeIsReadOnly ?? false
    }

    // MARK: - Card import

    var importProgress: (done: Int, total: Int)?

    /// Offload a camera card: copy each photo — and its RAW+JPEG sibling —
    /// into ~/Pictures/Chiaro Library/<capture day>/. Existing files are
    /// skipped, so re-importing a card is safe and cheap.
    func importToLibrary(_ targets: [Photo]) {
        guard importProgress == nil, !targets.isEmpty else { return }
        importProgress = (0, targets.count)
        KeepAwake.poke(600)
        let jobs = targets.map { photo in
            (url: photo.url,
             day: (photo.captureDate ?? Date()).formatted(.iso8601.year().month().day()))
        }
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            let root = fm.urls(for: .picturesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Chiaro Library")
            var listings: [URL: [URL]] = [:]
            for (index, job) in jobs.enumerated() {
                let folder = root.appendingPathComponent(job.day)
                try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
                let dir = job.url.deletingLastPathComponent()
                if listings[dir] == nil {
                    listings[dir] = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
                }
                let stem = job.url.deletingPathExtension().lastPathComponent
                let siblings = listings[dir]!.filter {
                    $0.deletingPathExtension().lastPathComponent == stem
                        && Photo.imageExtensions.contains($0.pathExtension.lowercased())
                }
                for file in siblings {
                    let target = folder.appendingPathComponent(file.lastPathComponent)
                    if !fm.fileExists(atPath: target.path) {
                        try? fm.copyItem(at: file, to: target)
                    }
                }
                let done = index + 1
                DispatchQueue.main.async { self.importProgress = (done, jobs.count) }
            }
            DispatchQueue.main.async { self.importProgress = nil }
        }
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
            if let activeEditor, activeEditor.photo.url == photo.url {
                activeEditor.commitDiscrete(copiedEdit)
            } else {
                photo.edit = copiedEdit
                Sidecar.write(for: photo)
            }
        }
    }
}
