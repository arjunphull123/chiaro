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
    var showOriginal = false
    var preview: CGImage?
    var originalPreview: CGImage?
    var histogram = HistogramData()
    var hasPerson: Bool?
    var isLoading = true
    var presetPreviews: [String: CGImage] = [:]

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
        presetPreviews = [:]
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

            // Tiny per-preset renders for the Looks carousel.
            let cards = await Offload.on(Offload.render) { () -> [String: CGImage] in
                let scale = 300 / max(base.extent.width, base.extent.height)
                let small = base.transformed(by: .init(scaleX: scale, y: scale))
                var cards: [String: CGImage] = [:]
                for preset in Preset.builtIn {
                    let out = RenderPipeline.render(base: small, edit: preset.edit, personMask: nil)
                    if let cg = RawEngine.shared.context.createCGImage(out, from: out.extent) {
                        cards[preset.name] = cg
                    }
                }
                return cards
            }
            guard self.photo.url == url else { return }
            self.presetPreviews = cards

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
        Task { [weak self] in
            let result = await Offload.on(Offload.render) { () -> (CGImage, HistogramData)? in
                let output = RenderPipeline.render(base: basePreview, edit: edit, personMask: mask)
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
