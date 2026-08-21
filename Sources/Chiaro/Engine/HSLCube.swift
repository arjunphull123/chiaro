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
                            let w = weight(hue: h * 360, center: HSLBand.centers[i], halfWidth: halfWidths[i])
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

    /// Black & white conversion (ADR 0015): grey weighted by the mixer's per-band
    /// `l` values, sharing the exact hue weighting `apply` uses above — same
    /// falloff, same widened half-widths, so there's no separate dead zone to
    /// reintroduce. Cached separately since only `l` matters here.
    static func applyMonochrome(_ image: CIImage, bands: [HSLBand]) -> CIImage {
        image.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": dimension,
            "inputCubeData": monochromeData(for: bands),
            "inputColorSpace": CGColorSpace(name: CGColorSpace.displayP3)!,
        ])
    }

    private static func monochromeData(for bands: [HSLBand]) -> Data {
        let key = ("mono|" + bands.map { "\(Int($0.l))" }.joined(separator: "|")) as NSString
        if let cached = cache.object(forKey: key) { return cached as Data }

        let n = dimension
        var cube = [Float](repeating: 0, count: n * n * n * 4)
        var offset = 0
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let rr = Double(r) / Double(n - 1)
                    let gg = Double(g) / Double(n - 1)
                    let bb = Double(b) / Double(n - 1)
                    let luma = 0.2126 * rr + 0.7152 * gg + 0.0722 * bb
                    var grey = luma
                    let (h, s, _) = rgbToHsv(rr, gg, bb)
                    if s > 0.01 {
                        var lumGain = 0.0
                        for (i, band) in bands.enumerated() where band.l != 0 {
                            let w = weight(hue: h * 360, center: HSLBand.centers[i], halfWidth: halfWidths[i])
                            guard w > 0 else { continue }
                            lumGain += w * band.l
                        }
                        let confidence = min(1, s * 4)
                        grey = (luma * (1 + lumGain / 100 * 0.6 * confidence)).clamped(to: 0...1)
                    }
                    cube[offset] = Float(grey)
                    cube[offset + 1] = Float(grey)
                    cube[offset + 2] = Float(grey)
                    cube[offset + 3] = 1
                    offset += 4
                }
            }
        }
        let data = cube.withUnsafeBufferPointer { Data(buffer: $0) }
        cache.setObject(data as NSData, forKey: key)
        return data
    }

    /// Cosine falloff around the band center, ±45° with wraparound — widened
    /// per band so it always reaches the nearest neighboring center. Centers
    /// aren't evenly spaced (30° red↔orange↔yellow, 60° yellow↔green↔aqua↔blue,
    /// 45° blue↔purple↔magenta): a flat 45° leaves green and aqua, whose
    /// neighbors sit 60° out on both sides, with a dead zone between the
    /// bands — e.g. grass at hue ~70 (yellow-green) got zero weight from
    /// green even though it's the nearest "green" control available.
    private static let halfWidths: [Double] = HSLBand.centers.map { center in
        let nearestGap = HSLBand.centers
            .filter { $0 != center }
            .map { other -> Double in
                let d = abs(other - center)
                return min(d, 360 - d)
            }
            .min() ?? 45
        return max(45, nearestGap)
    }

    private static func weight(hue: Double, center: Double, halfWidth: Double) -> Double {
        var distance = abs(hue - center)
        if distance > 180 { distance = 360 - distance }
        guard distance < halfWidth else { return 0 }
        return 0.5 * (1 + cos(distance / halfWidth * .pi))
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
