import CoreML
import CoreImage
import Observation

/// On-device object removal (Clean up): LaMa inpainting, the model behind
/// most cleanup tools — removal only, no content invention, nothing uploaded.
/// The model is a fixed 512×512 pass, so inference runs on the mask's
/// bounding box expanded for context, and the patch composites back at
/// image resolution. Results cache per (photo, strokes).
final class CleanupEngine: @unchecked Sendable {
    static let shared = CleanupEngine()
    private let lock = NSLock()
    private var model: MLModel?
    private var cache: (key: String, patch: CIImage, base: CGRect)?

    var isReady: Bool {
        lock.lock(); defer { lock.unlock() }
        return model != nil
    }

    func install(_ model: MLModel) {
        lock.lock(); self.model = model; lock.unlock()
    }

    /// The base image with all strokes inpainted, or the original when the
    /// model is missing. Blocking — Offload only.
    func applied(to image: CIImage, url: URL, strokes: [CleanupStroke]) -> CIImage {
        guard !strokes.isEmpty else { return image }
        let key = "\(url.path)|\(strokes.map(\.cacheKey).joined())|\(Int(image.extent.width))"
        lock.lock()
        if let cache, cache.key == key {
            lock.unlock()
            return cache.patch
        }
        guard let model else {
            lock.unlock()
            fputs("CLEANUP: model not loaded\n", stderr)
            return image
        }
        lock.unlock()

        let extent = image.extent
        guard let maskImage = Self.rasterize(strokes: strokes, extent: extent) else { return image }

        // Context window: the strokes' bounding box, tripled, squared off.
        var bounds = CGRect.null
        for stroke in strokes {
            for point in stroke.points {
                let r = stroke.radius * extent.width
                bounds = bounds.union(CGRect(
                    x: point.x * extent.width - r,
                    y: (1 - point.y) * extent.height - r,
                    width: r * 2, height: r * 2
                ))
            }
        }
        let side = max(bounds.width, bounds.height) * 3
        let crop = CGRect(
            x: bounds.midX - side / 2, y: bounds.midY - side / 2,
            width: side, height: side
        ).intersection(extent)
        guard crop.width > 8, crop.height > 8 else { return image }

        guard let output = infer(
            model: model,
            image: image.cropped(to: crop),
            mask: maskImage.cropped(to: crop),
            crop: crop
        ) else { return image }

        // Feathered composite: the inpainted patch only where the strokes are.
        let feathered = maskImage
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: extent.width / 400])
            .cropped(to: extent)
        let blend = CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: output,
            kCIInputBackgroundImageKey: image,
            kCIInputMaskImageKey: feathered,
        ])
        let result = blend?.outputImage?.cropped(to: extent) ?? image

        lock.lock()
        cache = (key, result, extent)
        lock.unlock()
        return result
    }

    private func infer(model: MLModel, image: CIImage, mask: CIImage, crop: CGRect) -> CIImage? {
        let side = 512
        let context = RawEngine.shared.context

        func bitmap(_ source: CIImage) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: side * side * 4)
            let scaled = source
                .transformed(by: .init(translationX: -crop.origin.x, y: -crop.origin.y))
                .transformed(by: .init(scaleX: CGFloat(side) / crop.width, y: CGFloat(side) / crop.height))
            context.render(
                scaled, toBitmap: &bytes, rowBytes: side * 4,
                bounds: CGRect(x: 0, y: 0, width: side, height: side),
                format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
            )
            return bytes
        }

        do {
            let imageBytes = bitmap(image)
            let maskBytes = bitmap(mask)
            let imageArray = try MLMultiArray(shape: [1, 3, 512, 512], dataType: .float32)
            let maskArray = try MLMultiArray(shape: [1, 1, 512, 512], dataType: .float32)
            let plane = side * side
            let imagePointer = imageArray.dataPointer.bindMemory(to: Float32.self, capacity: plane * 3)
            let maskPointer = maskArray.dataPointer.bindMemory(to: Float32.self, capacity: plane)
            for i in 0..<plane {
                imagePointer[i] = Float32(imageBytes[i * 4]) / 255
                imagePointer[plane + i] = Float32(imageBytes[i * 4 + 1]) / 255
                imagePointer[plane * 2 + i] = Float32(imageBytes[i * 4 + 2]) / 255
                maskPointer[i] = maskBytes[i * 4] > 127 ? 1 : 0
            }
            let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: [
                "image": MLFeatureValue(multiArray: imageArray),
                "mask": MLFeatureValue(multiArray: maskArray),
            ]))
            guard let name = output.featureNames.first(where: {
                output.featureValue(for: $0)?.multiArrayValue != nil
            }), let result = output.featureValue(for: name)?.multiArrayValue else { return nil }

            // (1,3,512,512) float 0…1 (some conversions emit 0…255) → RGBA8.
            let outPointer = result.dataPointer.bindMemory(to: Float32.self, capacity: plane * 3)
            var peak: Float32 = 0
            for i in stride(from: 0, to: plane * 3, by: 97) { peak = max(peak, outPointer[i]) }
            let scale: Float32 = peak > 2 ? 1 : 255
            var rgba = [UInt8](repeating: 255, count: plane * 4)
            for i in 0..<plane {
                rgba[i * 4] = UInt8(max(0, min(255, outPointer[i] * scale)))
                rgba[i * 4 + 1] = UInt8(max(0, min(255, outPointer[plane + i] * scale)))
                rgba[i * 4 + 2] = UInt8(max(0, min(255, outPointer[plane * 2 + i] * scale)))
            }
            let patch = CIImage(
                bitmapData: Data(rgba), bytesPerRow: side * 4,
                size: CGSize(width: side, height: side),
                format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
            )
            // Bitmap rows are top-down; flip, then place back over the crop.
            return patch
                .transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -CGFloat(side)))
                .transformed(by: .init(scaleX: crop.width / CGFloat(side), y: crop.height / CGFloat(side)))
                .transformed(by: .init(translationX: crop.origin.x, y: crop.origin.y))
        } catch {
            fputs("CLEANUP: inference failed — \(error)\n", stderr)
            return nil
        }
    }

    /// Strokes → white-on-black mask aligned to the image (CI bottom-left).
    static func rasterize(strokes: [CleanupStroke], extent: CGRect) -> CIImage? {
        let width = Int(extent.width), height = Int(extent.height)
        guard let cg = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        cg.setFillColor(gray: 0, alpha: 1)
        cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
        cg.setStrokeColor(gray: 1, alpha: 1)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        for stroke in strokes {
            cg.setLineWidth(stroke.radius * 2 * CGFloat(width))
            let points = stroke.points.map {
                CGPoint(x: $0.x * CGFloat(width), y: (1 - $0.y) * CGFloat(height))
            }
            guard let first = points.first else { continue }
            cg.beginPath()
            cg.move(to: first)
            if points.count == 1 { cg.addLine(to: first) }
            for point in points.dropFirst() { cg.addLine(to: point) }
            cg.strokePath()
        }
        guard let maskCG = cg.makeImage() else { return nil }
        return CIImage(cgImage: maskCG)
            .transformed(by: .init(translationX: extent.origin.x, y: extent.origin.y))
    }
}

