import CoreImage
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case jpeg = "JPEG"
    case heif = "HEIF"
    case tiff16 = "TIFF 16-bit"
    var id: String { rawValue }
    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .heif: "heic"
        case .tiff16: "tiff"
        }
    }
    var hasQuality: Bool { self != .tiff16 }
}

struct ExportOptions {
    var format: ExportFormat = .jpeg
    var quality: Double = 0.92
    var destination: URL?
}

enum Exporter {
    /// Full-resolution render through the same pipeline as the preview (SPEC.md).
    static func export(_ photo: Photo, options: ExportOptions) throws -> URL {
        let engine = RawEngine.shared
        guard let full = engine.fullImage(for: photo.url) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let edit = photo.edit
        var mask: CIImage?
        if edit.blurF > 0 || edit.relight != 0 {
            mask = PortraitEngine.shared.mask(for: photo.url, image: full)
        }
        let rendered = RenderPipeline.render(base: full, edit: edit, personMask: mask)

        let folder = options.destination
            ?? photo.url.deletingLastPathComponent().appendingPathComponent("Chiaro Exports")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let out = folder.appendingPathComponent(photo.name).appendingPathExtension(options.format.fileExtension)

        let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
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
        case .tiff16:
            try context.writeTIFFRepresentation(
                of: rendered, to: out, format: .RGBA16, colorSpace: colorSpace, options: [:]
            )
        }
        return out
    }
}
