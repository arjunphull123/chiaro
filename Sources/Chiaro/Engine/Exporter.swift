import CoreImage
import ImageIO
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case jpeg = "JPEG"
    case heif = "HEIF"
    case tiff = "TIFF"
    case original = "Original"
    var id: String { rawValue }
    var hasQuality: Bool { self == .jpeg || self == .heif }
    var blurb: String {
        switch self {
        case .jpeg: "universal — web, LinkedIn, print labs"
        case .heif: "half the size at the same quality"
        case .tiff: "lossless, for print or re-editing"
        case .original: "the untouched RAW file, copied as-is"
        }
    }
    func fileExtension(sourceURL: URL) -> String {
        switch self {
        case .jpeg: "jpg"
        case .heif: "heic"
        case .tiff: "tiff"
        case .original: sourceURL.pathExtension
        }
    }
}

enum ExportColorSpace: String, CaseIterable, Identifiable {
    case srgb = "sRGB"
    case displayP3 = "Display P3"
    case adobeRGB = "Adobe RGB"
    var id: String { rawValue }
    var blurb: String {
        switch self {
        case .srgb: "recommended — safe everywhere"
        case .displayP3: "wide gamut for Apple screens"
        case .adobeRGB: "for print labs that ask for it"
        }
    }
    var cgColorSpace: CGColorSpace {
        switch self {
        case .srgb: CGColorSpace(name: CGColorSpace.sRGB)!
        case .displayP3: CGColorSpace(name: CGColorSpace.displayP3)!
        case .adobeRGB: CGColorSpace(name: CGColorSpace.adobeRGB1998)!
        }
    }
}

struct ExportOptions {
    var format: ExportFormat = .jpeg
    var quality: Double = 0.85
    /// Longest edge in pixels; nil exports at full resolution. Never enlarges.
    var maxDimension: Double?
    var colorSpace: ExportColorSpace = .srgb
    var tiff16Bit = true
    /// Print resolution metadata (PPI) — changes no pixels.
    var ppi: Int = 300
    var stripMetadata = false
    var destination: URL?
}

enum Exporter {
    /// Full-resolution render through the same pipeline as the preview (SPEC.md).
    static func export(_ photo: Photo, options: ExportOptions) throws -> URL {
        let folder = options.destination
            ?? photo.url.deletingLastPathComponent().appendingPathComponent("Chiaro Exports")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let out = folder.appendingPathComponent(photo.name)
            .appendingPathExtension(options.format.fileExtension(sourceURL: photo.url))

        if options.format == .original {
            try? FileManager.default.removeItem(at: out)
            try FileManager.default.copyItem(at: photo.url, to: out)
            return out
        }

        let engine = RawEngine.shared
        guard let full = engine.fullImage(for: photo.url) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let edit = photo.edit
        var mask: CIImage?
        if edit.blurF > 0 || edit.relight != 0 {
            mask = PortraitEngine.shared.mask(for: photo.url, image: full)
        }
        var rendered = RenderPipeline.render(base: full, edit: edit, personMask: mask)
        if let maxDim = options.maxDimension {
            let scale = maxDim / Double(max(rendered.extent.width, rendered.extent.height))
            if scale < 1 {
                rendered = rendered.transformed(by: .init(scaleX: scale, y: scale), highQualityDownsample: true)
            }
        }

        let colorSpace = options.colorSpace.cgColorSpace
        let context = engine.context
        switch options.format {
        case .jpeg:
            try context.writeJPEGRepresentation(
                of: rendered, to: out, colorSpace: colorSpace,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: options.quality]
            )
        case .heif:
            try context.writeHEIFRepresentation(
                of: rendered, to: out, format: .RGBA8, colorSpace: colorSpace,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: options.quality]
            )
        case .tiff:
            try context.writeTIFFRepresentation(
                of: rendered, to: out, format: options.tiff16Bit ? .RGBA16 : .RGBA8,
                colorSpace: colorSpace, options: [:]
            )
        case .original:
            break
        }
        applyMetadataPolicy(to: out, options: options)
        return out
    }

    /// Post-write metadata pass: set print PPI, optionally strip everything else.
    /// Lossless — rewrites the container, never re-encodes pixels.
    private static func applyMetadataPolicy(to url: URL, options: ExportOptions) {
        guard options.ppi != 72 || options.stripMetadata else { return }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source) else { return }
        let temp = url.deletingLastPathComponent().appendingPathComponent(".chiaro-meta.tmp")
        guard let dest = CGImageDestinationCreateWithURL(temp as CFURL, type, 1, nil) else { return }
        var properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: options.ppi,
            kCGImagePropertyDPIHeight: options.ppi,
        ]
        if options.stripMetadata {
            properties[kCGImagePropertyExifDictionary] = kCFNull
            properties[kCGImagePropertyGPSDictionary] = kCFNull
            properties[kCGImagePropertyTIFFDictionary] = kCFNull
            properties[kCGImagePropertyIPTCDictionary] = kCFNull
        }
        CGImageDestinationAddImageFromSource(dest, source, 0, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: temp)
            return
        }
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.moveItem(at: temp, to: url)
    }

    /// Rough output size (bytes) from a bits-per-pixel table — content varies ±30%,
    /// so callers should present it as "~". HEIF runs about half of JPEG.
    static func estimatedBytes(pixels: Double, options: ExportOptions) -> Double {
        let effective: Double
        if let maxDim = options.maxDimension {
            // Assume 3:2; the long-edge cap bounds pixels at maxDim² / 1.5.
            effective = min(pixels, maxDim * maxDim / 1.5)
        } else {
            effective = pixels
        }
        switch options.format {
        case .tiff:
            return effective * (options.tiff16Bit ? 8 : 4)
        case .original:
            return 0 // caller substitutes the real file size
        case .jpeg, .heif:
            let table: [(q: Double, bpp: Double)] = [
                (0.5, 0.7), (0.6, 0.9), (0.7, 1.15), (0.8, 1.6),
                (0.85, 2.1), (0.9, 2.8), (0.95, 4.0), (1.0, 7.0),
            ]
            let q = options.quality.clamped(to: 0.5...1.0)
            var bpp = table.last!.bpp
            for i in 0..<(table.count - 1) where q >= table[i].q && q <= table[i + 1].q {
                let t = (q - table[i].q) / (table[i + 1].q - table[i].q)
                bpp = table[i].bpp + t * (table[i + 1].bpp - table[i].bpp)
            }
            let jpegBytes = effective * bpp / 8
            return options.format == .heif ? jpegBytes * 0.5 : jpegBytes
        }
    }
}
