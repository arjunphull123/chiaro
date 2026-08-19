import Foundation

/// A preset is just a saved EditState for the tonal/color parameters (ADR 0003).
/// Applying one preserves the photo's Portrait settings.
struct Preset: Identifiable {
    let name: String
    let edit: EditState
    var id: String { name }

    func applied(over current: EditState) -> EditState {
        var e = edit
        e.blurF = current.blurF
        e.relight = current.relight
        e.maskReach = current.maskReach
        return e
    }

    static let builtIn: [Preset] = [
        Preset(name: "Clean Headshot", edit: {
            var e = EditState()
            e.exposure = 0.15; e.contrast = 8; e.highlights = -25; e.shadows = 18
            e.vibrance = 12; e.clarity = 8; e.sharpness = 22; e.noiseReduction = 10
            return e
        }()),
        Preset(name: "Warm Film", edit: {
            var e = EditState()
            e.temp = 18; e.tint = 4; e.contrast = 6; e.vibrance = 20
            e.blacks = 8; e.vignette = 12
            return e
        }()),
        Preset(name: "Editorial", edit: {
            var e = EditState()
            e.contrast = 18; e.saturation = -14; e.blacks = -18; e.whites = 10
            e.clarity = 16; e.vignette = 14
            return e
        }()),
        Preset(name: "Mono", edit: {
            var e = EditState()
            e.saturation = -100; e.contrast = 16; e.clarity = 12
            e.whites = 8; e.blacks = -10; e.sharpness = 15
            return e
        }()),
        Preset(name: "Golden Hour", edit: {
            var e = EditState()
            e.temp = 32; e.tint = 6; e.exposure = 0.2; e.highlights = -20
            e.vibrance = 22; e.vignette = 14
            return e
        }()),
        Preset(name: "Cool Slate", edit: {
            var e = EditState()
            e.temp = -22; e.contrast = 10; e.saturation = -12
            e.shadows = 10; e.clarity = 6
            return e
        }()),
        Preset(name: "Punch", edit: {
            var e = EditState()
            e.contrast = 26; e.vibrance = 32; e.clarity = 18
            e.whites = 12; e.blacks = -14; e.sharpness = 18
            return e
        }()),
        Preset(name: "Faded Matte", edit: {
            var e = EditState()
            e.blacks = 28; e.contrast = -8; e.saturation = -16
            e.temp = 6; e.vignette = 8
            return e
        }()),
    ]
}
