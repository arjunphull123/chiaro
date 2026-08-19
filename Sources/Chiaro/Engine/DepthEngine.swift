import CoreML
import Vision
import CoreImage
import Observation

/// Monocular depth for depth-map blur, via Apple's Core ML build of
/// Depth Anything V2 (small, fp16). The model is not bundled — it's a 50 MB
/// download the user opts into from the Portrait section; weights live in
/// Application Support and compile once on first use.
final class DepthEngine: @unchecked Sendable {
    static let shared = DepthEngine()
    private let lock = NSLock()
    private var model: VNCoreMLModel?
    private var cache: [URL: CIImage] = [:]

    var isReady: Bool {
        lock.lock(); defer { lock.unlock() }
        return model != nil
    }

    func install(_ mlModel: MLModel) {
        let vn = try? VNCoreMLModel(for: mlModel)
        lock.lock(); model = vn; lock.unlock()
    }

    /// Normalized disparity map for the photo (1 = near, 0 = far), scaled to
    /// `extent`. Blocking — call from an Offload queue, never the cooperative pool.
    func depthMap(for url: URL, image: CIImage) -> CIImage? {
        lock.lock()
        if let cached = cache[url] {
            lock.unlock()
            return scaled(cached, to: image.extent)
        }
        guard let model else { lock.unlock(); return nil }
        lock.unlock()

        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(ciImage: image)
        try? handler.perform([request])
        guard let buffer = (request.results?.first as? VNPixelBufferObservation)?.pixelBuffer else {
            return nil
        }
        let raw = CIImage(cvPixelBuffer: buffer)

        // Normalize per image: read min/max back, then scale into 0…1.
        let minMax = raw.applyingFilter("CIAreaMinMax", parameters: [
            kCIInputExtentKey: CIVector(cgRect: raw.extent),
        ])
        var pixels = [Float](repeating: 0, count: 8)
        RawEngine.shared.context.render(
            minMax, toBitmap: &pixels, rowBytes: 32,
            bounds: CGRect(x: 0, y: 0, width: 2, height: 1),
            format: .RGBAf, colorSpace: nil
        )
        let lo = CGFloat(pixels[0]), hi = CGFloat(pixels[4])
        guard hi - lo > 0.001 else { return nil }
        let gain = 1 / (hi - lo)
        let normalized = raw.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: gain, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: gain, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: -lo * gain, y: -lo * gain, z: -lo * gain, w: 0),
        ])

        lock.lock()
        cache[url] = normalized
        if cache.count > 12 { cache.removeValue(forKey: cache.keys.first!) }
        lock.unlock()
        return scaled(normalized, to: image.extent)
    }

    /// Mean disparity inside the person mask → focusDepth (0 near … 1 far).
    /// nil when there's no person to focus on.
    static func subjectFocus(depth: CIImage, mask: CIImage?) -> Double? {
        guard let mask = mask?.cropped(to: depth.extent) else { return nil }
        let weighted = depth.applyingFilter("CIMultiplyCompositing", parameters: [
            kCIInputBackgroundImageKey: mask,
        ])
        func average(_ image: CIImage) -> Double {
            let area = image.applyingFilter("CIAreaAverage", parameters: [
                kCIInputExtentKey: CIVector(cgRect: depth.extent),
            ])
            var px = [Float](repeating: 0, count: 4)
            RawEngine.shared.context.render(
                area, toBitmap: &px, rowBytes: 16,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBAf, colorSpace: nil
            )
            return Double(px[0])
        }
        let maskMean = average(mask)
        guard maskMean > 0.01 else { return nil }
        let disparity = average(weighted) / maskMean
        return (1 - disparity).clamped(to: 0...1)
    }

    private func scaled(_ map: CIImage, to extent: CGRect) -> CIImage {
        let sx = extent.width / map.extent.width
        let sy = extent.height / map.extent.height
        return map
            .transformed(by: .init(scaleX: sx, y: sy))
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 3.0])
            .clampedToExtent()
            .cropped(to: extent)
    }
}

