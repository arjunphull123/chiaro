import Testing
@testable import Chiaro

@Suite struct MCPServerTests {
    @Test func loopbackOriginsAccepted() {
        #expect(MCPServer.isLoopbackOrigin("http://127.0.0.1:5173"))
        #expect(MCPServer.isLoopbackOrigin("http://localhost"))
        #expect(MCPServer.isLoopbackOrigin("http://localhost:3000"))
        #expect(MCPServer.isLoopbackOrigin("http://[::1]:3000"))
        #expect(MCPServer.isLoopbackOrigin("127.0.0.1"))
        #expect(MCPServer.isLoopbackOrigin("localhost"))
    }

    @Test func nonLoopbackOriginsRejected() {
        #expect(!MCPServer.isLoopbackOrigin("https://127.0.0.1.evil.com"))
        #expect(!MCPServer.isLoopbackOrigin("http://evil.com"))
        #expect(!MCPServer.isLoopbackOrigin("http://127.0.0.1.nip.io"))
        #expect(!MCPServer.isLoopbackOrigin("null"))
        #expect(!MCPServer.isLoopbackOrigin(""))
    }

    @Test func toolDefinitionsMatchExpectedNames() {
        let names = Set(MCPServer.toolDefinitions.compactMap { $0["name"] as? String })
        let expected: Set<String> = [
            "list_photos", "get_edit", "set_edit", "set_starred", "list_presets",
            "apply_preset", "open_photo", "get_preview", "get_stats", "export",
        ]
        #expect(names == expected)
        #expect(MCPServer.toolDefinitions.count == expected.count)
    }

    @Test func onboardingPromptMentionsConnectAndListPhotos() {
        let prompt = MCPServer.onboardingPrompt
        #expect(prompt.contains("/mcp"))
        #expect(prompt.contains("list_photos"))
    }
}
