import CoreImage

/// Colour grading by tonal zone (ADR 0015): one custom, Metal-backed
/// CIColorKernel. Shadow/mid/highlight weights are Gaussian bells in
/// luminance, normalized to sum to 1 at every pixel — smooth, so gradients
/// never band, and no zone is ever double counted. Each zone's hue tints in
/// at its own strength, then the pixel's original luminance is restored so
/// grading shifts colour, never exposure.
enum ColorGradeKernel {
    static func apply(_ image: CIImage, edit: EditState) -> CIImage {
        guard edit.shadowStrength != 0 || edit.midStrength != 0 || edit.highlightStrength != 0,
              let kernel else { return image }
        return kernel.apply(extent: image.extent, arguments: [
            image,
            edit.shadowStrength / 100, edit.shadowHue,
            edit.midStrength / 100, edit.midHue,
            edit.highlightStrength / 100, edit.highlightHue,
            edit.gradeBalance / 100,
        ]) ?? image
    }

    private static let kernel = CIColorKernel(source: source)

    private static let source = """
    vec3 hueColor(float h) {
        float hh = mod(h, 1.0) * 6.0;
        float x = 1.0 - abs(mod(hh, 2.0) - 1.0);
        if (hh < 1.0) { return vec3(1.0, x, 0.0); }
        if (hh < 2.0) { return vec3(x, 1.0, 0.0); }
        if (hh < 3.0) { return vec3(0.0, 1.0, x); }
        if (hh < 4.0) { return vec3(0.0, x, 1.0); }
        if (hh < 5.0) { return vec3(x, 0.0, 1.0); }
        return vec3(1.0, 0.0, x);
    }

    kernel vec4 grade(sample s, float shadowAmt, float shadowHue, float midAmt, float midHue, float highlightAmt, float highlightHue, float balance) {
        vec3 c = s.rgb;
        vec3 lumaWeights = vec3(0.2126, 0.7152, 0.0722);
        float L = dot(c, lumaWeights);

        float shift = balance * 0.2;
        float sigma = 0.4;
        float dS = L - shift;
        float dM = L - 0.5;
        float dH = L - 1.0 - shift;
        float wS = exp(-(dS * dS) / (2.0 * sigma * sigma));
        float wM = exp(-(dM * dM) / (2.0 * sigma * sigma));
        float wH = exp(-(dH * dH) / (2.0 * sigma * sigma));
        float wSum = wS + wM + wH;
        wS = wS / wSum;
        wM = wM / wSum;
        wH = wH / wSum;

        float aS = wS * shadowAmt;
        float aM = wM * midAmt;
        float aH = wH * highlightAmt;
        float tintTotal = aS + aM + aH;
        float total = clamp(tintTotal, 0.0, 1.0);

        vec3 tint = c;
        if (tintTotal > 0.0001) {
            tint = (hueColor(shadowHue / 360.0) * aS + hueColor(midHue / 360.0) * aM + hueColor(highlightHue / 360.0) * aH) / tintTotal;
        }

        vec3 blended = mix(c, tint, total);
        float newL = dot(blended, lumaWeights);
        vec3 result = clamp(blended + vec3(L - newL), 0.0, 1.0);
        return vec4(result, s.a);
    }
    """
}
