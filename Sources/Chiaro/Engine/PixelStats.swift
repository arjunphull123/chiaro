import CoreImage

/// Shared primitives for AutoEnhance's metering pass and StatsSampler's
/// get_stats diagnostics: the same bitmap readback, the same luma weights,
/// the same saturation formula. Resolution, color space, and clip/gray-world
/// selection criteria stay caller-specific — those differences are load-bearing
/// (see comments at each call site), not duplication.
enum PixelStats {
    static func readRGBA(_ image: CIImage, width: Int, height: Int, colorSpace: CGColorSpace?) -> [UInt8] {
        let extent = image.extent
        var rendered = image.transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
        if width != Int(extent.width.rounded()) || height != Int(extent.height.rounded()) {
            rendered = rendered.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / extent.width, y: CGFloat(height) / extent.height))
        }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        RawEngine.shared.context.render(
            rendered, toBitmap: &bytes, rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8, colorSpace: colorSpace
        )
        return bytes
    }

    static func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    static func saturation(hi: Double, lo: Double) -> Double {
        hi > 0 ? (hi - lo) / hi : 0
    }
}
