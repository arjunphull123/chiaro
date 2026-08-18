import CoreImage
import CoreImage.CIFilterBuiltins

/// Pure function (base image, edit, optional person mask) -> adjusted image.
/// Order is fixed by SPEC.md; every node reads only EditState values.
enum RenderPipeline {
    static func render(base: CIImage, edit: EditState, personMask: CIImage?) -> CIImage {
        var image = base
        let scale = max(base.extent.width, base.extent.height) / RawEngine.previewMaxDimension

        if edit.temp != 0 || edit.tint != 0 {
            let f = CIFilter.temperatureAndTint()
            f.inputImage = image
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: 6500 + edit.temp * 28, y: edit.tint * 0.9)
            image = f.outputImage ?? image
        }
        if edit.exposure != 0 {
            let f = CIFilter.exposureAdjust()
            f.inputImage = image
            f.ev = Float(edit.exposure)
            image = f.outputImage ?? image
        }
        if edit.highlights != 0 || edit.shadows != 0 {
            let f = CIFilter.highlightShadowAdjust()
            f.inputImage = image
            f.highlightAmount = Float(1 + min(0, edit.highlights) / 100 * 0.7)
            f.shadowAmount = Float(edit.shadows / 100)
            f.radius = Float(3 * scale)
            image = f.outputImage ?? image
        }
        if edit.whites != 0 || edit.blacks != 0 || edit.highlights > 0 {
            image = toneCurve(image, edit: edit)
        }
        if edit.contrast != 0 || edit.saturation != 0 {
            let f = CIFilter.colorControls()
            f.inputImage = image
            f.contrast = Float(1 + edit.contrast / 100 * 0.35)
            f.saturation = Float(1 + edit.saturation / 100)
            image = f.outputImage ?? image
        }
        if edit.vibrance != 0 {
            let f = CIFilter.vibrance()
            f.inputImage = image
            f.amount = Float(edit.vibrance / 100)
            image = f.outputImage ?? image
        }
        if edit.clarity != 0 {
            let f = CIFilter.unsharpMask()
            f.inputImage = image
            f.radius = Float(25 * scale)
            f.intensity = Float(edit.clarity / 100 * 0.5)
            image = f.outputImage ?? image
        }
        if edit.noiseReduction > 0 {
            let f = CIFilter.noiseReduction()
            f.inputImage = image
            f.noiseLevel = Float(edit.noiseReduction / 100 * 0.06)
            f.sharpness = 0.4
            image = f.outputImage ?? image
        }
        if edit.sharpness > 0 {
            let f = CIFilter.sharpenLuminance()
            f.inputImage = image
            f.sharpness = Float(edit.sharpness / 100 * 1.2)
            f.radius = Float(1.7 * scale)
            image = f.outputImage ?? image
        }
        if let personMask, edit.blurF > 0 || edit.relight != 0 {
            image = portrait(image, edit: edit, mask: personMask, scale: scale)
        }
        if edit.vignette > 0 {
            let f = CIFilter.vignette()
            f.inputImage = image
            f.intensity = Float(edit.vignette / 100 * 1.6)
            f.radius = Float(1.6)
            image = f.outputImage ?? image
        }
        return image.cropped(to: base.extent)
    }

    private static func toneCurve(_ image: CIImage, edit: EditState) -> CIImage {
        let w = edit.whites / 100, b = edit.blacks / 100, h = max(0, edit.highlights) / 100
        var p0 = CGPoint(x: 0, y: 0)
        var p4 = CGPoint(x: 1, y: 1)
        if b > 0 { p0.y = 0.15 * b } else { p0.x = -0.12 * b }
        if w > 0 { p4.x = 1 - 0.12 * w } else { p4.y = 1 + 0.15 * w }
        let f = CIFilter.toneCurve()
        f.inputImage = image
        f.point0 = p0
        f.point1 = CGPoint(x: 0.25, y: 0.25)
        f.point2 = CGPoint(x: 0.5, y: 0.5)
        f.point3 = CGPoint(x: 0.75, y: 0.75 + 0.12 * h)
        f.point4 = p4
        return f.outputImage ?? image
    }

    private static func portrait(_ image: CIImage, edit: EditState, mask: CIImage, scale: CGFloat) -> CIImage {
        var result = image
        let subjectMask = mask.cropped(to: image.extent)
        if edit.blurF > 0 {
            let inverted = subjectMask.applyingFilter("CIColorInvert")
            let blur = CIFilter.maskedVariableBlur()
            // Pre-clamp so edge pixels don't pull in transparent black.
            blur.inputImage = result.clampedToExtent()
            blur.mask = inverted
            blur.radius = Float(edit.blurF * 14 * scale)
            result = blur.outputImage?.cropped(to: image.extent) ?? result
        }
        if edit.relight != 0 {
            let relit = result.applyingFilter("CIExposureAdjust", parameters: [
                kCIInputEVKey: edit.relight / 100 * 1.2,
            ])
            let blend = CIFilter.blendWithMask()
            blend.inputImage = relit
            blend.backgroundImage = result
            blend.maskImage = subjectMask
            result = blend.outputImage ?? result
        }
        return result
    }
}
