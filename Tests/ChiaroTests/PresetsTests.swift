import Testing
@testable import Chiaro

@Suite @MainActor struct PresetsTests {
    private var builtIn: [Preset] { PresetStore.shared.builtIn }

    @Test func builtInPresetsIncludeExpectedNames() {
        let names = Set(builtIn.map(\.name))
        let expected: Set<String> = [
            "Punch", "Soft film", "Silver", "Golden hour", "Cool morning", "Portrait glow",
        ]
        #expect(names == expected)
    }

    @Test func applyingEachBuiltInMakesNeutralNonNeutral() {
        for preset in builtIn {
            let applied = preset.applied(to: .neutral)
            #expect(!applied.isNeutral, "\(preset.name)")
        }
    }

    /// `applied(to:)` assigns the preset's carried values onto the target
    /// rather than composing — reapplying is a no-op.
    @Test func applyingTwiceIsIdempotent() {
        for preset in builtIn {
            let once = preset.applied(to: .neutral)
            let twice = preset.applied(to: once)
            #expect(twice == once, "\(preset.name)")
        }
    }

    @Test func appliedPresetGeometryIsUntouched() {
        var edit = EditState.neutral
        edit.rotation = 90
        edit.crop = CropRect(x: 0.1, y: 0.1, w: 0.5, h: 0.5)
        for preset in builtIn {
            let applied = preset.applied(to: edit)
            #expect(applied.rotation == 90, "\(preset.name)")
            #expect(applied.crop == edit.crop, "\(preset.name)")
        }
    }
}
