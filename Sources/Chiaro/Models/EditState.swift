import Foundation

/// One control point on the tone curve, both axes 0…1.
struct CurvePoint: Codable, Equatable, Hashable {
    var x: Double
    var y: Double
    static let identity = [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)]
}

/// Normalized crop rectangle (0…1 in post-straighten image space).
struct CropRect: Codable, Equatable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
    static let full = CropRect(x: 0, y: 0, w: 1, h: 1)
}

/// How portrait blur decides what stays sharp.
enum BlurMode: String, Codable {
    case subject   // foreground instance lift — any salient subject
    case person    // person segmentation only
    case depth     // Depth Anything focus plane
}

/// One band of the color mixer: hue shift, saturation, luminance, each
/// -100…100, applied to pixels whose hue falls in the band.
struct HSLBand: Codable, Equatable {
    var h: Double = 0
    var s: Double = 0
    var l: Double = 0
    var isNeutral: Bool { h == 0 && s == 0 && l == 0 }

    static let names = ["red", "orange", "yellow", "green", "aqua", "blue", "purple", "magenta"]
    /// Band centers in hue degrees.
    static let centers: [Double] = [0, 30, 60, 120, 180, 240, 285, 330]
}

/// One local adjustment: a mask (radial ellipse, linear gradient, or the
/// detected subject) carrying its own tonal corrections. Coordinates are
/// normalized, y from the top. Radial: a = center, b = radii. Linear: the
/// gradient runs a → b (full effect at a, none at b).
struct LocalAdjustment: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case radial, linear, subject }
    var id = UUID()
    var kind: Kind
    var ax: Double = 0.5, ay: Double = 0.5
    var bx: Double = 0.25, by: Double = 0.25
    var feather: Double = 50   // 0…100
    var invert = false
    var exposure = 0.0         // -3…3 EV
    var contrast = 0.0         // -100…100
    var highlights = 0.0
    var shadows = 0.0
    var temp = 0.0
    var tint = 0.0
    var saturation = 0.0
    var clarity = 0.0

    var isNeutral: Bool {
        exposure == 0 && contrast == 0 && highlights == 0 && shadows == 0
            && temp == 0 && tint == 0 && saturation == 0 && clarity == 0
    }

    // id is UI state, not edit data — regenerated per session. Decoding is
    // tolerant: only `kind` is required, everything else keeps its default.
    enum CodingKeys: String, CodingKey {
        case kind, ax, ay, bx, by, feather, invert
        case exposure, contrast, highlights, shadows, temp, tint, saturation, clarity
    }

    init(kind: Kind) {
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        ax = try c.decodeIfPresent(Double.self, forKey: .ax) ?? ax
        ay = try c.decodeIfPresent(Double.self, forKey: .ay) ?? ay
        bx = try c.decodeIfPresent(Double.self, forKey: .bx) ?? bx
        by = try c.decodeIfPresent(Double.self, forKey: .by) ?? by
        feather = try c.decodeIfPresent(Double.self, forKey: .feather) ?? feather
        invert = try c.decodeIfPresent(Bool.self, forKey: .invert) ?? invert
        exposure = try c.decodeIfPresent(Double.self, forKey: .exposure) ?? 0
        contrast = try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 0
        highlights = try c.decodeIfPresent(Double.self, forKey: .highlights) ?? 0
        shadows = try c.decodeIfPresent(Double.self, forKey: .shadows) ?? 0
        temp = try c.decodeIfPresent(Double.self, forKey: .temp) ?? 0
        tint = try c.decodeIfPresent(Double.self, forKey: .tint) ?? 0
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 0
        clarity = try c.decodeIfPresent(Double.self, forKey: .clarity) ?? 0
    }
}

