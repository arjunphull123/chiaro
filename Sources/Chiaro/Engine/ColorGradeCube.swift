import CoreImage
import Foundation

/// Colour grading by tonal zone (ADR 0015), baked into a `CIColorCube` the
/// way `HSLCube` bakes the mixer — grading is a pure function of a pixel's
/// own RGB for a fixed set of grading values, so it's exactly representable
/// as a LUT. (The prior implementation used `CIColorKernel(source:)`, the
/// deprecated CIKL API; its `sample` vs. required `__sample` typo made the
/// initializer return nil, so grading silently did nothing for as long as it
/// shipped.) Shadow/mid/highlight weights are Gaussian bells in luminance,
/// normalized to sum to 1 at every pixel — smooth, so gradients never band,
/// and no zone is ever double counted. Each zone's hue tints in at its own
/// strength, then the pixel's original luminance is restored so grading
/// shifts colour, never exposure.
enum ColorGradeCube {
    static let dimension = 32
    private static let cache = NSCache<NSString, NSData>()

    static func apply(_ image: CIImage, edit: EditState) -> CIImage {
        guard edit.shadowStrength != 0 || edit.midStrength != 0 || edit.highlightStrength != 0
        else { return image }
        return image.applyingFilter("CIColorCube", parameters: [
            "inputCubeDimension": dimension,
            "inputCubeData": data(for: edit),
        ])
    }

    private static func data(for edit: EditState) -> Data {
        // Integer-rounded key so scrubbing hits the cache between ticks.
        let key = [
            edit.shadowStrength, edit.shadowHue, edit.midStrength, edit.midHue,
            edit.highlightStrength, edit.highlightHue, edit.gradeBalance,
        ].map { String(Int($0)) }.joined(separator: "|") as NSString
        if let cached = cache.object(forKey: key) { return cached as Data }

        let n = dimension
        let shadowAmt = edit.shadowStrength / 100, midAmt = edit.midStrength / 100
        let highlightAmt = edit.highlightStrength / 100, balance = edit.gradeBalance / 100
        let chromaS = chromaOf(edit.shadowHue), chromaM = chromaOf(edit.midHue), chromaH = chromaOf(edit.highlightHue)

        var cube = [Float](repeating: 0, count: n * n * n * 4)
        var offset = 0
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let c = (
                        Double(r) / Double(n - 1),
                        Double(g) / Double(n - 1),
                        Double(b) / Double(n - 1)
                    )
                    let out = grade(
                        c, shadowAmt: shadowAmt, midAmt: midAmt, highlightAmt: highlightAmt,
                        balance: balance, chromaS: chromaS, chromaM: chromaM, chromaH: chromaH
                    )
                    cube[offset] = Float(out.0)
                    cube[offset + 1] = Float(out.1)
                    cube[offset + 2] = Float(out.2)
                    cube[offset + 3] = 1
                    offset += 4
                }
            }
        }
        let data = cube.withUnsafeBufferPointer { Data(buffer: $0) }
        cache.setObject(data as NSData, forKey: key)
        return data
    }

    private static let lumaWeights = (0.2126, 0.7152, 0.0722)

    private static func dot(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        a.0 * b.0 + a.1 * b.1 + a.2 * b.2
    }

    private static func hueColor(_ h: Double) -> (Double, Double, Double) {
        let hh = h.truncatingRemainder(dividingBy: 1.0) * 6.0
        let x = 1.0 - abs(hh.truncatingRemainder(dividingBy: 2.0) - 1.0)
        if hh < 1.0 { return (1.0, x, 0.0) }
        if hh < 2.0 { return (x, 1.0, 0.0) }
        if hh < 3.0 { return (0.0, 1.0, x) }
        if hh < 4.0 { return (0.0, x, 1.0) }
        if hh < 5.0 { return (x, 0.0, 1.0) }
        return (1.0, 0.0, x)
    }

    /// A hue as a zero-luminance chroma vector: adding it shifts colour without
    /// touching brightness, and without overwriting the pixel's own hue the way
    /// blending toward a full-chroma colour would.
    private static func chromaOf(_ degrees: Double) -> (Double, Double, Double) {
        let h = hueColor(degrees / 360.0)
        let l = dot(h, lumaWeights)
        return (h.0 - l, h.1 - l, h.2 - l)
    }

    private static func grade(
        _ c: (Double, Double, Double), shadowAmt: Double, midAmt: Double, highlightAmt: Double,
        balance: Double, chromaS: (Double, Double, Double), chromaM: (Double, Double, Double),
        chromaH: (Double, Double, Double)
    ) -> (Double, Double, Double) {
        let l = dot(c, lumaWeights)

        let shift = balance * 0.2
        // Narrow enough that a shadow grade leaves highlights alone: at 0.4 the
        // bells overlap so far that midtones take a quarter of the shadow tint.
        let sigma = 0.18
        let dS = l - shift, dM = l - 0.5, dH = l - 1.0 - shift
        var wS = exp(-(dS * dS) / (2.0 * sigma * sigma))
        var wM = exp(-(dM * dM) / (2.0 * sigma * sigma))
        var wH = exp(-(dH * dH) / (2.0 * sigma * sigma))
        let wSum = wS + wM + wH
        wS /= wSum; wM /= wSum; wH /= wSum

        let chroma = (
            chromaS.0 * (wS * shadowAmt) + chromaM.0 * (wM * midAmt) + chromaH.0 * (wH * highlightAmt),
            chromaS.1 * (wS * shadowAmt) + chromaM.1 * (wM * midAmt) + chromaH.1 * (wH * highlightAmt),
            chromaS.2 * (wS * shadowAmt) + chromaM.2 * (wM * midAmt) + chromaH.2 * (wH * highlightAmt)
        )

        // Protect colour that is already there. Tinting is mostly a subtraction
        // from one channel, so applied flat it strips the red out of bark and
        // brick and leaves them muddy. Neutral pixels take the full tint,
        // already-saturated ones barely any, which is how vibrance differs from
        // saturation.
        let mx = max(c.0, max(c.1, c.2))
        let mn = min(c.0, min(c.1, c.2))
        let existing = mx > 0.004 ? (mx - mn) / mx : 0.0
        let protect = (1.0 - existing) * (1.0 - existing)

        // A fixed chroma offset is a large *relative* shift on a dark pixel, so
        // this stays low: at 0.6 a shadow strength of 16 landed like 40.
        return (
            (c.0 + chroma.0 * 0.3 * protect).clamped(to: 0...1),
            (c.1 + chroma.1 * 0.3 * protect).clamped(to: 0...1),
            (c.2 + chroma.2 * 0.3 * protect).clamped(to: 0...1)
        )
    }
}
