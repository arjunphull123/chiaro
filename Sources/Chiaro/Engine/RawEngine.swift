import CoreImage
import AppKit

/// Decodes RAW (and non-RAW) files to linear CIImages and caches working previews.
final class RawEngine {
    static let shared = RawEngine()
    let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!,
        .cacheIntermediates: true,
    ])

    static let previewMaxDimension: CGFloat = 2048
    private var previewCache: [URL: CIImage] = [:]
    private var cacheOrder: [URL] = []
    private let lock = NSLock()

    func fullImage(for url: URL) -> CIImage? {
        if let raw = CIRAWFilter(imageURL: url) {
            raw.extendedDynamicRangeAmount = 0
            if let image = raw.outputImage { return image }
        }
        return CIImage(contentsOf: url, options: [.applyOrientationProperty: true])
    }

    func preview(for url: URL) -> CIImage? {
        lock.lock()
        if let cached = previewCache[url] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let full = fullImage(for: url) else { return nil }
        let scale = min(1, Self.previewMaxDimension / max(full.extent.width, full.extent.height))
        var image = scale < 1
            ? full.transformed(by: .init(scaleX: scale, y: scale), highQualityDownsample: true)
            : full
        // Bake the downsample so every slider change doesn't re-run it.
        if let cg = context.createCGImage(image, from: image.extent) {
            image = CIImage(cgImage: cg)
        }

        lock.lock()
        previewCache[url] = image
        cacheOrder.removeAll { $0 == url }
        cacheOrder.append(url)
        while cacheOrder.count > 12 {
            previewCache.removeValue(forKey: cacheOrder.removeFirst())
        }
        lock.unlock()
        return image
    }
}
