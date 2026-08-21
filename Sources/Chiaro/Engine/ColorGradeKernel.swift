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

    /// A nil kernel means the CIKL source failed to compile, which would make
    /// grading a silent no-op forever. Trip loudly in debug instead.
    private static let kernel: CIColorKernel? = {
        let k = CIColorKernel(source: source)
        assert(k != nil, "ColorGradeKernel source failed to compile")
        return k
    }()

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

    /// A hue as a zero-luminance chroma vector: adding it shifts colour without
    /// touching brightness, and without overwriting the pixel's own hue the way
    /// blending toward a full-chroma colour would.
    vec3 chromaOf(float degrees, vec3 lumaWeights) {
        vec3 h = hueColor(degrees / 360.0);
        return h - vec3(dot(h, lumaWeights));
    }

    kernel vec4 grade(__sample s, float shadowAmt, float shadowHue, float midAmt, float midHue, float highlightAmt, float highlightHue, float balance) {
        vec3 c = s.rgb;
        vec3 lumaWeights = vec3(0.2126, 0.7152, 0.0722);
        float L = dot(c, lumaWeights);

        float shift = balance * 0.2;
        // Narrow enough that a shadow grade leaves highlights alone: at 0.4 the
        // bells overlap so far that midtones take a quarter of the shadow tint.
        float sigma = 0.18;
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

        vec3 chroma = chromaOf(shadowHue, lumaWeights) * (wS * shadowAmt)
                    + chromaOf(midHue, lumaWeights) * (wM * midAmt)
                    + chromaOf(highlightHue, lumaWeights) * (wH * highlightAmt);

        // A fixed chroma offset is a large *relative* shift on a dark pixel, so
        // this stays low: at 0.6 a shadow strength of 16 landed like 40.
        vec3 result = clamp(c + chroma * 0.3, 0.0, 1.0);
        return vec4(result, s.a);
    }
    """
}
