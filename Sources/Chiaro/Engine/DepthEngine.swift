import CoreML
import Vision
import CoreImage
import Observation

/// Monocular depth for depth-map blur, via Apple's Core ML build of
/// Depth Anything V2 (small, fp16). The model is not bundled — it's a 49.8 MB
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
        normalizedMap(for: url, image: image).map { scaled($0, to: image.extent, guide: image) }
    }

    /// The cached native-resolution normalized map (model output size).
    func normalizedMap(for url: URL, image: CIImage) -> CIImage? {
        lock.lock()
        if let cached = cache[url] {
            lock.unlock()
            return cached
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
        return normalized
    }

    /// Downsampled disparity + color grid for the 3D depth scene, plus the
    /// depth histogram for the focal-range strip. Blocking — Offload only.
    struct PointGrid: Sendable {
        var width: Int
        var height: Int
        var aspect: Float
        var disparity: [Float]     // width*height, row-major from top-left
        var colors: [UInt8]        // RGBA8, same order
        var histogram: [Float]     // normalized 0…1 counts over disparity bins
    }

    func pointGrid(for url: URL, image: CIImage, width: Int = 128, bins: Int = 48) -> PointGrid? {
        guard let map = normalizedMap(for: url, image: image) else { return nil }
        let aspect = Float(image.extent.width / image.extent.height)
        let height = max(2, Int((Float(width) / aspect).rounded()))
        let context = RawEngine.shared.context

        func resampled(_ source: CIImage) -> CIImage {
            let sx = CGFloat(width) / source.extent.width
            let sy = CGFloat(height) / source.extent.height
            return source
                .transformed(by: .init(scaleX: sx, y: sy))
                .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        }

        var depth = [Float](repeating: 0, count: width * height * 4)
        context.render(
            resampled(map), toBitmap: &depth, rowBytes: width * 16,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBAf, colorSpace: nil
        )
        var colors = [UInt8](repeating: 0, count: width * height * 4)
        context.render(
            resampled(image), toBitmap: &colors, rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )

        // render(toBitmap:) writes top-down — already top-left row-major.
        var disparity = [Float](repeating: 0, count: width * height)
        var histogram = [Float](repeating: 0, count: bins)
        for i in 0..<(width * height) {
            let d = depth[i * 4]
            disparity[i] = d
            histogram[min(bins - 1, max(0, Int(d * Float(bins))))] += 1
        }
        let peak = histogram.max() ?? 1
        if peak > 0 { for i in 0..<bins { histogram[i] /= peak } }
        return PointGrid(width: width, height: height, aspect: aspect,
                         disparity: disparity, colors: colors, histogram: histogram)
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

    /// Edge-preserving upsample guided by the photo — depth edges snap to
    /// image edges (hair, glasses) instead of smearing across them.
    private func scaled(_ map: CIImage, to extent: CGRect, guide: CIImage) -> CIImage {
        let upsampled = guide.applyingFilter("CIEdgePreserveUpsampleFilter", parameters: [
            "inputSmallImage": map,
        ])
        if upsampled.extent.width >= extent.width - 1 {
            return upsampled.clampedToExtent().cropped(to: extent)
        }
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
                // The source package is redundant once compiled — reclaim the 49.8 MB.
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
