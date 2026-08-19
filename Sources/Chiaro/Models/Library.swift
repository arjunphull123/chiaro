import AppKit
import Observation
import ImageIO

@Observable @MainActor
final class Library {
    var folderURL: URL?
    var photos: [Photo] = []
    var selection: Set<URL> = []
    var editing: Photo?
    var copiedEdit: EditState?
    /// The live edit session, when the edit view is open — lets external inputs
    /// (MCP tools) mutate the same EditState the UI is rendering (ADR 0008).
    weak var activeEditor: EditViewModel?

    /// True while an agent is actively driving edits over MCP; the UI shows a
    /// presence pill and soft-locks manual input. Clears 3s after the last call.
    var agentActive = false
    private var agentClearItem: DispatchWorkItem?

    func noteAgentActivity() {
        agentActive = true
        activeEditor?.armed = nil
        agentClearItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.agentActive = false }
        agentClearItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)
    }

    var folderName: String { folderURL?.lastPathComponent ?? "" }
    var selectedPhotos: [Photo] { photos.filter { selection.contains($0.url) } }

    func open(_ url: URL) {
        folderURL = url
        editing = nil
        selection = []
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

    private func loadThumbnails() {
        let targets = photos
        Task.detached(priority: .userInitiated) {
            await withTaskGroup(of: (URL, CGImage?).self) { group in
                var pending = targets.makeIterator()
                var active = 0
                func addNext(_ group: inout TaskGroup<(URL, CGImage?)>) {
                    guard let photo = pending.next() else { return }
                    let url = photo.url
                    active += 1
                    group.addTask { (url, Self.embeddedThumbnail(url)) }
                }
                for _ in 0..<6 { addNext(&group) }
                for await (url, image) in group {
                    active -= 1
                    if let image {
                        await MainActor.run { [targets] in
                            guard let photo = targets.first(where: { $0.url == url }) else { return }
                            photo.thumbnail = image
                            photo.aspect = CGFloat(image.width) / CGFloat(image.height)
                        }
                    }
                    addNext(&group)
                }
            }
        }
    }

    /// Fast thumbnail from the file's embedded preview — never a full RAW decode.
    nonisolated static func embeddedThumbnail(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 480,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
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
