import CoreImage
import Foundation

/// Color-mixer LUT: the 8 hue bands baked into a CIColorCube, cached per
/// band configuration (LUT generation walks 64³ entries on the CPU).
enum HSLCube {
    static let dimension = 32
    private static let cache = NSCache<NSString, NSData>()

    static func apply(_ image: CIImage, bands: [HSLBand]) -> CIImage {
        image.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": dimension,
            "inputCubeData": data(for: bands),
            "inputColorSpace": CGColorSpace(name: CGColorSpace.displayP3)!,
        ])
    }

    private static func data(for bands: [HSLBand]) -> Data {
        // Integer-rounded keys so scrubbing hits the cache between ticks.
        let key = bands.map { "\(Int($0.h)),\(Int($0.s)),\(Int($0.l))" }.joined(separator: "|") as NSString
        if let cached = cache.object(forKey: key) { return cached as Data }

        let n = dimension
        var cube = [Float](repeating: 0, count: n * n * n * 4)
        var offset = 0
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    var (h, s, v) = rgbToHsv(
                        Double(r) / Double(n - 1),
                        Double(g) / Double(n - 1),
                        Double(b) / Double(n - 1)
                    )
                    if s > 0.01, v > 0.01 {
                        var hueShift = 0.0, satGain = 0.0, lumGain = 0.0
                        var total = 0.0
                        for (i, band) in bands.enumerated() where !band.isNeutral {
                            let w = weight(hue: h * 360, center: HSLBand.centers[i])
                            guard w > 0 else { continue }
                            hueShift += w * band.h
                            satGain += w * band.s
                            lumGain += w * band.l
                            total += w
                        }
                        if total > 0 {
                            // Near-gray pixels have unstable hue — fade the effect.
                            let confidence = min(1, s * 4)
                            h += hueShift / 100 * 0.09 * confidence // ±32°
                            h -= floor(h)
                            s = (s * (1 + satGain / 100 * confidence)).clamped(to: 0...1)
                            v = (v * (1 + lumGain / 100 * 0.6 * confidence)).clamped(to: 0...1)
                        }
                    }
                    let (nr, ng, nb) = hsvToRgb(h, s, v)
                    cube[offset] = Float(nr)
                    cube[offset + 1] = Float(ng)
                    cube[offset + 2] = Float(nb)
                    cube[offset + 3] = 1
                    offset += 4
                }
            }
        }
        let data = cube.withUnsafeBufferPointer { Data(buffer: $0) }
        cache.setObject(data as NSData, forKey: key)
        return data
    }

    /// Cosine falloff around the band center, ±45° with wraparound.
    private static func weight(hue: Double, center: Double) -> Double {
        var distance = abs(hue - center)
        if distance > 180 { distance = 360 - distance }
        guard distance < 45 else { return 0 }
        return 0.5 * (1 + cos(distance / 45 * .pi))
    }

    private static func rgbToHsv(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let maxC = max(r, g, b), minC = min(r, g, b)
        let delta = maxC - minC
        var h = 0.0
        if delta > 0 {
            if maxC == r { h = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxC == g { h = (b - r) / delta + 2 }
            else { h = (r - g) / delta + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        let s = maxC == 0 ? 0 : delta / maxC
        return (h, s, maxC)
    }

    private static func hsvToRgb(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
        let i = Int(h * 6) % 6
        let f = h * 6 - Double(Int(h * 6))
        let p = v * (1 - s)
        let q = v * (1 - f * s)
        let t = v * (1 - (1 - f) * s)
        switch i {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }
}
