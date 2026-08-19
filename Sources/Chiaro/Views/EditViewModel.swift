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
    var armed: EditParameter? {
        didSet {
            // Focus peaking overlays only while Focus is armed.
            let peakers: Set<EditParameter?> = [.focusDepth, .focusRange]
            guard armed != oldValue, peakers.contains(armed) || peakers.contains(oldValue) else { return }
            scheduleRender()
        }
    }
    /// One-shot click-to-focus: armed by the scope button next to Focus, the
    /// next canvas click sets the focus plane, then it disarms itself.
    var focusPicking = false {
        didSet {
            guard focusPicking != oldValue, !focusPicking else { return }
            NSCursor.arrow.set()
        }
    }
    /// Held-space pan: drag moves the photo even while a parameter is armed.
    var spacePan = false {
        didSet {
            guard spacePan != oldValue else { return }
            if spacePan { NSCursor.openHand.push() } else { NSCursor.pop() }
        }
    }
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
    private var maskKind: PortraitEngine.MaskKind = .subject
    /// Focos-style 3D depth scene visibility.
    var depthSceneVisible = false
    /// Depth histogram for the focal-range strip (48 bins, 0 near … 1 far).
    var depthHistogram: [Float]?
    private var histogramURL: URL?
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
        depthHistogram = nil
        histogramURL = nil
        depthSceneVisible = false
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

            self.maskKind = self.edit.blurMode == .person ? .person : .subject
            self.reloadMask()
        }
    }

    private func reloadMask() {
        guard let basePreview else { return }
        let url = photo.url
        let kind = maskKind
        Task { [weak self] in
            let mask = await Offload.on(Offload.vision) {
                PortraitEngine.shared.mask(for: url, image: basePreview, kind: kind)
            }
            guard let self, self.photo.url == url, self.maskKind == kind else { return }
            self.personMask = mask
            self.hasPerson = mask != nil
            if self.edit.blurF > 0 || self.edit.relight != 0 { self.scheduleRender() }
        }
    }

    /// Point grid for the 3D scene — heavy, so built on demand off-pool.
    func depthGrid() async -> DepthEngine.PointGrid? {
        guard let basePreview else { return nil }
        let url = photo.url
        return await Offload.on(Offload.render) {
            DepthEngine.shared.pointGrid(for: url, image: basePreview)
        }
    }

    func loadDepthHistogram() {
        guard histogramURL != photo.url, let basePreview else { return }
        histogramURL = photo.url
        let url = photo.url
        Task { [weak self] in
            let grid = await Offload.on(Offload.render) {
                DepthEngine.shared.pointGrid(for: url, image: basePreview, width: 64)
            }
            guard let self, self.photo.url == url else { return }
            self.depthHistogram = grid?.histogram
        }
    }

    func setBlurMode(_ mode: BlurMode) {
        if mode == .depth {
            enableDepthBlur()
        } else {
            edit.blurMode = mode
            depthSceneVisible = false
        }
    }

    /// Turning depth mode on auto-focuses the subject: mean disparity inside
    /// the person mask becomes the focus plane, so the first render is sharp
    /// where it should be instead of blurring the person (focus defaults mid-scene).
    func enableDepthBlur() {
        edit.blurMode = .depth
        // Auto-focus only on first use — switching Subject ↔ Depth must not
        // stomp a focus the user already set.
        guard edit.focusDepth == EditParameter.focusDepth.defaultValue, let basePreview else { return }
        let url = photo.url
        let mask = personMask
        Task { [weak self] in
            let focus = await Offload.on(Offload.render) { () -> Double? in
                guard let depth = DepthEngine.shared.depthMap(for: url, image: basePreview) else { return nil }
                return DepthEngine.subjectFocus(depth: depth, mask: mask)
            }
            guard let self, let focus, self.edit.blurMode == .depth else { return }
            self.edit.focusDepth = focus
        }
    }

    /// Click-to-focus: sample the depth map at a normalized canvas point
    /// (u, v top-down) and move the focus plane there.
    func focusAt(u: Double, v: Double) {
        guard edit.blurMode == .depth, let basePreview, (0...1).contains(u), (0...1).contains(v) else { return }
        let url = photo.url
        let editNow = edit
        let skipCrop = cropMode
        Task { [weak self] in
            let disparity = await Offload.on(Offload.render) { () -> Double? in
                guard let raw = DepthEngine.shared.depthMap(for: url, image: basePreview) else { return nil }
                let depth = RenderPipeline.applyGeometry(raw, edit: editNow, skipCrop: skipCrop)
                let e = depth.extent
                let x = e.origin.x + u * (e.width - 1)
                let y = e.origin.y + (1 - v) * (e.height - 1)
                var px = [Float](repeating: 0, count: 4)
                RawEngine.shared.context.render(
                    depth, toBitmap: &px, rowBytes: 16,
                    bounds: CGRect(x: x, y: y, width: 1, height: 1),
                    format: .RGBAf, colorSpace: nil
                )
                return Double(px[0])
            }
            guard let self, let disparity else { return }
            self.edit.focusDepth = (1 - disparity).clamped(to: 0...1)
        }
    }

    private func scheduleRender() {
        guard let basePreview else { return }
        let neededKind: PortraitEngine.MaskKind = edit.blurMode == .person ? .person : .subject
        if neededKind != maskKind {
            maskKind = neededKind
            reloadMask()
        }
        KeepAwake.poke()
        renderGeneration += 1
        let generation = renderGeneration
        let edit = edit
        let mask = personMask
        let skipCrop = cropMode
        let url = photo.url
        let peaking = (armed == .focusDepth || armed == .focusRange) && edit.blurMode == .depth
        Task { [weak self] in
            let result = await Offload.on(Offload.render) { () -> (CGImage, HistogramData)? in
                let depth = edit.blurMode == .depth && (edit.blurF > 0 || peaking)
                    ? DepthEngine.shared.depthMap(for: url, image: basePreview) : nil
                let output = RenderPipeline.render(base: basePreview, edit: edit, personMask: mask, depthMap: depth, skipCrop: skipCrop, focusPeaking: peaking)
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
