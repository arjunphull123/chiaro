import Foundation
import Observation

/// Live view of the MCP connection: the transport is stateless HTTP, so
/// "connected" means a request arrived recently (ADR 0008).
@Observable @MainActor
final class AgentStatus {
    static let shared = AgentStatus()
    /// Persisted: agents don't re-initialize when the app restarts mid-session,
    /// so a fresh launch would otherwise show "Agent" instead of "Claude".
    var clientName: String? {
        didSet { UserDefaults.standard.set(clientName, forKey: "lastAgentClient") }
    }
    var lastSeen: Date?

    init() {
        clientName = UserDefaults.standard.string(forKey: "lastAgentClient")
    }

    struct Action: Identifiable {
        let id = UUID()
        let date: Date
        let text: String
    }
    /// Rolling log of what agents have done this session, newest first.
    private(set) var actions: [Action] = []

    func log(_ text: String) {
        actions.insert(Action(date: Date(), text: text), at: 0)
        if actions.count > 50 { actions.removeLast() }
    }

    var brand: AgentBrand { AgentBrand.match(clientName) }
    var displayName: String { brand.name == "Agent" ? (clientName ?? "Agent") : brand.name }

    /// HTTP transport is stateless — "connected" means requests arrived recently.
    /// Window is generous because agents legitimately go quiet while thinking.
    func isConnected(now: Date = Date()) -> Bool {
        guard let lastSeen else { return false }
        return now.timeIntervalSince(lastSeen) < 600
    }
}
