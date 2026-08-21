import Foundation
import Observation

/// A named starting point: the tonal/color half of an EditState. Geometry,
/// portrait, and blur settings never travel with presets.
struct Preset: Codable, Identifiable, Equatable {
    var name: String
    var edit: EditState
    var id: String { name }

    /// The parameters a preset carries.
    static let carried: [EditParameter] = [
        .exposure, .contrast, .highlights, .shadows, .whites, .blacks,
        .temp, .tint, .vibrance, .saturation,
        .clarity, .vignette, .sharpness, .noiseReduction, .colorNoiseReduction, .moireReduction,
        .grain, .grainSize,
        .shadowStrength, .shadowHue, .midStrength, .midHue,
        .highlightStrength, .highlightHue, .gradeBalance,
    ]

    /// Capture the preset-worthy subset of an edit.
    static func capture(name: String, from edit: EditState) -> Preset {
        var subset = EditState()
        for parameter in carried {
            parameter.set(parameter.value(in: edit), in: &subset)
        }
        subset.curve = edit.curve
        subset.hsl = edit.hsl
        subset.monochrome = edit.monochrome
        return Preset(name: name, edit: subset)
    }

    /// Apply onto an existing edit, leaving geometry/portrait untouched.
    func applied(to edit: EditState) -> EditState {
        var result = edit
        for parameter in Self.carried {
            parameter.set(parameter.value(in: self.edit), in: &result)
        }
        result.curve = self.edit.curve
        result.hsl = self.edit.hsl
        result.monochrome = self.edit.monochrome
        return result
    }

    /// True when the edit currently matches this preset's carried values.
    func matches(_ edit: EditState) -> Bool {
        Self.carried.allSatisfy { $0.value(in: edit) == $0.value(in: self.edit) }
            && edit.curve == self.edit.curve
            && edit.hsl == self.edit.hsl
            && edit.monochrome == self.edit.monochrome
    }
}

@Observable @MainActor
final class PresetStore {
    static let shared = PresetStore()

    let builtIn: [Preset] = [
        .init(name: "Punch", edit: {
            var e = EditState()
            e.contrast = 18; e.vibrance = 25; e.clarity = 12; e.blacks = -8
            return e
        }()),
        .init(name: "Soft film", edit: {
            var e = EditState()
            e.contrast = -10; e.saturation = -12; e.temp = 6
            e.curve = [.init(x: 0, y: 0.06), .init(x: 0.25, y: 0.28),
                       .init(x: 0.75, y: 0.78), .init(x: 1, y: 0.97)]
            return e
        }()),
        .init(name: "Silver", edit: {
            var e = EditState()
            e.monochrome = true
            e.contrast = 15; e.whites = 10; e.blacks = -10; e.clarity = 10
            // Real tonal separation, not a flat grey: darken the sky, lift skin.
            e.hsl[HSLBand.names.firstIndex(of: "blue")!].l = -35
            e.hsl[HSLBand.names.firstIndex(of: "aqua")!].l = -20
            e.hsl[HSLBand.names.firstIndex(of: "orange")!].l = 20
            e.hsl[HSLBand.names.firstIndex(of: "red")!].l = 10
            return e
        }()),
        .init(name: "Golden hour", edit: {
            var e = EditState()
            e.temp = 22; e.tint = 4; e.vibrance = 15; e.highlights = -15; e.vignette = 12
            return e
        }()),
        .init(name: "Cool morning", edit: {
            var e = EditState()
            e.temp = -18; e.tint = -2; e.contrast = 8; e.saturation = -8
            return e
        }()),
        .init(name: "Portrait glow", edit: {
            var e = EditState()
            e.temp = 8; e.highlights = -20; e.shadows = 12; e.clarity = -8
            e.vibrance = 10; e.sharpness = 12
            return e
        }()),
    ]

    private(set) var user: [Preset] = []

    var all: [Preset] { builtIn + user }

    private nonisolated static let folder = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Chiaro/Presets")

    private init() {
        load()
    }

    private func load() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        user = files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Preset.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func save(_ preset: Preset) {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? (try? encoder.encode(preset))?.write(to: url(for: preset.name))
        load()
    }

    func delete(_ preset: Preset) {
        try? FileManager.default.removeItem(at: url(for: preset.name))
        load()
    }

    private func url(for name: String) -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "-")
        return Self.folder.appendingPathComponent("\(safe).json")
    }
}
