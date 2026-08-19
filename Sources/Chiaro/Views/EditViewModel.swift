import SwiftUI
import CoreImage
import Observation

/// Owns the editing session for one photo: EditState in, rendered preview out.
/// Every input path (sliders, scrub, keys, future AI) mutates `edit`; rendering,
/// histogram, and sidecar persistence all follow from that one property (ADR 0003).
@Observable @MainActor
final class EditViewModel {
    private(set) var photo: Photo
    var edit: EditState {
        didSet {
            guard edit != oldValue else { return }
            if !isRestoringEdit {
                if Date().timeIntervalSince(lastEditAt) > 0.8 {
                    undoStack.append(oldValue)
                    if undoStack.count > 100 { undoStack.removeFirst() }
                    redoStack.removeAll()
                }
                lastEditAt = Date()
            }
            photo.edit = edit
            scheduleRender()
            scheduleSave()
        }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(edit)
        isRestoringEdit = true
        edit = previous
        isRestoringEdit = false
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(edit)
        isRestoringEdit = true
        edit = next
        isRestoringEdit = false
    }
    var armed: EditParameter?
    var hovered: EditParameter?
    var showOriginal = false
    /// Crop mode renders the full straightened frame; the crop rect is an overlay.
    var cropMode = false {
        didSet {
            guard cropMode != oldValue else { return }
            armed = nil
            scheduleRender()
        }
    }
    /// Locked pixel aspect (w/h) while cropping; nil = free.
    var cropAspect: Double?
    /// Chip identity — two chips can share a nil aspect (Free vs unknown Original).
    var cropAspectName: String?

    func applyCropAspect(_ aspect: Double?, name: String? = nil) {
        cropAspect = aspect
        cropAspectName = name
        guard let aspect, let frame = preview else { return }
        let frameAspect = Double(frame.width) / Double(frame.height)
        let k = aspect / frameAspect
        var c = CropRect.full
        if k <= 1 { c.w = k; c.x = (1 - k) / 2 } else { c.h = 1 / k; c.y = (1 - 1 / k) / 2 }
        edit.crop = c
    }
    var preview: CGImage?
    var originalPreview: CGImage?
    var histogram = HistogramData()
    var hasPerson: Bool?
    var isLoading = true

    private var basePreview: CIImage?
    private var personMask: CIImage?
    private var renderGeneration = 0
    private var saveItem: DispatchWorkItem?
    private var saveActivity: NSObjectProtocol?

    // Undo/redo: EditState snapshots, coalesced so a slider drag is one step.
    private var undoStack: [EditState] = []
    private var redoStack: [EditState] = []
    private var lastEditAt = Date.distantPast
    private var isRestoringEdit = false
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    init(photo: Photo) {
        self.photo = photo
        self.edit = photo.edit
        load()
    }

    func switchTo(_ newPhoto: Photo) {
        guard newPhoto.url != photo.url else { return }
        saveNow()
        photo = newPhoto
        isRestoringEdit = true
        edit = newPhoto.edit
        isRestoringEdit = false
        undoStack.removeAll()
        redoStack.removeAll()
        armed = nil
        preview = nil
        originalPreview = nil
        basePreview = nil
        personMask = nil
        hasPerson = nil
        isLoading = true
        load()
    }

    private func load() {
        KeepAwake.poke(30)
        let url = photo.url
        renderGeneration += 1
        Task { [weak self] in
            guard let decoded = await Offload.on(Offload.render, { () -> (CIImage, CGImage?)? in
                guard let base = RawEngine.shared.preview(for: url) else { return nil }
                return (base, RawEngine.shared.context.createCGImage(base, from: base.extent))
            }) else { return }
            let (base, baseCG) = decoded
            guard let self, self.photo.url == url else { return }
            self.basePreview = base
            self.originalPreview = baseCG
            self.isLoading = false
            self.scheduleRender()

            let mask = await Offload.on(Offload.vision) { PortraitEngine.shared.mask(for: url, image: base) }
            guard self.photo.url == url else { return }
            self.personMask = mask
            self.hasPerson = mask != nil
            if self.edit.blurF > 0 || self.edit.relight != 0 { self.scheduleRender() }
        }
    }

    private func scheduleRender() {
        guard let basePreview else { return }
        KeepAwake.poke()
        renderGeneration += 1
        let generation = renderGeneration
        let edit = edit
        let mask = personMask
        let skipCrop = cropMode
        Task { [weak self] in
            let result = await Offload.on(Offload.render) { () -> (CGImage, HistogramData)? in
                let output = RenderPipeline.render(base: basePreview, edit: edit, personMask: mask, skipCrop: skipCrop)
                guard let cg = RawEngine.shared.context.createCGImage(output, from: output.extent) else { return nil }
                return (cg, HistogramSampler.sample(output))
            }
            guard let self, let (cg, hist) = result, generation == self.renderGeneration else { return }
            self.preview = cg
            self.histogram = hist
        }
    }

    // Debounced via DispatchWorkItem, holding a latency-critical activity: App Nap
    // otherwise defers timer wakeups indefinitely while the app is backgrounded
    // (e.g. edits arriving over MCP), and the save would never land.
    private func scheduleSave() {
        saveItem?.cancel()
        if saveActivity == nil {
            saveActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical], reason: "sidecar save"
            )
        }
        let photo = photo
        let item = DispatchWorkItem { [weak self] in
            Sidecar.write(for: photo)
            if photo.hasEdits { Library.noteRecentEdit(photo.url) }
            self?.endSaveActivity()
        }
        saveItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    private func endSaveActivity() {
        if let activity = saveActivity {
            ProcessInfo.processInfo.endActivity(activity)
            saveActivity = nil
        }
    }

    func saveNow() {
        saveItem?.cancel()
        Sidecar.write(for: photo)
        if photo.hasEdits { Library.noteRecentEdit(photo.url) }
        endSaveActivity()
    }

    /// Scrub input from the canvas (ADR 0005): 1:1, fixed per-parameter sensitivity.
    func scrub(deltaX: CGFloat) {
        guard let armed else { return }
        let span = armed.range.upperBound - armed.range.lowerBound
        let old = armed.value(in: edit)
        armed.set(old + Double(deltaX) / 420 * span, in: &edit)
        HapticDetents.tickIfCrossed(parameter: armed, from: old, to: armed.value(in: edit))
    }
}
