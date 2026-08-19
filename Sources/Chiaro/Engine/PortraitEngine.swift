import CoreImage
import Vision

/// Subject masks for portrait blur/relight, cached per photo. Foreground
/// instance masking first (works for any salient subject — people, pets,
/// products), person segmentation as fallback.
final class PortraitEngine {
    static let shared = PortraitEngine()
    private var cache: [URL: CIImage] = [:]
    private var noPerson: Set<URL> = []
    private let lock = NSLock()

    /// Returns a mask (white = subject) scaled to `extent`, or nil if no subject found.
    func mask(for url: URL, image: CIImage) -> CIImage? {
        lock.lock()
        if noPerson.contains(url) { lock.unlock(); return nil }
        if let cached = cache[url] {
            lock.unlock()
            return scaled(cached, to: image.extent)
        }
        lock.unlock()

        let handler = VNImageRequestHandler(ciImage: image)
        var buffer: CVPixelBuffer?
        let foreground = VNGenerateForegroundInstanceMaskRequest()
        try? handler.perform([foreground])
        if let result = foreground.results?.first {
            buffer = try? result.generateScaledMaskForImage(
                forInstances: result.allInstances, from: handler)
        }
        if buffer == nil {
            let person = VNGeneratePersonSegmentationRequest()
            person.qualityLevel = .balanced
            person.outputPixelFormat = kCVPixelFormatType_OneComponent8
            try? handler.perform([person])
            buffer = person.results?.first?.pixelBuffer
        }
        guard let buffer else {
            lock.lock(); noPerson.insert(url); lock.unlock()
            return nil
        }
        let mask = CIImage(cvPixelBuffer: buffer)

        // Reject empty masks (no meaningful person coverage).
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
            lock.lock(); noPerson.insert(url); lock.unlock()
            return nil
        }

        lock.lock()
        cache[url] = mask
        if cache.count > 12 { cache.removeValue(forKey: cache.keys.first!) }
        lock.unlock()
        return scaled(mask, to: image.extent)
    }

    func hasPerson(for url: URL) -> Bool? {
        lock.lock(); defer { lock.unlock() }
        if noPerson.contains(url) { return false }
        if cache[url] != nil { return true }
        return nil
    }

    private func scaled(_ mask: CIImage, to extent: CGRect) -> CIImage {
        let sx = extent.width / mask.extent.width
        let sy = extent.height / mask.extent.height
        return mask
            .transformed(by: .init(scaleX: sx, y: sy))
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 2.0])
            .cropped(to: extent)
    }
}
