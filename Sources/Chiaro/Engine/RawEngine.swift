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
    private var previewCache: [CacheKey: CIImage] = [:]
    private var cacheOrder: [CacheKey] = []
    private let lock = NSLock()
    /// At most 3 full RAW decodes in flight — they're memory- and GPU-heavy.
    private let decodeGate = DispatchSemaphore(value: 3)

    private struct CacheKey: Hashable {
        let url: URL
        let decode: DecodeParams
    }

    /// The RAW decode-time controls (Tier 4, ADR: RAW decode parameters),
    /// isolated from the rest of EditState so a cache lookup only misses when
    /// a decode-relevant slider actually moved. Sliders are 0...100, matching
    /// the app's convention; `apply` maps that into CIRAWFilter's 0...1.
    struct DecodeParams: Hashable {
        var detail = 0.0          // sharpness
        var luminanceNoise = 0.0  // noiseReduction
        var colorNoise = 0.0      // colorNoiseReduction
        var moire = 0.0           // moireReduction
        static let neutral = DecodeParams()

        init() {}
        init(_ edit: EditState) {
            detail = edit.sharpness
            luminanceNoise = edit.noiseReduction
            colorNoise = edit.colorNoiseReduction
            moire = edit.moireReduction
        }
    }

    /// CIRAWFilter's own per-image recommendation (e.g. ~0.5 color NR, ISO-scaled
    /// luminance NR) is the slider's 0 point, not raw 0 — so a neutral EditState
    /// reproduces Apple's default decode instead of disabling detail/noise
    /// handling outright. 100 reaches the property's max (1.0).
    private static func scaled(_ slider: Double, from appleDefault: Float) -> Float {
        let t = Float(slider.clamped(to: 0...100) / 100)
        return appleDefault + (1 - appleDefault) * t
    }

    private static func apply(_ decode: DecodeParams, to raw: CIRAWFilter) {
        raw.detailAmount = scaled(decode.detail, from: raw.detailAmount)
        raw.luminanceNoiseReductionAmount = scaled(decode.luminanceNoise, from: raw.luminanceNoiseReductionAmount)
        raw.colorNoiseReductionAmount = scaled(decode.colorNoise, from: raw.colorNoiseReductionAmount)
        raw.moireReductionAmount = scaled(decode.moire, from: raw.moireReductionAmount)
    }

    func fullImage(for url: URL, decode: DecodeParams = .neutral) -> CIImage? {
        if let raw = CIRAWFilter(imageURL: url) {
            raw.extendedDynamicRangeAmount = 0
            Self.apply(decode, to: raw)
            if let image = raw.outputImage { return image }
        }
        return CIImage(contentsOf: url, options: [.applyOrientationProperty: true])
    }

    func preview(for url: URL, decode: DecodeParams = .neutral) -> CIImage? {
        let key = CacheKey(url: url, decode: decode)
        lock.lock()
        if let cached = previewCache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        decodeGate.wait()
        defer { decodeGate.signal() }
        guard let full = fullImage(for: url, decode: decode) else { return nil }
        let scale = min(1, Self.previewMaxDimension / max(full.extent.width, full.extent.height))
        var image = scale < 1
            ? full.transformed(by: .init(scaleX: scale, y: scale), highQualityDownsample: true)
            : full
        // Bake the downsample so every slider change doesn't re-run it.
        if let cg = context.createCGImage(image, from: image.extent) {
            image = CIImage(cgImage: cg)
        }

        lock.lock()
        previewCache[key] = image
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        while cacheOrder.count > 12 {
            previewCache.removeValue(forKey: cacheOrder.removeFirst())
        }
        lock.unlock()
        return image
    }
}
