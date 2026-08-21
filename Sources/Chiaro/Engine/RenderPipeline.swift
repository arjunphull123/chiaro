import CoreImage
import CoreImage.CIFilterBuiltins

/// Pure function (base image, edit, optional person mask) -> adjusted image.
/// Order is fixed by SPEC.md; every node reads only EditState values.
enum RenderPipeline {
    static func render(base: CIImage, edit: EditState, personMask: CIImage?, depthMap: CIImage? = nil, isRAW: Bool, skipCrop: Bool = false, focusPeaking: Bool = false, clippingWarnings: Bool = false) -> CIImage {
        var image = applyGeometry(base, edit: edit, skipCrop: skipCrop)
        // Masks are aligned to the un-transformed base, so they get the same
        // geometry before use.
        let personMask = personMask.map { applyGeometry($0, edit: edit, skipCrop: skipCrop) }
        let depthMap = depthMap.map { applyGeometry($0, edit: edit, skipCrop: skipCrop) }
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
        if edit.curve != CurvePoint.identity {
            image = userCurve(image, points: edit.curve)
        }
        // Monochrome (ADR 0015): grey first, using the mixer's l values as
        // channel weights, then the rest of the color stage is moot — global
        // saturation/vibrance/the hue cube would only re-desaturate a grey image.
        if edit.monochrome {
            image = HSLCube.applyMonochrome(image, bands: edit.hsl)
        }
        if edit.contrast != 0 || (edit.saturation != 0 && !edit.monochrome) {
            let f = CIFilter.colorControls()
            f.inputImage = image
            f.contrast = Float(1 + edit.contrast / 100 * 0.35)
            f.saturation = edit.monochrome ? 1 : Float(1 + edit.saturation / 100)
            image = f.outputImage ?? image
        }
        if edit.vibrance != 0 && !edit.monochrome {
            let f = CIFilter.vibrance()
            f.inputImage = image
            f.amount = Float(edit.vibrance / 100)
            image = f.outputImage ?? image
        }
        if !edit.monochrome && edit.hsl.contains(where: { !$0.isNeutral }) {
            image = HSLCube.apply(image, bands: edit.hsl)
        }
        // Grading (ADR 0015): after the mixer, before localisation — correction,
        // then grading, then locals.
        image = ColorGradeKernel.apply(image, edit: edit)
        for local in edit.locals where !local.isNeutral {
            image = applyLocal(local, to: image, personMask: personMask, scale: scale)
        }
        if edit.clarity != 0 {
            let f = CIFilter.unsharpMask()
            f.inputImage = image
            f.radius = Float(25 * scale)
            f.intensity = Float(edit.clarity / 100 * 0.5)
            image = f.outputImage ?? image
        }
        // RAW files route sharpness/noiseReduction to decode time instead
        // (RawEngine.DecodeParams, baked into `base` before this function ever
        // runs) — applying these post-demosaic too would double them up.
        if edit.noiseReduction > 0 && !isRAW {
            let f = CIFilter.noiseReduction()
            f.inputImage = image
            f.noiseLevel = Float(edit.noiseReduction / 100 * 0.06)
            f.sharpness = 0.4
            image = f.outputImage ?? image
        }
        if edit.sharpness > 0 && !isRAW {
            let f = CIFilter.sharpenLuminance()
            f.inputImage = image
            f.sharpness = Float(edit.sharpness / 100 * 1.2)
            f.radius = Float(1.7 * scale)
            image = f.outputImage ?? image
        }
        if edit.blurF > 0 || edit.relight != 0 {
            image = portrait(image, edit: edit, personMask: personMask, depthMap: depthMap, scale: scale)
        }
        if edit.vignette > 0 {
            let f = CIFilter.vignette()
            f.inputImage = image
            f.intensity = Float(edit.vignette / 100 * 1.6)
            f.radius = Float(1.6)
            image = f.outputImage ?? image
        }
        // Focus peaking (preview only, never export): amber wash over the
        // in-focus plane while the Focus control is armed.
        if focusPeaking, edit.blurMode == .depth, let depthMap {
            // Peaking shows the sharp zone: everything nearer than the
            // plane, with a small soft shoulder.
            let farEdge = 1 - edit.focusDepth - 0.04
            let inFocus = depthMap.cropped(to: image.extent)
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 12, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 12, y: 0, z: 0, w: 0),
                    "inputBVector": CIVector(x: 12, y: 0, z: 0, w: 0),
                    "inputBiasVector": CIVector(x: -farEdge * 12, y: -farEdge * 12, z: -farEdge * 12, w: 0),
                ])
                .applyingFilter("CIColorClamp")
            let amber = CIImage(color: CIColor(red: 0.91, green: 0.64, blue: 0.24, alpha: 0.45))
                .cropped(to: image.extent)
                .composited(over: image)
            let blend = CIFilter.blendWithMask()
            blend.inputImage = amber
            blend.backgroundImage = image
            blend.maskImage = inFocus
            image = blend.outputImage ?? image
        }
        // Blinkies (preview only): red where any channel blows past ~250,
        // blue where all channels crush under ~5 — the Lightroom convention.
        if clippingWarnings {
            let maxComponent = image.applyingFilter("CIMaximumComponent")
            let highlight = maxComponent.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 60, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 60, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 60, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: -58.8, y: -58.8, z: -58.8, w: 0), // 0.98 * 60
            ]).applyingFilter("CIColorClamp")
            let minComponent = image
                .applyingFilter("CIColorInvert")
                .applyingFilter("CIMaximumComponent")
                .applyingFilter("CIColorInvert")
            let shadow = minComponent.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: -60, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: -60, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: -60, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 1.2, y: 1.2, z: 1.2, w: 0), // 0.02 * 60
            ]).applyingFilter("CIColorClamp")
            let red = CIImage(color: CIColor(red: 1, green: 0.1, blue: 0.1)).cropped(to: image.extent)
            let blue = CIImage(color: CIColor(red: 0.15, green: 0.3, blue: 1)).cropped(to: image.extent)
            var warned = CIFilter(name: "CIBlendWithMask", parameters: [
                kCIInputImageKey: red,
                kCIInputBackgroundImageKey: image,
                kCIInputMaskImageKey: highlight.cropped(to: image.extent),
            ])?.outputImage ?? image
            warned = CIFilter(name: "CIBlendWithMask", parameters: [
                kCIInputImageKey: blue,
                kCIInputBackgroundImageKey: warned,
                kCIInputMaskImageKey: shadow.cropped(to: image.extent),
            ])?.outputImage ?? warned
            image = warned.cropped(to: image.extent)
        }
        return image
    }

    // MARK: - Geometry (straighten + crop, first stage)

    /// Straighten rotates about the center and auto-insets to the largest
    /// same-aspect rectangle (no empty corners); crop is normalized within that
    /// frame, y measured from the top. `skipCrop` keeps the full straightened
    /// frame visible for the crop-mode canvas.
    static func applyGeometry(_ image: CIImage, edit: EditState, skipCrop: Bool = false) -> CIImage {
        var result = image
        // Orientation first — lossless 90° steps and mirrors.
        if edit.flipH { result = result.oriented(.upMirrored) }
        if edit.flipV { result = result.oriented(.downMirrored) }
        for _ in 0..<(((edit.rotation % 360) + 360) % 360 / 90) {
            result = result.oriented(.right)
        }
        if edit.skewV != 0 || edit.skewH != 0 {
            let e = result.extent
            let dv = CGFloat(edit.skewV / 100) * e.width * 0.3
            let dh = CGFloat(edit.skewH / 100) * e.height * 0.3
            let f = CIFilter.perspectiveTransform()
            f.inputImage = result
            f.topLeft = CGPoint(x: e.minX - dv, y: e.maxY + dh)
            f.topRight = CGPoint(x: e.maxX + dv, y: e.maxY - dh)
            f.bottomLeft = CGPoint(x: e.minX + dv, y: e.minY + dh)
            f.bottomRight = CGPoint(x: e.maxX - dv, y: e.minY - dh)
            if let skewed = f.outputImage {
                result = skewed.cropped(to: e.insetBy(dx: abs(dv), dy: abs(dh)))
            }
        }
        if edit.straighten != 0 {
            let extent = result.extent
            let radians = -edit.straighten * .pi / 180
            let center = CGPoint(x: extent.midX, y: extent.midY)
            let transform = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: radians)
                .translatedBy(x: -center.x, y: -center.y)
            result = result.transformed(by: transform)
            let inset = Self.largestInscribed(size: extent.size, angle: abs(radians))
            result = result.cropped(to: CGRect(
                x: result.extent.midX - inset.width / 2,
                y: result.extent.midY - inset.height / 2,
                width: inset.width, height: inset.height
            ))
        }
        if edit.crop != .full && !skipCrop {
            let e = result.extent
            let rect = CGRect(
                x: e.origin.x + edit.crop.x * e.width,
                y: e.origin.y + (1 - edit.crop.y - edit.crop.h) * e.height,
                width: edit.crop.w * e.width,
                height: edit.crop.h * e.height
            )
            result = result.cropped(to: rect.intersection(e))
        }
        // Zero the origin so downstream extent math stays simple.
        return result.transformed(by: .init(
            translationX: -result.extent.origin.x, y: -result.extent.origin.y
        ))
    }

    /// Largest same-aspect axis-aligned rectangle inside a rotated rectangle.
    private static func largestInscribed(size: CGSize, angle: Double) -> CGSize {
        let w = Double(size.width), h = Double(size.height)
        let sinA = abs(sin(angle)), cosA = abs(cos(angle))
        let scale = min(w / (w * cosA + h * sinA), h / (w * sinA + h * cosA))
        return CGSize(width: w * scale, height: h * scale)
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

    /// User tone curve: monotone spline sampled into a 256-entry LUT for CIColorCurves.
    private static func userCurve(_ image: CIImage, points: [CurvePoint]) -> CIImage {
        let samples = CurveSampler.sample(points, count: 256)
        var floats = [Float]()
        floats.reserveCapacity(256 * 3)
        for y in samples { floats.append(contentsOf: [y, y, y]) }
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        return image.applyingFilter("CIColorCurves", parameters: [
            "inputCurvesData": data,
            "inputCurvesDomain": CIVector(x: 0, y: 1),
            "inputColorSpace": CGColorSpace(name: CGColorSpace.displayP3)!,
        ])
    }

    /// One masked correction: build the mask, apply the local's adjustments
    /// to a copy, blend through the mask.
    private static func applyLocal(_ local: LocalAdjustment, to image: CIImage, personMask: CIImage?, scale: CGFloat) -> CIImage {
        guard var mask = localMask(local, extent: image.extent, personMask: personMask) else { return image }
        if local.invert {
            mask = mask.applyingFilter("CIColorInvert").cropped(to: image.extent)
        }
        var adjusted = image
        if local.temp != 0 || local.tint != 0 {
            let f = CIFilter.temperatureAndTint()
            f.inputImage = adjusted
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: 6500 + local.temp * 28, y: local.tint * 0.9)
            adjusted = f.outputImage ?? adjusted
        }
        if local.exposure != 0 {
            adjusted = adjusted.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: local.exposure])
        }
        if local.highlights != 0 || local.shadows != 0 {
            let f = CIFilter.highlightShadowAdjust()
            f.inputImage = adjusted
            f.highlightAmount = Float(1 + min(0, local.highlights) / 100 * 0.7)
            f.shadowAmount = Float(local.shadows / 100)
            f.radius = Float(3 * scale)
            adjusted = f.outputImage ?? adjusted
        }
        if local.contrast != 0 || local.saturation != 0 {
            let f = CIFilter.colorControls()
            f.inputImage = adjusted
            f.contrast = Float(1 + local.contrast / 100 * 0.35)
            f.saturation = Float(1 + local.saturation / 100)
            adjusted = f.outputImage ?? adjusted
        }
        if local.clarity != 0 {
            let f = CIFilter.unsharpMask()
            f.inputImage = adjusted
            f.radius = Float(25 * scale)
            f.intensity = Float(local.clarity / 100 * 0.5)
            adjusted = f.outputImage ?? adjusted
        }
        let blend = CIFilter.blendWithMask()
        blend.inputImage = adjusted
        blend.backgroundImage = image
        blend.maskImage = mask
        return blend.outputImage?.cropped(to: image.extent) ?? image
    }

    private static func localMask(_ local: LocalAdjustment, extent: CGRect, personMask: CIImage?) -> CIImage? {
        switch local.kind {
        case .subject:
            return personMask?.cropped(to: extent)
        case .radial:
            // Unit-circle radial gradient, scaled into the ellipse.
            let feather = max(0.02, local.feather / 100)
            let gradient = CIFilter.radialGradient()
            gradient.center = .zero
            gradient.radius0 = Float(1 - feather)
            gradient.radius1 = 1
            gradient.color0 = CIColor.white
            gradient.color1 = CIColor.black
            let rx = max(0.01, local.bx) * extent.width
            let ry = max(0.01, local.by) * extent.height
            return gradient.outputImage?
                .transformed(by: CGAffineTransform(scaleX: rx, y: ry)
                    .translatedBy(
                        x: (local.ax * extent.width + extent.origin.x) / rx,
                        y: ((1 - local.ay) * extent.height + extent.origin.y) / ry))
                .cropped(to: extent)
        case .linear:
            let gradient = CIFilter.smoothLinearGradient()
            gradient.point0 = CGPoint(
                x: local.ax * extent.width + extent.origin.x,
                y: (1 - local.ay) * extent.height + extent.origin.y)
            gradient.point1 = CGPoint(
                x: local.bx * extent.width + extent.origin.x,
                y: (1 - local.by) * extent.height + extent.origin.y)
            gradient.color0 = CIColor.white
            gradient.color1 = CIColor.black
            return gradient.outputImage?.cropped(to: extent)
        }
    }

    private static func portrait(_ image: CIImage, edit: EditState, personMask: CIImage?, depthMap: CIImage?, scale: CGFloat) -> CIImage {
        var result = image
        var subjectMask = personMask?.cropped(to: image.extent)
        if edit.maskReach != 0, let mask = subjectMask {
            // Gamma on the confidence mask: + grows the protected subject, − shrinks it.
            subjectMask = mask.applyingFilter("CIGammaAdjust", parameters: [
                "inputPower": pow(2, -edit.maskReach / 60),
            ]).cropped(to: image.extent)
        }
        if edit.blurF > 0 {
            // The blur amount mask: white = full radius. Depth mode grades it by
            // distance from the focus plane; subject mode blurs everything but
            // the person.
            let amountMask: CIImage?
            if edit.blurMode == .depth, let depthMap {
                // One-sided: Focus IS the plane — everything nearer stays
                // sharp, blur ramps beyond it. (Two-sided optics blur noses.)
                let farEdge = 1 - edit.focusDepth
                let gain: CGFloat = 2.4
                amountMask = depthMap.cropped(to: image.extent)
                    .applyingFilter("CIColorMatrix", parameters: [
                        "inputRVector": CIVector(x: -gain, y: 0, z: 0, w: 0),
                        "inputGVector": CIVector(x: -gain, y: 0, z: 0, w: 0),
                        "inputBVector": CIVector(x: -gain, y: 0, z: 0, w: 0),
                        "inputBiasVector": CIVector(
                            x: farEdge * gain, y: farEdge * gain, z: farEdge * gain, w: 0),
                    ])
                    .applyingFilter("CIColorClamp")
            } else {
                amountMask = subjectMask?.applyingFilter("CIColorInvert")
            }
            if let amountMask {
                let blur = CIFilter.maskedVariableBlur()
                // Pre-clamp so edge pixels don't pull in transparent black.
                blur.inputImage = result.clampedToExtent()
                blur.mask = amountMask
                blur.radius = Float(edit.blurF * 34 * scale)
                result = blur.outputImage?.cropped(to: image.extent) ?? result
            }
        }
        if edit.relight != 0, let subjectMask {
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
