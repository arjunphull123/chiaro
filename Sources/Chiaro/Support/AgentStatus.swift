import Foundation
import Observation

/// Live view of the MCP connection: the transport is stateless HTTP, so
/// "connected" means a request arrived recently (ADR 0008).
@Observable @MainActor
final class AgentStatus {
    static let shared = AgentStatus()
    var clientName: String?
    var lastSeen: Date?

    func isConnected(now: Date = Date()) -> Bool {
        guard let lastSeen else { return false }
        return now.timeIntervalSince(lastSeen) < 180
    }
}
