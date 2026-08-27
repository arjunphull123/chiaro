import Testing
import Foundation
@testable import Chiaro

@Suite struct EditStateTests {
    @Test func neutralIsNeutral() {
        #expect(EditState.neutral.isNeutral)
        #expect(EditState().isNeutral)
    }

    /// A value guaranteed to differ from the parameter's default, inside its range.
    private func testValue(for p: EditParameter) -> Double {
        let up = (p.defaultValue + 1).clamped(to: p.range)
        return up != p.defaultValue ? up : (p.defaultValue - 1).clamped(to: p.range)
    }

    @Test func eachParameterRoundTrips() {
        for p in EditParameter.allCases {
            var state = EditState()
            let value = testValue(for: p)
            p.set(value, in: &state)
            #expect(p.value(in: state) == value, "\(p.rawValue)")
            #expect(!state.isNeutral, "\(p.rawValue)")
        }
    }

    private func fullyModifiedState() -> EditState {
        var state = EditState()
        for p in EditParameter.allCases {
            p.set(testValue(for: p), in: &state)
        }
        state.curve = [CurvePoint(x: 0, y: 0.1), CurvePoint(x: 0.5, y: 0.6), CurvePoint(x: 1, y: 0.95)]
        state.crop = CropRect(x: 0.1, y: 0.2, w: 0.5, h: 0.6)
        var local = LocalAdjustment(kind: .radial)
        local.exposure = 0.5
        local.ax = 0.3
        state.locals = [local]
        state.hsl[2] = HSLBand(h: 10, s: -20, l: 5)
        state.monochrome = true
        state.rotation = 90
        state.flipH = true
        state.flipV = true
        state.blurMode = .depth
        return state
    }

    @Test func jsonRoundTrip() throws {
        let original = fullyModifiedState()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EditState.self, from: data)
        #expect(decoded == original)
    }

    @Test func tolerantDecodeSubsetOfKeys() throws {
        let json = Data("{\"exposure\": 0.7}".utf8)
        let decoded = try JSONDecoder().decode(EditState.self, from: json)
        #expect(decoded.exposure == 0.7)
        var expected = EditState()
        expected.exposure = 0.7
        #expect(decoded == expected)
    }

    @Test func tolerantDecodeIgnoresUnknownKeys() throws {
        let json = Data("{\"exposure\": 0.5, \"someFutureField\": 123, \"nested\": {\"a\": 1}}".utf8)
        let decoded = try JSONDecoder().decode(EditState.self, from: json)
        #expect(decoded.exposure == 0.5)
    }

    @Test func selectBlurModeSeedsAndDefersToExplicitValue() {
        var state = EditState()
        #expect(state.blurF == 0)
        state.selectBlurMode(.depth)
        #expect(state.blurMode == .depth)
        #expect(state.blurF == EditState.defaultBlurAmount)

        // Switching modes again must not stomp an amount already dialed in.
        state.selectBlurMode(.person)
        #expect(state.blurF == EditState.defaultBlurAmount)

        // An explicit blurF applied after seeding wins.
        EditParameter.blurF.set(0.9, in: &state)
        #expect(state.blurF == 0.9)
    }

    @Test func cropRectRoundTrips() throws {
        let rect = CropRect(x: 0.1, y: 0.2, w: 0.3, h: 0.4)
        let data = try JSONEncoder().encode(rect)
        let decoded = try JSONDecoder().decode(CropRect.self, from: data)
        #expect(decoded == rect)
    }
}