/// The complete, serializable description of one photo's edit (ADR 0003).
/// Every UI input path mutates this; the render pipeline is a pure function of it.
struct EditState: Codable, Equatable {
    // Light
    var exposure: Double = 0      // -3...3 EV
    var contrast: Double = 0      // -100...100
    var highlights: Double = 0    // -100...100
    var shadows: Double = 0       // -100...100
    var whites: Double = 0        // -100...100
    var blacks: Double = 0        // -100...100
    // Color
    var temp: Double = 0          // -100...100
    var tint: Double = 0          // -100...100
    var vibrance: Double = 0      // -100...100
    var saturation: Double = 0    // -100...100
    // Effects
    var clarity: Double = 0       // -100...100
    var vignette: Double = 0      // 0...100
    // Detail
    var sharpness: Double = 0     // 0...100
    var noiseReduction: Double = 0 // 0...100
    // Portrait
    var blurF: Double = 0         // 0...1 (0 = off/f16, 1 = f1.4)
    var relight: Double = 0       // -100...100
    var maskReach: Double = 0     // -100...100: grow (+) or shrink (−) the subject mask
    var blurMode: BlurMode = .subject
    var focusDepth: Double = 0.5  // 0 = nearest, 1 = farthest — the plane kept sharp
    var focusRange: Double = 0.25 // width of the sharp zone around the focus plane
    // Local adjustments: masked corrections, applied after global ones
    var locals: [LocalAdjustment] = []
    // Color mixer: 8 hue bands (see HSLBand.names)
    var hsl: [HSLBand] = Array(repeating: HSLBand(), count: 8)
    // Tone curve: control points, always including endpoints
    var curve: [CurvePoint] = CurvePoint.identity
    // Geometry
    var rotation: Int = 0         // 0/90/180/270, clockwise, applied first
    var flipH = false
    var flipV = false
    var straighten: Double = 0    // -45...45 degrees
    var crop: CropRect = .full    // normalized, applied after straighten

    static let neutral = EditState()
    var isNeutral: Bool { self == .neutral }

    // Tolerant decoding: parameters added in later versions default to neutral,
    // so old sidecars keep working as the schema grows (ADR 0002).
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        for p in EditParameter.allCases {
            if let v = try c.decodeIfPresent(Double.self, forKey: CodingKeys(stringValue: p.rawValue)!) {
                p.set(v, in: &self)
            }
        }
        if let pts = try c.decodeIfPresent([CurvePoint].self, forKey: CodingKeys(stringValue: "curve")!),
           pts.count >= 2 {
            curve = pts.sorted { $0.x < $1.x }
        }
        if let rect = try c.decodeIfPresent(CropRect.self, forKey: CodingKeys(stringValue: "crop")!) {
            crop = rect
        }
        if let degrees = try c.decodeIfPresent(Int.self, forKey: CodingKeys(stringValue: "rotation")!) {
            rotation = ((degrees % 360) + 360) % 360 / 90 * 90
        }
        flipH = try c.decodeIfPresent(Bool.self, forKey: CodingKeys(stringValue: "flipH")!) ?? false
        flipV = try c.decodeIfPresent(Bool.self, forKey: CodingKeys(stringValue: "flipV")!) ?? false
        if let raw = try c.decodeIfPresent(String.self, forKey: CodingKeys(stringValue: "blurMode")!),
           let mode = BlurMode(rawValue: raw) {
            blurMode = mode
        } else if try c.decodeIfPresent(Bool.self, forKey: CodingKeys(stringValue: "depthBlur")!) == true {
            blurMode = .depth // pre-BlurMode sidecars
        }
    }

    struct CodingKeys: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        for p in EditParameter.allCases where p.value(in: self) != p.defaultValue {
            try c.encode(p.value(in: self), forKey: CodingKeys(stringValue: p.rawValue)!)
        }
        if curve != CurvePoint.identity {
            try c.encode(curve, forKey: CodingKeys(stringValue: "curve")!)
        }
        if crop != .full {
            try c.encode(crop, forKey: CodingKeys(stringValue: "crop")!)
        }
        if !locals.isEmpty {
            try c.encode(locals, forKey: CodingKeys(stringValue: "locals")!)
        }
        if hsl.contains(where: { !$0.isNeutral }) {
            try c.encode(hsl, forKey: CodingKeys(stringValue: "hsl")!)
        }
        if rotation != 0 {
            try c.encode(rotation, forKey: CodingKeys(stringValue: "rotation")!)
        }
        if flipH { try c.encode(true, forKey: CodingKeys(stringValue: "flipH")!) }
        if flipV { try c.encode(true, forKey: CodingKeys(stringValue: "flipV")!) }
        if blurMode != .subject {
            try c.encode(blurMode.rawValue, forKey: CodingKeys(stringValue: "blurMode")!)
        }
    }
}

