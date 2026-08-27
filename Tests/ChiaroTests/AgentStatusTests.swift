import Testing
import Foundation
@testable import Chiaro

// displayName's fallback/capitalization path needs `clientName`, whose setter
// writes UserDefaults.standard — not safe to exercise here, so it's skipped.
@Suite @MainActor struct AgentStatusTests {
    @Test func isActiveReflectsRecency() {
        let status = AgentStatus()
        #expect(!status.isActive())

        let now = Date()
        status.lastSeen = now.addingTimeInterval(-60)
        #expect(status.isActive(now: now))

        status.lastSeen = now.addingTimeInterval(-11 * 60)
        #expect(!status.isActive(now: now))
    }

    @Test func brandMatchKnownClients() {
        #expect(AgentBrand.match("claude-code").name == "Claude")
        #expect(AgentBrand.match("Cursor").name == "Cursor")
        #expect(AgentBrand.match("codex-cli").name == "Codex")
        #expect(AgentBrand.match("gemini").name == "Gemini")
    }

    @Test func brandMatchFallsBackForUnknownOrNil() {
        #expect(AgentBrand.match(nil).name == "Agent")
        #expect(AgentBrand.match("my-agent").name == "Agent")
    }
}
