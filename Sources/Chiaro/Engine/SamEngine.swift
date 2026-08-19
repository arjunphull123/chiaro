import CoreML
import CoreImage
import Observation

/// Click-anything selection via Apple's Core ML build of SAM 2.1 (tiny):
/// drag a box on the photo, get the object's mask, and aim the focus plane
/// at its depth interval. Three models (image encoder, prompt encoder, mask
/// decoder), an 80 MB opt-in download like the depth model.
final class SamEngine: @unchecked Sendable {
    static let shared = SamEngine()
    private let lock = NSLock()
    private var imageEncoder: MLModel?
    private var promptEncoder: MLModel?
    private var maskDecoder: MLModel?
    /// The image embedding is the expensive pass — cache it per photo.
    private var embeddingCache: (url: URL, features: [String: MLFeatureValue])?

    var isReady: Bool {
        lock.lock(); defer { lock.unlock() }
        return maskDecoder != nil
    }

    func install(imageEncoder: MLModel, promptEncoder: MLModel, maskDecoder: MLModel) {
        lock.lock()
        self.imageEncoder = imageEncoder
        self.promptEncoder = promptEncoder
        self.maskDecoder = maskDecoder
        lock.unlock()
    }

    /// Segment whatever the normalized box (top-left origin) covers.
    /// Returns a mask aligned to `image`. Blocking — Offload only.
    func mask(for url: URL, image: CIImage, box: CGRect) -> CIImage? {
        lock.lock()
        guard let imageEncoder, let promptEncoder, let maskDecoder else {
            lock.unlock(); return nil
        }
        let cached = embeddingCache?.url == url ? embeddingCache?.features : nil
        lock.unlock()

        do {
            let features: [String: MLFeatureValue]
            if let cached {
                features = cached
            } else {
                guard let buffer = Self.pixelBuffer(from: image, side: 1024) else { return nil }
                let input = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: buffer)])
                let output = try imageEncoder.prediction(from: input)
                var collected: [String: MLFeatureValue] = [:]
                for name in output.featureNames {
                    collected[name] = output.featureValue(for: name)
                }
                features = collected
                lock.lock()
                embeddingCache = (url, features)
                lock.unlock()
            }

            // Box prompt: SAM's convention is two labeled corner points
            // (2 = top-left, 3 = bottom-right), in 1024-space.
            let points = try MLMultiArray(shape: [1, 2, 2], dataType: .float32)
            points[0] = NSNumber(value: Float(box.minX * 1024))
            points[1] = NSNumber(value: Float(box.minY * 1024))
            points[2] = NSNumber(value: Float(box.maxX * 1024))
            points[3] = NSNumber(value: Float(box.maxY * 1024))
            let labels = try MLMultiArray(shape: [1, 2], dataType: .int32)
            labels[0] = 2
            labels[1] = 3
            let promptOutput = try promptEncoder.prediction(from: MLDictionaryFeatureProvider(dictionary: [
                "points": MLFeatureValue(multiArray: points),
                "labels": MLFeatureValue(multiArray: labels),
            ]))

            // Match features to what the decoder declares — Apple's prompt
            // encoder pluralizes names ("sparse_embeddings") that the decoder
            // wants singular ("sparse_embedding").
            var available: [String: MLFeatureValue] = [:]
            for name in promptOutput.featureNames {
                available[name] = promptOutput.featureValue(for: name)
            }
            for (name, value) in features {
                available[name] = value
            }
            var decoderInputs: [String: MLFeatureValue] = [:]
            for wanted in maskDecoder.modelDescription.inputDescriptionsByName.keys {
                decoderInputs[wanted] = available[wanted] ?? available[wanted + "s"]
            }
            guard maskDecoder.modelDescription.inputDescriptionsByName.keys
                .allSatisfy({ decoderInputs[$0] != nil }) else { return nil }

            let decoded = try maskDecoder.prediction(from: MLDictionaryFeatureProvider(dictionary: decoderInputs))
            guard let scoresName = decoded.featureNames.first(where: { $0.localizedCaseInsensitiveContains("score") }),
                  let masksName = decoded.featureNames.first(where: { $0.localizedCaseInsensitiveContains("mask") }),
                  let scores = decoded.featureValue(for: scoresName)?.multiArrayValue,
                  let masks = decoded.featureValue(for: masksName)?.multiArrayValue else { return nil }

            var bestIndex = 0
            for i in 0..<scores.count where scores[i].floatValue > scores[bestIndex].floatValue {
                bestIndex = i
            }
            return Self.maskImage(from: masks, channel: bestIndex, extent: image.extent)
        } catch {
            return nil
        }
    }

    /// The object's disparity interval (10th–90th percentile inside the
    /// eroded mask — boundary cells blend into the background at grid
    /// resolution and would inflate the range).
    static func disparityInterval(mask: CIImage, grid: DepthEngine.PointGrid) -> ClosedRange<Double>? {
        let width = grid.width, height = grid.height
        let eroded = mask.applyingFilter("CIMorphologyMinimum", parameters: [
            kCIInputRadiusKey: mask.extent.width / 80,
        ]).cropped(to: mask.extent)
        let sx = CGFloat(width) / mask.extent.width
        let sy = CGFloat(height) / mask.extent.height
        let small = eroded
            .transformed(by: .init(scaleX: sx, y: sy))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        RawEngine.shared.context.render(
            small, toBitmap: &pixels, rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8, colorSpace: nil
        )
        var values: [Float] = []
        for i in 0..<(width * height) where pixels[i * 4] > 127 {
            values.append(grid.disparity[i])
        }
        guard values.count > 8 else { return nil }
        values.sort()
        let lo = Double(values[Int(Float(values.count) * 0.1)])
        let hi = Double(values[min(values.count - 1, Int(Float(values.count) * 0.9))])
        return lo...hi
    }

    /// Dev harness: dump model IO names so integration mismatches are loud.
    func debugDescribe() {
        lock.lock(); defer { lock.unlock() }
        for (label, model) in [("image", imageEncoder), ("prompt", promptEncoder), ("decoder", maskDecoder)] {
            guard let model else { continue }
            let inputs = model.modelDescription.inputDescriptionsByName.keys.sorted().joined(separator: ", ")
            let outputs = model.modelDescription.outputDescriptionsByName.keys.sorted().joined(separator: ", ")
            fputs("SAM \(label): in[\(inputs)] out[\(outputs)]\n", stderr)
        }
    }

    private static func pixelBuffer(from image: CIImage, side: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, side, side, kCVPixelFormatType_32BGRA, [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true,
        ] as CFDictionary, &buffer)
        guard let buffer else { return nil }
        let scaled = image.transformed(by: .init(
            scaleX: CGFloat(side) / image.extent.width,
            y: CGFloat(side) / image.extent.height
        ))
        RawEngine.shared.context.render(
            scaled, to: buffer,
            bounds: CGRect(x: 0, y: 0, width: side, height: side),
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return buffer
    }

    /// Logits (1×N×256×256 or N×256×256) → thresholded mask scaled to extent.
    private static func maskImage(from masks: MLMultiArray, channel: Int, extent: CGRect) -> CIImage? {
        let shape = masks.shape.map(\.intValue)
        guard shape.count >= 2 else { return nil }
        let height = shape[shape.count - 2]
        let width = shape[shape.count - 1]
        let plane = width * height
        var bytes = [UInt8](repeating: 0, count: plane)
        let base = channel * plane
        guard base + plane <= masks.count else { return nil }
        for i in 0..<plane {
            bytes[i] = masks[base + i].floatValue > 0 ? 255 : 0
        }
        let data = Data(bytes)
        guard let mask = CIImage(
            bitmapData: data, bytesPerRow: width,
            size: CGSize(width: width, height: height),
            format: .L8, colorSpace: nil
        ) as CIImage? else { return nil }
        // MLMultiArray rows are top-down; CIImage origin is bottom-left.
        return mask
            .transformed(by: CGAffineTransform(scaleX: 1, y: -1)
                .translatedBy(x: 0, y: -CGFloat(height)))
            .transformed(by: .init(
                scaleX: extent.width / CGFloat(width),
                y: extent.height / CGFloat(height)
            ))
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.5])
            .cropped(to: extent)
    }
}

