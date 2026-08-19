import Foundation
import Observation

/// Live view of the MCP connection: the transport is stateless HTTP, so
/// "connected" means a request arrived recently (ADR 0008).
@Observable @MainActor
final class AgentStatus {
    static let shared = AgentStatus()
    var clientName: String?
    var lastSeen: Date?

    /// HTTP transport is stateless — "connected" means requests arrived recently.
    /// Window is generous because agents legitimately go quiet while thinking.
    func isConnected(now: Date = Date()) -> Bool {
        guard let lastSeen else { return false }
        return now.timeIntervalSince(lastSeen) < 600
    }

    func lastSeenText(now: Date = Date()) -> String? {
        guard let lastSeen else { return nil }
        let minutes = Int(now.timeIntervalSince(lastSeen) / 60)
        return minutes < 1 ? "active now" : "\(minutes)m ago"
    }
}
