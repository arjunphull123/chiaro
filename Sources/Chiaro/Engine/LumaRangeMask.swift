import CoreImage
import Foundation

/// Luminance range mask for local adjustments (Lightroom's range mask):
/// narrows an adjustment's geometric mask to a smooth tone band, e.g.
/// "shadows only" inside a radial.
///
/// Baked into a cube like `HSLCube`/`ColorGradeCube`, but deliberately the
/// PLAIN `CIColorCube`, not the `WithColorSpace` variant those two need. The
/// difference is what the cube's output means. Those emit a colour, so they
/// want Core Image to convert their gamma-encoded result back into the
/// extended-linear P3 working space. This emits a coefficient, and that same
/// return conversion would corrupt it: a 0.5 in the cube comes back as 0.218,
/// which leaves the feather monotonic but crushed, so mid-feather pixels take
/// a fifth of the adjustment instead of half. Untagged, the value passes
/// through untouched.
///
/// The linear working space still has to be reckoned with on the way IN, which
/// is what the `WithColorSpace` variant would otherwise have handled: cube
/// indices arrive as linear light, and `lumaLow`/`lumaHigh` describe perceptual
/// tone, so luminance is gamma-encoded here before it is compared against them.
enum LumaRangeMask {
    static let dimension = 32
    private static let cache = NSCache<NSString, NSData>()
    private static let lumaWeights = (0.2126, 0.7152, 0.0722)

    /// A window narrower than twice this feathers by the floor instead of a
    /// tenth of its own width, so a zero-width window still fades rather than
    /// posterising.
    private static let minFeather = 4.0

    static func apply(_ image: CIImage, low: Double, high: Double) -> CIImage {
        image.applyingFilter("CIColorCube", parameters: [
            "inputCubeDimension": dimension,
            "inputCubeData": data(low: low, high: high),
        ])
    }

    /// 1 across [low, high], smoothly fading to 0 outside. Feather is a tenth
    /// of the window's own width (floored), so a narrow selection gets a narrow
    /// feather and a wide one a wide feather, and gradients never band.
    ///
    /// Normalised by its own peak. Below a width of twice the feather floor the
    /// two edges overlap, which would otherwise drop the peak to 0.25 at zero
    /// width: a tight tonal selection would quietly apply a quarter of the
    /// adjustment with nothing on screen to explain why. Normalising keeps the
    /// edges smooth and the centre at full strength.
    ///
    /// A bound sitting on the 0...100 domain edge has nothing beyond it to fade
    /// into, so that side skips feathering. That is what keeps the fully-open
    /// (0, 100) window exactly 1 everywhere, which a default `LocalAdjustment`
    /// depends on to stay inert.
    static func window(luma: Double, low: Double, high: Double) -> Double {
        // Two independent sliders can cross. Read a crossed pair as the band
        // between them rather than as an empty or inverted selection.
        let lo = min(low, high), hi = max(low, high)
        let peak = raw(luma: (lo + hi) / 2, low: lo, high: hi)
        guard peak > 0 else { return 0 }
        return min(raw(luma: luma, low: lo, high: hi) / peak, 1)
    }

    private static func raw(luma: Double, low: Double, high: Double) -> Double {
        let feather = max(minFeather, (high - low) * 0.1)
        let rising = low <= 0 ? 1 : smoothstep(low - feather, low + feather, luma)
        let falling = high >= 100 ? 1 : 1 - smoothstep(high - feather, high + feather, luma)
        return rising * falling
    }

    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = ((x - edge0) / (edge1 - edge0)).clamped(to: 0...1)
        return t * t * (3 - 2 * t)
    }

    private static func data(low: Double, high: Double) -> Data {
        let key = "\(Int(low))|\(Int(high))" as NSString
        if let cached = cache.object(forKey: key) { return cached as Data }

        let n = dimension
        var cube = [Float](repeating: 0, count: n * n * n * 4)
        var offset = 0
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let rf = Double(r) / Double(n - 1)
                    let gf = Double(g) / Double(n - 1)
                    let bf = Double(b) / Double(n - 1)
                    let linear = rf * lumaWeights.0 + gf * lumaWeights.1 + bf * lumaWeights.2
                    // Gamma-encode before comparing: see the note on the type.
                    let luma = pow(max(linear, 0), 1.0 / 2.2) * 100
                    let w = Float(window(luma: luma, low: low, high: high))
                    cube[offset] = w
                    cube[offset + 1] = w
                    cube[offset + 2] = w
                    cube[offset + 3] = 1
                    offset += 4
                }
            }
        }
        let data = cube.withUnsafeBufferPointer { Data(buffer: $0) }
        cache.setObject(data as NSData, forKey: key)
        return data
    }
}