/// Download / compile lifecycle for the cleanup model, observable by the rail.
@Observable @MainActor
final class CleanupModelStore {
    static let shared = CleanupModelStore()

    var availability: DepthModelStore.Availability = .missing

    private nonisolated static let files: [(path: String, bytes: Int64)] = [
        ("Resources/LaMa.mlpackage/Manifest.json", 318),
        ("Resources/LaMa.mlpackage/Data/com.apple.CoreML/model.mlmodel", 1_386_464),
        ("Resources/LaMa.mlpackage/Data/com.apple.CoreML/weights/weight.bin", 38_472_128),
    ]
    private nonisolated static let baseURL = URL(string:
        "https://huggingface.co/Dadm-n/lama-dilated-coreml/resolve/main/")!
    private nonisolated static let modelsDir = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Chiaro/Models")
    private nonisolated static let packageURL = modelsDir.appendingPathComponent("LaMa.mlpackage")
    private nonisolated static let compiledURL = modelsDir.appendingPathComponent("LaMa.mlmodelc")

    private init() {
        if FileManager.default.fileExists(atPath: Self.compiledURL.path) {
            availability = .preparing
            loadCompiled()
        }
    }

    func downloadIfNeeded() {
        if case .downloading = availability { return }
        if case .ready = availability { return }
        if case .preparing = availability { return }
        availability = .downloading(0)
        KeepAwake.poke(600)
        Task {
            do {
                let total = Self.files.reduce(Int64(0)) { $0 + $1.bytes }
                var done: Int64 = 0
                for file in Self.files {
                    // Remote paths live under Resources/; locally the package sits flat.
                    let local = file.path.replacingOccurrences(of: "Resources/", with: "")
                    let target = Self.modelsDir.appendingPathComponent(local)
                    if (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) != file.bytes {
                        try FileManager.default.createDirectory(
                            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try await download(Self.baseURL.appendingPathComponent(file.path), to: target, offset: done, total: total)
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
                try? FileManager.default.removeItem(at: Self.packageURL)
                loadCompiled()
            } catch {
                availability = .failed(error.localizedDescription)
            }
        }
    }

    private func loadCompiled() {
        Task {
            let model = await Offload.on(Offload.vision) { () -> MLModel? in
                let config = MLModelConfiguration()
                // The ANE compiler chokes on LaMa's Fourier convolutions
                // (load hangs minutes); GPU runs it fine.
                config.computeUnits = .cpuAndGPU
                return try? MLModel(contentsOf: Self.compiledURL, configuration: config)
            }
            if let model {
                CleanupEngine.shared.install(model)
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
                    if case .downloading = CleanupModelStore.shared.availability {
                        CleanupModelStore.shared.availability = .downloading(Double(bytes) / Double(total))
                    }
                }
            }
            task.resume()
        }
        _ = try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: tmp, to: target)
    }
}
