import CoreImage
import Vision

/// Subject masks for portrait blur/relight, cached per photo and kind.
/// `.subject` = foreground instance lift (any salient subject — people, pets,
/// products); `.person` = person segmentation only.
final class PortraitEngine {
    static let shared = PortraitEngine()

    enum MaskKind: Hashable { case subject, person }
    private struct Key: Hashable {
        let url: URL
        let kind: MaskKind
    }

    private var cache: [Key: CIImage] = [:]
    private var misses: Set<Key> = []
    private let lock = NSLock()

    /// Returns a mask (white = kept sharp) scaled to `extent`, or nil if nothing found.
    func mask(for url: URL, image: CIImage, kind: MaskKind = .subject) -> CIImage? {
        let key = Key(url: url, kind: kind)
        lock.lock()
        if misses.contains(key) { lock.unlock(); return nil }
        if let cached = cache[key] {
            lock.unlock()
            return scaled(cached, to: image.extent, guide: image)
        }
        lock.unlock()

        let handler = VNImageRequestHandler(ciImage: image)
        var buffer: CVPixelBuffer?
        switch kind {
        case .subject:
            let request = VNGenerateForegroundInstanceMaskRequest()
            try? handler.perform([request])
            if let result = request.results?.first {
                buffer = try? result.generateScaledMaskForImage(
                    forInstances: result.allInstances, from: handler)
            }
        case .person:
            let request = VNGeneratePersonSegmentationRequest()
            request.qualityLevel = .balanced
            request.outputPixelFormat = kCVPixelFormatType_OneComponent8
            try? handler.perform([request])
            buffer = request.results?.first?.pixelBuffer
        }
        guard let buffer else {
            lock.lock(); misses.insert(key); lock.unlock()
            return nil
        }
        let mask = CIImage(cvPixelBuffer: buffer)

        // Reject empty masks (no meaningful coverage).
        let area = mask.applyingFilter("CIAreaAverage", parameters: [
            kCIInputExtentKey: CIVector(cgRect: mask.extent),
        ])
        var pixel = [UInt8](repeating: 0, count: 4)
        RawEngine.shared.context.render(
            area, toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: nil
        )
        guard pixel[0] > 8 else {
            lock.lock(); misses.insert(key); lock.unlock()
            return nil
        }

        lock.lock()
        cache[key] = mask
        if cache.count > 12 { cache.removeValue(forKey: cache.keys.first!) }
        lock.unlock()
        return scaled(mask, to: image.extent, guide: image)
    }

    /// Edge-preserving upsample guided by the photo — the mask hugs hair
    /// strands instead of blurring across them.
    private func scaled(_ mask: CIImage, to extent: CGRect, guide: CIImage) -> CIImage {
        let upsampled = guide.applyingFilter("CIEdgePreserveUpsampleFilter", parameters: [
            "inputSmallImage": mask,
        ])
        if upsampled.extent.width >= extent.width - 1 {
            return upsampled.clampedToExtent().cropped(to: extent)
        }
        let sx = extent.width / mask.extent.width
        let sy = extent.height / mask.extent.height
        return mask
            .transformed(by: .init(scaleX: sx, y: sy))
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 2.0])
            .cropped(to: extent)
    }
}
