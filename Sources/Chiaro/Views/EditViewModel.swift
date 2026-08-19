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
            photo.edit = edit
            scheduleRender()
            scheduleSave()
        }
    }
    var armed: EditParameter?
    var showOriginal = false
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

    init(photo: Photo) {
        self.photo = photo
        self.edit = photo.edit
        load()
    }

    func switchTo(_ newPhoto: Photo) {
        guard newPhoto.url != photo.url else { return }
        saveNow()
        photo = newPhoto
        edit = newPhoto.edit
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
        let url = photo.url
        renderGeneration += 1
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let base = RawEngine.shared.preview(for: url) else { return }
            let baseCG = RawEngine.shared.context.createCGImage(base, from: base.extent)
            await MainActor.run { [weak self] in
                guard let self, self.photo.url == url else { return }
                self.basePreview = base
                self.originalPreview = baseCG
                self.isLoading = false
                self.scheduleRender()
            }
            let mask = PortraitEngine.shared.mask(for: url, image: base)
            await MainActor.run { [weak self] in
                guard let self, self.photo.url == url else { return }
                self.personMask = mask
                self.hasPerson = mask != nil
                if self.edit.blurF > 0 || self.edit.relight != 0 { self.scheduleRender() }
            }
        }
    }

    private func scheduleRender() {
        guard let basePreview else { return }
        renderGeneration += 1
        let generation = renderGeneration
        let edit = edit
        let mask = personMask
        Task.detached(priority: .userInitiated) { [weak self] in
            let output = RenderPipeline.render(base: basePreview, edit: edit, personMask: mask)
            guard let cg = RawEngine.shared.context.createCGImage(output, from: output.extent) else { return }
            let hist = HistogramSampler.sample(output)
            await MainActor.run { [weak self] in
                guard let self, generation == self.renderGeneration else { return }
                self.preview = cg
                self.histogram = hist
            }
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
