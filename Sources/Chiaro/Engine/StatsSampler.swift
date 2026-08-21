import CoreImage

/// Decision-oriented photo diagnostics for the MCP get_stats tool. Same bitmap
/// readback AutoEnhance uses to meter a photo (CIContext render to a byte
/// buffer, one pass over pixels), reduced to numbers an agent can check a
/// change against instead of eyeballing a JPEG preview.
enum StatsSampler {
    private static let fineBins = 256
    private static let bucketCount = 32
    // Literal 8-bit rail check — a channel is reported clipped only if it
    // actually hit 0/255 or 255/255, unlike AutoEnhance's looser recovery
    // gate. This is a diagnostic readout an agent trusts to mean what it says.
    private static let floorThreshold = 1.0 / 255.0
    private static let ceilingThreshold = 254.0 / 255.0

    static func sample(_ image: CIImage) -> [String: Any] {
        let extent = image.extent
        let w = max(1, Int(extent.width.rounded())), h = max(1, Int(extent.height.rounded()))
        let bytes = PixelStats.readRGBA(image, width: w, height: h, colorSpace: CGColorSpace(name: CGColorSpace.displayP3))

        var redFloor = 0.0, redCeiling = 0.0
        var greenFloor = 0.0, greenCeiling = 0.0
        var blueFloor = 0.0, blueCeiling = 0.0
        var lumaFloor = 0.0, lumaCeiling = 0.0
        var fineHistogram = [Double](repeating: 0, count: fineBins)
        var lumaSum = 0.0
        var saturationSum = 0.0, saturationCount = 0.0
        var castR = 0.0, castG = 0.0, castB = 0.0, castCount = 0.0
        var grayR = 0.0, grayG = 0.0, grayB = 0.0, grayCount = 0.0
        let total = Double(w * h)

        for i in 0..<(w * h) {
            let o = i * 4
            let r = Double(bytes[o]) / 255, g = Double(bytes[o + 1]) / 255, b = Double(bytes[o + 2]) / 255
            let hi = max(r, g, b), lo = min(r, g, b)
            let luma = PixelStats.luminance(r, g, b)

            if r <= floorThreshold { redFloor += 1 }
            if r >= ceilingThreshold { redCeiling += 1 }
            if g <= floorThreshold { greenFloor += 1 }
            if g >= ceilingThreshold { greenCeiling += 1 }
            if b <= floorThreshold { blueFloor += 1 }
            if b >= ceilingThreshold { blueCeiling += 1 }
            if luma <= floorThreshold { lumaFloor += 1 }
            if luma >= ceilingThreshold { lumaCeiling += 1 }

            fineHistogram[min(fineBins - 1, Int(luma * Double(fineBins)))] += 1
            lumaSum += luma

            // Near-black pixels are excluded: sensor noise there has near-random
            // hue and would drag the mean saturation down without meaning anything.
            let saturation = PixelStats.saturation(hi: hi, lo: lo)
            if luma > 0.02 { saturationSum += saturation; saturationCount += 1 }
            // Gray-world sample, same pool AutoEnhance uses for white balance:
            // low-saturation midtones should be neutral, so their average reveals
            // a cast and its direction. Threshold is 0.30, not tighter: a strong
            // cast pushes formerly-neutral pixels past a tight threshold, leaving
            // only pixels that are low-saturation *because of* the shift — the
            // sample gets more confident exactly as the reading gets more wrong.
            let midLuma = luma > 0.25 && luma < 0.75
            if saturation < 0.30, midLuma {
                castR += r; castG += g; castB += b; castCount += 1
            }
            // Unfiltered companion: same midtone window, no saturation gate, so
            // it can't self-select away under a strong cast. Trade-off is the
            // opposite one: a genuinely saturated scene (red wall, foliage) reads
            // as cast when it isn't.
            if midLuma {
                grayR += r; grayG += g; grayB += b; grayCount += 1
            }
        }

        func percentile(_ p: Double) -> Double {
            let target = p * total
            var cumulative = 0.0
            for i in 0..<fineBins {
                cumulative += fineHistogram[i]
                if cumulative >= target { return (Double(i) + 0.5) / Double(fineBins) }
            }
            return 1
        }
        func pct(_ count: Double) -> Double { ((count / total) * 1000).rounded() / 10 }
        func frac(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }

        let bucketWidth = fineBins / bucketCount
        let histogram = (0..<bucketCount).map { bucket -> Double in
            let sum = fineHistogram[(bucket * bucketWidth)..<((bucket + 1) * bucketWidth)].reduce(0, +)
            return frac(sum / total)
        }

        return [
            "clipping": [
                "red": ["floor": pct(redFloor), "ceiling": pct(redCeiling)],
                "green": ["floor": pct(greenFloor), "ceiling": pct(greenCeiling)],
                "blue": ["floor": pct(blueFloor), "ceiling": pct(blueCeiling)],
                "luminance": ["floor": pct(lumaFloor), "ceiling": pct(lumaCeiling)],
            ],
            "luminance": [
                "p05": frac(percentile(0.05)), "p50": frac(percentile(0.50)),
                "p95": frac(percentile(0.95)), "mean": frac(lumaSum / total),
            ],
            "saturation": ["mean": frac(saturationCount > 0 ? saturationSum / saturationCount : 0)],
            "neutralCast": [
                "r": frac(castCount > 0 ? castR / castCount : 0),
                "g": frac(castCount > 0 ? castG / castCount : 0),
                "b": frac(castCount > 0 ? castB / castCount : 0),
                "pixelCount": Int(castCount),
            ],
            "grayWorld": [
                "r": frac(grayCount > 0 ? grayR / grayCount : 0),
                "g": frac(grayCount > 0 ? grayG / grayCount : 0),
                "b": frac(grayCount > 0 ? grayB / grayCount : 0),
                "pixelCount": Int(grayCount),
            ],
            "histogram": histogram,
        ]
    }
}