/// Download / compile lifecycle for the depth model, observable by the rail.
@Observable @MainActor
final class DepthModelStore {
    static let shared = DepthModelStore()

    enum Availability: Equatable {
        case missing
        case downloading(Double)
        case preparing
        case ready
        case failed(String)
    }
    var availability: Availability = .missing

    private nonisolated static let files: [(path: String, bytes: Int64)] = [
        ("Manifest.json", 617),
        ("Data/com.apple.CoreML/model.mlmodel", 399_433),
        ("Data/com.apple.CoreML/weights/weight.bin", 49_419_072),
    ]
    private nonisolated static let baseURL = URL(string:
        "https://huggingface.co/apple/coreml-depth-anything-v2-small/resolve/main/DepthAnythingV2SmallF16.mlpackage/")!
    private nonisolated static let modelsDir = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Chiaro/Models")
    private nonisolated static let packageURL = modelsDir.appendingPathComponent("DepthAnythingV2SmallF16.mlpackage")
    private nonisolated static let compiledURL = modelsDir.appendingPathComponent("DepthAnythingV2SmallF16.mlmodelc")

    private init() {
        if FileManager.default.fileExists(atPath: Self.compiledURL.path) {
            availability = .preparing
            loadCompiled()
        }
    }

    func downloadIfNeeded() {
        guard availability == .missing || isFailed else { return }
        availability = .downloading(0)
        KeepAwake.poke(600)
        Task {
            do {
                let total = Self.files.reduce(Int64(0)) { $0 + $1.bytes }
                var done: Int64 = 0
                for file in Self.files {
                    let target = Self.packageURL.appendingPathComponent(file.path)
                    if (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) != file.bytes {
                        try FileManager.default.createDirectory(
                            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                        let remote = Self.baseURL.appendingPathComponent(file.path)
                        try await download(remote, to: target, offset: done, total: total)
                    }
                    done += file.bytes
                    availability = .downloading(Double(done) / Double(total))
                }
                availability = .preparing
                let compiled = await Offload.on(Offload.vision) {
                    try? MLModel.compileModel(at: Self.packageURL)
                }
                guard let compiled else { throw URLError(.cannotParseResponse) }
                _ = try? FileManager.default.removeItem(at: Self.compiledURL)
                try FileManager.default.moveItem(at: compiled, to: Self.compiledURL)
                // The source package is redundant once compiled — reclaim the 48 MB.
                try? FileManager.default.removeItem(at: Self.packageURL)
                loadCompiled()
            } catch {
                availability = .failed(error.localizedDescription)
            }
        }
    }

    private var isFailed: Bool {
        if case .failed = availability { return true }
        return false
    }

    private func loadCompiled() {
        Task {
            let model = await Offload.on(Offload.vision) { () -> MLModel? in
                let config = MLModelConfiguration()
                config.computeUnits = .all
                return try? MLModel(contentsOf: Self.compiledURL, configuration: config)
            }
            if let model {
                DepthEngine.shared.install(model)
                availability = .ready
            } else {
                availability = .failed("model failed to load")
            }
        }
    }

    private func download(_ remote: URL, to target: URL, offset: Int64, total: Int64) async throws {
        let tmp: URL = try await withCheckedThrowingContinuation { continuation in
            var observation: NSKeyValueObservation?
            let task = URLSession.shared.downloadTask(with: remote) { tmp, response, error in
                observation?.invalidate()
                if let tmp, (response as? HTTPURLResponse).map({ $0.statusCode == 200 }) ?? false {
                    // Move immediately — the temp file dies when this handler returns.
                    let held = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                    do {
                        try FileManager.default.moveItem(at: tmp, to: held)
                        continuation.resume(returning: held)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume(throwing: error ?? URLError(.badServerResponse))
                }
            }
            observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                let bytes = offset + Int64(progress.fractionCompleted * Double(task.countOfBytesExpectedToReceive))
                Task { @MainActor in
                    DepthModelStore.shared.availability = .downloading(Double(bytes) / Double(total))
                }
            }
            task.resume()
        }
        _ = try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: tmp, to: target)
    }
}
