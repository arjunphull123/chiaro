import SwiftUI
import Vision
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
                }
                redoStack.removeAll()
                lastEditAt = Date()
                // Any change that isn't auto-enhance's own assignment invalidates
                // the toggle — "Auto" is only true while its exact edit still holds.
                if !isAutoEnhancing {
                    autoApplied = false
                    preAutoEdit = nil
                }
            }
            photo.edit = edit
            scheduleRender()
            scheduleSave()
        }
    }

    /// Bypasses coalescing: forces this change to start a fresh undo step even
    /// inside the 0.8s window (versions, presets, paste, revert, auto-enhance).
    func commitDiscrete(_ new: EditState) {
        lastEditAt = .distantPast
        edit = new
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(edit)
        isRestoringEdit = true
        edit = previous
        isRestoringEdit = false
        lastEditAt = Date()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(edit)
        isRestoringEdit = true
        edit = next
        isRestoringEdit = false
        lastEditAt = Date()
    }
    /// Which color-mix control is armed (drives the same glass dial).
    enum HSLComponent: String {
        case h = "Hue", s = "Saturation", l = "Luminance"
        var keyPath: WritableKeyPath<HSLBand, Double> {
            switch self {
            case .h: \.h
            case .s: \.s
            case .l: \.l
            }
        }
    }
    var armedHSL: (band: Int, component: HSLComponent)? {
        didSet { if armedHSL != nil { armed = nil; armedLocal = nil } }
    }

    var armed: EditParameter? {
        didSet {
            if armed != nil { armedHSL = nil; armedLocal = nil }
            // Focus peaking overlays only while Focus is armed.
            guard armed != oldValue, armed == .focusDepth || oldValue == .focusDepth else { return }
            scheduleRender()
        }
    }
    /// Which local adjustment field is armed (drives the same glass dial).
    /// Identified by UUID, not array index — `locals` can shrink mid-drag
    /// (an agent's `set_edit`), same reason `RailView.localRow` resolves by id.
    /// Label and range ride along from the row that armed it, rather than a
    /// second table of per-field ranges living in the view model.
    var armedLocal: (id: UUID, keyPath: WritableKeyPath<LocalAdjustment, Double>, label: String, range: ClosedRange<Double>)? {
        didSet { if armedLocal != nil { armed = nil; armedHSL = nil } }
    }
    /// The local adjustment being edited (gizmo shows on the canvas).
    var selectedLocalID: UUID?

    /// Clipping warnings — red blown highlights, blue crushed blacks (J).
    var showClipping = false {
        didSet { scheduleRender() }
    }

    /// Canvas zoom/pan, lifted here so the toolbar can drive them.
    var canvasZoom: CGFloat = 1
    var canvasPan: CGSize = .zero
    /// One-shot request: zoom so preview pixels map 1:1 to screen points.
    var pixelZoomRequested = false

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
    /// Which RAW-only Detail controls still do anything for this photo's
    /// decoder (RailView hides the rest rather than leaving a dead slider).
    var decodeCapabilities = RawEngine.DecodeCapabilities.allSupported
    private var personMask: CIImage?
    private var maskKind: PortraitEngine.MaskKind = .subject
    /// 3D depth scene visibility, and one-shot commands routed to it
    /// (exit / view presets) — the scene lives behind an NSViewRepresentable.
    var depthSceneVisible = false {
        didSet {
            if depthSceneVisible {
                armed = nil
                armedHSL = nil
                armedLocal = nil
            }
        }
    }
    var depthSceneCommand: DepthSceneCommand?
    /// Orbit state, shared with the orientation cube.
    var sceneYaw: CGFloat = DepthScene.restYaw
    var scenePitch: CGFloat = DepthScene.restPitch
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
        autoApplied = false
        preAutoEdit = nil
        cropMode = false
        cropAspect = nil
        cropAspectName = nil
        showClipping = false
        preview = nil
        originalPreview = nil
        basePreview = nil
        decodeCapabilities = .allSupported
        personMask = nil
        hasPerson = nil
        depthSceneVisible = false
        depthSceneCommand = nil
        isLoading = true
        load()
    }

    private func load() {
        KeepAwake.poke(30)
        let url = photo.url
        let isRAW = photo.isRAW
        renderGeneration += 1
        Task { [weak self] in
            guard let decoded = await Offload.on(Offload.render, { () -> (CIImage, CGImage?, RawEngine.DecodeCapabilities)? in
                guard let base = RawEngine.shared.preview(for: url) else { return nil }
                let capabilities = isRAW ? RawEngine.shared.decodeCapabilities(for: url) : .allSupported
                return (base, RawEngine.shared.context.createCGImage(base, from: base.extent), capabilities)
            }) else { return }
            let (base, baseCG, capabilities) = decoded
            guard let self, self.photo.url == url else { return }
            self.basePreview = base
            self.originalPreview = baseCG
            self.decodeCapabilities = capabilities
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

    /// Auto-level: Vision's horizon detector sets the straighten angle.
    func autoLevel() {
        guard let basePreview else { return }
        Task { [weak self] in
            let angle = await Offload.on(Offload.vision) { () -> Double? in
                let request = VNDetectHorizonRequest()
                let handler = VNImageRequestHandler(ciImage: basePreview)
                try? handler.perform([request])
                guard let observation = request.results?.first else { return nil }
                return Double(observation.angle) * 180 / .pi
            }
            guard let self, let angle else { return }
            self.edit.straighten = (-angle).clamped(to: -45...45)
        }
    }

    /// Auto headshot: find the face, frame it 4:5 with headroom.
    func autoHeadshotCrop() {
        guard let basePreview, let cg = preview else { return }
        let imageAspect = Double(cg.width) / Double(cg.height)
        Task { [weak self] in
            let face = await Offload.on(Offload.vision) { () -> CGRect? in
                let request = VNDetectFaceRectanglesRequest()
                let handler = VNImageRequestHandler(ciImage: basePreview)
                try? handler.perform([request])
                let faces = request.results ?? []
                // The biggest face wins.
                return faces.max(by: { $0.boundingBox.height < $1.boundingBox.height })?.boundingBox
            }
            guard let self, let face else { return }
            // Vision boxes are bottom-left origin; crop space is top-down.
            let faceTop = 1 - (face.origin.y + face.height)
            let faceCenterX = face.origin.x + face.width / 2
            let cropH = (Double(face.height) / 0.42).clamped(to: 0.2...1)
            let cropW = (0.8 * cropH / imageAspect).clamped(to: 0.1...1)
            var crop = CropRect(
                x: faceCenterX - cropW / 2,
                y: Double(faceTop) - cropH * 0.17,
                w: cropW, h: cropH
            )
            crop.x = crop.x.clamped(to: 0...(1 - crop.w))
            crop.y = crop.y.clamped(to: 0...(1 - crop.h))
            self.edit.crop = crop
            self.cropAspectName = nil
        }
    }

    func saveVersion(named name: String) {
        photo.snapshots.append(Sidecar.Snapshot(name: name, date: Date(), edit: edit))
        Sidecar.write(for: photo)
    }

    func applyVersion(_ snapshot: Sidecar.Snapshot) {
        commitDiscrete(snapshot.edit)
    }

    func deleteVersion(_ snapshot: Sidecar.Snapshot) {
        photo.snapshots.removeAll { $0.id == snapshot.id }
        Sidecar.write(for: photo)
    }

    /// The wand is a toggle: apply the auto edit, or click again to restore
    /// whatever was there before.
    var autoApplied = false
    private var preAutoEdit: EditState?
    /// Guards edit.didSet's staleness check against auto-enhance's own assignment.
    private var isAutoEnhancing = false

    func autoEnhance() {
        if autoApplied {
            if let preAutoEdit {
                isAutoEnhancing = true
                commitDiscrete(preAutoEdit)
                isAutoEnhancing = false
            }
            autoApplied = false
            return
        }
        guard let basePreview else { return }
        let mask = personMask
        let current = edit
        let isRAW = photo.isRAW
        Task { [weak self] in
            let enhanced = await Offload.on(Offload.render) {
                AutoEnhance.compute(base: basePreview, subjectMask: mask, isRAW: isRAW, onto: current)
            }
            guard let self, let enhanced else { return }
            self.preAutoEdit = current
            self.isAutoEnhancing = true
            self.commitDiscrete(enhanced)
            self.isAutoEnhancing = false
            self.autoApplied = true
        }
    }

    func setBlurMode(_ mode: BlurMode) {
        if mode == .depth {
            enableDepthBlur()
        } else {
            edit.selectBlurMode(mode)
            depthSceneVisible = false
        }
    }

    /// Turning depth mode on auto-focuses the subject: mean disparity inside
    /// the person mask becomes the focus plane, so the first render is sharp
    /// where it should be instead of blurring the person (focus defaults mid-scene).
    func enableDepthBlur() {
        edit.selectBlurMode(.depth)
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
            // The plane sits just behind the subject, not through it.
            self.edit.focusDepth = (focus + 0.14).clamped(to: 0...1)
        }
    }

    private func scheduleRender() {
        guard basePreview != nil else { return }
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
        let isRAW = photo.isRAW
        let decode = RawEngine.DecodeParams(edit)
        let peaking = armed == .focusDepth && edit.blurMode == .depth
        let clipping = showClipping
        Task { [weak self] in
            let result = await Offload.on(Offload.render) { () -> (CGImage, HistogramData)? in
                // Re-fetched (not the cached `basePreview` captured at load) so a
                // sharpness/noise-reduction change reaches RAW decode; RawEngine's
                // own cache keeps this a no-op redecode when nothing changed.
                guard let base = RawEngine.shared.preview(for: url, decode: decode) else { return nil }
                let depth = edit.blurMode == .depth && (edit.blurF > 0 || peaking)
                    ? DepthEngine.shared.depthMap(for: url, image: base) : nil
                let output = RenderPipeline.render(base: base, edit: edit, personMask: mask, depthMap: depth, isRAW: isRAW, skipCrop: skipCrop, focusPeaking: peaking, clippingWarnings: clipping)
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
    /// The raw (unsnapped) position accumulates separately so detents have real
    /// resistance: the value holds at the detent until the finger travels out of
    /// the window, instead of re-capturing every tick and pinning slow scrubs.
    private var scrubRaw: Double?
    private var scrubAnchor: Double?

    /// Shared core: accumulate the unsnapped position, capture at the neutral
    /// detent with symmetric resistance.
    private func scrubbed(old: Double, deltaX: CGFloat, unitPerPx: Double,
                          range: ClosedRange<Double>, detent: Double, window: Double) -> Double {
        if scrubRaw == nil || scrubAnchor != old { scrubRaw = old }
        let raw = (scrubRaw! + Double(deltaX) * unitPerPx).clamped(to: range)
        scrubRaw = raw
        return abs(raw - detent) < window ? detent : raw
    }

    func scrub(deltaX: CGFloat) {
        if let armedHSL {
            let keyPath = armedHSL.component.keyPath
            let old = edit.hsl[armedHSL.band][keyPath: keyPath]
            let new = scrubbed(old: old, deltaX: deltaX, unitPerPx: 200 / 420,
                               range: -100...100, detent: 0, window: 6)
            edit.hsl[armedHSL.band][keyPath: keyPath] = new
            scrubAnchor = new
            HapticDetents.ticks(span: 200, from: old, to: new, detent: 0)
            return
        }
        if let armedLocal, let i = edit.locals.firstIndex(where: { $0.id == armedLocal.id }) {
            let keyPath = armedLocal.keyPath
            let range = armedLocal.range
            let span = range.upperBound - range.lowerBound
            let detent = LocalAdjustment.defaults[keyPath: keyPath]
            let old = edit.locals[i][keyPath: keyPath]
            let new = scrubbed(old: old, deltaX: deltaX, unitPerPx: span / 420,
                               range: range, detent: detent, window: span * 0.03)
            edit.locals[i][keyPath: keyPath] = new
            scrubAnchor = new
            HapticDetents.ticks(span: span, from: old, to: new, detent: detent)
            return
        }
        guard let armed else { return }
        let span = armed.range.upperBound - armed.range.lowerBound
        let old = armed.value(in: edit)
        let new = scrubbed(old: old, deltaX: deltaX, unitPerPx: span / 420,
                           range: armed.range, detent: armed.defaultValue, window: span * 0.03)
        armed.set(new, in: &edit)
        scrubAnchor = armed.value(in: edit)
        HapticDetents.ticks(span: span, from: old, to: armed.value(in: edit), detent: armed.defaultValue)
    }

    func scrubStraighten(deltaX: CGFloat) {
        let old = edit.straighten
        let new = scrubbed(old: old, deltaX: deltaX, unitPerPx: 1 / 8,
                           range: -45...45, detent: 0, window: 1)
        edit.straighten = new
        scrubAnchor = new
        HapticDetents.ticks(span: 90, from: old, to: new, detent: 0)
    }

    func scrubFocusDepth(deltaX: CGFloat) {
        let old = edit.focusDepth
        let new = scrubbed(old: old, deltaX: deltaX, unitPerPx: 1 / 260,
                           range: 0...1, detent: 0.5, window: 0.03)
        edit.focusDepth = new
        scrubAnchor = new
        HapticDetents.ticks(span: 1, from: old, to: new, detent: 0.5)
    }

    /// Arrow keys: exactly one minimum display unit, no snapping — the
    /// refinement tool after a coarse scrub.
    func nudge(_ direction: Int) {
        if let armedHSL {
            let keyPath = armedHSL.component.keyPath
            let old = edit.hsl[armedHSL.band][keyPath: keyPath]
            edit.hsl[armedHSL.band][keyPath: keyPath] = (old + Double(direction)).clamped(to: -100...100)
        } else if let armedLocal, let i = edit.locals.firstIndex(where: { $0.id == armedLocal.id }) {
            let keyPath = armedLocal.keyPath
            let range = armedLocal.range
            let nudgeStep = range.upperBound <= 3 ? 0.01 : 1.0  // EV fields (exposure) vs. everything else
            edit.locals[i][keyPath: keyPath] = (edit.locals[i][keyPath: keyPath] + Double(direction) * nudgeStep)
                .clamped(to: range)
        } else if let armed {
            armed.set(armed.value(in: edit) + Double(direction) * armed.nudgeStep, in: &edit)
        } else if cropMode {
            edit.straighten = (edit.straighten + Double(direction) * EditParameter.straighten.nudgeStep)
                .clamped(to: -45...45)
        }
        scrubRaw = nil
    }
}
