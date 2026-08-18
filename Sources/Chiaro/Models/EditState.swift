import Foundation

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

    static let neutral = EditState()
    var isNeutral: Bool { self == .neutral }
}

/// A single adjustable parameter: identity, range, and EditState binding.
enum EditParameter: String, CaseIterable, Identifiable {
    case exposure, contrast, highlights, shadows, whites, blacks
    case temp, tint, vibrance, saturation
    case clarity, vignette
    case sharpness, noiseReduction
    case blurF, relight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .noiseReduction: "Noise"
        case .blurF: "Blur ƒ"
        case .temp: "Temp"
        case .relight: "Relight"
        default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .exposure: -3...3
        case .vignette, .sharpness, .noiseReduction: 0...100
        case .blurF: 0...1
        default: -100...100
        }
    }

    var defaultValue: Double { 0 }

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
        }
    }

    /// Display string for the current value (Geist Mono in the UI).
    func format(_ v: Double) -> String {
        switch self {
        case .exposure: String(format: "%+.2f", v)
        case .blurF:
            v <= 0.001 ? "off" : {
                let f = 16.0 * pow(1.4 / 16.0, v)
                return f < 10 ? String(format: "ƒ%.1f", f) : String(format: "ƒ%.0f", f)
            }()
        case .vignette, .sharpness, .noiseReduction: String(format: "%.0f", v)
        default: String(format: "%+.0f", v)
        }
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
