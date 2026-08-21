import CoreImage

/// The wand: histogram-percentile auto-adjust in the RawTherapee/darktable
/// family. Black/white points from 0.5/99.5 luminance percentiles (clipped
/// pixels excluded from statistics), exposure toward a median target with the
/// subject's luminance weighted in when a person is detected, gray-world
/// white balance, and conservative clamps throughout — a starting point,
/// never a look.
enum AutoEnhance {
    static func compute(base: CIImage, subjectMask: CIImage?, onto current: EditState) -> EditState? {
        let n = 96

        func bitmap(_ source: CIImage) -> [UInt8] {
            PixelStats.readRGBA(source, width: n, height: n, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        }

        let pixels = bitmap(base)
        let maskPixels = subjectMask.map(bitmap)

        var lumas: [Double] = []
        var sumR = 0.0, sumG = 0.0, sumB = 0.0, wbCount = 0.0
        var saturationSum = 0.0, saturationCount = 0.0
        var subjectLumaSum = 0.0, subjectWeight = 0.0
        var highlightClipped = 0.0, shadowCrushed = 0.0

        // Soft "about to clip" gate for the recovery sliders, not a literal
        // 0/255 rail check — deliberately looser than StatsSampler's clip
        // thresholds, which report whether a channel actually hit the rail.
        let highlightGate = 0.98, shadowGate = 0.02

        for i in 0..<(n * n) {
            let r = Double(pixels[i * 4]) / 255
            let g = Double(pixels[i * 4 + 1]) / 255
            let b = Double(pixels[i * 4 + 2]) / 255
            let luma = PixelStats.luminance(r, g, b)
            lumas.append(luma)
            let hi = max(r, g, b), lo = min(r, g, b)
            if hi > highlightGate { highlightClipped += 1 }
            if hi < shadowGate { shadowCrushed += 1 }
            if hi < highlightGate, lo > 0.01 {
                let saturation = PixelStats.saturation(hi: hi, lo: lo)
                saturationSum += saturation
                saturationCount += 1
                // Robust gray-world: only near-neutral pixels vote, so a
                // vegetation-heavy frame can't drag skin toward magenta.
                if saturation < 0.25 {
                    sumR += r; sumG += g; sumB += b; wbCount += 1
                }
            }
            if let maskPixels {
                let w = Double(maskPixels[i * 4]) / 255
                subjectLumaSum += luma * w
                subjectWeight += w
            }
        }
        guard !lumas.isEmpty else { return nil }
        lumas.sort()
        func percentile(_ p: Double) -> Double {
            lumas[min(lumas.count - 1, Int(Double(lumas.count) * p))]
        }
        let p005 = percentile(0.005)
        let median = percentile(0.5)
        let p995 = percentile(0.995)
        let total = Double(n * n)

        var edit = current

        // Exposure: median toward 0.42, subject-weighted 60/40 when present.
        var metered = median
        if subjectWeight > total * 0.02 {
            metered = 0.6 * (subjectLumaSum / subjectWeight) + 0.4 * median
        }
        edit.exposure = log2(0.42 / max(0.03, metered)).clamped(to: -1...1)

        // Levels: stretch toward healthy black/white points.
        edit.blacks = ((0.03 - p005) * 320).clamped(to: -35...25)
        edit.whites = ((0.95 - p995) * 240).clamped(to: -25...35)

        // Recover blown highlights / lift crushed shadows.
        edit.highlights = (-(highlightClipped / total) * 1400).clamped(to: -60...0)
        edit.shadows = ((shadowCrushed / total) * 900).clamped(to: 0...40)

        // Gentle contrast when the histogram is narrow.
        edit.contrast = ((0.82 - (p995 - p005)) * 80).clamped(to: 0...22)

        // Gray-world white balance from the neutral pool, conservatively —
        // and only when enough of the frame is actually neutral.
        if wbCount > total * 0.12 {
            let meanR = sumR / wbCount, meanG = sumG / wbCount, meanB = sumB / wbCount
            edit.temp = (((meanB - meanR) / meanG) * 300).clamped(to: -30...30)
            // Excess R+B over G is a magenta cast; positive tint pushes magenta, so cancel with negative.
            edit.tint = (((meanG - (meanR + meanB) / 2) / meanG) * 160).clamped(to: -10...10)
        }
        if saturationCount > 0 {
            let meanSaturation = saturationSum / saturationCount
            edit.vibrance = ((0.26 - meanSaturation) * 70).clamped(to: 0...15)
        }
        return edit
    }
}