/// Download / compile lifecycle for the SAM models, observable by the rail.
@Observable @MainActor
final class SamModelStore {
    static let shared = SamModelStore()

    var availability: DepthModelStore.Availability = .missing

    private nonisolated static let packages = [
        "SAM2_1TinyImageEncoderFLOAT16.mlpackage",
        "SAM2_1TinyPromptEncoderFLOAT16.mlpackage",
        "SAM2_1TinyMaskDecoderFLOAT16.mlpackage",
    ]
    private nonisolated static let files: [(path: String, bytes: Int64)] = [
        ("SAM2_1TinyImageEncoderFLOAT16.mlpackage/Manifest.json", 617),
        ("SAM2_1TinyImageEncoderFLOAT16.mlpackage/Data/com.apple.CoreML/model.mlmodel", 154_372),
        ("SAM2_1TinyImageEncoderFLOAT16.mlpackage/Data/com.apple.CoreML/weights/weight.bin", 67_069_504),
        ("SAM2_1TinyPromptEncoderFLOAT16.mlpackage/Manifest.json", 617),
        ("SAM2_1TinyPromptEncoderFLOAT16.mlpackage/Data/com.apple.CoreML/model.mlmodel", 20_618),
        ("SAM2_1TinyPromptEncoderFLOAT16.mlpackage/Data/com.apple.CoreML/weights/weight.bin", 2_101_056),
        ("SAM2_1TinyMaskDecoderFLOAT16.mlpackage/Manifest.json", 617),
        ("SAM2_1TinyMaskDecoderFLOAT16.mlpackage/Data/com.apple.CoreML/model.mlmodel", 75_167),
        ("SAM2_1TinyMaskDecoderFLOAT16.mlpackage/Data/com.apple.CoreML/weights/weight.bin", 10_222_400),
    ]
    private nonisolated static let baseURL = URL(string:
        "https://huggingface.co/apple/coreml-sam2.1-tiny/resolve/main/")!
    private nonisolated static let modelsDir = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Chiaro/Models")

