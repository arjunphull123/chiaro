import CoreImage

struct HistogramData: Equatable {
    var red: [Float] = []
    var green: [Float] = []
    var blue: [Float] = []
    var isEmpty: Bool { red.isEmpty }
}

enum HistogramSampler {
    static let bins = 64

    static func sample(_ image: CIImage) -> HistogramData {
        let histogram = image.applyingFilter("CIAreaHistogram", parameters: [
            kCIInputExtentKey: CIVector(cgRect: image.extent),
            "inputCount": bins,
            "inputScale": 1.0,
        ])
        var floats = [Float](repeating: 0, count: bins * 4)
        RawEngine.shared.context.render(
            histogram, toBitmap: &floats, rowBytes: bins * 16,
            bounds: CGRect(x: 0, y: 0, width: bins, height: 1),
            format: .RGBAf, colorSpace: nil
        )
        var data = HistogramData()
        data.red = (0..<bins).map { floats[$0 * 4] }
        data.green = (0..<bins).map { floats[$0 * 4 + 1] }
        data.blue = (0..<bins).map { floats[$0 * 4 + 2] }
        // Normalize against a high percentile so one spike doesn't flatten the rest.
        let all = (data.red + data.green + data.blue).sorted()
        let cap = max(all[Int(Double(all.count - 1) * 0.98)], .leastNonzeroMagnitude)
        for path in [\HistogramData.red, \.green, \.blue] {
            data[keyPath: path] = data[keyPath: path].map { min(1, $0 / cap) }
        }
        return data
    }
}