/// A single adjustable parameter: identity, range, and EditState binding.
enum EditParameter: String, CaseIterable, Identifiable {
    case exposure, contrast, highlights, shadows, whites, blacks
    case temp, tint, vibrance, saturation
    case clarity, vignette
    case sharpness, noiseReduction
    case blurF, relight, maskReach, focusDepth, focusRange
    case straighten

    var id: String { rawValue }

    var label: String {
        switch self {
        case .noiseReduction: "Noise"
        case .blurF: "Blur ƒ"
        case .temp: "Temp"
        case .relight: "Relight"
        case .maskReach: "Mask"
        case .focusDepth: "Focus"
        case .focusRange: "Range"
        case .straighten: "Straighten"
        default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .exposure: -3...3
        case .straighten: -45...45
        case .vignette, .sharpness, .noiseReduction: 0...100
        case .blurF, .focusDepth, .focusRange: 0...1
        default: -100...100
        }
    }

    var defaultValue: Double {
        switch self {
        case .focusDepth: 0.5
        case .focusRange: 0.25
        default: 0
        }
    }

    /// Detent positions for haptic feedback while scrubbing (ADR 0005).
    var detents: [Double] {
        switch self {
        case .blurF:
            // whole f-stops f/16 -> f/1.4
            [16.0, 11, 8, 5.6, 4, 2.8, 2, 1.4].map { f in
                log(16.0 / f) / log(16.0 / 1.4)
            }
        case .exposure: [-2, -1, 0, 1, 2]
        case .vignette, .sharpness, .noiseReduction: []
        case .focusDepth: [0.5]
        case .focusRange: [0.25]
        default: [0]
        }
    }

    func value(in edit: EditState) -> Double {
        edit[keyPath: keyPath]
    }

    func set(_ value: Double, in edit: inout EditState) {
        edit[keyPath: keyPath] = value.clamped(to: range)
    }

    var keyPath: WritableKeyPath<EditState, Double> {
        switch self {
        case .exposure: \.exposure
        case .contrast: \.contrast
        case .highlights: \.highlights
        case .shadows: \.shadows
        case .whites: \.whites
        case .blacks: \.blacks
        case .temp: \.temp
        case .tint: \.tint
        case .vibrance: \.vibrance
        case .saturation: \.saturation
        case .clarity: \.clarity
        case .vignette: \.vignette
        case .sharpness: \.sharpness
        case .noiseReduction: \.noiseReduction
        case .blurF: \.blurF
        case .relight: \.relight
        case .maskReach: \.maskReach
        case .focusDepth: \.focusDepth
        case .focusRange: \.focusRange
        case .straighten: \.straighten
        }
    }

    /// Display string for the current value (Geist Mono in the UI).
    func format(_ v: Double) -> String {
        switch self {
        case .exposure: v == 0 ? "0.00" : String(format: "%+.2f", v)
        case .blurF:
            v <= 0.001 ? "off" : {
                let f = 16.0 * pow(1.4 / 16.0, v)
                return f < 10 ? String(format: "ƒ%.1f", f) : String(format: "ƒ%.0f", f)
            }()
        case .vignette, .sharpness, .noiseReduction: String(format: "%.0f", v)
        case .focusDepth: v <= 0.02 ? "near" : v >= 0.98 ? "far" : String(format: "%.0f%%", v * 100)
        case .focusRange: String(format: "%.0f%%", v * 100)
        case .straighten: String(format: "%.1f°", v)
        default: v == 0 ? "0" : String(format: "%+.0f", v)
        }
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