    private nonisolated static func compiledURL(_ package: String) -> URL {
        modelsDir.appendingPathComponent(package.replacingOccurrences(of: ".mlpackage", with: ".mlmodelc"))
    }

    private init() {
        if Self.packages.allSatisfy({ FileManager.default.fileExists(atPath: Self.compiledURL($0).path) }) {
            availability = .preparing
            loadCompiled()
        }
    }

    func downloadIfNeeded() {
        if case .downloading = availability { return }
        if case .ready = availability { return }
        if case .preparing = availability { return }
        availability = .downloading(0)
        KeepAwake.poke(900)
        Task {
            do {
                let total = Self.files.reduce(Int64(0)) { $0 + $1.bytes }
                var done: Int64 = 0
                for file in Self.files {
                    let target = Self.modelsDir.appendingPathComponent(file.path)
                    if (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) != file.bytes {
                        try FileManager.default.createDirectory(
                            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try await download(Self.baseURL.appendingPathComponent(file.path), to: target, offset: done, total: total)
                    }
                    done += file.bytes
                    availability = .downloading(Double(done) / Double(total))
                }
                availability = .preparing
                for package in Self.packages {
                    let source = Self.modelsDir.appendingPathComponent(package)
                    let compiled = await Offload.on(Offload.vision) {
                        try? MLModel.compileModel(at: source)
                    }
                    guard let compiled else { throw URLError(.cannotParseResponse) }
                    _ = try? FileManager.default.removeItem(at: Self.compiledURL(package))
                    try FileManager.default.moveItem(at: compiled, to: Self.compiledURL(package))
                    try? FileManager.default.removeItem(at: source)
                }
                loadCompiled()
            } catch {
                availability = .failed(error.localizedDescription)
            }
        }
    }

    private func loadCompiled() {
        Task {
            let models = await Offload.on(Offload.vision) { () -> [MLModel]? in
                let config = MLModelConfiguration()
                config.computeUnits = .all
                let loaded = Self.packages.compactMap {
                    try? MLModel(contentsOf: Self.compiledURL($0), configuration: config)
                }
                return loaded.count == Self.packages.count ? loaded : nil
            }
            if let models {
                SamEngine.shared.install(imageEncoder: models[0], promptEncoder: models[1], maskDecoder: models[2])
                availability = .ready
            } else {
                availability = .failed("models failed to load")
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
                    if case .downloading = SamModelStore.shared.availability {
                        SamModelStore.shared.availability = .downloading(Double(bytes) / Double(total))
                    }
                }
            }
            task.resume()
        }
        _ = try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: tmp, to: target)
    }
}
