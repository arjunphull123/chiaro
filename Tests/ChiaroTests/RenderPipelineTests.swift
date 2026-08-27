import Testing
import CoreImage
@testable import Chiaro

@Suite struct RenderPipelineTests {
    private func greyImage(size: Int = 64) -> CIImage {
        CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
    }

    @Test func renderPreservesExtent() {
        let base = greyImage()
        let out = RenderPipeline.render(base: base, edit: .neutral, personMask: nil, isRAW: false)
        #expect(out.extent == base.extent)
    }

    @Test func raisingExposureRaisesLuminance() {
        let base = greyImage()
        let context = CIContext(options: [.useSoftwareRenderer: true])

        let neutralOut = RenderPipeline.render(base: base, edit: .neutral, personMask: nil, isRAW: false)
        var edit = EditState.neutral
        edit.exposure = 1.5
        let brighterOut = RenderPipeline.render(base: base, edit: edit, personMask: nil, isRAW: false)

        let neutralLuma = averageLuminance(neutralOut, context: context)
        let brighterLuma = averageLuminance(brighterOut, context: context)
        #expect(brighterLuma > neutralLuma)
    }

    private func averageLuminance(_ image: CIImage, context: CIContext) -> Double {
        let extent = image.extent
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image,
            kCIInputExtentKey: CIVector(cgRect: extent),
        ]), let output = filter.outputImage else { return 0 }
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            output, toBitmap: &bitmap, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil
        )
        return (Double(bitmap[0]) + Double(bitmap[1]) + Double(bitmap[2])) / 3.0
    }
}
